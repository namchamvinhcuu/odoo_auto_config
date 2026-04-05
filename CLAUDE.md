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
- **system_tray** 2.0.3 - system tray icon, menu, minimize to tray
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
│   ├── tray_service.dart        # System tray: init, show/hide, close behavior setting
│   └── update_service.dart      # Auto-update: check GitHub releases, download, install
├── screens/                     # UI screens (StatefulWidget)
│   ├── home_screen.dart         # NavigationRail (4 tab) + window size selector (S/M/L) + animation
│   ├── projects_screen.dart     # Odoo Projects: list/grid, favourite, CRUD, nginx setup/link/remove
│   ├── workspaces_screen.dart   # Other Projects: list/grid, favourite, auto-detect type, nginx
│   ├── quick_create_screen.dart # Dialog tạo Odoo project nhanh từ profile + Setup Nginx sau tạo
│   ├── profile_screen.dart      # CRUD profiles
│   ├── python_check_screen.dart # (ẩn khỏi menu, code giữ nguyên)
│   ├── venv_screen.dart         # 3 tabs: list/scan/create venv (nhúng trong Settings > Python)
│   ├── vscode_config_screen.dart # Sinh debug config (ẩn khỏi menu, code giữ nguyên)
│   ├── folder_structure_screen.dart # Tạo folder structure độc lập
│   ├── odoo_workspace_dialog.dart # Workspace View: dashboard quản lý repos trong addons/
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
   - Tab 5 **Git**: Danh sách Git accounts (name, username, email, token) + default account
     CRUD qua dialog. Lưu `gitAccounts` + `defaultGitAccount` vào settings

> Python Check và VSCode Config **ẩn khỏi menu** nhưng code giữ nguyên.

## Các pattern chính
- **Immutable models** với `fromJson()`/`toJson()` + `copyWith()` (nullable field dùng `Function()`)
- **Stateless services** - static methods, không giữ state
- **Provider** chỉ cho ThemeService, LocaleService (ChangeNotifier)
- **Real-time logging** - LogOutput widget auto-scroll, color-coded, SelectionArea wrap riêng
- **SelectionArea** - wrap toàn bộ app tại main.dart, cho phép select + copy text bất kỳ
- **Dialog-based workflows** - Quick Create, Edit, Nginx Setup, Install Python/Docker/mkcert
- **Dialog close button** - `AppDialog.closeButton(context)`: icon X, nền đỏ, chữ trắng, góc trên bên phải
  Hỗ trợ `onClose:` nullable (disable khi running). KHÔNG dùng footer Close/Cancel button nữa.
  Close-only dialog: xóa `actions:`, thêm closeButton vào title Row
  Cancel+Action dialog: xóa Cancel, thêm closeButton vào title Row, giữ action button trong `actions:`
- **Port conflict detection** - kiểm tra trùng port giữa các Odoo project
- **Cross-platform** - PlatformService abstract paths; mỗi service có branch cho 3 OS
- **Responsive layout** - Row cho header (Spacer đẩy nút sang phải), Wrap cho card actions
- **Window size** - 3 preset: Small (800x600 min), Medium (1100x750), Large (1400x900 default)
  Persisted vào settings JSON (`windowSize`). Lần đầu = Large, lần sau = size đã chọn trước đó.
  Animation ease-out cubic 200ms khi chuyển size, guard chống spam click
- **List/Grid view** - Shared static `ProjectsScreen.gridView`, persisted vào settings JSON
  Grid default, responsive columns: S=3, M=4, L=5. Scale icon/button theo cell width
- **Favourite** - Star icon (IconButton với hover), sort favourite lên đầu rồi by name A-Z
- **Grid context menu** - Right-click hiện menu (favourite, git pull/commit/selective pull, VSCode, folder, edit, delete)
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

## Tính năng System Tray
- **Package**: `system_tray 2.0.3` — macOS, Windows, Linux
- **Icon**: `assets/tray_icon.png` (512x512, package tự resize), `.ico` cho Windows
  `title: ''` — chỉ hiện icon, KHÔNG hiện text cạnh icon
- **Init**: luôn init khi app khởi động (main.dart), tray icon luôn hiện
- **Close behavior**: setting trong Settings > Theme tab
  `'exit'` (mặc định): đóng cửa sổ = thoát app
  `'tray'`: đóng cửa sổ = ẩn vào tray, click tray icon để mở lại
