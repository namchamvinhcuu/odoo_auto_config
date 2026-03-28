# Workspace Configuration - Project Context

## Overview
Flutter desktop app (macOS/Linux/Windows) giup developer thiet lap va quan ly moi truong phat trien.
Ho tro Odoo projects va cac du an ngon ngu khac (Flutter, React, NextJS, .NET, Rust, Go, Java...).
Cung cap GUI de quan ly project, Python/venv, nginx reverse proxy, Docker, va sinh cau hinh VSCode debug.

## Tech Stack
- **Flutter** SDK ^3.9.2 (FVM managed)
- **Provider** 6.1.0 - state management (ThemeService, LocaleService)
- **file_picker** 8.0.0 - chon thu muc/file (macOS/Linux; Windows dung native PowerShell dialog)
- **path** 1.9.0 - xu ly duong dan cross-platform
- **window_manager** 0.5.1 - control window size, min size, center, animation resize
- **msix** 3.16.13 - build MSIX installer cho Windows
- **flutter_launcher_icons** 0.14.4 - generate app icon da nen tang

## App Name
- Display name: **Workspace Configuration** (tat ca ARB, main.dart, pubspec.yaml, Info.plist)
- Package name: `odoo_auto_config` (giu nguyen, khong anh huong user)
- macOS CFBundleName: "Workspace Configuration" (co dau cach)
- App icon: `workspaces.png` (512x512)

## Architecture
```
lib/
├── main.dart                    # Entry point, Provider setup, window_manager init, SelectionArea
├── constants/app_constants.dart # Design tokens: spacing, font-size, colors, radius, dialog sizes
├── models/                      # Data classes (immutable, fromJson/toJson, copyWith)
│   ├── profile.dart             # Cau hinh Odoo dev profile
│   ├── workspace_info.dart      # Other project (name, path, type, description, favourite, port, nginxSubdomain)
│   ├── project_info.dart        # Odoo project (name, path, ports, description, favourite, nginxSubdomain)
│   ├── venv_info.dart           # Thong tin virtual environment
│   ├── python_info.dart         # Python installation detected
│   ├── command_result.dart      # Ket qua chay process
│   ├── venv_config.dart         # Config tao venv moi
│   └── folder_structure_config.dart # Config tao folder structure
├── services/                    # Business logic (stateless, static methods)
│   ├── storage_service.dart     # Luu tru JSON tai ~/.config/odoo_auto_config/
│   ├── command_runner.dart      # Wrap Process.run() -> CommandResult (runInShell: true)
│   ├── python_checker_service.dart # Detect Python installations (absolute paths + dedup shims)
│   ├── python_install_service.dart # Cross-platform Python install (winget/brew/apt)
│   ├── docker_install_service.dart # Docker install + status check (winget/brew/apt)
│   ├── nginx_service.dart       # Nginx: init project, setup/remove proxy, port check, hosts, mkcert
│   ├── venv_service.dart        # Tao/scan/inspect venv, pip install
│   ├── folder_structure_service.dart # Tao cau truc thu muc Odoo project
│   ├── vscode_config_service.dart   # Sinh .vscode/launch.json (debugpy)
│   ├── theme_service.dart       # Theme mode + accent color (ChangeNotifier)
│   ├── locale_service.dart      # Locale persistence + Provider (ChangeNotifier)
│   └── platform_service.dart    # Platform abstraction (paths, executables, native dialogs)
├── screens/                     # UI screens (StatefulWidget)
│   ├── home_screen.dart         # NavigationRail (4 tab) + window size selector (S/M/L) + animation
│   ├── projects_screen.dart     # Odoo Projects: list/grid, favourite, CRUD, nginx setup/link/remove
│   ├── workspaces_screen.dart   # Other Projects: list/grid, favourite, auto-detect type, nginx
│   ├── quick_create_screen.dart # Dialog tao Odoo project nhanh tu profile
│   ├── profile_screen.dart      # CRUD profiles
│   ├── python_check_screen.dart # (an khoi menu, code giu nguyen)
│   ├── venv_screen.dart         # 3 tabs: list/scan/create venv (nhung trong Settings > Python)
│   ├── vscode_config_screen.dart # Sinh debug config (an khoi menu, code giu nguyen)
│   ├── folder_structure_screen.dart # Tao folder structure doc lap
│   └── settings_screen.dart     # 4 tabs: Theme, Python+Venv, Nginx, Docker
├── widgets/                     # Reusable components
│   ├── status_card.dart         # Card hien thi trang thai
│   ├── directory_picker_field.dart # Text field + browse button
│   ├── log_output.dart          # Real-time log voi color coding + SelectionArea
│   └── nginx_setup_dialog.dart  # Dialog setup nginx (subdomain, port, validation)
└── templates/
    ├── odoo_templates.dart      # Sinh odoo.conf va README.md
    └── nginx_templates.dart     # Sinh nginx conf (odoo/generic), nginx.conf, docker-compose.yml
```

