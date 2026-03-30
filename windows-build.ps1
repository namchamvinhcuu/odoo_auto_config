# Build script for Windows MSIX installer
# Usage: Right-click > Run with PowerShell
#   or:  powershell -ExecutionPolicy Bypass -File windows-build.ps1
#
# MSIX version auto-increments build number on each run.
# Example: 1.1.0.0 -> 1.1.0.1 -> 1.1.0.2 ...
# To bump major/minor/patch, edit msix_version in pubspec.yaml manually.

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PubspecPath = "$ProjectDir\pubspec.yaml"
$OutputDir = "$ProjectDir\build\windows\x64\runner\Release"
$OutputName = "WorkspaceConfiguration"

Write-Host ""
Write-Host "=== Workspace Configuration - Windows Build ===" -ForegroundColor Cyan
Write-Host ""

# Step 0: Auto-increment msix_version build number
$pubspec = Get-Content $PubspecPath -Raw
if ($pubspec -match 'msix_version:\s*(\d+)\.(\d+)\.(\d+)\.(\d+)') {
    $major = $Matches[1]
    $minor = $Matches[2]
    $patch = $Matches[3]
    $build = [int]$Matches[4] + 1
    $oldVersion = "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])"
    $newVersion = "$major.$minor.$patch.$build"
    $pubspec = $pubspec -replace "msix_version:\s*$oldVersion", "msix_version: $newVersion"
    Set-Content $PubspecPath $pubspec -NoNewline
    Write-Host "  Version: $oldVersion -> $newVersion" -ForegroundColor Magenta
} else {
    Write-Host "  WARNING: msix_version not found in pubspec.yaml" -ForegroundColor Red
}
Write-Host ""

# Step 1: Clean
Write-Host "[1/4] Cleaning previous build..." -ForegroundColor Yellow
Set-Location $ProjectDir
fvm flutter clean
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: flutter clean failed" -ForegroundColor Red; exit 1 }

# Step 2: Get dependencies
Write-Host ""
Write-Host "[2/4] Getting dependencies..." -ForegroundColor Yellow
fvm flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: flutter pub get failed" -ForegroundColor Red; exit 1 }

# Step 3: Build Windows release
Write-Host ""
Write-Host "[3/4] Building Windows release..." -ForegroundColor Yellow
fvm flutter build windows --release
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: flutter build failed" -ForegroundColor Red; exit 1 }

# Step 4: Create MSIX
Write-Host ""
Write-Host "[4/4] Creating MSIX package..." -ForegroundColor Yellow
fvm dart run msix:create --build-windows false --install-certificate false --output-name $OutputName
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: msix:create failed" -ForegroundColor Red; exit 1 }

# Step 5: Copy certificate.pfx and install.ps1 to output dir
Write-Host ""
Write-Host "[5/5] Copying installer files..." -ForegroundColor Yellow
$certSource = "$ProjectDir\certificate.pfx"
$installSource = "$ProjectDir\install.ps1"
if (Test-Path $certSource) {
    Copy-Item $certSource "$OutputDir\certificate.pfx" -Force
    Write-Host "  Copied certificate.pfx" -ForegroundColor Green
}
if (Test-Path $installSource) {
    Copy-Item $installSource "$OutputDir\install.ps1" -Force
    Write-Host "  Copied install.ps1" -ForegroundColor Green
}
$batSource = "$ProjectDir\install.bat"
if (Test-Path $batSource) {
    Copy-Item $batSource "$OutputDir\install.bat" -Force
    Write-Host "  Copied install.bat" -ForegroundColor Green
}

# Done
$MsixPath = "$OutputDir\$OutputName.msix"
$ExePath = "$OutputDir\$OutputName.exe"

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "  Version: $newVersion" -ForegroundColor White

if (Test-Path $MsixPath) {
    $size = (Get-Item $MsixPath).Length / 1MB
    Write-Host "  MSIX:    $MsixPath" -ForegroundColor White
    Write-Host "  Size:    $([math]::Round($size, 1)) MB" -ForegroundColor White
}

if (Test-Path $ExePath) {
    Write-Host "  EXE:     $ExePath" -ForegroundColor White
}

Write-Host ""
Write-Host "  Output:  $OutputDir" -ForegroundColor White
Write-Host "  Install: Run install.ps1 in the output folder" -ForegroundColor Gray
Write-Host ""
