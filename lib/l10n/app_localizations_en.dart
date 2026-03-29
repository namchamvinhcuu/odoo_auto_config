// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Workspace Configuration';

  @override
  String get navOdooProjects => 'Odoo Projects';

  @override
  String get navProfiles => 'Profiles';

  @override
  String get navPythonCheck => 'Python Check';

  @override
  String get navVenvManager => 'Venv Manager';

  @override
  String get navVscodeConfig => 'VSCode Config';

  @override
  String get navSettings => 'Settings';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get create => 'Create';

  @override
  String get edit => 'Edit';

  @override
  String get import_ => 'Import';

  @override
  String get close => 'Close';

  @override
  String get install => 'Install';

  @override
  String get refresh => 'Refresh';

  @override
  String get rescan => 'Rescan';

  @override
  String get rename => 'Rename';

  @override
  String get browse => 'Browse...';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSubtitle => 'Customize theme and appearance.';

  @override
  String get themeMode => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get accentColor => 'Accent Color';

  @override
  String get preview => 'Preview';

  @override
  String get filledButton => 'Filled Button';

  @override
  String get tonalButton => 'Tonal Button';

  @override
  String get outlined => 'Outlined';

  @override
  String get language => 'Language';

  @override
  String get projectsTitle => 'Odoo Projects';

  @override
  String get projectsSubtitle =>
      'All Odoo projects with quick access. Import existing or create new ones.';

  @override
  String get projectsSearchHint => 'Search by name, path, label, port...';

  @override
  String get projectsEmpty =>
      'No projects yet. Use Quick Create or Import to add.';

  @override
  String get projectsNoMatch => 'No projects match your search.';

  @override
  String projectHttpPort(int port) {
    return 'HTTP: $port';
  }

  @override
  String projectLpPort(int port) {
    return 'LP: $port';
  }

  @override
  String get openInVscode => 'Open in VSCode';

  @override
  String get openFolder => 'Open folder';

  @override
  String get removeFromList => 'Remove from list';

  @override
  String get deleteProjectTitle => 'Delete project?';

  @override
  String deleteProjectConfirm(String name) {
    return 'Remove \"$name\" from the list?';
  }

  @override
  String get alsoDeleteFromDisk => 'Also delete project directory from disk';

  @override
  String deletedPath(String path) {
    return 'Deleted: $path';
  }

  @override
  String failedToDelete(String error) {
    return 'Failed to delete: $error';
  }

  @override
  String couldNotOpen(String path) {
    return 'Could not open: $path';
  }

  @override
  String get couldNotOpenVscode => 'Could not open VSCode';

  @override
  String get editProject => 'Edit Project';

  @override
  String get importExistingProject => 'Import Existing Project';

  @override
  String get projectDirectory => 'Project Directory';

  @override
  String get browseToSelect => 'Browse to select...';

  @override
  String get portsAutoDetected => 'Ports auto-detected from odoo.conf';

  @override
  String get projectName => 'Project Name';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String get descriptionHint => 'e.g. Polish tax project for client X';

  @override
  String get httpPort => 'HTTP Port';

  @override
  String get longpollingPort => 'Longpolling Port';

  @override
  String get selectProjectDirectory => 'Select existing Odoo project directory';

  @override
  String get quickCreateTitle => 'Quick Create';

  @override
  String get noProfilesFound => 'No profiles found. Create a profile first.';

  @override
  String get profile => 'Profile';

  @override
  String get baseDirectory => 'Base Directory';

  @override
  String get projectNameHint => 'e.g. my_odoo_project';

  @override
  String get portsMustBeDifferent =>
      'HTTP and longpolling ports must be different';

  @override
  String get creating => 'Creating...';

  @override
  String get createProject => 'Create Project';

  @override
  String get done => 'Done!';

  @override
  String get profilesTitle => 'Profiles';

  @override
  String get newProfile => 'New Profile';

  @override
  String get profilesSubtitle =>
      'Save venv + odoo-bin + settings as a profile for quick project creation.';

  @override
  String get profilesEmpty => 'No profiles yet. Create one to get started.';

  @override
  String get deleteProfileTitle => 'Delete profile?';

  @override
  String deleteProfileConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get profileName => 'Profile Name';

  @override
  String get profileNameHint => 'e.g. Odoo 17';

  @override
  String get virtualEnvironment => 'Virtual Environment';

  @override
  String get selectVenv => 'Select venv';

  @override
  String get odooBinPath => 'odoo-bin Path';

  @override
  String get odooBinPathHint => '/path/to/odoo/odoo-bin';

  @override
  String get selectOdooBin => 'Select odoo-bin';

  @override
  String get odooSourceDirectory => 'Odoo Source Code Directory';

  @override
  String get odooSourceHint => '/path/to/odoo (will be symlinked)';

  @override
  String get selectOdooSourceDirectory => 'Select Odoo source code directory';

  @override
  String get odooVersion => 'Odoo Version';

  @override
  String odooVersionLabel(String version) {
    return 'Odoo $version';
  }

  @override
  String get databaseConnection => 'Database Connection';

  @override
  String get host => 'Host';

  @override
  String get port => 'Port';

  @override
  String get user => 'User';

  @override
  String get password => 'Password';

  @override
  String get passwordHint => 'Leave empty to auto-generate';

  @override
  String get sslMode => 'SSL Mode';

  @override
  String get sslModeHint => 'prefer, disable, require';

  @override
  String venvLabel(String path) {
    return 'Venv: $path';
  }

  @override
  String odooBinLabel(String path) {
    return 'odoo-bin: $path';
  }

  @override
  String odooSrcLabel(String path) {
    return 'odoo src: $path';
  }

  @override
  String dbLabel(String user, String host, String port) {
    return 'db: $user@$host:$port';
  }

  @override
  String get pythonCheckTitle => 'Python Configuration Check';

  @override
  String get pythonCheckSubtitle =>
      'Detect installed Python versions, pip, and venv module availability.';

  @override
  String get scanningPython => 'Scanning for Python installations...';

  @override
  String get error => 'Error';

  @override
  String get noPythonFound => 'No Python Found';

  @override
  String get noPythonFoundSubtitle =>
      'No Python installation detected. Please install Python 3.8+.';

  @override
  String pythonVersion(String version) {
    return 'Python $version';
  }

  @override
  String pathLabel(String path) {
    return 'Path: $path';
  }

  @override
  String pipVersion(String version) {
    return 'pip $version';
  }

  @override
  String get venvModule => 'venv module';

  @override
  String get venvTitle => 'Virtual Environments';

  @override
  String get registered => 'Registered';

  @override
  String get scan => 'Scan';

  @override
  String get createNew => 'Create New';

  @override
  String get venvRegisteredSubtitle =>
      'Saved virtual environments for quick access.';

  @override
  String get noRegisteredVenvs => 'No registered venvs';

  @override
  String get noRegisteredVenvsSubtitle =>
      'Create a new venv or scan & register existing ones.';

  @override
  String get scanSubtitle =>
      'Scan a directory to find existing virtual environments.';

  @override
  String get scanDirectory => 'Scan Directory';

  @override
  String get scanning => 'Scanning...';

  @override
  String get scanningVenvs => 'Scanning for virtual environments...';

  @override
  String get noVenvsFound => 'No virtual environments found';

  @override
  String get noVenvsFoundSubtitle =>
      'Try scanning a different directory or increase depth.';

  @override
  String get registerThisVenv => 'Register this venv';

  @override
  String get registeredChip => 'Registered';

  @override
  String get listInstalledPackages => 'List installed packages';

  @override
  String get pipInstallPackage => 'pip install package';

  @override
  String get installRequirements => 'Install requirements.txt';

  @override
  String get valid => 'Valid';

  @override
  String get broken => 'Broken';

  @override
  String get deleteVenvTitle => 'Delete virtual environment?';

  @override
  String deleteVenvConfirm(String name) {
    return 'Remove \"$name\" from registered list?';
  }

  @override
  String get alsoDeleteVenvFromDisk => 'Also delete venv directory from disk';

  @override
  String registeredVenv(String name) {
    return 'Registered: $name';
  }

  @override
  String get filePNotFound => 'File not found';

  @override
  String get renameVenv => 'Rename venv';

  @override
  String get labelField => 'Label';

  @override
  String get labelHint => 'e.g. Odoo 17 Production';

  @override
  String get createVenvSubtitle =>
      'Create a Python virtual environment for your Odoo project.';

  @override
  String get pythonVersionLabel => 'Python Version';

  @override
  String pythonVersionDetail(String version, String path) {
    return 'Python $version ($path)';
  }

  @override
  String get noPythonWithVenv => 'No Python with venv support found';

  @override
  String get targetDirectory => 'Target Directory';

  @override
  String get venvName => 'Virtual Environment Name';

  @override
  String get venvNameHint => 'venv';

  @override
  String get createVenv => 'Create Venv';

  @override
  String get installedPackages => 'Installed Packages';

  @override
  String packagesCount(int count) {
    return '$count packages';
  }

  @override
  String get searchPackages => 'Search packages...';

  @override
  String errorLabel(String error) {
    return 'Error: $error';
  }

  @override
  String get packageHeader => 'Package';

  @override
  String get versionHeader => 'Version';

  @override
  String get noPackagesFound => 'No packages found.';

  @override
  String installPackagesTitle(String name) {
    return 'Install Packages — $name';
  }

  @override
  String get packagesField => 'Package(s)';

  @override
  String get packagesFieldHint => 'e.g. requests paramiko flask>=2.0';

  @override
  String get outputPlaceholder => 'Output will appear here...';

  @override
  String get vscodeConfigTitle => 'VSCode Configuration';

  @override
  String get vscodeConfigSubtitle =>
      'Generate .vscode/launch.json for Odoo debug.';

  @override
  String get configurationName => 'Configuration Name';

  @override
  String get configurationNameHint => 'e.g. Debug Polish Tax Odoo';

  @override
  String get projectDirectoryVscode =>
      'Project Directory (where .vscode/ will be created)';

  @override
  String get noRegisteredVenvsHint => 'No registered venvs';

  @override
  String get generating => 'Generating...';

  @override
  String get generateLaunchJson => 'Generate launch.json';

  @override
  String get previewLabel => 'Preview:';

  @override
  String get folderStructureTitle => 'Generate Folder Structure';

  @override
  String get folderStructureSubtitle =>
      'Create a standard Odoo development project structure.';

  @override
  String get generateStructure => 'Generate Structure';

  @override
  String get addons => 'addons';

  @override
  String get thirdPartyAddons => 'third_party_addons';

  @override
  String get config => 'config';

  @override
  String get venv => 'venv';

  @override
  String get noOutputYet => 'No output yet...';

  @override
  String get colorOdooPurple => 'Odoo Purple';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorTeal => 'Teal';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorRed => 'Red';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorIndigo => 'Indigo';

  @override
  String get colorCyan => 'Cyan';

  @override
  String get colorDeepPurple => 'Deep Purple';

  @override
  String get colorAmber => 'Amber';

  @override
  String get colorBrown => 'Brown';

  @override
  String get installPython => 'Install Python';

  @override
  String get installPythonTitle => 'Install Python';

  @override
  String get installPythonSubtitle =>
      'Select a Python version to install using your system package manager.';

  @override
  String get selectVersion => 'Select Version';

  @override
  String get installing => 'Installing...';

  @override
  String get installComplete => 'Installation complete! Rescanning...';

  @override
  String get installFailed => 'Installation failed. Check log for details.';

  @override
  String get uninstallPython => 'Uninstall Python';

  @override
  String uninstallPythonConfirm(String version) {
    return 'Are you sure you want to uninstall Python $version?';
  }

  @override
  String get uninstalling => 'Uninstalling...';

  @override
  String get symlinkErrorTitle => 'Cannot create symlink';

  @override
  String get symlinkErrorDesc =>
      'Windows requires Developer Mode to create symbolic links. The project was not created.';

  @override
  String get symlinkErrorSteps => 'How to enable Developer Mode:';

  @override
  String get symlinkErrorStep1 => '1. Open Windows Settings (Win + I)';

  @override
  String get symlinkErrorStep2 => '2. Go to System > For developers';

  @override
  String get symlinkErrorStep3 => '3. Turn on Developer Mode';

  @override
  String get symlinkErrorStep4 => '4. Come back and try again';

  @override
  String get symlinkErrorRetry =>
      'After enabling Developer Mode, try creating the project again.';

  @override
  String get packageManagerNotFound => 'Package manager not found';

  @override
  String get packageManagerNotFoundWindows =>
      'winget is required to install Python. Please install App Installer from Microsoft Store.';

  @override
  String get packageManagerNotFoundMac =>
      'Homebrew is required. Install it from https://brew.sh';

  @override
  String get packageManagerNotFoundLinux =>
      'apt and pkexec (polkit) are required to install Python.';

  @override
  String get navOtherProjects => 'Other Projects';

  @override
  String get wsTitle => 'Other Projects';

  @override
  String get wsSubtitle =>
      'Manage all your development projects. Quick access and open in VSCode.';

  @override
  String get wsSearchHint => 'Search by name, path, type...';

  @override
  String get wsEmpty => 'No workspaces yet. Import a directory to get started.';

  @override
  String get wsNoMatch => 'No workspaces match your search.';

  @override
  String get wsFilterByType => 'Filter by type';

  @override
  String get wsShowAll => 'Show all';

  @override
  String get wsDeleteTitle => 'Remove workspace?';

  @override
  String wsDeleteConfirm(String name) {
    return 'Remove \"$name\" from the list?';
  }

  @override
  String get wsImport => 'Import Workspace';

  @override
  String get wsEdit => 'Edit Workspace';

  @override
  String get wsDirectory => 'Directory';

  @override
  String get wsSelectDirectory => 'Select workspace directory';

  @override
  String get wsName => 'Name';

  @override
  String get wsType => 'Type';

  @override
  String get wsTypeHint => 'e.g. Flutter, React, .NET';

  @override
  String get wsSelectType => 'Select type';

  @override
  String get wsDescriptionHint => 'e.g. Client X frontend project';

  @override
  String get wsizeSmall => 'Small';

  @override
  String get wsizeMedium => 'Medium';

  @override
  String get wsizeLarge => 'Large';

  @override
  String get wsViewList => 'List view';

  @override
  String get wsViewGrid => 'Grid view';

  @override
  String get favourite => 'Add to favourites';

  @override
  String get unfavourite => 'Remove from favourites';

  @override
  String get wsPort => 'Port (optional)';

  @override
  String get wsPortHint => 'e.g. 3000, 8080';

  @override
  String get nginxSettings => 'Nginx Reverse Proxy';

  @override
  String get nginxConfDir => 'conf.d Directory';

  @override
  String get nginxConfDirHint => 'e.g. /path/to/conf.d';

  @override
  String get nginxDomainSuffix => 'Domain Suffix';

  @override
  String get nginxDomainSuffixHint => 'e.g. .namchamvinhcuu.test';

  @override
  String get nginxContainerName => 'Docker Container Name';

  @override
  String get nginxContainerNameHint => 'e.g. nginx';

  @override
  String get nginxSetup => 'Setup Nginx';

  @override
  String get nginxRemove => 'Remove Nginx';

  @override
  String nginxDomain(String domain) {
    return '$domain';
  }

  @override
  String nginxSetupSuccess(String domain) {
    return 'Nginx configured: $domain';
  }

  @override
  String nginxRemoveSuccess(String domain) {
    return 'Nginx removed: $domain';
  }

  @override
  String nginxFailed(String error) {
    return 'Nginx error: $error';
  }

  @override
  String get nginxNotConfigured => 'Configure Nginx in Settings first';

  @override
  String nginxConfirmRemove(String name) {
    return 'Remove nginx config for \"$name\"?';
  }

  @override
  String get nginxNoPort => 'Set a port first to setup Nginx';

  @override
  String get nginxSaved => 'Nginx settings saved';

  @override
  String get nginxSubdomain => 'Subdomain';

  @override
  String nginxPreviewDomain(String domain) {
    return 'Domain: $domain';
  }

  @override
  String get dockerStatus => 'Docker';

  @override
  String get dockerInstalled => 'Installed';

  @override
  String get dockerNotInstalled => 'Not installed';

  @override
  String get dockerRunning => 'Running';

  @override
  String get dockerStopped => 'Stopped';

  @override
  String get startDockerDesktop => 'Start Docker Desktop';

  @override
  String get starting => 'Starting...';

  @override
  String get dockerInstall => 'Install Docker';

  @override
  String get dockerInstallTitle => 'Install Docker';

  @override
  String get dockerInstallSubtitle =>
      'Install Docker Desktop using your system package manager.';

  @override
  String dockerVersion(String version) {
    return '$version';
  }

  @override
  String get dockerOpenDesktop =>
      'Please open Docker Desktop to start the daemon.';

  @override
  String get nginxInitTitle => 'Initialize Nginx Project';

  @override
  String get nginxInitSubtitle =>
      'Create nginx folder structure with docker-compose, SSL certs, and config.';

  @override
  String get nginxInitBaseDir => 'Base Directory';

  @override
  String get nginxInitFolderName => 'Folder Name';

  @override
  String get nginxInitDomain => 'Domain (for SSL cert)';

  @override
  String get nginxInitDomainHint => 'e.g. namchamvinhcuu.test';

  @override
  String get nginxImport => 'Import Existing';

  @override
  String get nginxPortCheck => 'Port Check';

  @override
  String nginxPortFree(int port) {
    return 'Port $port is available';
  }

  @override
  String nginxPortInUse(int port, String process, String pid) {
    return 'Port $port is in use by $process (PID: $pid)';
  }

  @override
  String nginxPortDocker(int port, String name) {
    return 'Port $port — Docker container \"$name\"';
  }

  @override
  String get nginxDockerRunning => 'Docker nginx is running';

  @override
  String get nginxDockerStopped => 'Docker nginx is not running';

  @override
  String get dockerNotInstalledBanner =>
      'Docker is not installed. Install Docker to use all features.';

  @override
  String get dockerNotRunningBanner =>
      'Docker daemon is not running. Start Docker Desktop to use all features.';

  @override
  String get dockerGoToSettings => 'Go to Settings';

  @override
  String get nginxKillProcess => 'Kill Process';

  @override
  String nginxKillConfirm(String process, String pid, int port) {
    return 'Kill $process (PID: $pid) to free port $port?';
  }

  @override
  String nginxKillSuccess(int port) {
    return 'Process killed. Port $port is now free.';
  }

  @override
  String nginxKillFailed(String error) {
    return 'Failed to kill process: $error';
  }

  @override
  String get nginxLocalDetected => 'Local nginx detected';

  @override
  String get nginxLocalDisableHint =>
      'To disable local nginx from auto-starting:';

  @override
  String get nginxLocalDisableMac =>
      'sudo brew services stop nginx\nsudo launchctl disable system/org.nginx.nginx';

  @override
  String get nginxLocalDisableLinux =>
      'sudo systemctl stop nginx\nsudo systemctl disable nginx';

  @override
  String get nginxLocalDisableWindows =>
      'net stop nginx\nsc config nginx start= disabled';

  @override
  String get nginxInitCreate => 'Create Structure';

  @override
  String get nginxDeleteTitle => 'Delete Nginx Configuration?';

  @override
  String get nginxDeleteConfirmText =>
      'This will remove nginx settings from the app.';

  @override
  String get nginxDeleteAlsoFolder => 'Also delete nginx folder from disk';

  @override
  String get nginxDeleted => 'Nginx configuration removed';

  @override
  String nginxInitSuccess(String path) {
    return 'Nginx project created at $path';
  }

  @override
  String nginxInitFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get nginxInitMkcertRequired =>
      'mkcert is required to generate SSL certificates';

  @override
  String get nginxInitMkcertInstall =>
      'Click the button below to install mkcert automatically.';

  @override
  String get nginxInvalidSubdomain =>
      'Only lowercase letters, numbers and hyphens allowed';

  @override
  String get nginxDomainConflict => 'This subdomain is already in use';

  @override
  String get nginxLink => 'Link existing Nginx';

  @override
  String get nginxLinkSubdomain => 'Existing subdomain';

  @override
  String get nginxLinkHint => 'Select the conf already created';

  @override
  String nginxLinked(String domain) {
    return 'Linked to $domain';
  }

  @override
  String nginxPortConflict(int port, String name) {
    return 'Port $port is already proxied by \"$name\"';
  }
}
