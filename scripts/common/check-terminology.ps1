#Requires -Version 7.4

<#
.SYNOPSIS
    Terminology gate over the repository's Markdown: umlauts, retired terms,
    dead relative paths and quoted repository paths that exist nowhere.

.DESCRIPTION
    Four language-independent checks that no other gate covers:

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

    This script is deliberately SELF-CONTAINED - it imports no module. It is
    mirrored into every consumer via scripts/common/, and PlaybookOps reaches
    none of them.

    Exits 1 when any check finds something, 0 otherwise.

.PARAMETER Path
    Repository root to scan. Defaults to the repository this script sits in.

.PARAMETER TermList
    The retired-term list. Defaults to forbidden-terms.txt beside this script.

.PARAMETER Json
    Serialize the findings as JSON instead of emitting objects.

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
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [string] $Path,
    [string] $TermList,
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Path) { $Path = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent }
if (-not $TermList) { $TermList = Join-Path $PSScriptRoot 'forbidden-terms.txt' }

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Repository root not found at '$Path'."
}
$root = (Resolve-Path -LiteralPath $Path).ProviderPath

# Code points, never bytes. Listed explicitly rather than as a Unicode category:
# the rule is about German umlauts and the sharp s, not about non-ASCII - the em
# dash and the arrow next door are allowed and must not match.
$umlautPattern = '[\u00E4\u00F6\u00FC\u00C4\u00D6\u00DC\u00DF]'

# Inline links [text](target) and reference definitions [label]: target.
$linkPattern = '\[[^\]]*\]\(\s*([^)\s]+)'
$referencePattern = '(?m)^\s*\[[^\]]+\]:\s*(\S+)'

# Backtick-quoted tokens, the form a rule text names a carrier place in.
$codeSpanPattern = '`([^`\r\n]+)`'

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
    'consumers/', '.claude/', '.github/')

# Exempt by base name, never by directory: `docs/backlog.md` in a consumer is
# the same self-creating file as `backlog.md` here.
$carrierExempt = @('backlog.md')

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

$relativeOf = {
    param($FullName)
    [System.IO.Path]::GetRelativePath($root, $FullName).Replace('\', '/')
}

$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.md' -Force |
        Where-Object {
            $relative = & $relativeOf $_.FullName
            $segments = $relative.Split('/')
            -not ($segments | Where-Object { $_ -in $skipDirectory }) -and
            -not ($exemptPrefix | Where-Object { $relative.StartsWith($_, [StringComparison]::Ordinal) })
        })

$findings = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($file in $files) {
    $relative = & $relativeOf $file.FullName
    $lines = @(Get-Content -LiteralPath $file.FullName)

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $number = $i + 1

        foreach ($hit in [regex]::Matches($line, $umlautPattern)) {
            $findings.Add([pscustomobject]@{
                    Path    = $relative
                    Line    = $number
                    Check   = 'umlaut'
                    Match   = $hit.Value
                    Message = "$relative`:$number - umlaut '$($hit.Value)' must be transliterated (ae / oe / ue / ss)"
                })
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

$results = @($findings)

if (-not $Json) {
    Write-Verbose "checked $($files.Count) Markdown file(s) under '$root'"
    if ($results.Count -eq 0) {
        Write-Output "OK: $($files.Count) Markdown file(s) clean (umlauts, retired terms, relative paths, carrier places)"
    } else {
        foreach ($item in $results) { Write-Output $item.Message }
    }
}

if ($Json) { ConvertTo-Json -InputObject $results -Depth 5 }

if ($results.Count -gt 0) {
    Write-Error "$($results.Count) terminology finding(s)." -ErrorAction Continue
    exit 1
}
