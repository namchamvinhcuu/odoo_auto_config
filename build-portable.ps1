# Build portable single .exe using Enigma Virtual Box
# Usage: powershell -ExecutionPolicy Bypass -File build-portable.ps1

param(
    [string]$ReleaseDir = "build\windows\x64\runner\Release",
    [string]$OutputName = "WorkspaceConfiguration"
)

$ErrorActionPreference = "Stop"

$ExeName = "WorkspaceConfiguration.exe"
$InputExe = "$ReleaseDir\$ExeName"
$OutputExe = "build\$OutputName.exe"
$EvbProject = "build\$OutputName.evb"
$EvbDir = "build\evb"
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

# Generate .evb project file
Write-Host "[2/3] Generating .evb project..." -ForegroundColor Yellow

function Get-EvbFileNode {
    param([string]$FilePath, [string]$Name)
    return @"
              <File>
                <Type>2</Type>
                <Name>$Name</Name>
                <File>$FilePath</File>
                <ActiveX>False</ActiveX>
                <ActiveXInstall>False</ActiveXInstall>
                <Action>0</Action>
                <OverwriteDateTime>False</OverwriteDateTime>
                <OverwriteAttributes>False</OverwriteAttributes>
                <PassCommandLine>False</PassCommandLine>
                <HideFromDialogs>0</HideFromDialogs>
              </File>
"@
}

function Get-EvbDirNode {
    param([string]$DirPath, [string]$Name)

    $innerXml = ""
    foreach ($item in Get-ChildItem -Path $DirPath) {
        if ($item.PSIsContainer) {
            $innerXml += Get-EvbDirNode -DirPath $item.FullName -Name $item.Name
        } else {
            $innerXml += Get-EvbFileNode -FilePath $item.FullName -Name $item.Name
        }
    }

    return @"
              <File>
                <Type>3</Type>
                <Name>$Name</Name>
                <Action>0</Action>
                <OverwriteDateTime>False</OverwriteDateTime>
                <OverwriteAttributes>False</OverwriteAttributes>
                <HideFromDialogs>0</HideFromDialogs>
                <Files>
$innerXml
                </Files>
              </File>
"@
}

# Build file nodes for everything in Release folder (except the main exe)
$releasePath = (Resolve-Path $ReleaseDir).Path
$filesXml = ""
foreach ($item in Get-ChildItem -Path $releasePath) {
    # Skip the main exe (it's the InputFile)
    if (-not $item.PSIsContainer -and $item.Name -eq $ExeName) { continue }
    # Skip MSIX-related files
    if ($item.Name -match '\.(msix|pfx)$' -or $item.Name -match '^install\.(ps1|bat)$') { continue }

    if ($item.PSIsContainer) {
        $filesXml += Get-EvbDirNode -DirPath $item.FullName -Name $item.Name
    } else {
        $filesXml += Get-EvbFileNode -FilePath $item.FullName -Name $item.Name
    }
}

$inputExeFull = (Resolve-Path $InputExe).Path
$outputExeFull = Join-Path $PWD $OutputExe

$evbXml = @"
<?xml version="1.0" encoding="windows-1252"?>
<>
  <InputFile>$inputExeFull</InputFile>
  <OutputFile>$outputExeFull</OutputFile>
  <Files>
    <Enabled>True</Enabled>
    <DeleteExtractedOnExit>True</DeleteExtractedOnExit>
    <CompressFiles>True</CompressFiles>
    <Files>
      <File>
        <Type>3</Type>
        <Name>%DEFAULT FOLDER%</Name>
        <Action>0</Action>
        <OverwriteDateTime>False</OverwriteDateTime>
        <OverwriteAttributes>False</OverwriteAttributes>
        <HideFromDialogs>0</HideFromDialogs>
        <Files>
$filesXml
        </Files>
      </File>
    </Files>
  </Files>
  <Registries>
    <Enabled>False</Enabled>
    <Registries>
      <Registry>
        <Type>1</Type>
        <Virtual>True</Virtual>
        <Name>Classes</Name>
        <ValueType>0</ValueType>
        <Value/>
        <Registries/>
      </Registry>
      <Registry>
        <Type>1</Type>
        <Virtual>True</Virtual>
        <Name>User</Name>
        <ValueType>0</ValueType>
        <Value/>
        <Registries/>
      </Registry>
      <Registry>
        <Type>1</Type>
        <Virtual>True</Virtual>
        <Name>Machine</Name>
        <ValueType>0</ValueType>
        <Value/>
        <Registries/>
      </Registry>
      <Registry>
        <Type>1</Type>
        <Virtual>True</Virtual>
        <Name>Users</Name>
        <ValueType>0</ValueType>
        <Value/>
        <Registries/>
      </Registry>
      <Registry>
        <Type>1</Type>
        <Virtual>True</Virtual>
        <Name>Config</Name>
        <ValueType>0</ValueType>
        <Value/>
        <Registries/>
      </Registry>
    </Registries>
  </Registries>
  <Packaging>
    <Enabled>False</Enabled>
  </Packaging>
  <Options>
    <ShareVirtualSystem>False</ShareVirtualSystem>
    <MapExecutableWithTemporaryFile>True</MapExecutableWithTemporaryFile>
    <AllowRunningOfVirtualExeFiles>True</AllowRunningOfVirtualExeFiles>
  </Options>
</>
"@

Set-Content -Path $EvbProject -Value $evbXml -Encoding UTF8
Write-Host "  Generated: $EvbProject" -ForegroundColor Green

# Run EVB to create single .exe
Write-Host "[3/3] Packing into single .exe..." -ForegroundColor Yellow
& $EvbConsole $EvbProject
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: EVB packing failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

# Verify output size (should be >10MB for a Flutter app)
if (Test-Path $OutputExe) {
    $size = (Get-Item $OutputExe).Length / 1MB
    if ($size -lt 10) {
        Write-Host "WARNING: Output is only $([math]::Round($size, 1)) MB — EVB may not have embedded files correctly" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "=== Portable Build Complete ===" -ForegroundColor Green
    Write-Host "  Output: $OutputExe" -ForegroundColor White
    Write-Host "  Size:   $([math]::Round($size, 1)) MB" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "ERROR: Output file not found" -ForegroundColor Red
    exit 1
}
