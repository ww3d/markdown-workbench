#Requires -Version 7.4

<#
.SYNOPSIS
    Say whether a FULL state audit is due, and show the numbers behind the
    answer.

.DESCRIPTION
    A full audit (.agents/rules/audit.md, section "State Audit") is due when
    any of three conditions holds; each one prints its actual figure, so the
    verdict can be re-checked by eye:

    a) The repository holds no audit: no audit/ist-stand-*.md (nor
       docs/audit/ist-stand-*.md).
    b) The design changes code that the architecture or baseline document
       describes. Input -Path: the paths the design touches. A hit is such a
       path - or a folder above it - named in backticks in
       docs/architecture*.md or docs/*baseline*.md; the answer names the
       document and line.
    c) More than N pull requests were merged into the default branch since the
       commit the latest audit names in its `**Commit:**` metadata line. The
       method: squash-merge commits whose subject ends in `(#<n>)` and merge
       commits whose subject starts with `Merge pull request #<n>`, counted
       with `git log --first-parent <commit>..<branch>`. N is 30 unless the
       repository's CLAUDE.md carries a line `Audit-Schwelle: <N>`. When the
       audit names no readable commit, or the commit is not in the history
       (a shallow clone), the figure is not computable; that counts as due, so
       a gap errs toward the audit, and the answer says why.

    This is an information script, not a gate: the exit code is 0 whatever
    the verdict. Only a broken input (not a git repository, unknown branch,
    unreadable path) ends it with an error.

.PARAMETER Path
    Paths (relative to -Root, forward slashes) the design touches; feeds
    condition b. Without it, b is reported as not checked.

.PARAMETER Root
    The repository root. Defaults to the repository this script sits in.

.PARAMETER Branch
    The default branch to count on. Defaults to what origin/HEAD points at,
    else main, else master.

.PARAMETER Json
    Serialize the answer as JSON instead of printing it.

.INPUTS
    None.

.OUTPUTS
    [string] one line per condition plus the verdict; with -Json one object
    (Due, Threshold, LatestAudit, Condition[] with Id, Due, Figure, Detail).

.EXAMPLE
    ./scripts/common/get-audit-due.ps1 -Path src/Orders/Pipeline.cs,docs/x.md

    The three conditions with their figures, for a design touching two files.
#>

[CmdletBinding()]
[OutputType([string])]
param(
    [string[]] $Path = @(),
    [string] $Root,
    [string] $Branch,
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if (-not $Root) { $Root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent }
if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Repository root not found at '$Root'." }
$Root = (Resolve-Path -LiteralPath $Root).ProviderPath

$git = {
    param([string[]] $Argument)
    $output = @(& git -C $Root @Argument 2>$null)
    [pscustomobject]@{ Exit = $LASTEXITCODE; Line = [string[]]@($output | ForEach-Object { "$_" }) }
}
if ((& $git @('rev-parse', '--is-inside-work-tree')).Exit -ne 0) { throw "'$Root' is not a git repository." }

# Threshold, default branch and the merged-PR subject test, shared with get-audit-worklist.ps1.
$settings = & (Join-Path $PSScriptRoot 'get-audit-settings.ps1') -Root $Root -Branch $Branch
$Branch = $settings.Branch
if (-not $Branch) { throw 'No default branch found (origin/HEAD, main, master); pass -Branch.' }
# The local branch may lag or be absent in a checkout of another branch; origin's wins when it exists.
$countRef = if ($settings.CountRef) { $settings.CountRef } else { $Branch }
if ((& $git @('rev-parse', '--verify', '--quiet', $countRef)).Exit -ne 0) { throw "Branch '$Branch' not found." }

$condition = [System.Collections.Generic.List[pscustomobject]]::new()
$add = {
    param([string] $Id, [bool] $Due, [string] $Figure, [string] $Detail = '')
    $condition.Add([pscustomobject]@{ Id = $Id; Due = $Due; Figure = $Figure; Detail = $Detail })
}

# --- a) no audit in the repository ---------------------------------------
$auditFile = @(@(foreach ($folder in 'audit', 'docs/audit') {
            $full = Join-Path $Root $folder
            if (Test-Path -LiteralPath $full -PathType Container) {
                Get-ChildItem -LiteralPath $full -Filter 'ist-stand-*.md' -File
            }
        }) | Sort-Object Name)
$latest = $auditFile | Select-Object -Last 1
if (-not $latest) {
    & $add 'a' $true 'kein Audit im Repo (audit/ist-stand-*.md)'
} else {
    & $add 'a' $false "$($auditFile.Count) Audit(s), letzter $($latest.Name)"
}

# --- b) the design touches code the architecture/baseline document describes ---
$docs = @()
$docFolder = Join-Path $Root 'docs'
if (Test-Path -LiteralPath $docFolder -PathType Container) {
    $docs = @(Get-ChildItem -LiteralPath $docFolder -File -Filter '*.md' |
            Where-Object { $_.Name -match '(?i)^architecture.*\.md$' -or $_.Name -match '(?i)baseline.*\.md$' })
}
$normalize = { param([string] $Value) (($Value.Trim() -replace '\\', '/') -replace '^(\./)+', '').TrimEnd('/') }
# `pwsh -File` hands "a,b" over as one string, so a comma splits here as well.
$touched = @($Path | ForEach-Object { $_ -split ',' } | Where-Object { $_.Trim() } | ForEach-Object { & $normalize $_ })
if ($touched.Count -eq 0) {
    & $add 'b' $false 'nicht geprueft (kein -Path angegeben)'
} elseif ($docs.Count -eq 0) {
    & $add 'b' $false "$($touched.Count) Pfad(e), kein Architektur-/Baseline-Dokument (docs/architecture*.md, docs/*baseline*.md)"
} else {
    $hit = [System.Collections.Generic.List[string]]::new()
    foreach ($doc in $docs) {
        $number = 0
        foreach ($text in [System.IO.File]::ReadAllLines($doc.FullName)) {
            $number++
            foreach ($span in [regex]::Matches($text, '`([^`]+)`')) {
                $token = & $normalize $span.Groups[1].Value
                if (-not $token) { continue }
                foreach ($candidate in $touched) {
                    if ($candidate -eq $token -or $candidate.StartsWith("$token/", [StringComparison]::Ordinal)) {
                        $hit.Add("$candidate in docs/$($doc.Name):$number")
                    }
                }
            }
        }
    }
    if ($hit.Count -gt 0) {
        & $add 'b' $true "$($hit.Count) Treffer: $($hit -join '; ')"
    } else {
        & $add 'b' $false "$($touched.Count) Pfad(e), kein Treffer in $(($docs | ForEach-Object Name) -join ', ')"
    }
}

# --- c) more than N merged PRs since the latest audit's commit -------------
$threshold = $settings.Threshold
if (-not $latest) {
    & $add 'c' $false 'nicht berechenbar: kein Audit, der Zaehlanker fehlt (Bedingung a gilt)'
} else {
    $commitLine = [regex]::Match((Get-Content -LiteralPath $latest.FullName -Raw), '(?m)^[\s>*-]*\*\*Commit:\*\*\s*`?([0-9a-fA-F]{7,40})')
    $sha = if ($commitLine.Success) { $commitLine.Groups[1].Value } else { '' }
    $known = $sha -and (& $git @('cat-file', '-e', "$sha^{commit}")).Exit -eq 0
    if (-not $sha) {
        & $add 'c' $true ('nicht berechenbar: {0} nennt keinen Commit in **Commit:** (Schwelle {1})' -f $latest.Name, $threshold) 'unknown'
    } elseif (-not $known) {
        & $add 'c' $true "nicht berechenbar: Commit $($sha.Substring(0, 7)) nicht in der History (Shallow Clone?) (Schwelle $threshold)" 'unknown'
    } else {
        $subject = (& $git @('log', '--first-parent', '--format=%s', "$sha..$countRef")).Line
        $count = @($subject | Where-Object { $_ -match $settings.PrSubjectPattern }).Count
        $over = $count -gt $threshold
        & $add 'c' $over "$count PRs seit $($sha.Substring(0, 7)) (Schwelle $threshold)" `
            "gezaehlt: Squash-Commits mit (#n) im Betreff und Merge-Commits 'Merge pull request #n', git log --first-parent $($sha.Substring(0, 7))..$Branch"
    }
}

$due = @($condition | Where-Object Due).Count -gt 0
$dueId = @($condition | Where-Object Due | ForEach-Object Id)

if ($Json) {
    [pscustomobject]@{
        Due         = $due
        Threshold   = $threshold
        LatestAudit = if ($latest) { $latest.Name } else { $null }
        Condition   = @($condition)
    } | ConvertTo-Json -Depth 4
    return
}

foreach ($item in $condition) {
    $mark = if ($item.Due) { 'faellig' } else { 'nicht faellig' }
    "$($item.Id): $($item.Figure) -> $mark"
    if ($item.Detail -and $item.Detail -ne 'unknown') { "   ($($item.Detail))" }
}
if ($due) { "Urteil: voller Audit faellig ($($dueId -join ', '))" } else { 'Urteil: kein voller Audit faellig (Schnell-Check genuegt)' }
