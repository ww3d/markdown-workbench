#Requires -Version 7.6

<#
.SYNOPSIS
    Run a command under a hard run limit and end it, with every child process,
    when the limit runs out - the one enforcement of the 3-minute rule
    (.agents/rules/pr.md, section "Test Runs").

.DESCRIPTION
    The limit counts from the start of the command, build included. Windows
    holds the process tree in a Job Object (a child that detaches from its
    parent still ends with the run); Linux and macOS end the whole process
    group, SIGTERM first and SIGKILL after the grace time. Where no process
    group can be made (no setsid) the tree is walked by parent id instead.

    -Kind names the sort of run. `gated` (default) is the 3-minute run and takes
    the default limit of 170 s. Every other kind - nightly, e2e, integration,
    full-before-merge - is exempt from 3:00; the kind stands in the end line.
    A nightly, e2e or integration run takes as its limit twice the longest of the
    last five green runs of its kind, kept under `runs` in
    .agents/config/test-limits.json (a green run adds its seconds there; -NoRecord
    leaves the file alone); with none on record it must name -LimitSec, and a
    given -LimitSec wins. full-before-merge must name -LimitSec and is refused,
    naming the plan, for the command that a plan of `splitPlans` in the same file
    covers (scripts/common/split-test-run.ps1): the repo runs its full run in parts.

    The per-test hang guard (the second stage) is handed to the stack's runner
    where the command is one of: `dotnet test` (VSTest: --blame-hang-timeout;
    Microsoft.Testing.Platform, seen in global.json: --hangdump
    --hangdump-timeout), `cargo nextest run` (a generated config file with
    slow-timeout and terminate-after), `jest` and `vitest` (--testTimeout). Its
    value is `hangTimeoutSec` in .agents/config/test-limits.json of the repo
    (default 150, allowed 30 to 150, anything else is refused naming the key).
    A Pester run is guarded through the environment variable
    PLAYBOOK_RUNNING_DIR: the test worker writes the block it starts into that
    folder, and the abort names it.

    At an abort the tests that were running are named from the stack's own
    record (dotnet: the Sequence_*.xml of --blame, tests without Completed;
    Pester: the folder above); a stack without a record gives
    `running: unknown (<stack>)`. A .NET hang adds a line
    `hang: <test> at <file>:<line> (<method>)`; the tool that reads the stack is a
    package whose question is still open, so the position stands as
    `at unknown (package question 1057)`.

    Exit codes: the command's own code when it ended in time (0 green, other
    red); 124 when the limit ended it - never 0, even when the command itself
    answered 0 at the very end; 2 for a call error (bad kind, bad value).
    A command that itself exits 124 is read as a timeout; use another code.
    The last line is always
    `guarded-run: kind=<kind> limit=<n>s elapsed=<n>s result=<ok|red|timeout> exit=<n>`;
    a timeout puts `red: timeout <names>` before it.

.PARAMETER Kind
    gated (default), nightly, e2e, integration or full-before-merge.

.PARAMETER LimitSec
    The run limit in seconds. Default 170 for `gated`; for nightly, e2e and integration the double of the
    longest of the last five green runs; mandatory for the other kinds and where no green run is on record.

.PARAMETER NoRecord
    Do not add a green nightly, e2e or integration run to `runs` of the limit file.

.PARAMETER LimitMs
    The limit in milliseconds, for tests; replaces -LimitSec.

.PARAMETER GraceMs
    Time between SIGTERM and SIGKILL on Linux and macOS. Default 10000.

.PARAMETER RepoRoot
    Where .agents/config/test-limits.json and global.json are read. Default: the current folder.

.PARAMETER Plan
    Print the command with the hang-guard arguments added as JSON and run nothing.

.PARAMETER Command (everything after the options)
    The command and its arguments; everything after the named parameters.

.EXAMPLE
    ./scripts/common/invoke-guarded-run.ps1 -Kind gated pwsh -File ./scripts/check.ps1

.EXAMPLE
    ./scripts/common/invoke-guarded-run.ps1 -Kind nightly -LimitSec 3600 dotnet test
#>

