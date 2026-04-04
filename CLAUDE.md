# Workspace Configuration - Project Context

## Tổng quan
Flutter desktop app (macOS/Linux/Windows) giúp developer thiết lập và quản lý môi trường phát triển.
Hỗ trợ Odoo projects và các dự án ngôn ngữ khác (Flutter, React, NextJS, .NET, Rust, Go, Java...).
Cung cấp GUI để quản lý project, Python/venv, nginx reverse proxy, Docker, và sinh cấu hình VSCode debug.

## Tech Stack
- **Flutter** SDK ^3.9.2 (FVM managed)
- **Provider** 6.1.0 - state management (ThemeService, LocaleService)
- **file_picker** 8.0.0 - chọn thư mục/file (macOS/Linux; Windows dùng native PowerShell dialog)
- **path** 1.9.0 - xử lý đường dẫn cross-platform
- **window_manager** 0.5.1 - control window size, min size, center, animation resize
- **msix** 3.16.13 - build MSIX installer cho Windows
- **flutter_launcher_icons** 0.14.4 - generate app icon đa nền tảng

## Tên ứng dụng
- Display name: **Workspace Configuration** (tất cả ARB, main.dart, pubspec.yaml, Info.plist)
- Package name: `odoo_auto_config` (giữ nguyên, không ảnh hưởng user)
- macOS CFBundleName: "Workspace Configuration" (có dấu cách)
- App icon: `workspaces.png` (512x512)

## Kiến trúc
```
lib/
├── main.dart                    # Entry point, Provider setup, window_manager init, SelectionArea
├── constants/app_constants.dart # Design tokens: spacing, font-size, colors, radius, dialog sizes
├── models/                      # Data classes (immutable, fromJson/toJson, copyWith)
│   ├── profile.dart             # Cấu hình Odoo dev profile
│   ├── workspace_info.dart      # Other project (name, path, type, description, favourite, port, nginxSubdomain)
│   ├── project_info.dart        # Odoo project (name, path, ports, description, favourite, nginxSubdomain)
│   ├── venv_info.dart           # Thông tin virtual environment
│   ├── python_info.dart         # Python installation detected
│   ├── command_result.dart      # Kết quả chạy process
│   ├── venv_config.dart         # Config tạo venv mới
│   └── folder_structure_config.dart # Config tạo folder structure
├── services/                    # Business logic (stateless, static methods)
│   ├── storage_service.dart     # Lưu trữ JSON tại ~/.config/odoo_auto_config/
│   ├── command_runner.dart      # Wrap Process.run() -> CommandResult (runInShell: true)
│   ├── python_checker_service.dart # Detect Python installations (absolute paths + dedup shims)
│   ├── python_install_service.dart # Cross-platform Python install (winget/brew/apt)
│   ├── docker_install_service.dart # Docker install + status check (winget/brew/apt)
│   ├── postgres_service.dart    # PostgreSQL: client detect, server detect (Docker+local), init Docker project, start/stop/restart
│   ├── nginx_service.dart       # Nginx: init project, setup/remove proxy, port check, hosts, mkcert
│   ├── venv_service.dart        # Tạo/scan/inspect venv, pip install
│   ├── folder_structure_service.dart # Tạo cấu trúc thư mục Odoo project
│   ├── vscode_config_service.dart   # Sinh .vscode/launch.json (debugpy)
│   ├── theme_service.dart       # Theme mode + accent color (ChangeNotifier)
│   ├── locale_service.dart      # Locale persistence + Provider (ChangeNotifier)
│   ├── platform_service.dart    # Platform abstraction (paths, executables, native dialogs)
│   └── update_service.dart      # Auto-update: check GitHub releases, download, install
├── screens/                     # UI screens (StatefulWidget)
│   ├── home_screen.dart         # NavigationRail (4 tab) + window size selector (S/M/L) + animation
│   ├── projects_screen.dart     # Odoo Projects: list/grid, favourite, CRUD, nginx setup/link/remove
│   ├── workspaces_screen.dart   # Other Projects: list/grid, favourite, auto-detect type, nginx
│   ├── quick_create_screen.dart # Dialog tạo Odoo project nhanh từ profile
│   ├── profile_screen.dart      # CRUD profiles
│   ├── python_check_screen.dart # (ẩn khỏi menu, code giữ nguyên)
│   ├── venv_screen.dart         # 3 tabs: list/scan/create venv (nhúng trong Settings > Python)
│   ├── vscode_config_screen.dart # Sinh debug config (ẩn khỏi menu, code giữ nguyên)
│   ├── folder_structure_screen.dart # Tạo folder structure độc lập
│   └── settings_screen.dart     # 6 tabs: Theme, Docker, Python+Venv, PostgreSQL, Nginx, Git
├── widgets/                     # Reusable components
│   ├── status_card.dart         # Card hiển thị trạng thái
│   ├── directory_picker_field.dart # Text field + browse button
│   ├── log_output.dart          # Real-time log với color coding + SelectionArea
│   └── nginx_setup_dialog.dart  # Dialog setup nginx (subdomain, port, validation)
└── templates/
    ├── odoo_templates.dart      # Sinh odoo.conf, README.md, git-repositories.sh/.ps1
    ├── nginx_templates.dart     # Sinh nginx conf (odoo/generic), nginx.conf, docker-compose.yml
    └── postgres_templates.dart  # Sinh docker-compose.yml, .env, postgresql.conf cho PostgreSQL Docker
```

