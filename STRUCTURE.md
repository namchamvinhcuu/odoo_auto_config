# Project Structure

> File này mô tả kiến trúc thư mục và chức năng từng file trong `lib/`.
> Được cập nhật tự động mỗi khi thêm/bớt file. Sessions mới đọc file này để nắm codebase nhanh.

```
lib/
├── main.dart                        # Entry point, OdooAutoConfigApp (ConsumerWidget), Provider setup, window_manager init, SelectionArea
├── constants/
│   └── app_constants.dart           # Design tokens: AppSpacing(xxs→xxxl), AppFontSize(xs→title), AppIconSize(sm→feature), AppRadius(sm→xl), AppDialog(width/height/listHeight/logHeight + show/closeButton), GitActionIcons, GitActionColors, AppLogColors, AppNav
├── generated/
│   └── version.dart                 # Generated version const (auto by CI/release.sh — KHÔNG sửa thủ công)
├── l10n/
│   ├── l10n_extension.dart          # Extension: context.l10n.keyName
│   ├── app_en.arb                   # English strings (default)
│   ├── app_vi.arb                   # Vietnamese strings
│   ├── app_ko.arb                   # Korean strings
│   └── app_localizations*.dart      # Generated l10n files (KHÔNG sửa thủ công)
│
├── models/
│   ├── profile.dart                 # Profile, ProfileCategory — cấu hình Odoo dev profile
│   ├── workspace_info.dart          # WorkspaceInfo — Other project (name, path, type, description, favourite, port, nginxSubdomain)
│   ├── project_info.dart            # ProjectInfo — Odoo project (name, path, ports, description, favourite, nginxSubdomain)
│   ├── venv_info.dart               # VenvInfo — thông tin virtual environment
│   ├── python_info.dart             # PythonInfo — Python installation detected (version, pip, venv support)
│   ├── command_result.dart          # CommandResult — kết quả chạy process (exit code, stdout, stderr)
│   ├── venv_config.dart             # VenvConfig — config tạo venv mới
│   └── folder_structure_config.dart # FolderStructureConfig — config tạo folder structure
│
├── services/
│   ├── storage_service.dart         # StorageService — lưu trữ JSON tại ~/.config/odoo_auto_config/, thread-safe với _synchronized lock
│   ├── command_runner.dart          # CommandRunner — wrap Process.run() → CommandResult, ANSI cleaning (runInShell: true)
│   ├── platform_service.dart        # PlatformService — platform abstraction (paths, executables, native dialogs, file pickers)
│   ├── python_checker_service.dart  # PythonCheckerService — detect Python installations (absolute paths + dedup shims)
│   ├── python_install_service.dart  # PythonInstallService — cross-platform Python install (winget/brew/apt)
│   ├── docker_install_service.dart  # DockerInstallService — Docker install + status check + start daemon (winget/brew/apt)
│   ├── postgres_service.dart        # PostgresService, PgServerInfo — PostgreSQL: client detect, server detect (Docker+local), init Docker, start/stop/restart
│   ├── nginx_service.dart           # NginxService — Nginx: init project, setup/remove proxy, port check, hosts, mkcert
│   ├── venv_service.dart            # VenvService — tạo/scan/inspect venv, pip install
│   ├── folder_structure_service.dart # FolderStructureService — tạo cấu trúc thư mục Odoo project với symlinks
│   ├── vscode_config_service.dart   # VscodeConfigService — sinh .vscode/launch.json (debugpy)
│   ├── instance_service.dart         # InstanceService — multi-instance: registry, IPC signals, PID check, launch
│   ├── tray_service.dart            # TrayService — system tray: single icon, submenu Show/New Window/Quit All
│   ├── update_service.dart          # UpdateInfo, UpdateService — auto-update: check GitHub releases, download, install
│   ├── git_service.dart             # GitService — Git: check installed, resolve absolute path (cross-platform)
│   ├── git_branch_service.dart      # GitBranchService — shared git branch operations (switch, create, delete, publish, clean stale, getRemoteUrl, openInBrowser)
│   └── shortcut_service.dart        # ShortcutSpec (ctrl/meta/shift/alt + triggerKeyId, matches/format/toJson) + ShortcutActions ids + platform-aware defaults
│
├── providers/
│   ├── theme_provider.dart          # ThemeState + ThemeNotifier (Notifier) — theme mode, seed color, closeBehavior, windowSize
│   ├── locale_provider.dart         # LocaleNotifier (Notifier) — language selection (en, vi, ko) with persistence
│   ├── profile_provider.dart        # ProfileState + ProfileNotifier (AsyncNotifier) — CRUD profiles + venv list
│   ├── environment_provider.dart    # EnvironmentState + EnvironmentNotifier (Notifier) — overall env status (git, docker, python, nginx, vscode)
│   ├── odoo_projects_provider.dart  # OdooProjectsState + OdooProjectsNotifier (AsyncNotifier) — CRUD Odoo projects + gridView
│   ├── other_projects_provider.dart # OtherProjectsState + OtherProjectsNotifier (AsyncNotifier) — CRUD Other projects + branches
│   ├── settings_provider.dart       # SettingsState + SettingsNotifier (Notifier) — scan environment + git accounts
│   ├── venv_provider.dart           # VenvState + VenvNotifier (AsyncNotifier) — CRUD registered venvs
│   ├── docker_status_provider.dart  # DockerStatus + DockerStatusNotifier (Notifier) — Docker status auto-check + nginx auto-start
│   ├── update_provider.dart         # UpdateState + UpdateNotifier (Notifier) — auto-check GitHub releases
│   └── shortcut_provider.dart       # ShortcutState + ShortcutNotifier (Notifier) — customizable keyboard shortcuts, persist to settings, findAction(event) for dispatch
│
├── screens/
│   ├── home_screen.dart             # HomeScreen (ConsumerStatefulWidget) — NavigationRail (4 tab) + window size selector (S/M/L) + tray listener
│   │
│   ├── odoo_projects/               # Odoo Projects screen
│   │   ├── odoo_projects_screen.dart    # OdooProjectsScreen (ConsumerStatefulWidget) — main screen, grid/list toggle
│   │   ├── odoo_project_list_view.dart  # OdooProjectListView (StatelessWidget) — list card layout
│   │   ├── odoo_project_grid_view.dart  # OdooProjectGridView (StatelessWidget) — grid card + context menu
│   │   ├── import_project_dialog.dart   # ImportProjectDialog — import existing Odoo project (port auto-detection)
│   │   ├── project_info_dialog.dart     # ProjectInfoDialog — Info + Edit + Nginx + Database gộp 1 dialog
│   │   ├── create_db_dialog.dart        # CreateDbDialog — tạo database Odoo mới
│   │   ├── git_pull_dialog.dart         # GitPullDialog — chạy git-repositories.sh/.ps1 pull hàng loạt repos
│   │   ├── git_commit_dialog.dart       # GitCommitDialog + RepoStatus — multi-repo commit trong addons/
│   │   ├── selective_pull_dialog.dart   # SelectivePullDialog — chọn repos cụ thể để pull (UI ẨN)
│   │   └── selective_pull_log_dialog.dart # SelectivePullLogDialog — log output cho selective pull
│   │
│   ├── other_projects/              # Other Projects screen
│   │   ├── other_projects_screen.dart   # OtherProjectsScreen (ConsumerStatefulWidget) — main screen
│   │   ├── other_project_list_view.dart # OtherProjectListView (StatelessWidget) — list card layout
│   │   ├── other_project_grid_view.dart # OtherProjectGridView (StatelessWidget) — grid card + context menu
│   │   ├── import_workspace_dialog.dart # ImportWorkspaceDialog — import non-Odoo project với preset types
│   │   ├── simple_git_pull_dialog.dart  # SimpleGitPullDialog — single repo git pull
│   │   ├── simple_git_commit_dialog.dart # SimpleGitCommitDialog — single repo commit + PR button after done
│   │   ├── create_pr_dialog.dart        # CreatePRDialog — create GitHub PR (gh CLI, base branch, diff check)
│   │   ├── switch_branch_dialog.dart    # SwitchBranchDialog (StatelessWidget) — thin wrapper → GitBranchDialog
│   │   └── prune_dialog.dart            # PruneDialog — delete stale/merged branches
│   │
│   ├── odoo_workspace/              # Workspace View: dashboard quản lý pinned repos trong addons/
│   │   ├── odoo_workspace_dialog.dart   # OdooWorkspaceDialog — dialog chính, pinned repos, lazy loading, batch actions
│   │   ├── repo_info.dart               # RepoInfo — data class (name, path, branch, changedFiles, ahead/behind, hasUpstream)
│   │   ├── repo_branch_dialog.dart      # RepoBranchDialog (StatelessWidget) — thin wrapper → GitBranchDialog
│   │   ├── repo_git_pull_dialog.dart    # RepoGitPullDialog — pull single repo
│   │   ├── repo_commit_dialog.dart      # RepoCommitDialog — single repo commit + PR button after done
│   │   ├── repo_create_pr_dialog.dart   # RepoCreatePRDialog — create PR cho repo trong workspace
│   │   ├── repo_prune_dialog.dart       # RepoPruneDialog — delete merged branches per repo
│   │   ├── branch_picker_dialog.dart    # BranchPickerDialog — chọn branch gộp unique từ tất cả repos
│   │   ├── workspace_commit_dialog.dart # WorkspaceCommitDialog — batch commit across multiple repos
│   │   ├── git_action_dialog.dart       # GitActionDialog — batch git operations (pull/push/switch/publish)
│   │   └── publish_modules_dialog.dart  # PublishModulesDialog — scan addons/ tìm module chưa có .git → create GitHub repo
│   │
│   ├── profile/                     # CRUD profiles
│   │   ├── profile_screen.dart          # ProfileScreen (ConsumerWidget) — profile management
│   │   ├── profile_dialog.dart          # ProfileDialog — create/edit profile (DB config, venv, git account)
│   │   └── clone_odoo_dialog.dart       # CloneOdooDialog — clone Odoo source từ GitHub
│   │
│   ├── settings/                    # 7 tabs: Theme, Docker, Python+Venv, PostgreSQL, Nginx, Git, Shortcuts
│   │   ├── settings_screen.dart         # SettingsScreen (ConsumerStatefulWidget) — TabBar + 7 tab widgets
│   │   ├── theme_tab.dart               # ThemeTab (ConsumerWidget) — language, theme mode, accent color, window size, close behavior
│   │   ├── docker_tab.dart              # DockerTab (ConsumerWidget) — docker status, install/start
│   │   ├── python_tab.dart              # PythonTab (ConsumerStatefulWidget) — python check + venv (sub-tabs)
│   │   ├── postgres_tab.dart            # PostgresTab (ConsumerWidget) — client tools detect, server status, Docker setup
│   │   ├── nginx_tab.dart               # NginxTab (ConsumerStatefulWidget) — config record, port check, container controls
│   │   ├── git_tab.dart                 # GitTab (ConsumerWidget) — git accounts CRUD + default account
│   │   ├── shortcuts_tab.dart           # ShortcutsTab (ConsumerWidget) — list actions, Change/Reset via capture dialog, Reset All
│   │   ├── git_account_dialog.dart      # GitAccountDialog — add/edit Git account credentials
│   │   ├── python_install_dialog.dart   # PythonInstallDialog — Python version installer (winget/brew/apt)
│   │   ├── python_uninstall_dialog.dart # PythonUninstallDialog — Python version uninstaller
│   │   ├── pg_setup_dialog.dart         # PgSetupDialog — PostgreSQL Docker container setup (docker-compose.yml, .env)
│   │   ├── postgres_install_dialog.dart # PostgresInstallDialog — PostgreSQL client tools installer
│   │   ├── docker_install_dialog.dart   # DockerInstallDialog — Docker install (OrbStack/Docker Desktop trên macOS)
│   │   └── nginx_init_dialog.dart       # NginxInitDialog — Nginx Docker container init với mkcert SSL
│   │
│   ├── venv/                        # Dialogs tách từ venv_screen
│   │   ├── package_list_dialog.dart     # PackageListDialog — list installed packages with search
│   │   ├── pip_install_dialog.dart      # PipInstallDialog — interactive pip package installer
│   │   └── install_requirements_dialog.dart # InstallRequirementsDialog — install requirements.txt
│   │
│   ├── venv_screen.dart             # VenvScreen (ConsumerStatefulWidget) — 3 tabs: list/scan/create venv
│   ├── quick_create_screen.dart     # QuickCreateDialog — tạo Odoo project nhanh từ profile
│   ├── python_check_screen.dart     # PythonCheckScreen — Python detection (ẩn khỏi menu, code giữ nguyên)
│   ├── vscode_config_screen.dart    # VscodeConfigScreen — sinh debug config (ẩn khỏi menu, code giữ nguyên)
│   ├── folder_structure_screen.dart # FolderStructureScreen — tạo folder structure độc lập
│   └── environment_screen.dart      # EnvironmentScreen (ConsumerWidget) — environment check (git, docker, python, nginx, vscode)
│
├── widgets/
│   ├── status_card.dart             # StatusCard (StatelessWidget) — styled status card (success/error/warning/loading/info)
│   ├── directory_picker_field.dart  # DirectoryPickerField (StatefulWidget) — text field + browse button
│   ├── log_output.dart              # LogOutput (StatefulWidget) — real-time log với color coding + auto-scroll
│   ├── clone_repository_dialog.dart # CloneRepositoryDialog — shared git clone dialog cho Other Projects và Odoo Workspace
│   ├── nginx_setup_dialog.dart      # NginxSetupDialog (StatefulWidget) — setup nginx (subdomain, port, validation, conflict detection)
│   ├── git_branch_dialog.dart       # GitBranchDialog (StatefulWidget) — shared Git Branches dialog (Other Projects + Odoo Workspace)
│   ├── vscode_install_dialog.dart   # VscodeInstallDialog (StatefulWidget) — VSCode installer (brew/winget/apt)
│   ├── shortcut_capture_dialog.dart # ShortcutCaptureDialog (StatefulWidget) — Focus + onKeyEvent, capture key combo, validate modifier required
│   └── ansi_parser.dart             # AnsiParser — static ANSI escape code parser cho terminal log output
│
└── templates/
    ├── odoo_templates.dart          # OdooTemplates — sinh odoo.conf, README.md, .vscode/settings.json, git-repositories.sh/.ps1
    ├── nginx_templates.dart         # NginxTemplates — sinh nginx conf (odoo/generic), nginx.conf, docker-compose.yml
    └── postgres_templates.dart      # PostgresTemplates — sinh docker-compose.yml, .env, postgresql.conf cho PostgreSQL Docker
```

## Root files

```
├── pubspec.yaml                 # Package config, version 2.0.9+1, dependencies
├── analysis_options.yaml        # Dart lint rules
├── l10n.yaml                    # Localization config
├── release.sh                   # macOS/Linux: version bump + git tag (bash)
├── release.ps1                  # Windows: version bump + git tag (PowerShell)
├── linux-build.sh               # Linux release build script
├── macos-build.sh               # macOS release build script
├── windows-build.ps1            # Windows release build script
├── install.ps1                  # Windows MSIX installer script
├── assets/
│   ├── version.json             # Version metadata (must match git tag khi release)
│   ├── tray_icon.png            # System tray icon 512x512
│   ├── tray_icon_16.png         # System tray icon 16x16
│   └── tray_icon.ico            # System tray icon (Windows)
└── .github/workflows/
    └── release.yml              # CI: build Linux AppImage + macOS DMG/ZIP + Windows MSIX → publish to public repo
```
