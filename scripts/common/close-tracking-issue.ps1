#Requires -Version 7.4

<#
.SYNOPSIS
    After a green merge gate and the merge: close the tracking issue the pull
    request names - but only if it is closable.

.DESCRIPTION
    .agents/rules/carrier.md, section "Tracking Issue", has whoever merges
    close the tracking issue. This script does it in one step and keeps the
    closing rule out of the hands of memory: the issues are the ones named by
    `Refs #N` / `Closes #N` (and the other keywords of the PR description
    rule, at a line start) in the PR body; each one is judged by
    find-closable-issues.ps1 -Pr (no open checkbox, no Sub-Issue open, nothing
    in the repository that still names it as its carrier, no marker to
    re-hang first). A closable issue gets the closing comment that script
    wrote and is closed as completed. An issue that is not closable stays
    open and the output says why.

    Refuses to act (exit 1) when the PR is not merged, when the merge commit is
    not in the HEAD of -Root (the carrier search would read a tree from before
    the merge: NOT VERIFIED), when the repository cannot be searched (SOURCE
    UNAVAILABLE), or when a write fails. An issue
    that stays open for a reason is no error: exit 0. A PR body that names no
    issue of this repository closes nothing and says so.

    Supports -WhatIf / -Confirm: the judgement runs, the comment and the close
    do not.

.PARAMETER Repo
    owner/name of the repository.

.PARAMETER Pr
    Number of the merged pull request.

.PARAMETER Root
    A directory inside a checkout of the repository at the merged state, which
    find-closable-issues.ps1 searches for carrier formulas. Defaults to the
    repository this script sits in.

.INPUTS
    None.

.OUTPUTS
    [string] one line per named issue: closed, would close, or stays open and why.

.EXAMPLE
    ./scripts/common/close-tracking-issue.ps1 -Repo ww3d/playbook -Pr 352 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
