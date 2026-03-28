# Odoo Auto Config

Ứng dụng Flutter desktop (macOS/Linux/Windows) giúp developer thiết lập và quản lý môi trường phát triển. Hỗ trợ Odoo projects và các dự án ngôn ngữ khác (Flutter, React, NextJS, .NET, Rust, Go, Java...).

---

## Mục lục

- [Cài đặt](#cài-đặt)
- [Hướng dẫn sử dụng](#hướng-dẫn-sử-dụng)
  - [Giao diện chính](#giao-diện-chính)
  - [Odoo Projects](#1-odoo-projects)
  - [Other Projects](#2-other-projects)
  - [Profiles](#3-profiles)
  - [Python Check](#4-python-check)
  - [Venv Manager](#5-venv-manager)
  - [VSCode Config](#6-vscode-config)
  - [Folder Structure](#7-folder-structure)
  - [Settings](#8-settings)
  - [Nginx Reverse Proxy](#9-nginx-reverse-proxy)
- [Workflow khuyến nghị](#workflow-khuyến-nghị)
- [Clone Odoo Core](#clone-odoo-core)
- [Xử lý lỗi thường gặp](#xử-lý-lỗi-thường-gặp)
- [Build](#build)
- [Development](#development)

---

## Cài đặt

### macOS

**Cách 1: DMG Installer**

Mở file `Odoo Config.dmg`, kéo **Odoo Config.app** vào `/Applications`.

**Cách 2: Copy thủ công**

```bash
cp -R "build/macos/Build/Products/Release/odoo_auto_config.app" "/Applications/Odoo Config.app"
xattr -cr "/Applications/Odoo Config.app"
codesign --force --deep --sign - "/Applications/Odoo Config.app"
```

### Windows

**Cách 1: Chạy trực tiếp (Portable)**

Copy toàn bộ folder `build\windows\x64\runner\Release\` và chạy `odoo_auto_config.exe`.

**Cách 2: Cài đặt bằng MSIX**

MSIX được ký bằng self-signed certificate. Trước khi cài `.msix`, bạn cần cài certificate trước.

**Bước 1: Cài đặt Certificate**

Dùng PowerShell (Admin):

```powershell
$pwd = ConvertTo-SecureString -String "odoo123" -Force -AsPlainText
Import-PfxCertificate -FilePath "C:\path\to\certificate.pfx" -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" -Password $pwd
```

Hoặc cài thủ công: Double-click `certificate.pfx` > Local Machine > Password: `odoo123` > Place in: **Trusted People**.

**Bước 2:** Double-click `odoo_auto_config.msix` > Install.

**Gỡ cài đặt:** Settings > Apps > tìm "Odoo Auto Config" > Uninstall.

### Linux

Chạy trực tiếp từ `build/linux/x64/release/bundle/odoo_auto_config`.

> Dữ liệu cấu hình lưu tại `~/.config/odoo_auto_config/odoo_auto_config.json`, không bị xóa khi uninstall.

---

## Hướng dẫn sử dụng

### Giao diện chính

App sử dụng **NavigationRail** bên trái với 7 tab:

| # | Tab | Chức năng |
|---|-----|-----------|
| 1 | Odoo Projects | Quản lý dự án Odoo |
| 2 | Other Projects | Quản lý dự án ngôn ngữ khác |
| 3 | Profiles | Lưu cấu hình Odoo tái sử dụng |
| 4 | Python Check | Phát hiện & cài Python |
| 5 | Venv Manager | Quản lý virtual environment |
| 6 | VSCode Config | Sinh launch.json debug |
| 7 | Settings | Giao diện, ngôn ngữ, nginx |

**Window Size:** Bấm **S** / **M** / **L** dưới logo để thay đổi kích thước cửa sổ:
- **S** - 800x600 (minimum, không thu nhỏ hơn)
- **M** - 1100x750 (mặc định)
- **L** - 1400x900

**View Mode:** Chuyển giữa **List** và **Grid** bằng nút toggle. Lựa chọn được lưu lại cho lần mở app sau.

**Select & Copy:** Tất cả text trong app đều có thể select và copy (Cmd+C / Ctrl+C).

---

### 1. Odoo Projects

Quản lý tất cả dự án Odoo với truy cập nhanh.

#### Tạo mới (Quick Create)

Bấm **Create** > chọn Profile > điền thông tin:

| Field | Mô tả |
|-------|--------|
| Profile | Chọn profile đã lưu (venv + odoo-bin + DB settings) |
| Base Directory | Thư mục chứa project |
| Project Name | Tên project (VD: `my_odoo_project`) |
| HTTP Port | Port web (VD: 8069). Tự gợi ý port tiếp theo |
| Longpolling Port | Port longpolling (VD: 8072). Tự gợi ý |

App sẽ tự động:
- Tạo cấu trúc thư mục (addons, config, venv...)
- Sinh `odoo.conf` với port và DB settings
- Sinh `.vscode/launch.json` cho debug
- Sinh `README.md`
- Kiểm tra trùng port với project khác

#### Import project có sẵn

Bấm **Import** > browse thư mục > app tự phát hiện port từ `odoo.conf`.

#### Thao tác trên mỗi project

| Nút | Chức năng |
|-----|-----------|
| ★ | Favourite - đưa lên đầu danh sách |
| `<>` | Mở trong VSCode |
| 📁 | Mở thư mục trong Finder/Explorer |
| ✏️ | Sửa thông tin project |
| 🌐 (DNS) | Cấu hình Nginx reverse proxy |
| 🗑️ | Xóa (có option xóa file trên đĩa) |

**Grid View:** Click vào ô mở VSCode. Right-click hiện context menu đầy đủ.

**Tìm kiếm:** Gõ trong search bar để lọc theo tên, path, port.

**Sắp xếp:** Favourite lên đầu, sau đó theo tên A-Z.

---

### 2. Other Projects

Quản lý dự án không phải Odoo (Flutter, React, .NET, Rust, Go, Java, Python...).

#### Import

Bấm **Import** > browse thư mục. App tự phát hiện loại dự án từ marker files:

| File | Loại phát hiện |
|------|---------------|
| `pubspec.yaml` | Flutter |
| `package.json` | React (hoặc NextJS nếu có `next.config.*`) |
| `*.csproj` / `*.sln` | .NET |
| `Cargo.toml` | Rust |
| `go.mod` | Go |
| `pom.xml` / `build.gradle` | Java |
| `requirements.txt` / `pyproject.toml` | Python |
| `odoo-bin` / `odoo.conf` | Odoo |

#### Các field khi import/edit

| Field | Mô tả |
|-------|--------|
| Directory | Thư mục project |
| Name | Tên hiển thị |
| Type | Loại dự án (tự phát hiện hoặc chọn từ danh sách) |
| Description | Mô tả (hiện tooltip khi hover trong grid view) |
| Port | Port dev server (tùy chọn, dùng cho nginx) |

#### Lọc theo type

Bấm nút filter (icon lọc) bên cạnh search bar để lọc theo loại dự án.

#### Thao tác

Giống Odoo Projects: Favourite, VSCode, Folder, Edit, Nginx, Delete.

---

### 3. Profiles

Lưu cấu hình môi trường Odoo để tái sử dụng khi tạo project mới.

#### Tạo profile

Bấm **New Profile** > điền:

| Field | Mô tả |
|-------|--------|
| Profile Name | Tên (VD: "Odoo 17") |
| Virtual Environment | Chọn venv đã đăng ký |
| odoo-bin Path | Đường dẫn tới `odoo-bin` |
| Odoo Source Directory | Thư mục source Odoo (tùy chọn, cho symlink) |
| Odoo Version | 14 - 18 |
| DB Host / Port / User / Password | Thông tin kết nối PostgreSQL |
| SSL Mode | prefer / disable / require |

> Profile lưu trữ tất cả settings cần thiết để Quick Create project chỉ với vài click.

---

### 4. Python Check

Phát hiện và cài đặt Python trên hệ thống.

#### Scan

App tự quét các Python đã cài, hiển thị:
- Phiên bản (VD: Python 3.11.5)
- Đường dẫn executable
- Trạng thái pip (có/không)
- Trạng thái venv module (có/không)

#### Cài Python mới

Bấm **Install Python** > chọn version (3.10 - 3.13):

| OS | Package Manager |
|----|----------------|
| macOS | `brew install python@X.Y` |
| Linux | `pkexec apt install python3.X python3.X-venv` |
| Windows | `winget install Python.Python.X.Y` |

App hiện log cài đặt realtime và tự rescan sau khi hoàn tất.

---

### 5. Venv Manager

Quản lý Python virtual environments với 3 tab.

#### Tab: Registered

Danh sách venv đã đăng ký. Mỗi venv có:

| Nút | Chức năng |
|-----|-----------|
| Packages | Xem danh sách package đã cài |
| pip install | Cài package mới |
| requirements.txt | Cài từ file requirements |
| Rename | Đổi tên hiển thị |
| Delete | Xóa khỏi danh sách (không xóa thư mục) |

#### Tab: Scan

Quét thư mục để tìm venv có sẵn:
1. Chọn thư mục cần scan
2. Bấm **Scan** - app tìm các thư mục chứa `pyvenv.cfg`
3. Bấm **Register** để thêm vào danh sách

#### Tab: Create New

Tạo venv mới:
1. Chọn thư mục đích
2. Đặt tên venv
3. Chọn Python version (từ danh sách đã phát hiện)
4. Bấm **Create** - tự động đăng ký sau khi tạo

---

### 6. VSCode Config

Sinh file `.vscode/launch.json` cho debug Odoo với debugpy.

| Field | Mô tả |
|-------|--------|
| Configuration Name | Tên hiện trong VSCode debug (VD: "Debug Odoo 17") |
| Project Directory | Thư mục project (tạo `.vscode/` ở đây) |
| Virtual Environment | Chọn venv đã đăng ký |
| odoo-bin Path | Đường dẫn tới `odoo-bin` |

Bấm **Generate** - app merge với `launch.json` hiện có (không ghi đè).

Preview JSON hiện bên dưới trước khi generate.

---

### 7. Folder Structure

Tạo cấu trúc thư mục Odoo project độc lập (không cần profile).

| Field | Mô tả |
|-------|--------|
| Base Directory | Thư mục cha |
| Project Name | Tên project |
| Odoo Version | 14 - 18 |

Tùy chọn tạo: addons, third_party_addons, config, venv.

---

### 8. Settings

#### Ngôn ngữ
English (default), Tiếng Việt, 한국어.

#### Giao diện
- **Theme Mode:** System / Light / Dark
- **Accent Color:** 12 màu chủ đạo

#### Nginx Reverse Proxy

Cấu hình chung cho tính năng nginx (xem mục tiếp theo).

| Field | Mô tả | Ví dụ |
|-------|--------|-------|
| conf.d Directory | Thư mục chứa file conf nginx | `/path/to/nginx/conf.d` |
| Domain Suffix | Hậu tố domain | `.namchamvinhcuu.test` |
| Docker Container Name | Tên container nginx | `nginx` |

Bấm **Save** để lưu.

---

### 9. Nginx Reverse Proxy

Tự động tạo cấu hình nginx reverse proxy, thêm vào `/etc/hosts`, và reload container.

#### Điều kiện

- Docker nginx container đang chạy (network_mode: host)
- Đã cấu hình nginx trong Settings
- SSL certificates đã có trong nginx (kế thừa từ `nginx.conf`)

#### Setup Nginx cho project

1. Bấm nút **DNS** (🌐) trên project > chọn **Setup Nginx**
2. Dialog hiện ra với subdomain đã fill sẵn từ tên project
3. Sửa subdomain nếu muốn ngắn gọn hơn (VD: `pltax` thay vì `polish-tax-odoo`)
4. Với Other Projects: thêm field Port
5. Bấm **Setup Nginx**

App tự động:
- Tạo file conf trong `conf.d/` (Odoo: 3 location; Other: 1 location)
- Thêm `127.0.0.1 <domain>` vào `/etc/hosts` (yêu cầu nhập password admin)
- Chạy `docker exec nginx nginx -s reload`
- Nút DNS chuyển sang **màu xanh**

#### Validation

- **Subdomain:** Chỉ cho phép chữ thường, số, dấu gạch ngang. Không bắt đầu/kết thúc bằng `-`
- **Trùng domain:** Cảnh báo nếu subdomain đã tồn tại trong conf.d
- **Trùng port:** Cảnh báo nếu port đã được proxy bởi project khác (kiểm tra cả Odoo + Other)
- Preview domain realtime khi gõ

#### Link Nginx có sẵn

Nếu đã tạo conf trước đó (thủ công hoặc từ lần trước), bấm **DNS** > **Link existing Nginx**:
- Hiện danh sách tất cả file `.conf` trong `conf.d/`
- Chọn conf muốn gắn vào project
- Nút DNS chuyển xanh mà không tạo/sửa file conf

#### Remove Nginx

Bấm nút DNS (xanh) > xác nhận xóa:
- Xóa file conf
- Xóa dòng trong `/etc/hosts`
- Reload nginx container
- Nút DNS quay lại màu mặc định

#### Odoo conf template

```
HTTP -> HTTPS redirect (port 80)
HTTPS server (port 443):
  /websocket  -> proxy to httpPort (WebSocket upgrade)
  /           -> proxy to httpPort (HSTS)
  /longpolling -> proxy to longpollingPort
```

#### Generic conf template (Other Projects)

```
HTTP -> HTTPS redirect (port 80)
HTTPS server (port 443):
  /           -> proxy to port (HSTS)
```

---

## Workflow khuyến nghị

### Lần đầu setup

1. **Python Check** - kiểm tra Python đã cài, cài thêm nếu cần
2. **Venv Manager > Create** - tạo venv cho Odoo version cần dùng
3. **Profiles > New** - tạo profile với venv + odoo-bin + DB settings
4. **Odoo Projects > Create** - Quick Create project từ profile
5. **VSCode Config** - sinh debug config (nếu chưa có)
6. Mở project trong VSCode và bắt đầu code

### Thêm project mới (đã có profile)

1. **Odoo Projects > Create** - chọn profile, đặt tên, port tự gợi ý
2. Bấm ★ để favourite nếu hay dùng
3. Setup Nginx nếu cần domain riêng

### Import project có sẵn

1. **Odoo Projects > Import** (hoặc **Other Projects > Import**)
2. Browse thư mục - app tự phát hiện thông tin
3. Sửa port/name nếu cần > Save

---

## Clone Odoo Core

Clone source code Odoo để dùng với odoo-bin. Thay `XX.0` bằng version cần dùng (14.0 - 18.0):

```bash
git clone --branch XX.0 --single-branch --depth 1 https://github.com/odoo/odoo.git odooXX
```

Ví dụ:

```bash
# Odoo 17
git clone --branch 17.0 --single-branch --depth 1 https://github.com/odoo/odoo.git odoo17

# Odoo 18
git clone --branch 18.0 --single-branch --depth 1 https://github.com/odoo/odoo.git odoo18
```

> `--depth 1` chỉ clone commit mới nhất, giúp giảm dung lượng download.

---

## Xử lý lỗi thường gặp

### 1. Python version không tương thích (SyntaxError trong site.py)

**Lỗi:**
```
Fatal Python error: init_import_site: Failed to import the site module
SyntaxError: multiple exception types must be parenthesized
```

**Nguyên nhân:** VSCode sử dụng Python quá mới (VD: 3.14). Odoo 17 chỉ hỗ trợ Python 3.10 - 3.12.

**Cách sửa:** Mở `.vscode/settings.json`, thêm:
```json
{
  "python.defaultInterpreterPath": "/path/to/venv/bin/python"
}
```
Hoặc: `Ctrl+Shift+P` > `Python: Select Interpreter` > chọn Python từ venv.

### 2. User database 'postgres' bị chặn

**Lỗi:**
```
Using the database user 'postgres' is a security risk, aborting.
```

**Cách sửa:**

```sql
-- Tạo user mới
CREATE USER odoo WITH CREATEDB PASSWORD 'your_password';
```

Cập nhật `odoo.conf`:
```ini
db_user = odoo
db_password = your_password
```

### 3. Lệnh `psql` không được nhận diện (Windows)

**Cách sửa:** Dùng đường dẫn đầy đủ:
```cmd
"C:\Program Files\PostgreSQL\16\bin\psql.exe" -U postgres
```
Hoặc thêm `C:\Program Files\PostgreSQL\16\bin` vào PATH.

### 4. App crash trên macOS sau khi copy

**Cách sửa:**
```bash
xattr -cr "/Applications/Odoo Config.app"
codesign --force --deep --sign - "/Applications/Odoo Config.app"
```

### 5. Nginx setup yêu cầu password

Bình thường - app cần quyền admin để sửa `/etc/hosts`. Trên macOS hiện dialog nhập password, trên Linux dùng pkexec.

---

## Build

### Yêu cầu

- Flutter SDK ^3.9.2 (FVM managed)
- Xcode (macOS build)
- Visual Studio 2022 với C++ desktop workload (Windows build)
- GTK3 (Linux build)

### macOS

```bash
fvm flutter build macos --release

# Tạo DMG
APP_PATH="build/macos/Build/Products/Release/odoo_auto_config.app"
DMG_PATH="build/Odoo Config.dmg"
TMP_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$TMP_DIR/Odoo Config.app"
ln -s /Applications "$TMP_DIR/Applications"
hdiutil create -volname "Odoo Config" -srcfolder "$TMP_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$TMP_DIR"
```

### Windows

```bash
fvm flutter build windows --release
fvm dart run msix:create --install-certificate false
```

### Linux

```bash
fvm flutter build linux --release
```

---

## Development

```bash
# Chạy debug
fvm flutter run -d macos   # hoặc linux, windows

# Analyze
fvm flutter analyze

# Generate l10n (sau khi sửa file ARB)
fvm flutter gen-l10n
```

> **Lưu ý:** Khi thêm package native mới (VD: window_manager), cần full restart app, không dùng hot reload.

---

Generated by **Odoo Auto Config**
