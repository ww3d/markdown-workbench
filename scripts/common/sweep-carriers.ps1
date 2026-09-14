#Requires -Version 7.4

<#
.SYNOPSIS
    Find closed tracking issues that still carry an open checkbox, and open
    references to a carrier issue that has since been closed.

.DESCRIPTION
    ww3d/playbook#158 asked for a recurring run of what ww3d did by hand on
    2026-08-06: walk merged PR bodies for open points, match each against
    issues / roadmap.md / backlog.md / architecture status markers, and report
    a point whose named carrier does not really carry it. The FULL scope of
    #158 is deliberately NOT what this script builds - scanning PR bodies stays
    out (Entscheidung 21, docs/decisions/2026-09-13T1625-playbook-buendel-scheibe-decisions.md).
    What ships here is the narrower, mechanically checkable half of the same
    idea, over issues alone:

    * checkbox - a CLOSED issue (label `tracking` by default, or every closed
      issue under -AllClosed) whose body still carries an unticked `- [ ]`
      line. The same shape .agents/rules/carrier.md, section "Tracking Issue",
      warns about: a closed tracking issue is the worst carrier there is,
      because it looks like a finished one. The checklist pattern is the same
      one get-audit-worklist.ps1 already uses for OPEN issues
      (`^\s*[-*]\s*\[( |x|X)\]\s*(.+)$`) - here it runs over CLOSED ones
      instead.
    * carrier-ref - a bare `#N` reference on an UNTICKED checklist line
      (`- [ ] ... #N`) inside the body of an issue carrying -Label (or of
      every issue under -AllClosed, open and closed alike) where the
      referenced issue #N is itself closed. A point naming a closed issue as
      its carrier has, in effect, no carrier at all. Restricted to unticked
      checkbox lines specifically, not merely "not a ticked one": a plain
      PROSE line naming a closed issue is usually a quotation of past history
      ("- **#163** - Punkt 1, geschlossen mit dem Merge"), which
      .agents/rules/carrier.md, section "Carrier Requirement", explicitly does
      not count as a carrier reference - a point is a checkbox line. Measured
      against this repository's own #230: 27 of 104 raw hits were an
      already-ticked line naming the issue that carried an already-delivered
      point (not a defect either), and every one of the 76 that remained
      after excluding those was prose, none a real defect - the
      "SOURCE YIELDED NOTHING"-style noise get-audit-worklist.ps1 argues
      against in its own source-report.

    Two `gh` calls total, not one per referenced issue: the first lists the
    source issues (their body, state and closedAt), the second lists every
    issue's number and state in one shot, which becomes the lookup table the
    carrier-ref check reads instead of a `gh issue view` per reference. Cross-
    repo references (`owner/repo#N`) and the `GH-N` short form are out of scope
    on purpose - checking either would need its own `gh` call per distinct
    repository named, which the bundled lookup does not cover.

    This script is deliberately SELF-CONTAINED - it imports no module, because
    it is mirrored into every consumer via scripts/common/.

    It only ever READS; filing a carrier or closing an issue is the sweep's
    result, not this script's job.

.PARAMETER Repo
    owner/name of the repository to sweep. Defaults to whatever `gh` resolves
    for the checkout.

.PARAMETER Since
    Only the checkbox check considers a closed issue closed AFTER this
    timestamp (`YYYY-MM-DD` or a full ISO stamp); without it every closed issue
    in scope is considered. The carrier-ref check is unaffected - a stale
    reference to a closed carrier is worth reporting regardless of when that
    carrier closed.

.PARAMETER Label
    Issue label that marks a tracking issue. Default 'tracking'. Ignored under
    -AllClosed.

.PARAMETER AllClosed
    Widen the source-issue pool from "carries -Label" to every issue in the
    repository, for both checks: the checkbox check then walks every closed
    issue, and the carrier-ref check then walks every issue's body regardless
    of label.

.PARAMETER Json
    Serialize the findings as JSON instead of emitting objects.

.INPUTS
    None.

