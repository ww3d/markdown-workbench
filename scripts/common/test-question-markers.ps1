#Requires -Version 7.6

<#
.SYNOPSIS
    Finds every question marked for the maintainer that carries no question number - the check a
    design round runs before it hands over.

.DESCRIPTION
    A design round marks an open question for the maintainer as `(question <N>)`, <N> the number its
    question channel gave it. A marker without the number - `(question)`, or an old form such as
    `(Frage)` and `(Frage <N>)` - is a question that was never put; the round does not hand over
    while one stands (skill ccweb-prompt, step 4).

    Matching is case-insensitive on the word. A numbered marker is no finding. A marker inside a
    Markdown inline code span, a fenced code block, or a backtick span inside a JSONL string value is
    a quotation and no finding.

    Scope: the lines the checkout adds against the merge base of HEAD and -BaseRef, through
    get-changed-lines.ps1 (commits and uncommitted changes of tracked files; a new file with all its
    lines). -AllLines checks every line of every tracked text file instead. With -Issue and -Repo the
    whole body of that issue is checked as well, read with one REST call.

    Each finding is one line: `<path>:<line>: <marker> without question number - draft: "<sentence>"`.
    The draft is the sentence holding the marker, the marker removed - the text of the question the
    round still has to put. The script sends nothing. For an issue body the path is `#<N>`.

    Exit code 0 without findings, 1 with findings, 2 on a call or git error, named in one line.

    This script is deliberately SELF-CONTAINED beyond its two siblings get-changed-lines.ps1 and
    get-rest-items.ps1 - it imports no module, because it is mirrored into every consumer via
    scripts/common/.

.PARAMETER Path
    The working copy to check. Defaults to the repository this script sits in.

.PARAMETER BaseRef
    The ref the lines are compared against, through its merge base with HEAD. Defaults to
    origin/main.

.PARAMETER AllLines
    Check every line of every tracked text file instead of the added lines.

.PARAMETER Issue
    Also check the whole body of this issue. Needs -Repo.

.PARAMETER Repo
    The repository of -Issue, as owner/repo.

.PARAMETER Json
    Write the findings as one JSON array of objects with path, line, marker and draft.

.PARAMETER Waive
    The way past: print the findings as warnings, print `Question check waived: <reason>` and exit 0.
    The round writes the same line under `## Design` of its tracking issue. An empty reason is a call
    error.

.INPUTS
    None.

.OUTPUTS
    [string] one line per finding, or with -Json one JSON array.

.EXAMPLE
    pwsh scripts/common/test-question-markers.ps1 -Repo ww3d/playbook -Issue 554

    The lines this branch adds and the body of the tracking issue; exit 1 names every marker without
    a number.

.EXAMPLE
    pwsh scripts/common/test-question-markers.ps1 -AllLines -Json

    Every tracked text file, the findings as JSON.
#>

