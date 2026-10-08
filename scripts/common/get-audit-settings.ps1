#Requires -Version 7.4

<#
.SYNOPSIS
    Resolve what the audit scripts count with: the PR threshold, the default
    branch and the pattern that tells a merged PR from any other commit.

.DESCRIPTION
    get-audit-due.ps1 and get-audit-worklist.ps1 both count merged pull requests
    against a threshold on the default branch. Each used to carry its own copy of
    the threshold regex, the default-branch lookup and the `(#n)` subject test,
    kept in step by a comment. Both now call this script, so one repository gives
    the same figures in both.

    - Threshold: 30, or the number of a line `Audit-Schwelle: <N>` in the
      repository's CLAUDE.md.
    - Branch: -Branch, else what origin/HEAD points at, else main, else master;
      $null when none exists.
    - CountRef: the ref to count on - origin's branch when it exists (the local
      one may lag or be absent), else the local one; $null when neither exists.
    - PrSubjectPattern: a commit subject counts as a merged PR when it ends in
      `(#<n>)` (squash merge) or starts with `Merge pull request #<n>` (merge
      commit).

    This script is deliberately SELF-CONTAINED - it imports no module, because
    it is mirrored into every consumer via scripts/common/.

.PARAMETER Root
    The repository root. Defaults to the repository this script sits in.

.PARAMETER Branch
    The branch to count on, instead of the default branch.

.INPUTS
    None.

.OUTPUTS
    [pscustomobject] with Threshold ([int]), Branch, CountRef and PrSubjectPattern.

.EXAMPLE
    (./scripts/common/get-audit-settings.ps1).Threshold

    The number of merged PRs after which a full audit is due.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [string] $Root,
    [string] $Branch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if (-not $Root) { $Root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent }

$threshold = 30
$claudeFile = Join-Path $Root 'CLAUDE.md'
if (Test-Path -LiteralPath $claudeFile -PathType Leaf) {
    $override = [regex]::Match((Get-Content -LiteralPath $claudeFile -Raw), '(?m)^[\s>*`-]*Audit-Schwelle:[*`]{0,2}\s*(\d+)')
    if ($override.Success) { $threshold = [int]$override.Groups[1].Value }
}

$refExists = {
    param([string] $Ref)
    & git -C $Root rev-parse --verify --quiet $Ref 2>$null | Out-Null
    $LASTEXITCODE -eq 0
}

$countRef = $null
try {
    if (-not $Branch) {
        $Branch = "$(& git -C $Root symbolic-ref --short refs/remotes/origin/HEAD 2>$null)".Trim() -replace '^origin/', ''
        if (-not $Branch) {
            $Branch = foreach ($candidate in 'main', 'master') {
                if (& $refExists "refs/heads/$candidate") { $candidate; break }
            }
        }
    }
    if ($Branch) {
        foreach ($candidate in "refs/remotes/origin/$Branch", "refs/heads/$Branch") {
            if (& $refExists $candidate) { $countRef = $candidate; break }
        }
    }
} catch {
    $countRef = $null
}
$global:LASTEXITCODE = 0

[pscustomobject]@{
    Threshold        = $threshold
    Branch           = if ($Branch) { "$Branch" } else { $null }
    CountRef         = $countRef
    PrSubjectPattern = '\(#\d+\)\s*$|^Merge pull request #\d+'
}