.OUTPUTS
    [pscustomobject] per finding with Source, Path, Line, Text and Note.

.EXAMPLE
    ./scripts/common/sweep-carriers.ps1

    Sweeps the checkout's own repository for both defects, human-readable.

.EXAMPLE
    ./scripts/common/sweep-carriers.ps1 -Repo ww3d/playbook -Since 2026-08-16 -Json

    Only issues closed after the last audit's stamp, machine-readable.

.EXAMPLE
    ./scripts/common/sweep-carriers.ps1 -AllClosed

    Every closed issue, not only the ones labelled `tracking`.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [string] $Repo,
    # Compared as UTC on both sides: a bare Kind is treated as local wall-clock
    # time and converted, the same reading .ToUniversalTime() gives a locally
    # typed -Since. Comparing a local $_ against UtcNow directly (the first cut
    # of this check) rejected a -Since within the last few hours as "in the
    # future" on any host east of UTC.
    [ValidateScript({ $_.ToUniversalTime() -le [datetime]::UtcNow },
        ErrorMessage = "-Since '{0}' lies in the future.")]
    [Nullable[datetime]] $Since,
    [string] $Label = 'tracking',
    [switch] $AllClosed,
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Same shape get-audit-worklist.ps1 already uses for OPEN tracking issues; here
# it runs over CLOSED ones - an unticked box in a closed carrier is the sibling
# defect to the one that script reports.
$checkboxPattern = '^\s*[-*]\s*\[( |x|X)\]\s*(.+)$'

# A bare same-repo reference only - `#N`, never `owner/repo#N` or `GH-N`. Both
# sides are guarded so 'ww3d/playbook#158' is not misread as a bare '#158'.
$referencePattern = '(?<![\w/])#(\d+)\b'

$entries = [System.Collections.Generic.List[pscustomobject]]::new()

$sourceArguments = @('issue', 'list', '--state', 'all',
    '--json', 'number,title,body,state,closedAt', '--limit', '1000')
if (-not $AllClosed) { $sourceArguments += @('--label', $Label) }
if ($Repo) { $sourceArguments += @('--repo', $Repo) }

# Catch-and-degrade, and it says so: gh may be absent, unauthenticated, or
# blocked server-side. A silent empty result here would look like a sweep that
# found nothing, which is indistinguishable from a healthy repository.
$sourceIssues = $null
try {
    $raw = & gh @sourceArguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw "gh exited $LASTEXITCODE" }
    $sourceIssues = @($raw | ConvertFrom-Json)
} catch {
    if (-not $Json) {
        Write-Warning "issues not read: $($_.Exception.Message). Report this sweep as NOT VERIFIED."
    }
    $entries.Add([pscustomobject]@{
            Source = 'unavailable'
            Path   = ''
            Line   = 0
            Text   = ''
            Note   = 'SOURCE UNAVAILABLE - not verified (issue list)'
        })
}

# The bundled lookup table for the carrier-ref check: one call for every issue
# number and state in the repository, instead of a `gh issue view` per
# reference found below.
$lookup = $null
if ($null -ne $sourceIssues) {
    $lookupArguments = @('issue', 'list', '--state', 'all',
        '--json', 'number,state', '--limit', '1000')
    if ($Repo) { $lookupArguments += @('--repo', $Repo) }
    try {
        $rawLookup = & gh @lookupArguments 2>$null
        if ($LASTEXITCODE -ne 0) { throw "gh exited $LASTEXITCODE" }
        $lookup = @{}
        foreach ($item in ($rawLookup | ConvertFrom-Json)) { $lookup[[int]$item.number] = $item.state }
    } catch {
        if (-not $Json) {
            Write-Warning "issue states not read: $($_.Exception.Message). Carrier-reference check reported as NOT VERIFIED."
        }
        $entries.Add([pscustomobject]@{
                Source = 'unavailable'
                Path   = ''
                Line   = 0
                Text   = ''
                Note   = 'SOURCE UNAVAILABLE - not verified (issue state lookup)'
            })
    }
}

