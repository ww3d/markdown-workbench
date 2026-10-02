# Toolchain bootstrap (Windows PowerShell 5.1 and PowerShell 7): the pinned Node and pnpm, repo-local.
#
# The pins are read, never repeated here: Node from package.json devEngines.runtime (an exact version),
# pnpm from package.json packageManager. A Node or pnpm already on the PATH is used only when its
# version equals the pin; any other one is never used - the pinned version is fetched into .tools/
# instead, and only this process's PATH learns about it (no machine-wide change). Modeled on
# ww3d/atlas eng/common/tools.ps1 (.dotnet next to the repo root).
#
# Dot-sourced by build.ps1; the functions are importable on their own (tests/eng/bootstrap.test.ts).
#   MARKDOWN_WORKBENCH_NODE_DIST_URL  replaces https://nodejs.org/dist (a mirror, or the tests' server)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ToolsDir = Join-Path $RepoRoot '.tools'

function Get-Manifest {
    Get-Content -Raw -Path (Join-Path $RepoRoot 'package.json') | ConvertFrom-Json
}

function Get-NodePin {
    $manifest = Get-Manifest
    $runtime = $null
    if ($manifest.PSObject.Properties['devEngines'] -and $manifest.devEngines.PSObject.Properties['runtime']) {
        $runtime = $manifest.devEngines.runtime
    }
    if (-not $runtime -or $runtime.name -ne 'node' -or $runtime.version -notmatch '^\d+\.\d+\.\d+$') {
        throw "package.json devEngines.runtime must name node with an exact version (e.g. '26.10.0') - the pin the build fetches."
    }
    $runtime.version
}

function Get-PnpmPin {
    $pin = (Get-Manifest).packageManager
    # 'pnpm@12.6.0', optionally with a hash suffix ('pnpm@12.6.0+sha512.<hash>').
    if ($pin -notmatch '^pnpm@(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)(?:\+.*)?$') {
        throw "package.json packageManager '$pin' is not 'pnpm@<version>' - the build cannot resolve pnpm."
    }
    $Matches[1]
}

function Test-IsWindows {
    [Environment]::OSVersion.Platform -eq 'Win32NT'
}

function Get-ToolVersion {
    # The version a command on the PATH reports, or $null when there is none; 'v' prefix dropped.
    param([string] $Command)
    # Applications only: on Windows an npm shim has a .ps1 twin that Windows PowerShell 5.1 runs without output.
    $found = @(Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue)
    if (Test-IsWindows) {
        $found = @($found | Where-Object { $_.Path -match '\.(exe|cmd|bat)$' })
    }
    if ($found.Count -eq 0) {
        return $null
    }
    $out = & $found[0].Path --version 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) {
        return $null
    }
    ("$out").Trim().TrimStart('v')
}

function Invoke-Retry {
    param([scriptblock] $Action, [int] $Attempts = 3)
    for ($i = 1; ; $i++) {
        try {
            return & $Action
        }
        catch {
            if ($i -ge $Attempts) { throw }
            Write-Host "  $($_.Exception.Message) - retrying ($i of $Attempts)." -ForegroundColor Yellow
            Start-Sleep -Seconds ([math]::Pow(2, $i))
        }
    }
}

function Get-Platform {
    # nodejs.org's platform name of this machine, e.g. 'win-x64' or 'linux-arm64'.
    if (Test-IsWindows) {
        $machine = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        $arch = switch ($machine) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } default { $null } }
        if (-not $arch) { throw "Unsupported Windows architecture '$machine' - Node publishes win-x64 and win-arm64." }
        return "win-$arch"
    }
    $uname = (& uname -sm).Trim()
    $os = if ($uname -like 'Darwin*') { 'darwin' } else { 'linux' }
    $arch = switch -Wildcard ($uname) { '*x86_64' { 'x64' } '*arm64' { 'arm64' } '*aarch64' { 'arm64' } default { $null } }
    if (-not $arch) { throw "Unsupported platform '$uname' - Node publishes x64 and arm64." }
    "$os-$arch"
}

function Get-NodeArchive {
    # The official nodejs.org archive name: zip on Windows, tar.gz elsewhere (gzip is on every machine; xz is not).
    param([string] $Version)
    $ext = if (Test-IsWindows) { 'zip' } else { 'tar.gz' }
    "node-v$Version-$(Get-Platform).$ext"
}

