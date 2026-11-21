#Requires -Version 7.6

<#
.SYNOPSIS
    The one way the scripts call gh: stdout is the result, stderr never is (ww3d/playbook#682).

.DESCRIPTION
    gh writes advice on stderr (since 2.105 a multi-line `hint:` on `gh pr view` and `gh api`). A script that
    merges stderr into its result reads that advice as data or as a finding. This script keeps the streams
    apart: stderr comes back as its own field, so a failure can still say what gh said.

    Every other script calls gh only through here; `tests/GhCalls.Tests.ps1` turns a bare `gh` call red.

    stdout is decoded as UTF-8 (no BOM) for the call and the old encoding put back in `finally`; the setting
    is process-wide, so a caller that runs gh in parallel threads wraps them all in one
    `invoke-utf8-output.ps1` call and passes -KeepEncoding. Self-contained: no module import, since it is
    mirrored into every consumer via scripts/common/.

.PARAMETER Argument
    The arguments after `gh`, as given (`@('api', 'repos/o/r/issues/7')`).

.PARAMETER InputBody
    Text piped to gh's stdin (`gh api graphql --input -`).

.PARAMETER KeepEncoding
    Leave [Console]::OutputEncoding alone; the caller has set it.

.OUTPUTS
    One object: ExitCode (int), Output (string[], the stdout lines), Error (string, stderr trimmed).
    $LASTEXITCODE is left at 0 so no caller's `$ErrorActionPreference`/exit logic trips on a handled failure.

.EXAMPLE
    $r = & (Join-Path $PSScriptRoot 'invoke-gh.ps1') -Argument 'api', "repos/$repo/pulls/$pr"
    if ($r.ExitCode -ne 0) { throw "gh failed: $($r.Error)" }
    $pull = ($r.Output -join "`n") | ConvertFrom-Json
#>
param(
    [Parameter(Mandatory)][string[]] $Argument,
    [string] $InputBody,
    [switch] $KeepEncoding
)

# A handled failure: neither the caller's preference may turn gh's exit code or stderr into an exception.
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false
$ghSavedEncoding = [Console]::OutputEncoding
try {
    if (-not $KeepEncoding) { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) }
    # 2>&1 only to tell the streams apart by type: a stderr line of gh (or of a PowerShell stand-in on PATH)
    # arrives as an ErrorRecord, a stdout line as a string. Written to a file instead, a stand-in's
    # Write-Error would land there with the error view (line numbers) around its message.
    $ghAll = if ($PSBoundParameters.ContainsKey('InputBody')) {
        $InputBody | & gh @Argument 2>&1
    } else {
        & gh @Argument 2>&1
    }
    $ghExit = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    [pscustomobject]@{
        ExitCode = $ghExit
        Output   = @($ghAll | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
        Error    = (@($ghAll | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }) -join "`n").Trim()
    }
} finally {
    if (-not $KeepEncoding) { [Console]::OutputEncoding = $ghSavedEncoding }
}