## Navigation (4 tabs)
1. **Odoo Projects** - projects_screen.dart (icon: folder_special)
2. **Other Projects** - workspaces_screen.dart (icon: workspaces)
3. **Profiles** - profile_screen.dart (icon: person)
4. **Settings** - settings_screen.dart (icon: settings)
   - Tab 0 **Theme**: ngôn ngữ, theme mode, accent color, preview
   - Tab 1 **Docker**: trạng thái + cài đặt
   - Tab 2 **Python**: Python installations + cài đặt + Venv Manager (nhúng VenvScreen)
   - Tab 3 **PostgreSQL**: 2 phần:
     1. Client Tools: phát hiện 6 tools (psql, pg_dump, pg_restore, createdb, dropdb, pg_isready),
        hiện path từng tool, cài tự động (brew install libpq / apt install postgresql-client / winget)
     2. Server Status: phát hiện Docker containers (running+stopped, lọc internal port 5432) + local service
        (brew services/systemctl/sc query/Postgres.app), xác minh bằng pg_isready -t 1, chạy song song
        Controls: Start/Stop/Restart cho Docker containers, Start cho local service
        Setup: Dialog tạo PostgreSQL Docker project (docker-compose.yml, .env, postgresql.conf)
        Nếu chưa có server nào → hiện nút "Setup PostgreSQL Docker"
   - Tab 4 **Nginx**: config record (init/import/edit/delete) + port check (80/443)
   - Tab 5 **Git**: GitHub token (lưu vào settings, dùng khi tạo git-repositories script)

> Python Check và VSCode Config **ẩn khỏi menu** nhưng code giữ nguyên.

## Các pattern chính
- **Immutable models** với `fromJson()`/`toJson()` + `copyWith()` (nullable field dùng `Function()`)
- **Stateless services** - static methods, không giữ state
- **Provider** chỉ cho ThemeService, LocaleService (ChangeNotifier)
- **Real-time logging** - LogOutput widget auto-scroll, color-coded, SelectionArea wrap riêng
- **SelectionArea** - wrap toàn bộ app tại main.dart, cho phép select + copy text bất kỳ
- **Dialog-based workflows** - Quick Create, Edit, Nginx Setup, Install Python/Docker/mkcert
- **Port conflict detection** - kiểm tra trùng port giữa các Odoo project
- **Cross-platform** - PlatformService abstract paths; mỗi service có branch cho 3 OS
- **Responsive layout** - Row cho header (Spacer đẩy nút sang phải), Wrap cho card actions
- **Window size** - 3 preset: Small (800x600 min), Medium (1100x750), Large (1400x900 default)
  Persisted vào settings JSON (`windowSize`). Lần đầu = Large, lần sau = size đã chọn trước đó.
  Animation ease-out cubic 200ms khi chuyển size, guard chống spam click
- **List/Grid view** - Shared static `ProjectsScreen.gridView`, persisted vào settings JSON
  Grid default, responsive columns: S=3, M=4, L=5. Scale icon/button theo cell width
- **Favourite** - Star icon (IconButton với hover), sort favourite lên đầu rồi by name A-Z
- **Grid context menu** - Right-click hiện menu (favourite, git pull/commit, nginx setup/link/remove, VSCode, folder, edit, delete)
- **Grid tooltip** - Hover hiện description (hoặc path nếu không có description)
- **Auto-detect project type** - Import workspace tự động nhận diện từ marker files
- **Nginx status** - Lưu `nginxSubdomain` vào model JSON (không derive từ tên project)
  Khi setup: lưu subdomain. Khi remove: xóa subdomain. Check bằng `hasNginx` getter.

