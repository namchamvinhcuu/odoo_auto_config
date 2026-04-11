# Workspace Configuration - Project Context

## Tổng quan
Flutter desktop app (macOS/Linux/Windows) giúp developer thiết lập và quản lý môi trường phát triển.
Hỗ trợ Odoo projects và các dự án ngôn ngữ khác (Flutter, React, NextJS, .NET, Rust, Go, Java...).
Cung cấp GUI để quản lý project, Python/venv, nginx reverse proxy, Docker, và sinh cấu hình VSCode debug.

## Tech Stack
- **Flutter** SDK ^3.9.2 (FVM managed)
- **flutter_riverpod** 2.6.1 - state management (Notifier/AsyncNotifier, tách business logic khỏi UI)
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

> Chi tiết cây thư mục + mô tả chức năng từng file: xem **[STRUCTURE.md](STRUCTURE.md)**
> File đó được cập nhật tự động mỗi khi thêm/bớt file.

## Navigation (4 tabs)
1. **Odoo Projects** - odoo_projects/odoo_projects_screen.dart (class OdooProjectsScreen, icon: folder_special)
2. **Other Projects** - other_projects/other_projects_screen.dart (class OtherProjectsScreen, icon: workspaces)
3. **Profiles** - profile/profile_screen.dart (icon: person)
4. **Settings** - settings/settings_screen.dart (icon: settings)
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
- **Package imports** — LUÔN dùng `package:odoo_auto_config/` thay vì relative `../`
  VD: `import 'package:odoo_auto_config/providers/theme_provider.dart'` thay vì `import '../../providers/theme_provider.dart'`
  Chỉ dùng relative cho sibling files cùng thư mục (VD: `import 'docker_tab.dart'`)
  KHÔNG dùng barrel files — import chính xác file cần dùng
- **Immutable models** với `fromJson()`/`toJson()` + `copyWith()` (nullable field dùng `Function()`)
- **Stateless services** - static methods, không giữ state
- **Riverpod** — state management: `Notifier` cho sync state (theme, locale), `AsyncNotifier` cho async data (profiles, projects...)
  `ConsumerWidget` cho stateless screens, `ConsumerStatefulWidget` cho screens cần UI controllers (TabController, TextEditingController...)
  Business logic trong `lib/providers/`, UI chỉ watch state + dispatch actions. KHÔNG dùng `StateNotifier` (legacy)
  **QUAN TRỌNG**: Trong `Notifier.build()`, KHÔNG gọi async method trực tiếp (sẽ crash "uninitialized provider").
  Phải dùng `Future.microtask(() => asyncMethod())` để schedule sau khi build() return:
  ```dart
  @override
  MyState build() {
    Future.microtask(() => loadData()); // ĐÚNG
    // loadData(); // SAI — state chưa sẵn sàng
    return const MyState();
  }
  ```
- **Real-time logging** - LogOutput widget auto-scroll, color-coded, SelectionArea wrap riêng
- **SelectionArea** - wrap toàn bộ app tại main.dart, cho phép select + copy text bất kỳ
- **Dialog-based workflows** - Quick Create, Edit, Nginx Setup, Install Python/Docker/mkcert
- **AppDialog.show()** - LUÔN dùng `AppDialog.show()` thay `showDialog()` cho mọi dialog trong app.
  Tự động wrap `barrierDismissible: false` + `PopScope(canPop: false)` → không đóng bằng click ngoài hoặc ESC.
  Tự động wrap `_DraggableDialog` → tất cả dialog có thể kéo di chuyển bằng drag.
  Sửa 1 chỗ (`app_constants.dart`) áp dụng cho tất cả dialog.
