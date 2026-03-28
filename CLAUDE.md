# Odoo Auto Config - Project Context

## Overview
Flutter desktop app (macOS/Linux/Windows) giup developer thiet lap va quan ly moi truong phat trien. Ho tro ca Odoo projects lan cac du an ngon ngu khac (Flutter, React, .NET, Rust, Go, Java...). Cung cap GUI de tao project, quan ly Python/venv, sinh cau hinh VSCode debug, va luu profile tai su dung.

## Tech Stack
- **Flutter** SDK ^3.9.2 (FVM managed)
- **Provider** 6.1.0 - state management (chi dung cho ThemeService, LocaleService)
- **file_picker** 8.0.0 - chon thu muc/file (macOS/Linux; Windows dung native PowerShell dialog)
- **path** 1.9.0 - xu ly duong dan cross-platform
- **window_manager** 0.5.1 - control window size, min size, center
- **msix** 3.16.13 - build MSIX installer cho Windows
- **flutter_launcher_icons** 0.14.4 - generate app icon da nen tang

## Architecture
```
lib/
├── main.dart                    # Entry point, Provider setup, window_manager init, load view pref
├── constants/app_constants.dart # Design tokens: spacing, font-size, colors, radius, dialog sizes
├── models/                      # Data classes (immutable, fromJson/toJson, copyWith)
│   ├── profile.dart             # Cau hinh Odoo dev profile
│   ├── workspace_info.dart      # General workspace (name, path, type, description, favourite)
│   ├── project_info.dart        # Odoo project (name, path, ports, description, favourite)
│   ├── venv_info.dart           # Thong tin virtual environment
│   ├── python_info.dart         # Python installation detected
│   ├── command_result.dart      # Ket qua chay process
│   ├── venv_config.dart         # Config tao venv moi
│   └── folder_structure_config.dart # Config tao folder structure
├── services/                    # Business logic (stateless)
│   ├── storage_service.dart     # Luu tru JSON tai ~/.config/odoo_auto_config/
│   ├── command_runner.dart      # Wrap Process.run() -> CommandResult (runInShell: true)
│   ├── python_checker_service.dart # Detect Python installations (absolute paths + dedup shims)
│   ├── venv_service.dart        # Tao/scan/inspect venv, pip install
│   ├── folder_structure_service.dart # Tao cau truc thu muc Odoo project
│   ├── vscode_config_service.dart   # Sinh .vscode/launch.json (debugpy)
│   ├── python_install_service.dart  # Cross-platform Python install (winget/brew/apt via pkexec)
│   ├── theme_service.dart       # Theme mode + accent color (ChangeNotifier)
│   ├── locale_service.dart      # Locale persistence + Provider (ChangeNotifier)
│   └── platform_service.dart    # Platform abstraction (paths, executables, native dialogs)
├── screens/                     # UI screens (StatefulWidget)
│   ├── home_screen.dart         # NavigationRail + window size selector (S/M/L)
│   ├── projects_screen.dart     # Odoo Projects: list/grid view, favourite, CRUD, quick create
│   ├── workspaces_screen.dart   # Other Projects: list/grid view, favourite, auto-detect type
│   ├── quick_create_screen.dart # Dialog tao Odoo project nhanh tu profile
│   ├── profile_screen.dart      # CRUD profiles
│   ├── python_check_screen.dart # Hien thi Python installations
│   ├── venv_screen.dart         # 3 tabs: list/scan/create venv
│   ├── vscode_config_screen.dart # Sinh debug config
│   ├── folder_structure_screen.dart # Tao folder structure doc lap
│   └── settings_screen.dart     # Theme mode + accent color + language
├── widgets/                     # Reusable components
│   ├── status_card.dart         # Card hien thi trang thai
│   ├── directory_picker_field.dart # Text field + browse button
│   └── log_output.dart          # Real-time log voi color coding
└── templates/
    └── odoo_templates.dart      # Sinh odoo.conf va README.md
```

## Navigation (NavigationRail)
1. **Odoo Projects** - projects_screen.dart (icon: folder_special)
2. **Other Projects** - workspaces_screen.dart (icon: workspaces)
3. **Profiles** - profile_screen.dart
4. **Python Check** - python_check_screen.dart
5. **Venv Manager** - venv_screen.dart
6. **VSCode Config** - vscode_config_screen.dart
7. **Settings** - settings_screen.dart

## Key Patterns
- **Immutable models** voi `fromJson()`/`toJson()` + `copyWith()` serialization
- **Stateless services** - khong giu state, tra ve data classes
- **Provider** chi cho ThemeService, LocaleService (ChangeNotifier)
- **Real-time logging** - LogOutput widget auto-scroll, color-coded `[+]` `[-]` `[ERROR]` `[WARN]`
- **Dialog-based workflows** - Quick Create, Edit profile dung Dialog, return result qua Navigator.pop
- **Port conflict detection** - kiem tra trung port giua cac Odoo project
- **Cross-platform** - PlatformService abstract paths (bin/python vs Scripts/python.exe)
- **Responsive layout** - Dung `Wrap` thay `Row` cho header buttons de tranh overflow o 800px
- **Window size** - 3 preset: Small (800x600 min), Medium (1100x750 default), Large (1400x900)
- **List/Grid view** - Toggle giua list va grid, shared state `ProjectsScreen.gridView` (static),
  persisted vao settings JSON. Grid default, responsive columns: S=3, M=4, L=5
- **Favourite** - Star icon, sort favourite len dau roi by name A-Z. Luu trong model JSON (`favourite: bool`)
- **Grid context menu** - Right-click hien menu (favourite, open VSCode, open folder, edit, delete)
- **Auto-detect project type** - Workspace import tu dong nhan dien loai du an tu marker files
  (pubspec.yaml -> Flutter, package.json -> React/NextJS, .csproj/.sln -> .NET, etc.)

