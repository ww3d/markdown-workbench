<#
.SYNOPSIS
    The commit each ref names in a working copy, '' where it names none, in one git call for all refs.

.DESCRIPTION
    One `git cat-file --batch-check` answers every ref as `<ref>^{commit}`, the same reading as
    `git rev-parse --verify --quiet <ref>^{commit}` per ref, which cost one process start each
    (ww3d/playbook#427). Shared by test-pure-catch-up.ps1, test-applied-suggestions.ps1 and
    test-merge-ready.ps1.

    The refs go to git on stdin as UTF-8, whatever $OutputEncoding the caller set. A ref with a line
    break would shift the answers by a line and names no commit anyway: it gets '' without being
    asked. A git that cannot answer - no working copy at -Root, a native error made terminating by
    $PSNativeCommandUseErrorActionPreference - names no commit either.

    This script is deliberately SELF-CONTAINED - it imports no module, because it is mirrored into every
    consumer via scripts/common/.

.PARAMETER Root
    The working copy git asks.

.PARAMETER Ref
    The refs, in any form git takes (a branch, a short or full sha, HEAD~1).

.INPUTS
    None.

.OUTPUTS
    [string] one full sha or '' per ref, in the order of -Ref. $LASTEXITCODE is 0 afterwards.

.EXAMPLE
    $verdictSha, $headSha, $baseSha = & (Join-Path $PSScriptRoot 'resolve-git-commits.ps1') -Root . -Ref $Verdict, 'HEAD', 'origin/main'

    Three commits from one git call; a ref the working copy lacks gives ''.
#>

[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter(Mandatory)][string] $Root,
    [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Ref
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$withUtf8Output = Join-Path $PSScriptRoot 'invoke-utf8-output.ps1'
$asked = @($Ref | Where-Object { $_ -notmatch '[\r\n]' } | ForEach-Object { "$_^{commit}" })
try {
    $answer = @(if ($asked.Count -gt 0) {
            & $withUtf8Output {
                param($Spec)
                $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
                $Spec | & git -C $Root cat-file --batch-check 2>$null
            } $asked
        })
} catch {
    $answer = @()
}
$global:LASTEXITCODE = 0
$sha = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
if ($answer.Count -eq $asked.Count) {
    for ($i = 0; $i -lt $asked.Count; $i++) {
        if ("$($answer[$i])" -match '^([0-9a-f]{40,64}) commit \d+$') { $sha[$asked[$i]] = $Matches[1] }
    }
}
foreach ($item in $Ref) { if ($sha.ContainsKey("$item^{commit}")) { $sha["$item^{commit}"] } else { '' } }
