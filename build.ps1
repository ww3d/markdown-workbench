# Build orchestrator for the markdown-workbench extension.
#
# Tasks:
#   Check     - format check (Biome + Prettier) and lint (Biome)
#   Test      - run the node:test suites
#   Coverage  - run tests under c8 with the coverage gate
#   Build     - bundle the extension with esbuild into dist/
#   Package   - Build + create the .vsix with vsce
#   All       - Check + version check + Coverage + Package (default)
#
# The version in package.json is the source of truth (vsce requirement);
# the topmost CHANGELOG.md entry must match it.

[CmdletBinding()]
param(
    [ValidateSet('Check', 'Test', 'Coverage', 'Build', 'Package', 'All')]
    [string] $Task = 'All',
    # Opt out of the implicit dependency restore (dotnet convention): fall back
    # to fail-fast with 'run pnpm install --frozen-lockfile first' instead of restoring.
    [switch] $NoRestore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

function Invoke-Step {
    param(
        [string] $Name,
        [scriptblock] $Action
    )
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "Step '$Name' failed with exit code $LASTEXITCODE."
    }
}

function Assert-Dependencies {
    # Step 0: detect a missing or stale node_modules before node/pnpm exec dies
    # with cryptic MODULE_NOT_FOUND (and a fake coverage drop). Cheap check, no
    # pnpm call: pnpm writes node_modules/.modules.yaml on install; if the
    # tracked pnpm-lock.yaml is newer, the tree is stale. -Force is required
    # because that marker is a dotfile and Get-Item skips hidden items without
    # it on Linux (Test-Path still finds them).
    $reason = $null
    if (-not (Test-Path 'node_modules')) {
        $reason = 'node_modules is missing'
    }
    else {
        $installed = 'node_modules/.modules.yaml'
        if (-not (Test-Path $installed)) {
            $reason = 'node_modules is stale (no install marker)'
        }
        elseif ((Get-Item 'pnpm-lock.yaml' -Force).LastWriteTimeUtc -gt
                (Get-Item $installed -Force).LastWriteTimeUtc) {
            $reason = 'node_modules is stale (pnpm-lock.yaml is newer than the install)'
        }
    }
    if (-not $reason) {
        Write-Host 'Dependencies present and consistent with pnpm-lock.yaml.'
        return
    }

    # In CI, never auto-install: a lockfile drift must surface as a red build,
    # not be silently repaired - the pipeline runs its own frozen install and
    # that stays the source of truth. -NoRestore forces the same fail-fast locally.
    if ($env:CI -or $NoRestore) {
        throw "$reason - run 'pnpm install --frozen-lockfile' first."
    }

    # Local default: implicit restore (like dotnet build since .NET Core 2.0),
    # announced up front - never silent. A failed restore aborts with pnpm's
    # exit code, never swallowed.
    Write-Host "$reason - restoring (pnpm install --frozen-lockfile)..." -ForegroundColor Yellow
    pnpm install --frozen-lockfile
    if ($LASTEXITCODE -ne 0) {
        throw "Dependency restore (pnpm install) failed with exit code $LASTEXITCODE."
    }
    Write-Host 'Dependencies restored.'
}

function Assert-VersionConsistency {
    $manifest = Get-Content -Raw 'package.json' | ConvertFrom-Json
    $changelogTop = (Select-String -Path 'CHANGELOG.md' -Pattern '^## (\d+\.\d+\.\d+)' |
        Select-Object -First 1).Matches[0].Groups[1].Value
    if ($manifest.version -ne $changelogTop) {
        throw "Version mismatch: package.json is $($manifest.version), topmost CHANGELOG entry is $changelogTop."
    }
    Write-Host "Version $($manifest.version) is consistent across package.json and CHANGELOG.md."
}

function Invoke-Check {
    Invoke-Step 'Format check (Biome + Prettier)' {
        pnpm run format
    }
    Invoke-Step 'Lint (Biome)' {
        pnpm run lint
    }
}

function Invoke-Tests {
    Invoke-Step 'Tests (node:test)' {
        node --test 'tests/**/*.test.js'
    }
}

function Invoke-Coverage {
    Invoke-Step 'Tests with coverage gate (c8)' {
        pnpm exec c8 --include='src/**/*.js' `
            --reporter=text --reporter=lcov `
            --check-coverage --lines 88 --branches 82 --functions 78 `
            node --test 'tests/**/*.test.js'
    }
}

function Invoke-Build {
    Invoke-Step 'Bundle (tsdown / Rolldown)' {
        pnpm exec tsdown
    }
    # Guards the bundle, not the sources: Shiki's languages/themes are lazy
    # chunks, and a broken cross-chunk runtime degrades silently to plain
    # code blocks (initHighlighter catches the load error). Unit tests run
    # against src/ and cannot see this.
    Invoke-Step 'Bundle smoke test' {
        node scripts/bundle-smoke.cjs
    }
}

function Invoke-Package {
    Invoke-Build
    Invoke-Step 'Package (vsce)' {
        pnpm exec vsce package
    }
    Get-ChildItem '*.vsix' | Sort-Object LastWriteTime | Select-Object -Last 1 |
        ForEach-Object { Write-Host "Created $($_.Name) ($([math]::Round($_.Length / 1MB, 2)) MB)" }
}

try {
    Assert-Dependencies # every task runs node/pnpm exec; guard all of them up front
    switch ($Task) {
        'Check' { Invoke-Check }
        'Test' { Invoke-Tests }
        'Coverage' { Invoke-Coverage }
        'Build' { Invoke-Build }
        'Package' { Assert-VersionConsistency; Invoke-Package }
        'All' {
            Invoke-Check
            Assert-VersionConsistency
            Invoke-Coverage
            Invoke-Package
        }
    }
    Write-Host 'Done.' -ForegroundColor Green
} finally {
    Pop-Location
}
