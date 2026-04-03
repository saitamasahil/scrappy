param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Show-Usage {
    Write-Host "Usage: powershell -ExecutionPolicy Bypass -File build.ps1 [option]"
    Write-Host "Options:"
    Write-Host "  1, --full     Build ONLY the full package"
    Write-Host "  2, --update   Build ONLY the update package"
    Write-Host "  (none)        Build BOTH packages (default)"
    Write-Host "  -h, --help    Show this help message"
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$DestinationDir
    )

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        return
    }

    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    Get-ChildItem -LiteralPath $SourceDir -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $DestinationDir -Recurse -Force
    }
}

function Format-FileSize {
    param([Parameter(Mandatory = $true)][long]$Bytes)
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

# Get project root directory
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Build options
$buildFull = $true
$buildUpdate = $true

$option = ""
if ($Arguments -and $Arguments.Count -gt 0) {
    $option = $Arguments[0]
}

switch ($option) {
    "1" { $buildUpdate = $false }
    "--full" { $buildUpdate = $false }
    "2" { $buildFull = $false }
    "--update" { $buildFull = $false }
    "-h" {
        Show-Usage
        exit 0
    }
    "--help" {
        Show-Usage
        exit 0
    }
    "" { }
    default {
        Write-Host "Error: Unknown option '$option'" -ForegroundColor Red
        Show-Usage
        exit 1
    }
}

# Create build directory if it doesn't exist
$BuildDir = Join-Path $ProjectRoot "build"
if (-not (Test-Path -LiteralPath $BuildDir -PathType Container)) {
    Write-Host "Creating build directory: $BuildDir"
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
}

# Read version from globals.lua
$globalsPath = Join-Path $ProjectRoot "globals.lua"
if (-not (Test-Path -LiteralPath $globalsPath -PathType Leaf)) {
    throw "Error: globals.lua not found at $globalsPath"
}

$globalsContent = Get-Content -LiteralPath $globalsPath -Raw
$majorMatch = [regex]::Match($globalsContent, "(?m)^\s*major\s*=\s*(\d+)")
$minorMatch = [regex]::Match($globalsContent, "(?m)^\s*minor\s*=\s*(\d+)")
$patchMatch = [regex]::Match($globalsContent, "(?m)^\s*patch\s*=\s*(\d+)")

if (-not $majorMatch.Success -or -not $minorMatch.Success -or -not $patchMatch.Success) {
    throw "Error: Could not determine version from globals.lua"
}

$major = $majorMatch.Groups[1].Value
$minor = $minorMatch.Groups[1].Value
$patch = $patchMatch.Groups[1].Value
$tag = "v$major.$minor.$patch"
Write-Host "Building version: $tag"

# Set up paths
$fullPackage = Join-Path $BuildDir "Scrappy_${tag}.muxapp"
$updatePackage = Join-Path $BuildDir "Scrappy_${tag}_update.muxapp"
$workDir = Join-Path $BuildDir "pkg_${major}${minor}${patch}"
$workScrappyDir = Join-Path $workDir "Scrappy"
$workHiddenDir = Join-Path $workScrappyDir ".scrappy"

# Clean up old build
if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force }
if (Test-Path -LiteralPath $fullPackage) { Remove-Item -LiteralPath $fullPackage -Force }
if (Test-Path -LiteralPath $updatePackage) { Remove-Item -LiteralPath $updatePackage -Force }
New-Item -ItemType Directory -Force -Path $workHiddenDir | Out-Null

# Copy all necessary files (Base files for both packages)
Write-Host "Copying base files..."
Copy-Item -LiteralPath (Join-Path $ProjectRoot "mux_launch.sh") -Destination $workScrappyDir -Force

# Copy core directories
Copy-Item -LiteralPath (Join-Path $ProjectRoot "helpers") -Destination $workHiddenDir -Recurse -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot "lib") -Destination $workHiddenDir -Recurse -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot "scenes") -Destination $workHiddenDir -Recurse -Force
if (Test-Path -LiteralPath (Join-Path $ProjectRoot "scripts")) {
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "scripts") -Destination $workHiddenDir -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $ProjectRoot "templates") -Destination $workHiddenDir -Recurse -Force

