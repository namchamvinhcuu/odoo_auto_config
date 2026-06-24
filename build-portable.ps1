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
    exit 1
}

# Download Enigma Virtual Box if not present (retry + integrity check — the
# upstream download is occasionally corrupt/partial, which makes the silent
# installer fail with "file or directory is corrupted and unreadable").
if (-not (Test-Path $EvbConsole)) {
    Write-Host "[1/3] Downloading Enigma Virtual Box..." -ForegroundColor Yellow
    $EvbUrl = "https://enigmaprotector.com/assets/files/enigmavb.exe"
    $EvbInstaller = "$env:TEMP\enigmavb_installer.exe"
    $MinInstallerBytes = 1MB   # a real EVB installer is several MB; smaller = failed/HTML download
    $MaxAttempts = 3
    # Optional pinned SHA256 of the installer. The URL serves the latest EVB
    # build (a moving target) so this is empty by default; the actual hash is
    # logged each run — paste a known-good value here to enforce exact match.
    $EvbSha256 = ""

    New-Item -ItemType Directory -Force -Path $EvbDir | Out-Null
    $installed = $false

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Write-Host "  Attempt $attempt/$MaxAttempts : downloading installer..." -ForegroundColor Gray
            Remove-Item $EvbInstaller -Force -ErrorAction SilentlyContinue
            Invoke-WebRequest -Uri $EvbUrl -OutFile $EvbInstaller -UseBasicParsing -TimeoutSec 120

            # Integrity check: exists, large enough, valid PE (MZ header)
            if (-not (Test-Path $EvbInstaller)) { throw "Installer was not downloaded" }
            $size = (Get-Item $EvbInstaller).Length
            if ($size -lt $MinInstallerBytes) {
                throw "Downloaded installer too small ($size bytes) - likely partial/corrupt"
            }
            $fs = [System.IO.File]::OpenRead($EvbInstaller)
            $magic = New-Object byte[] 2
            $null = $fs.Read($magic, 0, 2)
            $fs.Close()
            if ($magic[0] -ne 0x4D -or $magic[1] -ne 0x5A) {   # 'MZ'
                throw "Downloaded file is not a valid Windows executable (bad MZ header)"
            }

            $sha = (Get-FileHash $EvbInstaller -Algorithm SHA256).Hash
            Write-Host "  Downloaded $([math]::Round($size/1MB,1)) MB, SHA256=$sha" -ForegroundColor Gray
            if ($EvbSha256 -and ($sha -ne $EvbSha256)) {
                throw "SHA256 mismatch (expected $EvbSha256, got $sha)"
            }

            Write-Host "  Installing EVB silently..." -ForegroundColor Gray
            Start-Process -FilePath $EvbInstaller -ArgumentList "/VERYSILENT", "/DIR=$((Resolve-Path $EvbDir).Path)" -Wait -NoNewWindow

            if (Test-Path $EvbConsole) { $installed = $true; break }
            throw "EVB console not found after install"
        } catch {
            Write-Host "  Attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor Yellow
            if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds (5 * $attempt) }
        }
    }

    Remove-Item $EvbInstaller -Force -ErrorAction SilentlyContinue
    if (-not $installed) {
        Write-Host "ERROR: EVB installation failed after $MaxAttempts attempts" -ForegroundColor Red
        exit 1
    }
    Write-Host "  EVB installed to $EvbDir" -ForegroundColor Green
} else {
    Write-Host "[1/3] Enigma Virtual Box found" -ForegroundColor Green
}

# Generate .evb project file
Write-Host "[2/3] Generating .evb project..." -ForegroundColor Yellow

function Get-EvbFileXml([string]$FilePath, [string]$Name) {
    $lines = @()
    $lines += '              <File>'
    $lines += '                <Type>2</Type>'
    $lines += "                <Name>$Name</Name>"
    $lines += "                <File>$FilePath</File>"
    $lines += '                <ActiveX>False</ActiveX>'
    $lines += '                <ActiveXInstall>False</ActiveXInstall>'
    $lines += '                <Action>0</Action>'
    $lines += '                <OverwriteDateTime>False</OverwriteDateTime>'
    $lines += '                <OverwriteAttributes>False</OverwriteAttributes>'
    $lines += '                <PassCommandLine>False</PassCommandLine>'
    $lines += '                <HideFromDialogs>0</HideFromDialogs>'
    $lines += '              </File>'
    return $lines -join "`r`n"
}

function Get-EvbDirXml([string]$DirPath, [string]$Name) {
    $inner = @()
    foreach ($item in Get-ChildItem -Path $DirPath) {
        if ($item.PSIsContainer) {
            $inner += Get-EvbDirXml -DirPath $item.FullName -Name $item.Name
        } else {
            $inner += Get-EvbFileXml -FilePath $item.FullName -Name $item.Name
        }
    }
    $lines = @()
    $lines += '              <File>'
    $lines += '                <Type>3</Type>'
    $lines += "                <Name>$Name</Name>"
    $lines += '                <Action>0</Action>'
    $lines += '                <OverwriteDateTime>False</OverwriteDateTime>'
    $lines += '                <OverwriteAttributes>False</OverwriteAttributes>'
    $lines += '                <HideFromDialogs>0</HideFromDialogs>'
    $lines += '                <Files>'
    $lines += ($inner -join "`r`n")
    $lines += '                </Files>'
    $lines += '              </File>'
    return $lines -join "`r`n"
}

