#Requires -Version 7.6

<#
.SYNOPSIS
    List the points earlier rounds already rejected - "already rejected,
    reopen only with a new argument".

.DESCRIPTION
    Reads every round ledger (docs/decisions/*-ledger.jsonl, see
    ledger.schema.json) and prints the points with status `rejected`, and in
    a group of their own the ones with status `deferred`: id, statement,
    reason, reopen_only_with, source and the file the point stands in. A
    design session reads the list before it reopens a question, so a rejected
    idea comes back only with the new argument its ledger line names.

    Lines that do not parse are skipped with a warning; test-ledger.ps1 is the
    check that names them. Exit code 0, whatever the list holds.

.PARAMETER Path
    Ledger files, or folders holding *-ledger.jsonl files. Defaults to
    docs/decisions of the repository this script sits in.

.PARAMETER Json
    Serialize the points as JSON instead of Markdown.

.INPUTS
    None.

.OUTPUTS
    [string] Markdown; with -Json one JSON array of points (Group `rejected`
    or `deferred`, Id, Statement, Reason, ReopenOnlyWith, Source, File).

.EXAMPLE
    ./scripts/common/get-rejected-points.ps1

    The list for the next design round, as Markdown.

.EXAMPLE
    ./scripts/common/get-rejected-points.ps1 -Json
#>

[CmdletBinding()]
[OutputType([string])]
param(
    [string[]] $Path,
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$file = @(& (Join-Path $PSScriptRoot 'get-ledger-file.ps1') -Path $Path)

$groupOf = @{ rejected = 'rejected'; deferred = 'deferred' }
$value = {
    param([hashtable] $Line, [string] $Key)
    if ($Line.ContainsKey($Key)) { "$($Line[$Key])" } else { '' }
}

$point = [System.Collections.Generic.List[pscustomobject]]::new()
foreach ($ledger in $file) {
    $number = 0
    foreach ($text in [System.IO.File]::ReadAllLines($ledger)) {
        $number++
        if (-not $text.Trim()) { continue }
        try { $line = $text | ConvertFrom-Json -AsHashtable -ErrorAction Stop }
        catch { Write-Warning "${ledger}:${number}: not valid JSON, skipped"; continue }
        if ($line -isnot [hashtable]) { Write-Warning "${ledger}:${number}: not a JSON object, skipped"; continue }
        $status = & $value $line 'status'
        if ($status -cnotin 'rejected', 'deferred') { continue }
        $point.Add([pscustomobject]@{
                Group          = $status
                Id             = & $value $line 'id'
                Statement      = & $value $line 'statement'
                Reason         = & $value $line 'reason'
                ReopenOnlyWith = & $value $line 'reopen_only_with'
                Source         = & $value $line 'source'
                File           = $ledger
            })
    }
}

if ($Json) {
    ConvertTo-Json -InputObject @($point) -Depth 3
    return
}

$out = [System.Text.StringBuilder]::new()
[void]$out.AppendLine('# Already rejected - reopen only with a new argument')
$heading = [ordered]@{
    rejected = '## Rejected'
    deferred = '## Deferred'
}
foreach ($group in $heading.Keys) {
    $member = @($point | Where-Object Group -EQ $group)
    [void]$out.AppendLine().AppendLine($heading[$group]).AppendLine()
    if ($member.Count -eq 0) { [void]$out.AppendLine('None.'); continue }
    foreach ($entry in $member) {
        [void]$out.AppendLine("- **$($entry.Id)** - $($entry.Statement)")
        [void]$out.AppendLine("  - Reason: $($entry.Reason)")
        if ($entry.ReopenOnlyWith) { [void]$out.AppendLine("  - Reopen only with: $($entry.ReopenOnlyWith)") }
        [void]$out.AppendLine("  - Source: $($entry.Source) ($(Split-Path -Leaf $entry.File))")
    }
}
$out.ToString().TrimEnd()
