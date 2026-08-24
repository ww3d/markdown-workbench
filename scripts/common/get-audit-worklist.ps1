#Requires -Version 7.4

<#
.SYNOPSIS
    Build the work list the state audit walks: status markers, open tracking
    issue points, and every TODO / HACK / FIXME with its carrier reference.

.DESCRIPTION
    .agents/rules/audit.md, section "State Audit", requires an audit before every new slice,
    and the `state-audit` skill runs it. Its first step is not judgement but
    collection - and collection done from memory leaves out exactly the source
    nobody holds in their head. This script does the collecting.

    Three sources, each emitted with its own Source value so the audit can group
    them:

    * marker - every APPLIED [erfuellt] / [teilweise] / [geplant] statement in
      the repository's Markdown, with path and line. A marker inside inline code
      or a code block is a quotation of the convention, not an instance of it,
      and is discarded - decided on the Markdown syntax tree, not on a
      heuristic. These are target-vs-actual displays, not carriers; the audit is
      what carries each one into a tracking issue.
    * tracking-issue - the body of every open tracking issue, one entry per
      checklist line. Needs `gh`; when `gh` is missing or unauthenticated the
      source is reported as unavailable rather than silently empty, because an
      empty source and a skipped source look identical in a report.
    * marker-comment - every TODO / HACK / FIXME in code or in prose, with the
      FORM of the carrier reference it names: an issue reference, a URL, or a
      carrier file of the repository. One naming nothing is itself a finding
      (.agents/rules/carrier.md, section "Carrier Requirement").
    * source-report - one entry per source above: how many raw hits it saw, how
      many it discarded and why. A source that discarded everything says so in
      the same shape as an unavailable one, because zero usable entries out of a
      non-zero raw count is a finding about the filter, not a quiet result.

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
# The pattern above is nakedly permissive on purpose - it is the RAW count. What
# separates an applied marker from a quoted one is not the pattern but the
# position: a marker inside inline code or inside a code block is MARKUP naming
# the convention, not an instance of it. In the first real run - the state audit
# in ww3d/atlas of 2026-08-23 - 36 of 36 hits were of that kind, so the source
# produced nothing usable and looked like it had worked.
#
# The position comes from the Markdown syntax tree, not from a heuristic: a
# parser knows the difference by construction, while a hand-rolled guard has to
# rebuild it and is wrong again with every new writing style. That is how prose
# linters do it - Vale reads at tree level and excludes code by default.
#
# MEASURED BEFORE IT WAS BUILT, because Markdig sets precise source positions
# only on a pipeline configured for them and the built-in cmdlet's pipeline was
# unverified: ConvertFrom-Markdown does report Line and Span for inline nodes,
# and slicing the source with a reported Span returns exactly the node's text.
# Both halves of this filter therefore read the tree; there is no line-wise
# fallback because there is nothing to fall back from.
$codeNodeType = @('CodeBlock', 'FencedCodeBlock', 'CodeInline')
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
# The same word without any of that strictness - the RAW count for this source,
# so the report below can say how many hits the strict pattern threw away and
# why. A source that filters silently is indistinguishable from one that found
# nothing.
$commentRawPattern = '\b(TODO|HACK|FIXME)\b'
# A carrier reference is deliberately loose: the audit judges whether the target
# really carries the point, this only separates "names something" from "names
# nothing". It was not loose ENOUGH - requiring a `#` reported four of five
# TODOs in the atlas run as carrier-less, because a verbatim import from an
# upstream repo writes its reference as a URL.
#
# Which of the forms are reported is what changed with them: GitHub itself
# treats several spellings as the same reference and which ones count depends on
# the repository, so a closing catalogue of forms cannot exist. And the valid
# carriers of this convention are not only issues - a line in roadmap.md or
# backlog.md carries a point just as well (.agents/rules/carrier.md, section
# "Carrier Requirement"), and a TODO pointing there used to be reported wrong in
# exactly the same way.
#
# Ordered most specific first: a line naming both an issue and a URL is reported
# as the issue reference, which is the more precise of the two.
$carrierForm = [ordered]@{
    'issue-ref' = '(?:(?:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+)?#\d+|\bGH-\d+\b)'
    'url'       = 'https?://\S+'
    'file'      = '\b(?:roadmap|backlog)\.md\b'
}