- **Dialog close button** - `AppDialog.closeButton(context)`: icon X, nền đỏ, chữ trắng, góc trên bên phải
  Hỗ trợ `enabled:` (default true) — khi `false`: button xám, không bấm được (dùng khi process đang chạy).
  Hỗ trợ `onClose:` để custom close behavior (VD: return value khi pop).
  KHÔNG dùng footer Close/Cancel button nữa.
  Close-only dialog: xóa `actions:`, thêm closeButton vào title Row
  Cancel+Action dialog: xóa Cancel, thêm closeButton vào title Row, giữ action button trong `actions:`
  Dialog có process: `AppDialog.closeButton(context, enabled: !_running)` để chặn đóng giữa chừng
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
- Check GitHub CLI (gh) installed → nếu chưa có → tự động install (brew/winget/apt)
- `HomeScreen.navigateToSettings(settingsTab: N)` để chuyển tab từ bất kỳ screen nào
  (VD: bấm Setup Nginx khi chưa config → tự động chuyển sang Settings > Nginx tab)

## Tính năng System Tray (Multi-Instance)
- **Package**: `system_tray 2.0.3` — macOS, Windows, Linux
- **Icon**: `assets/tray_icon.png` (512x512, package tự resize), `.ico` cho Windows
  `title: ''` — chỉ hiện icon, KHÔNG hiện text cạnh icon
- **Single tray icon**: chỉ instance đầu tiên (tray owner) tạo tray icon
  Các instance khác skip tray init. Tray owner xác định bằng `.tray.lock` file lock.
- **Close behavior**: luôn minimize to tray (không có lựa chọn "Exit app")
  Click X → `TrayService.hideToTray()` → `windowManager.hide()`
  HomeScreen `onWindowClose` luôn gọi `hideToTray()` (macOS/Linux)
  Windows: native WM_CLOSE trong `flutter_window.cpp` hide window, không cần xử lý thêm ở Dart
- **Tray menu** (SubMenu style):
  ```
  Show  ▸  Instance 1, Instance 2, ...
  ──────────
  New Window
  ──────────
  Quit All
  ```
- **Events**: click/double-click → show tray owner's window, right-click → menu
- **Hỗ trợ**: macOS + Windows + Linux. `TrayService.supported` = tất cả desktop
- **macOS**: dùng `windowManager.setPreventClose(true)` + `onWindowClose` callback
  `applicationShouldTerminateAfterLastWindowClosed` PHẢI return `false`
- **Windows**: xử lý `WM_CLOSE` ở native C++ level
  `flutter_window.cpp`: `case WM_CLOSE: ShowWindow(hwnd, SW_HIDE); return 0;`
  `main.cpp`: `SetQuitOnClose(false)` — QUAN TRỌNG
  **KHÔNG dùng `setSkipTaskbar`** trên Windows — gây native crash
