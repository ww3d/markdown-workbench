#Requires -Version 7.6

<#
.SYNOPSIS
    Read the time of every test from the result files of one run and write them, with the hang value of
    the repo, to .agents/config/test-limits.json (ww3d/playbook#632).

.DESCRIPTION
    The measurement behind the two limits of a run (.agents/rules/pr.md, section "Test Runs"): the per-test
    hang guard of scripts/common/invoke-guarded-run.ps1 and the parts of scripts/common/split-test-run.ps1.
    It reads TRX (dotnet test --logger trx), JUnit XML (nextest, Jest, Vitest) and NUnit XML (Pester) and
    keeps one number per test, keyed `<unit>::<test>` - the unit is the class or the test file the test
    belongs to, in a repo-relative path where the file lies under the repo.

    Written under `tests`: the seconds of each test. `slowestTest` names the slowest. `hangTimeoutSec` is
    3 x the slowest test, rounded up, at least 30 and at most 150. `measuredAt` is the UTC time.
    Every other key of the file stays as it is. A repo without a result file gets no value: the script
    says which path has none, writes nothing and exits 1, and the guard keeps its default of 150 s.

    With -LastRunPath the times go into that file only and the repo's config stays untouched - the cache
    the next plan of split-test-run.ps1 reads first, so a part that tore its limit is cut anew.

.PARAMETER ResultPath
    Result files or folders; a folder is searched for *.trx and *.xml, deeply.

.PARAMETER RepoRoot
    The repo. Default: the current folder.

.PARAMETER ConfigPath
    The config file to write. Default: .agents/config/test-limits.json under -RepoRoot.

.PARAMETER LastRunPath
    Write the times of this run only to this file (a JSON object: unit::test to seconds).

.PARAMETER DryRun
    Print what would be written and write nothing.

.OUTPUTS
    [pscustomobject] with Tests, Slowest, SlowestSec, HangTimeoutSec, Target and Written.

.EXAMPLE
    ./scripts/common/measure-test-times.ps1 -ResultPath ./TestResults -DryRun
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)][string[]] $ResultPath,
    [string] $RepoRoot = (Get-Location).ProviderPath,
    [string] $ConfigPath,
    [string] $LastRunPath,
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
if (-not $ConfigPath) { $ConfigPath = Join-Path $RepoRoot '.agents/config/test-limits.json' }

$files = @(foreach ($item in $ResultPath) {
        if (-not (Test-Path -LiteralPath $item)) { continue }
        $full = (Resolve-Path -LiteralPath $item).ProviderPath
        if (Test-Path -LiteralPath $full -PathType Container) {
            Get-ChildItem -LiteralPath $full -Recurse -File | Where-Object { $_.Extension -in '.trx', '.xml' }
        } else { Get-Item -LiteralPath $full }
    })
if ($files.Count -eq 0) {
    Write-Error "No result file under: $($ResultPath -join ', '). Nothing measured, nothing written; the hang guard keeps its default of 150 s." -ErrorAction Continue
    exit 1
}

# A unit that is a file path under the repo is written repo-relative with forward slashes.
$unitName = {
    param([string] $Name)
    if ($Name -and [System.IO.Path]::IsPathRooted($Name)) {
        $relative = [System.IO.Path]::GetRelativePath($RepoRoot, $Name)
        if (-not $relative.StartsWith('..')) { return $relative -replace '\\', '/' }
    }
    $Name
}

$seconds = [System.Collections.Generic.Dictionary[string, double]]::new()
$add = {
    param([string] $Unit, [string] $Test, [double] $Value)
    $key = "$(& $unitName $Unit)::$Test"
    $seconds[$key] = [Math]::Round($(if ($seconds.ContainsKey($key)) { $seconds[$key] } else { 0 }) + $Value, 3)
}
$number = { param([string] $Text) [double]::Parse($Text, [cultureinfo]::InvariantCulture) }

