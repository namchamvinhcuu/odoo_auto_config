# scripts/setup-vault.ps1
#
# Tạo symlink .obsidian-vault tới Obsidian vault path do USER nhập.
# Script KHÔNG tự đoán path (mỗi dự án có vault riêng, auto-detect dễ link sai vault).
# Chạy 1 lần per máy mới, hoặc khi vault path thay đổi.
#
# Usage:
#   pwsh scripts/setup-vault.ps1                       # prompt user nhập path
#   pwsh scripts/setup-vault.ps1 -VaultPath "C:\..."   # explicit path (skip prompt)
#
# Yêu cầu Developer Mode hoặc Run as Administrator để tạo symlink trên Windows.
# Marker: vault PHẢI có file Index.md ở root để verify đúng vault.

param(
    [string]$VaultPath
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Symlink = Join-Path $ProjectRoot ".obsidian-vault"
$Marker = "Index.md"

function New-VaultSymlink {
    param([string]$Target, [string]$Reason)
    $Target = [System.Environment]::ExpandEnvironmentVariables($Target)
    if (-not (Test-Path (Join-Path $Target $Marker))) {
        Write-Host "✗ Path không hợp lệ (thiếu ${Marker}): $Target"
        return $false
    }
    New-Item -ItemType SymbolicLink -Path $Symlink -Target $Target -Force | Out-Null
    Write-Host "✓ Linked ($Reason): $Symlink → $Target"
    return $true
}

# 1) Symlink đã tồn tại + resolve OK → noop
if (Test-Path $Symlink) {
    $existing = Get-Item $Symlink -ErrorAction SilentlyContinue
    if ($existing.LinkType -eq 'SymbolicLink' -and (Test-Path (Join-Path $Symlink $Marker))) {
        Write-Host "✓ Symlink đã tồn tại: $Symlink → $($existing.Target)"
        exit 0
    }
    # Broken symlink → xóa
    if ($existing.LinkType -eq 'SymbolicLink') {
        Write-Host "⚠ Symlink broken (target không có $Marker), xóa: $Symlink"
        Remove-Item $Symlink -Force
    }
}

# 2) Path argument explicit → bỏ qua prompt
if ($VaultPath) {
    if (New-VaultSymlink -Target $VaultPath -Reason "manual") { exit 0 } else { exit 1 }
}

# 3) Prompt user
@"
Symlink .obsidian-vault chưa tồn tại cho dự án này.

Nhập path tới Obsidian vault dành cho DỰ ÁN NÀY (folder chứa $Marker).
Mỗi dự án có vault riêng — KHÔNG dùng path của dự án khác.

Ví dụ format (thay theo cấu hình OneDrive trên máy bạn):
  Windows OneDrive:  %OneDrive%\Obsidian_Vault\<project>\<vault>
  Windows USERPROFILE: %USERPROFILE%\OneDrive\Obsidian_Vault\<project>\<vault>

"@ | Write-Host

$custom = Read-Host "Vault path"

if ([string]::IsNullOrWhiteSpace($custom)) {
    Write-Host "✗ Hủy bỏ."
    exit 1
}

if (New-VaultSymlink -Target $custom -Reason "manual prompt") { exit 0 } else { exit 1 }