## Navigation (4 tabs)
1. **Odoo Projects** - projects_screen.dart (icon: folder_special)
2. **Other Projects** - workspaces_screen.dart (icon: workspaces)
3. **Profiles** - profile_screen.dart (icon: person)
4. **Settings** - settings_screen.dart (icon: settings)
   - Tab **Theme**: language, theme mode, accent color, preview
   - Tab **Python**: Python installations + install + Venv Manager (nhung VenvScreen)
   - Tab **Nginx**: config record (init/import/edit/delete) + port check (80/443)
   - Tab **Docker**: status + install

> Python Check va VSCode Config **an khoi menu** nhung code giu nguyen.

## Key Patterns
- **Immutable models** voi `fromJson()`/`toJson()` + `copyWith()` (nullable field dung `Function()`)
- **Stateless services** - static methods, khong giu state
- **Provider** chi cho ThemeService, LocaleService (ChangeNotifier)
- **Real-time logging** - LogOutput widget auto-scroll, color-coded, SelectionArea wrap rieng
- **SelectionArea** - wrap toan bo app tai main.dart, cho phep select + copy text bat ky
- **Dialog-based workflows** - Quick Create, Edit, Nginx Setup, Install Python/Docker/mkcert
- **Port conflict detection** - kiem tra trung port giua cac Odoo project
- **Cross-platform** - PlatformService abstract paths; moi service co branch cho 3 OS
- **Responsive layout** - Row cho header (Spacer day nut sang phai), Wrap cho card actions
- **Window size** - 3 preset: Small (800x600 min), Medium (1100x750 default), Large (1400x900)
  Animation ease-out cubic 200ms khi chuyen size, guard chong spam click
- **List/Grid view** - Shared static `ProjectsScreen.gridView`, persisted vao settings JSON
  Grid default, responsive columns: S=3, M=4, L=5. Scale icon/button theo cell width
- **Favourite** - Star icon (IconButton voi hover), sort favourite len dau roi by name A-Z
- **Grid context menu** - Right-click hien menu (favourite, nginx setup/link/remove, VSCode, folder, edit, delete)
- **Grid tooltip** - Hover hien description (hoac path neu khong co description)
- **Auto-detect project type** - Import workspace tu dong nhan dien tu marker files
- **Nginx status** - Luu `nginxSubdomain` vao model JSON (khong derive tu ten project)
  Khi setup: luu subdomain. Khi remove: xoa subdomain. Check bang `hasNginx` getter.

## Nginx Feature
- **Init project**: Tao structure (conf.d/, certs/, nginx.conf, docker-compose.yml, .gitignore)
  Dung mkcert de tao SSL cert. App co the cai mkcert tu dong (brew/winget/apt).
- **Import**: Chon folder nginx co san, tu detect conf.d ben trong
- **Config record**: Chi 1 record duy nhat. Hien info card (confDir, domainSuffix, containerName)
  Co nut Edit (chuyen sang form) va Delete (confirm + option xoa folder)
- **Port check**: Tu dong check port 80/443 khi hien info card
  macOS/Linux: `lsof`, Windows: `netstat + tasklist`. Hien process name + PID
- **Setup per project**: Dialog voi subdomain (fill san, co the sua ngan gon) + port (Other Projects)
  Validation: ky tu hop le (a-z, 0-9, -), trung domain, trung port
- **Link existing**: Chon tu danh sach conf co san trong conf.d/
- **Remove**: Xoa conf file + hosts entry + reload container
- **Hosts file**: macOS (osascript), Linux (pkexec), Windows (PowerShell RunAs/UAC)
- **Conf templates**: Odoo (3 location: /, /websocket, /longpolling), Generic (1 location: /)
- **Docker only**: Khong ho tro nginx cai local (structure khac nhau tuy OS, qua nhieu bien the)

