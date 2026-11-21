#Requires -Version 7.6

<#
.SYNOPSIS
    Compute the machine section of a tracking issue - the block between `<!-- status:begin v1 ... -->`
    and `<!-- status:end -->` - from the body and REST facts, without AI; or check every open
    tracking issue of a repository against it (ww3d/playbook#670, q566 d).

.DESCRIPTION
    A tracking issue opens with a glance block (.agents/rules/carrier.md "Tracking Issue"): a
    `> [!NOTE]` alert the owner keeps by hand, and below it the section only the machine writes.
    This script is the machine's half. It writes nothing itself: edit-issue-body.ps1 (`-Status`, and
    every other write to a body with a section) puts the lines it returns into the body.

    Render (default): -Body and either -Repo and -Issue (facts read over REST) or -Facts (offline,
    for tests). The section holds one bullet per fact, in this order: `Open`, `Waiting on you`,
    `PRs` (left out without PRs), `Since summary` (left out without a change), `As of` (always last).
    Facts v1: the boxes of the body (get-checklist-items.ps1), questions from unticked boxes that carry
    `(question <N>)` or a link `fragen/#q<N>`, same-repo PRs from the `cross-referenced` events of the
    issue's timeline, the `state:*` label.

    The start marker carries `hand` (hash of the alert), `seen` (the fact state when the alert was
    last changed) and `since` (the time of that), `facts` (hash of the facts at the write) and `self`
    (hash of the lines between the markers). Hashes are the first 12 hex digits of SHA-256 over the
    canonical text (LF, Unicode NFC). Where `hand` differs from the alert's hash the anchor is set
    anew; otherwise the facts are compared with `seen`, and a marked change (a question new or
    done, a PR merged or closed, the `state:*` label changed, at least -BoxCount boxes or
    -BoxPercent percent changed) adds ` - Handzeilen pruefen` to the `Since summary` line. Nothing
    is blocked. A run where only `As of` would differ returns `unchanged`.

    Markers count only at a line start outside a code fence. A missing, doubled or reversed pair
    returns `broken` with the line numbers, and nothing is to be written.

    Check (-Check -Repo): reads every open issue labelled `tracking` page by page, writes nothing and
    prints one line per finding `STATUS <kind> <owner/repo>#<n>: <text>`:
    `edited` (`self` differs), `stale` (`facts` or `hand` differ), `misprint` (the render differs
    from the section though nothing else did), `summary` (a marked change), `missing` (a new tracking
    issue, or one over 5,000 characters, without a section or without an alert; a hint), `broken`.
    Exit 0 without a finding, 1 with one, 2 on a read error.

    Foreign text is escaped for Markdown; PR links are built from https://github.com/ or dropped; the
    link of a question is the one already standing in the body. No token is read or logged.

    This script is deliberately SELF-CONTAINED - it imports no module, because it is mirrored into
    every consumer via scripts/common/. It calls the siblings get-checklist-items.ps1 and
    get-rest-items.ps1.

.PARAMETER Body
    Render: the issue body.

.PARAMETER Repo
    owner/name. Render: with -Issue, where the facts are read. Check: the repository.

.PARAMETER Issue
    Render: the issue number, with -Repo. Check: only this issue.

.PARAMETER Facts
    Render, offline:
    `@{ State = '<label without state:>'; Prs = @(@{ Number = 1; State = 'open|merged|closed'; Url = '...' }) }`.

.PARAMETER Now
    The time of the write, `YYYY-MM-DDTHHMMZ`. Default: the clock, UTC.

.PARAMETER BoxCount
    A marked change from this many boxes changed. Default 3.

.PARAMETER BoxPercent
    A marked change from this share of the boxes changed. Default 20.

.PARAMETER Check
    Check every open tracking issue of -Repo.

.PARAMETER NewSince
    Check: a tracking issue created on or after this date counts as new for `missing`. Default 2026-11-20.

.INPUTS
    None.

.OUTPUTS
    Render: [pscustomobject] with Result (`unchanged`, `changed`, `absent` - no section yet, Lines is a new
    one -, `broken`), Lines (the section with both markers), Start and End (0-based line of each old
    marker, -1 without), Marked, Finding (kinds), Problem, Seen, HasHand (an alert stands in the head).
    Check: the finding lines.

