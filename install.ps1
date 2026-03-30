# Workspace Configuration - Auto Install
# Right-click > Run with PowerShell

$ErrorActionPreference = "Stop"

# Auto elevate if not admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`""
    exit
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$certFile = Join-Path $scriptDir "certificate.pfx"
$msixFile = Get-ChildItem -Path $scriptDir -Filter "*.msix" | Select-Object -First 1
$certPassword = "odoo123"
$certSubject = "CN=Nam, O=Nam, C=VN"

Write-Host ""
Write-Host "=== Workspace Configuration Installer ===" -ForegroundColor Cyan
Write-Host ""

# 1. Remove old certificate (all stores)
Write-Host "[1/3] Removing old certificates..." -ForegroundColor Yellow
$removed = 0
foreach ($store in @("TrustedPeople", "My", "Root", "CA")) {
    $certs = Get-ChildItem "Cert:\LocalMachine\$store" -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq $certSubject }
    foreach ($cert in $certs) {
        Remove-Item $cert.PSPath -Force
        $removed++
    }
    $certs = Get-ChildItem "Cert:\CurrentUser\$store" -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq $certSubject }
    foreach ($cert in $certs) {
        Remove-Item $cert.PSPath -Force
        $removed++
    }
}
if ($removed -gt 0) {
    Write-Host "      Removed $removed old certificate(s)" -ForegroundColor Green
} else {
    Write-Host "      No old certificates found" -ForegroundColor Gray
}

# 2. Install certificate to LocalMachine\TrustedPeople
Write-Host "[2/3] Installing certificate..." -ForegroundColor Yellow
if (Test-Path $certFile) {
    $pwd = ConvertTo-SecureString -String $certPassword -Force -AsPlainText
    Import-PfxCertificate -FilePath $certFile -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" -Password $pwd | Out-Null
    Write-Host "      Certificate installed to Local Machine > Trusted People" -ForegroundColor Green
} else {
    Write-Host "      certificate.pfx not found!" -ForegroundColor Red
    Write-Host ""
    pause
    exit 1
}

# 3. Install MSIX app
Write-Host "[3/3] Installing application..." -ForegroundColor Yellow
if ($msixFile) {
    Add-AppxPackage -Path $msixFile.FullName
    Write-Host "      $($msixFile.Name) installed successfully!" -ForegroundColor Green
} else {
    Write-Host "      No .msix file found in $scriptDir" -ForegroundColor Red
    Write-Host ""
    pause
    exit 1
}

Write-Host ""
Write-Host "Done! Launch 'Workspace Configuration' from the Start Menu." -ForegroundColor Cyan
Write-Host ""
pause