$releasePath = (Resolve-Path $ReleaseDir).Path
$fileNodes = @()
foreach ($item in Get-ChildItem -Path $releasePath) {
    if (-not $item.PSIsContainer -and $item.Name -eq $ExeName) { continue }
    if ($item.Name -match '\.(msix|pfx)$' -or $item.Name -match '^install\.(ps1|bat)$') { continue }
    if ($item.PSIsContainer) {
        $fileNodes += Get-EvbDirXml -DirPath $item.FullName -Name $item.Name
    } else {
        $fileNodes += Get-EvbFileXml -FilePath $item.FullName -Name $item.Name
    }
}

$inputExeFull = (Resolve-Path $InputExe).Path
$outputExeFull = Join-Path $PWD $OutputExe
$allFiles = $fileNodes -join "`r`n"

# Build EVB XML using array join (avoids PowerShell here-string parse issues with <>)
$xml = @()
$xml += '<?xml version="1.0" encoding="windows-1252"?>'
$xml += '<>'
$xml += "  <InputFile>$inputExeFull</InputFile>"
$xml += "  <OutputFile>$outputExeFull</OutputFile>"
$xml += '  <Files>'
$xml += '    <Enabled>True</Enabled>'
$xml += '    <DeleteExtractedOnExit>True</DeleteExtractedOnExit>'
$xml += '    <CompressFiles>True</CompressFiles>'
$xml += '    <Files>'
$xml += '      <File>'
$xml += '        <Type>3</Type>'
$xml += '        <Name>%DEFAULT FOLDER%</Name>'
$xml += '        <Action>0</Action>'
$xml += '        <OverwriteDateTime>False</OverwriteDateTime>'
$xml += '        <OverwriteAttributes>False</OverwriteAttributes>'
$xml += '        <HideFromDialogs>0</HideFromDialogs>'
$xml += '        <Files>'
$xml += $allFiles
$xml += '        </Files>'
$xml += '      </File>'
$xml += '    </Files>'
$xml += '  </Files>'
$xml += '  <Registries>'
$xml += '    <Enabled>False</Enabled>'
$xml += '    <Registries>'
$xml += '      <Registry><Type>1</Type><Virtual>True</Virtual><Name>Classes</Name><ValueType>0</ValueType><Value/><Registries/></Registry>'
$xml += '      <Registry><Type>1</Type><Virtual>True</Virtual><Name>User</Name><ValueType>0</ValueType><Value/><Registries/></Registry>'
$xml += '      <Registry><Type>1</Type><Virtual>True</Virtual><Name>Machine</Name><ValueType>0</ValueType><Value/><Registries/></Registry>'
$xml += '      <Registry><Type>1</Type><Virtual>True</Virtual><Name>Users</Name><ValueType>0</ValueType><Value/><Registries/></Registry>'
$xml += '      <Registry><Type>1</Type><Virtual>True</Virtual><Name>Config</Name><ValueType>0</ValueType><Value/><Registries/></Registry>'
$xml += '    </Registries>'
$xml += '  </Registries>'
$xml += '  <Packaging>'
$xml += '    <Enabled>False</Enabled>'
$xml += '  </Packaging>'
$xml += '  <Options>'
$xml += '    <ShareVirtualSystem>False</ShareVirtualSystem>'
$xml += '    <MapExecutableWithTemporaryFile>True</MapExecutableWithTemporaryFile>'
$xml += '    <AllowRunningOfVirtualExeFiles>True</AllowRunningOfVirtualExeFiles>'
$xml += '  </Options>'
$xml += '</>'

$xmlContent = $xml -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PWD $EvbProject), $xmlContent, [System.Text.Encoding]::UTF8)
Write-Host "  Generated: $EvbProject" -ForegroundColor Green

# Run EVB
Write-Host "[3/3] Packing into single .exe..." -ForegroundColor Yellow
& $EvbConsole (Join-Path $PWD $EvbProject)
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: EVB packing failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

# Verify output
if (Test-Path $OutputExe) {
    $size = [math]::Round((Get-Item $OutputExe).Length / 1MB, 1)
    if ($size -lt 10) {
        Write-Host "WARNING: Output is only $size MB - EVB may not have embedded files" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "=== Portable Build Complete ===" -ForegroundColor Green
    Write-Host "  Output: $OutputExe" -ForegroundColor White
    Write-Host "  Size:   $size MB" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "ERROR: Output file not found" -ForegroundColor Red
    exit 1
}
