#Requires -Version 7.6

<#
.SYNOPSIS
    Plan the full run before a merge or a build in parts that each fit the 3-minute run limit
    (ww3d/playbook#632).

.DESCRIPTION
    Reads the measured seconds of every test from .agents/config/test-limits.json (written by
    scripts/common/measure-test-times.ps1), sums them per unit (the class or test file a test belongs to)
    and packs the units into parts of at most -LimitSec planned seconds, build included: a part costs
    `max(sum of its units / -Workers, its biggest unit) + -BuildSec`. Biggest units first, each into the
    first part it fits; a unit that does not fit alone gets a part of its own and is named under
    `oversize`.

    A unit without a measured time is planned with the hang value of the repo (`hangTimeoutSec`, else
    150 s) and named under `unmeasured`. The times of the last run, in -LastRunPath, win over the file's
    for the units they hold, so the next plan starts from what the last run showed. -MarkTorn records the
    units of a part the run limit ended: each is set to its share of twice the limit (the part took
    longer than the limit), so the next plan cuts the part anew.

    Every part is run by the repo's own test entry as a `gated` run of scripts/common/invoke-guarded-run.ps1,
    under the same limit as any other run, and written under "How tested" as `Mode full part <k>/<n>`.
    -Register notes the plan in `splitPlans` of the config; from then on invoke-guarded-run.ps1 refuses
    -Kind full-before-merge for the command the entry `covers`.

.PARAMETER RepoRoot
    The repo. Default: the current folder.

.PARAMETER Unit
    The units to run. Default: every unit the measurement knows. Units named here but not measured are planned
    with the hang value.

.PARAMETER LimitSec
    Planned seconds per part, build included. Default 150, at most 150: the margin to 3:00 is for the run's start
    and the load of the host.

.PARAMETER BuildSec
    The build time every part pays. Default 0.

.PARAMETER Workers
    The workers a part spreads its units over. Default 1.

.PARAMETER Name
    The plan's name. Default `full`.

.PARAMETER LastRunPath
    The times of the last run; default: a file in the temp folder named for the repo.

.PARAMETER MarkTorn
    Units of a part that the run limit ended; recorded into -LastRunPath, nothing is planned.

.PARAMETER Register
    Note the plan under `splitPlans` of the config.

.PARAMETER Covers
    With -Register: the command text of the test entry the plan replaces. Default `scripts/test.ps1`.

.OUTPUTS
    [pscustomobject] with Name, LimitSec, BuildSec, Workers, LastRunPath, Parts (Part, Of, PlannedSec, Units),
    Unmeasured and Oversize.

.EXAMPLE
    ./scripts/common/split-test-run.ps1 -Workers 16 | ConvertTo-Json -Depth 4
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [string] $RepoRoot = (Get-Location).ProviderPath,
    [string[]] $Unit,
    [ValidateRange(1, 150)][double] $LimitSec = 150,
    [ValidateRange(0, 150)][double] $BuildSec = 0,
    [ValidateRange(1, 64)][int] $Workers = 1,
    [string] $Name = 'full',
    [string] $LastRunPath,
    [string[]] $MarkTorn,
    [switch] $Register,
    [string] $Covers = 'scripts/test.ps1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
$configPath = Join-Path $RepoRoot '.agents/config/test-limits.json'
if (-not $LastRunPath) {
    $hash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($RepoRoot.ToLowerInvariant())))
    $LastRunPath = Join-Path ([System.IO.Path]::GetTempPath()) "test-times-$($hash.Substring(0, 12)).json"
}

$unitOfKey = { param([string] $Key) $Key.Substring(0, [Math]::Max(0, $Key.IndexOf('::'))) }
$readTimes = {
    param([string] $Path, [string] $Property)
    $found = @{}
    if (Test-Path -LiteralPath $Path) {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
        $table = if ($Property) { if ($json.ContainsKey($Property)) { $json[$Property] } else { @{} } } else { $json }
        foreach ($entry in $table.GetEnumerator()) { $found[$entry.Key] = [double]$entry.Value }
    }
    $found
}

$config = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
$hangSec = if ($config.ContainsKey('hangTimeoutSec')) { [double]$config['hangTimeoutSec'] } else { 150.0 }