# @($null) is a ONE-ELEMENT array holding $null, not an empty array - the catch
# block above leaves $sourceIssues as $null on failure, and looping over it
# unguarded threw on $issue.body under Set-StrictMode the first time gh failed.
foreach ($issue in @($sourceIssues | Where-Object { $null -ne $_ })) {
    $body = $issue.body
    if (-not $body) { $body = '' }
    $bodyLines = @($body -split "`r?`n")
    $isClosed = $issue.state -eq 'CLOSED'

    $passesSince = $true
    if ($Since) {
        $passesSince = $false
        # closedAt from the API is ISO 8601 UTC ("...Z"); $Since is converted
        # the same way the -Since validation reads it, so both sides compare
        # in the same clock regardless of this host's time zone.
        if ($issue.closedAt) { $passesSince = ([datetime]$issue.closedAt).ToUniversalTime() -gt $Since.ToUniversalTime() }
    }

    if ($isClosed -and $passesSince) {
        for ($i = 0; $i -lt $bodyLines.Count; $i++) {
            $line = $bodyLines[$i]
            if ($line -notmatch $checkboxPattern) { continue }
            if ($Matches[1] -ne ' ') { continue }
            $entries.Add([pscustomobject]@{
                    Source = 'checkbox'
                    Path   = "#$($issue.number)"
                    Line   = $i + 1
                    Text   = $Matches[2].Trim()
                    Note   = "closed tracking issue '$($issue.title)' still carries an open checkbox"
                })
        }
    }

    if ($null -ne $lookup) {
        for ($i = 0; $i -lt $bodyLines.Count; $i++) {
            $line = $bodyLines[$i]
            # Restricted to an UNTICKED checkbox line - not merely "not a
            # ticked one" (review round 1 of #233): the first cut of this fix
            # still let every plain PROSE line through, and prose is exactly
            # where a carrier reference is most often a quotation of past
            # history rather than a point ("- **#163** - Punkt 1, geschlossen
            # mit dem Merge", "umgehaengt nach #196") - carrier.md, section
            # "Carrier Requirement", explicitly does not count a quotation as
            # a carrier. REQ-027 speaks of "Punkte, deren genannter Traeger
            # geschlossen ist", and a point is a checkbox line. Measured
            # against this repository with only the ticked-line exclusion:
            # 76 of 76 remaining hits were prose, none a real defect.
            if ($line -notmatch $checkboxPattern) { continue }
            if ($Matches[1] -ne ' ') { continue }
            foreach ($match in [regex]::Matches($line, $referencePattern)) {
                $referenced = [int]$match.Groups[1].Value
                if ($referenced -eq [int]$issue.number) { continue }
                if (-not $lookup.ContainsKey($referenced)) { continue }
                if ($lookup[$referenced] -ne 'CLOSED') { continue }
                $entries.Add([pscustomobject]@{
                        Source = 'carrier-ref'
                        Path   = "#$($issue.number)"
                        Line   = $i + 1
                        Text   = $line.Trim()
                        Note   = "references carrier #$referenced, which is closed"
                    })
            }
        }
    }
}

$results = @($entries)

if ($Json) {
    ConvertTo-Json -InputObject $results -Depth 5
} else {
    $findings = @($results | Where-Object Source -ne 'unavailable')
    if ($findings.Count -eq 0) {
        Write-Output 'OK: no closed tracking issue with an open checkbox, no reference to a closed carrier issue'
    } else {
        foreach ($item in $findings) { Write-Output "$($item.Path):$($item.Line) - $($item.Note): $($item.Text)" }
    }
    foreach ($item in @($results | Where-Object Source -eq 'unavailable')) { Write-Output "UNAVAILABLE: $($item.Note)" }
}

$findingCount = @($results | Where-Object Source -ne 'unavailable').Count
if ($findingCount -gt 0) {
    Write-Error "$findingCount sweep-carriers finding(s)." -ErrorAction Continue
    exit 1
}
