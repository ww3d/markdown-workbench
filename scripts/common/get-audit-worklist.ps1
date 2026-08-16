#Requires -Version 7.4

<#
.SYNOPSIS
    Build the work list the state audit walks: status markers, open tracking
    issue points, and every TODO / HACK / FIXME with its carrier reference.

.DESCRIPTION
    AGENTS.md, section "State Audit", requires an audit before every new slice,
    and the `state-audit` skill runs it. Its first step is not judgement but
    collection - and collection done from memory leaves out exactly the source
    nobody holds in their head. This script does the collecting.

    Three sources, each emitted with its own Source value so the audit can group
    them:

    * marker - every [erfuellt] / [teilweise] / [geplant] statement in the
      repository's Markdown, with path and line. These are target-vs-actual
      displays, not carriers; the audit is what carries each one into a tracking
      issue.
    * tracking-issue - the body of every open tracking issue, one entry per
      checklist line. Needs `gh`; when `gh` is missing or unauthenticated the
      source is reported as unavailable rather than silently empty, because an
      empty source and a skipped source look identical in a report.
    * marker-comment - every TODO / HACK / FIXME in code or in prose, with
      whether it carries a carrier reference. One without a reference is itself
      a finding (AGENTS.md, section "Carrier Requirement").

    This script is deliberately SELF-CONTAINED - it imports no module, because
    it is mirrored into every consumer via scripts/common/.

    It only ever READS. Correcting a marker or editing an issue body is the
    audit's job, not this script's.

.PARAMETER Path
    Repository root to scan. Defaults to the repository this script sits in.

.PARAMETER Repo
    owner/name of the repository whose open tracking issues are read. Defaults
    to whatever `gh` resolves for the checkout.

.PARAMETER Label
    Issue label that marks a tracking issue. Default 'tracking'.

.PARAMETER SkipIssue
    Collect the two local sources only and do not call `gh` at all.

.PARAMETER Json
    Serialize the work list as JSON instead of emitting objects.

.INPUTS
    None.

.OUTPUTS
    [pscustomobject] per entry with Source, Path, Line, Text and Note.

.EXAMPLE
    ./scripts/common/get-audit-worklist.ps1

    The full work list for the repository this script sits in.

.EXAMPLE
    ./scripts/common/get-audit-worklist.ps1 -SkipIssue -Json

    Markers and TODO comments only, as a JSON document - the offline half.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [string] $Path,
    [string] $Repo,
    [string] $Label = 'tracking',
    [switch] $SkipIssue,
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Path) { $Path = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent }
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Repository root not found at '$Path'."
}
$root = (Resolve-Path -LiteralPath $Path).ProviderPath

$markerPattern = '\[(erfuellt|teilweise|geplant)\]'
# A marker is `TODO:`, `HACK:` or `FIXME:`, optionally with a parenthesised
# reference first (`TODO(#42):`). Three things make this pattern strict on
# purpose, because a work list full of false positives is worse than one that
# misses an unconventionally written marker - nobody walks a list they have
# learned to skim:
#   * UPPERCASE only, matched with -cmatch. PowerShell's -match is
#     case-INSENSITIVE, so a plain `\b(TODO|HACK|FIXME)\b` also catches the
#     lowercase `todo` inside the Conventional-Comments vocabulary next door in
#     measure-review-comment.ps1.
#   * The trailing colon. Without it, every sentence ABOUT markers matches - the
#     rule in AGENTS.md ("A `TODO`, `HACK`, or `FIXME` ... carries a reference"),
#     this script's own help, and the state-audit skill describing its sources.
#     Ten of twelve hits in the first run were of that kind.
#   * \b at the front so `NOTODO:` is not a marker.
#   * A leading backtick disqualifies the match: inside `TODO:` the word is
#     MARKUP quoting a marker, not one. That is what this very comment does, and
#     what a rule text does when it names the convention it defines.
$commentPattern = '(?<!`)\b(TODO|HACK|FIXME)(\([^)]*\))?\s*:'
# A carrier reference is an issue number or a repo-qualified one. Deliberately
# loose: the audit judges whether the target really carries the point; this only
# separates "names something" from "names nothing".
$carrierPattern = '(?:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+)?#\d+'

$skipDirectory = @('.git', 'node_modules', 'bin', 'obj', '_build', '_buildtools', 'dist')
# The logs are immutable history: a marker quoted there describes a past state.
$exemptPrefix = @('docs/decisions/')