## Hành vi khi khởi động
- Check Docker installed + daemon running (retry 3 lần, mỗi lần cách 5s - phòng trường hợp auto-start after login)
- Nếu Docker không cài hoặc daemon chưa chạy → hiện MaterialBanner (không tự tắt) với nút "Go to Settings"
- Nếu Docker running + nginx container stopped → tự động `docker start <container>`
- Banner chỉ mất khi Docker daemon thực sự running
- `HomeScreen.navigateToSettings(settingsTab: N)` để chuyển tab từ bất kỳ screen nào
  (VD: bấm Setup Nginx khi chưa config → tự động chuyển sang Settings > Nginx tab)

## Tính năng Auto-Update
- **Phát hiện version**: Đọc từ `lib/generated/version.dart` (compiled Dart const)
  File này PHẢI được generate trước khi build (CI workflow và release.sh tự động làm)
- **Kiểm tra GitHub**: Query `api.github.com/repos/namchamvinhcuu/workspace-configuration/releases/latest`
  So sánh semver: currentVersion vs tag_name. Hiện MaterialBanner nếu có update
- **Download + Install** (theo platform):
  - **macOS**: Tải `.zip` (KHÔNG phải .dmg) → `ditto -xk` unzip → shell script replace .app → relaunch
    DMG chỉ dùng cho user tải manual. ZIP dùng cho auto-update (đơn giản, không cần mount/unmount)
  - **Linux**: Tải `.AppImage` → shell script replace → relaunch
  - **Windows**: Tải `.msix` → `Add-AppPackage -ForceApplicationShutdown` → `Start-Process` relaunch
- **Xử lý lỗi**: Download/install fail → hiện SnackBar thông báo. macOS log tại `/tmp/wsc_update.log`
- **Public repo**: Releases publish lên `namchamvinhcuu/workspace-configuration` (public)
  Code dev tại `namchamvinhcuu/odoo_auto_config` (private)
- **QUAN TRỌNG**: Khi release, `assets/version.json` phải khớp với version tag
  CI workflow tự động generate từ `$GITHUB_REF_NAME`. Local release qua `release.sh` cũng tự động update
- **MSIX version**: Không hardcode `msix_version` trong pubspec.yaml. Tự động derive từ `version` field
  (VD: version 1.2.0+1 → msix_version 1.2.0.1). release.sh/ps1 chỉ cần update `version`

## Tính năng Nginx
- **Init project**: Tạo structure (conf.d/, certs/, nginx.conf, docker-compose.yml, .gitignore)
  Dùng mkcert để tạo SSL cert. App có thể cài mkcert tự động (brew/winget/apt).
- **Import**: Chọn folder nginx có sẵn, tự detect conf.d bên trong
- **Config record**: Chỉ 1 record duy nhất. Hiện info card (confDir, domainSuffix, containerName)
  Có nút Edit (chuyển sang form) và Delete (confirm + option xóa folder)
- **Port check**: Tự động check port 80/443 khi hiện info card
  macOS/Linux: `lsof`, Windows: `netstat + tasklist`. Hiện process name + PID
  Phân biệt docker vs local: nếu docker container running + process là docker runtime → xanh (OK)
  Nếu process khác (local nginx, apache, ...) → cam (warning) + nút Kill Process
  Nếu là local nginx → hiện thêm hướng dẫn disable auto-start (brew services stop / systemctl disable)
- **Container controls**: Start (khi stopped), Stop (khi running), Restart. Error hiện inline card đỏ
- **Nginx config record**: 3 trạng thái: empty (chưa config), info card (đã config), edit form
- **Setup per project**: Dialog với subdomain (fill sẵn, có thể sửa ngắn gọn) + port (Other Projects)
  Validation: ký tự hợp lệ (a-z, 0-9, -), trùng domain, trùng port
- **Link existing**: Chọn từ danh sách conf có sẵn trong conf.d/
- **Remove**: Xóa conf file + hosts entry + reload container
- **Hosts file**: macOS (osascript), Linux (pkexec), Windows (PowerShell RunAs/UAC)
- **Conf templates**: Odoo (3 location: /, /websocket, /longpolling), Generic (1 location: /)
- **Chỉ Docker**: Không hỗ trợ nginx cài local (structure khác nhau tùy OS, quá nhiều biến thể)

## Tính năng Git
- **Git Pull**:
  - Odoo Projects: chạy `git-repositories.sh` (macOS/Linux) hoặc `.ps1` (Windows) — pull hàng loạt repos trong addons/
  - Other Projects: chạy `git pull` trực tiếp (single repo, check .git tồn tại)