- **Multi-instance**: Không còn single-instance enforcement
  Windows: đã xóa mutex. Linux: `G_APPLICATION_NON_UNIQUE`
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
- **Git Branches Dialog** — shared `GitBranchDialog` (`lib/widgets/git_branch_dialog.dart`):
  - Dùng chung cho cả Other Projects (`SwitchBranchDialog` wrapper) và Odoo Workspace (`RepoBranchDialog` wrapper)
  - Sub-dialogs inject qua builder callbacks: `pullDialogBuilder`, `commitDialogBuilder`, `prDialogBuilder`, `pruneDialogBuilder`
  - Stateful dialog 2 cột: Local + Remote, click branch để switch
  - Tính năng: Switch, Create (`git checkout -b`), Delete (`git branch -d/-D`), Clean stale (`git fetch --prune` + tìm gone branches), Commit, Pull, PR, Publish, View on GitHub
  - **Action bar** (giữa dialog): Pull (disable khi không có remote), Commit (disable khi không có changes), PR (ẩn khi trên main/master), + Create
  - **View on GitHub**: button trên title bar, `GitBranchService.getRemoteUrl()` (SSH→HTTPS conversion) + `openInBrowser()`
  - **Pull branch khác** (icon trên mỗi branch tile): stash → checkout target → pull → checkout back → stash pop, mở dialog log
  - **Publish branch**: `git push -u origin <branch>`, hiện khi branch chưa có remote, tự ẩn sau publish
  - **Create PR** (`CreatePRDialog` / `RepoCreatePRDialog`): check `gh` CLI, chọn base branch, nhập title/body, auto push trước
    Proactive diff check: `git fetch origin <base>` + `git rev-list --count origin/<base>..HEAD` khi mở dialog + khi đổi base
    Nếu no changes → hiện inline "There are no changes" UI, ẩn form title/body/create
    Dropdown base branch: filter `origin/` prefix đúng cách, lọc current branch ra khỏi list
    Detect PR đã tồn tại (URL từ stderr) → hiện "PR already exists. New commits have been pushed."
    Check uncommitted changes → cảnh báo + cho commit trước hoặc continue
    Nút "View in Browser" mở PR URL (cross-platform: open/start/xdg-open)
  - **GH CLI Authentication** — 3 cấp ưu tiên:
    1. `gh auth login` (native auth) → KHÔNG truyền `GH_TOKEN`, để gh tự quản lý (hỗ trợ `gh auth switch` multi-account)
    2. Project-specific token (chỉ Odoo) → đọc TOKEN từ `git-repositories.sh`/`.ps1` trong project root
       `RepoCreatePRDialog` derive project path: `p.dirname(p.dirname(repoPath))` (addons/repoName → project root)
    3. Default account token → `StorageService.getDefaultGitToken()`
    4. Không có gì → hiện warning icon `key_off` + mô tả + nút "Go to Git Settings" (tab 5)
    Check auth: `gh auth status` (exitCode 0 = đã login). `GH_TOKEN` env var chỉ truyền khi gh chưa native authed
    Pattern: `environment: (!_ghNativeAuth && _token != null) ? {'GH_TOKEN': _token!} : null`
    `hasOpenPR` trong `git_branch_service.dart` cũng check `gh auth status` trước khi pass `GH_TOKEN`
  - **GH CLI path (Windows MSIX)**: `PlatformService.ghPath` có fallback `where.exe gh` khi `File.exists()` không tìm thấy
    (MSIX app có thể không thấy file qua `File.exists()` dù file tồn tại)
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

### Tất cả OS — VÔ CÙNG QUAN TRỌNG
- **Process.run / Process.start PHẢI có `runInShell: true`** (AOT mode)
  Không có → fail im lặng trên release build cả 3 OS. Debug mode có thể chạy bình thường → dễ bỏ sót
  **SAU MỖI REFACTOR**: chạy audit script kiểm tra toàn bộ codebase:
  ```bash
  python3 -c "
  import re, glob
  files = glob.glob('lib/**/*.dart', recursive=True)
  for f in files:
      with open(f) as fh:
          lines = fh.readlines()
      i = 0
      while i < len(lines):
          line = lines[i]
          if 'Process.run(' in line or 'Process.start(' in line:
              call = line; j = i + 1
              pc = line.count('(') - line.count(')')
              while pc > 0 and j < len(lines):
                  call += lines[j]; pc += lines[j].count('(') - lines[j].count(')'); j += 1
              if 'runInShell' not in call:
                  print(f'{f}:{i+1}: {line.strip()[:80]}')
          i += 1
  "
  ```