foreach ($file in $files) {
    $xml = [xml](Get-Content -LiteralPath $file.FullName -Raw)
    $root = $xml.DocumentElement.LocalName
    switch ($root) {
        'TestRun' {
            $unitOf = @{}
            foreach ($definition in $xml.SelectNodes("//*[local-name()='UnitTest']")) {
                $method = $definition.SelectSingleNode("*[local-name()='TestMethod']")
                if ($method) { $unitOf[$definition.GetAttribute('id')] = $method.GetAttribute('className') }
            }
            foreach ($result in $xml.SelectNodes("//*[local-name()='UnitTestResult']")) {
                $duration = [timespan]::Parse($result.GetAttribute('duration'), [cultureinfo]::InvariantCulture)
                & $add $unitOf[$result.GetAttribute('testId')] $result.GetAttribute('testName') $duration.TotalSeconds
            }
        }
        { $_ -in 'testsuites', 'testsuite' } {
            foreach ($case in $xml.SelectNodes('//testcase')) {
                $unit = $case.GetAttribute('classname')
                if (-not $unit) { $unit = $case.ParentNode.GetAttribute('name') }
                & $add $unit $case.GetAttribute('name') (& $number "0$($case.GetAttribute('time'))")
            }
        }
        { $_ -in 'test-results', 'test-run' } {
            foreach ($case in $xml.SelectNodes('//test-case')) {
                # NUnit 3 names the class; NUnit 2.5 (Pester) nests the test in a suite per file, below the
                # root suite: the second suite from the top is the unit.
                $unit = $case.GetAttribute('classname')
                if (-not $unit) {
                    $suites = @()
                    for ($node = $case.ParentNode; $node; $node = $node.ParentNode) { if ($node.LocalName -eq 'test-suite') { $suites += $node } }
                    $pick = if ($suites.Count -ge 2) { $suites[$suites.Count - 2] } elseif ($suites.Count -eq 1) { $suites[0] } else { $null }
                    $unit = if ($pick) { $pick.GetAttribute('name') } else { '' }
                }
                $time = $case.GetAttribute('time'); if (-not $time) { $time = $case.GetAttribute('duration') }
                & $add $unit $case.GetAttribute('name') (& $number "0$time")
            }
            # What a file costs besides its tests (discovery, setup blocks, the worker start) counts for its part.
            foreach ($suite in $xml.SelectNodes('/test-results/test-suite/results/test-suite')) {
                $inner = 0.0
                foreach ($case in $suite.SelectNodes('.//test-case')) { $time = $case.GetAttribute('time'); if (-not $time) { $time = $case.GetAttribute('duration') }; $inner += (& $number "0$time") }
                $setup = [Math]::Max(0, (& $number "0$($suite.GetAttribute('time'))") - $inner)
                if ($setup -gt 0) { & $add $suite.GetAttribute('name') '~setup' $setup }
            }
        }
        default { Write-Warning "Result file '$($file.Name)' has the root element '$root', not TRX, JUnit or NUnit: skipped." }
    }
}
if ($seconds.Count -eq 0) {
    Write-Error "No test found in: $(($files | ForEach-Object Name) -join ', '). Nothing written." -ErrorAction Continue
    exit 1
}

$slowest = $seconds.GetEnumerator() | Where-Object { -not $_.Key.EndsWith('::~setup') } | Sort-Object Value -Descending | Select-Object -First 1
$hang = [int][Math]::Min(150, [Math]::Max(30, [Math]::Ceiling(3 * $slowest.Value)))
$tests = [ordered]@{}
foreach ($entry in $seconds.GetEnumerator() | Sort-Object Key) { $tests[$entry.Key] = $entry.Value }

$target = if ($LastRunPath) { $LastRunPath } else { $ConfigPath }
if (-not $DryRun) {
    if ($LastRunPath) {
        New-Item -ItemType Directory -Path (Split-Path -Path $LastRunPath -Parent) -Force | Out-Null
        # A run's file holds one part: the units it measured replace theirs, the others stay.
        $unitOf = { param([string] $Key) $Key.Substring(0, [Math]::Max(0, $Key.IndexOf('::'))) }
        $ran = @($tests.Keys | ForEach-Object { & $unitOf $_ } | Select-Object -Unique)
        $merged = [ordered]@{}
        if (Test-Path -LiteralPath $LastRunPath) {
            foreach ($entry in (Get-Content -LiteralPath $LastRunPath -Raw | ConvertFrom-Json -AsHashtable).GetEnumerator()) {
                if ((& $unitOf $entry.Key) -notin $ran) { $merged[$entry.Key] = $entry.Value }
            }
        }
        foreach ($entry in $tests.GetEnumerator()) { $merged[$entry.Key] = $entry.Value }
        $merged | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $LastRunPath -Encoding utf8
    } else {
        $config = [ordered]@{}
        if (Test-Path -LiteralPath $ConfigPath) {
            foreach ($entry in (Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -AsHashtable).GetEnumerator()) { $config[$entry.Key] = $entry.Value }
        }
        $config['hangTimeoutSec'] = $hang
        $config['slowestTest'] = [ordered]@{ name = $slowest.Key; sec = $slowest.Value }
        $config['measuredAt'] = [datetime]::UtcNow.ToString("yyyy-MM-dd'T'HHmm'Z'")
        $config['tests'] = $tests
        New-Item -ItemType Directory -Path (Split-Path -Path $ConfigPath -Parent) -Force | Out-Null
        $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding utf8
    }
}

[pscustomobject]@{
    Tests = $seconds.Count; Slowest = $slowest.Key; SlowestSec = $slowest.Value; HangTimeoutSec = $hang
    Target = $target; Written = -not $DryRun
}