- **Git Commit**:
  - Other Projects: `git status --porcelain` → checkbox list files → `git add --` từng file → `git commit` → optional `git push`
  - Odoo Projects: scan `addons/` tìm repos có changes → checkbox list repos → `git add -A` + `git commit` + optional `git push` cho mỗi repo
  - Reload status sau khi commit để hiện file/repo còn lại
- **Git Repositories Script** (`git-repositories.sh` / `.ps1`):
  - Template trong `odoo_templates.dart` với params `token` và `org`
  - Tạo tự động khi Quick Create Odoo project
  - Token đọc từ settings (`gitToken`), org nhập khi tạo project
  - Edit project: đọc/sửa token+org trực tiếp từ file script (regex parse)
- **Vị trí UI**: List view (IconButton), Grid view (chỉ Git Pull, commit trong context menu), Context menu (đầy đủ)
- **Log output**: Dùng `Text.rich` (KHÔNG dùng `RichText`) trong `SelectionArea` để copy text được
  `RichText` là render-level widget, không tham gia `SelectionArea`. `Text.rich` wrapper đúng cách
- **Parse git status**: Dùng `substring(0,2)` cho status + `substring(3)` cho filename.
  QUAN TRỌNG: output phải dùng `.trimRight()` (KHÔNG dùng `.trim()` vì sẽ xóa space đầu dòng đầu tiên → mất ký tự status)
  Handle rename format `old -> new`
- **git add**: Add từng file một với `git add -- <file>` (tránh shell argument issues khi nhiều files)

## Lưu trữ dữ liệu
Tất cả data lưu tại: `~/.config/odoo_auto_config/odoo_auto_config.json`
Gồm: profiles, projects, workspaces, registered_venvs, settings
Settings gồm: theme, locale, gridView, nginx (confDir, domainSuffix, containerName), gitToken

## Lệnh thường dùng
```bash
# Chạy debug
fvm flutter run -d macos   # hoặc linux, windows
# LƯU Ý: `fvm flutter run macOS` (không có -d) sẽ báo lỗi "Target file not found"

# Build release
fvm flutter build macos --release

# Gen l10n (sau khi sửa file ARB)
fvm flutter gen-l10n

# Analyze
fvm flutter analyze

# Generate app icons (sau khi đổi file icon)
fvm dart run flutter_launcher_icons
# Cần flutter clean + restart sau khi đổi icon (macOS cache)

# Build DMG
APP_PATH="build/macos/Build/Products/Release/odoo_auto_config.app"
DMG_PATH="build/Workspace Configuration.dmg"
TMP_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$TMP_DIR/Workspace Configuration.app"
ln -s /Applications "$TMP_DIR/Applications"
hdiutil create -volname "Workspace Configuration" -srcfolder "$TMP_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$TMP_DIR"

# Release (macOS/Linux)
bash release.sh 1.0.5

# Release (Windows PowerShell)
.\release.ps1 1.0.5
```

## Đa ngôn ngữ (i18n)
- **Ngôn ngữ hỗ trợ**: English (default), Vietnamese (`vi`), Korean (`ko`)
- **ARB files**: `lib/l10n/app_en.arb`, `app_vi.arb`, `app_ko.arb`
- **Generated files**: `lib/l10n/app_localizations*.dart` (KHÔNG sửa thủ công)
- **Extension**: `context.l10n.keyName` qua `lib/l10n/l10n_extension.dart`
- **Log messages**: giữ nguyên tiếng Anh (technical output)
- Khi thêm string mới: thêm vào cả 3 file ARB, chạy `fvm flutter gen-l10n`
- Lưu ý dịch thuật: "Theme Mode" tiếng Việt là "Tùy chỉnh giao diện" (không phải "Chế độ giao diện")

## Lưu ý Cross-Platform

### Shell scripts cross-platform
- `sed -i` khác nhau: macOS (BSD) cần `sed -i ''`, Linux (GNU) dùng `sed -i`
  Trong release.sh: dùng `$OSTYPE` check để chọn đúng variant

### QUAN TRỌNG: App được build và cài đặt để chạy độc lập (DMG/MSIX/bundle)
- **MỌI thay đổi code PHẢI tính đến release mode**, không chỉ debug
- macOS GUI app (.app) KHÔNG có PATH từ shell (~/.zshrc không được load)
- Tất cả external binary (docker, mkcert, python, code, ...) PHẢI resolve absolute path
- Test trên release build (DMG) trước khi xác nhận tính năng hoạt động
- KHÔNG dùng hardcode `'docker'`, `'mkcert'`, ... mà phải qua PlatformService