# Seconds per unit: the last run's value for a unit it holds, else the config's.
$unitSec = @{}
$last = & $readTimes $LastRunPath ''
$lastUnits = @($last.Keys | ForEach-Object { & $unitOfKey $_ } | Select-Object -Unique)
foreach ($fromLast in $false, $true) {
    $source = if ($fromLast) { $last } else { & $readTimes $configPath 'tests' }
    foreach ($key in $source.Keys) {
        $u = & $unitOfKey $key
        if (-not $fromLast -and $u -in $lastUnits) { continue }
        $unitSec[$u] = ($unitSec[$u] ?? 0) + $source[$key]
    }
}
if ($MarkTorn) {
    foreach ($torn in $MarkTorn) {
        foreach ($key in @($last.Keys | Where-Object { (& $unitOfKey $_) -eq $torn })) { $last.Remove($key) }
        $last["$torn::torn"] = [Math]::Round([Math]::Max($unitSec[$torn] ?? 0, 2 * $LimitSec * $Workers / $MarkTorn.Count), 3)
    }
    New-Item -ItemType Directory -Path (Split-Path -Path $LastRunPath -Parent) -Force | Out-Null
    $last | ConvertTo-Json | Set-Content -LiteralPath $LastRunPath -Encoding utf8
    return [pscustomobject]@{ Name = $Name; Torn = @($MarkTorn); LastRunPath = $LastRunPath }
}
$units = @(if ($Unit) { $Unit | Select-Object -Unique } else { $unitSec.Keys | Sort-Object })
if ($units.Count -eq 0) { throw "No unit to plan: no -Unit given and no measured test in $configPath (run scripts/common/measure-test-times.ps1 first)." }

$unmeasured = @($units | Where-Object { -not $unitSec.ContainsKey($_) })
$weight = @{}
foreach ($u in $units) { $weight[$u] = if ($unitSec.ContainsKey($u)) { $unitSec[$u] } else { $hangSec } }

$capacity = $LimitSec - $BuildSec
$bins = [System.Collections.Generic.List[object]]::new()
$oversize = [System.Collections.Generic.List[string]]::new()
$loadOf = { param($Bin) [Math]::Max($Bin.Sum / $Workers, $Bin.Max) }
foreach ($u in $units | Sort-Object { $weight[$_] } -Descending) {
    if ($weight[$u] -gt $capacity) {
        $oversize.Add($u)
        $bins.Add([pscustomobject]@{ Units = [System.Collections.Generic.List[string]]@($u); Sum = $weight[$u]; Max = $weight[$u]; Alone = $true })
        continue
    }
    $target = $bins | Where-Object { -not $_.Alone -and (& $loadOf ([pscustomobject]@{ Sum = $_.Sum + $weight[$u]; Max = [Math]::Max($_.Max, $weight[$u]) })) -le $capacity } | Select-Object -First 1
    if ($target) { $target.Units.Add($u); $target.Sum += $weight[$u]; $target.Max = [Math]::Max($target.Max, $weight[$u]) }
    else { $bins.Add([pscustomobject]@{ Units = [System.Collections.Generic.List[string]]@($u); Sum = $weight[$u]; Max = $weight[$u]; Alone = $false }) }
}

$parts = @(for ($i = 0; $i -lt $bins.Count; $i++) {
        [pscustomobject]@{
            Part = $i + 1; Of = $bins.Count; PlannedSec = [Math]::Round((& $loadOf $bins[$i]) + $BuildSec, 1)
            Units = @($bins[$i].Units | Sort-Object)
        }
    })

if ($Register) {
    $plans = @(if ($config.ContainsKey('splitPlans')) { $config['splitPlans'] | Where-Object { $_.name -ne $Name } })
    $plans += [ordered]@{ name = $Name; covers = $Covers }
    $config['splitPlans'] = $plans
    New-Item -ItemType Directory -Path (Split-Path -Path $configPath -Parent) -Force | Out-Null
    $config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding utf8
}

[pscustomobject]@{
    Name = $Name; LimitSec = $LimitSec; BuildSec = $BuildSec; Workers = $Workers; LastRunPath = $LastRunPath
    Parts = $parts; Unmeasured = $unmeasured; Oversize = @($oversize)
}
