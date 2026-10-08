#Requires -Version 7.4

<#
.SYNOPSIS
    Merge gate: hold the run lines of a pull request body against the merge
    head and check that a review verdict exists.

.DESCRIPTION
    .agents/rules/pr.md, section "Merge", has the merger run this script before
    merging; the merger runs no full test run of its own. The script checks
    four things and prints each with its finding:

    1. Run line for the head. The newest `voll` run line under the heading
       "Wie getestet" names the head the PR has now (Kopf equal to the head
       OID, or a prefix of at least 7 characters). Or one of the documented
       exceptions:
       - A diff without code (every changed file is Markdown or under docs/):
         a `format` run line names the head.
       - After a full run, the commits after the gated head touch only
         Markdown / docs files, only test files, or only a review ledger file;
         or the head is a rebase of the gated head (the code paths of the two
         trees do not differ). Docs, tests and rebase need BOTH a `format` and
         a `gefiltert` run line naming the head. A comment-only fix in a code
         file is not machine-checkable and does not qualify: it needs a new
         full run.
    2. No red test. Every run line check 1 relies on says `rot: 0`, so a newer
       red run cannot hide behind an older green one.
    3. Base head. The `Basis` of the newest `voll` run line is the current head
       of the PR's base branch; when the base moved since, the gate fails with
       "main moved since the full run". Offline without -BaseSha it is not
       compared, and the finding says so.
    4. Review verdict. An APPROVED review by an account other than the PR
       author (the latest review of each account decides, so a later
       CHANGES_REQUESTED withdraws an approve; an approve given on an older
       commit still counts and is noted, because the requirement is that a
       verdict exists, not on which commit); or a review or PR comment of another
       account with a line `Review-Verdikt: approve <sha>` whose sha matches the
       head; or, only with -SameAccount (author and reviewer are one account), the
       same line in a review of the author's own account. A doc-only
       PR (only docs/** and root *.md other than AGENTS.md and CLAUDE.md) needs no verdict
       (.agents/rules/docs.md, section "Documentation").

    Run line format, one per line (a leading list marker is allowed):

        Lauf | Kopf <sha> | Basis <sha> | Modus <voll|gefiltert|format> | <gewaehlt>/<gesamt> | rot: <0|names> | flaky: <0|names> | <dauer> | <rechner> | <plattformen>

    A line starting with `Lauf |` that does not follow it is reported and
    ignored. Exit code 1 when the PR is not merge-ready, 0 when it is.

    Two input modes. Online (-Repo and -Pr, REST over gh) reads body, head,
    base head, author, changed files, reviews, comments and commits itself; the
    commits after the gated head come from the working copy at -Root when it
    holds both heads, else from the forge, fetched in parallel. Offline
    (-BodyPath and -HeadSha, plus optional -ReviewsPath, -CommitsPath,
    -FilesPath and -BaseSha) reads files, for tests and for a body copied out
    of the forge.

.PARAMETER Repo
    owner/name of the repository, with -Pr.

.PARAMETER Pr
    Pull request number, with -Repo.

.PARAMETER BodyPath
    Offline: file holding the PR body.

.PARAMETER HeadSha
    Offline: the PR's current head OID.

.PARAMETER ReviewsPath
    Offline: JSON file `{ "author": "<login>", "reviews": [ { "user": { "login" },
    "state", "body", "commit_id" } ], "comments": [ { "user": { "login" }, "body" } ] }`.
    Absent means no review and no comment.

.PARAMETER CommitsPath
    Offline: JSON array `[ { "sha", "files": [ "<path>" ] } ]`, the PR's commits
    oldest first. Without it the commits come from the working copy at -Root.

.PARAMETER FilesPath
    Offline: JSON array of the paths the PR changes. Without it the diff counts
    as holding code.

.PARAMETER BaseSha
    Offline: the current head of the PR's base branch, for the Basis comparison.

.PARAMETER Root
    Working copy that answers the git questions (the commits after the gated
    head, the code paths between two heads). Default: the current directory.

.PARAMETER SameAccount
    The merger states that author and reviewer are one account (`.agents/rules/pr.md` § "Accounts per Seat").
    Only then does a `Review-Verdikt: approve <sha>` line in a review of the author's own account count;
    the forge data cannot tell this case from an author approving unreviewed work, so the switch carries it.
    Without it a verdict needs another account.

.PARAMETER Json
    Serialize the result as JSON instead of printing it.

.INPUTS
    None.

.OUTPUTS
    [string] one line per check and a verdict; with -Json one object (MergeReady,
    Head, Check[] with Name, Ok, Finding).

.EXAMPLE
    ./scripts/common/test-merge-ready.ps1 -Repo ww3d/playbook -Pr 352

.EXAMPLE
    ./scripts/common/test-merge-ready.ps1 -BodyPath body.md -HeadSha 4f2a1c9 -ReviewsPath reviews.json
#>

[CmdletBinding(DefaultParameterSetName = 'Online')]
[OutputType([string])]
param(
    [Parameter(Mandatory, ParameterSetName = 'Online')][ValidatePattern('^[\w.-]+/[\w.-]+$')][string] $Repo,
    [Parameter(Mandatory, ParameterSetName = 'Online')][ValidateRange(1, [int]::MaxValue)][int] $Pr,
    [Parameter(Mandatory, ParameterSetName = 'Offline')][string] $BodyPath,
    [Parameter(Mandatory, ParameterSetName = 'Offline')][ValidatePattern('^[0-9a-fA-F]{7,40}$')][string] $HeadSha,
    [Parameter(ParameterSetName = 'Offline')][string] $ReviewsPath,
    [Parameter(ParameterSetName = 'Offline')][string] $CommitsPath,
    [Parameter(ParameterSetName = 'Offline')][string] $FilesPath,
    [Parameter(ParameterSetName = 'Offline')][ValidatePattern('^[0-9a-fA-F]{7,40}$')][string] $BaseSha,
    [string] $Root = '.',
    [switch] $SameAccount,
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Input ------------------------------------------------------------------
# Every page of a REST endpoint, flattened: the reader the sibling scripts share.
$restItems = Join-Path $PSScriptRoot 'get-rest-items.ps1'
$readJson = {
    param([string] $File)
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "File not found: '$File'." }
    Get-Content -LiteralPath $File -Raw | ConvertFrom-Json
}
# One git question to the working copy at -Root; Ok is false when git or the object is missing.
$git = {
    param([string[]] $GitArgument)
    try {
        $text = & git -C $workingCopy -c core.quotepath=off @GitArgument 2>$null
        $ok = $LASTEXITCODE -eq 0
    } catch {
        $text = @()
        $ok = $false
    }
    $global:LASTEXITCODE = 0
    [pscustomobject]@{ Ok = $ok; Line = @($text) }
}
$hasCommit = { param([string] $Sha) (& $git @('cat-file', '-e', "$Sha^{commit}")).Ok }

$body = ''
$head = ''
$author = ''
$baseHead = ''
$review = @()
$comment = @()
# Paths the PR changes; $null when not known (then the diff counts as holding code).
$prFile = $null
# Oldest first; $null without -CommitsPath offline. Online the list is only the fallback
# for a working copy that lacks the heads.
$commit = $null
$filesOf = $null
$online = $PSCmdlet.ParameterSetName -eq 'Online'
$workingCopy = $Root

if ($online) {
    $pull = @(& $restItems -Endpoint "repos/$Repo/pulls/$Pr")[0]
    $body = "$($pull.body)"
    $head = "$($pull.head.sha)"
    $author = "$($pull.user.login)"
    $baseHead = "$(@(& $restItems -Endpoint "repos/$Repo/branches/$($pull.base.ref)")[0].commit.sha)"
    # A rename names both paths: a move out of code into docs/ must not look like a docs change.
    $prFile = @(& $restItems -Endpoint "repos/$Repo/pulls/$Pr/files?per_page=100" | ForEach-Object {
            "$($_.filename)"
            if ($_.PSObject.Properties['previous_filename']) { "$($_.previous_filename)" }
        })
    $review = @(& $restItems -Endpoint "repos/$Repo/pulls/$Pr/reviews?per_page=100")
    $comment = @(& $restItems -Endpoint "repos/$Repo/issues/$Pr/comments?per_page=100")
    $commit = {
        @(& $restItems -Endpoint "repos/$Repo/pulls/$Pr/commits?per_page=100" | ForEach-Object { [pscustomobject]@{ sha = "$($_.sha)" } })
    }
} else {
    if (-not (Test-Path -LiteralPath $BodyPath -PathType Leaf)) { throw "Body file not found: '$BodyPath'." }
    $body = Get-Content -LiteralPath $BodyPath -Raw
    $head = $HeadSha
    $baseHead = $BaseSha
    if ($FilesPath) { $prFile = @(& $readJson $FilesPath | ForEach-Object { "$_" }) }
    if ($ReviewsPath) {
        $data = & $readJson $ReviewsPath
        $author = if ($data.PSObject.Properties['author']) { "$($data.author)" } else { '' }
        if ($data.PSObject.Properties['reviews']) { $review = @($data.reviews) }
        if ($data.PSObject.Properties['comments']) { $comment = @($data.comments) }
    }
    if ($CommitsPath) {
        $offlineCommit = @(& $readJson $CommitsPath)
        $commit = { $offlineCommit }.GetNewClosure()
        $filesOf = {
            param([string] $Sha)
            $found = $offlineCommit | Where-Object { $_.sha -eq $Sha } | Select-Object -First 1
            if ($found -and $found.PSObject.Properties['files']) { @($found.files) } else { @() }
        }.GetNewClosure()
    }
}

# The commits after the gated head, each with its files, from the working copy.
$localAfter = {
    param([string] $Gated)
    $list = [System.Collections.Generic.List[pscustomobject]]::new()
    $current = $null
    foreach ($line in (& $git @('log', '--reverse', '--name-only', '--format=>>%H', "$Gated..$head")).Line) {
        if ($line.StartsWith('>>')) {
            $current = [pscustomobject]@{ sha = $line.Substring(2); files = [System.Collections.Generic.List[string]]::new() }
            $list.Add($current)
        } elseif ($line.Trim() -and $current) {
            $current.files.Add($line.Trim())
        }
    }
    @($list)
}
# The files of several commits from the forge, one request per commit but in parallel, every
# page of a commit's file list flattened (a commit of more than 300 files is paged).
$forgeFiles = {
    param([string[]] $Sha)
    $found = @($Sha | ForEach-Object -ThrottleLimit 8 -Parallel {
            $raw = & gh api "repos/$($using:Repo)/commits/$_" --paginate --slurp 2>$null
            $failed = $LASTEXITCODE -ne 0
            $file = @()
            if (-not $failed) {
                $file = @($raw | ConvertFrom-Json | ForEach-Object { $_ } |
                        ForEach-Object { if ($_.PSObject.Properties['files']) { $_.files } } |
                        ForEach-Object {
                            "$($_.filename)"
                            if ($_.PSObject.Properties['previous_filename']) { "$($_.previous_filename)" }
                        })
            }
            [pscustomobject]@{ Sha = $_; Failed = $failed; File = $file }
        })
    $failedSha = @($found | Where-Object Failed | ForEach-Object Sha)
    if ($failedSha.Count -gt 0) { throw "gh api repos/$Repo/commits/<sha> failed for $($failedSha -join ', ')" }
    $found
}

# --- Run lines --------------------------------------------------------------
$runLine = [System.Collections.Generic.List[pscustomobject]]::new()
$ignored = [System.Collections.Generic.List[string]]::new()
$partial = [System.Collections.Generic.List[string]]::new()
$inSection = $false
foreach ($raw in ($body -split "`r?`n")) {
    if ($raw -match '^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$') {
        $inSection = $Matches[1] -match '(?i)^Wie getestet\b'
        continue
    }
    if (-not $inSection) { continue }
    $text = ($raw -replace '^\s*(?:[-*+]\s+)?', '').Trim().Trim('`')
    if ($text -notmatch '^Lauf\s*\|') { continue }
    $field = @($text -split '\|' | ForEach-Object { $_.Trim() })
    $ok = $field.Count -ge 10 -and
    $field[1] -match '^Kopf\s+([0-9a-fA-F]{7,40})$' -and ($sha = $Matches[1]) -and
    $field[2] -match '^Basis\s+(\S+)$' -and ($basis = $Matches[1]) -and
    $field[3] -match '^Modus\s+(voll|gefiltert|format)$' -and ($mode = $Matches[1]) -and
    $field[4] -match '^(\d+)/(\d+)$' -and ($chosen = [decimal]$Matches[1]) -ge 0 -and ($total = [decimal]$Matches[2]) -ge 0 -and
    $field[5] -match '^rot:\s*(\S.*)$' -and ($red = $Matches[1]) -and
    $field[6] -match '^flaky:\s*\S'
    if (-not $ok) { $ignored.Add($text); continue }
    # A voll run is the whole suite: a partial count is a gefiltert run under the wrong name.
    if ($mode -eq 'voll' -and $chosen -ne $total) { $partial.Add($text); continue }
    $runLine.Add([pscustomobject]@{ Sha = $sha.ToLowerInvariant(); Basis = $basis; Mode = $mode; Red = $red; Text = $text })
}

$namesHead = {
    param([string] $Sha)
    $Sha.Length -ge 7 -and $head.StartsWith($Sha, [StringComparison]::OrdinalIgnoreCase)
}
$short = { param([string] $Sha) $Sha.Substring(0, [Math]::Min(7, $Sha.Length)) }

$check = [System.Collections.Generic.List[pscustomobject]]::new()
$add = { param([string] $Name, [bool] $Ok, [string] $Finding) $check.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Finding = $Finding }) }

$note = if ($ignored.Count -gt 0) { " ($($ignored.Count) malformed run line(s) ignored)" } else { '' }
if ($partial.Count -gt 0) { $note += " ($($partial.Count) voll run line(s) ignored: gewaehlt is not gesamt)" }
$newestFull = @($runLine | Where-Object Mode -EQ 'voll') | Select-Object -Last 1
$formatHead = @($runLine | Where-Object { $_.Mode -eq 'format' -and (& $namesHead $_.Sha) }) | Select-Object -Last 1
$filteredHead = @($runLine | Where-Object { $_.Mode -eq 'gefiltert' -and (& $namesHead $_.Sha) }) | Select-Object -Last 1

$docs = '(?i)\.md$|^docs/'
$tests = '(?i)(^|/)(tests?|__tests__)/|\.tests?\.\w+$|\.spec\.\w+$|_test\.go$'
# A review round's ledger file is committed by the dev with its next push; it carries no code,
# so it owes no run line.
$ledger = '(?i)^docs/decisions/[^/]+-ledger\.jsonl$'
# What .agents/rules/docs.md calls a doc-only PR: docs/** and root *.md other than AGENTS.md and
# CLAUDE.md, no skill or rule file.
$docOnly = '(?i)^docs/|^(?!(AGENTS|CLAUDE)\.md$)[^/]+\.md$'
$noCode = $null -ne $prFile -and $prFile.Count -gt 0 -and @($prFile | Where-Object { $_ -notmatch $docs }).Count -eq 0
$reviewExempt = $null -ne $prFile -and $prFile.Count -gt 0 -and @($prFile | Where-Object { $_ -notmatch $docOnly }).Count -eq 0

# The run lines checks 1 and 2 rely on, and whether the Basis of the newest voll line counts.
$relied = [System.Collections.Generic.List[pscustomobject]]::new()
$basisCounts = $false

# 1. a voll run line for the head, a format line for a diff without code, or the documented exception
if ($newestFull -and (& $namesHead $newestFull.Sha)) {
    $relied.Add($newestFull)
    $basisCounts = $true
    & $add 'run-line' $true "newest voll run line names the head $(& $short $head)$note"
} elseif ($noCode) {
    if ($formatHead) {
        $relied.Add($formatHead)
        & $add 'run-line' $true "the diff holds no code; a format run line names the head $(& $short $head)$note"
    } else {
        & $add 'run-line' $false "the diff holds no code, but no format run line names the head $(& $short $head)$note"
    }
} elseif (-not $newestFull) {
    & $add 'run-line' $false "no run line with Modus voll under 'Wie getestet'$note"
} else {
    $relied.Add($newestFull)
    $basisCounts = $true
    $reason = "newest voll run line names $(& $short $newestFull.Sha), the head is $(& $short $head)"
    $gated = $newestFull.Sha
    # Where the commits after the gated head come from: -CommitsPath, the working copy, the forge.
    $source = if ($commit -and -not $online) { 'json' } elseif ((& $hasCommit $gated) -and (& $hasCommit $head)) { 'git' } elseif ($online) { 'forge' } else { 'none' }
    $after = $null
    $rebase = $false
    $fail = ''
    switch ($source) {
        'none' { $fail = "$reason; the commits after it are not known (no -CommitsPath and no working copy at -Root holding both heads), the exception cannot be checked" }
        'git' {
            if ((& $git @('merge-base', '--is-ancestor', $gated, $head)).Ok) {
                $after = @(& $localAfter $gated)
            } else {
                # Not a descendant: a rebase is fine when no code path differs between the two trees.
                $rebase = $true
                $changed = @((& $git @('diff', '--name-only', $gated, $head)).Line | Where-Object { $_.Trim() -and $_ -notmatch $docs })
                if ($changed.Count -gt 0) {
                    $fail = "$reason; the head is not a descendant of it and code paths differ ($(@($changed | Select-Object -First 3) -join ', '))"
                }
            }
        }
        default {
            $all = @(& $commit)
            $from = -1
            for ($i = 0; $i -lt $all.Count; $i++) {
                if ($all[$i].sha.StartsWith($gated, [StringComparison]::OrdinalIgnoreCase)) { $from = $i }
            }
            $headListed = @($all | Where-Object { "$($_.sha)".Length -ge 7 -and $head.StartsWith("$($_.sha)", [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            if ($from -lt 0) {
                $fail = "$reason; that head is not among the PR's commits"
            } elseif (-not $headListed) {
                $fail = "$reason; the head is not among the PR's commits"
            } else {
                $later = if ($from + 1 -lt $all.Count) { @($all[($from + 1)..($all.Count - 1)]) } else { @() }
                if ($source -eq 'json') {
                    $after = @($later | ForEach-Object { [pscustomobject]@{ sha = $_.sha; files = @(& $filesOf $_.sha) } })
                } else {
                    $byCommit = @{}
                    if ($later.Count -gt 0) { foreach ($item in (& $forgeFiles @($later.sha))) { $byCommit[$item.Sha] = @($item.File) } }
                    $after = @($later | ForEach-Object { [pscustomobject]@{ sha = $_.sha; files = @($byCommit[$_.sha]) } })
                }
            }
        }
    }

    if (-not $fail -and -not $rebase -and @($after).Count -eq 0) { $fail = "$reason; no commit after it was found" }
    $bad = [System.Collections.Generic.List[string]]::new()
    $onlyLedger = -not $rebase
    foreach ($later in $after) {
        $path = @($later.files)
        $isLedger = $path.Count -gt 0 -and @($path | Where-Object { $_ -notmatch $ledger }).Count -eq 0
        if ($isLedger) { continue }
        $onlyLedger = $false
        $onlyDocs = $path.Count -gt 0 -and @($path | Where-Object { $_ -notmatch $docs }).Count -eq 0
        $onlyTests = $path.Count -gt 0 -and @($path | Where-Object { $_ -notmatch $tests }).Count -eq 0
        if (-not ($onlyDocs -or $onlyTests)) { $bad.Add((& $short $later.sha)) }
    }
    if ($formatHead) { $relied.Add($formatHead) }
    if ($filteredHead) { $relied.Add($filteredHead) }
    $missing = @(if (-not $formatHead) { 'format' }; if (-not $filteredHead) { 'gefiltert' })

    if ($fail) {
        & $add 'run-line' $false "$fail$note"
    } elseif ($bad.Count -gt 0) {
        & $add 'run-line' $false "$reason; commit(s) $($bad -join ', ') touch more than docs or more than tests$note"
    } elseif ($onlyLedger) {
        & $add 'run-line' $true "$reason; every commit after it touches only a review ledger file$note"
    } elseif ($missing.Count -gt 0) {
        & $add 'run-line' $false "$reason; the exception needs a format and a gefiltert run line for the head (missing: $($missing -join ', '))$note"
    } else {
        $what = if ($rebase) { 'the head is a rebase with identical code paths' } else { 'every commit after it touches only docs or only tests' }
        & $add 'run-line' $true "$reason; $what, and a format and a gefiltert run line name the head (documented exception)$note"
    }
}

# 2. no red test in the run lines relied on
if ($relied.Count -eq 0) {
    & $add 'red-tests' $false 'no run line to read'
} else {
    $redLine = @($relied | Where-Object { $_.Red -ne '0' })
    if ($redLine.Count -eq 0) {
        & $add 'red-tests' $true (@($relied | ForEach-Object { "$($_.Mode) run line $(& $short $_.Sha) says rot: 0" }) -join '; ')
    } else {
        & $add 'red-tests' $false (@($redLine | ForEach-Object { "$($_.Mode) run line $(& $short $_.Sha) says rot: $($_.Red)" }) -join '; ')
    }
}

# 3. the full run was made on the current head of the base branch
if ($basisCounts) {
    $basis = $newestFull.Basis
    $same = $basis.Length -ge 7 -and $baseHead.Length -ge 7 -and
    ($baseHead.StartsWith($basis, [StringComparison]::OrdinalIgnoreCase) -or $basis.StartsWith($baseHead, [StringComparison]::OrdinalIgnoreCase))
    if (-not $baseHead) {
        & $add 'base-head' $true "Basis $(& $short $basis) is not compared (no -BaseSha)"
    } elseif ($same) {
        & $add 'base-head' $true "Basis $(& $short $basis) is the base head"
    } else {
        & $add 'base-head' $false "main moved since the full run: Basis $(& $short $basis), the base head is $(& $short $baseHead)"
    }
}

# 4. a review verdict
$latestByUser = @{}
foreach ($item in $review) {
    $user = "$($item.user.login)".ToLowerInvariant()
    $state = "$($item.state)".ToUpperInvariant()
    if (-not $user -or $state -in 'COMMENTED', 'PENDING') { continue }
    $latestByUser[$user] = $item
}
$approver = @($latestByUser.Keys | Where-Object {
        $latestByUser[$_].state -eq 'APPROVED' -and $_ -ne $author.ToLowerInvariant()
    } | Sort-Object)
$changesBy = @($latestByUser.Keys | Where-Object {
        $latestByUser[$_].state -eq 'CHANGES_REQUESTED' -and $_ -ne $author.ToLowerInvariant()
    } | Sort-Object)
$verdictPattern = '(?im)^\s*Review-Verdikt:\s*approve\s+([0-9a-f]{7,40})\b'
$verdictBy = [System.Collections.Generic.List[string]]::new()
# A verdict line of the author's own account counts only with -SameAccount and only inside a review: the forge
# data cannot tell the same-account case (.agents/rules/pr.md § "Accounts per Seat") from an author alone.
$sameAccountBy = [System.Collections.Generic.List[string]]::new()
$sources = @(@($review) | ForEach-Object { @{ Item = $_; IsReview = $true } }) +
@(@($comment) | ForEach-Object { @{ Item = $_; IsReview = $false } })
foreach ($source in $sources) {
    $item = $source.Item
    if ($null -eq $item -or -not $item.PSObject.Properties['body']) { continue }
    $byAuthor = "$($item.user.login)".ToLowerInvariant() -eq $author.ToLowerInvariant()
    if ($byAuthor -and (-not $source.IsReview -or -not $SameAccount)) { continue }
    foreach ($m in [regex]::Matches("$($item.body)", $verdictPattern)) {
        if (-not (& $namesHead $m.Groups[1].Value)) { continue }
        $verdictBy.Add("$($item.user.login)")
        if ($byAuthor) { $sameAccountBy.Add("$($item.user.login)") }
    }
}
if ($changesBy.Count -gt 0) {
    # Whatever a verdict line says: the latest state of another account stands.
    & $add 'review-verdict' $false "CHANGES_REQUESTED stands from $($changesBy -join ', '); a verdict line or an approve of another account does not withdraw it"
} elseif ($reviewExempt) {
    & $add 'review-verdict' $true 'doc-only PR (only docs/** and root *.md other than AGENTS.md / CLAUDE.md): no review verdict required (.agents/rules/docs.md)'
} elseif ($approver.Count -gt 0) {
    $stale = @($approver | Where-Object {
            $property = $latestByUser[$_].PSObject.Properties['commit_id']
            $id = if ($property) { "$($property.Value)" } else { '' }
            $id -and -not $head.StartsWith($id, [StringComparison]::OrdinalIgnoreCase)
        })
    $extra = if ($stale.Count -gt 0) { "; note: the approve of $($stale -join ', ') was given on an older commit" } else { '' }
    & $add 'review-verdict' $true "APPROVED by $($approver -join ', ') (not the author $author)$extra"
} elseif ($verdictBy.Count -gt 0) {
    $sameAccountNote = if ($sameAccountBy.Count -gt 0) { "; same-account verdict by the author's account (-SameAccount)" } else { '' }
    & $add 'review-verdict' $true "verdict line 'Review-Verdikt: approve $(& $short $head)' by $(($verdictBy | Select-Object -Unique) -join ', ')$sameAccountNote"
} else {
    & $add 'review-verdict' $false "no APPROVED review by an account other than the author ($author) and no 'Review-Verdikt: approve $(& $short $head)' line (-SameAccount counts the author's own review verdict)"
}

$ready = @($check | Where-Object { -not $_.Ok }).Count -eq 0

if ($Json) {
    [pscustomobject]@{ MergeReady = $ready; Head = $head; Check = @($check) } | ConvertTo-Json -Depth 4
} else {
    foreach ($item in $check) { "$(if ($item.Ok) { 'OK    ' } else { 'FEHLT ' }) $($item.Name): $($item.Finding)" }
    if ($ready) { 'Urteil: merge-bereit' } else { 'Urteil: NICHT merge-bereit' }
}
if (-not $ready) { exit 1 }