### Tất cả OS
- Process.run PHẢI dùng `runInShell: true` (AOT mode)
- window_manager cần **full restart** (không hot reload) khi thêm mới
- App icon cần `flutter clean` + rebuild sau khi thay đổi
- External binaries PHẢI resolve qua PlatformService (dockerPath, pythonCandidates, ...)
- **KHÔNG BAO GIỜ hardcode separator `/` hoặc `\` khi nối đường dẫn local file system**
  Luôn dùng `p.join()` từ `package:path/path.dart` (import as `p`)
  VD: `p.join(baseDir, 'conf.d')` thay vì `'$baseDir/conf.d'`
  `p.dirname(path)` thay vì `path.substring(0, path.length - N)`
  CHỈ NGOẠI LỆ: paths bên trong Docker container (nginx conf, docker-compose volumes) luôn dùng `/` vì container là Linux
- **Process output (winget/brew/apt)**: dùng `utf8.decoder` thay vì `SystemEncoding().decoder`
  Dùng `CommandRunner.cleanLine()` để strip ANSI codes, spinner chars, và progress bars

### macOS
- App Sandbox PHẢI tắt trong cả DebugProfile và Release entitlements
- **GUI app (.app) không load ~/.zshrc** → PATH rất tối giản
  Fix: PlatformService resolve absolute paths cho tất cả binaries:
  - Python: pyenv shims, pyenv versions, homebrew, /usr/local/bin, /usr/bin
  - Docker: /usr/local/bin/docker, ~/.orbstack/bin/docker, /opt/homebrew/bin/docker,
    /Applications/Docker.app/.../docker, /Applications/OrbStack.app/.../docker
  - VSCode: `open -a "Visual Studio Code"` (tránh PATH issue)
- Hosts: `osascript` với `with administrator privileges` (native password dialog)
- Sau khi copy/rename .app: cần `xattr -cr` (KHÔNG cần codesign, chỉ xattr là đủ)

### Windows
- MSIX cần `runFullTrust` capability để Process.run hoạt động
- Native file/folder picker bằng PowerShell + COM (IFileOpenDialog)
- Open VSCode: `cmd /c code` (qua PATH)
- Hosts: `C:\Windows\System32\drivers\etc\hosts`, PowerShell `Start-Process -Verb RunAs` (UAC)
- Port check: `netstat -ano` + `tasklist /FI "PID eq ..."`
- Docker/Python install: `winget`
- mkcert install: `winget install FiloSottile.mkcert`

### Windows - CHƯA TEST (cần kiểm tra khi có điều kiện)
| Chức năng | Rủi ro | Chi tiết |
|-----------|--------|----------|
| Hosts file edit | CAO | PowerShell RunAs + UAC, escape string chưa verify thực tế |
| mkcert install | TRUNG BÌNH | `winget install FiloSottile.mkcert` - chưa verify package name |
| Docker install | TRUNG BÌNH | `winget install Docker.DockerDesktop` - cần restart sau cài |
| Port check | TRUNG BÌNH | `netstat -ano` output format có thể khác giữa Windows versions |
| Kill process | TRUNG BÌNH | `taskkill /F /PID` - cần quyền admin cho system processes |
| Native file picker | THẤP | Đã test trước đó, dùng PowerShell COM |
| nginx conf write | THẤP | File.writeAsString cross-platform |
- macOS: đã test OK
- Linux: đã test OK (2026-03-29)

### Linux
- Python install: `pkexec apt install` (graphical sudo, không cần terminal)
- Hosts: `pkexec` (polkit graphical sudo)
- Port check: `lsof -i :PORT`
- Docker install: `pkexec apt install docker.io docker-compose-v2` + systemctl enable

## Quyết định thiết kế
- **Nginx chỉ Docker**: Không hỗ trợ nginx local vì conf structure khác nhau tùy OS/cách cài
- **1 nginx record**: Mỗi PC chỉ cần 1 container nginx, không cần nhiều record
- **nginxSubdomain lưu trong model**: Để track status chính xác, không phụ thuộc tên project
  (user có thể đặt subdomain khác tên project, VD: "pltax" cho project "polish-tax-odoo")
- **Link existing conf**: Cho phép gán conf đã có vào project mà không tạo/sửa file
- **Settings tabbed**: Theme / Docker / Python+Venv / PostgreSQL / Nginx / Git - để mở rộng thêm framework sau
- **Hidden screens**: Python Check và VSCode Config ẩn khỏi NavigationRail nhưng giữ code
  (Python Check nhúng vào Settings > Python, VSCode Config có thể dùng riêng nếu cần)
