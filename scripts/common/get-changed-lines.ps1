#Requires -Version 7.6

<#
.SYNOPSIS
    The lines a checkout adds or changes against the merge base with a ref, and the paths it deletes
    or renames away - the one changed-lines reading the checks of this directory share.

.DESCRIPTION
    `git diff -U0` of the merge base of HEAD and -BaseRef against the working tree (commits, staged
    and unstaged changes of tracked files; a new file counts with all its lines) is read into the
    new-side line numbers per file. A second `git diff --name-status` lists the paths the diff
    deletes or renames away, each with its folders.

    Without a merge base - not a git checkout, or the ref is missing - the script emits nothing and
    the caller decides: check-terminology.ps1 warns and checks every line, test-question-markers.ps1
    fails with a call error.

    This script is deliberately SELF-CONTAINED - it imports no module, because it is mirrored into
    every consumer via scripts/common/.

.PARAMETER Root
    The working copy to read. Defaults to the current directory.

.PARAMETER BaseRef
    The ref compared against, through its merge base with HEAD. Defaults to origin/main.

.PARAMETER Filter
    Wildcard patterns (-like) the repo-relative path with / must match to count under Lines, for
    example '*.md'. Defaults to every tracked file. Removed is never filtered.

.INPUTS
    None.

.OUTPUTS
    [pscustomobject] with MergeBase, Lines (a hashtable: repo-relative path with / to a HashSet[int]
    of new-side line numbers) and Removed (a HashSet[string] of deleted or renamed-away paths); or
    nothing when there is no merge base.

.EXAMPLE
    $scope = ./scripts/common/get-changed-lines.ps1 -Filter '*.md'
    $scope.Lines['docs/playbook-ops.md']

    The new-side line numbers the checkout changes in that file.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [string] $Root = (Get-Location).ProviderPath,
    [string] $BaseRef = 'origin/main',
    [string[]] $Filter = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PSNativeCommandUseErrorActionPreference = $false
$withUtf8Output = Join-Path $PSScriptRoot 'invoke-utf8-output.ps1'

$mergeBase = $null
try {
    $mergeBase = & $withUtf8Output { & git -C $Root merge-base $BaseRef HEAD 2>$null }
    if ($LASTEXITCODE -ne 0) { $mergeBase = $null }
} catch { $mergeBase = $null }
$global:LASTEXITCODE = 0
if (-not $mergeBase) { return }
$mergeBase = "$mergeBase".Trim()

$scope = [pscustomobject]@{
    MergeBase = $mergeBase
    Lines     = @{}
    Removed   = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
}
$gitDiff = @('-c', 'core.quotepath=off', '-C', $Root, 'diff', '-M', '--relative', '--no-color', '--no-ext-diff')
$diff = & $withUtf8Output { & git @gitDiff -U0 $mergeBase 2>$null }
$inHeader = $false
$current = $null
foreach ($row in $diff) {
    if ($row.StartsWith('diff --git ', [StringComparison]::Ordinal)) { $inHeader = $true; $current = $null }
    elseif ($inHeader -and $row -match '^\+\+\+ b/(.+?)\t?$') {
        $current = $Matches[1]
        if ($Filter.Count -and -not ($Filter | Where-Object { $current -like $_ })) { $current = $null; continue }
        $scope.Lines[$current] = [System.Collections.Generic.HashSet[int]]::new()
    } elseif ($row.StartsWith('@@', [StringComparison]::Ordinal)) {
        $inHeader = $false
        if ($current -and $row -match '^@@ -\S+ \+(\d+)(?:,(\d+))? @@') {
            $count = if ($Matches[2]) { [int]$Matches[2] } else { 1 }
            for ($n = [int]$Matches[1]; $n -lt [int]$Matches[1] + $count; $n++) {
                [void]$scope.Lines[$current].Add($n)
            }
        }
    }
}
$status = & $withUtf8Output { & git @gitDiff --name-status $mergeBase 2>$null }
foreach ($row in $status) {
    $part = $row -split "`t"
    if ($part.Count -lt 2 -or $part[0] -notmatch '^[DR]') { continue }
    # Its folders count too: a link to a folder the diff empties points at a path the diff removes.
    for ($gone = $part[1]; $gone; $gone = $gone.Substring(0, [Math]::Max(0, $gone.LastIndexOf('/')))) {
        [void]$scope.Removed.Add($gone)
    }
}
$global:LASTEXITCODE = 0
$scope
