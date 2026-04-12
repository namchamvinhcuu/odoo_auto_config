# Build portable single .exe using Enigma Virtual Box
# Usage: powershell -ExecutionPolicy Bypass -File build-portable.ps1
#
# Prerequisites: Flutter Windows build must be completed first.
# This script downloads EVB if needed, generates .evb config, and packs into single .exe.

param(
    [string]$ReleaseDir = "build\windows\x64\runner\Release",
    [string]$OutputName = "WorkspaceConfiguration",
    [string]$EvbDir = "build\evb"
)

$ErrorActionPreference = "Stop"

$ExeName = "WorkspaceConfiguration.exe"
$InputExe = "$ReleaseDir\$ExeName"
$OutputExe = "build\$OutputName.exe"
$EvbProject = "build\$OutputName.evb"
$EvbConsole = "$EvbDir\enigmavbconsole.exe"

Write-Host ""
Write-Host "=== Building Portable .exe ===" -ForegroundColor Cyan
Write-Host ""

# Verify release build exists
if (-not (Test-Path $InputExe)) {
    Write-Host "ERROR: Release build not found at $InputExe" -ForegroundColor Red
    Write-Host "Run 'flutter build windows --release' first." -ForegroundColor Yellow
    exit 1
}

# Download Enigma Virtual Box if not present
if (-not (Test-Path $EvbConsole)) {
    Write-Host "[1/3] Downloading Enigma Virtual Box..." -ForegroundColor Yellow
    $EvbUrl = "https://enigmaprotector.com/assets/files/enigmavb.exe"
    $EvbInstaller = "$env:TEMP\enigmavb_installer.exe"

    Invoke-WebRequest -Uri $EvbUrl -OutFile $EvbInstaller -UseBasicParsing
    Write-Host "  Installing EVB silently..." -ForegroundColor Gray

    # Silent install to custom directory
    New-Item -ItemType Directory -Force -Path $EvbDir | Out-Null
    Start-Process -FilePath $EvbInstaller -ArgumentList "/VERYSILENT", "/DIR=$((Resolve-Path $EvbDir).Path)" -Wait -NoNewWindow
    Remove-Item $EvbInstaller -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $EvbConsole)) {
        Write-Host "ERROR: EVB installation failed" -ForegroundColor Red
        exit 1
    }
    Write-Host "  EVB installed to $EvbDir" -ForegroundColor Green
} else {
    Write-Host "[1/3] Enigma Virtual Box found" -ForegroundColor Green
}

# Generate .evb project file by scanning Release folder
Write-Host "[2/3] Generating .evb project..." -ForegroundColor Yellow

function Get-EvbFiles {
    param([string]$Dir, [string]$RelativePath = "")

    $xml = ""
    foreach ($item in Get-ChildItem -Path $Dir) {
        if ($item.PSIsContainer) {
            # Folder
            $subPath = if ($RelativePath) { "$RelativePath\$($item.Name)" } else { $item.Name }
            $innerXml = Get-EvbFiles -Dir $item.FullName -RelativePath $subPath
            $xml += @"
      <File>
        <Type>2</Type>
        <Name>$($item.Name)</Name>
        <Files>
$innerXml
        </Files>
      </File>
"@
        } else {
            # Skip the main exe (it's the InputFile, not embedded)
            if ($RelativePath -eq "" -and $item.Name -eq $ExeName) { continue }
            $xml += @"
      <File>
        <Type>3</Type>
        <Name>$($item.Name)</Name>
        <SourcePath>$($item.FullName)</SourcePath>
      </File>
"@
        }
    }
    return $xml
}

$filesXml = Get-EvbFiles -Dir (Resolve-Path $ReleaseDir).Path
$inputExeFull = (Resolve-Path $InputExe).Path
$outputExeFull = "$PWD\$OutputExe"

$evbXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<EvbData>
  <InputFile>$inputExeFull</InputFile>
  <OutputFile>$outputExeFull</OutputFile>
  <CompressFiles>true</CompressFiles>
  <DeleteExtractedOnExit>true</DeleteExtractedOnExit>
  <Files>
$filesXml
  </Files>
</EvbData>
"@

Set-Content -Path $EvbProject -Value $evbXml -Encoding UTF8
Write-Host "  Generated: $EvbProject" -ForegroundColor Green

# Run EVB to create single .exe
Write-Host "[3/3] Packing into single .exe..." -ForegroundColor Yellow
& $EvbConsole $EvbProject
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: EVB packing failed" -ForegroundColor Red
    exit 1
}

# Report
if (Test-Path $OutputExe) {
    $size = (Get-Item $OutputExe).Length / 1MB
    Write-Host ""
    Write-Host "=== Portable Build Complete ===" -ForegroundColor Green
    Write-Host "  Output: $OutputExe" -ForegroundColor White
    Write-Host "  Size:   $([math]::Round($size, 1)) MB" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "ERROR: Output file not found" -ForegroundColor Red
    exit 1
}
