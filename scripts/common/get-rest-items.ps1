#Requires -Version 7.4

<#
.SYNOPSIS
    Read every page of a GitHub REST endpoint and emit the items as one flat
    stream - the one REST reader the scripts in this directory share.

.DESCRIPTION
    Several scripts here read issues, pull requests, reviews or commits over
    `gh api` (REST only; why: AGENTS.md "Forge Tooling"). Each used to carry its own copy
    of the same reader. They now call this script.

    `--paginate` alone concatenates several JSON arrays past 100 items, which
    ConvertFrom-Json cannot parse; `--slurp` wraps the pages in one outer array,
    which is flattened here. A single object comes back as a one-element stream.
    Without `--paginate` the default page size of 30 would truncate exactly the
    long lists this reads.

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
# Native output decoded as UTF-8, whatever the console code page: `& $withUtf8Output { <call> } <arguments>`.
$withUtf8Output = Join-Path $PSScriptRoot 'invoke-utf8-output.ps1'

# stderr is kept apart from the JSON on stdout, so a failure can say what gh said.
$output = @(& $withUtf8Output { & gh api $Endpoint --paginate --slurp 2>&1 })
$exitCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($exitCode -ne 0) {
    $stderr = (@($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join ' ').Trim()
    throw "gh api $Endpoint exited ${exitCode}$(if ($stderr) { ": $stderr" })"
}
$raw = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
@($raw | ConvertFrom-Json | ForEach-Object { $_ })
