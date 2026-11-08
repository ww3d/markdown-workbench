#Requires -Version 7.6

<#
.SYNOPSIS
    Move one issue inside its plan column: compute its `Rank:` line from its neighbours and write it.

.DESCRIPTION
    Carries out a decision on the order inside `plan/now` or `plan/next`. Column and rank are the
    maintainer's decision (.agents/rules/docs.md "Planning"); an agent runs this only to carry one
    out. The issue must be open and carry exactly one of `plan/now` and `plan/next`; `plan/later` has no
    rank, and the column is never changed here.

    The column is read first - the open issues with the same label, the issue itself left out - and
    only issues with a valid rank line count (what the others lack is a finding of
    test-plan-labels.ps1). The new rank is the shortest decimal strictly between the two neighbours,
    the one nearest their middle; where two are as near, the larger. One more digit is added only where
    the shorter ones leave no room:

      -Top        above the first issue: the greatest whole number above 0 and below the first rank;
                  none, as with a first rank of 1 or less, the shortest decimal between 0 and it
      -Bottom     below the last issue: its whole part plus 1
      -After <N>  directly behind issue N of the column; behind the last one it is -Bottom
      -Before <N> directly before issue N of the column; before the first one it is -Top

    An empty column gives 1. The value is computed as [decimal] and written with the invariant culture,
    a point, no thousands separator and no zeros at the end. The line is written by
    edit-issue-body.ps1 -Field Rank and by nothing else, so its protections hold: the text around the
    line is compared byte for byte, the body is read again before the write and put back when GitHub
    stores another one. -WhatIf computes the rank and shows the change without writing.

    This script is deliberately SELF-CONTAINED - it imports no module, because it is mirrored into
    every consumer via scripts/common/. It calls three siblings: get-rest-items.ps1 for the REST reads,
    get-plan-fields.ps1 for the rank line and edit-issue-body.ps1 for the write.

.PARAMETER Repo
    owner/name of the repository.

.PARAMETER Issue
    The issue to move.

.PARAMETER Top
    Put the issue first in its column.

.PARAMETER Bottom
    Put the issue last in its column.

.PARAMETER After
    Put the issue directly behind this issue of the column.

.PARAMETER Before
    Put the issue directly before this issue of the column.

.INPUTS
    None.

.OUTPUTS
    [pscustomobject] with Issue (owner/repo#N), Column, Previous (the rank text it had, or $null), Rank
    (the text it gets) and Result ('written', 'unchanged' or 'what-if').

.EXAMPLE
    ./scripts/common/set-plan-rank.ps1 -Repo ww3d/playbook -Issue 491 -After 487 -WhatIf

    Shows the rank issue 491 would get directly behind issue 487 of its column.
#>

[CmdletBinding(SupportsShouldProcess)]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string] $Repo,

    [Parameter(Mandatory)]
    [ValidateRange(1, [int]::MaxValue)]
    [int] $Issue,

    [Parameter(Mandatory, ParameterSetName = 'Top')]
    [switch] $Top,

    [Parameter(Mandatory, ParameterSetName = 'Bottom')]
    [switch] $Bottom,

    [Parameter(Mandatory, ParameterSetName = 'After')]
    [ValidateRange(1, [int]::MaxValue)]
    [int] $After,

    [Parameter(Mandatory, ParameterSetName = 'Before')]
    [ValidateRange(1, [int]::MaxValue)]
    [int] $Before
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$getRestItems = Join-Path $PSScriptRoot 'get-rest-items.ps1'
$planFields = Join-Path $PSScriptRoot 'get-plan-fields.ps1'
$editBody = Join-Path $PSScriptRoot 'edit-issue-body.ps1'
$digitsMax = 28

# The shortest decimal strictly between $Low and $High, the nearest to their middle; a tie goes to the larger.
# A candidate with k decimals lies in the interval exactly when the middle rounded to k decimals does.
function Get-ShortestBetween([decimal] $Low, [decimal] $High) {
    $middle = ($Low + $High) / 2
    for ($digits = 0; $digits -le $digitsMax; $digits++) {
        $candidate = [math]::Round($middle, $digits, [MidpointRounding]::AwayFromZero)
        if ($candidate -gt $Low -and $candidate -lt $High) { return $candidate }
    }
    throw "no decimal of at most $digitsMax digits lies between $Low and $High."
}