.EXAMPLE
    ./scripts/common/get-status-block.ps1 -Repo ww3d/playbook -Check

    One line per tracking issue whose section is edited, stale, misprinted or marked.
#>

[CmdletBinding(DefaultParameterSetName = 'Render')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Render')]
    [AllowEmptyString()]
    [string] $Body,

    [Parameter(ParameterSetName = 'Render')]
    [Parameter(Mandatory, ParameterSetName = 'Check')]
    [string] $Repo,

    [Parameter(ParameterSetName = 'Render')]
    [Parameter(ParameterSetName = 'Check')]
    [int] $Issue,

    [Parameter(ParameterSetName = 'Render')]
    $Facts,

    [string] $Now,

    [ValidateRange(1, 1000)]
    [int] $BoxCount = 3,

    [ValidateRange(1, 100)]
    [int] $BoxPercent = 20,

    [Parameter(Mandatory, ParameterSetName = 'Check')]
    [switch] $Check,

    [Parameter(ParameterSetName = 'Check')]
    [string] $NewSince = '2026-11-20'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$checklistItems = Join-Path $PSScriptRoot 'get-checklist-items.ps1'
$restItems = Join-Path $PSScriptRoot 'get-rest-items.ps1'
if (-not $Now) { $Now = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HHmm'Z'") }
$lineBreak = "`r?`n"
$prWord = @{ open = 'offen'; merged = 'gemergt'; closed = 'geschlossen' }
$maxListed = 5
$maxChanges = 3

function Get-Hash([string] $Text) {
    $canonical = ($Text -replace "`r?`n", "`n").Normalize([System.Text.NormalizationForm]::FormC)
    $bytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($canonical))
    (-join ($bytes | ForEach-Object { $_.ToString('x2') })).Substring(0, 12)
}

# Foreign text inside Markdown: every punctuation character that can start markup is escaped, control characters go.
function ConvertTo-MarkdownText([string] $Text) {
    ($Text -replace '[\x00-\x1f\x7f]', ' ') -replace '([\\`*_{}\[\]()<>#+\-.!|~&])', '\$1'
}

# Per line: inside a fenced code block or on one of its fence lines (the fence rule of get-checklist-items.ps1).
function Get-FenceFlag([string[]] $Lines) {
    $fencePattern = '^\s*(?:>\s*)*(`{3,}|~{3,})(.*)$'
    $openFence = $null
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $fencePattern) {
            $fence = $Matches[1]
            $rest = $Matches[2]
            if ($null -eq $openFence) { $openFence = $fence }
            elseif ($fence[0] -eq $openFence[0] -and $fence.Length -ge $openFence.Length -and -not $rest.Trim()) { $openFence = $null }
            $true
            continue
        }
        $null -ne $openFence
    }
}

function Get-Attribute([string] $Text, [string] $Name) {
    if ($Text -cmatch "(?:^|\s)$Name=(\S*)") { $Matches[1] } else { $null }
}

function ConvertTo-StateName([string] $Label) {
    $name = ($Label -replace '^state:', '') -replace '[^A-Za-z0-9._]', '_'
    $name -replace '_{2,}', '_'
}

# --- Facts -----------------------------------------------------------------

# The facts the body itself holds: boxes and the questions behind them.
function Get-BodyFact([string] $Text) {
    $items = @(& $checklistItems -Body $Text)
    $question = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($item in $items) {
        $number = $null
        if ($item.Text -match '\(question (\d+)\)') { $number = [int]$Matches[1] }
        elseif ($item.Text -match 'fragen/#q(\d+)') { $number = [int]$Matches[1] }
        if ($null -eq $number) { continue }
        $link = ''
        if ($item.Text -match '\[[^\]]*\]\([^)\s]*fragen/#q\d+[^)\s]*\)') { $link = $Matches[0] }
        elseif ($item.Text -match '(https?://\S*fragen/#q\d+)') { $link = "[Frage $number]($($Matches[1]))" }
        $known = @($question | Where-Object Number -eq $number)
        if ($known) {
            if (-not $item.Checked) { $known[0].Done = $false }
            if (-not $known[0].Link) { $known[0].Link = $link }
        } else {
            $question.Add([pscustomobject]@{ Number = $number; Done = [bool]$item.Checked; Link = $link })
        }
    }
    $done = @($items | Where-Object Checked).Count
    [pscustomobject]@{ Open = $items.Count - $done; Done = $done; Question = @($question) }
}

