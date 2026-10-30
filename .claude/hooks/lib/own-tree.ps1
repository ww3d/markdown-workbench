# Helper of guard-kill.sh on Windows (ww3d/playbook#511): is a target process the session's own?
#
# Prints one word per target, in order: `own` (a descendant of the session's process), `gone` (no such process,
# so ending it ends nothing) or `foreign`. The session's process is -Root, or else the nearest ancestor of -Self
# that is Claude Code. The session's process and its ancestors are never own. A parent counts only when it was
# created before its child: Windows reuses process ids, and a reused id is no parent.
# -Jump lists `child=ancestor` pairs (Windows ids) the caller knows better than the process table: an MSYS
# process's Windows parent may be an exited stub, so it steps to its MSYS parent instead.
# Exit 2 when the process table cannot be read or -Self is not in it, 3 when no session process is found;
# nothing by number then passes the hook.
param(
    [Parameter(Mandatory)][int]$Self,
    [Parameter(Mandatory)][string]$Target,
    [string]$Jump = '',
    [int]$Root = 0
)
$ErrorActionPreference = 'Stop'
try {
    $all = Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId, Name, CommandLine, CreationDate
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
    $verdict = 'foreign'
    if ($id -ne $Root) {
        $p = $byId[$id]
        for ($i = 0; $i -lt 64 -and $null -ne $p; $i++) {
            $p = Get-RealParent $p
            if ($null -ne $p -and [int]$p.ProcessId -eq $Root) { $verdict = 'own'; break }
        }
    }
    $verdict
}