- **Events**: click/double-click → show, right-click → menu (Show / Quit)
- **Hỗ trợ**: macOS + Windows. `TrayService.supported` = `Platform.isMacOS || Platform.isWindows`
  Linux: tạm tắt (tạo duplicate instance)
- **macOS**: dùng `windowManager.setPreventClose(true)` + `onWindowClose` callback
  `applicationShouldTerminateAfterLastWindowClosed` PHẢI return `false`
  Không cần `setSkipTaskbar`, chỉ `hide()/show()`
- **Windows**: cơ chế hoàn toàn khác macOS (xem chi tiết bên dưới)
  - `window_manager 0.5.1` + Flutter 3.41: `setPreventClose(true)` KHÔNG hoạt động
    Plugin intercept `WM_CLOSE` nhưng `onWindowClose` callback không fire
  - **Giải pháp**: xử lý `WM_CLOSE` ở native C++ level
    `flutter_window.cpp`: `case WM_CLOSE: ShowWindow(hwnd, SW_HIDE); return 0;`
    Window bị hide thay vì destroy, tray icon giữ nguyên
  - **Close behavior exit**: dùng `onWindowEvent('hide')` trong HomeScreen
    Phân biệt minimize vs close bằng flag `_isMinimizing`
    (`minimize` event fire trước `hide` khi minimize, nhưng không fire khi nhấn X)
  - **Close behavior tray**: window đã bị hide bởi native code, không cần làm gì thêm
  - `main.cpp`: `SetQuitOnClose(false)` — QUAN TRỌNG, nếu `true` thì `PostQuitMessage` sẽ
    thoát app khi window bị destroy
  - **KHÔNG dùng `setSkipTaskbar`** trên Windows — gây native crash với window_manager 0.5.1
  - **Single instance**: Named mutex `WorkspaceConfiguration_SingleInstance` trong `main.cpp`
    Nếu mutex đã tồn tại → `FindWindow` + `ShowWindow(SW_SHOW)` + `SetForegroundWindow` → exit
    Tránh tạo duplicate instance khi click taskbar icon hoặc chạy exe lần 2
- **WindowListener**: `onWindowClose` trong HomeScreen (macOS), `onWindowEvent` (Windows)
  Cache `_closeBehavior` trong initState, KHÔNG async đọc file trong callback
  `HomeScreen.updateCloseBehavior(value)` sync khi user đổi setting
- **Linux CI**: cần `libayatana-appindicator3-dev` (đã thêm vào workflow)

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
    Relaunch dùng `Start-Process ('shell:AppsFolder\' + PackageFamilyName + '!App')`
    KHÔNG dùng `explorer.exe` (sẽ mở OneDrive/Documents thay vì app)
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
- **Selective Pull** (chỉ Odoo Projects) — **UI đã ẩn** (code giữ nguyên, dùng Workspace View thay thế):
  - Scan `addons/` tìm repos có `.git`, user search + chọn repos cụ thể qua Autocomplete
  - Selection persist vào settings (`selectivePull_<projectPath>`)
  - Nút Clear list + remove từng repo, Pull chạy tuần tự cho repos đã chọn
  - Ẩn ở 3 nơi: grid card, list view, context menu (comment out, không xóa code)
- **Git Commit**:
  - Other Projects: `git status --porcelain` → checkbox list files → `git add --` từng file → `git commit` → optional `git push`
  - Odoo Projects: scan `addons/` tìm repos có changes → checkbox list repos → `git add -A` + `git commit` + optional `git push` cho mỗi repo
  - Reload status sau khi commit để hiện file/repo còn lại
- **Git Repositories Script** (`git-repositories.sh` / `.ps1`):
  - Template trong `odoo_templates.dart` với params `token` và `org`
  - Tạo tự động khi Quick Create Odoo project
  - Token đọc từ Git account (dropdown chọn account), org nhập khi tạo project
  - Edit project (Info dialog > Edit): dropdown chọn account + sửa org, save vào file script
