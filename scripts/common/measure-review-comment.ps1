#Requires -Version 7.4

<#
.SYNOPSIS
    Count the Conventional Comments on a pull request: how many of each label,
    how many block, and how many review rounds it took.

.DESCRIPTION
    The effort measurement asked for over the next five slices - waves, review
    rounds, findings per class, questions to the human. Counted by hand that is
    exactly the bookkeeping the review rebuild removed, so it is counted by
    script instead. That the numbers are machine-readable at all is the side
    benefit of Conventional Comments (AGENTS.md, section "Review Comments").

    Counted per label - issue / nitpick / question / suggestion - plus how many
    of them carry `(blocking)`, plus the number of rounds. A round is one
    submitted review, not one comment: three comments in one review are one
    round, which is the number the measurement is about.

    Input comes either from `gh` or from a JSON file, and the counting is the
    same code either way. The file path exists so the counting can be exercised
    without a forge - `gh` is blocked server-side in some sessions, and a metric
    that cannot be tested is a metric nobody trusts. Note what that does NOT
    cover: the fetching itself. A hand-built dump proves the counting and says
    nothing about which endpoints were asked.

    This script is deliberately SELF-CONTAINED - it imports no module, because
    it is mirrored into every consumer via scripts/common/.

.PARAMETER PullRequest
    The pull request as `owner/repo#N`. Ignored when -InputPath is given.

.PARAMETER InputPath
    A JSON file holding an array of comment objects, each with a `body` and
    optionally a `pull_request_review_id`. Bypasses `gh` entirely, and with it
    both endpoints - the dump stands for whatever the caller put in it.

.PARAMETER Json
    Serialize the counts as JSON instead of emitting an object.

.INPUTS
    None.

.OUTPUTS
    [pscustomobject] with PullRequest, Issue, Nitpick, Question, Suggestion,
    Other, Blocking, NonBlocking, Rounds and Total.

.EXAMPLE
    ./scripts/common/measure-review-comment.ps1 -PullRequest ww3d/playbook#178

    Reads the review comments through `gh` and prints the counts.

.EXAMPLE
    ./scripts/common/measure-review-comment.ps1 -InputPath ./comments.json -Json

    Counts a captured comment dump, no forge involved.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [string] $PullRequest,
    [string] $InputPath,
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $InputPath -and -not $PullRequest) {
    throw 'Name a pull request as owner/repo#N, or pass -InputPath with a captured comment dump.'
}

if ($InputPath) {
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
        throw "Comment dump not found at '$InputPath'."
    }
    $comments = @(Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json)
    $label = if ($PullRequest) { $PullRequest } else { $InputPath }
} else {
    if ($PullRequest -notmatch '^(?<repo>[^#\s]+)#(?<number>\d+)$') {
        throw "Pull request must read owner/repo#N, got '$PullRequest'."
    }
    $repo = $Matches['repo']
    $number = $Matches['number']

    # TWO endpoints, because the labels live in both places:
    #   pulls/N/comments - the inline review comments
    #   pulls/N/reviews  - the review BODY, where pr-poll-review posts its summary
    # Counting only the first misses every label that stood in a review body, and
    # loses any round that carried no inline comment at all - which is exactly the
    # short rounds the measurement is meant to see.
    #
    # --slurp with --paginate: past 100 items `gh` concatenates several JSON
    # arrays, and ConvertFrom-Json throws on that. --slurp wraps the pages in one
    # outer array, which is then flattened here.
    $fetch = {
        param($Endpoint)
        $raw = & gh api "repos/$repo/pulls/$number/$Endpoint" --paginate --slurp 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "gh could not read $Endpoint of $PullRequest (exit $LASTEXITCODE)."
        }
        # One flatten step: --slurp always yields an array of pages.
        @($raw | ConvertFrom-Json | ForEach-Object { $_ })
    }

    # A review row has no pull_request_review_id of its own - its own id IS the
    # round, so it is mapped onto the same field the counting below reads.
    $reviews = @(& $fetch 'reviews' | ForEach-Object {
            [pscustomobject]@{ body = $_.body; pull_request_review_id = $_.id }
        })
    $comments = @(& $fetch 'comments') + $reviews
    $label = $PullRequest
}

# Anchored at the start of a line so a label quoted inside a sentence ("that is
# an issue: for the maintainer") is not counted as one. Multiline, because a
# comment body holds several lines and the label sits on the first of its block.
$labelPattern = '(?m)^\s*>?\s*(?<label>issue|nitpick|question|suggestion|todo|praise|thought|chore)\s*:'
$blockingPattern = '\((?<decoration>non-blocking|blocking)\)'

$counts = [ordered]@{ issue = 0; nitpick = 0; question = 0; suggestion = 0; other = 0 }
$blocking = 0
$nonBlocking = 0
$rounds = [System.Collections.Generic.HashSet[string]]::new()

foreach ($comment in $comments) {
    $body = if ($comment.PSObject.Properties.Name -contains 'body') { [string]$comment.body } else { '' }
    if (-not $body) { continue }

    $reviewId = if ($comment.PSObject.Properties.Name -contains 'pull_request_review_id') {
        [string]$comment.pull_request_review_id
    } else { '' }
    if ($reviewId) { [void]$rounds.Add($reviewId) }

    foreach ($hit in [regex]::Matches($body, $labelPattern)) {
        $name = $hit.Groups['label'].Value.ToLowerInvariant()
        if ($counts.Contains($name)) { $counts[$name]++ } else { $counts['other']++ }

        # The decoration is read from the label's own line, not from the whole
        # body: a comment may quote the other decoration while explaining itself.
        $lineEnd = $body.IndexOf("`n", $hit.Index)
        if ($lineEnd -lt 0) { $lineEnd = $body.Length }
        $labelLine = $body.Substring($hit.Index, $lineEnd - $hit.Index)

        $decoration = [regex]::Match($labelLine, $blockingPattern)
        if ($decoration.Success -and $decoration.Groups['decoration'].Value -eq 'blocking') {
            $blocking++
        } else {
            # No decoration is not blocking: only `(blocking)` blocks, and a
            # nitpick never does whatever it writes next to itself.
            $nonBlocking++
        }
    }
}

$total = ($counts.Values | Measure-Object -Sum).Sum

$result = [pscustomobject]@{
    PullRequest = $label
    Issue       = $counts['issue']
    Nitpick     = $counts['nitpick']
    Question    = $counts['question']
    Suggestion  = $counts['suggestion']
    Other       = $counts['other']
    Blocking    = $blocking
    NonBlocking = $nonBlocking
    Rounds      = $rounds.Count
    Total       = $total
}

if ($Json) { ConvertTo-Json -InputObject $result -Depth 5 } else { $result }