# Copy configuration files
Copy-Item -LiteralPath (Join-Path $ProjectRoot "conf.lua") -Destination $workHiddenDir -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot "globals.lua") -Destination $workHiddenDir -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot "main.lua") -Destination $workHiddenDir -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot "config.ini.example") -Destination $workHiddenDir -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot "skyscraper_config.ini.example") -Destination $workHiddenDir -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot "theme.ini") -Destination $workHiddenDir -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot "theme_light.ini") -Destination $workHiddenDir -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot "theme_classic.ini") -Destination $workHiddenDir -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot "theme_light_classic.ini") -Destination $workHiddenDir -Force

# Copy assets and ensure the directory exists
$workAssetsDir = Join-Path $workHiddenDir "assets"
New-Item -ItemType Directory -Force -Path $workAssetsDir | Out-Null
$assetsDir = Join-Path $ProjectRoot "assets"
if (Test-Path -LiteralPath $assetsDir -PathType Container) {
    Write-Host "Copying assets..."
    Copy-DirectoryContents -SourceDir $assetsDir -DestinationDir $workAssetsDir
}

# Ensure glyph directory exists in the root of the app and copy scrappy.png
$workGlyphDir = Join-Path $workScrappyDir "glyph"
New-Item -ItemType Directory -Force -Path $workGlyphDir | Out-Null

$glyphSource = $null
$assetGlyphSource = Join-Path $ProjectRoot "assets/scrappy.png"
$glyphDirSource = Join-Path $ProjectRoot "glyph/scrappy.png"
if (Test-Path -LiteralPath $assetGlyphSource -PathType Leaf) {
    $glyphSource = $assetGlyphSource
} elseif (Test-Path -LiteralPath $glyphDirSource -PathType Leaf) {
    $glyphSource = $glyphDirSource
}

if ($glyphSource) {
    Write-Host "Copying scrappy.png to glyph directory..."
    Copy-Item -LiteralPath $glyphSource -Destination $workGlyphDir -Force
    foreach ($res in @("640x480", "720x480", "720x720", "1024x768")) {
        $resDir = Join-Path $workGlyphDir $res
        New-Item -ItemType Directory -Force -Path $resDir | Out-Null
        Copy-Item -LiteralPath $glyphSource -Destination (Join-Path $resDir "scrappy.png") -Force
    }
} else {
    Write-Host "Warning: scrappy.png not found in expected locations" -ForegroundColor Yellow
}

if ($buildUpdate) {
    Write-Host "Creating update package..."
    Compress-Archive -Path (Join-Path $workDir "Scrappy") -DestinationPath $updatePackage -CompressionLevel Optimal -Force
}

if ($buildFull) {
    Write-Host "Copying additional files for full package..."
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "bin") -Destination $workHiddenDir -Recurse -Force
    foreach ($optionalDir in @("data", "logs", "sample")) {
        $source = Join-Path $ProjectRoot $optionalDir
        if (Test-Path -LiteralPath $source -PathType Container) {
            Copy-Item -LiteralPath $source -Destination $workHiddenDir -Recurse -Force
        }
    }
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "static") -Destination $workHiddenDir -Recurse -Force

    # Copy any additional glyph files from assets/glyph if they exist
    $assetsGlyphDir = Join-Path $ProjectRoot "assets/glyph"
    if (Test-Path -LiteralPath $assetsGlyphDir -PathType Container) {
        Write-Host "Copying additional glyph files from assets..."
        Copy-DirectoryContents -SourceDir $assetsGlyphDir -DestinationDir $workGlyphDir
    }

    Write-Host "Creating full package..."
    Compress-Archive -Path (Join-Path $workDir "Scrappy") -DestinationPath $fullPackage -CompressionLevel Optimal -Force
}

# Clean up
if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force }

Write-Host ""
Write-Host "Build complete!"
if ($buildFull -and (Test-Path -LiteralPath $fullPackage -PathType Leaf)) {
    $item = Get-Item -LiteralPath $fullPackage
    Write-Host ("{0}`t{1}" -f (Format-FileSize -Bytes $item.Length), $item.FullName)
}
if ($buildUpdate -and (Test-Path -LiteralPath $updatePackage -PathType Leaf)) {
    $item = Get-Item -LiteralPath $updatePackage
    Write-Host ("{0}`t{1}" -f (Format-FileSize -Bytes $item.Length), $item.FullName)
}
