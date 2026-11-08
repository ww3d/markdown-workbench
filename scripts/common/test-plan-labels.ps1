#Requires -Version 7.6

<#
.SYNOPSIS
    Check the plan rule of one repository: the plan labels, the rank lines and the cap of `plan/now`.

.DESCRIPTION
    The plan rule (.agents/rules/docs.md "Planning") puts when an issue is due into exactly one label -
    `plan/now`, `plan/next` or `plan/later` - and its order inside `plan/now` and `plan/next` into a
    `Rank: <decimal>` line of its body. This script reads the repository and reports where that does
    not hold. It reads only; it never sets a label or a rank.

    Read: the labels of the repository, every open issue that carries a `plan/*` label, and every open
    issue that carries `tracking`; pull requests are left out. Every finding names the issue, and the
    cap finding names the number it read and where from.

    Findings:

      unplanned             an open tracking issue without a plan label (tracking issues only)
      multiple-plan-labels  more than one plan label; the rank findings skip such an issue
      now-over-cap          more open `plan/now` issues than the cap
      cap-unreadable        the label `plan/now` is missing or its description does not read
                            `Now: at most <N> at once`; no default is assumed - -NowCap names one
      rank-missing          a `plan/now` or `plan/next` issue without a rank line
      rank-malformed        a rank line that is no decimal, a second one, text behind the value, or
                            a line that is no paragraph of its own
      rank-duplicate        the same rank on two issues of one column
      rank-on-later         a `plan/later` issue that carries a rank line

    The cap is the one in the description of `plan/now`; -NowCap replaces it for one run and is named
    as the source in the output.

    Output: per column the issues in rank order (an issue without a valid rank behind them), then the
    findings. -Json gives the same as one object for a machine. Exit 0 without a finding, 1 with
    one, 2 when a read failed.

    This script is deliberately SELF-CONTAINED - it imports no module, because it is mirrored into
    every consumer via scripts/common/. It calls two siblings: get-rest-items.ps1 for the REST reads
    and get-plan-fields.ps1 for the two forms of the plan rule.

.PARAMETER Repo
    owner/name of the repository.

.PARAMETER NowCap
    The cap for this run, instead of the one in the description of `plan/now`.

.PARAMETER Json
    Emit one JSON object (repo, cap, columns, findings) instead of text.

.INPUTS
    None.

.OUTPUTS
    [string] the report, or one JSON text under -Json.

.EXAMPLE
    ./scripts/common/test-plan-labels.ps1 -Repo ww3d/playbook

    The columns of ww3d/playbook in rank order, then what breaks the plan rule.
#>

[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string] $Repo,

    [Nullable[int]] $NowCap,

    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$getRestItems = Join-Path $PSScriptRoot 'get-rest-items.ps1'
$planFields = Join-Path $PSScriptRoot 'get-plan-fields.ps1'
$column = 'now', 'next', 'later'

function Get-OpenIssue([string] $Label) {
    @(& $getRestItems -Endpoint "repos/$Repo/issues?state=open&labels=$([uri]::EscapeDataString($Label))&per_page=100" |
            Where-Object { -not $_.PSObject.Properties['pull_request'] })
}

function Get-Entry {
    $issue = @{}   # not [ordered]: an integer key would be read as an index there
    foreach ($label in $column | ForEach-Object { "plan/$_" }) {
        foreach ($i in Get-OpenIssue $label) { $issue[[int]$i.number] = $i }
    }
    foreach ($i in Get-OpenIssue 'tracking') { $issue[[int]$i.number] = $i }
    foreach ($number in $issue.Keys | Sort-Object) {
        $i = $issue[$number]
        $name = @($i.labels | ForEach-Object { [string]$_.name })
        [pscustomobject]@{
            Number   = $number
            Title    = [string]$i.title
            Tracking = 'tracking' -cin $name
            Plan     = @($column | Where-Object { "plan/$_" -cin $name })
            Rank     = & $planFields -Body ([string]$i.body)
        }
    }
}

function Get-Cap([object[]] $Label) {
    $nowLabel = @($Label | Where-Object { $_.name -ceq 'plan/now' })
    if ($null -ne $NowCap) { return [pscustomobject]@{ Value = [int]$NowCap; Source = '-NowCap'; Problem = '' } }
    if (-not $nowLabel) { return [pscustomobject]@{ Value = $null; Source = 'unreadable'; Problem = 'the label plan/now does not exist' } }
    $description = [string]$nowLabel[0].description
    $cap = (& $planFields -Description $description).Cap
    if ($null -eq $cap) {
        return [pscustomobject]@{ Value = $null; Source = 'unreadable'; Problem = "the description of plan/now, '$description', does not read 'Now: at most <N> at once'" }
    }
    [pscustomobject]@{ Value = $cap; Source = 'label'; Problem = '' }
}