# No param block on purpose: a command such as `dotnet test -v n` carries its own dashes, and
# a bound parameter list would read `-v` as -Verbose. The options in front of the command are
# read here; the first word that is no option starts the command.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Kind = 'gated'; $LimitSec = $null; $LimitMs = $null; $GraceMs = 10000; $RepoRoot = (Get-Location).ProviderPath; $Plan = $false; $NoRecord = $false
$kinds = 'gated', 'nightly', 'e2e', 'integration', 'full-before-merge'
$position = 0
while ($position -lt $args.Count) {
    $name = [string]$args[$position]
    $takesValue = $name -in '-Kind', '-LimitSec', '-LimitMs', '-GraceMs', '-RepoRoot'
    if ($takesValue -and $position + 1 -ge $args.Count) { [Console]::Error.WriteLine("$name needs a value."); exit 2 }
    $value = if ($takesValue) { [string]$args[$position + 1] } else { $null }
    $number = 0.0
    if ($name -in '-LimitSec', '-LimitMs', '-GraceMs' -and
        -not ([double]::TryParse($value, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$number) -and ($number -gt 0 -or ($name -eq '-GraceMs' -and $number -eq 0)))) {
        [Console]::Error.WriteLine("$name needs a positive number, is '$value'."); exit 2
    }
    switch ($name) {
        '-Kind' { if ($value -notin $kinds) { [Console]::Error.WriteLine("-Kind is one of: $($kinds -join ', ')."); exit 2 }; $Kind = $value }
        '-LimitSec' { $LimitSec = $number }
        '-LimitMs' { $LimitMs = $number }
        '-GraceMs' { $GraceMs = [int]$number }
        '-RepoRoot' { $RepoRoot = $value }
        '-Plan' { $Plan = $true }
        '-NoRecord' { $NoRecord = $true }
    }
    if ($name -notin '-Kind', '-LimitSec', '-LimitMs', '-GraceMs', '-RepoRoot', '-Plan', '-NoRecord') { break }
    $position += if ($takesValue) { 2 } else { 1 }
}
$Command = @($args | Select-Object -Skip $position | ForEach-Object { [string]$_ })

if (-not $Command) { [Console]::Error.WriteLine('No command given.'); exit 2 }

# ---- the repo's limit file -------------------------------------------------
$config = @{}
$limitFile = Join-Path $RepoRoot '.agents/config/test-limits.json'
if (Test-Path -LiteralPath $limitFile) { $config = Get-Content -LiteralPath $limitFile -Raw | ConvertFrom-Json -AsHashtable }