[OutputType([string])]
param(
    [Parameter(Mandatory)][ValidatePattern('^[\w.-]+/[\w.-]+$')][string] $Repo,
    [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int] $Pr,
    [string] $Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$finder = Join-Path $PSScriptRoot 'find-closable-issues.ps1'
if (-not (Test-Path -LiteralPath $finder -PathType Leaf)) { throw 'find-closable-issues.ps1 not found beside this script.' }

$restItems = Join-Path $PSScriptRoot 'get-rest-items.ps1'

$pull = @(& $restItems -Endpoint "repos/$Repo/pulls/$Pr")[0]
if (-not $pull.merged) {
    Write-Output "PR #$Pr ist nicht gemergt - nichts geschlossen. Erst nach dem Merge ausfuehren."
    exit 1
}

# One keyword per line, at its start (.agents/rules/pr.md, "PR / MR Description").
$keyword = '(?im)^[ \t]*(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)[ \t]*:?[ \t]+(?:(?<repo>[\w.-]+/[\w.-]+))?#(?<n>\d+)\b'
$named = [System.Collections.Generic.SortedSet[int]]::new()
foreach ($match in [regex]::Matches("$($pull.body)", $keyword)) {
    $slug = $match.Groups['repo'].Value
    if (($slug -and $slug -ne $Repo) -or [int]$match.Groups['n'].Value -eq $Pr) { continue }
    [void]$named.Add([int]$match.Groups['n'].Value)
}
if ($named.Count -eq 0) {
    Write-Output "PR #$Pr nennt kein Tracking Issue dieses Repos (Refs/Closes #N) - nichts zu schliessen."
    exit 0
}

# The carrier search reads the committed tree at -Root: judged against a HEAD from before the
# merge it would miss a carrier the merge added, so the merge commit must be in that HEAD.
$searchRoot = if ($Root) { $Root } else { Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent }
$mergeSha = if ($pull.PSObject.Properties['merge_commit_sha']) { "$($pull.merge_commit_sha)" } else { '' }
$mergeInHead = $false
if ($mergeSha) {
    try {
        & git -C $searchRoot merge-base --is-ancestor $mergeSha HEAD 2>$null
        $mergeInHead = $LASTEXITCODE -eq 0
    } catch {
        $mergeInHead = $false
    }
    $global:LASTEXITCODE = 0
}
if (-not $mergeInHead) {
    $what = if ($mergeSha) { "der Merge-Commit $($mergeSha.Substring(0, [Math]::Min(7, $mergeSha.Length))) liegt nicht in HEAD von '$searchRoot'" } else { 'die PR nennt keinen Merge-Commit' }
    Write-Output "NOT VERIFIED - nichts geschlossen: $what. Erst den Stand nach dem Merge holen (git pull)."
    exit 1
}

$arguments = @('-NoProfile', '-File', $finder, '-Repo', $Repo, '-Pr', "$Pr", '-Json')
if ($Root) { $arguments += @('-Root', $Root) }
$pwsh = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$pwshPath = if ($pwsh) { $pwsh.Source } else { [System.Environment]::ProcessPath }
$raw = & $pwshPath @arguments 2>&1 | Out-String
$finderExit = $LASTEXITCODE
$global:LASTEXITCODE = 0
try { $entry = @($raw | ConvertFrom-Json) }
catch { Write-Output "find-closable-issues.ps1 lieferte keine lesbare Antwort (Exit $finderExit): $($raw.Trim())"; exit 1 }
$unavailable = @($entry | Where-Object Source -EQ 'unavailable')
if ($finderExit -ne 0 -or $unavailable.Count -gt 0) {
    $why = if ($unavailable.Count -gt 0) { ($unavailable | ForEach-Object Note) -join '; ' } else { "Exit $finderExit" }
    Write-Output "SOURCE UNAVAILABLE - nichts geschlossen: $why"
    exit 1
}

$failed = $false
foreach ($number in $named) {
    $label = "#$number"
    $mine = @($entry | Where-Object { $_.Issue -eq $label })
    $judge = $mine | Where-Object Source -EQ 'issue' | Select-Object -First 1
    $rehang = $mine | Where-Object Source -EQ 'rehang-first' | Select-Object -First 1
    if (-not $judge) {
        $skip = $mine | Select-Object -First 1
        Write-Output "$label bleibt offen: $(if ($skip) { "$($skip.Source) - $($skip.Note)" } else { 'von find-closable-issues.ps1 nicht beurteilt' })"
        continue
    }
    if ($rehang) {
        Write-Output "$label bleibt offen: ein Marker nennt es als Traeger (erst umhaengen): $($rehang.Location -join ', ')"
        continue
    }
    switch ($judge.Result) {
        'closable' {
            if ($PSCmdlet.ShouldProcess("$Repo$label", 'comment and close as completed')) {
                $commentFile = New-TemporaryFile
                try {
                    Set-Content -LiteralPath $commentFile -Value $judge.Note -Encoding utf8NoBOM
                    & gh api -X POST "repos/$Repo/issues/$number/comments" -F "body=@$commentFile" > $null
                    if ($LASTEXITCODE -ne 0) { throw "comment on $label failed (gh exited $LASTEXITCODE)" }
                    & gh api -X PATCH "repos/$Repo/issues/$number" -f state=closed -f state_reason=completed > $null
                    if ($LASTEXITCODE -ne 0) { throw "closing $label failed (gh exited $LASTEXITCODE)" }
                    Write-Output "$label geschlossen - $($judge.Title)"
                } catch {
                    $failed = $true
                    Write-Output "$label FEHLER: $($_.Exception.Message)"
                } finally {
                    Remove-Item -LiteralPath $commentFile -Force -ErrorAction SilentlyContinue
                    $global:LASTEXITCODE = 0
                }
            } else {
                Write-Output "$label wuerde geschlossen (closable) - $($judge.Title)"
            }
        }
        'open-boxes' { Write-Output "$label bleibt offen: $($judge.Count) offene Checkbox(en)/Sub-Issue(s)" }
        'still-carried-by' { Write-Output "$label bleibt offen: noch Traeger an $($judge.Location -join ', ')" }
        'closed-clean' {
            if ($judge.Count -gt 0) {
                Write-Output "$label ist geschlossen und kein Traeger-Verweis nennt es mehr, aber $($judge.Count) Checkbox(en) sind noch offen - von Hand beurteilen"
            } else {
                Write-Output "$label ist geschlossen, kein Traeger-Verweis nennt es mehr."
            }
        }
        'no-reference' { Write-Output "$label bleibt offen: weder Checkbox noch Sub-Issue - kein Tracking Issue im Sinne der Regel, von Hand beurteilen" }
        default { Write-Output "$label bleibt offen: $($judge.Result)" }
    }
}
if ($failed) { exit 1 }