function Get-RestFact([string] $Slug, [int] $Number) {
    $issue = @(& $restItems -Endpoint "repos/$Slug/issues/$Number")[0]
    $labelList = if ($issue.PSObject.Properties['labels']) { @($issue.labels) } else { @() }
    $label = @($labelList | Where-Object { "$($_.name)" -like 'state:*' } | Select-Object -First 1)
    $pr = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($entry in @(& $restItems -Endpoint "repos/$Slug/issues/$Number/timeline?per_page=100")) {
        if ("$($entry.event)" -ne 'cross-referenced') { continue }
        $source = $entry.PSObject.Properties['source']
        if (-not $source -or -not $source.Value.PSObject.Properties['issue'] -or -not $source.Value.issue) { continue }
        $from = $source.Value.issue
        if (-not $from.PSObject.Properties['pull_request'] -or -not $from.pull_request) { continue }
        if ("$($from.repository.full_name)" -ne $Slug) { continue }
        $state = if ($from.pull_request.merged_at) { 'merged' } elseif ("$($from.state)" -eq 'open') { 'open' } else { 'closed' }
        if (@($pr | Where-Object Number -eq ([int]$from.number)).Count -eq 0) {
            $pr.Add([pscustomobject]@{ Number = [int]$from.number; State = $state; Url = "https://github.com/$Slug/pull/$($from.number)" })
        }
    }
    [pscustomobject]@{ State = if ($label) { ConvertTo-StateName $label[0].name } else { '' }; Prs = @($pr) }
}

function Join-Fact($BodyFact, $RestFact) {
    $pr = @(@($RestFact.Prs) | Where-Object { $_ } | ForEach-Object {
            $state = "$($_.State)"
            if (-not $prWord.ContainsKey($state)) { throw "unknown PR state '$state'" }
            $url = if ($_.PSObject.Properties['Url'] -and "$($_.Url)".StartsWith('https://github.com/', [StringComparison]::Ordinal)) { "$($_.Url)" } else { '' }
            [pscustomobject]@{ Number = [int]$_.Number; State = $state; Url = $url }
        } | Sort-Object Number)
    [pscustomobject]@{
        Open = $BodyFact.Open; Done = $BodyFact.Done; Question = @($BodyFact.Question)
        State = ConvertTo-StateName "$($RestFact.State)"; Pr = $pr
    }
}

# open=3;done=5;state=review;q1250=open;pr12=merged - what the marker's `seen` and `facts` hold.
function ConvertTo-SeenText($Fact) {
    $part = @("open=$($Fact.Open)", "done=$($Fact.Done)", "state=$($Fact.State)")
    $part += @($Fact.Question | Sort-Object Number | ForEach-Object { "q$($_.Number)=$(if ($_.Done) { 'done' } else { 'open' })" })
    $part += @($Fact.Pr | ForEach-Object { "pr$($_.Number)=$($_.State)" })
    ($part -join ';') -replace '-{2,}', '-'
}

function ConvertFrom-SeenText([string] $Text) {
    $map = @{}
    foreach ($pair in ($Text -split ';')) {
        $at = $pair.IndexOf('=')
        if ($at -gt 0) { $map[$pair.Substring(0, $at)] = $pair.Substring($at + 1) }
    }
    $map
}

# "1 Kasten", "2 Kaesten": the count with its noun in the right number.
function Format-BoxCount([int] $Count) { if ($Count -eq 1) { '1 Kasten' } else { "$Count Kaesten" } }

