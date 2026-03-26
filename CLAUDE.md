# Odoo Auto Config - Project Context

## Overview
Flutter desktop app (macOS/Linux/Windows) giup developer Odoo thiet lap va quan ly moi truong phat trien. Cung cap GUI de tao project, quan ly Python/venv, sinh cau hinh VSCode debug, va luu profile tai su dung.

## Tech Stack
- **Flutter** SDK ^3.9.2 (FVM managed)
- **Provider** 6.1.0 - state management (chi dung cho ThemeService)
- **file_picker** 8.0.0 - chon thu muc/file
- **path** 1.9.0 - xu ly duong dan cross-platform

## Architecture
```
lib/
├── main.dart                    # Entry point, ThemeService + Provider setup
├── constants/app_constants.dart # Design tokens: spacing, font-size, colors
├── models/                      # Data classes (immutable, fromJson/toJson)
│   ├── profile.dart             # Cau hinh Odoo dev profile
│   ├── project_info.dart        # Metadata project da tao
│   ├── venv_info.dart           # Thong tin virtual environment
│   ├── python_info.dart         # Python installation detected
│   ├── command_result.dart      # Ket qua chay process
│   ├── venv_config.dart         # Config tao venv moi
│   └── folder_structure_config.dart # Config tao folder structure
├── services/                    # Business logic (stateless)
│   ├── storage_service.dart     # Luu tru JSON tai ~/.config/odoo_auto_config/
│   ├── command_runner.dart      # Wrap Process.run() -> CommandResult
│   ├── python_checker_service.dart # Detect Python installations
│   ├── venv_service.dart        # Tao/scan/inspect venv, pip install
│   ├── folder_structure_service.dart # Tao cau truc thu muc Odoo project
│   ├── vscode_config_service.dart   # Sinh .vscode/launch.json (debugpy)
│   ├── theme_service.dart       # Theme mode + accent color (ChangeNotifier)
│   └── platform_service.dart    # Platform abstraction (paths, executables)
├── screens/                     # UI screens (StatefulWidget)
│   ├── home_screen.dart         # NavigationRail chinh
│   ├── projects_screen.dart     # CRUD projects, quick create dialog
│   ├── quick_create_screen.dart # Dialog tao project nhanh tu profile
│   ├── profile_screen.dart      # CRUD profiles
│   ├── python_check_screen.dart # Hien thi Python installations
│   ├── venv_screen.dart         # 3 tabs: list/scan/create venv
│   ├── vscode_config_screen.dart # Sinh debug config
│   ├── folder_structure_screen.dart # Tao folder structure doc lap
│   └── settings_screen.dart     # Theme mode + accent color
├── widgets/                     # Reusable components
│   ├── status_card.dart         # Card hien thi trang thai
│   ├── directory_picker_field.dart # Text field + browse button
│   └── log_output.dart          # Real-time log voi color coding
└── templates/
    └── odoo_templates.dart      # Sinh odoo.conf va README.md
```

## Key Patterns
- **Immutable models** voi `fromJson()`/`toJson()` serialization
- **Stateless services** - khong giu state, tra ve data classes
- **Provider** chi cho ThemeService (ChangeNotifier)
- **Real-time logging** - LogOutput widget auto-scroll, color-coded `[+]` `[-]` `[ERROR]` `[WARN]`
- **Dialog-based workflows** - Quick Create, Edit profile dung Dialog, return result qua Navigator.pop
- **Port conflict detection** - kiem tra trung port giua cac project
- **Cross-platform** - PlatformService abstract paths (bin/python vs Scripts/python.exe)

## Persistent Storage
Tat ca data luu tai: `~/.config/odoo_auto_config/odoo_auto_config.json`
Gom: profiles, projects, registered venvs, settings (theme)

## Typical Workflow
1. Detect Python (Python Check)
2. Tao venv (Venv Manager -> Create)
3. Luu profile (Profiles -> New)
4. Quick Create project (Projects -> Create) - tao folder, odoo.conf, launch.json, README
5. Sinh VSCode debug config (VSCode Config)
6. Mo project trong VSCode

## Commands
```bash
# Run app
flutter run -d macos   # hoac linux, windows

# Build
flutter build macos
```

## Notes
- Venv detection bang marker file `pyvenv.cfg`
- VSCode config merge voi existing launch.json (khong ghi de)
- Symlink `project/odoo` -> Odoo source directory (optional)
- Admin password: random 16-char, DB password: random 48-char neu de trong
- Odoo versions supported: 14-18
