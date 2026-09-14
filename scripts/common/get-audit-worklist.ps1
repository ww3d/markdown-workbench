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

    Four sources, each emitted with its own Source value so the audit can group
    them:

    * marker - every APPLIED marker statement in the repository's Markdown, with
      path and line. The marker WORDS are a table, not a hardcoded pattern -
      [erfuellt] / [teilweise] / [geplant] plus ww3d/iris's fourth form
      [nicht verifiziert] ("weder aus dem Repo heraus zu belegen noch zu
      widerlegen", for a statement about a foreign repository this one only
      pins a dependency on) - so a repository that adopts a new applied form
      costs a row in that table, never a new pattern written against this
      script (#215, #216). Backticks around the marker do not change whether it
      raises a raw hit; whether it is an INSTANCE or a QUOTATION of the
      convention is decided separately: a real CODE BLOCK (fenced or indented)
      always means quotation, decided on the Markdown syntax tree rather than a
      heuristic; a line naming more than one marker word, a file whose whole
      purpose is to define the grammar, or - for a backtick-wrapped hit only - a
      marker that does not stand at the end of its statement line, all mean the
      same. These are target-vs-actual displays, not carriers; the audit is what
      carries each one into a tracking issue.
    * tracking-issue - the body of every open tracking issue, one entry per
      unticked checklist line, PLUS every open GitHub Sub-Issue of that issue
      (Entscheidung 6, carrier.md, section "Tracking Issue": past a size guideline a
      tracking issue trades its checkboxes for Sub-Issues, and the body then
      carries only the current state - reading the body alone would miss them).
      Needs `gh`; when `gh` is missing or unauthenticated the source is reported
      as unavailable rather than silently empty, because an empty source and a
      skipped source look identical in a report. A single issue's Sub-Issues
      call failing degrades separately and quietly (most issues have none at
      all, which is an empty answer, not an error) - it does not turn the whole
      source unavailable.
    * marker-comment - every TODO / HACK / FIXME in code or in prose, with the
      FORM of the carrier reference it names: an issue reference, a URL, or a
      carrier file of the repository. One naming nothing is itself a finding
      (.agents/rules/carrier.md, section "Carrier Requirement").
    * source-report - one entry per source above: how many raw hits it saw, how
      many it discarded and why. A source that discarded EVERYTHING it saw ends
      the run as an error (exit 1), not as a quiet source-report line
      indistinguishable from "nothing there to find" - zero usable out of a
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

.PARAMETER Sarif
    Emit the marker and marker-comment findings as a SARIF 2.1.0 log instead of
    the default objects/JSON. tracking-issue and source-report entries carry no
    repository location and are left out. -Sarif takes precedence over -Json
    when both are given.

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

.EXAMPLE
    ./scripts/common/get-audit-worklist.ps1 -SkipIssue -Sarif > worklist.sarif

    Markers and TODO comments as a SARIF 2.1.0 log.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [string] $Path,
    [string] $Repo,
    [string] $Label = 'tracking',
    [switch] $SkipIssue,
    [switch] $Json,
    [switch] $Sarif
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Path) { $Path = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent }
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Repository root not found at '$Path'."
}
$root = (Resolve-Path -LiteralPath $Path).ProviderPath

