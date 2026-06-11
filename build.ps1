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
