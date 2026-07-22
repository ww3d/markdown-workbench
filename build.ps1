# Build orchestrator for the markdown-workbench extension.
#
# Tasks:
#   Test      - run the node:test suites
#   Coverage  - run tests under c8 with the coverage gate
#   Build     - bundle the extension with esbuild into dist/
#   Package   - Build + create the .vsix with vsce
#   All       - version check + Coverage + Package (default)
#
# The version in package.json is the source of truth (vsce requirement);
# the topmost CHANGELOG.md entry must match it.

[CmdletBinding()]
param(
    [ValidateSet('Test', 'Coverage', 'Build', 'Package', 'All')]
    [string] $Task = 'All'
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
    # Step 0: fail fast with a clear message when node_modules is missing or
    # stale, instead of letting node/npx die with cryptic MODULE_NOT_FOUND (and
    # a fake coverage drop). No auto-install - the fix is a deliberate 'npm ci'.
    # Cheap check, no npm call: npm writes node_modules/.package-lock.json on
    # install; if the tracked package-lock.json is newer, the tree is stale.
    if (-not (Test-Path 'node_modules')) {
        throw "node_modules is missing - run 'npm ci' first."
    }
    $installed = 'node_modules/.package-lock.json'
    if (-not (Test-Path $installed)) {
        throw "node_modules is stale (no install marker) - run 'npm ci' first."
    }
    if ((Get-Item 'package-lock.json').LastWriteTimeUtc -gt (Get-Item $installed).LastWriteTimeUtc) {
        throw "node_modules is stale (package-lock.json is newer than the install) - run 'npm ci' first."
    }
    Write-Host 'Dependencies present and consistent with package-lock.json.'
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

function Invoke-Tests {
    Invoke-Step 'Tests (node:test)' {
        node --test tests/*.test.js
    }
}

function Invoke-Coverage {
    Invoke-Step 'Tests with coverage gate (c8)' {
        npx c8 --include=src/extension.js --include=src/render.js `
            --include=src/views.js --include=src/editing.js `
            --reporter=text --reporter=lcov `
            --check-coverage --lines 88 --branches 82 --functions 78 `
            node --test tests/*.test.js
    }
}

function Invoke-Build {
    Invoke-Step 'Bundle (tsdown / Rolldown)' {
        npx tsdown
    }
    # Guards the bundle, not the sources: Shiki's languages/themes are lazy
    # chunks, and a broken cross-chunk runtime degrades silently to plain
    # code blocks (initHighlighter catches the load error). Unit tests run
    # against src/ and cannot see this.
    Invoke-Step 'Bundle smoke test' {
        node scripts/bundle-smoke.js
    }
}

function Invoke-Package {
    Invoke-Build
    Invoke-Step 'Package (vsce)' {
        npx vsce package
    }
    Get-ChildItem '*.vsix' | Sort-Object LastWriteTime | Select-Object -Last 1 |
        ForEach-Object { Write-Host "Created $($_.Name) ($([math]::Round($_.Length / 1MB, 2)) MB)" }
}

try {
    Assert-Dependencies # every task runs node/npx; guard all of them up front
    switch ($Task) {
        'Test' { Invoke-Tests }
        'Coverage' { Invoke-Coverage }
        'Build' { Invoke-Build }
        'Package' { Assert-VersionConsistency; Invoke-Package }
        'All' {
            Assert-VersionConsistency
            Invoke-Coverage
            Invoke-Package
        }
    }
    Write-Host 'Done.' -ForegroundColor Green
} finally {
    Pop-Location
}