# What changed since `seen`: plain German, and whether the change is one that makes the alert suspect.
function Get-Change($Fact, [hashtable] $Seen) {
    $text = [System.Collections.Generic.List[string]]::new()
    $marked = $false
    foreach ($q in ($Fact.Question | Sort-Object Number)) {
        $was = $Seen["q$($q.Number)"]
        $is = if ($q.Done) { 'done' } else { 'open' }
        if (-not $was) { $text.Add("Frage $($q.Number) neu"); $marked = $true }
        elseif ($was -ne $is) {
            $text.Add($(if ($q.Done) { "Frage $($q.Number) beantwortet" } else { "Frage $($q.Number) wieder offen" }))
            $marked = $true
        }
    }
    foreach ($key in ($Seen.Keys | Where-Object { $_ -match '^q(\d+)$' } | Sort-Object { [int]($_ -replace '^q', '') })) {
        $number = [int]($key -replace '^q', '')
        if (@($Fact.Question | Where-Object Number -eq $number).Count -eq 0) { $text.Add("Frage $number entfernt") }
    }
    foreach ($pr in $Fact.Pr) {
        $was = $Seen["pr$($pr.Number)"]
        if (-not $was) {
            $text.Add("PR $($pr.Number) neu ($($prWord[$pr.State]))")
            if ($pr.State -ne 'open') { $marked = $true }
        } elseif ($was -ne $pr.State) {
            $text.Add("PR $($pr.Number) $($prWord[$pr.State])")
            if ($pr.State -ne 'open') { $marked = $true }
        }
    }
    $wasState = if ($Seen.ContainsKey('state')) { $Seen['state'] } else { '' }
    if ($wasState -ne $Fact.State) {
        $from = if ($wasState) { ConvertTo-MarkdownText $wasState } else { 'ohne' }
        $to = if ($Fact.State) { ConvertTo-MarkdownText $Fact.State } else { 'ohne' }
        $text.Add("Status $from zu $to")
        $marked = $true
    }
    $wasDone = [int]$(if ($Seen.ContainsKey('done')) { $Seen['done'] } else { $Fact.Done })
    $wasOpen = [int]$(if ($Seen.ContainsKey('open')) { $Seen['open'] } else { $Fact.Open })
    $delta = $Fact.Done - $wasDone
    $all = $Fact.Open + $Fact.Done
    if ($delta -ne 0) {
        $text.Add($(if ($delta -gt 0) { "$(Format-BoxCount $delta) erledigt" } else { "$(Format-BoxCount (-$delta)) wieder offen" }))
        if ([math]::Abs($delta) -ge $BoxCount -or ($all -gt 0 -and [math]::Abs($delta) * 100 -ge $BoxPercent * $all)) { $marked = $true }
    }
    $added = $all - ($wasDone + $wasOpen)
    if ($added -gt 0) { $text.Add("$(Format-BoxCount $added) neu") }
    elseif ($added -lt 0) { $text.Add("$(Format-BoxCount (-$added)) weniger") }
    [pscustomobject]@{ Text = @($text); Marked = $marked }
}

# --- The section ------------------------------------------------------------

function Format-Section($Fact, [string] $SinceLine, [string] $AsOf) {
    $line = [System.Collections.Generic.List[string]]::new()
    $line.Add("- Open: $($Fact.Open) of $($Fact.Open + $Fact.Done)")
    $waiting = @($Fact.Question | Where-Object { -not $_.Done })
    if ($waiting) {
        $shown = @($waiting | Select-Object -First $maxListed | ForEach-Object { if ($_.Link) { $_.Link } else { "Frage $($_.Number)" } })
        if ($waiting.Count -gt $maxListed) { $shown += "+ $($waiting.Count - $maxListed) weitere" }
        $line.Add("- Waiting on you: $($shown -join ', ')")
    } else { $line.Add('- Waiting on you: keine') }
    if ($Fact.Pr.Count) {
        $shown = @($Fact.Pr | Select-Object -First $maxListed | ForEach-Object {
                $label = "#$($_.Number)"
                "$(if ($_.Url) { "[$label]($($_.Url))" } else { $label }) $($prWord[$_.State])"
            })
        if ($Fact.Pr.Count -gt $maxListed) { $shown += "+ $($Fact.Pr.Count - $maxListed) weitere" }
        $line.Add("- PRs: $($shown -join ', ')")
    }
    if ($SinceLine) { $line.Add($SinceLine) }
    $line.Add("- As of: $AsOf")
    @($line)
}

