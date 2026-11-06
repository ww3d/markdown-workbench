# Helper of guard-kill.sh and grant-kill.sh on Windows (ww3d/playbook#511, #516): the process table, read once.
#
# With -Target: one word per target, in order: `own` (a descendant of the session's process), `gone` (no such
# process, so ending it ends nothing) or `foreign:<start>`, its start time as Unix milliseconds. The session's
# process is -Root, or else the nearest ancestor of -Self that is Claude Code. The session's process and its
# ancestors are never own. A parent counts only when it was created before its child: Windows reuses process ids,
# and a reused id is no parent.
# With -Describe <id>: the records grant-kill.sh judges, one per line, fields split by the unit separator (0x1F):
#   T id start kernel name path cwd cmdline   the process (kernel 1 for ids 0 and 4 and session 0)
#   C why                                     only where its working folder could not be read: why (cwd is empty)
#   A id name path cmdline                    each ancestor, nearest first
#   D id name path cmdline                    each descendant
#   S id                                      -Self and each of its ancestors
# -Jump lists `child=ancestor` pairs (Windows ids) the caller knows better than the process table: an MSYS
# process's Windows parent may be an exited stub, so it steps to its MSYS parent instead.
# Exit 2 when the process table cannot be read or -Self is not in it, 3 when no session process is found (-Target),
# 4 when the -Describe process is gone; nothing by number then passes the hook.
param(
    [Parameter(Mandatory)][int]$Self,
    [string]$Target = '',
    [string]$Jump = '',
    [int]$Root = 0,
    [int]$Describe = -1
)
$ErrorActionPreference = 'Stop'
try {
    $all = Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId, Name, CommandLine,
        CreationDate, ExecutablePath, SessionId
} catch {
    exit 2
}
$byId = @{}
foreach ($p in $all) { $byId[[int]$p.ProcessId] = $p }
if (-not $byId.ContainsKey($Self)) { exit 2 }

$jumps = @{}
foreach ($pair in ($Jump -split ',' | Where-Object { $_ })) {
    $from, $to = $pair -split '=', 2
    $jumps[[int]$from] = [int]$to
}

function Get-RealParent($Process) {
    $id = [int]$Process.ProcessId
    if ($jumps.ContainsKey($id)) { return $byId[$jumps[$id]] }
    $parent = $byId[[int]$Process.ParentProcessId]
    if ($null -eq $parent -or $parent.ProcessId -eq $Process.ProcessId) { return $null }
    if ($null -eq $parent.CreationDate -or $null -eq $Process.CreationDate) { return $null }
    if ($parent.CreationDate -gt $Process.CreationDate) { return $null }
    $parent
}

function Get-Start($Process) {
    if ($null -eq $Process.CreationDate) { return '' }
    ([DateTimeOffset]$Process.CreationDate).ToUnixTimeMilliseconds()
}