function Get-Finding([object[]] $Entry, [pscustomobject] $Cap) {
    $found = [System.Collections.Generic.List[object]]::new()
    $add = { param($Name, $Number, $Message) $found.Add([pscustomobject]@{ Finding = $Name; Issue = $Number; Message = $Message }) }

    if ($null -eq $Cap.Value) { & $add 'cap-unreadable' $null "$($Cap.Problem); pass -NowCap <N> to name a cap for this run" }
    foreach ($e in $Entry) {
        if ($e.Tracking -and $e.Plan.Count -eq 0) { & $add 'unplanned' $e.Number 'a tracking issue without a plan label' }
        if ($e.Plan.Count -gt 1) {
            & $add 'multiple-plan-labels' $e.Number "carries $($e.Plan.Count) plan labels: $(($e.Plan | ForEach-Object { "plan/$_" }) -join ', ')"
            continue
        }
        if ($e.Plan.Count -eq 0) { continue }
        switch ($e.Plan[0]) {
            'later' { if ($e.Rank.Lines -gt 0) { & $add 'rank-on-later' $e.Number 'a plan/later issue carries a rank line' } }
            default {
                if ($e.Rank.Status -eq 'none') { & $add 'rank-missing' $e.Number "a plan/$_ issue without a 'Rank:' line" }
                elseif ($e.Rank.Status -eq 'malformed') { & $add 'rank-malformed' $e.Number $e.Rank.Reason }
            }
        }
    }
    foreach ($name in 'now', 'next') {
        $ranked = @($Entry | Where-Object { $_.Plan.Count -eq 1 -and $_.Plan[0] -eq $name -and $_.Rank.Status -eq 'ok' })
        foreach ($group in $ranked | Group-Object { $_.Rank.Text } | Where-Object Count -gt 1) {
            foreach ($e in $group.Group) {
                $others = ($group.Group | Where-Object Number -ne $e.Number | ForEach-Object { "#$($_.Number)" }) -join ', '
                & $add 'rank-duplicate' $e.Number "rank $($group.Name) in plan/$name is also on $others"
            }
        }
    }
    $open = @($Entry | Where-Object { 'now' -in $_.Plan }).Count
    if ($null -ne $Cap.Value -and $open -gt $Cap.Value) {
        & $add 'now-over-cap' $null "$open open plan/now issues, cap $($Cap.Value) (source: $($Cap.Source))"
    }
    $found
}

function Get-ColumnList([object[]] $Entry) {
    $list = [ordered]@{}
    foreach ($name in $column) {
        $list[$name] = @($Entry | Where-Object { $name -in $_.Plan } |
                Sort-Object { if ($_.Rank.Status -eq 'ok') { $_.Rank.Rank } else { [decimal]::MaxValue } }, Number |
                ForEach-Object { [pscustomobject]@{ Issue = $_.Number; Title = $_.Title; Rank = $(if ($_.Rank.Status -eq 'ok') { $_.Rank.Text } else { $null }) } })
    }
    $list
}

try {
    $label = @(& $getRestItems -Endpoint "repos/$Repo/labels?per_page=100")
    $entry = @(Get-Entry)
} catch {
    [Console]::Error.WriteLine("test-plan-labels: a read failed: $($_.Exception.Message)")
    exit 2
}

$cap = Get-Cap $label
$finding = @(Get-Finding $entry $cap)
$list = Get-ColumnList $entry

if ($Json) {
    [ordered]@{
        repo     = $Repo
        cap      = [ordered]@{ value = $cap.Value; source = $cap.Source }
        columns  = $list
        findings = @($finding)
    } | ConvertTo-Json -Depth 6
} else {
    $capText = if ($null -ne $cap.Value) { "$($cap.Value) (source: $($cap.Source))" } else { 'unreadable' }
    "Plan check $Repo - cap $capText"
    foreach ($name in $column) {
        ''
        "plan/$name ($($list[$name].Count))"
        foreach ($i in $list[$name]) { "  #$($i.Issue)  $(if ($null -ne $i.Rank) { "Rank $($i.Rank)" } else { 'no rank' })  $($i.Title)" }
    }
    ''
    "Findings ($($finding.Count))"
    foreach ($f in $finding) { "  $($f.Finding)$(if ($null -ne $f.Issue) { " #$($f.Issue)" }): $($f.Message)" }
}
exit $(if ($finding.Count) { 1 } else { 0 })