function Get-StatusResult([string] $Text, $Fact) {
    $lines = @($Text -split $lineBreak)
    $fenced = @(Get-FenceFlag $lines)
    $begin = @(); $end = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($fenced[$i]) { continue }
        if ($lines[$i] -cmatch '^<!--\s*status:begin\b') { $begin += $i }
        elseif ($lines[$i] -cmatch '^<!--\s*status:end\s*-->\s*$') { $end += $i }
    }
    $number = { param($Index) ($Index | ForEach-Object { $_ + 1 }) -join ', ' }
    $result = [pscustomobject]@{
        Result = 'unchanged'; Lines = @(); Start = -1; End = -1; Marked = $false; Finding = @(); Problem = ''; Seen = ''; HasHand = $false
    }
    $problem = ''
    if ($begin.Count -ne $end.Count -or $begin.Count -gt 1) {
        $problem = "status markers are doubled or unpaired: begin at line(s) $(& $number $begin), end at line(s) $(& $number $end)"
    } elseif ($begin.Count -eq 1 -and $end[0] -lt $begin[0]) {
        $problem = "status markers are reversed: begin at line $(& $number $begin), end at line $(& $number $end)"
    } elseif ($begin.Count -eq 1 -and $lines[$begin[0]] -cnotmatch '^<!--\s*status:begin\s+v1\b.*-->\s*$') {
        $problem = "the start marker at line $($begin[0] + 1) is not a v1 marker"
    }
    if ($problem) { $result.Result = 'broken'; $result.Problem = $problem; $result.Finding = @('broken'); return $result }

    # The alert: the first `> [!NOTE]` of the head and the quote lines that follow it.
    $headEnd = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $fenced[$i] -and $lines[$i] -match '^ {0,3}##[ \t]') { $headEnd = $i; break }
    }
    $alert = @()
    for ($i = 0; $i -lt $headEnd; $i++) {
        if (-not $fenced[$i] -and $lines[$i] -cmatch '^>\s*\[!NOTE\]\s*$') {
            $alert = @($lines[$i])
            for ($j = $i + 1; $j -lt $headEnd -and $lines[$j] -match '^>'; $j++) { $alert += $lines[$j] }
            break
        }
    }
    $result.HasHand = $alert.Count -gt 0
    $handNow = Get-Hash ($alert -join "`n")
    $seenNow = ConvertTo-SeenText $Fact
    $factsNow = Get-Hash $seenNow

    $old = $begin.Count -eq 1
    $oldHand = $null; $oldSeen = $null; $oldSince = $null; $oldFacts = $null; $oldSelf = $null; $oldAsOf = $null
    $oldInner = @()
    if ($old) {
        $startLine = $lines[$begin[0]]
        $oldHand = Get-Attribute $startLine 'hand'; $oldSeen = Get-Attribute $startLine 'seen'
        $oldSince = Get-Attribute $startLine 'since'; $oldFacts = Get-Attribute $startLine 'facts'
        $oldSelf = Get-Attribute $startLine 'self'
        $oldInner = if ($end[0] - $begin[0] -gt 1) { @($lines[($begin[0] + 1)..($end[0] - 1)]) } else { @() }
        foreach ($inner in $oldInner) { if ($inner -cmatch '^- As of: (\S+)\s*$') { $oldAsOf = $Matches[1] } }
        $result.Start = $begin[0]; $result.End = $end[0]
    }
    $anchorNew = -not $old -or $oldHand -ne $handNow -or -not $oldSeen -or -not $oldSince
    $seen = $seenNow; $since = $Now; $sinceLine = ''
    if (-not $anchorNew) {
        $seen = $oldSeen; $since = $oldSince
        $change = Get-Change $Fact (ConvertFrom-SeenText $oldSeen)
        if ($change.Text.Count) {
            $shown = @($change.Text | Select-Object -First $maxChanges)
            $tail = if ($change.Text.Count -gt $maxChanges) { " und $($change.Text.Count - $maxChanges) weitere" } else { '' }
            $sinceLine = "- Since summary ($since): $($shown -join ', ')$tail$(if ($change.Marked) { ' - Handzeilen pruefen' })"
            $result.Marked = $change.Marked
        }
    }
    $build = {
        param([string] $AsOf)
        $inner = Format-Section $Fact $sinceLine $AsOf
        $selfHash = Get-Hash ($inner -join "`n")
        $startMarker = "<!-- status:begin v1 hand=$handNow seen=$seen since=$since facts=$factsNow self=$selfHash - written by scripts/common/edit-issue-body.ps1, edit outside only -->"
        @($startMarker) + $inner + @('<!-- status:end -->')
    }
    $result.Seen = $seenNow
    if (-not $old) {
        $result.Result = 'absent'
        $result.Lines = & $build $Now
        return $result
    }
    $oldBlock = @($lines[$begin[0]..$end[0]])
    $same = & $build $(if ($oldAsOf) { $oldAsOf } else { $Now })
    if (($same -join "`n") -ceq ($oldBlock -join "`n")) {
        $result.Lines = $oldBlock
    } else {
        $result.Result = 'changed'
        $result.Lines = & $build $Now
    }
    $kind = [System.Collections.Generic.List[string]]::new()
    $edited = $oldSelf -ne (Get-Hash ($oldInner -join "`n"))
    $stale = $oldFacts -ne $factsNow -or $oldHand -ne $handNow
    if ($edited) { $kind.Add('edited') }
    if ($stale) { $kind.Add('stale') }
    if (-not $edited -and -not $stale -and $result.Result -eq 'changed') { $kind.Add('misprint') }
    if ($result.Marked) { $kind.Add('summary') }
    $result.Finding = @($kind)
    $result
}

