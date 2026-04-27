#!/usr/bin/env bash
# scripts/setup-vault.sh
#
# Tạo symlink .obsidian-vault tới Obsidian vault path do USER nhập.
# Script KHÔNG tự đoán path (mỗi dự án có vault riêng, auto-detect dễ link sai vault).
# Chạy 1 lần per máy mới, hoặc khi vault path thay đổi.
#
# Usage:
#   bash scripts/setup-vault.sh                  # prompt user nhập path
#   bash scripts/setup-vault.sh /path/to/vault   # explicit path (skip prompt)
#
# Marker: vault PHẢI có file Index.md ở root để verify đúng vault.

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYMLINK="$PROJECT_ROOT/.obsidian-vault"
MARKER="Index.md"

create_symlink() {
    local target="$1"
    local reason="$2"
    target="${target/#\~/$HOME}"
    if [ ! -f "$target/$MARKER" ]; then
        echo "✗ Path không hợp lệ (thiếu $MARKER): $target"
        return 1
    fi
    ln -s "$target" "$SYMLINK"
    echo "✓ Linked ($reason): $SYMLINK → $target"
    return 0
}

# 1) Symlink đã tồn tại + resolve OK → noop
if [ -L "$SYMLINK" ] && [ -f "$SYMLINK/$MARKER" ]; then
    echo "✓ Symlink đã tồn tại: $SYMLINK → $(readlink "$SYMLINK")"
    exit 0
fi

# 2) Broken symlink → xóa
if [ -L "$SYMLINK" ]; then
    echo "⚠ Symlink broken (target không có $MARKER), xóa: $SYMLINK"
    rm "$SYMLINK"
fi

# 3) Path argument explicit → bỏ qua prompt
if [ -n "${1:-}" ]; then
    create_symlink "$1" "manual" || exit 1
    exit 0
fi

# 4) Prompt user nhập path
cat <<EOF
Symlink .obsidian-vault chưa tồn tại cho dự án này.

Nhập path tới Obsidian vault dành cho DỰ ÁN NÀY (folder chứa $MARKER).
Mỗi dự án có vault riêng — KHÔNG dùng path của dự án khác.

Ví dụ format (thay theo nơi vault đang nằm trên máy bạn — internal drive,
external drive, cloud sync folder, ...):
  Internal:      ~/Documents/Obsidian_Vault/<project>/<vault>
  External:      /Volumes/<DriveName>/Obsidian_Vault/<project>/<vault>
  Cloud sync:    ~/<CloudFolder>/Obsidian_Vault/<project>/<vault>

EOF
read -r -p "Vault path: " custom

if [ -z "$custom" ]; then
    echo "✗ Hủy bỏ."
    exit 1
fi

create_symlink "$custom" "manual prompt" || exit 1