# Marker grammar - a TABLE, not a fourth hardcoded form (#215, #216). Each row
# is one marker WORD; a repo that adopts a new applied form costs one row here,
# never a new regex written against this script. `nicht verifiziert` is
# ww3d/iris's fourth form (#216): "weder aus dem Repo heraus zu belegen noch zu
# widerlegen", for a statement about a foreign repo it only pins a dependency
# on.
$markerWord = @('erfuellt', 'teilweise', 'geplant', 'nicht verifiziert')
# Backticks around the marker are IRRELEVANT to whether it raises a raw hit -
# #215 measured two consumer repos (win-util, iris) that write every APPLIED
# marker backtick-quoted, and the previous code-span-based filter discarded
# 100% of theirs as "quoted in code" for exactly that reason (iris:
# "SOURCE YIELDED NOTHING - 687 raw, 687 discarded"). Whether a backtick-quoted
# hit is an instance or a quotation is a classification question, decided
# below - not a reason to exclude it from the raw count in the first place.
$markerPattern = '`?\[(' + ($markerWord -join '|') + ')\]`?'
# The pattern above is nakedly permissive on purpose - it is the RAW count. What
# separates an applied marker from a quoted one is not the pattern but the
# position and the line: a marker inside a CODE BLOCK is MARKUP naming the
# convention, not an instance of it. In the first real run - the state audit
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
#
# CodeInline is deliberately NOT in this set (#215): an inline code span no
# longer disqualifies a marker by itself - a backtick-wrapped `[erfuellt]`
# standing on its own is the APPLIED form in at least two consumer repos. Only
# a real CODE BLOCK (fenced or indented) still means "this is a worked example
# of the syntax, not a statement about this repository".
$codeNodeType = @('CodeBlock', 'FencedCodeBlock')
# Line-scoped inline-code-span pattern (same shape as check-terminology.ps1's
# own $codeSpanPattern), used only to tell "a marker exactly wrapped in its
# own backticks" from "a marker inside a LONGER quoted sentence" - the tree
# walk above no longer makes that distinction at all now that CodeInline is
# out of it.
$codeSpanPattern = '`([^`\r\n]+)`'
# The other half of the classification: a line naming the CONVENTION rather
# than applying it. Two shapes, neither needing a Markdown parse:
#   * more than one DISTINCT marker word on the same line - "the markers are
#     [erfuellt] / [teilweise] / [geplant]" describes the grammar, it does not
#     assert three different states of the same statement;
#   * a line that stands in one of a small set of files whose entire purpose
#     IS to define these markers. Listed here by path for the same reason the
#     marker words are a table above: a rule text that moves gets one row
#     updated here, not a special case in the walker.
$markerConventionFile = @('.agents/rules/docs.md', '.agents/rules/audit.md',
    '.claude/skills/state-audit/SKILL.md')
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
# audit/ is deliberately NOT here - a state audit report is exactly the
# document a real applied marker in prose is measured against (see
# tests/fixtures/audit-worklist/audit-report.md), so exempting the whole
# directory would hide the one source this script exists to feed honestly.
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
# try/catch, not just 2>$null: git itself being absent from PATH is a
# CommandNotFoundException, which $ErrorActionPreference = 'Stop' makes
# terminating - a redirected stderr only silences what a RUNNING git prints,
# never a missing-command error the engine raises before git can run at all.
# -c core.quotepath=off: the default quotes a non-ASCII path as octal escapes
# (a German-umlaut file name comes back as its raw UTF-8 bytes in octal), and
# Test-Path never matches that string against the real file - the path fell
# out of the scan silently.
try {
    $tracked = & git -c core.quotepath=off -C $root ls-files 2>$null
    $gitOk = $LASTEXITCODE -eq 0
} catch {
    $tracked = $null
    $gitOk = $false
}
if ($gitOk -and $tracked) {
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
$markerDropped = [ordered]@{ 'quoted in code' = 0; 'describes the convention' = 0; 'in an exempt path' = 0 }
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
            $isConventionFile = $relative -in $markerConventionFile

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
                $lineText = $text.Substring($lineStarts[$lineIndex], $lineEnd - $lineStarts[$lineIndex])

                # Describes the convention rather than applying it (#215): more
                # than one DISTINCT marker word on this line ("the markers are
                # [erfuellt] / [teilweise] / [geplant]"), or the file's whole
                # purpose is to define the grammar (see $markerConventionFile
                # above). NOT a position-in-the-line rule any more (review
                # round 1 of #233): a controller-decided correction against
                # #215's own two measured repos - ww3d/iris (13/306 usable,
                # 293 dropped as "describes the convention") and ww3d/win-util
                # (4/55 usable) - both write their applied backtick-quoted
                # markers mid-sentence ("`[teilweise]` **Aussage**", "`[erfuellt]`
                # - Beleg: ...", "... `[erfuellt]` (PR 4; ...)"), which an
                # end-of-line rule silently kept discarding. A backtick-wrapped
                # marker now counts as applied wherever it stands on its line,
                # exactly like a bare one, UNLESS it also falls into one of the
                # two reasons below.
                $wordsOnLine = @([regex]::Matches($lineText, $markerPattern) |
                        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)

                # Part of a LONGER inline code span - "`foo [erfuellt] bar`" -
                # is markup quoting a sentence, not the marker standing on its
                # own between backticks: this ONE case stays a quotation even
                # after the position rule above is gone. $markerPattern only
                # captures a backtick immediately touching the bracket, so this
                # hit would otherwise read as bare and count as applied.
                # Scanned once per hit against the LINE's own inline spans, not
                # against $codeSpans above: that tree walk no longer collects
                # CodeInline at all (see $codeNodeType), on purpose, since a
                # marker EXACTLY wrapped in its own backticks is the applied
                # form in at least two consumer repos - only a span wider than
                # the marker's own bracket text means this.
                $hitLineOffset = $hit.Index - $lineStarts[$lineIndex]
                $inLongerSpan = [bool]([regex]::Matches($lineText, $codeSpanPattern) | Where-Object {
                        $_.Index -le $hitLineOffset -and ($_.Index + $_.Length) -gt $hitLineOffset -and
                        $_.Groups[1].Value.Length -gt $hit.Value.Trim('`').Length
                    })

                if ($isConventionFile -or $wordsOnLine.Count -gt 1 -or $inLongerSpan) {
                    $markerDropped['describes the convention']++; continue
                }

                $entries.Add([pscustomobject]@{
                        Source = 'marker'
                        Path   = $relative
                        Line   = $lineIndex + 1
                        Text   = $lineText.Trim()
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
        $issues = @($raw | ConvertFrom-Json)

        # E6 (Entscheidung 6, carrier.md, section "Tracking Issue"): past a size
        # guideline a tracking issue trades its open points for GitHub
        # Sub-Issues, and the body then carries only the current state - a
        # worklist that read the body alone would look emptier than the issue
        # actually is. Needs an explicit owner/repo the `issue list` call above
        # did not: resolved once, only when sub-issues will actually be read.
        $repoSlug = $Repo
        if (-not $repoSlug -and $issues.Count -gt 0) {
            $repoSlug = "$(& gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>$null)".Trim()
            if ($LASTEXITCODE -ne 0 -or -not $repoSlug) { $repoSlug = $null }
            $global:LASTEXITCODE = 0
        }

        foreach ($issue in $issues) {
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

            if (-not $repoSlug) { continue }
            # Per-issue, catch-and-degrade separately from the checklist read
            # above: most tracking issues have no sub-issues at all (an empty
            # array, not an error), and one issue's sub-issue call failing is
            # not the wholesale gh outage the top-level SOURCE UNAVAILABLE
            # below is for.
            try {
                # --paginate --slurp, same pattern as measure-review-comment.ps1:
                # the sub_issues endpoint defaults to 30 per page, and
                # carrier.md, section "Tracking Issue", puts the Sub-Issues
                # switchover at roughly that same size - a tracking issue big
                # enough to need Sub-Issues is exactly the one whose list this
                # silently truncated. --slurp wraps the pages in one outer
                # array, flattened here.
                $subRaw = & gh api "repos/$repoSlug/issues/$($issue.number)/sub_issues" --paginate --slurp 2>$null
                if ($LASTEXITCODE -ne 0) { throw "gh exited $LASTEXITCODE" }
                foreach ($sub in @($subRaw | ConvertFrom-Json | ForEach-Object { $_ })) {
                    if ($sub.state -ne 'open') { continue }
                    $entries.Add([pscustomobject]@{
                            Source = 'tracking-issue'
                            Path   = "#$($sub.number)"
                            Line   = 0
                            Text   = $sub.title
                            Note   = "sub-issue of #$($issue.number) ($($issue.title))"
                        })
                }
            } catch {
                if (-not $Json -and -not $Sarif) {
                    Write-Warning "sub-issues of #$($issue.number) not read: $($_.Exception.Message)."
                }
            }
            $global:LASTEXITCODE = 0
        }
    } catch {
        $issueUnavailable = $true
        # Display only, and skipped under -Json: PowerShell renders the WARNING
        # stream on stdout, so under -Json it would sit inside the JSON document
        # and break every machine consumer - precisely when -Json is used. The
        # information is not lost either way; the SOURCE UNAVAILABLE entry below
        # carries it in the data, which is where a caller reads it.
        if (-not $Json -and -not $Sarif) {
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

# A source that discarded 100% of its raw hits ends as an ERROR (#215, last
# paragraph), not as a source-report line indistinguishable from "nothing
# there to find": zero usable out of zero raw IS a quiet, correct result, zero
# usable out of a non-zero raw count is a finding about the filter.
$yieldedNothing = @($results | Where-Object { $_.Source -eq 'source-report' -and $_.Note -like 'SOURCE YIELDED NOTHING*' })

if ($Sarif) {
    # SARIF 2.1.0, the required-fields subset - see check-terminology.ps1's
    # -Sarif for the same shape. Only 'marker' and 'marker-comment' carry a real
    # repository location; 'tracking-issue' and 'source-report' entries are not
    # file findings and are left out, the same way a linter does not emit a
    # SARIF result for its own run summary.
    $sarifLog = [ordered]@{
        '$schema' = 'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json'
        version   = '2.1.0'
        runs      = @(
            [ordered]@{
                tool    = [ordered]@{
                    driver = [ordered]@{
                        name    = 'get-audit-worklist'
                        version = '1.0.0'
                    }
                }
                results = @($results | Where-Object { $_.Source -in 'marker', 'marker-comment' } | ForEach-Object {
                        [ordered]@{
                            ruleId    = $_.Source
                            level     = 'note'
                            message   = [ordered]@{ text = "$($_.Text) ($($_.Note))" }
                            locations = @(
                                [ordered]@{
                                    physicalLocation = [ordered]@{
                                        artifactLocation = [ordered]@{ uri = $_.Path }
                                        region           = [ordered]@{ startLine = [Math]::Max(1, $_.Line) }
                                    }
                                }
                            )
                        }
                    })
            }
        )
    }
    ConvertTo-Json -InputObject $sarifLog -Depth 10
} elseif ($Json) {
    ConvertTo-Json -InputObject $results -Depth 5
} else {
    $results
}

if ($yieldedNothing.Count -gt 0) {
    $names = ($yieldedNothing | ForEach-Object { $_.Path }) -join ', '
    Write-Error "$($yieldedNothing.Count) source(s) discarded every raw hit they saw: $names. Check the filter, not just the count." -ErrorAction Continue
    exit 1
}