## Persistent Storage
Tat ca data luu tai: `~/.config/odoo_auto_config/odoo_auto_config.json`
Gom: profiles, projects, workspaces, registered_venvs, settings
Settings gom: theme, locale, gridView, nginx (confDir, domainSuffix, containerName)

## Commands
```bash
# Run debug
fvm flutter run -d macos   # hoac linux, windows
# LUU Y: `fvm flutter run macOS` (khong co -d) se bao loi "Target file not found"

# Build release
fvm flutter build macos --release

# Gen l10n (sau khi sua file ARB)
fvm flutter gen-l10n

# Analyze
fvm flutter analyze

# Generate app icons (sau khi doi file icon)
fvm dart run flutter_launcher_icons
# Can flutter clean + restart sau khi doi icon (macOS cache)

# Build DMG
APP_PATH="build/macos/Build/Products/Release/odoo_auto_config.app"
DMG_PATH="build/OdooAutoConfig.dmg"
TMP_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$TMP_DIR/Workspace Configuration.app"
ln -s /Applications "$TMP_DIR/Applications"
hdiutil create -volname "Workspace Configuration" -srcfolder "$TMP_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$TMP_DIR"
```

## Internationalization (i18n)
- **Supported locales**: English (default), Vietnamese (`vi`), Korean (`ko`)
- **ARB files**: `lib/l10n/app_en.arb`, `app_vi.arb`, `app_ko.arb`
- **Generated files**: `lib/l10n/app_localizations*.dart` (DO NOT edit manually)
- **Extension**: `context.l10n.keyName` qua `lib/l10n/l10n_extension.dart`
- **Log messages**: giu nguyen tieng Anh (technical output)
- Khi them string moi: them vao ca 3 file ARB, chay `fvm flutter gen-l10n`
- Luu y dich thuat: "Theme Mode" tieng Viet la "Tuy chinh giao dien" (khong phai "Che do giao dien")

## Cross-Platform Notes

### Tat ca OS
- Process.run PHAI dung `runInShell: true` (AOT mode)
- window_manager can **full restart** (khong hot reload) khi them moi
- App icon can `flutter clean` + rebuild sau khi thay doi

### macOS
- App Sandbox PHAI tat trong ca DebugProfile va Release entitlements
- GUI app khong load ~/.zshrc -> PlatformService tra ve absolute paths
- Open VSCode: `open -a "Visual Studio Code"` (tranh PATH issue)
- Hosts: `osascript` voi `with administrator privileges` (native password dialog)
- Sau khi copy/rename .app: can `xattr -cr` va `codesign --force --deep --sign -`

### Windows
- MSIX can `runFullTrust` capability de Process.run hoat dong
- Native file/folder picker bang PowerShell + COM (IFileOpenDialog)
- Open VSCode: `cmd /c code` (qua PATH)
- Hosts: `C:\Windows\System32\drivers\etc\hosts`, PowerShell `Start-Process -Verb RunAs` (UAC)
- Port check: `netstat -ano` + `tasklist /FI "PID eq ..."`
- Docker/Python install: `winget`
- mkcert install: `winget install FiloSottile.mkcert`

### Linux
- Python install: `pkexec apt install` (graphical sudo, khong can terminal)
- Hosts: `pkexec` (polkit graphical sudo)
- Port check: `lsof -i :PORT`
- Docker install: `pkexec apt install docker.io docker-compose-v2` + systemctl enable

## Design Decisions
- **Nginx Docker only**: Khong ho tro nginx local vi conf structure khac nhau tuy OS/cach cai
- **1 nginx record**: Moi PC chi can 1 container nginx, khong can nhieu record
- **nginxSubdomain luu trong model**: De track status chinh xac, khong phu thuoc ten project
  (user co the dat subdomain khac ten project, VD: "pltax" cho project "polish-tax-odoo")
- **Link existing conf**: Cho phep gan conf da co vao project ma khong tao/sua file
- **Settings tabbed**: Theme / Python+Venv / Nginx / Docker - de mo rong them framework sau
- **Hidden screens**: Python Check va VSCode Config an khoi NavigationRail nhung giu code
  (Python Check nhung vao Settings > Python, VSCode Config co the dung rieng neu can)