$entries = [System.Collections.Generic.List[pscustomobject]]::new()

$relativeOf = {
    param($FullName)
    [System.IO.Path]::GetRelativePath($root, $FullName).Replace('\', '/')
}

# Tracked files only, where git can say so. Generated output is not repository
# text: `testResults.xml` from `Invoke-Pester -CI` is gitignored and still landed
# in the first work list, because a test-case DESCRIPTION quoted the word TODO.
# The rest of the playbook tooling classifies through git for the same reason
# (Test-VersionBump reads `git diff`), so the fallback below is only for a
# consumer that is not a git checkout at all.
$tracked = & git -C $root ls-files 2>$null
if ($LASTEXITCODE -eq 0 -and $tracked) {
    $candidates = @($tracked | ForEach-Object {
            $full = Join-Path $root $_
            if (Test-Path -LiteralPath $full -PathType Leaf) { Get-Item -LiteralPath $full -Force }
        })
} else {
    $candidates = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)
}
$global:LASTEXITCODE = 0

$candidates = @($candidates | Where-Object {
        $relative = & $relativeOf $_.FullName
        -not ($relative.Split('/') | Where-Object { $_ -in $skipDirectory })
    })

foreach ($file in $candidates) {
    $relative = & $relativeOf $file.FullName
    $isMarkdown = $file.Name -like '*.md'
    $isExempt = [bool]($exemptPrefix | Where-Object { $relative.StartsWith($_, [StringComparison]::Ordinal) })
    if ($isExempt) { continue }

    # Binary files have no lines worth reading, and reading them as text is slow
    # and noisy. -ErrorAction on the read, not a suffix allowlist: a repository
    # may put source in any extension.
    $lines = @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)
    if (-not $lines) { continue }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $number = $i + 1

        if ($isMarkdown) {
            foreach ($hit in [regex]::Matches($line, $markerPattern)) {
                $entries.Add([pscustomobject]@{
                        Source = 'marker'
                        Path   = $relative
                        Line   = $number
                        Text   = $line.Trim()
                        Note   = $hit.Groups[1].Value
                    })
            }
        }

        if ($line -cmatch $commentPattern) {
            $carried = $line -match $carrierPattern
            $entries.Add([pscustomobject]@{
                    Source = 'marker-comment'
                    Path   = $relative
                    Line   = $number
                    Text   = $line.Trim()
                    Note   = if ($carried) { 'carrier referenced' } else { 'NO CARRIER REFERENCE' }
                })
        }
    }
}

if (-not $SkipIssue) {
    $arguments = @('issue', 'list', '--state', 'open', '--label', $Label,
        '--json', 'number,title,body', '--limit', '100')
    if ($Repo) { $arguments += @('--repo', $Repo) }

    # Catch-and-degrade, and it says so: gh may be absent, unauthenticated, or
    # blocked server-side. An audit that reported nothing here would look like an
    # audit that found nothing.
    try {
        $raw = & gh @arguments 2>$null
        if ($LASTEXITCODE -ne 0) { throw "gh exited $LASTEXITCODE" }
        foreach ($issue in ($raw | ConvertFrom-Json)) {
            foreach ($line in ($issue.body -split "`r?`n")) {
                if ($line -notmatch '^\s*[-*]\s*\[( |x|X)\]\s*(.+)$') { continue }
                if ($Matches[1] -ne ' ') { continue }
                $entries.Add([pscustomobject]@{
                        Source = 'tracking-issue'
                        Path   = "#$($issue.number)"
                        Line   = 0
                        Text   = $Matches[2].Trim()
                        Note   = $issue.title
                    })
            }
        }
    } catch {
        # Display only, and skipped under -Json: PowerShell renders the WARNING
        # stream on stdout, so under -Json it would sit inside the JSON document
        # and break every machine consumer - precisely when -Json is used. The
        # information is not lost either way; the SOURCE UNAVAILABLE entry below
        # carries it in the data, which is where a caller reads it.
        if (-not $Json) {
            Write-Warning "tracking issues not read: $($_.Exception.Message). Report this source as NOT VERIFIED."
        }
        $entries.Add([pscustomobject]@{
                Source = 'tracking-issue'
                Path   = ''
                Line   = 0
                Text   = ''
                Note   = 'SOURCE UNAVAILABLE - not verified'
            })
    }
}

$results = @($entries)

if ($Json) {
    ConvertTo-Json -InputObject $results -Depth 5
} else {
    $results
}
