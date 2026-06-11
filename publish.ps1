# Marketplace publish orchestrator for the markdown-workbench extension.
#
# Publishes the attested GitHub release artifact - never a local build - to
# the VS Code Marketplace, authenticating via Entra ID (az login +
# `vsce publish --azure-credential`; Marketplace PATs retire 12/2026, so
# there is no PAT path). Deliberately separate from build.ps1, which stays
# credential-free and deterministic for CI. Publishing is a manual decision
# per release; see CONTRIBUTING.md "Marketplace publishing".
#
# Usage: ./publish.ps1 [-Version <x.y.z>]
#        Default: version from package.json. The tag v<version> must already
#        exist as a GitHub release (merge to main first).
#
# Steps, each failing hard - no fallbacks:
#   1. Preflight: node >= 22, az present + logged in, gh authenticated,
#      publisher field set in package.json
#   2. Download vsix + SHA256SUMS.txt of release v<version> to a temp dir
#   3. Verify checksum against SHA256SUMS.txt AND the build-provenance
#      attestation (both mandatory; any mismatch aborts before publishing)
#   4. Skip cleanly (exit 0) if the gallery already has this version
#   5. vsce publish --packagePath <vsix> --azure-credential

[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

$repo = 'ww3d/markdown-workbench'
$tempDir = Join-Path ([IO.Path]::GetTempPath()) "markdown-workbench-publish-$([Guid]::NewGuid())"

try {
    # --- 1. Preflight -------------------------------------------------------
    Write-Host '==> Preflight' -ForegroundColor Cyan

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        throw "node not found. Install Node.js 22+ (winget install OpenJS.NodeJS.LTS) and retry."
    }
    $nodeVersion = (node --version).Trim()
    if ([int]$nodeVersion.TrimStart('v').Split('.')[0] -lt 22) {
        throw "node $nodeVersion is too old; 22+ is required. Update Node.js (winget install OpenJS.NodeJS.LTS) and retry."
    }

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI (az) not found. Install it (winget install Microsoft.AzureCLI) and retry."
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) not found. Install it (winget install GitHub.cli) and retry."
    }
    & gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI is not authenticated. Run 'gh auth status' to see why, 'gh auth login' to fix it, then retry."
    }

    $manifest = Get-Content -Raw 'package.json' | ConvertFrom-Json
    $publisherProperty = $manifest.PSObject.Properties['publisher']
    if (-not $publisherProperty -or [string]::IsNullOrWhiteSpace($publisherProperty.Value)) {
        throw "package.json has no 'publisher' field. Set it to the Marketplace publisher id and retry."
    }
    $publisher = $publisherProperty.Value

    & az account show --only-show-errors --output none 2> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI is not logged in. Run 'az login' with the account that owns the '$publisher' publisher and retry."
    }

    if (-not $Version) { $Version = $manifest.version }
    $extensionId = "$publisher.$($manifest.name)"
    $tag = "v$Version"

    # --- 2. Download the release assets -------------------------------------
    Write-Host "==> Download release assets for $tag" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $tempDir > $null
    & gh release download $tag --repo $repo --pattern '*.vsix' --pattern 'SHA256SUMS.txt' --dir $tempDir
    if ($LASTEXITCODE -ne 0) {
        throw "Could not download the assets of release $tag from $repo. If that release does not exist yet, merge the $Version version bump to main first (the release job tags and publishes it), then publish."
    }
    $vsix = @(Get-ChildItem -Path (Join-Path $tempDir '*.vsix'))
    if ($vsix.Count -ne 1) {
        throw "Expected exactly one vsix asset in release $tag, found $($vsix.Count)."
    }
    $vsix = $vsix[0]
    $sumsFile = Join-Path $tempDir 'SHA256SUMS.txt'
    if (-not (Test-Path $sumsFile)) {
        throw "Release $tag has no SHA256SUMS.txt asset; refusing to publish without the checksum chain."
    }

    # --- 3. Verify the integrity chain (both checks mandatory) --------------
    Write-Host '==> Verify checksum against SHA256SUMS.txt' -ForegroundColor Cyan
    # sha256sum format: "<hex> <space><space-or-*><filename>"
    $sumLine = Get-Content $sumsFile | Where-Object { $_ -match ('^([0-9a-fA-F]{64}) [ *]' + [regex]::Escape($vsix.Name) + '$') } | Select-Object -First 1
    if (-not $sumLine) {
        throw "SHA256SUMS.txt has no entry for $($vsix.Name); refusing to publish."
    }
    $expectedHash = ($sumLine -split '\s+')[0]
    $actualHash = (Get-FileHash -Algorithm SHA256 -Path $vsix.FullName).Hash
    if ($actualHash -ne $expectedHash) {
        throw "Checksum mismatch for $($vsix.Name): SHA256SUMS.txt says $expectedHash, the file hashes to $actualHash. Aborting before any publish attempt."
    }
    Write-Host "Checksum OK ($actualHash)."

    Write-Host '==> Verify build-provenance attestation' -ForegroundColor Cyan
    & gh attestation verify $vsix.FullName --repo $repo
    if ($LASTEXITCODE -ne 0) {
        throw "Attestation verification failed for $($vsix.Name). The artifact is not provably from this repo's CI - aborting before any publish attempt."
    }

    # --- 4. Idempotency: skip if the gallery already has this version -------
    Write-Host "==> Check the gallery for $extensionId $Version" -ForegroundColor Cyan
    $showOutput = (& npx @vscode/vsce show $extensionId --json 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not query the gallery for ${extensionId}: $showOutput"
    }
    if ($showOutput.Trim() -eq 'undefined') {
        # vsce show prints the literal string "undefined" (exit 0) when the
        # gallery has no such extension - the first-publish case.
        Write-Host "Extension $extensionId is not in the gallery yet - this will be its first publish."
    } else {
        $publishedVersions = @(($showOutput | ConvertFrom-Json).versions.version)
        if ($publishedVersions -contains $Version) {
            Write-Host "Version $Version of $extensionId is already in the Marketplace - nothing to do." -ForegroundColor Green
            exit 0
        }
        Write-Host "Gallery has $extensionId, but not version $Version yet."
    }

    # --- 5. Publish ----------------------------------------------------------
    Write-Host "==> Publish $($vsix.Name) via Entra (vsce --azure-credential)" -ForegroundColor Cyan
    & npx @vscode/vsce publish --packagePath $vsix.FullName --azure-credential
    if ($LASTEXITCODE -ne 0) {
        throw "vsce publish failed with exit code $LASTEXITCODE."
    }

    Write-Host "Published $extensionId $Version to the VS Code Marketplace." -ForegroundColor Green
    Write-Host "https://marketplace.visualstudio.com/items?itemName=$extensionId"
} finally {
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
}
