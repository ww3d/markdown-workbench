# Build orchestrator for the markdown-workbench extension.
#
# Tasks:
#   Check     - format check (Biome + Prettier), lint (Biome), typecheck (tsc -b) and the type scope tests
#   Test      - run the unit tests (node:test; tests/package/ and tests/probes/ run in Package and Check)
#   Coverage  - run tests under c8 with the coverage gate
#   Build     - bundle the extension host and the webview (tsdown) into dist/, smoke both, then the size gate
#   Package   - Build + the package tests against the built dist/ + create the .vsix with vsce
#   Integration - Build + the integration tests in a real VS Code
#               (@vscode/test-electron; under Linux through xvfb-run -a)
#   All       - Check + version check + Coverage + Package + Integration (default)
#
# The version in package.json is the source of truth (vsce requirement);
# the topmost CHANGELOG.md entry must match it. Every output path comes from
# eng/layout.ts (Get-Layout), never from a literal here.

[CmdletBinding()]
param(
    [ValidateSet('Check', 'Test', 'Coverage', 'Build', 'Package', 'Integration', 'All')]
    [string] $Task = 'All',
    # Opt out of the implicit dependency restore (dotnet convention): fall back
    # to fail-fast with 'run pnpm install --frozen-lockfile first' instead of restoring.
    [switch] $NoRestore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

# The output layout from eng/layout.ts, resolved once per run.
$script:Layout = $null
function Get-Layout {
    if (-not $script:Layout) {
        $json = node eng/layout.ts
        if ($LASTEXITCODE -ne 0) {
            throw "Reading the output layout (node eng/layout.ts) failed with exit code $LASTEXITCODE."
        }
        $script:Layout = $json | ConvertFrom-Json
    }
    return $script:Layout
}

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
    Invoke-Step 'Typecheck (tsc -b)' {
        pnpm run typecheck
    }
    # The type probes only prove something while each check scope includes them (tests/probes/).
    # Runs here with the typecheck, not in the unit run: three compiler runs are no unit test.
    Invoke-Step 'Type scope tests (tests/probes)' {
        node --test 'tests/probes/**/*.test.ts'
    }
}

# The unit run (the command of pnpm test): four test processes at once instead of Node's default
# of one per core minus one - the runner itself idles, and the CI runners have four cores.
function Invoke-Tests {
    Invoke-Step 'Tests (node:test)' {
        node --env-file=tests/helpers/compile-cache.env --import ./tests/helpers/setup.ts --test --test-concurrency=4 'tests/*.test.ts' 'tests/!(package|probes)/**/*.test.ts'
    }
}

function Invoke-Coverage {
    $layout = Get-Layout
    Invoke-Step 'Tests with coverage gate (c8)' {
        pnpm exec c8 --all --src src --include='src/**/*.ts' `
            --reporter=text --reporter=lcov `
            --reports-dir $layout.coverage --temp-directory $layout.coverageTemp `
            --check-coverage --lines 88 --branches 82 --functions 78 `
            node --env-file=tests/helpers/compile-cache.env --import ./tests/helpers/setup.ts --test --test-concurrency=4 'tests/*.test.ts' 'tests/!(package|probes)/**/*.test.ts'
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
        node scripts/bundle-smoke.ts
    }
    # The same for the webview bundle: the unit tests import src/webview, so only a
    # run of the built dist/webview.js (in happy-dom) sees what the bundler made of it.
    Invoke-Step 'Webview smoke test' {
        node scripts/webview-smoke.ts
    }
    # Last step of the build, before anything is packaged: the bundles stay inside the size
    # limits (gzip P1/P2 and the uncompressed bytes of the webview files).
    Invoke-Step 'Size gate' {
        node scripts/size-gate.ts
    }
}

# The package layer (tests/package/): checks that read the built dist/ and the real vsce
# pack list. Kept out of the unit run (`pnpm test`, coverage), which builds nothing (REQ-020).
function Invoke-PackageTests {
    Invoke-Step 'Package tests (built dist/)' {
        node --test 'tests/package/**/*.test.ts'
    }
}

function Invoke-Package {
    Invoke-Build
    Invoke-PackageTests
    $packages = (Get-Layout).packages
    New-Item -ItemType Directory -Force -Path $packages | Out-Null
    Invoke-Step 'Package (vsce)' {
        pnpm exec vsce package --out $packages
    }
    Get-ChildItem (Join-Path $packages '*.vsix') | Sort-Object LastWriteTime | Select-Object -Last 1 |
        ForEach-Object { Write-Host "Created $($_.Name) ($([math]::Round($_.Length / 1MB, 2)) MB)" }
}

# Runs the extension in a real VS Code (the minimum version from engines.vscode
# and the current stable one), docs/DECISIONS.md #48. Linux has no display in
# CI or containers, so the run goes through xvfb-run there.
function Invoke-Integration {
    Invoke-Step 'Integration tests (VS Code, @vscode/test-electron)' {
        if ($IsLinux) {
            xvfb-run -a node tests/integration/run.ts
        }
        else {
            node tests/integration/run.ts
        }
    }
}

try {
    Assert-Dependencies # every task runs node/pnpm exec; guard all of them up front
    switch ($Task) {
        'Check' { Invoke-Check }
        'Test' { Invoke-Tests }
        'Coverage' { Invoke-Coverage }
        'Build' { Invoke-Build }
        'Package' { Assert-VersionConsistency; Invoke-Package }
        'Integration' { Invoke-Build; Invoke-Integration }
        'All' {
            Invoke-Check
            Assert-VersionConsistency
            Invoke-Coverage
            Invoke-Package
            Invoke-Integration
        }
    }
    Write-Host 'Done.' -ForegroundColor Green
} finally {
    Pop-Location
}