$skipDirectory = @('.git', 'node_modules', 'bin', 'obj', '_build', '_buildtools', 'dist')
# The logs are immutable history: a marker quoted there describes a past state.
$exemptPrefix = @('docs/decisions/')

$entries = [System.Collections.Generic.List[pscustomobject]]::new()

$relativeOf = {
    param($FullName)
    [System.IO.Path]::GetRelativePath($root, $FullName).Replace('\', '/')
}

# Every character range in the document that is code rather than prose, taken
# from the Markdown syntax tree. Returned as [start, end] pairs into the very
# string that was parsed, which is what makes the offsets of a regex match
# comparable against them.
#
# Compared by type NAME rather than with -is: the Markdig assembly is loaded as
# a side effect of the first ConvertFrom-Markdown call, so a type literal in
# this file would depend on that having happened already.
# $Starts is the caller's line-start list, passed in rather than recomputed: it
# needs the same one to turn a hit offset into a line number, and scanning a
# 400 KB document for newlines twice is a scan too many.
$codeSpansOf = {
    param([string] $Text, [System.Collections.Generic.List[int]] $Starts)

    $spans = [System.Collections.Generic.List[int[]]]::new()
    $pending = [System.Collections.Generic.Stack[object]]::new()
    foreach ($token in (ConvertFrom-Markdown -InputObject $Text).Tokens) { $pending.Push($token) }

    while ($pending.Count -gt 0) {
        $node = $pending.Pop()
        $span = $node.Span

        if ($node.GetType().Name -in $codeNodeType) {
            # A degenerate span (the empty group node the parser appends) would
            # otherwise mask the whole document.
            if ($span.Start -ge 0 -and $span.End -ge $span.Start) {
                $end = $span.End

                # An UNCLOSED fence is the one place the reported span lies: Markdig
                # ends it at the opening line while still rendering the rest as code,
                # so every marker below it counted as APPLIED - the exact direction
                # this filter exists against, and invisible because the report then
                # calls those hits usable.
                #
                # `Lines` is the content the parser actually consumed, so the block
                # reaches at least to line (Line + Lines.Count): the opening line plus
                # that many content lines. A CLOSED fence has its closing line beyond
                # that, and its reported span already covers it - which is why this
                # only ever EXTENDS, never shortens.
                # -1 is the sentinel for "Lines was not readable"; 0 is a real
                # answer and must be treated as one. An unclosed fence with NO
                # content line at all - the last thing in a file that writes
                # about fence syntax - gets a raw span of a few characters, so a
                # marker in its own info string stayed unfiltered while the
                # neighbouring case with content lines was caught. Zero content
                # lines means "no FURTHER lines", not "nothing to extend".
                #
                # WHERE `Line` POINTS differs by block kind, and the offset with
                # it - measured on Markdig, not assumed:
                #   * FencedCodeBlock: `Line` is the OPENING FENCE, which is not
                #     a content line. Line + Lines.Count is therefore the last
                #     line the block occupies (the closing fence, or the last
                #     content line when there is none).
                #   * CodeBlock (indented): there is no opening line. `Line` is
                #     already the FIRST content line, so the last one is
                #     Line + Lines.Count - 1, and the fence formula would point
                #     one line PAST the block - at the first prose line after it.
                #     An applied marker there, with no blank line in between
                #     (CommonMark does not require one), was discarded as
                #     `quoted in code`: the opposite direction of the unclosed-fence
                #     bug above, out of the same corner.
                $lineCount = -1
                if ($null -ne $node.PSObject.Properties['Lines']) {
                    try { $lineCount = [int]$node.Lines.Count } catch { $lineCount = -1 }
                }
                if ($lineCount -ge 0) {
                    $opensWithOwnLine = $node.GetType().Name -eq 'FencedCodeBlock'
                    $lastLine = $node.Line + $lineCount - $(if ($opensWithOwnLine) { 0 } else { 1 })
                    # A block can never end before it starts; guards the
                    # (parser-wise impossible) indented block with zero lines.
                    if ($lastLine -lt $node.Line) { $lastLine = $node.Line }
                    $lineEnd = if ($lastLine + 1 -lt $Starts.Count) {
                        $Starts[$lastLine + 1] - 1
                    } else {
                        $Text.Length - 1
                    }
                    if ($lineEnd -gt $end) { $end = $lineEnd }
                }

                $spans.Add([int[]]@($span.Start, $end))
            }
            # Nothing inside a code node is prose, so its children are not walked.
            continue
        }

        if ($node -is [System.Collections.IEnumerable]) {
            foreach ($child in $node) { $pending.Push($child) }
        }
        # A leaf block keeps its inline content beside itself rather than as its
        # enumeration, so it needs its own push.
        if ($null -ne $node.PSObject.Properties['Inline'] -and $null -ne $node.Inline) {
            foreach ($child in $node.Inline) { $pending.Push($child) }
        }
    }
    # Sorted by start offset, so the caller can binary-search instead of scanning
    # every span for every hit. Code spans never nest - the walk stops at a code
    # node - so a sorted list has at most one candidate per offset.
    # Comma on purpose: a bare return unrolls the list into the pipeline, and a
    # single span would arrive as its two loose integers.
    return , ([System.Collections.Generic.List[int[]]]@($spans | Sort-Object { $_[0] }))
}

# Character offset -> 1-based line number. The offsets come from the parser, the
# entries have to carry a line, and counting newlines per match would be
# quadratic on a long document.
$lineStartsOf = {
    param([string] $Text)

    $starts = [System.Collections.Generic.List[int]]::new()
    $starts.Add(0)
    for ($i = 0; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -eq "`n") { $starts.Add($i + 1) }
    }
    # Comma on purpose, same reason as above - a one-line document would come
    # back as a bare [int] with no BinarySearch on it.
    return ,$starts
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

# Filter transparency, per source. The real damage in the atlas run was not the
# wrong filter but that a source with nothing left looked like one that had
# worked - so every source now says how much it saw and how much it threw away.
$markerRaw = 0
$markerDropped = [ordered]@{ 'quoted in code' = 0; 'in an exempt path' = 0 }
$commentRaw = 0
$commentDropped = [ordered]@{
    'not a marker (no colon, backtick-quoted, or lowercase)' = 0
    'in an exempt path'                                      = 0
}

foreach ($file in $candidates) {
    $relative = & $relativeOf $file.FullName
    $isMarkdown = $file.Name -like '*.md'
    $isExempt = [bool]($exemptPrefix | Where-Object { $relative.StartsWith($_, [StringComparison]::Ordinal) })

    # Binary files have no lines worth reading, and reading them as text is slow
    # and noisy. -ErrorAction on the read, not a suffix allowlist: a repository
    # may put source in any extension.
    $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($text)) { continue }

    if ($isMarkdown) {
        $rawHits = @([regex]::Matches($text, $markerPattern))
        $markerRaw += $rawHits.Count

        if ($isExempt) {
            $markerDropped['in an exempt path'] += $rawHits.Count
        } elseif ($rawHits.Count -gt 0) {
            # Parsed only where there is something to place - the tree walk is
            # the expensive part and most files carry no marker at all.
            $lineStarts = & $lineStartsOf $text
            $codeSpans = & $codeSpansOf $text $lineStarts
            # The starts alone, so the search below is a binary one. Running the
            # whole span list through a Where-Object per hit is quadratic, and
            # the difference is measured rather than assumed.
            #
            # BENCHMARK, so the numbers are readable: one synthetic Markdown file
            # per run, one quoted marker per line, measured as the wall-clock
            # time of the whole script (`time pwsh -NoProfile -File ... -SkipIssue
            # -Json`), one run per size, on the Linux container this was built in.
            # Before: 2,000 markers / 137 KB in 16.9 s, of which 15.9 s in the
            # Where-Object pipeline; 6,000 markers / 408 KB in 137 s. After:
            # 1.2 s and 2.6 s, same results in both cases. The before-state is
            # the parent commit of the one that introduced this loop; the numbers
            # are an order of magnitude, not a regression threshold.
            $spanStarts = [System.Collections.Generic.List[int]]@($codeSpans | ForEach-Object { $_[0] })

            foreach ($hit in $rawHits) {
                # The last span that starts at or before the hit is the only one
                # that can contain it, because code spans do not nest.
                $at = $spanStarts.BinarySearch($hit.Index)
                $candidate = if ($at -ge 0) { $at } else { -$at - 2 }
                $quoted = $candidate -ge 0 -and $hit.Index -le $codeSpans[$candidate][1]
                if ($quoted) { $markerDropped['quoted in code']++; continue }

                # BinarySearch returns the exact index, or the bitwise complement
                # of the first element GREATER than the offset - one past the
                # line the offset sits on.
                $found = $lineStarts.BinarySearch($hit.Index)
                $lineIndex = if ($found -ge 0) { $found } else { -$found - 2 }

                $lineEnd = $text.IndexOf("`n", $lineStarts[$lineIndex])
                if ($lineEnd -lt 0) { $lineEnd = $text.Length }

                $entries.Add([pscustomobject]@{
                        Source = 'marker'
                        Path   = $relative
                        Line   = $lineIndex + 1
                        Text   = $text.Substring($lineStarts[$lineIndex], $lineEnd - $lineStarts[$lineIndex]).Trim()
                        Note   = $hit.Groups[1].Value
                    })
            }
        }
    }

    $lines = @($text -split "`r?`n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -notmatch $commentRawPattern) { continue }
        # Counted BEFORE the exempt path is skipped. Skipping first hid the file
        # from this source's report entirely, so an exempt TODO was neither a raw
        # hit nor a discarded one - the silent filter this whole round is against,
        # and in the one source whose filter got four of five hits wrong.
        $commentRaw++
        if ($isExempt) { $commentDropped['in an exempt path']++; continue }

        if ($line -cnotmatch $commentPattern) {
            $commentDropped['not a marker (no colon, backtick-quoted, or lowercase)']++
            continue
        }

        $form = 'NO CARRIER REFERENCE'
        foreach ($name in $carrierForm.Keys) {
            if ($line -match $carrierForm[$name]) { $form = "carrier: $name"; break }
        }

        $entries.Add([pscustomobject]@{
                Source = 'marker-comment'
                Path   = $relative
                Line   = $i + 1
                Text   = $line.Trim()
                Note   = $form
            })
    }
}