function Get-CharacterCount([string] $Text) {
    $Text.Length - [regex]::Matches($Text, '[\uDC00-\uDFFF]').Count
}

# --- Check -------------------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'Check') {
    $found = 0
    $unread = 0
    try {
        $issues = @(& $restItems -Endpoint "repos/$Repo/issues?state=open&labels=tracking&per_page=100")
    } catch {
        "get-status-block: cannot read the open tracking issues of ${Repo}: $($_.Exception.Message)"
        exit 2
    }
    $newFrom = [DateTime]::Parse($NewSince, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
    foreach ($item in $issues) {
        if ($item.PSObject.Properties['pull_request'] -and $item.pull_request) { continue }
        if ($Issue -and [int]$item.number -ne $Issue) { continue }
        $slug = "$Repo#$($item.number)"
        $text = "$($item.body)"
        try {
            $fact = Join-Fact (Get-BodyFact $text) (Get-RestFact $Repo ([int]$item.number))
            $status = Get-StatusResult $text $fact
        } catch {
            "STATUS unread ${slug}: $($_.Exception.Message)"
            $unread++
            continue
        }
        $say = {
            param([string] $Kind, [string] $Message)
            "STATUS $Kind ${slug}: $Message"
            $script:found++
        }
        if ($status.Result -eq 'broken') { & $say 'broken' $status.Problem; continue }
        if ($status.Result -eq 'absent') {
            $created = [DateTime]::Parse("$($item.created_at)", [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
            if ($created -ge $newFrom -or (Get-CharacterCount $text) -gt 5000) {
                & $say 'missing' 'hint: no status section (new tracking issue or over 5,000 characters)'
            }
            continue
        }
        foreach ($kind in $status.Finding) {
            $message = switch ($kind) {
                'edited' { 'the section was edited by hand (self differs)' }
                'stale' { 'facts or alert changed since the section was written' }
                'misprint' { 'the render differs from the section' }
                'summary' { 'a marked change since the alert was written - Handzeilen pruefen' }
            }
            & $say $kind $message
        }
        if (-not $status.HasHand) { & $say 'missing' 'hint: no alert (> [!NOTE]) in the head' }
    }
    if ($unread -gt 0) { exit 2 }
    if ($found -gt 0) { exit 1 }
    return
}

# --- Render ------------------------------------------------------------------
$bodyFact = Get-BodyFact $Body
if ($PSBoundParameters.ContainsKey('Facts') -and $null -ne $Facts) {
    $rest = [pscustomobject]@{
        State = if ($Facts -is [hashtable] -and $Facts.ContainsKey('State')) { $Facts['State'] } elseif ($Facts.PSObject.Properties['State']) { $Facts.State } else { '' }
        Prs   = if ($Facts -is [hashtable] -and $Facts.ContainsKey('Prs')) { @($Facts['Prs']) } elseif ($Facts.PSObject.Properties['Prs']) { @($Facts.Prs) } else { @() }
    }
    $rest.Prs = @($rest.Prs | ForEach-Object { if ($_ -is [hashtable]) { [pscustomobject]$_ } else { $_ } })
} elseif ($Repo -and $Issue) {
    $rest = Get-RestFact $Repo $Issue
} else {
    $rest = [pscustomobject]@{ State = ''; Prs = @() }
}
Get-StatusResult $Body (Join-Fact $bodyFact $rest)
