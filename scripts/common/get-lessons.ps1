#Requires -Version 7.4

<#
.SYNOPSIS
    Print the lessons of .agents/lessons.md that apply to one role.

.DESCRIPTION
    .agents/lessons.md holds one entry per lesson, in this form:

        ## L04 - <short title>

        gilt fuer: dev, review

        <one paragraph>

    (the dash after the number is an em dash). A skill loads only the lessons
    of its own role instead of the whole file: an entry matches when its
    `gilt fuer` list names the role or `alle`. The entries come out verbatim,
    heading to last text line, separated by one blank line; no match prints
    nothing.

    A role the file does not know - neither one of the standard roles nor
    named in any `gilt fuer` line - is an error (exit 1) with the list of known
    roles, so a typo does not read as "no lessons apply". An entry without a
    `gilt fuer` line matches no role; it is reported as a warning.

.PARAMETER Role
    The role to load the lessons for, e.g. dev, review, design, audit,
    controller. Case-insensitive.

.PARAMETER Path
    The lessons file. Defaults to .agents/lessons.md of the repository this
    script sits in.

.INPUTS
    None.

.OUTPUTS
    [string] The matching entries.

.EXAMPLE
    pwsh scripts/common/get-lessons.ps1 -Role review
#>

[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Role,
    [string] $Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Path) {
    $Path = Join-Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) '.agents/lessons.md'
}
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Lessons file not found at '$Path'." }

# The em dash as a code point: every script in this directory is ASCII. A plain hyphen is accepted too.
$headingPattern = '^##\s+(?<id>L\S+)\s+(?:' + [char]0x2014 + '|--?)\s+(?<title>.+?)\s*$'
$scopePattern = '^gilt fuer:\s*(?<list>.*?)\s*$'
# Roles that exist whatever the file holds, so an unused one is not "unknown".
$standardRole = @('alle', 'dev', 'review', 'design', 'audit', 'controller', 'pfleger')

$entry = [System.Collections.Generic.List[pscustomobject]]::new()
$current = $null
$inFence = $false
foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
    if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence }
    if (-not $inFence -and $line -match $headingPattern) {
        $current = [pscustomobject]@{
            Id = $Matches['id']; Line = [System.Collections.Generic.List[string]]::new(); Scope = $null
        }
        $entry.Add($current)
    }
    if ($current) {
        $current.Line.Add($line)
        if ($null -eq $current.Scope -and $line -match $scopePattern) {
            $current.Scope = @($Matches['list'] -split '[,;]' | ForEach-Object { $_.Trim().ToLowerInvariant() } |
                    Where-Object { $_ })
        }
    }
}

foreach ($item in $entry) {
    if ($null -eq $item.Scope) { Write-Warning "Lesson $($item.Id) has no 'gilt fuer' line; it matches no role." }
}

$wanted = $Role.Trim().ToLowerInvariant()
$known = @($standardRole + @($entry | Where-Object { $null -ne $_.Scope } | ForEach-Object { $_.Scope }) |
        Sort-Object -Unique)
if ($wanted -notin $known) {
    Write-Error "Unknown role '$Role'. Known roles: $($known -join ', ')." -ErrorAction Continue
    exit 1
}

$block = foreach ($item in $entry) {
    if ($null -eq $item.Scope) { continue }
    if ('alle' -in $item.Scope -or $wanted -in $item.Scope) {
        (($item.Line -join "`n").TrimEnd())
    }
}
if ($block) { $block -join "`n`n" }
