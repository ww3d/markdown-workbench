#Requires -Version 7.6

<#
.SYNOPSIS
    Check the form of a pull request and its size before it goes to review: the one script for
    every point a reviewer would otherwise report as form.

.DESCRIPTION
    .agents/rules/pr.md (section "PR / MR Description" and "Task Spec") and .agents/rules/review.md
    leave form and size to this script: red means the PR is not ready for review, and the
    reviewer reports no form point any more. Each finding is one line
    `FORM <path>[:<line>] <point>: <text>`; exit 0 without a finding, 1 with one, 2 when an input
    cannot be read.

    Points:
    - comment-length    - an added comment line over 120 characters in a code file.
    - body-headings     - the five headings of the PR body, in order.
    - body-anchor       - one `Closes`/`Fixes`/`Resolves`/`Refs` line naming the anchor issue.
    - body-closing-line - a closing keyword with a number stands only as a line of its own.
    - body-quantity     - no diff quantities (lines, files, tests, functions) in the body.
    - body-list         - under "Deliberately not changed" and "Open questions" and "Observations"
                          each list item is a link and nothing else.
    - body-terminology  - check-terminology.ps1 -BodyPath is clean.
    - run-line          - a well-formed run line under "How tested" names the head, or an ancestor after which only
                          review ledger commits follow.
    - spec-file         - each task spec the PR adds or changes under docs/tasks/: frontmatter, REQ numbers gapless
                          inside each block of a hundred, each ticked or
                          `not delivered:`, a `Review-Mode:` line, and for `hard` a wave report.
    - anchor-open       - the anchor issue is open.
    - moved-fix         - find-moved-fixes.ps1 reports none.
    - size              - over 1,000 changed lines or 40 files without `Size exception: <reason>`
                          under "## Design" in the anchor issue. Tests (the merge gate's pattern),
                          files marked `linguist-generated` at the base, and pure renames do not
                          count.

    -Waive "<reason>" with the line `Form check waived: <reason>` under "## Design" of the
    anchor issue turns the run green and says so.

    Online (-Repo and -Pr) reads the PR and the anchor issue over REST and asks the working copy at
    -Root for the diff against the PR's base, fetching the PR's base and head from origin when the clone lacks
    them. Offline (-BodyPath, -AnchorPath, -MovedFixesPath)
    reads files, for tests and for a body copied out of the forge; the diff then comes from -BaseRef
    and -HeadSha in -Root.

.PARAMETER Repo
    owner/name of the repository, with -Pr.

.PARAMETER Pr
    Pull request number, with -Repo.

.PARAMETER BodyPath
    Offline: file holding the PR body.

.PARAMETER AnchorPath
    Offline: JSON `{ "repo", "number", "state", "body" }` of the anchor issue. Absent while the body names an
    anchor means the issue is not read: an `UNREAD` line and exit 2, no finding.

.PARAMETER MovedFixesPath
    Offline: the output of `find-moved-fixes.ps1 -Json`. Absent means the check is not made.

.PARAMETER Root
    Working copy that answers the git questions. Default: the current directory.

.PARAMETER BaseRef
    Offline: the base of the diff. Default origin/main. Online the PR's base commit.

.PARAMETER HeadSha
    Offline: the PR head. Default HEAD of -Root.

.PARAMETER Waive
    The reason to let the run pass; the anchor issue must carry the same line.

.PARAMETER Json
    Serialize the findings as JSON.

.INPUTS
    None.

.OUTPUTS
    [string] one line per finding (`UNREAD ...` for what could not be read); with -Json one object (Ok, Head, Waived,
    Finding[], Unread[]).

.EXAMPLE
    ./scripts/common/test-pr-form.ps1 -Repo ww3d/playbook -Pr 586
#>

[CmdletBinding(DefaultParameterSetName = 'Online')]
[OutputType([string])]
param(
    [Parameter(Mandatory, ParameterSetName = 'Online')][ValidatePattern('^[\w.-]+/[\w.-]+$')][string] $Repo,
    [Parameter(Mandatory, ParameterSetName = 'Online')][ValidateRange(1, [int]::MaxValue)][int] $Pr,
    [Parameter(Mandatory, ParameterSetName = 'Offline')][string] $BodyPath,
    [Parameter(ParameterSetName = 'Offline')][string] $AnchorPath,
    [Parameter(ParameterSetName = 'Offline')][string] $MovedFixesPath,
    [Parameter(ParameterSetName = 'Offline')][string] $BaseRef = 'origin/main',
    [Parameter(ParameterSetName = 'Offline')][string] $HeadSha,
    [string] $Root = '.',
    [string] $Waive,
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$withUtf8Output = Join-Path $PSScriptRoot 'invoke-utf8-output.ps1'
$finding = [System.Collections.Generic.List[pscustomobject]]::new()
$add = {
    param([string] $Point, [string] $Text, [string] $Where = '')
    $finding.Add([pscustomobject]@{ Point = $Point; Where = $Where; Text = $Text })
}
$git = {
    param([string[]] $GitArgument)
    $text = & $withUtf8Output { param($Argument) & git -C $Root -c core.quotepath=off @Argument 2>$null } $GitArgument
    $exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    [pscustomobject]@{ Ok = $exitCode -eq 0; Line = @($text) }
}
$fail = { param([string] $Message) "test-pr-form: $Message"; exit 2 }
# What could not be read: not a finding, but the run is not green either (exit 2).
$unread = [System.Collections.Generic.List[string]]::new()

# --- Inputs ----------------------------------------------------------------
try {
    if ($PSCmdlet.ParameterSetName -eq 'Online') {
        $pull = (& $withUtf8Output { & gh api "repos/$Repo/pulls/$Pr" } | Out-String) | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw "gh api pulls/$Pr failed" }
        $body = "$($pull.body)"
        $head = "$($pull.head.sha)"
        $baseRef = "$($pull.base.sha)"
        # The working copy may not hold the PR's commits (a clone that never fetched them): fetch what is missing.
        foreach ($sha in @($baseRef, $head)) {
            $present = { (& $git @('cat-file', '-e', "$sha^{commit}")).Ok }
            if (& $present) { continue }
            $null = & $git @('fetch', '--quiet', 'origin', $sha)
            if (-not (& $present)) { $null = & $git @('fetch', '--quiet', 'origin', "refs/pull/$Pr/head") }
            if (-not (& $present)) { $null = & $git @('fetch', '--quiet', 'origin', "$($pull.base.ref)") }
            if (-not (& $present)) { throw "commit $sha is not in the working copy at $Root and could not be fetched from origin" }
        }
    } else {
        $body = Get-Content -LiteralPath $BodyPath -Raw
        $head = if ($HeadSha) { $HeadSha } else { "$((& $git @('rev-parse', 'HEAD')).Line)".Trim() }
        $baseRef = $BaseRef
    }
} catch { & $fail $_.Exception.Message }
$bodyLine = @($body -split "`r?`n")

# The sections of the body: heading text -> its lines (code fences left out everywhere below).
$inFence = $false
$section = ''
$heading = [System.Collections.Generic.List[string]]::new()
$inSection = @{}
$bodyText = [System.Collections.Generic.List[pscustomobject]]::new()
# The run lines also stand in a code block, as .agents/rules/pr.md "Test Runs" shows them and the merge gate reads them.
$runText = [System.Collections.Generic.List[pscustomobject]]::new()
foreach ($raw in $bodyLine) {
    if ($raw -match '^\s{0,3}(```|~~~)') { $inFence = -not $inFence; continue }
    if ($inFence) { $runText.Add([pscustomobject]@{ Section = $section; Text = $raw }); continue }
    if ($raw -match '^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$') { $section = $Matches[1]; $heading.Add($section); continue }
    $bodyText.Add([pscustomobject]@{ Section = $section; Text = $raw })
    $runText.Add([pscustomobject]@{ Section = $section; Text = $raw })
}

# --- Body: headings, anchor, closing line, quantities, lists ------------------
$expected = @(
    @('What', 'Was'), @('Deliberately not changed', 'Was bewusst nicht geaendert wurde'),
    @('Decisions', 'Entscheidungen'), @('How tested', 'Wie getestet'), @('Open questions', 'Offene Fragen'))
$position = -1
foreach ($names in $expected) {
    $at = -1
    for ($i = 0; $i -lt $heading.Count; $i++) { if ($heading[$i] -in $names) { $at = $i; break } }
    if ($at -lt 0) { & $add 'body-headings' "heading '$($names[0])' is missing" }
    elseif ($at -lt $position) { & $add 'body-headings' "heading '$($names[0])' is out of order" }
    else { $position = $at }
}
# The closing forms of .agents/rules/pr.md "PR / MR Description": Close, Closes, Closed, Fix, Fixes, Fixed, Resolve,
# Resolves, Resolved (an optional colon after the word, several items on one line), and Ref or Refs for the anchor.
$closeWord = 'close[sd]?|fix(?:e[sd])?|resolve[sd]?'
$issueRef = '(?:[\w.-]+/[\w.-]+)?#\d+'
$keyword = "(?i)\b(?:$closeWord)\b:?\s+$issueRef"
$closeItem = "(?:$closeWord)\b:?\s+$issueRef"
$anchorItem = "(?:(?:$closeWord)|refs?)\b:?\s+($issueRef)"
$anchor = @($bodyText | Where-Object { $_.Text -match "(?i)^\s*$anchorItem(?:\s*[,;]\s*(?:(?:$closeWord)|refs?)\b:?\s+$issueRef)*\s*$" } | ForEach-Object { $Matches[1] })
if ($anchor.Count -eq 0) { & $add 'body-anchor' 'no `Closes #N` or `Refs #N` line of its own names the anchor issue' }
foreach ($line in $bodyText) {
    if ($line.Text -match $keyword -and $line.Text -notmatch "(?i)^\s*$closeItem(?:\s*[,;]\s*$closeItem)*\s*$") {
        & $add 'body-closing-line' "a closing keyword with a number stands only as a line of its own: $($line.Text.Trim())"
    }
}
$quantity = '(?i)(?<![\w.#-])\d+(?:[.,]\d{3})*(?![\d.]*\.\d)\s+(?:changed\s+|new\s+|added\s+)?(?:lines?|files?|tests?|functions?|zeilen|dateien)\b'
foreach ($line in $bodyText) {
    $isRun = $line.Text -match '^\s*(?:[-*+]\s+)?`?(?:Run|Lauf)\s*\|'
    if ($line.Section -notmatch '(?i)^(?:How tested|Wie getestet)\b' -and -not $isRun -and $line.Text -match $quantity) {
        & $add 'body-quantity' "no diff quantities in the body: $($line.Text.Trim())"
    }
}
$link = '\[[^\]]*\]\([^)]*\)|https?://\S+|(?:[\w.-]+/[\w.-]+)?#\d+'
foreach ($line in $bodyText) {
    if ($line.Section -notmatch '(?i)^(?:Deliberately not changed|Was bewusst nicht geaendert wurde|Open questions|Offene Fragen|Observations)\b') { continue }
    if ($line.Text -notmatch '^\s*[-*+]\s+(.*)$') { continue }
    $item = $Matches[1].Trim()
    $rest = ($item -replace $link, '') -replace '[\s\p{P}]+', ''
    if ($item -match '^(?i:none|keine)(?:\s+yet)?\.?$') { continue }
    if ($item -notmatch $link -or $rest.Length -gt 0) { & $add 'body-list' "a point here is a link to its carrier and nothing else: $item" }
}
$terminology = Join-Path $PSScriptRoot 'check-terminology.ps1'
$bodyFile = Join-Path ([IO.Path]::GetTempPath()) "pr-form-body-$([guid]::NewGuid().ToString('N')).md"
try {
    Set-Content -LiteralPath $bodyFile -Value $body -NoNewline
    $report = @(& $terminology -Path $Root -BodyPath $bodyFile -BaseRef $baseRef 2>&1)
    if ($LASTEXITCODE -ne 0) { foreach ($row in ($report | Where-Object { "$_".Trim() })) { & $add 'body-terminology' "$row".Trim() } }
    $global:LASTEXITCODE = 0
} finally { Remove-Item -LiteralPath $bodyFile -ErrorAction SilentlyContinue }

# --- Run line -----------------------------------------------------------------
$runPattern = '^(?:Run|Lauf)\s*\|\s*(?:Head|Kopf)\s+([0-9a-fA-F]{7,40})\s*\|\s*(?:Base|Basis)\s+\S+\s*\|\s*(?:Mode|Modus)\s+(?:full|filtered|format|publish|voll|gefiltert)\s*\|(?:[^|]*\|){5}[^|]*$'
$runHead = @($runText | Where-Object { $_.Section -match '(?i)^(?:How tested|Wie getestet)\b' } | ForEach-Object {
        $t = ($_.Text -replace '^\s*(?:[-*+]\s+)?', '').Trim().Trim('`')
        if ($t -match $runPattern) { $Matches[1] }
    })
# A run line holds for the head, or for an ancestor after which only review ledger commits follow (no run line owed).
$ledgerOnly = '(?i)^docs/decisions/[^/]+-ledger\.jsonl$'
$holdsFor = {
    param([string] $Sha)
    if ($head.StartsWith($Sha, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $full = & $git @('rev-parse', '--verify', '--quiet', "$Sha^{commit}")
    if (-not $full.Ok -or $full.Line.Count -eq 0) { return $false }
    $ancestor = & $git @('merge-base', '--is-ancestor', "$($full.Line[0])", $head)
    if (-not $ancestor.Ok) { return $false }
    $path = & $git @('diff', '--name-only', '--no-renames', "$($full.Line[0])", $head)
    $path.Ok -and @($path.Line | Where-Object { $_.Trim() -and $_ -notmatch $ledgerOnly }).Count -eq 0
}
if ($runHead.Count -eq 0) { & $add 'run-line' 'no well-formed run line under "How tested" (Run | Head | Base | Mode | ... as in .agents/rules/pr.md "Test Runs")' }
elseif (-not (@($runHead | Where-Object { & $holdsFor $_ }).Count)) {
    & $add 'run-line' "no run line names the head $($head.Substring(0, [Math]::Min(7, $head.Length))) (or an ancestor followed only by review ledger commits)"
}

# --- Diff: size and comment length ----------------------------------------------
$tests = '(?i)(^|/)(tests?|__tests__)/|\.tests?\.\w+$|\.spec\.\w+$|_test\.go$'
$codeFile = '(?i)\.(?:ps1|psm1|psd1|sh|bash|cs|js|jsx|mjs|cjs|ts|tsx|mts|cts|py|rb|rs|go|java|kt|c|h|cpp)$'
$changed = [System.Collections.Generic.List[pscustomobject]]::new()
$numstat = & $git @('diff', '--numstat', '-M', '-z', '--no-ext-diff', "$baseRef...$head")
if (-not $numstat.Ok) { & $fail "git diff $baseRef...$head failed in $Root" }
$token = @(("$($numstat.Line -join "`n")" -split "`0") | Where-Object { $_ -ne '' })
for ($i = 0; $i -lt $token.Count; $i++) {
    $entry = $token[$i].TrimStart("`n")
    if ($entry -notmatch '^(\d+|-)\t(\d+|-)\t(.*)$') { continue }
    $lines = if ($Matches[1] -eq '-') { 0 } else { [int]$Matches[1] + [int]$Matches[2] }
    $path = $Matches[3]
    if ($path -eq '' -and $i + 2 -lt $token.Count) { $path = $token[$i + 2]; $i += 2 }
    $changed.Add([pscustomobject]@{ Path = $path; Lines = $lines; Rename = $Matches[3] -eq '' })
}
$generated = @{}
if ($changed.Count -gt 0) {
    $attr = & $git (@('check-attr', '--source', $baseRef, 'linguist-generated', '--') + @($changed | ForEach-Object { $_.Path }))
    if (-not $attr.Ok) { $unread.Add('git check-attr failed; generated files count towards the size') }
    foreach ($row in $attr.Line) { if ("$row" -match '^(.*): linguist-generated: (set|true)$') { $generated[$Matches[1]] = $true } }
}
$counted = @($changed | Where-Object { $_.Path -notmatch $tests -and -not $generated.ContainsKey($_.Path) -and -not ($_.Rename -and $_.Lines -eq 0) })
$sumLines = 0
foreach ($item in $counted) { $sumLines += $item.Lines }
$exception = $false

# comment-length: every added comment line over 120 characters in a code file. A comment line is read from the file at
# the head, so a line inside a block comment (<# #> or /* */) counts, and a marker inside a string does not.
$added = @{}
$patch = & $git @('diff', '--no-color', '--no-ext-diff', '-U0', '--no-renames', "$baseRef...$head")
$file = ''; $lineNo = 0
foreach ($row in $patch.Line) {
    if ($row -match '^\+\+\+ b/(.*?)\t?$') { $file = $Matches[1]; continue }
    if ($row -match '^@@ .* \+(\d+)(?:,\d+)? @@') { $lineNo = [int]$Matches[1]; continue }
    if ($row -notmatch '^\+' -or $row -match '^\+\+\+') { continue }
    if ($file -match $codeFile) {
        if (-not $added.ContainsKey($file)) { $added[$file] = [System.Collections.Generic.List[int]]::new() }
        $added[$file].Add($lineNo)
    }
    $lineNo++
}
foreach ($file in $added.Keys) {
    $content = & $git @('show', "${head}:$file")
    if (-not $content.Ok) { $unread.Add("$file could not be read at the head"); continue }
    $isPs = $file -match '(?i)\.(?:ps1|psm1|psd1)$'
    $hash = $file -match '(?i)\.(?:ps1|psm1|psd1|sh|bash|py|rb)$'
    # Block comments exist in PowerShell (<# #>) and the C family (/* */); a shell, Python or Ruby file has none.
    $hasBlock = $isPs -or -not $hash
    $open = if ($isPs) { '<#' } else { '/*' }
    $close = if ($isPs) { '#>' } else { '*/' }
    $marker = if ($hash) { '(?:^|\s)#' } else { '(?:^|\s)//(?:\s|$)' }
    $hereOpen = $null
    $inBlock = $false
    $isComment = @{}
    for ($n = 1; $n -le $content.Line.Count; $n++) {
        $text = "$($content.Line[$n - 1])"
        # A PowerShell here-string holds text, never comments: its lines are skipped up to the closing "@ or '@.
        if ($hereOpen) {
            if ($text.StartsWith($hereOpen)) { $hereOpen = $null }
            continue
        }
        $bare = $text -replace '"[^"]*"|''[^'']*''', ''
        $line = $inBlock
        if ($inBlock) {
            if ($bare.Contains($close)) { $inBlock = $false }
        } elseif ($hasBlock -and $bare -match $(if ($isPs) { '<#' } else { '(?:^|\s)/\*' })) {
            $line = $true
            if (-not $bare.Substring($bare.IndexOf($open) + 2).Contains($close)) { $inBlock = $true }
        }
        if (-not $line) { $line = $bare -match $marker -or (-not $hash -and $bare -match '^\s*\*') }
        if ($line) { $isComment[$n] = $true }
        if ($isPs -and -not $line -and $bare -match '@(["''])\s*$') { $hereOpen = "$($Matches[1])@" }
    }
    foreach ($n in $added[$file]) {
        $text = "$($content.Line[$n - 1])"
        if ($isComment.ContainsKey($n) -and $text.Length -gt 120) {
            & $add 'comment-length' "comment line of $($text.Length) characters, 120 at most" "${file}:${n}"
        }
    }
}

# --- Anchor issue: state, waive, size exception, spec, moved fixes --------------------
$issue = $null
if ($PSCmdlet.ParameterSetName -eq 'Online') {
    if ($anchor.Count -gt 0 -and $anchor[0] -match '^(?:([\w.-]+/[\w.-]+))?#(\d+)$') {
        $issueRepo = if ($Matches[1]) { $Matches[1] } else { $Repo }
        try { $issue = (& $withUtf8Output { & gh api "repos/$issueRepo/issues/$($Matches[2])" } | Out-String) | ConvertFrom-Json } catch { $issue = $null }
        if ($LASTEXITCODE -ne 0) { $issue = $null }
        $global:LASTEXITCODE = 0
    }
} elseif ($AnchorPath) {
    try { $issue = Get-Content -LiteralPath $AnchorPath -Raw | ConvertFrom-Json } catch { & $fail "anchor file unreadable: $($_.Exception.Message)" }
}
$issueBody = if ($issue) { "$($issue.body)" } else { '' }
$designLine = {
    param([string] $Label)
    $in = $false
    foreach ($row in ($issueBody -split "`r?`n")) {
        if ($row -match '^\s{0,3}##\s+(.*?)\s*$') { $in = $Matches[1] -eq 'Design'; continue }
        if ($in -and $row -match "^\s*(?:[-*+]\s+)?$Label\s*(.*?)\s*$") { return $Matches[1] }
    }
    $null
}
if ($issue) {
    if ("$($issue.state)" -ne 'open') { & $add 'anchor-open' "the anchor issue #$($issue.number) is $($issue.state), not open" }
    $exceptionReason = & $designLine 'Size exception:'
    $exception = [bool]$exceptionReason
} elseif ($anchor.Count -gt 0) {
    $unread.Add('the anchor issue could not be read; its open state, a size exception and a waiver are not checked')
}
if ($sumLines -gt 1000 -or $counted.Count -gt 40) {
    if (-not $exception) {
        & $add 'size' "$sumLines changed lines in $($counted.Count) files (tests, generated files and pure renames left out); over 1,000 lines or 40 files needs a line 'Size exception: <reason>' under '## Design' in the anchor issue"
    }
}

# Spec file: the one the PR adds or changes under docs/tasks/.
$specPath = @(@($changed | ForEach-Object { $_.Path }) | Where-Object { $_ -match '^docs/tasks/.*\.md$' })
foreach ($spec in $specPath) {
    $raw = (& $git @('show', "${head}:$spec")).Line
    if ($raw.Count -eq 0) { continue }
    $text = $raw -join "`n"
    $front = if ($text -match '(?s)^---\r?\n(.*?)\r?\n---') { $Matches[1] } else { '' }
    foreach ($key in 'repo', 'slug', 'title') { if ($front -notmatch "(?m)^${key}:\s*\S") { & $add 'spec-file' "frontmatter lacks '$key'" $spec } }
    if ($front -notmatch '(?m)^(?:issue|pr):\s*\S') { & $add 'spec-file' "frontmatter lacks 'issue' or 'pr'" $spec }
    $req = @($raw | Where-Object { $_ -match '^\s*[-*+]\s+\[[ xX]\]\s+REQ-\d+' })
    $number = @($req | ForEach-Object { if ($_ -match 'REQ-(\d+)') { [int]$Matches[1] } })
    # Gapless inside each block of a hundred (parallel PRs get fixed ID ranges and IDs are never renumbered).
    foreach ($group in ($number | Group-Object { if ($_ -lt 100) { 0 } else { [Math]::Floor($_ / 100) } })) {
        $ids = @($group.Group | Sort-Object)
        $wanted = @($ids[0]..($ids[0] + $ids.Count - 1))
        if (($ids -join ',') -ne ($wanted -join ',')) { & $add 'spec-file' "REQ numbers have a gap or a duplicate: $($ids -join ',')" $spec }
    }
    $reqLine = @($raw)
    for ($r = 0; $r -lt $reqLine.Count; $r++) {
        if ($reqLine[$r] -notmatch '^\s*[-*+]\s+\[ \]\s+(REQ-\d+)') { continue }
        $id = $Matches[1]
        # The point is its list item with its continuation lines, up to the next list item or a blank line.
        $block = $reqLine[$r]
        for ($k = $r + 1; $k -lt $reqLine.Count -and $reqLine[$k] -match '\S' -and $reqLine[$k] -notmatch '^\s*[-*+]\s'; $k++) { $block += " $($reqLine[$k])" }
        if ($block -notmatch 'not delivered:') { & $add 'spec-file' "$id is neither ticked nor 'not delivered:'" $spec }
    }
    if ($text -notmatch '(?m)^Review-(?:Mode|Modus):\s*(\S+)') { & $add 'spec-file' 'no line `Review-Mode: <mode>`' $spec }
    elseif ($Matches[1] -match '^`?hard') {
        $wave = @($bodyText | Where-Object {
                $_.Text -match '(?i)\b(?:wave|welle)\s*\d+\b' -and $_.Text -match '(?i)\b(?:opus|sonnet|haiku)\b' -and
                $_.Text -match '(?i)(?:issues?\D{0,4}\d|\d\s*issues?)' -and $_.Text -match '(?i)(?:nitpicks?\D{0,4}\d|\d\s*nitpicks?)' -and
                $_.Text -match '(?i)(?:questions?\D{0,4}\d|\d\s*questions?)' })
        if ($wave.Count -eq 0) { & $add 'spec-file' 'Review-Mode hard needs the wave report in the PR body: one line per wave with its number, models, focuses and the finding count per label issue, nitpick and question (0 too)' $spec }
    }
}

# Moved fixes.
$moved = $null
if ($PSCmdlet.ParameterSetName -eq 'Online') {
    $movedScript = Join-Path $PSScriptRoot 'find-moved-fixes.ps1'
    try { $moved = (& $movedScript -Repo $Repo -Pr $Pr -Json | Out-String).Trim() } catch { $moved = $null; $unread.Add("find-moved-fixes.ps1 failed: $($_.Exception.Message)") }
    $global:LASTEXITCODE = 0
} elseif ($MovedFixesPath) {
    try { $moved = Get-Content -LiteralPath $MovedFixesPath -Raw } catch { & $fail "moved-fixes file unreadable: $($_.Exception.Message)" }
}
if ($moved) {
    try { $parsed = @($moved | ConvertFrom-Json) } catch { & $fail "moved-fixes input is no JSON: $($_.Exception.Message)" }
    foreach ($h in @($parsed | Where-Object { "$($_.Result)" -eq 'moved-fix' })) {
        & $add 'moved-fix' "$($h.Text) (names $($h.File), carrier $($h.Carrier))" "$($h.Carrier):$($h.Line)"
    }
    foreach ($h in @($parsed | Where-Object { "$($_.Result)" -eq 'unavailable' })) { $unread.Add("moved fixes not checked: $($h.Text)") }
} elseif ($PSCmdlet.ParameterSetName -eq 'Online' -and $unread.Count -eq 0) { $unread.Add('find-moved-fixes.ps1 returned nothing') }

# --- Waive and result ----------------------------------------------------------------
$waived = $false
if ($Waive) {
    if ((& $designLine 'Form check waived:') -eq $Waive) { $waived = $true }
    else { & $add 'waive' "-Waive needs the line 'Form check waived: $Waive' under '## Design' in the anchor issue" }
}
$ok = $finding.Count -eq 0 -or ($waived -and @($finding | Where-Object Point -eq 'waive').Count -eq 0)
if ($Json) {
    [pscustomobject]@{ Ok = $ok; Head = $head; Waived = $waived; Finding = @($finding); Unread = @($unread) } | ConvertTo-Json -Depth 4
} else {
    foreach ($item in $finding) { "FORM $(if ($item.Where) { "$($item.Where) " })$($item.Point): $($item.Text)" }
    foreach ($item in $unread) { "UNREAD $item" }
    if ($waived) { "Form check waived: $Waive" }
    elseif ($ok -and $unread.Count -eq 0) { 'Form: ok' }
}
if (-not $ok) { exit 1 }
if ($unread.Count -gt 0) { exit 2 }
