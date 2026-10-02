# Entry point of the root scripts (Build.cmd, Restore.cmd, Test.cmd, eng/common/CIBuild.cmd), Windows
# PowerShell 5.1 compatible: fetches the pinned Node and pnpm repo-local (tools.ps1), then hands every
# option to the build flow, eng/build.ts, which is where tasks, switches and their documentation live
# (`-help`). Modeled on ww3d/atlas eng/common/build.ps1.
#
# Atlas-style action switches and -Task are the same thing: -restore, -build, -test, -pack, -check,
# -coverage and -integrationTest each name a task; with none given, the task is All.

[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('Restore', 'Check', 'Test', 'Coverage', 'Build', 'Package', 'Integration', 'All')]
    [string[]] $Task = @(),
    [switch][Alias('r')] $restore,
    [switch][Alias('b')] $build,
    [switch][Alias('t')] $test,
    [switch] $check,
    [switch] $coverage,
    [switch] $pack,
    [switch] $integrationTest,
    [switch] $NoRestore,
    [switch] $ci,
    [switch] $release,
    [string] $officialBuildId,
    [switch] $clean,
    [string] $artifactsDir,
    [switch] $help
)

. (Join-Path $PSScriptRoot 'tools.ps1')

$tasks = @($Task)
if ($restore) { $tasks += 'Restore' }
if ($check) { $tasks += 'Check' }
if ($build) { $tasks += 'Build' }
if ($test) { $tasks += 'Test' }
if ($coverage) { $tasks += 'Coverage' }
if ($pack) { $tasks += 'Package' }
if ($integrationTest) { $tasks += 'Integration' }

$buildArgs = @()
foreach ($t in $tasks) { $buildArgs += '--task', $t }
if ($NoRestore) { $buildArgs += '--no-restore' }
if ($ci) { $buildArgs += '--ci' }
if ($release) { $buildArgs += '--release' }
if ($officialBuildId) { $buildArgs += '--official-build-id', $officialBuildId }
if ($clean) { $buildArgs += '--clean' }
if ($artifactsDir) { $buildArgs += '--artifacts-dir', $artifactsDir }
if ($help) { $buildArgs += '--help' }

Push-Location $RepoRoot
try {
    # -clean and -help need no toolchain beyond Node itself, but the fetch is cheap once cached.
    Initialize-Toolchain
    & node eng/build.ts @buildArgs
    $code = $LASTEXITCODE
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    $code = 1
}
finally {
    Pop-Location
}
exit $code