# A repo that splits its full run (scripts/common/split-test-run.ps1 -Register) has no single full-before-merge run.
if ($Kind -eq 'full-before-merge' -and $config.ContainsKey('splitPlans')) {
    # Separators unified: a plan covers scripts/test.ps1 however the command spells the path.
    $commandLine = ($Command -join ' ').ToLowerInvariant().Replace('\', '/')
    foreach ($split in @($config['splitPlans'])) {
        $covers = "$($split['covers'])".ToLowerInvariant().Replace('\', '/')
        if (-not $covers -or $commandLine.Contains($covers)) {
            [Console]::Error.WriteLine("-Kind full-before-merge is refused: this repo splits its full run in the plan '$($split['name'])' ($limitFile). Run its parts, each as -Kind gated (scripts/common/split-test-run.ps1).")
            exit 2
        }
    }
}

# ---- the run limit --------------------------------------------------------
# A nightly, e2e or integration run ends at twice the longest of the last five green runs of its kind
# (`runs` in the limit file); with none on record the call names -LimitSec.
$longRuns = 'nightly', 'e2e', 'integration'
$history = @(if ($Kind -in $longRuns -and $config.ContainsKey('runs') -and $config['runs'] -is [System.Collections.IDictionary] -and $config['runs'].Contains($Kind)) {
        @($config['runs'][$Kind]) | Select-Object -Last 5
    })
$limitMillis = if ($null -ne $LimitMs) { $LimitMs }
elseif ($null -ne $LimitSec) { $LimitSec * 1000 }
elseif ($Kind -eq 'gated') { 170000 }
elseif ($history.Count -gt 0) { 2000 * ($history | Measure-Object -Maximum).Maximum }
else { [Console]::Error.WriteLine("-Kind $Kind needs -LimitSec (only gated has the default 170 s, and no green run of this kind is on record in $limitFile)."); exit 2 }
if ($Kind -eq 'gated' -and $limitMillis -gt 180000) {
    [Console]::Error.WriteLine('-Kind gated ends after 3:00 at the latest; use another kind for a longer run.'); exit 2
}

# ---- the per-test hang guard value ---------------------------------------
$hangSec = 150
if ($config.Count -gt 0) {
    if ($config.ContainsKey('hangTimeoutSec')) {
        $value = $config['hangTimeoutSec']
        if ($value -isnot [int] -and $value -isnot [long] -and $value -isnot [double] -or $value -lt 30 -or $value -gt 150) {
            [Console]::Error.WriteLine("hangTimeoutSec in $limitFile must be a number from 30 to 150, is '$value'."); exit 2
        }
        $hangSec = [int]$value
    }
}

# ---- stack and hang-guard arguments --------------------------------------
$leaf = [System.IO.Path]::GetFileNameWithoutExtension($Command[0]).ToLowerInvariant()
$joined = ($Command | ForEach-Object { $_.ToLowerInvariant() }) -join ' '
$stack = 'unknown'
$guardArgs = @()
$nextestConfig = $null
if ($leaf -eq 'dotnet' -and $joined -match '(^| )test( |$)') {
    $globalJson = Join-Path $RepoRoot 'global.json'
    $mtp = (Test-Path -LiteralPath $globalJson) -and ((Get-Content -LiteralPath $globalJson -Raw) -match 'Microsoft\.Testing\.Platform')
    $stack = if ($mtp) { 'dotnet-mtp' } else { 'dotnet-vstest' }
    if ($mtp -and $joined -notmatch '--hangdump') { $guardArgs = @('--hangdump', '--hangdump-timeout', "$($hangSec)s") }
    elseif (-not $mtp -and $joined -notmatch '--blame-hang-timeout') { $guardArgs = @('--blame-hang-timeout', "$($hangSec)s") }
} elseif ($leaf -eq 'cargo' -and $joined -match 'nextest') {
    $stack = 'rust-nextest'
    if ($joined -notmatch '--config-file|--tool-config-file') {
        $nextestConfig = Join-Path ([System.IO.Path]::GetTempPath()) "nextest-guard-$([guid]::NewGuid().ToString('N')).toml"
        # --config-file would replace the repo's .config/nextest.toml (retries, test groups): such a repo gets the
        # guard as a tool config, which its own keys outrank (#632).
        $guardArgs = if (Test-Path -LiteralPath (Join-Path $RepoRoot '.config/nextest.toml')) { @('--tool-config-file', "playbook-guard:$nextestConfig") } else { @('--config-file', $nextestConfig) }
    }
} elseif ($leaf -in 'jest', 'vitest' -or $joined -match '(^| )(jest|vitest)( |$)') {
    $stack = if ($joined -match 'vitest') { 'vitest' } else { 'jest' }
    if ($joined -notmatch '--testtimeout') { $guardArgs = @('--testTimeout', [string]($hangSec * 1000)) }
} elseif ($leaf -in 'pwsh', 'powershell') {
    $stack = 'pester'
}
$runCommand = @($Command) + $guardArgs

if ($Plan) {
    [pscustomobject]@{
        Kind = $Kind; LimitMs = $limitMillis; Stack = $stack; HangSec = $hangSec
        Command = @($runCommand); NextestConfig = $nextestConfig
    } | ConvertTo-Json -Depth 3
    exit 0
}
if ($nextestConfig) {
    # One test ends after the value; without a nextest.toml of the repo this file is the whole config.
    Set-Content -LiteralPath $nextestConfig -Encoding utf8 -Value @(
        '[profile.default]'
        "slow-timeout = { period = `"$($hangSec)s`", terminate-after = 1 }")
}

# ---- Windows Job Object ---------------------------------------------------
if ($IsWindows -and -not ('GuardedRun.Job' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace GuardedRun {
  public static class Job {
    [StructLayout(LayoutKind.Sequential)] struct BasicLimit { public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinWs, MaxWs; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass, SchedulingClass; }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong a, b, c, d, e, f; }
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimit { public BasicLimit Basic; public IoCounters Io; public UIntPtr ProcessMemory, JobMemory, PeakProcess, PeakJob; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attrs, string name);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int cls, ref ExtendedLimit info, int len);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] static extern bool TerminateJobObject(IntPtr job, uint code);
    public static IntPtr Create() {
      IntPtr job = CreateJobObject(IntPtr.Zero, null);
      var info = new ExtendedLimit(); info.Basic.LimitFlags = 0x2000; // KILL_ON_JOB_CLOSE
      if (!SetInformationJobObject(job, 9, ref info, Marshal.SizeOf(info))) throw new System.ComponentModel.Win32Exception();
      return job;
    }
    public static void Assign(IntPtr job, IntPtr process) { if (!AssignProcessToJobObject(job, process)) throw new System.ComponentModel.Win32Exception(); }
    public static void Kill(IntPtr job) { TerminateJobObject(job, 124); }
  }
}
'@
}

$runningDir = Join-Path ([System.IO.Path]::GetTempPath()) "guarded-running-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $runningDir -Force | Out-Null

function Get-ChildProcessId {
    param([int] $ParentId)
    foreach ($line in @(& pgrep -P $ParentId 2>$null)) {
        [int]$line
        Get-ChildProcessId -ParentId ([int]$line)
    }
}

# One hit only: /bin and /usr/bin both in PATH would give two, and Source would be an array.
function Find-Setsid { Get-Command setsid -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 }

$setsid = if ($IsWindows) { $null } else { Find-Setsid }
$launch = if ($setsid) { @($setsid.Source, '--') + $runCommand } else { $runCommand }
$start = [System.Diagnostics.ProcessStartInfo]::new($launch[0])
foreach ($arg in $launch | Select-Object -Skip 1) { $start.ArgumentList.Add($arg) }
$start.UseShellExecute = $false
# Set on the child's own environment: the caller's process keeps no variable pointing at a deleted folder.
$start.Environment['PLAYBOOK_RUNNING_DIR'] = $runningDir
$start.WorkingDirectory = (Get-Location).ProviderPath

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$job = [IntPtr]::Zero
if ($IsWindows) { $job = [GuardedRun.Job]::Create() }
$process = [System.Diagnostics.Process]::Start($start)
if ($IsWindows) { [GuardedRun.Job]::Assign($job, $process.Handle) }
$startedAt = [datetime]::UtcNow

$timedOut = -not $process.WaitForExit([int][Math]::Max(1, $limitMillis - $stopwatch.ElapsedMilliseconds))
if ($timedOut) {
    # The stack's record is read before the tree is gone.
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $runningDir -File -ErrorAction SilentlyContinue)) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($text) { $names.Add($text.Trim()) }
    }
    if ($stack -like 'dotnet-*') {
        foreach ($sequence in @(Get-ChildItem -Path $RepoRoot -Recurse -Filter 'Sequence_*.xml' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTimeUtc -ge $startedAt.AddSeconds(-1) })) {
            try {
                $xml = [xml](Get-Content -LiteralPath $sequence.FullName -Raw)
                foreach ($test in @($xml.TestSequence.Test | Where-Object { $_ -and $_.Completed -ne 'True' })) { $names.Add([string]$test.Name) }
            } catch { Write-Verbose "Sequence file '$($sequence.Name)' unreadable: $($_.Exception.Message)" }
        }
    }
    # The kill program, not the Stop-Process alias (PSAvoidUsingCmdletAliases); only non-Windows branches use it.
    if (-not $IsWindows) { $kill = (Get-Command -Name kill -CommandType Application -TotalCount 1).Source }
    if ($IsWindows) {
        [GuardedRun.Job]::Kill($job)
    } elseif ($setsid) {
        # `--` before the negative id: without it procps kill exits 0 and signals nothing (#632).
        & $kill -TERM -- "-$($process.Id)" 2>$null
        if (-not $process.WaitForExit($GraceMs)) { & $kill -KILL -- "-$($process.Id)" 2>$null }
    } else {
        $tree = @(Get-ChildProcessId -ParentId $process.Id)
        foreach ($id in $tree + $process.Id) { & $kill -TERM $id 2>$null }
        if (-not $process.WaitForExit($GraceMs)) { foreach ($id in $tree + $process.Id) { & $kill -KILL $id 2>$null } }
    }
    $null = $process.WaitForExit(5000)
    $running = @($names | Where-Object { $_ } | Select-Object -Unique)
    [Console]::Error.WriteLine("red: timeout$(if ($running) { " $($running -join ', ')" })")
    if (-not $running) { [Console]::Error.WriteLine("running: unknown ($stack)") }
    if ($stack -like 'dotnet-*' -and $running) {
        [Console]::Error.WriteLine("hang: $($running[0]) at unknown (package question 1057)")
    }
}
$elapsed = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
$exit = if ($timedOut) { 124 } else { $process.ExitCode }
$result = if ($timedOut) { 'timeout' } elseif ($exit -eq 0) { 'ok' } else { 'red' }
Remove-Item -LiteralPath $runningDir -Recurse -Force -ErrorAction SilentlyContinue
# A green long run goes on record: the next limit of its kind is twice the longest of the last five.
if ($result -eq 'ok' -and $Kind -in $longRuns -and -not $NoRecord) {
    $recorded = [ordered]@{}
    foreach ($entry in $config.GetEnumerator()) { $recorded[$entry.Key] = $entry.Value }
    $runs = [ordered]@{}
    if ($recorded.Contains('runs') -and $recorded['runs'] -is [System.Collections.IDictionary]) {
        foreach ($entry in $recorded['runs'].GetEnumerator()) { $runs[$entry.Key] = $entry.Value }
    }
    $runs[$Kind] = @(@($history) + [int][Math]::Ceiling($stopwatch.Elapsed.TotalSeconds) | Select-Object -Last 5)
    $recorded['runs'] = $runs
    New-Item -ItemType Directory -Path (Split-Path -Path $limitFile -Parent) -Force | Out-Null
    $recorded | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $limitFile -Encoding utf8
}
if ($nextestConfig) { Remove-Item -LiteralPath $nextestConfig -Force -ErrorAction SilentlyContinue }
[Console]::Error.WriteLine("guarded-run: kind=$Kind limit=$([Math]::Round($limitMillis / 1000, 1))s elapsed=$($elapsed)s result=$result exit=$exit")
exit $exit
