#Requires -Version 7.4

<#
.SYNOPSIS
    The patterns that find a qualified issue or pull request reference in text -
    the one definition get-issue-links.ps1 and find-closable-issues.ps1 share.

.DESCRIPTION
    Both scripts read `owner/repo#N` and `https://github.com/owner/repo/issues/N`
    out of Markdown. Each carried its own copy of the two patterns, word for
    word. A change to one (a new file suffix a fragment such as `docs/x.md#12`
    must not be mistaken for a repository) would have left the other behind.

    This script is deliberately SELF-CONTAINED - it imports no module, because
    it is mirrored into every consumer via scripts/common/.

.INPUTS
    None.

.OUTPUTS
    [pscustomobject] with Qualified and Url, two regular expressions. Group 1 of
    each match is `owner/repo`, group 2 the number.

.EXAMPLE
    $pattern = ./scripts/common/get-reference-pattern.ps1
    [regex]::Matches($text, $pattern.Qualified)

    Every `owner/repo#N` in $text.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[pscustomobject]@{
    # owner/repo#N with GitHub's owner charset; a file fragment such as `docs/x.md#12` is not a repository.
    Qualified = '(?<![\w/.-])([A-Za-z0-9-]+/[A-Za-z0-9._-]+)(?<!\.(?:md|ps1|psm1|psd1|json|ya?ml|txt|html?|cs|ts|js))#(\d+)(?![\w-])'
    Url       = 'https://github\.com/([A-Za-z0-9-]+/[A-Za-z0-9._-]+)/(?:issues|pull)/(\d+)\b'
}
