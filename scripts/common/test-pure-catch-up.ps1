#Requires -Version 7.6

<#
.SYNOPSIS
    Prove that between a reviewed commit and the head of a pull request lies
    nothing but a pure catch-up of the base branch.

.DESCRIPTION
    A review holds for the PR's own change. When the branch only takes in the
    base branch afterwards - a merge of main, or a rebase onto it - that change
    stays the same, and a new review round would read it again for nothing
    (.agents/rules/review.md, section "Review Comments"). This script decides
    that case by computation instead of by the author's word. Pure means all
    of these:

    1. The PR's own diff is unchanged: the patch-id of the diff from the merge
       base with -Base to the commit is the same at -Reviewed and at -Head.
       `git patch-id --verbatim` is --stable (the order of the files does not
       count) without its whitespace stripping, so an indentation change is a
       change. The diff keeps git's standard context of three lines on purpose:
       a base change right next to the PR's code changes the patch-id and gets
       a review. A review round's ledger file
       (docs/decisions/*-ledger.jsonl) is left out of both diffs: it carries no
       code and needs no review (.agents/rules/review.md, section "Review Comments").
    2. No conflict was resolved by hand: every merge commit between -Reviewed
       and -Head that the base does not hold has two parents and exactly the
       tree that `git merge-tree --write-tree` builds from them without a
       conflict. A merge on the base itself was reviewed there.
    3. The head is the reviewed change on the new base: the tree that
       `git merge-tree --write-tree --merge-base <old base>` builds from the new
       base and -Reviewed equals the head's tree, ledger files aside. The
       patch-id is blind to line numbers; this catches an own commit that moves
       reviewed code to a spot with the same context.

    One conflict is allowed: in the root VERSION and in files named
    CHANGELOG.md at any depth, where two PRs raising the version and adding
    a changelog entry always collide. The conflicted paths come from
    `git merge-tree --write-tree --name-only` (exit 1); a conflict in any
    other file, or in a path git has to quote, stays "not pure". The three
    checks then leave each conflicted file out, and the head has to keep
    both sides of it instead:

    4. A conflicted VERSION at the head reads main's version raised by the
       level (MAJOR, MINOR or PATCH) the PR raised its own by against the
       old base.
    5. Each conflicted CHANGELOG.md carries the same change against main at
       the head as at the reviewed commit against the old base: the diffs
       without context are equal apart from line numbers, once the version
       the PR raised to (with or without a leading v) is replaced by the
       expected one. A line of either side missing at the head breaks the
       equality. A changelog both sides created, and a link line naming the
       old version beside the new one, are not covered: they need a review.

    A merge commit may resolve a conflict only in a file the replay
    conflicts in too. A PR that changes nothing but those files has no
    patch-id; the other checks decide alone.

    Where both sides raised VERSION to the same number, git merges it
    without a conflict while the changelogs still collide; VERSION then
    takes check 4 too. The resolved paths stand in ResolvedConflicts and in
    the PURE line.

    All of them hold for a merge and for a rebase. The new base holds the old
    one: a rebase onto an older base takes nothing in and is no catch-up.
    The proof replaces the review only, never a test run: a semantic
    conflict with the same diff stays invisible to it, and the second full
    run after main moved by code stays owed
    (.agents/rules/pr.md, section "Test Runs").

    A commit the working copy does not hold gives "not pure" with the reason;
    the script never guesses. A git older than 2.40, which lacks
    `patch-id --verbatim` or `merge-tree --merge-base`, stops it with an
    error instead of falling back to a weaker comparison.

    This script is deliberately SELF-CONTAINED - it imports no module, because
    it is mirrored into every consumer via scripts/common/.

.PARAMETER Reviewed
    The commit the review verdict names.

.PARAMETER Head
    The PR's head. Default: HEAD of the working copy.

.PARAMETER Base
    The head of the PR's base branch, e.g. origin/main or its sha.

.PARAMETER Root
    The working copy holding all three commits. Default: the current directory.

.PARAMETER Json
    Serialize the result as JSON (Pure, Reviewed, Head, OldBase, NewBase,
    PatchId, ResolvedConflicts, Reason) instead of printing one line;
    ResolvedConflicts lists the version and changelog paths whose conflict
    was resolved, empty without one.

.INPUTS
    None.

.OUTPUTS
    [string] one line, `PURE: ...` or `NOT PURE: <reason>`; with -Json one
    object. Exit code 1 when the catch-up is not pure.

.EXAMPLE
    ./scripts/common/test-pure-catch-up.ps1 -Reviewed 4f2a1c9 -Base origin/main

    Says whether HEAD differs from the reviewed commit only by taking in main.
#>

[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter(Mandatory)][string] $Reviewed,
    [string] $Head = 'HEAD',
    [Parameter(Mandatory)][string] $Base,
    [string] $Root = '.',
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Native output decoded as UTF-8, whatever the console code page.
$withUtf8Output = Join-Path $PSScriptRoot 'invoke-utf8-output.ps1'
# One git question to the working copy at -Root; Ok is false when git or the object is missing.
$git = {
    param([string[]] $GitArgument)
    try {
        $text = & $withUtf8Output { param($Argument) & git -C $Root -c core.quotepath=off @Argument 2>$null } $GitArgument
        $exitCode = $LASTEXITCODE
    } catch {
        $text = @()
        $exitCode = -1
    }
    $global:LASTEXITCODE = 0
    [pscustomobject]@{ Ok = $exitCode -eq 0; ExitCode = $exitCode; Line = @($text) }
}
# The commit each ref names, '' where it names none, from one git call for all refs.
$resolveCommits = Join-Path $PSScriptRoot 'resolve-git-commits.ps1'
# The patch-id of a commit's own diff against its merge base with the base branch; empty when there is no diff.
# The options pin what a user's or the repo's git config could change: context, renames, prefixes, external diff
# drivers, and a submodule that .gitmodules or diff.ignoreSubmodules hides.
# --binary hashes the content and the full blob ids of a binary change; a plain diff carries only abbreviated ids.
# Matched from the repository's top and in any case, as the merge gate matches a ledger file, whatever -Root points at.
$ledgerSpec = ':(top,exclude,glob,icase)docs/decisions/?*-ledger.jsonl'
# The only files a catch-up may resolve a conflict in: the root VERSION and any CHANGELOG.md (ww3d/playbook#581).
$versionPath = 'VERSION'
$isVersionOrChangelog = { param([string] $Path) $Path -ceq $versionPath -or $Path -cmatch '(^|/)CHANGELOG\.md$' }
# The three checks leave each conflicted file out; the both-sides proof below takes it over.
$skipSpec = @($ledgerSpec)
$patchIdOf = {
    param([string] $Tip, [string] $Basis)
    $diffArgument = @('-C', $Root, '-c', 'core.quotepath=off', 'diff', '--no-color', '--no-ext-diff', '--no-textconv',
        '--no-renames', '--ignore-submodules=none', '--src-prefix=a/', '--dst-prefix=b/', '--binary', '-U3', $Basis, $Tip, '--', ':/') +
        $skipSpec
    # pwsh pipes the bytes between two native commands unchanged.
    $line = @(& git @diffArgument 2>$null | & git -C $Root patch-id --verbatim 2>$null)
    $global:LASTEXITCODE = 0
    if ($line.Count -gt 0 -and "$($line[0])" -match '^([0-9a-f]{40,64})\s') { $Matches[1] } else { '' }
}
$short = { param([string] $Sha) $Sha.Substring(0, [Math]::Min(7, $Sha.Length)) }
# The conflicted paths of a `git merge-tree --write-tree --name-only` run: exit 1 with a list after the tree line.
# Null when the merge failed otherwise; never guessed.
$conflictOf = {
    param($MergeTree)
    if ($MergeTree.Ok) { return , @() }
    $path = @($MergeTree.Line | Select-Object -Skip 1 | Where-Object { "$_" } | Select-Object -Unique)
    # git quotes a path with a quote, backslash or control character even under core.quotepath=off: not matchable.
    if ($MergeTree.ExitCode -eq 1 -and $path.Count -gt 0 -and -not ($path -like '"*')) { , $path } else { $null }
}
# MAJOR.MINOR.PATCH of the root VERSION at a commit as three ints; null when absent or of another form.
$versionAt = {
    param([string] $Sha)
    $read = & $git @('show', "${Sha}:$versionPath")
    if ($read.Ok -and "$($read.Line -join "`n")".Trim() -match '^(\d+)\.(\d+)\.(\d+)$') { , @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3]) }
}
# The version the head must carry: main's, raised by the level the PR raised its own by. Why not, or the version.
$expectedVersion = {
    param([string] $OldBase, [string] $Reviewed, [string] $NewBase)
    $old = & $versionAt $OldBase; $own = & $versionAt $Reviewed; $main = & $versionAt $NewBase
    if (-not $old -or -not $own -or -not $main) {
        return [pscustomobject]@{ Why = "$versionPath is no MAJOR.MINOR.PATCH at the old base, the reviewed commit or the new base" }
    }
    $level = (0..2 | Where-Object { $own[$_] -ne $old[$_] } | Select-Object -First 1)
    if ($null -ne $level -and $own[$level] -lt $old[$level]) {
        return [pscustomobject]@{ Why = "the PR lowered $versionPath from $($old -join '.') to $($own -join '.')" }
    }
    $want = @($main)
    if ($null -ne $level) { $want[$level]++; for ($i = $level + 1; $i -lt 3; $i++) { $want[$i] = 0 } }
    [pscustomobject]@{ Why = ''; Own = $own -join '.'; Want = $want -join '.'; Raised = $null -ne $level }
}
# A changelog diff without context, hunk positions and blob ids: what one side added and removed, in order.
$changelogChange = {
    param([string] $From, [string] $To, [string] $Path)
    # --text: a changelog git takes for binary would otherwise read 'Binary files differ' on both sides, always equal.
    $diff = & $git @('diff', '--no-color', '--no-ext-diff', '--no-textconv', '--text', '--no-renames', '-U0', $From, $To, '--', ":(top,literal)$Path")
    @($diff.Line | Where-Object { $_ -notmatch '^index ' } | ForEach-Object { if ($_ -match '^@@') { '@@' } else { "$_" } })
}
# Both sides of each version and changelog file kept at the head (ww3d/playbook#581); why not, empty when they are.
$bothSidesWhy = {
    param([string] $OldBase, [string] $Reviewed, [string] $NewBase, [string] $Head, [string[]] $Path)
    $version = $null
    if ($Path -ccontains $versionPath) {
        $version = & $expectedVersion $OldBase $Reviewed $NewBase
        if ($version.Why) { return $version.Why }
        # The text itself, one line, not its numbers: the tree check leaves VERSION out, so nothing else proves it.
        $read = & $git @('show', "${Head}:$versionPath")
        $line = @($read.Line | Where-Object { "$_" -ne '' })
        $atHead = if (-not $read.Ok) { 'missing' } elseif ($line.Count -eq 1) { "$($line[0])" } else { "'$($line -join ' ')'" }
        if ($atHead -cne $version.Want) {
            return "$versionPath at the head is $atHead, expected $($version.Want): main's version raised by the PR's level"
        }
    }
    foreach ($changelog in @($Path | Where-Object { $_ -cne $versionPath })) {
        $own = & $changelogChange $OldBase $Reviewed $changelog
        if ($version -and $version.Raised -and $version.Own -cne $version.Want) {
            # A leading v counts as part of the version's spelling (`## [v1.3.0]`), any other letter or digit does not.
            $pattern = "(?<!(?!v)[\w.])$([regex]::Escape($version.Own))(?![\w]|\.\d)"
            $own = @($own | ForEach-Object { if ($_ -cmatch '^[+-](?![+-]{2} )') { $_ -creplace $pattern, $version.Want } else { $_ } })
        }
        $kept = & $changelogChange $NewBase $Head $changelog
        if (($own -join "`n") -cne ($kept -join "`n")) {
            return "$changelog at the head does not hold both sides: its change against main is not the PR's reviewed change"
        }
    }
    ''
}

# No silent fallback to --stable, which strips whitespace: below 2.40 the proof cannot be computed.
# Asked once per process and PATH: the merge gate runs both proofs in one process.
$gitVersion = & (Join-Path $PSScriptRoot 'get-git-version.ps1')
if ($gitVersion -notmatch '(\d+)\.(\d+)' -or [version]"$($Matches[1]).$($Matches[2])" -lt [version]'2.40') {
    throw "test-pure-catch-up.ps1 needs git 2.40 or later (patch-id --verbatim, merge-tree --merge-base), found '$gitVersion'."
}

# Every merge between the reviewed commit and the head that the base does not hold is the conflict-free merge of its
# parents, a conflict in a file the replay conflicts in too aside. Why not, empty when it is.
$mergesWhy = {
    # One line per merge: its sha, its tree, its parents.
    $mergeLine = (& $git @('log', '--merges', '--format=%H %T %P', "$reviewedSha..$headSha", "^$baseSha")).Line
    foreach ($line in @($mergeLine | Where-Object { $_ })) {
        $merge, $tree, $parent = @("$line" -split '\s+' | Where-Object { $_ })
        $parent = @($parent)
        if ($parent.Count -ne 2) { return "merge $(& $short $merge) has $($parent.Count) parents" }
        $built = & $git @('merge-tree', '--write-tree', '--no-messages', '--name-only', $parent[0], $parent[1])
        $conflict = & $conflictOf $built
        # Only a file the replay conflicts in too: it is left out of the checks and proven on both sides.
        $foreign = @($conflict | Where-Object { $_ -cnotin $resolved })
        if ($null -eq $conflict -or $foreign.Count -gt 0) {
            return "merge $(& $short $merge) resolved a conflict$(if ($foreign) { " in $($foreign -join ', ')" })"
        }
        $sameTree = if ($conflict.Count -eq 0) { "$($built.Line[0])".Trim() -eq $tree } else {
            (& $git (@('diff', '--quiet', '--ignore-submodules=none', "$($built.Line[0])".Trim(), $tree, '--', ':/') + $skipSpec)).Ok
        }
        if (-not $sameTree) { return "merge $(& $short $merge) differs from the conflict-free merge of its parents" }
    }
    ''
}

$reviewedSha, $headSha, $baseSha = & $resolveCommits -Root $Root -Ref @($Reviewed, $Head, $Base)
$oldBase = ''
$newBase = ''
$patchId = ''
$reason = ''
$same = $false
$resolved = @()

$missing = @(@{ Name = 'reviewed commit'; Ref = $Reviewed; Sha = $reviewedSha }, @{ Name = 'head'; Ref = $Head; Sha = $headSha },
    @{ Name = 'base'; Ref = $Base; Sha = $baseSha } | Where-Object { -not $_.Sha } | ForEach-Object { "$($_.Name) '$($_.Ref)'" })
if ($missing.Count -gt 0) {
    $reason = "the working copy at '$Root' does not hold $($missing -join ', ')"
} elseif ($reviewedSha -eq $headSha) {
    $same = $true
} else {
    $oldBase = "$((& $git @('merge-base', $reviewedSha, $baseSha)).Line | Select-Object -First 1)".Trim()
    $newBase = "$((& $git @('merge-base', $headSha, $baseSha)).Line | Select-Object -First 1)".Trim()
    if (-not $oldBase -or -not $newBase) {
        $reason = "no merge base with the base $(& $short $baseSha)"
    } elseif (-not (& $git @('merge-base', '--is-ancestor', $oldBase, $newBase)).Ok) {
        # A rebase onto an older base takes nothing in; it is no catch-up, whatever the diff says.
        $reason = "the base moved back: the new base $(& $short $newBase) does not hold the old one $(& $short $oldBase)"
    } else {
        # The reviewed change replayed onto the new base; a conflict only in version and changelog files is allowed.
        $replay = & $git @('merge-tree', '--write-tree', '--no-messages', '--name-only', '--merge-base', $oldBase, $newBase, $reviewedSha)
        $replayConflict = & $conflictOf $replay
        if ($null -eq $replayConflict -or @($replayConflict | Where-Object { -not (& $isVersionOrChangelog $_) }).Count -gt 0) {
            $listed = @($replay.Line | Select-Object -Skip 1 | Where-Object { "$_" } | Select-Object -Unique)
            $reason = 'the reviewed change does not apply to the new base without a conflict' +
            $(if ($listed) { " (in $($listed -join ', '))" })
        } else {
            $resolved = @($replayConflict)
            # Two PRs raising VERSION to the same number merge without a conflict there; their changelogs still collide.
            $raisedBoth = { param([string] $To) -not (& $git @('diff', '--quiet', $oldBase, $To, '--', ":(top,literal)$versionPath")).Ok }
            if ($resolved.Count -gt 0 -and $resolved -cnotcontains $versionPath -and (& $raisedBoth $reviewedSha) -and (& $raisedBoth $newBase)) {
                $resolved += $versionPath
            }
            $skipSpec += @($resolved | ForEach-Object { ":(top,exclude,literal)$_" })
            $oldId = & $patchIdOf $reviewedSha $oldBase
            $newId = & $patchIdOf $headSha $newBase
            # A release PR changes only version and changelog: with both left out, the other proofs decide alone.
            $releaseOnly = -not $oldId -and -not $newId -and $resolved.Count -gt 0
            if (-not $releaseOnly -and (-not $oldId -or -not $newId)) {
                $reason = 'the PR diff is empty at the reviewed commit or the head, there is nothing to compare'
            } elseif ($oldId -ne $newId) {
                $reason = "the PR diff changed: patch-id $(& $short $oldId) at the reviewed commit, $(& $short $newId) at the head"
            } else {
                $patchId = $newId
                $reason = & $mergesWhy
                $replayTree = "$($replay.Line[0])".Trim()
                if (-not $reason -and -not (& $git (@('diff', '--quiet', '--ignore-submodules=none', $replayTree, $headSha, '--', ':/') + $skipSpec)).Ok) {
                    $reason = 'the head differs from the reviewed change on the new base (code moved or added after the review)'
                }
                if (-not $reason -and $resolved.Count -gt 0) { $reason = & $bothSidesWhy $oldBase $reviewedSha $newBase $headSha $resolved }
            }
        }
    }
}

$pure = -not $reason
$result = [pscustomobject]@{
    Pure              = $pure
    Reviewed          = $reviewedSha
    Head              = $headSha
    OldBase           = $oldBase
    NewBase           = $newBase
    PatchId           = $patchId
    ResolvedConflicts = @($resolved)
    Reason            = $reason
}
$resolvedNote = if ($resolved.Count -gt 0) { "; conflicts resolved with both sides kept in $($resolved -join ', ')" } else { '' }

if ($Json) {
    ConvertTo-Json -InputObject $result -Depth 3
} elseif ($same) {
    "PURE: the head is the reviewed commit $(& $short $headSha)"
} elseif ($pure -and $oldBase -eq $newBase) {
    "PURE: the PR diff is unchanged between $(& $short $reviewedSha) and $(& $short $headSha) on the same base" +
    " $(& $short $newBase) (patch-id $(& $short $patchId))"
} elseif ($pure) {
    "PURE: only a catch-up of the base between $(& $short $reviewedSha) and $(& $short $headSha)" +
    " (base $(& $short $oldBase) -> $(& $short $newBase), $(if ($patchId) { "patch-id $(& $short $patchId)" } else { 'no patch-id: version and changelog only' })$resolvedNote)"
} else {
    "NOT PURE: $reason"
}
if (-not $pure) { exit 1 }