if ($Describe -ge 0) {
    $t = $byId[$Describe]
    if ($null -eq $t) { exit 4 }
    $sep = [string][char]0x1F
    # RTL_USER_PROCESS_PARAMETERS.CurrentDirectory.DosPath: the PEB holds ProcessParameters at 0x20 (0x10 in the
    # PEB32 of a WOW64 process), CurrentDirectory lies at 0x38 (0x24) there.
    $pebReader = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class GuardKillPeb {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(int access, bool inherit, int id);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool IsWow64Process(IntPtr handle, out bool wow64);
    [DllImport("ntdll.dll")]
    static extern int NtQueryInformationProcess(IntPtr handle, int infoClass, byte[] info, int size, out int got);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadProcessMemory(IntPtr handle, IntPtr address, byte[] buffer, IntPtr size, out IntPtr got);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetProcessTimes(IntPtr handle, out long created, out long exited, out long kernel, out long user);

    static Exception Fail(string what) {
        return new Exception(string.Format("{0} (Win32 error {1})", what, Marshal.GetLastWin32Error()));
    }
    static byte[] Read(IntPtr handle, long address, int size) {
        byte[] buffer = new byte[size];
        IntPtr got;
        if (!ReadProcessMemory(handle, new IntPtr(address), buffer, new IntPtr(size), out got) || got.ToInt64() != size)
            throw Fail("reading its memory failed");
        return buffer;
    }
    public static string CurrentDirectory(int id, long startMs) {
        if (IntPtr.Size != 8) throw new Exception("the reader runs as a 32-bit process");
        IntPtr handle = OpenProcess(0x1000 | 0x0010, false, id); // QUERY_LIMITED_INFORMATION | VM_READ
        if (handle == IntPtr.Zero) throw Fail("opening the process failed");
        try {
            bool wow64;
            long created, exited, kernel, user;
            if (!GetProcessTimes(handle, out created, out exited, out kernel, out user)) throw Fail("asking for its start failed");
            // The number may name another process since the snapshot; its start tells them apart.
            if (startMs >= 0 && Math.Abs(DateTimeOffset.FromFileTime(created).ToUnixTimeMilliseconds() - startMs) > 1)
                throw new Exception("the number names another process now");
            if (!IsWow64Process(handle, out wow64)) throw Fail("asking for its bitness failed");
            int got, status;
            long length, text;
            if (wow64) {
                byte[] info = new byte[8];
                status = NtQueryInformationProcess(handle, 26, info, info.Length, out got); // ProcessWow64Information
                if (status != 0) throw new Exception(string.Format("no PEB32 (NTSTATUS 0x{0:X8})", status));
                long parameters = BitConverter.ToUInt32(Read(handle, BitConverter.ToInt64(info, 0) + 0x10, 4), 0);
                byte[] dosPath = Read(handle, parameters + 0x24, 8);
                length = BitConverter.ToUInt16(dosPath, 0); text = BitConverter.ToUInt32(dosPath, 4);
            } else {
                byte[] info = new byte[48];
                status = NtQueryInformationProcess(handle, 0, info, info.Length, out got); // ProcessBasicInformation
                if (status != 0) throw new Exception(string.Format("no PEB (NTSTATUS 0x{0:X8})", status));
                long parameters = BitConverter.ToInt64(Read(handle, BitConverter.ToInt64(info, 8) + 0x20, 8), 0);
                byte[] dosPath = Read(handle, parameters + 0x38, 16);
                length = BitConverter.ToUInt16(dosPath, 0); text = BitConverter.ToInt64(dosPath, 8);
            }
            if (length == 0) throw new Exception("its working folder is empty");
            return Encoding.Unicode.GetString(Read(handle, text, (int)length));
        } finally {
            CloseHandle(handle);
        }
    }
}
'@
    function Get-Field($Process) {
        foreach ($v in $Process.Name, $Process.ExecutablePath, $Process.CommandLine) { "$v" -replace '[\t\r\n\x1F]', ' ' }
    }
    function Get-Record([string]$Kind, $Process) {
        (@($Kind, $Process.ProcessId) + (Get-Field $Process)) -join $sep
    }
    $kernel = if ($Describe -in 0, 4 -or $t.SessionId -eq 0) { 1 } else { 0 }
    $name, $path, $line = Get-Field $t
    # No CIM class carries the working folder: it is read from the target's PEB, as psutil does
    # (ww3d/playbook#531). Compiled here only, never on guard-kill.sh's own-tree call.
    $cwd, $cwdWhy = '', ''
    $start = Get-Start $t
    $startMs = if ($start -eq '') { -1 } else { [long]$start }
    try {
        Add-Type -TypeDefinition $pebReader
        $cwd = [GuardKillPeb]::CurrentDirectory($Describe, $startMs) -replace '[\t\r\n\x1F]', ' '
    } catch {
        $cwdWhy = "the working folder could not be read: $($_.Exception.GetBaseException().Message)" -replace '[\t\r\n\x1F]', ' '
    }
    ('T', $Describe, $start, $kernel, $name, $path, $cwd, $line) -join $sep
    if ($cwdWhy) { "C$sep$cwdWhy" }
    $p = $t
    for ($i = 0; $i -lt 64; $i++) {
        $p = Get-RealParent $p
        if ($null -eq $p) { break }
        Get-Record 'A' $p
    }
    $children = @{}
    foreach ($c in $all) {
        $parent = Get-RealParent $c
        if ($null -ne $parent) { $children[[int]$parent.ProcessId] += @($c) }
    }
    $queue = [System.Collections.Generic.Queue[int]]::new()
    $queue.Enqueue($Describe)
    $seen = @{ $Describe = $true }
    while ($queue.Count -gt 0) {
        foreach ($c in $children[$queue.Dequeue()]) {
            $id = [int]$c.ProcessId
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            $queue.Enqueue($id)
            Get-Record 'D' $c
        }
    }
    $p = $byId[$Self]
    for ($i = 0; $i -lt 64 -and $null -ne $p; $i++) {
        "S$sep$($p.ProcessId)"
        $p = Get-RealParent $p
    }
    exit 0
}

if ($Root -eq 0) {
    # Claude Code: the native claude.exe, or node running the npm package.
    $p = $byId[$Self]
    for ($i = 0; $i -lt 64 -and $null -ne $p; $i++) {
        if ($p.Name -eq 'claude.exe' -or "$($p.CommandLine)" -match '@anthropic-ai[\\/]claude-code') {
            $Root = [int]$p.ProcessId
            break
        }
        $p = Get-RealParent $p
    }
}
if ($Root -eq 0 -or -not $byId.ContainsKey($Root)) { exit 3 }

foreach ($t in ($Target -split '[\s,]+' | Where-Object { $_ })) {
    $id = [int]$t
    if (-not $byId.ContainsKey($id)) { 'gone'; continue }
    $verdict = "foreign:$(Get-Start $byId[$id])"
    if ($id -ne $Root) {
        $p = $byId[$id]
        for ($i = 0; $i -lt 64 -and $null -ne $p; $i++) {
            $p = Get-RealParent $p
            if ($null -ne $p -and [int]$p.ProcessId -eq $Root) { $verdict = 'own'; break }
        }
    }
    $verdict
}