## Persistent Storage
Tat ca data luu tai: `~/.config/odoo_auto_config/odoo_auto_config.json`
Gom: profiles, projects, workspaces, registered venvs, settings (theme, locale, gridView)

## Typical Workflow
1. Detect Python (Python Check)
2. Tao venv (Venv Manager -> Create)
3. Luu profile (Profiles -> New)
4. Quick Create project (Odoo Projects -> Create) - tao folder, odoo.conf, launch.json, README
5. Sinh VSCode debug config (VSCode Config)
6. Mo project trong VSCode
7. Import du an khac (Other Projects -> Import) - auto-detect type, open in VSCode

## Commands
```bash
# Run debug
fvm flutter run -d macos   # hoac linux, windows

# Build release
fvm flutter build macos --release

# Gen l10n sau khi sua ARB files
fvm flutter gen-l10n

# Analyze
fvm flutter analyze
```

## Build & Deploy

### macOS (DMG)
```bash
flutter build macos --release

APP_PATH="build/macos/Build/Products/Release/odoo_auto_config.app"
DMG_PATH="build/Odoo Config.dmg"
TMP_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$TMP_DIR/Odoo Config.app"
ln -s /Applications "$TMP_DIR/Applications"
hdiutil create -volname "Odoo Config" -srcfolder "$TMP_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$TMP_DIR"

# Cai vao Applications (neu khong dung DMG)
cp -R "$APP_PATH" "/Applications/Odoo Config.app"
xattr -cr "/Applications/Odoo Config.app"
codesign --force --deep --sign - "/Applications/Odoo Config.app"
```

### Windows (MSIX)
```bash
flutter build windows --release
# MSIX config trong pubspec.yaml:
#   display_name: Odoo Auto Config
#   publisher: CN=Nam, O=Nam, C=VN
#   identity: com.nam.odoo-auto-config
#   capabilities: runFullTrust (cho phep Process.run)
flutter pub run msix:create
# Output: build/windows/x64/runner/Release/odoo_auto_config.msix
# Can certificate de cai dat MSIX tren Windows
```

### Linux
```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/
# Dependencies: GTK3 (gtk+-3.0)
# Python install dung pkexec (graphical sudo) de chay apt
```

## Internationalization (i18n)
- **Framework**: Flutter official `flutter_localizations` + `gen-l10n` (ARB files)
- **Supported locales**: English (default), Vietnamese (`vi`), Korean (`ko`)
- **ARB files**: `lib/l10n/app_en.arb`, `app_vi.arb`, `app_ko.arb`
- **Generated files**: `lib/l10n/app_localizations*.dart` (auto-generated, DO NOT edit manually)
- **Config**: `l10n.yaml` o project root
- **Extension**: `context.l10n.keyName` qua `lib/l10n/l10n_extension.dart`
- **LocaleService**: `lib/services/locale_service.dart` - luu locale vao StorageService, dung Provider
- **Language selector**: trong Settings screen (SegmentedButton)
- **Log messages**: giu nguyen tieng Anh (technical output)
- Khi them string moi: them vao ca 3 file ARB, chay `fvm flutter gen-l10n`

## Notes
- Venv detection bang marker file `pyvenv.cfg`
- VSCode config merge voi existing launch.json (khong ghi de)
- Symlink `project/odoo` -> Odoo source directory (optional)
- Admin password: random 16-char, DB password: random 48-char neu de trong
- Odoo versions supported: 14-18
- App name hien thi: "OdooAutoConfig" (CFBundleName trong Info.plist)
- App icon: pngegg.png (Odoo logo, 512x512)
- `window_manager` can full restart (khong hot reload) khi them moi

## macOS-Specific Issues (da fix)
- **App Sandbox PHAI tat** (`com.apple.security.app-sandbox = false`) trong ca
  DebugProfile.entitlements va Release.entitlements. Sandbox chan Process.run.
- **Release.entitlements** phai co `allow-jit` va `network.server` giong DebugProfile,
  neu khong app crash khi cai dat.
- **Process.run PHAI dung `runInShell: true`** trong release mode (AOT).
  Khong co shell, Dart native crash khi executable khong ton tai trong PATH.
  Da apply cho ca CommandRunner va PythonCheckerService.
- **macOS GUI app khong load ~/.zshrc** nen PATH rat toi gian.
  Fix: PlatformService.pythonCandidates tra ve absolute paths
  (pyenv shims, pyenv versions, homebrew, /usr/local/bin, /usr/bin).
- **Open folder**: dung `open` (macOS), `xdg-open` (Linux), `explorer` (Windows).
- **Open VSCode**: dung `open -a "Visual Studio Code"` tren macOS (tranh PATH issue).
- **Dedup pyenv shims**: loai bo shim entry khi da co real binary cung version.
- **Sau khi copy/rename .app**: can `xattr -cr` va `codesign --force --deep --sign -`.

## Windows-Specific Issues (da fix)
- **MSIX can `runFullTrust` capability** de Process.run hoat dong (tuong tu tat Sandbox tren macOS).
- **Native file/folder picker** bang PowerShell + COM (IFileOpenDialog) trong PlatformService,
  tranh dependency vao file_picker package tren Windows.
- **Certificate signing** can thiet de cai dat MSIX, config trong pubspec.yaml msix_config section.

## Linux-Specific Notes
- **Python install** qua `pkexec apt install` (graphical sudo prompt, khong can terminal).
- **PythonInstallService** ho tro chon version Python (3.10-3.13) truoc khi cai.
- **pythonCandidates** scan versioned binaries (`python3.X`) trong `/usr/bin`, `/usr/local/bin`.
