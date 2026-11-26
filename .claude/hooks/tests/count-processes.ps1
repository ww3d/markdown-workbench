#Requires -Version 7.6
<#
.SYNOPSIS
    Counts the processes of one command's whole process tree on Windows: the command starts suspended inside a job
    object, which counts every process of the tree and names each through its completion port (ww3d/playbook#734,
    decision 8; taken over from the orchestrator helper's measurement 2026-11-25T1338Z).
.DESCRIPTION
    Prints one line of JSON: {"processes":<n>,"programs":["bash.exe",...],"cpuMs":<user + kernel of the tree>,
    "wallMs":<start to the last process gone>,"exitCode":<the command's>}. A program whose process was gone before
    it could be named is "?". The tree is ended after -TimeoutSec, and the line then says "killed": true.
    Dot-sourced (`. count-processes.ps1`), it only loads the type [ProcessTree] for a caller that times many runs.
.PARAMETER Command
    The command line as CreateProcess takes it, e.g. "C:\Program Files\Git\bin\bash.exe" -c "<hook entry>".
.PARAMETER CommandFile
    Instead of -Command: a file of command lines, one per line, each run in turn on the same input, one line of JSON
    each - one PowerShell start for all hooks of a path.
.PARAMETER InputFile
    The file the command reads as stdin (the hook payload); stdout and stderr go to NUL.
.PARAMETER Environment
    NAME=VALUE pairs, one per line, set for the command on top of this process's environment.
.PARAMETER TimeoutSec
    Hang guard for the whole tree (default 30, the hooks' own limit in settings.json).
.EXAMPLE
    pwsh -NoProfile -File .claude/hooks/tests/count-processes.ps1 -InputFile payload.json `
        -Command '"C:\Program Files\Git\bin\bash.exe" -c :'
#>
[CmdletBinding()]
param(
    [string] $Command = '',
    [string] $CommandFile = '',
    [string] $InputFile = '',
    [string] $Environment = '',
    [int] $TimeoutSec = 30
)
$ErrorActionPreference = 'Stop'

if (-not ('ProcessTree' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class ProcessTree
{
    [StructLayout(LayoutKind.Sequential)] struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public bool bInheritHandle; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
    [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [StructLayout(LayoutKind.Sequential)] struct BASIC_ACCOUNTING {
        public long TotalUserTime, TotalKernelTime, ThisPeriodTotalUserTime, ThisPeriodTotalKernelTime;
        public int TotalPageFaultCount, TotalProcesses, ActiveProcesses, TotalTerminatedProcesses; }
    [StructLayout(LayoutKind.Sequential)] struct ASSOCIATE_PORT { public IntPtr Key; public IntPtr Port; }

    const uint CREATE_SUSPENDED = 0x4, CREATE_NO_WINDOW = 0x08000000, STARTF_USESTDHANDLES = 0x100;
    const int JobBasicAccounting = 1, JobAssociateCompletionPort = 7;
    const uint MsgActiveProcessZero = 4, MsgNewProcess = 6;

    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcess(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFile(string name, uint access, uint share, ref SECURITY_ATTRIBUTES sa, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32", SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr a, string n);
    [DllImport("kernel32", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
    [DllImport("kernel32", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr j, int cls, ref ASSOCIATE_PORT info, int len);
    [DllImport("kernel32", SetLastError = true)] static extern bool QueryInformationJobObject(IntPtr j, int cls, out BASIC_ACCOUNTING info, int len, IntPtr ret);
    [DllImport("kernel32", SetLastError = true)] static extern IntPtr CreateIoCompletionPort(IntPtr f, IntPtr p, IntPtr k, int n);
    [DllImport("kernel32", SetLastError = true)] static extern bool GetQueuedCompletionStatus(IntPtr p, out uint msg, out IntPtr key, out IntPtr ov, uint ms);
    [DllImport("kernel32", SetLastError = true)] static extern uint ResumeThread(IntPtr t);
    [DllImport("kernel32", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr h, out int code);
    [DllImport("kernel32", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", SetLastError = true)] static extern bool TerminateJobObject(IntPtr j, uint code);
    [DllImport("kernel32", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr p, int f, StringBuilder s, ref int n);

    public class Result { public int Processes; public string[] Programs; public double CpuMs, WallMs; public int ExitCode; public bool Killed; }

    static string NameOf(int pid)
    {
        IntPtr h = OpenProcess(0x1000, false, pid); // PROCESS_QUERY_LIMITED_INFORMATION
        if (h == IntPtr.Zero) return "?";
        try {
            var sb = new StringBuilder(1024); int len = sb.Capacity;
            return QueryFullProcessImageName(h, 0, sb, ref len) ? Path.GetFileName(sb.ToString()) : "?";
        } finally { CloseHandle(h); }
    }

    public static Result Run(string commandLine, string stdinFile, string cwd, int timeoutMs)
    {
        var sa = new SECURITY_ATTRIBUTES { nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)), bInheritHandle = true };
        IntPtr stdin = CreateFile(stdinFile, 0x80000000, 1, ref sa, 3, 0x80, IntPtr.Zero);   // GENERIC_READ, OPEN_EXISTING
        IntPtr nul = CreateFile("NUL", 0x40000000, 3, ref sa, 3, 0x80, IntPtr.Zero);         // GENERIC_WRITE
        if (stdin == new IntPtr(-1)) throw new IOException("cannot open " + stdinFile);
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        IntPtr port = CreateIoCompletionPort(new IntPtr(-1), IntPtr.Zero, IntPtr.Zero, 1);
        var assoc = new ASSOCIATE_PORT { Key = new IntPtr(1), Port = port };
        SetInformationJobObject(job, JobAssociateCompletionPort, ref assoc, Marshal.SizeOf(typeof(ASSOCIATE_PORT)));
        var si = new STARTUPINFO { cb = Marshal.SizeOf(typeof(STARTUPINFO)), dwFlags = (int)STARTF_USESTDHANDLES, hStdInput = stdin, hStdOutput = nul, hStdError = nul };
        var names = new List<string>();
        var r = new Result();
        var clock = Stopwatch.StartNew();
        PROCESS_INFORMATION pi;
        if (!CreateProcess(null, new StringBuilder(commandLine), IntPtr.Zero, IntPtr.Zero, true, CREATE_SUSPENDED | CREATE_NO_WINDOW, IntPtr.Zero, cwd, ref si, out pi))
            throw new InvalidOperationException("CreateProcess failed: " + Marshal.GetLastWin32Error());
        AssignProcessToJobObject(job, pi.hProcess);
        // The port names every process of the tree as it starts, and says when the last one is gone.
        var empty = new ManualResetEventSlim();
        var reader = new Thread(() => {
            while (!empty.IsSet) {
                uint msg; IntPtr key, ov;
                if (!GetQueuedCompletionStatus(port, out msg, out key, out ov, 200)) continue;
                if (msg == MsgNewProcess) { string n = NameOf(ov.ToInt32()); lock (names) names.Add(n); }
                else if (msg == MsgActiveProcessZero) empty.Set();
            }
        });
        reader.Start();
        ResumeThread(pi.hThread);
        if (!empty.Wait(timeoutMs)) { TerminateJobObject(job, 1); r.Killed = true; empty.Wait(5000); empty.Set(); }
        clock.Stop();
        reader.Join(1000);
        BASIC_ACCOUNTING acct;
        QueryInformationJobObject(job, JobBasicAccounting, out acct, Marshal.SizeOf(typeof(BASIC_ACCOUNTING)), IntPtr.Zero);
        GetExitCodeProcess(pi.hProcess, out r.ExitCode);
        r.WallMs = clock.Elapsed.TotalMilliseconds;
        r.CpuMs = (acct.TotalUserTime + acct.TotalKernelTime) / 10000.0;
        r.Processes = acct.TotalProcesses;
        lock (names) r.Programs = names.ToArray();
        CloseHandle(pi.hThread); CloseHandle(pi.hProcess); CloseHandle(job); CloseHandle(port); CloseHandle(stdin); CloseHandle(nul);
        return r;
    }
}
'@
}
if ($MyInvocation.InvocationName -eq '.') { return }

if (-not $IsWindows) { throw 'count-processes.ps1 counts through a Windows job object; on Linux the hook suite counts with strace.' }
if (-not ($Command -or $CommandFile) -or -not $InputFile) { throw 'Usage: count-processes.ps1 -Command <command line> | -CommandFile <file> -InputFile <stdin file> [-Environment "NAME=VALUE`n..."] [-TimeoutSec <n>]' }
foreach ($pair in $Environment -split "`n") {
    $pair = $pair.TrimEnd("`r")
    if (-not $pair) { continue }
    $name, $value = $pair -split '=', 2
    [Environment]::SetEnvironmentVariable($name, $value)
}
$commands = if ($CommandFile) { @(Get-Content -LiteralPath $CommandFile | Where-Object { $_ }) } else { @($Command) }
$stdin = (Resolve-Path -LiteralPath $InputFile).Path
foreach ($c in $commands) {
    $r = [ProcessTree]::Run($c, $stdin, (Get-Location).Path, $TimeoutSec * 1000)
    $line = [ordered]@{ processes = $r.Processes; programs = @($r.Programs); cpuMs = [int][math]::Round($r.CpuMs); wallMs = [int][math]::Round($r.WallMs); exitCode = $r.ExitCode }
    if ($r.Killed) { $line.killed = $true }
    $line | ConvertTo-Json -Compress
}
