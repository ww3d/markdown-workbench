#Requires -Version 7.4

<#
.SYNOPSIS
    Terminology gate over the repository's Markdown: umlauts, retired terms,
    dead relative paths and quoted repository paths that exist nowhere. On
    demand also a PR body, against the closing-line rule.

.DESCRIPTION
    Six language-independent checks that no other gate covers:

    * UMLAUTS - AGENTS.md, section "Language", requires German umlauts to be
      transliterated (ae / oe / ue / ss) in repository text. Matching is by CODE
      POINT, not by byte: the em dash, the arrow and the ellipsis are explicitly
      allowed UTF-8 punctuation, and a byte-wise search flags every one of them.
      That is not hypothetical - a hand-run `grep -P` without LC_ALL=C.UTF-8 did
      exactly that and reported 114 false hits.
    * RETIRED TERMS - literal, CASE-SENSITIVE matches from forbidden-terms.txt,
      which sits beside this script so the list can change without touching the
      check. Case-sensitivity is what separates the retired `Ist-Stand-Audit`
      from the audit file name `audit/ist-stand-<stamp>.md`, which stays.
    * DEAD RELATIVE PATHS - every relative Markdown link target that resolves to
      nothing. Absolute URLs and pure anchors are out of scope; a fragment on a
      relative target is stripped before resolving.
    * CARRIER PLACES - every backtick-quoted repository path that resolves to
      nothing, resolved from the repository ROOT rather than from the citing
      file. This is the half the link check cannot see: a rule text names its
      carrier as `roadmap.md`, `docs/architecture.md` or
      `scripts/common/forbidden-terms.txt` in backticks, not as a Markdown link,
      so a place that never existed in this repository - or stopped existing -
      goes unnoticed. Only path-SHAPED tokens count (they carry a directory
      separator) and only known documentation and tooling extensions; a bare
      `package.json` in a convention text describes the consumer's tree, not
      this one. `backlog.md` is exempt by name: AGENTS.md, section
      "Documentation", has the first PR that defers a point create it, so a
      check demanding it would fight the rule it is meant to enforce.

    Two paths are exempt from all four: docs/decisions/, whose logs are
    immutable history, and docs/tasks/, where a spec file quotes the very terms
    it retires. A self-quotation is not an occurrence. A third, templates/, is
    exempt from the two PATH checks alone and stays subject to umlauts and
    retired terms: a skeleton's paths are written for the tree it is copied
    into, so resolving them here would always fail and would say nothing about
    the file being correct.

    * TEMPLATE BANNER / PLACEHOLDER - a fixed, small set of consumer paths is
      DERIVED from a templates/ skeleton at onboarding (templates/README.md,
      "Onboarding-Sequenz"): docs/decisions/README.md from
      templates/docs/decisions-README.md, CLAUDE.md from templates/root/CLAUDE.md,
      and so on. Derivation means removing the skeleton's warning blockquote and
      filling every `<Platzhalter>` token - a file at one of these paths that
      still carries either one is an onboarding that stopped short, and it is
      invisible to every other check here because the file is otherwise
      well-formed Markdown. Matched by PATH EQUALITY to the known mapping, not by
      a blanket text search: the banner phrase and the `<...>` syntax are legitimately
      quoted in prose that explains the convention (templates/README.md itself
      does this), and a search with no location filter would flag the
      explanation along with the leftover. In the playbook itself templates/ is
      the source of these files and is exempt from every check already; a path in
      the mapping that happens to also exist here (it does not today) would still
      be checked, since the playbook is a consumer of its own conventions same as
      any other repository.
    * BOILERPLATE - "Draft-PR" as a delivery state, a `<type>/<topic>`-shaped
      branch-naming instruction, or a reviewer mention (`@ww3-claude-bot`,
      `@ww3-claude`, `@ww3d`) inside docs/tasks/*.md or a `*-prompt.md` file.
      These are workflow mechanics the ccweb-prompt skill explicitly tells a
      design round never to put in a task prompt or spec file - the `dev` role in
      pr.md already owns opening the draft, naming the branch and requesting
      reviewers - and it happened anyway: a prompt is not a
      review, and prose cannot enforce its own exclusions. Scoped to exactly
      these two path shapes, which is why they run over their OWN file selection
      rather than the Markdown set above: docs/tasks/ is exempt from every other
      check precisely because a spec file quotes retired terms and dead paths on
      purpose, and a *-prompt.md file need not be Markdown-scanned material at
      all otherwise.

    A seventh check runs only over a text handed in with -BodyPath, never over the
    repository:

    * CLOSING LINE - a closing keyword carrying an issue number that does NOT
      stand on a line of its own. .agents/rules/pr.md, section "PR / MR Description", puts
      the pair in the closing line and nowhere else: on a squash merge the PR
      body travels into the commit body, and the parser there tells a mention
      from an instruction not at all - not in backticks, not inside a negation.
      That is measured, not supposed. Keywords are GitHub's own set (close,
      closes, closed, fix, fixes, fixed, resolve, resolves, resolved), because a
      check that knew three of the nine would miss the trap it exists for; the
      reference may be `#12`, `owner/repo#12`, a Markdown link to either, or the
      full issue URL - every one of them IS an issue reference, and admitting
      one unverified form while refusing its neighbours would be an asymmetry
      with no argument behind it. A line that STARTS with such a keyword is the
      closing line itself and is never reported, however many issues it lists -
      the documented multi-issue form repeats the keyword on one line. A leading
      list marker counts as a line start, bulleted or numbered, since the list
      form is documented too.

      Inside a FENCED block nothing counts as the closing line: a fence holds an
      example, and an example carrying a real number is the very shape this
      repository defused in its own guide. The inline code span next door was
      measured not to protect either. Fence length is tracked, not just the
      fence character - the four-backtick form AGENTS.md prescribes for a body
      that quotes a code block would otherwise be ended by its own inner fence,
      and every line after it would count as quoted.

    The limit is deliberate and worth stating: this check sees only the text it
    is handed. It does NOT replace the review gate (pr-poll-review, phase 4,
    points 5 and 8), which reads the body at the head and weighs it against the
    tracking issue - it is the cheap run-up in front of it. Repository files are
    never parsed by the forge, which is why the check is not part of the
    repository scan: a rule text quoting the pair is documentation, a PR body
    carrying it is an instruction.

    FILE SELECTION - the Markdown set is `git ls-files -- '*.md'` against the
    scanned Path, not a filesystem walk: a gitignored scratch file (AGENTS.md,
    section "Working Mode", names .agent/ as exactly that kind of directory) is
    not repository text, and a filesystem walk counted it anyway - measured at
    195 false findings from a single audit working folder left in the tree
    (ww3d/playbook#217). Outside a git checkout (LASTEXITCODE non-zero, or git
    itself missing) this falls back to the filesystem walk, with a warning:
    get-audit-worklist.ps1 next door classifies files the same way, for the same
    reason.

    LOCAL OVERRIDES - .agents/rules/local/terminology.yml, read from the scanned
    Path and never touched by the sync (local/ is excluded from the managed
    .agents set; verified by Test-MirrorPath). Two top-level keys, both a list of
    plain strings:

      exempt_paths:
        - docs/handoffs/*
      allowed_terms:
        - Grundsaetze

    `exempt_paths` are repo-relative glob patterns (PowerShell -like wildcards)
    excluded from the UMLAUT check only - a consumer's own, documented override
    for a byte-identical mirror or a dated snapshot that keeps native umlauts on
    purpose. `allowed_terms` are whole words that stay allowed
    wherever they appear, for a term the umlaut pattern would otherwise flag
    everywhere rather than in a handful of places a glob can name.

    This is a hand-written reader for a DELIBERATELY small subset of YAML - one
    key per top-level line ending in `:`, its items as `  - value` lines below
    it, `#` comments and blank lines ignored, no nesting, no inline comments, no
    quoting beyond a single matched pair of `'` or `"` around a whole item. Not
    powershell-yaml: scripts/common/README.md, section "Self-contained by
    design", is unconditional - a YAML module dependency for the file this
    script alone reads would defeat the reason that section exists. The same
    subset, with the same example, is documented again in
    scripts/common/README.md so a consumer can write one without reading this
    script.

    This script is deliberately SELF-CONTAINED - it imports no module. It is
    mirrored into every consumer via scripts/common/, and PlaybookOps reaches
    none of them.

    Exits 1 when any check finds something, 0 otherwise.

.PARAMETER Path
    Repository root to scan. Defaults to the repository this script sits in.

.PARAMETER TermList
    The retired-term list. Defaults to forbidden-terms.txt beside this script.

.PARAMETER OverridePath
    The local override file. Defaults to .agents/rules/local/terminology.yml
    under Path. A missing file is not an error - it means no repo-specific
    override exists yet.

.PARAMETER BodyPath
    A PR body to check against the closing-line rule, as a text file. Optional
    and additive: without it the run is exactly what it was before, so no
    existing caller has to change.

.PARAMETER Json
    Serialize the findings as JSON instead of emitting objects.

.PARAMETER Sarif
    Emit the findings as a SARIF 2.1.0 log instead of the default objects/JSON,
    for later PR-annotation ingestion once the org CI runs (pr.md, section "CI
    Counts as Dead Org-Wide"). -Sarif takes precedence over -Json when both are
    given.

.INPUTS
    None.

.OUTPUTS
    [pscustomobject] per finding with Path, Line, Check, Match and Message.

.EXAMPLE
    ./scripts/common/check-terminology.ps1

    Checks the whole repository and exits 1 on the first finding.

.EXAMPLE
    ./scripts/common/check-terminology.ps1 -Path /tmp/tree -Json

    Checks a throwaway tree and writes the findings as a JSON document.

.EXAMPLE
    gh pr view 196 --json body --jq .body > body.md
    ./scripts/common/check-terminology.ps1 -BodyPath body.md

    Checks a PR body for a closing keyword with a number that stands anywhere
    but on a line of its own, alongside the repository scan.

.EXAMPLE
    ./scripts/common/check-terminology.ps1 -Sarif > terminology.sarif

    Checks the repository and writes a SARIF 2.1.0 log.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [string] $Path,
    [string] $TermList,
    [string] $OverridePath,
    # Validated at binding time, not after the repository scan: a mistyped path
    # should fail before the run, not at the end of it.
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf },
        ErrorMessage = "PR body not found at '{0}'.")]
    [string] $BodyPath,
    [switch] $Json,
    [switch] $Sarif
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Path) { $Path = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent }
if (-not $TermList) { $TermList = Join-Path $PSScriptRoot 'forbidden-terms.txt' }

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Repository root not found at '$Path'."
}
$root = (Resolve-Path -LiteralPath $Path).ProviderPath
if (-not $OverridePath) { $OverridePath = Join-Path $root '.agents/rules/local/terminology.yml' }

# Hand-written reader for the documented subset only - see the DESCRIPTION
# block above and scripts/common/README.md for the grammar. Returns a fixed
# shape so a missing file and an empty file behave identically.
function Read-TerminologyOverride {
    param([string] $OverrideFile)

    $result = [pscustomobject]@{ ExemptPaths = @(); AllowedTerms = @() }
    if (-not (Test-Path -LiteralPath $OverrideFile -PathType Leaf)) { return $result }

    $key = $null
    $lists = @{ exempt_paths = [System.Collections.Generic.List[string]]::new()
        allowed_terms        = [System.Collections.Generic.List[string]]::new() }

    foreach ($line in Get-Content -LiteralPath $OverrideFile) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^(\w+):\s*$') { $key = $Matches[1]; continue }
        if ($line -match '^\s*-\s*(.+?)\s*$' -and $key -and $lists.ContainsKey($key)) {
            $item = $Matches[1]
            if ($item.Length -ge 2 -and $item[0] -eq $item[-1] -and $item[0] -in "'", '"') {
                $item = $item.Substring(1, $item.Length - 2)
            }
            $lists[$key].Add($item)
        }
    }

    $result.ExemptPaths = @($lists['exempt_paths'])
    $result.AllowedTerms = @($lists['allowed_terms'])
    return $result
}

$override = Read-TerminologyOverride -OverrideFile $OverridePath

# Code points, never bytes. Listed explicitly rather than as a Unicode category:
# the rule is about German umlauts and the sharp s, not about non-ASCII - the em
# dash and the arrow next door are allowed and must not match.
$umlautPattern = '[\u00E4\u00F6\u00FC\u00C4\u00D6\u00DC\u00DF]'

# Inline links [text](target) and reference definitions [label]: target.
$linkPattern = '\[[^\]]*\]\(\s*([^)\s]+)'
$referencePattern = '(?m)^\s*\[[^\]]+\]:\s*(\S+)'

# Backtick-quoted tokens, the form a rule text names a carrier place in.
$codeSpanPattern = '`([^`\r\n]+)`'

# GitHub's own closing keywords, all nine. Three of them would leave "Fixed #12"
# unseen, which is the same trap written in a different word.
$closingKeyword = 'close[sd]?|fix(?:e[sd])?|resolve[sd]?'
# The reference the keyword has to be adjacent to. Four forms, and they are in
# for one reason rather than four: the rule forbids pairing the keyword with an
# issue REFERENCE, and every one of these carries one - a bare `#12`, a
# cross-repo `owner/repo#12`, a Markdown link `[#12](...)`, and the full issue
# URL. Whether the forge parses each of them is NOT verified here, and that is
# precisely why the set is wide: for a run-up check, under-reporting is the
# expensive direction, and admitting one unverified form while refusing its
# neighbours would be an asymmetry with no argument behind it.
$closingReference = '(?:\[?(?:[\w.-]+/[\w.-]+)?#\d+\]?|<?https?://[^\s)>]+/issues/\d+>?)'
# Separator: whitespace, or the documented colon form - with or without the
# space that follows it in the documentation.
$closingSeparator = '(?:\s*:\s*|\s+)'
$closingPattern = "(?i)\b(?:$closingKeyword)$closingSeparator$closingReference"
# The closing line itself, which is what the rule prescribes: the keyword opens
# the line, optionally behind a list marker, and everything on that line is then
# the instruction rather than prose about it. Both list forms count - the guide
# documents a "Listen-Form" without fixing the bullet type.
$closingListMarker = '(?:[-*+]|\d+[.)])\s+'
$closingLinePattern = "(?i)^\s*(?:$closingListMarker)?(?:$closingKeyword)$closingSeparator$closingReference"
# A fenced block holds an EXAMPLE, so a keyword inside one is never the closing
# line - it is quoted, exactly like the inline code span next door, and the
# forge was measured not to respect that one either.
#
# The CommonMark rules that matter here, all three, because dropping any one of
# them breaks a form this repository itself prescribes:
#   * a closer needs the same character AND at least the opener's length - a
#     four-backtick block wrapping a three-backtick one is exactly what
#     .agents/rules/docs.md, section "Documentation", requires of a body that quotes a code
#     block, and a length-blind toggle lets the inner closer end the outer block;
#   * a closer carries no info string;
#   * a backtick opener's info string holds no backtick, which is what separates
#     an opener from an inline span written with three backticks.
$fenceLinePattern = '^\s*(`{3,}|~{3,})\s*(.*)$'

# Documentation and tooling only. Source-file extensions are deliberately out:
# a convention text naming `src/Foo.cs` illustrates a consumer's tree, and the
# evidence rule already accepts such a path as an anchor a human checks.
$carrierExtension = @('.md', '.ps1', '.psd1', '.psm1', '.sh', '.yml', '.yaml', '.json', '.txt')

# The check reaches only into REPOSITORY-OWNED directories, and this list is
# what draws that line. It is not a narrowing for convenience: a convention text
# describes the CONSUMER's tree as often as its own, and every one of those
# references is correct while resolving to nothing here - `tech/powershell.md`
# (the consumer's wrapper), `./build.ps1` (the consumer's build entry),
# `.agent/progress.md` (git-ignored by design), `@tech/common/dotnet.md` (an
# import directive, not a path). Anchored at a directory this repository owns,
# a quoted path can only mean this tree, and a dead one is always a defect.
$carrierRoot = @('docs/', 'audit/', 'scripts/', 'src/', 'tests/', 'templates/',
    'consumers/', '.claude/', '.agents/', '.github/')

# Exempt by base name, never by directory: `docs/backlog.md` in a consumer is
# the same self-creating file as `backlog.md` here. terminology.yml joins it
# for the same reason - .agents/rules/local/terminology.yml (this script's own
# override file, see the DESCRIPTION block) is a consumer's own creation and
# does not exist in the playbook, which carries no local overrides of its own.
$carrierExempt = @('backlog.md', 'terminology.yml')

# Repo-relative, forward slashes, so a finding reads the same on both platforms.
$exemptPrefix = @('docs/decisions/', 'docs/tasks/')

# Exempt from both path checks - the relative-link one and the carrier one -
# never from umlauts or retired terms: a skeleton's paths are written for the
# tree it is copied into, not for the one it sits in. Resolving `./common/ci.md`
# here would always fail and would say nothing about the file being correct.
$exemptFromPathCheck = @('templates/')
$skipDirectory = @('.git', 'node_modules', 'bin', 'obj', '_build', '_buildtools', 'dist')

$terms = @()
if (Test-Path -LiteralPath $TermList -PathType Leaf) {
    foreach ($line in Get-Content -LiteralPath $TermList) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        # Tab or two-plus spaces separates term from reason, so a term may hold
        # a single space ("hard v1") without needing quoting.
        $parts = [regex]::Split($trimmed, '\t+|\s{2,}', 2)
        $terms += [pscustomobject]@{
            Term   = $parts[0]
            Reason = if ($parts.Count -gt 1) { $parts[1].Trim() } else { 'retired term' }
        }
    }
}

# A fixed, small mapping of consumer paths derived from a templates/ skeleton at
# onboarding, checked below for a leftover skeleton banner or an unresolved
# placeholder. See the DESCRIPTION block, "TEMPLATE BANNER / PLACEHOLDER": this
# is deliberately a lookup, not a derivation from a live templates/ tree, since
# this script runs in every consumer, where templates/ does not exist at all.
$templateDerivedPath = [ordered]@{
    'CLAUDE.md'                = 'templates/root/CLAUDE.md'
    'docs/decisions/README.md' = 'templates/docs/decisions-README.md'
    'docs/ci.md'               = 'templates/docs/ci.md'
    'docs/developer-guide.md'  = 'templates/docs/developer-guide.md'
    'docs/dotnet.md'           = 'templates/docs/dotnet.md'
    'docs/powershell.md'       = 'templates/docs/powershell.md'
    'tech/dotnet.md'           = 'templates/tech/dotnet.md'
    'tech/powershell.md'       = 'templates/tech/powershell.md'
}
# Two banner forms, not one: templates/docs/decisions-README.md carries
# "Skelett - beim Onboarding ableiten" (a full file derived once and never
# touched again), while every wrapper template (templates/docs/ci.md,
# developer-guide.md, dotnet.md, powershell.md, both tech/ overlays) opens
# with "Wrapper - optional" instead - a different sentence for a different
# decision (whether to create the wrapper at all), but the same defect once a
# consumer HAS derived the file and left the explanation standing. Measured:
# the narrower pattern reached only 1 of 8 mapped paths.
$templateBannerPattern = '(Skelett|Wrapper)\s*[-\u2014]\s*(beim Onboarding ableiten|optional)'
$templatePlaceholderPattern = '<[\p{Lu}][^<>\r\n]{0,60}>'

$relativeOf = {
    param($FullName)
    [System.IO.Path]::GetRelativePath($root, $FullName).Replace('\', '/')
}

# git ls-files, not a filesystem walk: a gitignored scratch directory (.agent/,
# AGENTS.md section "Working Mode") is not repository text, and a filesystem
# walk counted it anyway - measured at 195 false findings from a single
# leftover audit working folder (ww3d/playbook#217). Same pattern as
# get-audit-worklist.ps1's classification, for the same reason; outside a git
# checkout this falls back to the filesystem walk, with a warning.
# Wrapped in try/catch, not just a 2>$null/$LASTEXITCODE check: git itself
# being absent from PATH is a CommandNotFoundException, which
# $ErrorActionPreference = 'Stop' turns terminating - a 2>$null redirection
# only silences an external command's OWN stderr, never a missing-command
# error the engine raises before that command can run at all.
# -c core.quotepath=off: the default quotes a non-ASCII path as octal escapes
# (a German-umlaut file name comes back as its raw UTF-8 bytes in octal,
# core.quotepath's own default is on), and Test-Path never matches that
# string against the real file - the path fell out of the scan silently, with
# no warning and no error.
try {
    $tracked = & git -c core.quotepath=off -C $root ls-files -- '*.md' 2>$null
    $usedGit = $LASTEXITCODE -eq 0
    $global:LASTEXITCODE = 0
} catch {
    $tracked = $null
    $usedGit = $false
}
if (-not $usedGit -and -not $Json -and -not $Sarif) {
    # Never under -Json/-Sarif: PowerShell renders the WARNING stream on stdout
    # once this script runs as a child process, so an unguarded warning here
    # would land INSIDE the JSON/SARIF document and break every machine
    # consumer - precisely when one of those switches is used.
    Write-Warning "'$root' is not a git checkout (or git is unavailable) - falling back to a filesystem walk, which cannot tell repository text from gitignored scratch files."
}

$files = @(if ($usedGit) {
        $tracked | ForEach-Object {
            $full = Join-Path $root $_
            if (Test-Path -LiteralPath $full -PathType Leaf) { Get-Item -LiteralPath $full -Force }
        }
    } else {
        Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.md' -Force
    })
$files = @($files | Where-Object {
        $relative = & $relativeOf $_.FullName
        $segments = $relative.Split('/')
        -not ($segments | Where-Object { $_ -in $skipDirectory }) -and
        -not ($exemptPrefix | Where-Object { $relative.StartsWith($_, [StringComparison]::Ordinal) })
    })

# The boilerplate check's own selection (DESCRIPTION, "BOILERPLATE"): it runs
# over docs/tasks/*.md and *-prompt.md files specifically, which the Markdown
# set above deliberately excludes (docs/tasks/ is exempt from every other
# check) or would never have reached (a *-prompt.md need not live under a
# scanned extension-agnostic tree). Git-tracked only, same reasoning as above.
$boilerplateFiles = @(if ($usedGit) {
        & git -c core.quotepath=off -C $root ls-files -- 'docs/tasks/*.md' '*-prompt.md' 2>$null
    } else {
        Get-ChildItem -LiteralPath $root -Recurse -File -Force |
            Where-Object { $_.Name -like '*-prompt.md' -or (& $relativeOf $_.FullName) -like 'docs/tasks/*.md' } |
            ForEach-Object { & $relativeOf $_.FullName }
    })
$global:LASTEXITCODE = 0

$findings = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($file in $files) {
    $relative = & $relativeOf $file.FullName
    $lines = @(Get-Content -LiteralPath $file.FullName)
    $umlautExempt = [bool]($override.ExemptPaths | Where-Object { $relative -like $_ })

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $number = $i + 1

        if (-not $umlautExempt) {
            foreach ($hit in [regex]::Matches($line, $umlautPattern)) {
                # The enclosing LETTER run, not \S+: allowed_terms names whole
                # words "wherever they appear", and \S+ also swallows adjacent
                # punctuation - "Grundsaetze," at a clause boundary or inside a
                # backtick span never matched the bare word "Grundsaetze" in
                # the list. \p{L}+ stops at exactly the letter/word boundary,
                # transliterated hyphen-joined German compounds included since
                # a bare hyphen is not itself a letter and this is scoped to a
                # single script's run. Falls back to the hit itself if,
                # somehow, no run contains it - which cannot happen for a
                # letter hit, but a fallback here is cheaper than an assumption.
                $enclosing = [regex]::Matches($line, '[\p{L}]+') |
                    Where-Object { $_.Index -le $hit.Index -and ($_.Index + $_.Length) -gt $hit.Index } |
                    Select-Object -First 1
                $word = if ($enclosing) { $enclosing.Value } else { $hit.Value }
                if ($override.AllowedTerms -contains $word) { continue }

                $findings.Add([pscustomobject]@{
                        Path    = $relative
                        Line    = $number
                        Check   = 'umlaut'
                        Match   = $hit.Value
                        Message = "$relative`:$number - umlaut '$($hit.Value)' must be transliterated (ae / oe / ue / ss)"
                    })
            }
        }

        foreach ($term in $terms) {
            if ($line.Contains($term.Term, [StringComparison]::Ordinal)) {
                $findings.Add([pscustomobject]@{
                        Path    = $relative
                        Line    = $number
                        Check   = 'term'
                        Match   = $term.Term
                        Message = "$relative`:$number - retired term '$($term.Term)': $($term.Reason)"
                    })
            }
        }

        if ($exemptFromPathCheck | Where-Object { $relative.StartsWith($_, [StringComparison]::Ordinal) }) { continue }

        foreach ($pattern in $linkPattern, $referencePattern) {
            foreach ($hit in [regex]::Matches($line, $pattern)) {
                $target = $hit.Groups[1].Value
                # Absolute URLs, protocol-relative URLs and pure anchors are not
                # this check's business - it verifies what the repository owns.
                if ($target -match '^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|//|#)') { continue }
                # A fragment or a title suffix is not part of the file name.
                $targetPath = ($target -split '#', 2)[0].Trim('<', '>')
                if (-not $targetPath) { continue }
                # A placeholder is a template, not a broken link.
                if ($targetPath.Contains('<') -or $targetPath.Contains('%')) { continue }

                $resolved = Join-Path (Split-Path -Path $file.FullName -Parent) ($targetPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                if (-not (Test-Path -LiteralPath $resolved)) {
                    $findings.Add([pscustomobject]@{
                            Path    = $relative
                            Line    = $number
                            Check   = 'path'
                            Match   = $target
                            Message = "$relative`:$number - relative link target '$target' resolves to nothing"
                        })
                }
            }
        }

        foreach ($hit in [regex]::Matches($line, $codeSpanPattern)) {
            $token = $hit.Groups[1].Value.Trim()
            # A placeholder, a glob or a cross-repo reference is a pattern, not
            # a path: `docs/tasks/<issue>-<slug>.md`, `scripts/*.ps1`,
            # `consumers/[name].yml`, `ww3d/playbook#158`.
            if ($token -match '[<>*?\[\]{}%#\s]') { continue }
            $candidate = $token -replace '^\./', ''
            if (-not ($carrierRoot | Where-Object { $candidate.StartsWith($_, [StringComparison]::Ordinal) })) { continue }
            if ([System.IO.Path]::GetExtension($candidate) -notin $carrierExtension) { continue }
            if ([System.IO.Path]::GetFileName($candidate) -in $carrierExempt) { continue }

            # From the ROOT, not from the citing file: that is the convention
            # these rule texts are written in, and it is why the link check next
            # door cannot stand in for this one.
            $resolved = Join-Path $root ($candidate -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $resolved)) {
                $findings.Add([pscustomobject]@{
                        Path    = $relative
                        Line    = $number
                        Check   = 'carrier'
                        Match   = $token
                        Message = "$relative`:$number - quoted repository path '$token' exists nowhere in this repository"
                    })
            }
        }
    }
}

# TEMPLATE BANNER / PLACEHOLDER - path equality to the fixed mapping above, not
# a text search over every file: see DESCRIPTION for why a blanket search would
# also flag templates/README.md's own explanation of the convention.
foreach ($candidate in $templateDerivedPath.Keys) {
    $full = Join-Path $root ($candidate -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }

    $lines = @(Get-Content -LiteralPath $full)
    # A fenced block is a worked EXAMPLE of the entry format an onboarded file
    # keeps forever (docs/decisions/README.md, section "Beispiel", shows a
    # decision entry with its own <Platzhalter> tokens on purpose) - not a
    # leftover from the onboarding skeleton. Same fence-char/length tracking as
    # the -BodyPath closing-line check below (a bare toggle would let a
    # three-backtick fence nested inside a four-backtick one - exactly the form
    # .agents/rules/docs.md, section "Documentation", requires - end the OUTER
    # fence early), applied here instead of a Markdown parse for one reason:
    # this loop already reads plain lines, and a second parsing strategy in the
    # same script would only be another place to drift.
    $fenceChar = $null
    $fenceLength = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $number = $i + 1

        if ($line -match $fenceLinePattern) {
            $marker = $Matches[1].Substring(0, 1)
            $length = $Matches[1].Length
            $info = $Matches[2]
            if (-not ($marker -eq '`' -and $info.Contains('`'))) {
                if (-not $fenceChar) {
                    $fenceChar = $marker
                    $fenceLength = $length
                } elseif ($fenceChar -eq $marker -and $length -ge $fenceLength -and -not $info) {
                    $fenceChar = $null
                    $fenceLength = 0
                }
            }
        }
        if ($fenceChar) { continue }

        if ($line -match $templateBannerPattern) {
            $findings.Add([pscustomobject]@{
                    Path    = $candidate
                    Line    = $number
                    Check   = 'template-banner'
                    Match   = $Matches[0]
                    Message = "$candidate`:$number - leftover skeleton banner from $($templateDerivedPath[$candidate]); an onboarded file removes it"
                })
        }
        foreach ($hit in [regex]::Matches($line, $templatePlaceholderPattern)) {
            # Inline code, not a leftover placeholder: an inline generic like
            # `Task<Result>` or `IReadOnlyList<Entry>` matches the same
            # <Upper...> shape by pure accident of C# syntax. Measured: every
            # .NET consumer with such a line in a mapped path (CLAUDE.md,
            # docs/dotnet.md, ...) went red on the next sync wave, and none of
            # the eight mapped templates/ files carries a real placeholder
            # inside a backtick span at head. Exempt the same way the fenced
            # block above already is - one line further out, since a code SPAN
            # does not toggle multi-line state the way a fence does.
            $hitLineOffset = $hit.Index
            $inCodeSpan = [bool]([regex]::Matches($line, $codeSpanPattern) | Where-Object {
                    $_.Index -le $hitLineOffset -and ($_.Index + $_.Length) -gt $hitLineOffset
                })
            if ($inCodeSpan) { continue }

            $findings.Add([pscustomobject]@{
                    Path    = $candidate
                    Line    = $number
                    Check   = 'template-placeholder'
                    Match   = $hit.Value
                    Message = "$candidate`:$number - unresolved placeholder '$($hit.Value)' from $($templateDerivedPath[$candidate])"
                })
        }
    }
}

# BOILERPLATE - docs/tasks/*.md and *-prompt.md files only, see DESCRIPTION.
$boilerplateTerm = [ordered]@{
    'Draft-PR'         = 'Draft-PR'
    'branch-name'      = '<[\w.-]+>/<[\w.-]+>'
    'reviewer-mention' = '@ww3-claude-bot\b|@ww3-claude\b|@ww3d\b'
}
foreach ($relative in $boilerplateFiles) {
    $full = Join-Path $root ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }

    $lines = @(Get-Content -LiteralPath $full)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $number = $i + 1

        foreach ($name in $boilerplateTerm.Keys) {
            foreach ($hit in [regex]::Matches($line, $boilerplateTerm[$name])) {
                $findings.Add([pscustomobject]@{
                        Path    = $relative
                        Line    = $number
                        Check   = 'boilerplate'
                        Match   = $hit.Value
                        Message = "$relative`:$number - workflow boilerplate ($name) does not belong in a task prompt or spec file: '$($hit.Value)'"
                    })
            }
        }
    }
}

if ($BodyPath) {
    if (-not (Test-Path -LiteralPath $BodyPath -PathType Leaf)) {
        throw "PR body not found at '$BodyPath'."
    }
    $bodyName = Split-Path -Path $BodyPath -Leaf
    $bodyLines = @(Get-Content -LiteralPath $BodyPath)

    $fenceChar = $null
    $fenceLength = 0

    for ($i = 0; $i -lt $bodyLines.Count; $i++) {
        $line = $bodyLines[$i]

        if ($line -match $fenceLinePattern) {
            $marker = $Matches[1].Substring(0, 1)
            $length = $Matches[1].Length
            $info = $Matches[2]
            if (-not ($marker -eq '`' -and $info.Contains('`'))) {
                if (-not $fenceChar) {
                    $fenceChar = $marker
                    $fenceLength = $length
                } elseif ($fenceChar -eq $marker -and $length -ge $fenceLength -and -not $info) {
                    $fenceChar = $null
                    $fenceLength = 0
                }
            }
        }

        # A line that opens with the keyword IS the closing line - including the
        # documented multi-issue form, which repeats the keyword on that one
        # line. Anything else carrying the pair is prose, a quotation or a
        # negation, and the parser reads all three as an instruction. Inside a
        # fence nothing is the closing line, so an example carrying a real
        # number is reported there rather than waved through.
        if (-not $fenceChar -and $line -match $closingLinePattern) { continue }

        foreach ($hit in [regex]::Matches($line, $closingPattern)) {
            $findings.Add([pscustomobject]@{
                    Path    = $bodyName
                    Line    = $i + 1
                    Check   = 'closing-line'
                    Match   = $hit.Value
                    Message = "$bodyName`:$($i + 1) - closing keyword with a number outside a closing line: '$($hit.Value)'"
                })
        }
    }
}

$results = @($findings)

if ($Sarif) {
    # SARIF 2.1.0, the required-fields subset: one run, one driver name, one
    # result per finding with a ruleId, a level and a physicalLocation. No
    # external schema tool validates this - the Pester test for this switch
    # checks the same required fields the SARIF spec names.
    $sarifLog = [ordered]@{
        '$schema' = 'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json'
        version   = '2.1.0'
        runs      = @(
            [ordered]@{
                tool    = [ordered]@{
                    driver = [ordered]@{
                        name    = 'check-terminology'
                        version = '1.0.0'
                    }
                }
                results = @($results | ForEach-Object {
                        [ordered]@{
                            ruleId    = $_.Check
                            level     = 'error'
                            message   = [ordered]@{ text = $_.Message }
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
    Write-Verbose "checked $($files.Count) Markdown file(s) under '$root'"
    if ($results.Count -eq 0) {
        $checks = 'umlauts, retired terms, relative paths, carrier places, template banners/placeholders, boilerplate'
        if ($BodyPath) { $checks += ', closing line' }
        Write-Output "OK: $($files.Count) Markdown file(s) clean ($checks)"
    } else {
        foreach ($item in $results) { Write-Output $item.Message }
    }
}

if ($results.Count -gt 0) {
    Write-Error "$($results.Count) terminology finding(s)." -ErrorAction Continue
    exit 1
}
