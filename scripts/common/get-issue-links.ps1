#Requires -Version 7.4

<#
.SYNOPSIS
    Look up every `owner/repo#N` reference in some text and put the target's
    state and title next to it.

.DESCRIPTION
    An on-demand lookup, deliberately not named check-*: scripts/check.ps1 runs
    every check-* script as a gate, and this one needs the network.

    A reference written from memory ("owner/repo#12 (the audit gate)") is
    wrong more often than a reference looked up. This script finds every
    `owner/repo#N` - and every Markdown or plain link to
    `github.com/<owner>/<repo>/(issues|pull)/<n>` - in the given files or text,
    resolves each one over REST (`gh api repos/<owner>/<repo>/issues/<n>`,
    which answers for issues and pull requests alike) and prints

        owner/repo#N | state | title

    State is open, closed, merged (a pull request) or `nicht aufloesbar` with
    the reason after it. Exit code 1 when one reference does not resolve.

    Each reference is resolved once per run (cache). The literal placeholder
    `owner/repo#N` is no reference. A bare `#N` names no repository and is not
    looked at. With -Offline nothing is resolved: the references are only
    listed (state `-`) and the exit code is 0.

.PARAMETER Path
    Files to scan, or folders scanned for *.md.

.PARAMETER Text
    Text to scan instead of, or beside, -Path.

.PARAMETER Offline
    List the references without asking the forge.

.PARAMETER Json
    Serialize the entries as JSON instead of printing them.

.INPUTS
    None.

.OUTPUTS
    [string] one line per reference; with -Json one object per reference
    (Reference, State, Title, Resolved, Where).

.EXAMPLE
    ./scripts/common/get-issue-links.ps1 -Path docs/decisions/2026-10-08T0055Z-x-decisions.md

.EXAMPLE
    ./scripts/common/get-issue-links.ps1 -Text 'siehe ww3d/playbook#351' -Offline
#>

[CmdletBinding()]
[OutputType([string])]
param(
    [string[]] $Path = @(),
    [string] $Text,
    [switch] $Offline,
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Path.Count -eq 0 -and -not $PSBoundParameters.ContainsKey('Text')) {
    throw 'Pass -Path or -Text.'
}

# owner/repo#N and issue/PR URL, the patterns find-closable-issues.ps1 reads with.
$referencePattern = & (Join-Path $PSScriptRoot 'get-reference-pattern.ps1')
$qualifiedPattern = $referencePattern.Qualified
$urlPattern = $referencePattern.Url


$source = [System.Collections.Generic.List[pscustomobject]]::new()
foreach ($item in $Path) {
    if (Test-Path -LiteralPath $item -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $item -Filter '*.md' -File -Recurse | Sort-Object FullName) {
            $source.Add([pscustomobject]@{ Name = $file.FullName; Text = (Get-Content -LiteralPath $file.FullName -Raw) })
        }
    } elseif (Test-Path -LiteralPath $item -PathType Leaf) {
        $source.Add([pscustomobject]@{ Name = $item; Text = (Get-Content -LiteralPath $item -Raw) })
    } else {
        throw "Path not found: '$item'."
    }
}
if ($PSBoundParameters.ContainsKey('Text')) { $source.Add([pscustomobject]@{ Name = '-Text'; Text = $Text }) }

# Reference -> first place it stands, in order of appearance.
$found = [ordered]@{}
foreach ($entry in $source) {
    $number = 0
    foreach ($line in ("$($entry.Text)" -split "`r?`n")) {
        $number++
        foreach ($pattern in $qualifiedPattern, $urlPattern) {
            foreach ($match in [regex]::Matches($line, $pattern)) {
                $slug = $match.Groups[1].Value
                if ($slug -ceq 'owner/repo') { continue }
                $key = "$slug#$($match.Groups[2].Value)"
                if (-not $found.Contains($key)) { $found[$key] = "$($entry.Name):$number" }
            }
        }
    }
}

$cache = @{}
$resolve = {
    param([string] $Slug, [string] $Number)
    $answer = @(& gh api "repos/$Slug/issues/$Number" 2>&1)
    $exit = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($exit -ne 0) {
        $reason = (($answer | ForEach-Object { "$_" }) -join ' ').Trim() -replace '\s+', ' '
        return [pscustomobject]@{ Resolved = $false; State = 'nicht aufloesbar'; Title = $reason }
    }
    $issue = ($answer | ForEach-Object { "$_" }) -join "`n" | ConvertFrom-Json
    $isPull = $issue.PSObject.Properties['pull_request'] -and $issue.pull_request
    $state = if ($isPull -and $issue.pull_request.PSObject.Properties['merged_at'] -and $issue.pull_request.merged_at) { 'merged' }
    else { "$($issue.state)" }
    [pscustomobject]@{ Resolved = $true; State = $state; Title = "$($issue.title)" }
}

$result = foreach ($key in $found.Keys) {
    $slug, $number = $key -split '#', 2
    if ($Offline) {
        $answer = [pscustomobject]@{ Resolved = $true; State = '-'; Title = '' }
    } else {
        if (-not $cache.ContainsKey($key)) { $cache[$key] = & $resolve $slug $number }
        $answer = $cache[$key]
    }
    [pscustomobject]@{
        Reference = $key; State = $answer.State; Title = $answer.Title; Resolved = $answer.Resolved; Where = $found[$key]
    }
}
$result = @($result)

if ($Json) {
    ConvertTo-Json -InputObject $result -Depth 3
} else {
    foreach ($item in $result) { "$($item.Reference) | $($item.State) | $($item.Title)" }
    if ($result.Count -eq 0) { 'Keine Verweise der Form owner/repo#N gefunden.' }
}
if (@($result | Where-Object { -not $_.Resolved }).Count -gt 0) { exit 1 }