- **Git Branches Dialog** (Other Projects — `_SwitchBranchDialog`):
  - Stateful dialog 2 cột: Local + Remote, click branch để switch
  - Tính năng: Switch, Create (`git checkout -b`), Delete (`git branch -d/-D`), Clean stale (`git fetch --prune` + tìm gone branches), Commit, Pull, PR, Publish
  - **Action bar** (giữa dialog): Pull, Commit, PR (ẩn khi trên main/master), + Create
  - **Pull branch khác** (icon trên mỗi branch tile): stash → checkout target → pull → checkout back → stash pop, mở dialog log
  - **Publish branch**: `git push -u origin <branch>`, hiện khi branch chưa có remote, tự ẩn sau publish
  - **Create PR** (`_CreatePRDialog`): check `gh` CLI, chọn base branch, nhập title/body, auto push trước
    Detect PR đã tồn tại (URL từ stderr) → hiện "PR already exists. New commits have been pushed."
    Check uncommitted changes → cảnh báo + cho commit trước hoặc continue
    Nút "View in Browser" mở PR URL (cross-platform: open/start/xdg-open)
  - **Divider** tách main/master xuống cuối danh sách local và remote
  - **Current branch chip** hiện trong title dialog
  - **Mouse cursor** pointer cho branch tiles (dùng `InkWell.mouseCursor`, KHÔNG `MouseRegion`)
  - Branch chip hiện ở giữa card (trên tên project), type badge lên top-left grid card
  - Màu theo branch: main/master=xanh lá, dev=cam, feature/feat=xanh dương, hotfix/fix=đỏ
  - Không cho delete main/master
  - Parse branches dùng `%(refname)` (KHÔNG `%(refname:short)`)
- **Vị trí UI**: List view (IconButton), Grid view (chỉ Git Pull, commit trong context menu), Context menu (đầy đủ)
  Selective Pull đã ẩn khỏi cả 3 nơi (comment out), dùng Workspace View thay thế
- **Log output**: Dùng `Text.rich` (KHÔNG dùng `RichText`) trong `SelectionArea` để copy text được
  `RichText` là render-level widget, không tham gia `SelectionArea`. `Text.rich` wrapper đúng cách
- **Parse git status**: Dùng `substring(0,2)` cho status + `substring(3)` cho filename.
  QUAN TRỌNG: output phải dùng `.trimRight()` (KHÔNG dùng `.trim()` vì sẽ xóa space đầu dòng đầu tiên → mất ký tự status)
  Handle rename format `old -> new`
- **git add**: Add từng file một với `git add -- <file>` (tránh shell argument issues khi nhiều files)
- **Commit message**: TextField với `minLines: 3`, `maxLines: 8` (tự scroll khi vượt 8 dòng, KHÔNG dùng `maxLines: null` sẽ overflow)

## Lưu trữ dữ liệu
Tất cả data lưu tại: `~/.config/odoo_auto_config/odoo_auto_config.json`
Gồm: profiles, projects, workspaces, registered_venvs, settings
Settings gồm: theme, locale, gridView, nginx (confDir, domainSuffix, containerName),
  gitAccounts (danh sách accounts), defaultGitAccount, gitToken (tương thích ngược),
  selectivePull_<path> (selection per project)

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
bash release.sh          # auto bump patch: 1.1.3 → 1.1.4
bash release.sh minor    # bump minor: 1.1.3 → 1.2.0
bash release.sh major    # bump major: 1.1.3 → 2.0.0
bash release.sh 2.0.0    # chỉ định version cụ thể