function Get-RankBelow([decimal] $First) {
    if ($First -le 0) { throw "the first rank is $First; no rank fits before it." }
    $whole = [math]::Ceiling($First) - 1
    if ($whole -gt 0) { return [decimal] $whole }
    Get-ShortestBetween 0 $First
}

function Get-RankAbove([decimal] $Last) { [math]::Floor($Last) + 1 }

function Get-NewRank([decimal[]] $Rank, [string] $Mode, $Anchor) {
    if ($Rank.Count -eq 0) { return [decimal] 1 }
    $sorted = @($Rank | Sort-Object)
    switch ($Mode) {
        'Top' { return Get-RankBelow $sorted[0] }
        'Bottom' { return Get-RankAbove $sorted[-1] }
        'After' {
            $greater = @($sorted | Where-Object { $_ -gt $Anchor })
            if ($greater.Count -eq 0) { return Get-RankAbove $sorted[-1] }
            return Get-ShortestBetween $Anchor $greater[0]
        }
        'Before' {
            $smaller = @($sorted | Where-Object { $_ -lt $Anchor })
            if ($smaller.Count -eq 0) { return Get-RankBelow $sorted[0] }
            return Get-ShortestBetween $smaller[-1] $Anchor
        }
    }
}

$target = @(& $getRestItems -Endpoint "repos/$Repo/issues/$Issue")[0]
if ($target.PSObject.Properties['pull_request']) { throw "$Repo#$Issue is a pull request, not an issue." }
if ($target.state -ne 'open') { throw "$Repo#$Issue is $($target.state); only an open issue is ranked." }
$plan = @($target.labels | ForEach-Object { [string]$_.name } | Where-Object { $_ -cin 'plan/now', 'plan/next', 'plan/later' })
if ($plan.Count -eq 0) { throw "$Repo#$Issue carries no plan label; the maintainer places it first (.agents/rules/docs.md `"Planning`")." }
if ($plan.Count -gt 1) { throw "$Repo#$Issue carries $($plan.Count) plan labels ($($plan -join ', ')); one is left first." }
if ($plan[0] -eq 'plan/later') { throw "$Repo#$Issue is in plan/later, which has no rank." }
$own = & $planFields -Body ([string]$target.body)
if ($own.Status -eq 'malformed') { throw "$Repo#$Issue has a malformed rank line ($($own.Reason)); repair it first." }

$column = @(& $getRestItems -Endpoint "repos/$Repo/issues?state=open&labels=$([uri]::EscapeDataString($plan[0]))&per_page=100" |
        Where-Object { -not $_.PSObject.Properties['pull_request'] -and [int]$_.number -ne $Issue })
$ranked = [System.Collections.Generic.Dictionary[int, decimal]]::new()
$skipped = 0
foreach ($i in $column) {
    $labels = @($i.labels | ForEach-Object { [string]$_.name } | Where-Object { $_ -clike 'plan/*' })
    $read = & $planFields -Body ([string]$i.body)
    if ($labels.Count -eq 1 -and $read.Status -eq 'ok') { $ranked[[int]$i.number] = $read.Rank } else { $skipped++ }
}
if ($skipped) { Write-Warning "$skipped issue(s) of $($plan[0]) have no valid rank line and are left out; test-plan-labels.ps1 names them." }

$mode = $PSCmdlet.ParameterSetName
$anchor = $null
if ($mode -in 'After', 'Before') {
    $anchorNumber = if ($mode -eq 'After') { $After } else { $Before }
    if ($anchorNumber -eq $Issue) { throw "-$mode names the issue itself." }
    if (-not $ranked.ContainsKey($anchorNumber)) {
        throw "#$anchorNumber is no issue with a valid rank in $($plan[0]) of $Repo."
    }
    $anchor = $ranked[$anchorNumber]
}

$rank = Get-NewRank -Rank @($ranked.Values) -Mode $mode -Anchor $anchor
$text = & $planFields -Format $rank
$edit = & $editBody -Repo $Repo -Issue $Issue -Field Rank -Value $text -WhatIf:$WhatIfPreference

[pscustomobject]@{
    Issue    = "$Repo#$Issue"
    Column   = $plan[0]
    Previous = $(if ($own.Status -eq 'ok') { $own.Text })
    Rank     = $text
    Result   = $edit.Result
}