- window_manager cần **full restart** (không hot reload) khi thêm mới
- App icon cần `flutter clean` + rebuild sau khi thay đổi
- External binaries PHẢI resolve qua PlatformService (dockerPath, ghPath, mkcertPath, pythonCandidates, ...)
- **KHÔNG BAO GIỜ hardcode separator `/` hoặc `\` khi nối đường dẫn local file system**
  Luôn dùng `p.join()` từ `package:path/path.dart` (import as `p`)
  VD: `p.join(baseDir, 'conf.d')` thay vì `'$baseDir/conf.d'`
  `p.dirname(path)` thay vì `path.substring(0, path.length - N)`
  CHỈ NGOẠI LỆ: paths bên trong Docker container (nginx conf, docker-compose volumes) luôn dùng `/` vì container là Linux
- **Process output (winget/brew/apt)**: dùng `utf8.decoder` thay vì `SystemEncoding().decoder`
  Dùng `CommandRunner.cleanLine()` để strip ANSI codes, spinner chars, và progress bars
- **StorageService.updateSettings()** — LUÔN dùng cho write settings (atomic trong _synchronized lock)
  KHÔNG dùng pattern cũ `loadSettings → modify → saveSettings` (race condition giữa các provider)

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
- **VSCode settings.json**: Quick Create tự động tạo `.vscode/settings.json` cùng `launch.json`
  Template trong `OdooTemplates.vscodeSettings()`. Nội dung: `python.analysis.extraPaths` (../odoo, ../odoo/addons, ../addons),
  `files.exclude` (*.pyc, __pycache__, .venv), `files.watcherInclude`, `python.languageServer: "None"`

## Tính năng Odoo Workspace View
Dialog chuyên biệt quản lý **pinned repos** trong `addons/` của 1 Odoo project.
File: `lib/screens/odoo_workspace_dialog.dart`
- **Mở từ**: List view (IconButton workspaces), Grid view (grid button), Context menu (Workspace View)
- **Pinned repos**: KHÔNG hiện tất cả repos. User search + add repos quan tâm, persist vào settings
  Storage key: `workspaceRepos_<projectPath>` (danh sách pin), `workspaceSelected_<projectPath>` (selection)
- **Search dropdown**: `RawAutocomplete` — click/focus hiện toàn bộ repos chưa pin, gõ để lọc
  Có nút dropdown arrow + counter `3 / 30`. Giữ focus sau khi add để tiếp tục thêm
- **Mỗi repo hiện**: tên module, branch (color coded, clickable → mở branch dialog), changed files count, ahead/behind, nút Pull/Publish hoặc Push/Remove
- **`_RepoInfo.hasUpstream`**: detect qua `git rev-list @{upstream}..HEAD` — nếu fail → `hasUpstream = false`
  Repo không có upstream hiện nút Publish (cloud_upload xanh lá) thay vì Push
- **Per-repo Branch Dialog** (`RepoBranchDialog`): thin wrapper → shared `GitBranchDialog`
  Inject `RepoGitPullDialog`, `RepoCommitDialog`, `RepoCreatePRDialog`, `RepoPruneDialog`
  Sau đóng dialog → reload repo status
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
  - **Switch Branch** — **ẨN** (comment out, code giữ nguyên `_switchBranchAll` + `_BranchPickerDialog`):
    dialog chọn branch gộp unique từ tất cả repos, hoặc nhập tên tạo branch mới
    Thử checkout existing → checkout -b từ origin → checkout -b mới
    Lý do ẩn: chưa có nhu cầu dùng, dùng per-repo branch dialog thay thế
  - **Publish Branch**: hiện khi có selected repos chưa có upstream → batch `git push -u origin`
  - **Publish Modules** (`_PublishModulesDialog`): scan addons/ tìm module chưa có `.git`,
    checkbox chọn modules → tạo GitHub repo private trong org, tự tạo `.gitignore`/`README.md` nếu thiếu,
    git init → add → commit → push. Đọc org/token từ `git-repositories.sh`/`.ps1`.
    Handle: repo đã tồn tại (422), remote đã có (set-url), thiếu org/token (hiện lỗi).
    Sau đóng dialog → reload workspace view.
- **Log output**: ANSI color coded, auto-scroll, SelectionArea + Text.rich, height 180px
- **Cross-platform**: chỉ dùng `git` commands, `runInShell: true`, `p.join()` cho paths
- **Grid columns** (odoo_projects_screen + other_projects_screen): L=4, M=3, S=2. Quick actions dùng `Wrap` thay `Row`
- **Grid card layout** (other_projects): top-left=type badge, top-right=star, giữa=branch chip (clickable), dưới=tên project

### Refactoring — Đã hoàn thành
Branch: `refactor/core-clean-structure`
- Phase 1: tách dialog ra file riêng, rename projects→odoo_projects, workspaces→other_projects
- Phase 2: Riverpod migration — 8 providers, tất cả screens dùng ConsumerWidget/ConsumerStatefulWidget
- Phase 3: tách settings tabs (6 tab files), ANSI shared utility, GitBranchService, list/grid view widgets
- Kết quả: không còn file code nào > 1000 dòng (trừ l10n generated)

### Roadmap — Chưa triển khai
- **Cherry-pick**: Chọn 1 hoặc nhiều commits cụ thể từ branch khác để copy vào branch hiện tại
  UI: click branch → hiện danh sách commits (`git log --oneline <current>..<target>`) → checkbox chọn → cherry-pick tuần tự
  Dùng `git cherry-pick <hash>`, hiện dialog log output, xử lý conflict
- **File system watcher**: `Directory.watch()` chỉ watch `addons/` của project đang mở, tự refresh khi file thay đổi
- **Switch Branch filter**: chỉ hiện branches chung giữa các repos (hiện gộp unique)
- **Lưu ý**: Flutter multi-window phức tạp, file watcher khác nhau trên 3 OS

### Multi-Instance — Đang triển khai
Cho phép mở nhiều cửa sổ app (separate processes) để thao tác nhiều projects cùng lúc.

**Kiến trúc:**
- Mỗi instance là 1 OS process riêng (Flutter không hỗ trợ true multi-window)
- **Single tray icon** — instance đầu tiên giữ quyền via file lock, các instance khác không tạo tray
- **Close behavior forced = "tray"** — bỏ lựa chọn "Exit app", luôn minimize to tray
- **Quit = Quit All** — tắt tất cả instances cùng lúc
- **File-based IPC** — giao tiếp giữa instances qua file system

**IPC Directory** (`~/.config/odoo_auto_config/instances/`):
- `<pid>.json` — registry mỗi instance: `{pid, label, started}`
- `.tray.lock` — exclusive file lock (tray owner giữ open)
- `<pid>.show` — signal file: show window của instance đó
- `.quit_all` — signal file: tất cả instances exit

**Tray menu** (submenu style):
```
Show  ▸  Instance 1
         Instance 2
