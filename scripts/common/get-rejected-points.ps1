#Requires -Version 7.4

<#
.SYNOPSIS
    List the points earlier rounds already rejected - "schon verworfen, nur mit
    neuem Argument wieder aufmachen".

.DESCRIPTION
    Reads every round ledger (docs/decisions/*-ledger.jsonl, see
    ledger.schema.json) and prints the points with status `verworfen`, and in
    a group of their own the ones with status `zurueckgestellt`: id, satz,
    grund, neu_nur_mit, quelle and the file the point stands in. A design
    session reads the list before it reopens a question, so a rejected idea
    comes back only with the new argument its ledger line names.

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
    [string] Markdown; with -Json one JSON array of points (Group, Id, Satz,
    Grund, NeuNurMit, Quelle, File).

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


$groupOf = @{ verworfen = 'verworfen'; zurueckgestellt = 'zurueckgestellt' }
$value = {
    param([hashtable] $Line, [string] $Key)
    if ($Line.ContainsKey($Key) -and $null -ne $Line[$Key]) { "$($Line[$Key])" } else { '' }
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
        if (-not $groupOf.ContainsKey($status)) { continue }
        $point.Add([pscustomobject]@{
                Group     = $groupOf[$status]
                Id        = & $value $line 'id'
                Satz      = & $value $line 'satz'
                Grund     = & $value $line 'grund'
                NeuNurMit = & $value $line 'neu_nur_mit'
                Quelle    = & $value $line 'quelle'
                File      = $ledger
            })
    }
}

if ($Json) {
    ConvertTo-Json -InputObject @($point) -Depth 3
    return
}

$out = [System.Text.StringBuilder]::new()
[void]$out.AppendLine('# Schon verworfen - nur mit neuem Argument wieder aufmachen')
$heading = [ordered]@{
    verworfen       = '## Verworfen'
    zurueckgestellt = '## Zurueckgestellt'
}
foreach ($group in $heading.Keys) {
    $member = @($point | Where-Object Group -EQ $group)
    [void]$out.AppendLine().AppendLine($heading[$group]).AppendLine()
    if ($member.Count -eq 0) { [void]$out.AppendLine('Keine.'); continue }
    foreach ($entry in $member) {
        [void]$out.AppendLine("- **$($entry.Id)** - $($entry.Satz)")
        [void]$out.AppendLine("  - Grund: $($entry.Grund)")
        if ($entry.NeuNurMit) { [void]$out.AppendLine("  - Neu nur mit: $($entry.NeuNurMit)") }
        [void]$out.AppendLine("  - Quelle: $($entry.Quelle) ($(Split-Path -Leaf $entry.File))")
    }
}
$out.ToString().TrimEnd()