$issueRaw = 0
$issueDropped = 0
$issueUnavailable = $false

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
                $issueRaw++
                if ($Matches[1] -ne ' ') { $issueDropped++; continue }
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
        $issueUnavailable = $true
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

# One report per source: raw hits, discarded hits, and the reason they were
# discarded. "36 found, 36 discarded" would have shown the defect on day one
# instead of after a complete audit, and no tool in the comparison field reports
# how sure its own filter currently is.
#
# A source that discarded EVERYTHING it saw says so loudly, in the same shape as
# SOURCE UNAVAILABLE above: zero usable entries out of a non-zero raw count is
# not a quiet result, it is a finding about the filter.
$sourceReport = {
    # IDictionary, not Hashtable: the marker source counts two reasons and keeps
    # them ordered, which makes its table an OrderedDictionary.
    param([string] $Name, [int] $Raw, [System.Collections.IDictionary] $Dropped)

    $droppedTotal = ($Dropped.Values | Measure-Object -Sum).Sum
    $reasons = @($Dropped.Keys | Where-Object { $Dropped[$_] -gt 0 } |
            ForEach-Object { "$($Dropped[$_]) $_" }) -join ', '
    if (-not $reasons) { $reasons = 'none discarded' }

    $note = "$Raw raw, $droppedTotal discarded ($reasons)"
    if ($Raw -gt 0 -and $droppedTotal -eq $Raw) {
        $note = "SOURCE YIELDED NOTHING - $note"
    }

    [pscustomobject]@{
        Source = 'source-report'
        Path   = $Name
        Line   = 0
        Text   = "$($Raw - $droppedTotal) usable"
        Note   = $note
    }
}

$entries.Add((& $sourceReport 'marker' $markerRaw $markerDropped))
$entries.Add((& $sourceReport 'marker-comment' $commentRaw $commentDropped))
if (-not $SkipIssue -and -not $issueUnavailable) {
    $entries.Add((& $sourceReport 'tracking-issue' $issueRaw @{ 'already ticked' = $issueDropped }))
}

$results = @($entries)

if ($Json) {
    ConvertTo-Json -InputObject $results -Depth 5
} else {
    $results
}