# Release (Windows PowerShell)
.\release.ps1            # auto bump patch
.\release.ps1 minor
.\release.ps1 2.0.0
```

## Đa ngôn ngữ (i18n)
- **Ngôn ngữ hỗ trợ**: English (default), Vietnamese (`vi`), Korean (`ko`)
- **ARB files**: `lib/l10n/app_en.arb`, `app_vi.arb`, `app_ko.arb`
- **Generated files**: `lib/l10n/app_localizations*.dart` (KHÔNG sửa thủ công)
- **Extension**: `context.l10n.keyName` qua `lib/l10n/l10n_extension.dart`
- **Log messages**: giữ nguyên tiếng Anh (technical output)
- Khi thêm string mới: thêm vào cả 3 file ARB, chạy `fvm flutter gen-l10n`. KHÔNG BAO GIỜ hardcode string user-visible
- Lưu ý dịch thuật: "Theme Mode" tiếng Việt là "Tùy chỉnh giao diện" (không phải "Chế độ giao diện")
- **Thuật ngữ Git/tech giữ nguyên English cả 3 ngôn ngữ** — KHÔNG dịch:
  Pull, Push, Commit, Merge, Branch, Checkout, Stash, Rebase, Cherry-pick,
  PR, Create Branch, Delete Branch, Force Delete, Clean stale, Publish,
  Setup Nginx, Docker, PostgreSQL...
  Developer dùng hàng ngày bất kể ngôn ngữ, dịch ra sẽ gây nhầm lẫn.
- **Mô tả ngữ cảnh/mục đích** thì dịch theo ngôn ngữ:
  VD: "Cập nhật {current} với code từ {source}" (VI), "Update {current} with code from {source}" (EN)

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
- **Docker install**: dialog cho chọn OrbStack (mặc định) hoặc Docker Desktop
  OrbStack: `brew install --cask orbstack`, Docker Desktop: `brew install --cask docker`
  Lưu lựa chọn vào settings `dockerRuntime` (`'orbstack'` hoặc `'docker'`)
- **Start Docker**: `DockerInstallService.startDaemon()` — đọc `dockerRuntime` từ settings
  Ưu tiên app đã chọn, fallback app còn lại. Mặc định = orbstack
  Dùng `open -a <AppName>` — KHÔNG check path `/Applications/` (miss nếu cài external drive)
  Tất cả screens gọi chung `startDaemon()` — 1 chỗ sửa, cả app cập nhật

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
- Windows system tray: đã test OK (2026-04-05) — hide to tray, show from tray, single instance, exit mode

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
- **Project Info dialog gộp**: Info + Edit + Nginx + Database trong 1 dialog. Toggle edit mode bằng icon bút chì.
  Không còn nút Edit riêng. `_ImportProjectDialog` chỉ dùng cho import
- **Hidden screens**: Python Check và VSCode Config ẩn khỏi NavigationRail nhưng giữ code
  (Python Check nhúng vào Settings > Python, VSCode Config có thể dùng riêng nếu cần)

## Tính năng Odoo Workspace View
Dialog chuyên biệt quản lý **pinned repos** trong `addons/` của 1 Odoo project.
File: `lib/screens/odoo_workspace_dialog.dart`
- **Mở từ**: List view (IconButton workspaces), Grid view (grid button), Context menu (Workspace View)
- **Pinned repos**: KHÔNG hiện tất cả repos. User search + add repos quan tâm, persist vào settings
  Storage key: `workspaceRepos_<projectPath>` (danh sách pin), `workspaceSelected_<projectPath>` (selection)
- **Search dropdown**: `RawAutocomplete` — click/focus hiện toàn bộ repos chưa pin, gõ để lọc
  Có nút dropdown arrow + counter `3 / 30`. Giữ focus sau khi add để tiếp tục thêm
- **Mỗi repo hiện**: tên module, branch (color coded), changed files count, ahead/behind, nút Pull/Push/Remove
- **Selection**: ban đầu deselect all, user select repos nào → persist cho lần sau
  Add repo mới → sort A-Z. Remove repo → xóa khỏi cả pin list và selection
- **Lazy loading repos**: Lần mở dialog đầu tiên chỉ load batch 8 repos (`_kBatchSize`),
  scroll gần cuối (200px) → tự động load batch tiếp (`_onScroll` + `_loadNextBatch`).
  Nút Refresh (`_loadPinnedRepos(loadAll: true)`) load tất cả repos cùng lúc.
  Mỗi `_RepoInfo` có flag `loaded` — repo chưa loaded hiện `CircularProgressIndicator` thay vì status.
- **Batch actions toolbar** (dùng `Wrap` để tự xuống dòng):
  - **Pull Selected**: pull tất cả repos đã select
  - **Git Commit**: kiểm tra repos có thay đổi →
    Không có → hiện dialog thông báo "No changes to commit"
    Có → mở `_WorkspaceCommitDialog` riêng (danh sách repos + changed count, message, push after commit, log)
  - **Switch Branch**: dialog chọn branch gộp unique từ tất cả repos, hoặc nhập tên tạo branch mới
    Thử checkout existing → checkout -b từ origin → checkout -b mới
  - **Publish Modules** (`_PublishModulesDialog`): scan addons/ tìm module chưa có `.git`,
    checkbox chọn modules → tạo GitHub repo private trong org, tự tạo `.gitignore`/`README.md` nếu thiếu,
    git init → add → commit → push. Đọc org/token từ `git-repositories.sh`/`.ps1`.
    Handle: repo đã tồn tại (422), remote đã có (set-url), thiếu org/token (hiện lỗi).
    Sau đóng dialog → reload workspace view.
- **Log output**: ANSI color coded, auto-scroll, SelectionArea + Text.rich, height 180px
- **Cross-platform**: chỉ dùng `git` commands, `runInShell: true`, `p.join()` cho paths
- **Grid columns** (projects_screen + workspaces_screen): L=4, M=3, S=2. Quick actions dùng `Wrap` thay `Row`
- **Grid card layout** (workspaces): top-left=type badge, top-right=star, giữa=branch chip (clickable), dưới=tên project

### Roadmap — Chưa triển khai
- **Cherry-pick**: Chọn 1 hoặc nhiều commits cụ thể từ branch khác để copy vào branch hiện tại
  UI: click branch → hiện danh sách commits (`git log --oneline <current>..<target>`) → checkbox chọn → cherry-pick tuần tự
  Dùng `git cherry-pick <hash>`, hiện dialog log output, xử lý conflict
- **File system watcher**: `Directory.watch()` chỉ watch `addons/` của project đang mở, tự refresh khi file thay đổi
- **Switch Branch filter**: chỉ hiện branches chung giữa các repos (hiện gộp unique)
- **Lưu ý**: Flutter multi-window phức tạp, file watcher khác nhau trên 3 OS

## Lessons Learned — KHÔNG lặp lại các lỗi này

### UI / Layout
- **KHÔNG hardcode số** cho size/spacing/font — luôn dùng `AppFontSize`, `AppIconSize`, `AppSpacing`, `AppRadius`, `AppDialog`
- **Grid card top row** dùng `Stack` + `Align` cho elements ở các góc (branch top-left, star top-right).
  KHÔNG dùng `Row` + `Spacer`/`Flexible` — gây lỗi vị trí khi có/không có conditional children
- **Dialog responsive** dùng `Builder` + `MediaQuery.of(context).size.width`.
  KHÔNG dùng `LayoutBuilder` trong `AlertDialog.content` → lỗi "Cannot hit test a render box with no size"
  Rộng (>900px): 2 cột + `widthLg`. Hẹp: 1 cột stacked + `widthMd`
- **TextField commit message**: `maxLines: 8`, `minLines: 3`. KHÔNG dùng `maxLines: null` → overflow layout
- **`Text.rich`** thay `RichText` trong `SelectionArea` để copy text được.
  `RichText` là render-level widget, không tham gia `SelectionArea`
- **`SingleChildScrollView` + `Column`** thay `ListView.builder` cho text selection
- **`GestureDetector`** wrap cả Checkbox + label để click label cũng toggle
- **Output-log luôn mở dialog riêng** — KHÔNG nhúng inline. Dùng `_GitActionDialog` pattern:
  auto-run khi mở, `LinearProgressIndicator`, `SelectionArea` + `Text.rich` cho copy text,
  ANSI color parsing, auto-scroll, Close disabled khi running
- **SnackBar bị chìm sau dialog** — dùng dialog thông báo thay SnackBar khi context đang có dialog mở

### Git operations
- **Parse `git status --porcelain`**: dùng `.trimRight()` KHÔNG `.trim()` — sẽ xóa space đầu dòng đầu = mất status char
- **`git add`**: add từng file một với `git add -- <file>` (tránh shell argument issues khi nhiều files + `runInShell: true`)
- **Parse branches**: dùng `git branch -a --format=%(refname)` KHÔNG `%(refname:short)` — vì `origin` bị lọt vào local
  `refs/heads/` → local, `refs/remotes/origin/` → remote
- **Highlight branch**: chỉ highlight current ở cột local (`!isRemote && branch == _current`)

### Auto-update
- **macOS**: dùng `.zip` + `ditto -xk` KHÔNG dùng `.dmg` (mount/unmount/codesign phức tạp và hay fail)
  `xattr -cr` là đủ, KHÔNG cần `codesign`
- **Windows MSIX**: `Add-AppPackage -ForceApplicationShutdown` + relaunch qua `Start-Process ('shell:AppsFolder\' + PackageFamilyName + '!App')`
  KHÔNG dùng `explorer.exe shell:AppsFolder\` (mở nhầm OneDrive/Documents thay vì app)
  KHÔNG dùng `Platform.resolvedExecutable` vì MSIX thay đổi exe path mỗi version
- **`msix_version`**: KHÔNG hardcode — để package `msix` tự derive từ `version` field trong pubspec.yaml
- **CI zip path**: `ditto` output phải nằm trong `build/` (không dùng `cd` + relative path → sai vị trí)

### Code quality
- **`fvm flutter analyze` phải luôn "No issues found!"** — fix TẤT CẢ issues, kể cả info level (curly_braces, unused vars...)
  KHÔNG BAO GIỜ bỏ qua với lý do "chỉ là info warning"
- **`StorageService.saveSettings` PHẢI load trước rồi merge** — KHÔNG BAO GIỜ ghi đè toàn bộ settings
  Pattern đúng: `final settings = await StorageService.loadSettings(); settings['key'] = value; await StorageService.saveSettings(settings);`
  Bug đã xảy ra: ThemeService ghi đè toàn bộ settings → mất nginx config, git accounts, workspace repos
- **`StorageService` có `_synchronized` lock** — serialize tất cả write operations để tránh race condition
  Nếu 2 save chạy đồng thời (VD: saveSettings + saveWorkspaces), operation sau đọc config cũ → ghi đè mất data
  Tất cả save/add/remove methods đều wrap trong `_synchronized`, read-modify-write trong cùng 1 lock
- **Xóa project/workspace phải cleanup nginx** — nếu `hasNginx` thì gọi `NginxService.removeNginx(sub)` trước khi xóa
  Wrap try-catch để không block việc xóa nếu nginx cleanup fail
- Khi edit workspace/project: phải preserve `favourite` và `nginxSubdomain` từ object gốc (dùng `copyWith`)
- **Dialog reload**: Khi dialog con đóng (VD: Commit dialog đóng → quay lại Branches dialog), phải reload status trong dialog cha.
  Khi dialog cha đóng, phải reload data ở parent screen (dùng `.then()` sau `showDialog`)
- **Branch status trên grid/list**: hiện `changed count ↑` (cam) + `behind count ↓` (cyan) cạnh branch name
  Load async song song với branch detection trong `_loadBranches`
  `git status --porcelain` cho changed, `git rev-list --count HEAD..@{upstream}` cho behind (sau `git fetch --quiet`)

### System Tray (Windows)
- **`window_manager 0.5.1` + Flutter 3.41**: `setPreventClose(true)` KHÔNG hoạt động trên Windows
  Plugin intercept `WM_CLOSE` nhưng `onWindowClose` Dart callback không bao giờ fire
  PHẢI xử lý `WM_CLOSE` ở native C++ (`flutter_window.cpp`) thay vì dựa vào Dart callback
- **KHÔNG dùng `windowManager.setSkipTaskbar()`** trên Windows — gây native crash (process exit không log)
  Chỉ dùng `windowManager.show()` / `windowManager.hide()` / `windowManager.focus()`
- **`SetQuitOnClose(false)`** trong `main.cpp` — bắt buộc khi dùng tray, nếu `true` thì `PostQuitMessage`
  sẽ thoát app ngay khi window bị destroy
- **Phân biệt minimize vs close trên Windows**: dùng flag `_isMinimizing` trong `onWindowEvent`
  `minimize` event fire trước `hide` khi minimize, nhưng KHÔNG fire khi nhấn X → dùng để phân biệt
- **Single instance**: Named mutex trong `main.cpp`, `FindWindow` + `ShowWindow` để activate cái cũ
  Tránh duplicate instance khi click taskbar icon hoặc chạy exe lần 2

### Process / Shell
- **`runInShell: true`** bắt buộc cho mọi `Process.run` trong AOT/release mode
- **`hdiutil`** không có `runInShell: true` → fail im lặng trong release build
- **Shell script template**: header (token/org) dùng string interpolation `'''`, body dùng raw string `r'''` để tránh Dart interpret `$`
