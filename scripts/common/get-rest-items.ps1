#Requires -Version 7.6

<#
.SYNOPSIS
    Read every page of a GitHub REST endpoint and emit the items as one flat
    stream - the one REST reader the scripts in this directory share.

.DESCRIPTION
    Several scripts here read issues, pull requests, reviews or commits over
    `gh api` (REST only; why: .agents/rules/pr.md "Forge Tooling"). Each used to carry its own copy
    of the same reader. They now call this script.

    The pages are fetched here, one `gh api` call each, through `page=N` on the given path - not
    through `gh api --paginate`, which follows the `Link` header of the answer to
    `repositories/<id>/...`, a path the proxy of a Claude Code web session refuses (HTTP 403). A
    list is read until a page is shorter than its `per_page` (the one in the endpoint's query, else
    GitHub's default of 30), so give a long list `per_page=100`. An answer that is a single object
    stays one call, with no paging parameter added to the path.

    A failing `gh` call throws; a caller that degrades catches it.

    This script is deliberately SELF-CONTAINED - it imports no module, because
    it is mirrored into every consumer via scripts/common/.

.PARAMETER Endpoint
    The REST path, for example `repos/<owner>/<repo>/pulls/<n>/commits?per_page=100`.

.INPUTS
    None.

.OUTPUTS
    [pscustomobject] one per item of every page, in order.

.EXAMPLE
    @(./scripts/common/get-rest-items.ps1 -Endpoint 'repos/ww3d/playbook/pulls/352')[0].head.sha

    The head SHA of a pull request.
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Endpoint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PSNativeCommandUseErrorActionPreference = $false
# gh is called through the one wrapper that keeps its stderr out of the result (ww3d/playbook#682).
$invokeGh = Join-Path $PSScriptRoot 'invoke-gh.ps1'

$path, $query = $Endpoint -split '\?', 2
$perPage = if ($query -match '(?:^|&)per_page=(\d+)(?:&|$)') { [int]$Matches[1] } else { 30 }
# The query without a `page` of the caller's own: this script sets it.
$baseQuery = (@($query -split '&' | Where-Object { $_ -and $_ -notmatch '^page=' }) -join '&')

for ($page = 1; ; $page++) {
    $request = if ($page -eq 1) { $Endpoint } else { "${path}?$(@($baseQuery, "page=$page").Where({ $_ }) -join '&')" }
    $reply = & $invokeGh -Argument 'api', $request
    if ($reply.ExitCode -ne 0) {
        throw "gh api $request exited $($reply.ExitCode)$(if ($reply.Error) { ": $($reply.Error)" })"
    }
    $raw = $reply.Output
    # -NoEnumerate keeps a one-element list a list, so it is told from a single object.
    $answer = ($raw -join "`n") | ConvertFrom-Json -NoEnumerate
    if ($answer -isnot [array]) { $answer; break }
    $answer | ForEach-Object { $_ }
    if ($answer.Count -lt $perPage) { break }
}
