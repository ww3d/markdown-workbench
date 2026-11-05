<#
.SYNOPSIS
    The first line of `git version`, asked once per process and PATH.

.DESCRIPTION
    test-pure-catch-up.ps1 and test-applied-suggestions.ps1 both check for git 2.40 or later, and the merge
    gate runs both in one process; each asking git anew cost one process start per proof
    (ww3d/playbook#427). The answer is kept in the process's AppDomain data, keyed on PATH: the PATH decides
    which git `& git` starts, so a version shim on another PATH is asked anew. A git replaced in place on
    the same PATH keeps its first answer until the process ends. An empty answer (no git) is not kept.

    This script is deliberately SELF-CONTAINED - it imports no module, because it is mirrored into every
    consumer via scripts/common/.

.INPUTS
    None.

.OUTPUTS
    [string] the first line of `git version`, '' when git prints none; a git missing from PATH raises
    CommandNotFoundException. $LASTEXITCODE is 0 afterwards.

.EXAMPLE
    $gitVersion = & (Join-Path $PSScriptRoot 'get-git-version.ps1')

    The version line, from git on the first call of the process and PATH, from memory after.
#>

[CmdletBinding()]
[OutputType([string])]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$key = "ww3d.playbook.git-version|$env:PATH"
$known = [AppDomain]::CurrentDomain.GetData($key)
if ($known) { return "$known" }
$answer = "$(& git version 2>$null | Select-Object -First 1)"
$global:LASTEXITCODE = 0
if ($answer) { [AppDomain]::CurrentDomain.SetData($key, $answer) }
$answer
