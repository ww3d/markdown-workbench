#Requires -Version 7.6

<#
.SYNOPSIS
    Read the two forms the plan rule sets - the cap in the description of `plan/now` and the `Rank:` line
    in an issue body - the one reading every plan script shares.

.DESCRIPTION
    The plan rule (.agents/rules/docs.md "Planning") sets two forms:

    * the description of the label `plan/now` reads `Now: at most <N> at once`;
    * the body of an issue carries `Rank: <decimal>` as its own paragraph before its first H2 heading
      (`## Order` on a tracking issue).

    With -Description the answer is the cap, `$null` where the text does not have the form. With -Format
    the answer is the text of a rank: invariant culture, a point, no thousands separator, no zeros
    at the end (`2.5`, `3`). With -Body the answer is the rank and what is wrong with it:

    * Status `none`       no line starting with `Rank:` in the head, `Rank` is `$null`;
    * Status `ok`         exactly one line `Rank: <decimal>` standing as its own paragraph, `Rank` is its value
                          and `Text` its text;
    * Status `malformed`  anything else - two such lines, a value that is no decimal, text on the same
                          line behind the value, a line that touches the paragraph before or behind it;
                          `Rank` is `$null` and `Reason` says which.

    The head of a body is everything before the first level-2 heading outside a code fence; a
    `Rank:` line inside a fence is a quotation and does not count. A line counts as a rank line
    where it starts with `rank`, in any case, followed by a colon - so `rank: 2` is reported, not
    overlooked. A value reads as `[decimal]` with the invariant culture.

    This script is deliberately SELF-CONTAINED - it imports no module, because it is mirrored into
    every consumer via scripts/common/.

.PARAMETER Body
    The body of an issue.

.PARAMETER Description
    The description of the label `plan/now`.

.PARAMETER Format
    A rank to write as text.

.INPUTS
    None.

.OUTPUTS
    [pscustomobject] with Cap (int or $null) under -Description; with Status, Rank (decimal or $null), Text,
    Lines (the number of rank lines in the head) and Reason under -Body; a [string] under -Format.

.EXAMPLE
    ./scripts/common/get-plan-fields.ps1 -Description 'Now: at most 2 at once'

    Cap is 2.

.EXAMPLE
    ./scripts/common/get-plan-fields.ps1 -Body "Rank: 2.5`n`n## Order`n..."

    Status ok, Rank 2.5.

.EXAMPLE
    ./scripts/common/get-plan-fields.ps1 -Format ([decimal] 2.50)

    `2.5`.
#>

[CmdletBinding(DefaultParameterSetName = 'Body')]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory, ParameterSetName = 'Body')]
    [AllowEmptyString()]
    [string] $Body,

    [Parameter(Mandatory, ParameterSetName = 'Description')]
    [AllowEmptyString()]
    [string] $Description,

    [Parameter(Mandatory, ParameterSetName = 'Format')]
    [decimal] $Format
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The text of a rank: up to 28 decimals, the zeros at the end dropped.
function Format-Rank([decimal] $Rank) { $Rank.ToString('0.############################', [cultureinfo]::InvariantCulture) }

if ($PSCmdlet.ParameterSetName -eq 'Format') { return Format-Rank $Format }

if ($PSCmdlet.ParameterSetName -eq 'Description') {
    $cap = $null
    if ($Description -match '^\s*Now: at most (\d+) at once\s*$' -and [int]::TryParse($Matches[1], [ref] $cap)) {
        return [pscustomobject]@{ Cap = $cap }
    }
    return [pscustomobject]@{ Cap = $null }
}

# The lines of the head that stand outside a code fence (CommonMark: same character, at least as long,
# nothing but whitespace behind a closing fence), with their index in the head.
function Get-HeadLine([string] $Text) {
    $lines = @($Text -split "`r?`n")
    $fencePattern = '^\s*(?:>\s*)*(`{3,}|~{3,})(.*)$'
    $openFence = $null
    $head = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match $fencePattern) {
            $fence = $Matches[1]
            if ($null -eq $openFence) { $openFence = $fence }
            elseif ($fence[0] -eq $openFence[0] -and $fence.Length -ge $openFence.Length -and -not $Matches[2].Trim()) { $openFence = $null }
            $head.Add([pscustomobject]@{ Text = $line; Fenced = $true })
            continue
        }
        if ($null -eq $openFence -and $line -match '^ {0,3}##(?!#)(?:[ \t].*)?$') { break }
        $head.Add([pscustomobject]@{ Text = $line; Fenced = $null -ne $openFence })
    }
    , @($head)
}

$head = Get-HeadLine $Body
$candidate = @(0..($head.Count - 1) | Where-Object { $head.Count -and -not $head[$_].Fenced -and $head[$_].Text -match '^\s*(?i:rank)\s*:' })
$none = [pscustomobject]@{ Status = 'none'; Rank = $null; Text = ''; Lines = 0; Reason = '' }
if ($candidate.Count -eq 0) { return $none }

$malformed = { param($Reason) [pscustomobject]@{ Status = 'malformed'; Rank = $null; Text = ''; Lines = $candidate.Count; Reason = $Reason } }
if ($candidate.Count -gt 1) { return & $malformed "$($candidate.Count) rank lines" }

$at = $candidate[0]
$line = $head[$at].Text
if ($line -cnotmatch '^Rank: (\S+)[ \t]*$') { return & $malformed "not of the form 'Rank: <decimal>': '$($line.Trim())'" }
$text = $Matches[1]
$value = [decimal] 0
if ($text -notmatch '^\d+(?:\.\d+)?$' -or -not [decimal]::TryParse($text, [System.Globalization.NumberStyles]::AllowDecimalPoint, [cultureinfo]::InvariantCulture, [ref] $value)) {
    return & $malformed "'$text' is no decimal"
}
$before = $at -eq 0 -or -not $head[$at - 1].Text.Trim()
$behind = $at -eq $head.Count - 1 -or -not $head[$at + 1].Text.Trim()
if (-not ($before -and $behind)) { return & $malformed 'the rank line is not a paragraph of its own' }
[pscustomobject]@{ Status = 'ok'; Rank = $value; Text = (Format-Rank $value); Lines = 1; Reason = '' }