──────────
New Window
──────────
Quit All
```

**Tray ownership:**
- Startup: try acquire `.tray.lock` (exclusive). Thành công → init tray, làm tray owner
- Thất bại → skip tray init (instance khác đã owns)
- Click/double-click tray icon → show tray owner's window
- Tray owner watch `instances/` directory → rebuild menu khi instance thêm/bớt

**Show signaling:**
- Tray owner tạo file `<pid>.show` → target instance detect via `Directory.watch()` → show window → delete file

**Quit All signaling:**
- Tray owner tạo `.quit_all` → tất cả instances detect → cleanup → `exit(0)`

**Instance launcher** (`InstanceService.launchNewInstance()`):
- macOS: chạy binary trực tiếp với `--child-instance` flag (`ProcessStartMode.detached`)
  AppDelegate detect flag → set `NSApp.setActivationPolicy(.accessory)` → child KHÔNG hiện Dock icon
  KHÔNG dùng `open -n -a` vì tạo LaunchServices instance riêng → 2 Dock icons
- Windows: `Platform.resolvedExecutable` trực tiếp (bypass MSIX App Model single-instance)
  KHÔNG dùng `shell:AppsFolder` — chỉ activate cửa sổ cũ, không tạo instance mới
- Linux: `$APPIMAGE` hoặc `Platform.resolvedExecutable`
- UI: nút "New Window" trong NavigationRail + trong tray menu

**Cross-process storage:**
- `StorageService._synchronized()` dùng cả in-process Future lock + cross-process `RandomAccessFile.lock(FileLock.exclusive)`
- Lock file: `~/.config/odoo_auto_config/.lock`
- `_readConfig()` có retry 1 lần khi JSON bị corrupt (instance khác đang write) → tránh crash

**Stale PID cleanup** (crash recovery):
- macOS/Linux: `kill -0 <pid>` (exit code 0 = alive)
- Windows: `tasklist /FI "PID eq <pid>"`
- Dead PIDs → xóa `.json` registry file

**Native changes:**
- Windows `main.cpp`: xóa mutex `WorkspaceConfiguration_SingleInstance`
- Linux `my_application.cc`: `G_APPLICATION_DEFAULT_FLAGS` → `G_APPLICATION_NON_UNIQUE`
- macOS: không thay đổi native (dùng `open -n` để mở instance mới)

**Files chính:**
- `lib/services/instance_service.dart` — **MỚI**: registry, IPC, PID check, launch
- `lib/services/tray_service.dart` — **REFACTOR LỚN**: ownership, submenu, watcher, signals
- `lib/services/storage_service.dart` — thêm cross-process file lock
- `lib/screens/home_screen.dart` — always hide-to-tray, nút "New Window"
- `lib/screens/settings/theme_tab.dart` — xóa close behavior toggle
- `lib/providers/theme_provider.dart` — hardcode closeBehavior='tray'

**Future enhancements (chưa làm):**
- Per-instance quit (submenu Quit ▸ [Instance 1, ..., All]) + auto-transfer tray ownership
- Instance label hiện tên project/tab thay vì "Instance N"
- Settings sync giữa instances via file watcher

## Quy tắc làm việc
- **Sau mỗi task hoàn thành**: LUÔN tóm tắt những gì đã thay đổi + liệt kê danh sách đầy đủ các file đã sửa

## Lessons Learned — KHÔNG lặp lại các lỗi này

### UI / Layout
- **KHÔNG BAO GIỜ hardcode số** cho UI dimensions — luôn dùng constants từ `app_constants.dart`:
  **Spacing**: `AppSpacing.xxs(2)/xs(4)/sm(8)/md(12)/lg(16)/xl(20)/xxl(24)/xxxl(32)`
  **Font**: `AppFontSize.xs(11)/sm(12)/md(13)/lg(16)/xl(17)/xxl(18)/title(28)`
  **Icon**: `AppIconSize.sm(14)/md(16)/statusIcon(18)/lg(24)/xl(28)/xxl(40)/xxxl(48)/feature(64)`
  **Radius**: `AppRadius.sm(4)/md(8)/lg(12)/xl(24)` + `smallBorderRadius/mediumBorderRadius/largeBorderRadius`
  **Dialog width**: `AppDialog.widthSm(500)/widthMd(700)/widthLg(800)/widthXl(900)`
  **Dialog height**: `AppDialog.heightSm(400)/heightMd(450)/heightLg(700)/heightXl(750)`
  **List container**: `AppDialog.listHeightSm(120)/listHeight(150)`
  **Log output**: `AppDialog.logHeightSm(180)/logHeightMd(200)/logHeightLg(250)/logHeightXl(350)`
  **CircularProgressIndicator trong button**: `SizedBox(width: AppIconSize.md, height: AppIconSize.md)`
  Nếu cần giá trị mới → thêm constant vào `app_constants.dart` TRƯỚC, rồi dùng constant đó
- **Dialog content PHẢI wrap `ConstrainedBox` + `SingleChildScrollView`** — tránh overflow khi nội dung dài
  `SingleChildScrollView` + `Column(mainAxisSize: MainAxisSize.min)` KHÔNG tự scroll vì Column request đúng height nó cần.
  PHẢI thêm `ConstrainedBox(maxHeight)` để giới hạn vùng hiển thị, khi đó `SingleChildScrollView` mới scroll được.
  Pattern chuẩn:
  ```dart
  content: SizedBox(
    width: AppDialog.widthLg,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [...]),
      ),
    ),
  ),
  ```
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
- **KHÔNG dùng `showDialog()` trực tiếp** — luôn dùng `AppDialog.show()` để đảm bảo tất cả dialog
  không đóng bằng click ngoài, ESC, và có thể thay đổi behavior tập trung tại 1 chỗ
- **Close button process dialog** — dùng `enabled: !_running` thay vì `onClose: _running ? null : ...`
  Pattern cũ bị bug: khi `onClose: null`, fallback default `Navigator.pop` → vẫn cho đóng

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
- **Windows MSIX relaunch**: KHÔNG dùng `shell:AppsFolder` trong detached PowerShell — không có shell context nên URI không resolve
  Dùng `Get-AppxPackage` → `InstallLocation` → tìm exe → `Start-Process` trực tiếp
  Script phải đợi PID exit trước (như macOS/Linux), dùng `-ForceUpdateFromAnyVersion` cho safety

### Code quality & Cross-platform
- **Windows path có spaces** — `Process.run` tự handle quoting nhưng `Process.start` thì KHÔNG
  PlatformService path getters (`ghPath`, `mkcertPath`) trả về path nguyên bản, **KHÔNG pre-quote**
  Cho `gh` CLI: LUÔN dùng `PlatformService.runGh()` / `PlatformService.startGh()` — helper xử lý:
  Windows + path có spaces → `runInShell: false` (CreateProcess handle spaces đúng)
  macOS/Linux hoặc path không có spaces → `runInShell: true` (cần cho PATH resolution)
- **Dart `replaceFirst` KHÔNG hỗ trợ backreference `$1`** — `$1` được chèn literal, phá hỏng output
  LUÔN dùng `replaceFirstMapped(regex, (m) => '${m[1]}...')` khi cần preserve captured groups
- **`fvm flutter analyze` phải luôn "No issues found!"** — fix TẤT CẢ issues, kể cả info level (curly_braces, unused vars...)
  KHÔNG BAO GIỜ bỏ qua với lý do "chỉ là info warning"
- **SAU MỖI REFACTOR / TẠO FILE MỚI**: chạy audit `runInShell` + path separator cho TOÀN BỘ codebase
  Bug thực tế: refactor lớn tạo 19 Process calls thiếu runInShell — debug chạy OK nhưng release build fail im lặng
- **`StorageService.updateSettings()` — LUÔN dùng cho write settings** — atomic read-modify-write trong `_synchronized` lock
  Pattern đúng: `await StorageService.updateSettings((settings) { settings['key'] = value; });`
  KHÔNG BAO GIỜ dùng pattern cũ `loadSettings → modify → saveSettings` (race condition: 2 provider cùng load → cái sau ghi đè mất data cái trước)
  `loadSettings()` chỉ dùng cho read-only (startup, load preferences)
- **`StorageService` có `_synchronized` lock** — serialize tất cả write operations để tránh race condition
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

### Multi-instance
- **Windows launch**: KHÔNG dùng `shell:AppsFolder` / `Get-AppxPackage` — MSIX App Model single-instance
  chỉ activate cửa sổ cũ, không tạo process mới. Dùng `Platform.resolvedExecutable` trực tiếp để bypass
- **macOS Dock icon**: KHÔNG dùng `open -n -a` để launch child instance (tạo 2 Dock icons)
  Phải chạy binary trực tiếp với `--child-instance` flag + AppDelegate set `.accessory` activation policy
- **Cross-process JSON corruption**: `_readConfig()` PHẢI có try-catch cho `FormatException`
  Khi instance A đang write config JSON, instance B có thể đọc được file bị cắt ngang (partial write)
  → `jsonDecode` throw `FormatException` → crash nếu không catch
  Fix: retry 1 lần sau 100ms delay. Nếu vẫn fail → return empty map (benign failure)
- **Nginx link path**: PHẢI có try-catch quanh `updateProject`/`updateWorkspace`
  Path "link existing" trong `_setupNginx` từng thiếu try-catch → crash khi cross-process write conflict

### Process / Shell
- **`runInShell: true`** bắt buộc cho mọi `Process.run` trong AOT/release mode
- **`hdiutil`** không có `runInShell: true` → fail im lặng trong release build
- **Shell script template**: header (token/org) dùng string interpolation `'''`, body dùng raw string `r'''` để tránh Dart interpret `$`
