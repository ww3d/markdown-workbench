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

    - Threshold: 30, or the number of a line `Audit threshold: <N>` in the
      repository's CLAUDE.md.
    - FullRun, GuardClasses, FormatCheck, FilteredRun: the text of the fields
      `**Full run:**`, `**Guard classes:**`, `**Format check:**` and
      `**Filtered run:**` of the CLAUDE.md section "Test Runs and Audit" (a
      field reaches to the next bullet, heading or blank line); $null when
      absent.
    - Platforms: the platform names listed after `platforms:` in the full-run
      field, split by the platform rule below - "Windows (pwsh 7.4, Git
      Bash) and Linux (...)" gives Windows, Linux; empty when none is named.

    THE PLATFORM RULE, one for every platform list - this field and the
    platform field of a run line, which test-merge-ready.ps1 splits through
    -PlatformList: backticks and parenthesised remarks dropped, the list ended
    at the first sentence end (a `.` before a blank or the end, so prose after
    it names no platform), split at `,` `+` `/` `&` and the words "and" /
    "und", the first word of each item; names compare case-insensitively, a
    repeat is dropped.

    The old German forms - `Audit-Schwelle`, `Voller Lauf`, `Waechterklassen`,
    `Plattformen:` - are read until playbook 25.0.0 (ww3d/playbook#356).
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

.PARAMETER PlatformList
    A platform list to split by the platform rule; the script then returns
    only the names ([string[]]) and reads no repository.

.INPUTS
    None.

.OUTPUTS
    [pscustomobject] with Threshold ([int]), Branch, CountRef, PrSubjectPattern,
    FullRun, Platforms ([string[]]), FormatCheck, FilteredRun and GuardClasses;
    with -PlatformList the names as [string].

.EXAMPLE
    (./scripts/common/get-audit-settings.ps1).Threshold

    The number of merged PRs after which a full audit is due.

.EXAMPLE
    ./scripts/common/get-audit-settings.ps1 -PlatformList 'Windows (pwsh 7.4)/Linux'

    Windows and Linux.
#>

[CmdletBinding(DefaultParameterSetName = 'Settings')]
[OutputType([pscustomobject], ParameterSetName = 'Settings')]
[OutputType([string], ParameterSetName = 'Split')]
param(
    [Parameter(ParameterSetName = 'Settings')][string] $Root,
    [Parameter(ParameterSetName = 'Settings')][string] $Branch,
    [Parameter(Mandatory, ParameterSetName = 'Split')][AllowEmptyString()][string] $PlatformList
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# The platform rule (help, "THE PLATFORM RULE"): the one split for the full-run field and a run line's platform field.
$splitPlatform = {
    param([string] $Text)
    $text = $Text -replace '`', ''
    while ($text -match '\([^()]*\)') { $text = $text -replace '\([^()]*\)', ' ' }
    # After the remarks are gone, so a full stop inside one ("pwsh 7.4. Git Bash") does not end the list.
    $text = ($text -split '\.(?=\s|$)', 2)[0]
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($item in ($text -split '(?i)[,+/&]|\band\b|\bund\b')) {
        $word = [regex]::Match($item, '[\p{L}\p{N}][\p{L}\p{N}_.-]*')
        if (-not $word.Success) { continue }
        $name = $word.Value.TrimEnd('.')
        # -notcontains compares case-insensitively.
        if ($names -notcontains $name) { $names.Add($name) }
    }
    [string[]]$names.ToArray()
}
if ($PSCmdlet.ParameterSetName -eq 'Split') {
    & $splitPlatform $PlatformList
    return
}

if (-not $Root) { $Root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent }

$threshold = 30
$claudeText = ''
$claudeFile = Join-Path $Root 'CLAUDE.md'
if (Test-Path -LiteralPath $claudeFile -PathType Leaf) {
    $claudeText = (Get-Content -LiteralPath $claudeFile -Raw) -replace "`r`n", "`n"
    # old German forms read until playbook 25.0.0 (ww3d/playbook#356): Audit-Schwelle
    $override = [regex]::Match($claudeText, '(?mi)^[\s>*`-]*(?:Audit threshold|Audit-Schwelle):[*`]{0,2}\s*(\d+)')
    if ($override.Success) { $threshold = [int]$override.Groups[1].Value }
}

# The text of a `- **<Name>:** ...` field of the test-run section: everything after the label up to the next
# bullet, heading or blank line, its lines joined; $null when the field is absent or empty.
$fieldText = {
    param([string[]] $Name)
    $label = ($Name | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $match = [regex]::Match($claudeText, "(?mi)^[ \t>]*[-*][ \t]+\*\*(?:$label):\*\*(?<rest>[^\n]*(?:\n(?![ \t]*(?:[-*+][ \t]|#|>?[ \t]*\n|$))[^\n]*)*)")
    if (-not $match.Success) { return $null }
    $text = ($match.Groups['rest'].Value -replace '\s+', ' ').Trim()
    if ($text) { $text } else { $null }
}
# old German forms read until playbook 25.0.0 (ww3d/playbook#356): Voller Lauf, Waechterklassen
$fullRun = & $fieldText @('Full run', 'Voller Lauf')
$guardClasses = & $fieldText @('Guard classes', 'Waechterklassen')
$formatCheck = & $fieldText @('Format check')
$filteredRun = & $fieldText @('Filtered run')

# The platforms named after `platforms:` in the full-run field, split by the platform rule.
# old German forms read until playbook 25.0.0 (ww3d/playbook#356): Plattformen:
$platforms = [string[]]@()
if ($fullRun) {
    $list = [regex]::Match($fullRun, '(?i)\b(?:platforms|Plattformen):\s*(?<list>.+)$')
    if ($list.Success) { $platforms = [string[]]@(& $splitPlatform $list.Groups['list'].Value) }
}

# Native output decoded as UTF-8, whatever the console code page: `& $withUtf8Output { <call> } <arguments>`.
$withUtf8Output = Join-Path $PSScriptRoot 'invoke-utf8-output.ps1'

$refExists = {
    param([string] $Ref)
    & git -C $Root rev-parse --verify --quiet $Ref 2>$null | Out-Null
    $LASTEXITCODE -eq 0
}

$countRef = $null
try {
    if (-not $Branch) {
        $Branch = "$(& $withUtf8Output { & git -C $Root symbolic-ref --short refs/remotes/origin/HEAD 2>$null })".Trim() -replace '^origin/', ''
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
    FullRun          = $fullRun
    Platforms        = $platforms
    FormatCheck      = $formatCheck
    FilteredRun      = $filteredRun
    GuardClasses     = $guardClasses
}