function Install-Node {
    # Downloads the pinned Node from nodejs.org, checks the archive against the release's
    # SHASUMS256.txt (a mismatch aborts, nothing is extracted) and unpacks it to $Dir.
    param([string] $Version, [string] $Dir)
    $dist = if ($env:MARKDOWN_WORKBENCH_NODE_DIST_URL) { $env:MARKDOWN_WORKBENCH_NODE_DIST_URL.TrimEnd('/') } else { 'https://nodejs.org/dist' }
    $archive = Get-NodeArchive $Version
    $work = Join-Path $ToolsDir "node\.download-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    try {
        $ProgressPreference = 'SilentlyContinue' # the progress bar makes Invoke-WebRequest several times slower
        Write-Host "  Fetching Node $Version ($archive) from $dist."
        $sums = Invoke-Retry { (Invoke-WebRequest "$dist/v$Version/SHASUMS256.txt" -UseBasicParsing).Content }
        if ($sums -is [byte[]]) { $sums = [Text.Encoding]::UTF8.GetString($sums) } # no text content type: raw bytes
        $line = ($sums -split "`n") | Where-Object { $_ -match "^[0-9a-f]{64}\s+\*?$([regex]::Escape($archive))\s*$" } | Select-Object -First 1
        if (-not $line) { throw "SHASUMS256.txt of Node $Version does not list $archive." }
        $expected = ($line -split '\s+')[0]
        $file = Join-Path $work $archive
        Invoke-Retry { Invoke-WebRequest "$dist/v$Version/$archive" -UseBasicParsing -OutFile $file }
        $actual = Get-Sha256 $file
        if ($actual -ne $expected) {
            throw "Checksum mismatch for ${archive}: SHASUMS256.txt says $expected, the download is $actual. Nothing was installed."
        }
        $unpacked = Join-Path $work 'unpacked'
        New-Item -ItemType Directory -Force -Path $unpacked | Out-Null
        if ($archive.EndsWith('.zip')) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($file, $unpacked)
        }
        else {
            & tar -xzf $file -C $unpacked
            if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE." }
        }
        $inner = Get-ChildItem -Path $unpacked -Directory | Select-Object -First 1
        if (Test-Path -LiteralPath $Dir) { Remove-Item -LiteralPath $Dir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dir) | Out-Null
        Move-Item -LiteralPath $inner.FullName -Destination $Dir
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-Sha256 {
    # .NET instead of Get-FileHash: it needs no module, so it also works where module autoloading does not.
    param([string] $Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try {
        ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) -join ""
    }
    finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

function Get-NodeBinDir {
    # Windows keeps node.exe in the archive root, the Unix archives in bin/.
    param([string] $Dir)
    if (Test-IsWindows) { $Dir } else { Join-Path $Dir 'bin' }
}

function Add-ToPath {
    param([string[]] $Dirs)
    $env:PATH = (@($Dirs) + $env:PATH) -join [IO.Path]::PathSeparator
}

function Initialize-Node {
    $pin = Get-NodePin
    $found = Get-ToolVersion 'node'
    if ($found -eq $pin) {
        Write-Host "Node ${pin}: using the one on the PATH."
        return
    }
    # The platform is part of the folder name: one checkout may be built from Windows and from WSL alike.
    $name = "$pin-$(Get-Platform)"
    $dir = Join-Path (Join-Path $ToolsDir 'node') $name
    $bin = Get-NodeBinDir $dir
    $nodeExe = Join-Path $bin $(if (Test-IsWindows) { 'node.exe' } else { 'node' })
    if (-not (Test-Path -LiteralPath $nodeExe)) {
        $why = if ($found) { "the one on the PATH is $found" } else { 'none on the PATH' }
        Write-Host "Node $pin ($why) - fetching it into .tools/node/$name (this repo only)..." -ForegroundColor Yellow
        Install-Node $pin $dir
    }
    Add-ToPath $bin
    $now = Get-ToolVersion 'node'
    if ($now -ne $pin) {
        throw "Node $pin is still not what runs after the install (found: '$now')."
    }
    Write-Host "Node $pin ready (.tools/node/$name)."
}

function Initialize-Pnpm {
    $pin = Get-PnpmPin
    $found = Get-ToolVersion 'pnpm'
    if ($found -eq $pin) {
        Write-Host "pnpm ${pin}: using the one on the PATH."
        return
    }
    # pnpm 12 is a native binary that npm picks per platform, so the platform is part of the folder name too.
    $name = "$pin-$(Get-Platform)"
    $dir = Join-Path (Join-Path $ToolsDir 'pnpm') $name
    # A local npm install links the package's bin into <prefix>/node_modules/.bin.
    Add-ToPath (Join-Path (Join-Path $dir 'node_modules') '.bin')
    if ((Get-ToolVersion 'pnpm') -ne $pin) {
        $why = if ($found) { "the one on the PATH is $found" } else { 'none on the PATH' }
        Write-Host "pnpm $pin ($why) - fetching it with npm into .tools/pnpm/$name (this repo only)..." -ForegroundColor Yellow
        # npm ships with Node (Corepack no longer does since Node 25) and checks the registry's integrity hash.
        & npm install --prefix $dir "pnpm@$pin" --no-audit --no-fund --loglevel=error
        if ($LASTEXITCODE -ne 0) { throw "npm install pnpm@$pin failed with exit code $LASTEXITCODE." }
    }
    $now = Get-ToolVersion 'pnpm'
    if ($now -ne $pin) {
        throw "pnpm $pin is still not what runs after the install (found: '$now')."
    }
    Write-Host "pnpm $pin ready (.tools/pnpm/$name)."
}

function Initialize-Toolchain {
    Initialize-Node
    Initialize-Pnpm
}