[CmdletBinding()]
[OutputType([string])]
param(
    [string] $Path = (Resolve-Path (Join-Path $PSScriptRoot '../..')).ProviderPath,
    [string] $BaseRef = 'origin/main',
    [switch] $AllLines,
    [ValidateRange(1, [int]::MaxValue)][int] $Issue,
    [string] $Repo,
    [switch] $Json,
    [string] $Waive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PSNativeCommandUseErrorActionPreference = $false
$withUtf8Output = Join-Path $PSScriptRoot 'invoke-utf8-output.ps1'

$fail = {
    param([string] $Message)
    [Console]::Error.WriteLine("test-question-markers: $Message")
    exit 2
}

if ($PSBoundParameters.ContainsKey('Waive') -and [string]::IsNullOrWhiteSpace($Waive)) {
    & $fail '-Waive needs a reason.'
}
if ($Issue -and -not $Repo) { & $fail '-Issue needs -Repo <owner/repo>.' }

# `(question)`, `(question 12)`, `(Frage)`, `(Frage 12)`; group 1 the word, group 2 the number.
$markerPattern = [regex]::new('\((question|frage)(?:[ \t]+(\d+))?\)', 'IgnoreCase')
# A backtick span: the same run of backticks opens and closes it.
$spanPattern = [regex]::new('(?<!`)(`+)(?!`).+?(?<!`)\1(?!`)', 'Singleline')
$fencePattern = [regex]::new('^ {0,3}(`{3,}|~{3,})')
$bulletPattern = [regex]::new('^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?')
$finding = [System.Collections.Generic.List[pscustomobject]]::new()

# The findings of one text: $Text split into lines, $Wanted the line numbers in scope ($null: all).
$scan = {
    param([string] $Label, [string] $Text, [bool] $Markdown, $Wanted)
    $fence = $null
    $number = 0
    foreach ($line in [regex]::Split($Text, '\r?\n')) {
        $number++
        if ($Markdown -and $fencePattern.IsMatch($line)) {
            $run = $fencePattern.Match($line).Groups[1].Value
            if (-not $fence) { $fence = $run; continue }
            if ($run[0] -eq $fence[0] -and $run.Length -ge $fence.Length) { $fence = $null; continue }
        }
        if ($fence -or ($Wanted -and -not $Wanted.Contains($number)) -or -not $markerPattern.IsMatch($line)) { continue }
        # Quotations are blanked to spaces, so the columns of the rest stay put.
        $open = $spanPattern.Replace($line, { param($m) ' ' * $m.Length })
        foreach ($marker in $markerPattern.Matches($open)) {
            if ($marker.Groups[1].Value -ieq 'question' -and $marker.Groups[2].Success) { continue }
            $form = $marker.Value
            # The sentence round the marker, found in the blanked line (a quoted stop or marker is no
            # boundary), cut from the original, the marker itself left out.
            $end = $marker.Index + $marker.Length
            $from = $open.Substring(0, $marker.Index).LastIndexOfAny([char[]]'.!?') + 1
            $stop = $open.IndexOfAny([char[]]'.!?', $end)
            $to = if ($stop -lt 0) { $line.Length } else { $stop + 1 }
            $sentence = $line.Substring($from, $marker.Index - $from) + $line.Substring($end, $to - $end)
            $draft = ($bulletPattern.Replace($sentence, '') -replace '\s+', ' ' -replace ' ([.,;:!?])', '$1').Trim()
            $finding.Add([pscustomobject]@{ path = $Label; line = $number; marker = $form; draft = $draft })
        }
    }
}

try {
    $isMarkdown = { param([string] $File) $File -match '\.(md|markdown)$' }
    if ($AllLines) {
        $tracked = @(& $withUtf8Output { & git -c core.quotepath=off -C $Path ls-files -z 2>$null }) -join '' -split "`0" |
            Where-Object { $_ }
        if ($LASTEXITCODE -ne 0) { & $fail "git ls-files failed under '$Path' (not a git checkout?)." }
        foreach ($file in $tracked) {
            $full = Join-Path $Path $file
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
            $bytes = [System.IO.File]::ReadAllBytes($full)
            if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { continue }
            & $scan $file ([System.Text.Encoding]::UTF8.GetString($bytes)) (& $isMarkdown $file) $null
        }
    } else {
        $scope = & (Join-Path $PSScriptRoot 'get-changed-lines.ps1') -Root $Path -BaseRef $BaseRef
        if (-not $scope) { & $fail "no merge base of '$BaseRef' and HEAD under '$Path'." }
        foreach ($file in ($scope.Lines.Keys | Sort-Object)) {
            $full = Join-Path $Path $file
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
            $bytes = [System.IO.File]::ReadAllBytes($full)
            if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { continue }
            & $scan $file ([System.Text.Encoding]::UTF8.GetString($bytes)) (& $isMarkdown $file) $scope.Lines[$file]
        }
    }
    if ($Issue) {
        $body = & (Join-Path $PSScriptRoot 'get-rest-items.ps1') -Endpoint "repos/$Repo/issues/$Issue"
        & $scan "#$Issue" ([string]$body.body) $true $null
    }
} catch {
    & $fail ($_.Exception.Message -replace '\s+', ' ')
}

$ordered = @($finding)
$line = @($ordered | ForEach-Object {
        $hint = if ($_.marker -match 'frage') { ' - use (question <N>)' } else { '' }
        "$($_.path):$($_.line): $($_.marker) without question number - draft: `"$($_.draft)`"$hint"
    })
if ($Json) {
    if ($ordered.Count) { $ordered | ConvertTo-Json -AsArray -Depth 3 } else { '[]' }
} elseif (-not $Waive) {
    $line
}
if ($Waive) {
    if (-not $Json) { $line | ForEach-Object { Write-Warning $_ } }
    # With -Json stdout stays the one JSON array; the waiver line goes to stderr.
    if ($Json) { [Console]::Error.WriteLine("Question check waived: $Waive") } else { "Question check waived: $Waive" }
    exit 0
}
if ($ordered.Count -gt 0) { exit 1 }
