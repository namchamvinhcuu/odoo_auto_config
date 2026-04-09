import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
    Locale('vi'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspace Configuration'**
  String get appTitle;

  /// No description provided for @navOdooProjects.
  ///
  /// In en, this message translates to:
  /// **'Odoo Projects'**
  String get navOdooProjects;

  /// No description provided for @navProfiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get navProfiles;

  /// No description provided for @navPythonCheck.
  ///
  /// In en, this message translates to:
  /// **'Python Check'**
  String get navPythonCheck;

  /// No description provided for @navVenvManager.
  ///
  /// In en, this message translates to:
  /// **'Venv Manager'**
  String get navVenvManager;

  /// No description provided for @navVscodeConfig.
  ///
  /// In en, this message translates to:
  /// **'VSCode Config'**
  String get navVscodeConfig;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @cloneOdooSource.
  ///
  /// In en, this message translates to:
  /// **'Clone Odoo'**
  String get cloneOdooSource;

  /// No description provided for @cloneOdooTitle.
  ///
  /// In en, this message translates to:
  /// **'Clone Odoo Source'**
  String get cloneOdooTitle;

  /// No description provided for @cloneOdooSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clone Odoo source code from GitHub for development.'**
  String get cloneOdooSubtitle;

  /// No description provided for @cloneOdooFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get cloneOdooFolder;

  /// No description provided for @shallowClone.
  ///
  /// In en, this message translates to:
  /// **'Shallow clone (--depth 1, faster download)'**
  String get shallowClone;

  /// No description provided for @cloning.
  ///
  /// In en, this message translates to:
  /// **'Cloning...'**
  String get cloning;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @import_.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import_;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available: {current} → {latest}'**
  String updateAvailable(String current, String latest);

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get updateNow;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @updateDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to download update. Please try again.'**
  String get updateDownloadFailed;

  /// No description provided for @updateInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to install update. Please try again.'**
  String get updateInstallFailed;

  /// No description provided for @install.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @rescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get rescan;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @browse.
  ///
  /// In en, this message translates to:
  /// **'Browse...'**
  String get browse;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customize theme and appearance.'**
  String get settingsSubtitle;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeMode;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get accentColor;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @filledButton.
  ///
  /// In en, this message translates to:
  /// **'Filled Button'**
  String get filledButton;

  /// No description provided for @tonalButton.
  ///
  /// In en, this message translates to:
  /// **'Tonal Button'**
  String get tonalButton;

  /// No description provided for @outlined.
  ///
  /// In en, this message translates to:
  /// **'Outlined'**
  String get outlined;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @projectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Odoo Projects'**
  String get projectsTitle;

  /// No description provided for @projectsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All Odoo projects with quick access. Import existing or create new ones.'**
  String get projectsSubtitle;

  /// No description provided for @projectsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, path, label, port...'**
  String get projectsSearchHint;

  /// No description provided for @projectsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No projects yet. Use Quick Create or Import to add.'**
  String get projectsEmpty;

  /// No description provided for @projectsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No projects match your search.'**
  String get projectsNoMatch;

  /// No description provided for @projectHttpPort.
  ///
  /// In en, this message translates to:
  /// **'HTTP: {port}'**
  String projectHttpPort(int port);

  /// No description provided for @projectLpPort.
  ///
  /// In en, this message translates to:
  /// **'LP: {port}'**
  String projectLpPort(int port);

  /// No description provided for @openInVscode.
  ///
  /// In en, this message translates to:
  /// **'Open in VSCode'**
  String get openInVscode;

  /// No description provided for @gitPull.
  ///
  /// In en, this message translates to:
  /// **'Git Pull'**
  String get gitPull;

  /// No description provided for @gitPullTitle.
  ///
  /// In en, this message translates to:
  /// **'Git Pull — {name}'**
  String gitPullTitle(String name);

  /// No description provided for @gitPullNoScript.
  ///
  /// In en, this message translates to:
  /// **'git-repositories script not found in project directory (.sh or .ps1)'**
  String get gitPullNoScript;

  /// No description provided for @gitPullRunning.
  ///
  /// In en, this message translates to:
  /// **'Running...'**
  String get gitPullRunning;

  /// No description provided for @gitPullDone.
  ///
  /// In en, this message translates to:
  /// **'Done!'**
  String get gitPullDone;

  /// No description provided for @gitPullFailed.
  ///
  /// In en, this message translates to:
  /// **'Script failed with exit code {code}'**
  String gitPullFailed(int code);

  /// No description provided for @gitPullNotARepo.
  ///
  /// In en, this message translates to:
  /// **'This project is not a git repository'**
  String get gitPullNotARepo;

  /// No description provided for @gitSelectivePull.
  ///
  /// In en, this message translates to:
  /// **'Selective Pull'**
  String get gitSelectivePull;

  /// No description provided for @gitSelectivePullTitle.
  ///
  /// In en, this message translates to:
  /// **'Selective Pull — {name}'**
  String gitSelectivePullTitle(String name);

  /// No description provided for @gitSearchRepo.
  ///
  /// In en, this message translates to:
  /// **'Search repository...'**
  String get gitSearchRepo;

  /// No description provided for @gitSelectedRepos.
  ///
  /// In en, this message translates to:
  /// **'Selected repositories ({count})'**
  String gitSelectedRepos(int count);

  /// No description provided for @gitNoReposFound.
  ///
  /// In en, this message translates to:
  /// **'No git repositories found in addons/'**
  String get gitNoReposFound;

  /// No description provided for @gitClearList.
  ///
  /// In en, this message translates to:
  /// **'Clear list'**
  String get gitClearList;

  /// No description provided for @gitPullSelected.
  ///
  /// In en, this message translates to:
  /// **'Pull selected'**
  String get gitPullSelected;

  /// No description provided for @gitCommit.
  ///
  /// In en, this message translates to:
  /// **'Git Commit'**
  String get gitCommit;

  /// No description provided for @gitCommitTitle.
  ///
  /// In en, this message translates to:
  /// **'Git Commit — {name}'**
  String gitCommitTitle(String name);

  /// No description provided for @gitCommitMessage.
  ///
  /// In en, this message translates to:
  /// **'Commit message'**
  String get gitCommitMessage;

  /// No description provided for @gitCommitMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Describe your changes...'**
  String get gitCommitMessageHint;

  /// No description provided for @gitCommitNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes to commit'**
  String get gitCommitNoChanges;

  /// No description provided for @gitCommitDone.
  ///
  /// In en, this message translates to:
  /// **'Committed successfully!'**
  String get gitCommitDone;

  /// No description provided for @gitCommitFailed.
  ///
  /// In en, this message translates to:
  /// **'Commit failed with exit code {code}'**
  String gitCommitFailed(int code);

  /// No description provided for @gitCommitAndPush.
  ///
  /// In en, this message translates to:
  /// **'Commit & Push'**
  String get gitCommitAndPush;

  /// No description provided for @gitCommitOnly.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get gitCommitOnly;

  /// No description provided for @gitPushAfterCommit.
  ///
  /// In en, this message translates to:
  /// **'Push after commit'**
  String get gitPushAfterCommit;

  /// No description provided for @gitSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get gitSelectAll;

  /// No description provided for @gitDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get gitDeselectAll;

  /// No description provided for @gitStagedFiles.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) selected'**
  String gitStagedFiles(int count);

  /// No description provided for @gitNoReposWithChanges.
  ///
  /// In en, this message translates to:
  /// **'No repositories with changes found'**
  String get gitNoReposWithChanges;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolder;

  /// No description provided for @openInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get openInBrowser;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @removeFromList.
  ///
  /// In en, this message translates to:
  /// **'Remove from list'**
  String get removeFromList;

  /// No description provided for @deleteProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete project?'**
  String get deleteProjectTitle;

  /// No description provided for @deleteProjectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from the list?'**
  String deleteProjectConfirm(String name);

  /// No description provided for @alsoDeleteFromDisk.
  ///
  /// In en, this message translates to:
  /// **'Also delete project directory from disk'**
  String get alsoDeleteFromDisk;

  /// No description provided for @deletedPath.
  ///
  /// In en, this message translates to:
  /// **'Deleted: {path}'**
  String deletedPath(String path);

  /// No description provided for @failedToDelete.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: {error}'**
  String failedToDelete(String error);

  /// No description provided for @couldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open: {path}'**
  String couldNotOpen(String path);

  /// No description provided for @couldNotOpenVscode.
  ///
  /// In en, this message translates to:
  /// **'Could not open VSCode'**
  String get couldNotOpenVscode;

  /// No description provided for @editProject.
  ///
  /// In en, this message translates to:
  /// **'Edit Project'**
  String get editProject;

  /// No description provided for @importExistingProject.
  ///
  /// In en, this message translates to:
  /// **'Import Existing Project'**
  String get importExistingProject;

  /// No description provided for @projectDirectory.
  ///
  /// In en, this message translates to:
  /// **'Project Directory'**
  String get projectDirectory;

  /// No description provided for @browseToSelect.
  ///
  /// In en, this message translates to:
  /// **'Browse to select...'**
  String get browseToSelect;

  /// No description provided for @portsAutoDetected.
  ///
  /// In en, this message translates to:
  /// **'Ports auto-detected from odoo.conf'**
  String get portsAutoDetected;

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Project Name'**
  String get projectName;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @descriptionHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Polish tax project for client X'**
  String get descriptionHint;

  /// No description provided for @httpPort.
  ///
  /// In en, this message translates to:
  /// **'HTTP Port'**
  String get httpPort;

  /// No description provided for @longpollingPort.
  ///
  /// In en, this message translates to:
  /// **'Longpolling Port'**
  String get longpollingPort;

  /// No description provided for @selectProjectDirectory.
  ///
  /// In en, this message translates to:
  /// **'Select existing Odoo project directory'**
  String get selectProjectDirectory;

  /// No description provided for @quickCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Create'**
  String get quickCreateTitle;

  /// No description provided for @noProfilesFound.
  ///
  /// In en, this message translates to:
  /// **'No profiles found. Create a profile first.'**
  String get noProfilesFound;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @baseDirectory.
  ///
  /// In en, this message translates to:
  /// **'Base Directory'**
  String get baseDirectory;

  /// No description provided for @projectNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. my_odoo_project'**
  String get projectNameHint;

  /// No description provided for @portsMustBeDifferent.
  ///
  /// In en, this message translates to:
  /// **'HTTP and longpolling ports must be different'**
  String get portsMustBeDifferent;

  /// No description provided for @creating.
  ///
  /// In en, this message translates to:
  /// **'Creating...'**
  String get creating;

  /// No description provided for @createProject.
  ///
  /// In en, this message translates to:
  /// **'Create Project'**
  String get createProject;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done!'**
  String get done;

  /// No description provided for @profilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get profilesTitle;

  /// No description provided for @newProfile.
  ///
  /// In en, this message translates to:
  /// **'New Profile'**
  String get newProfile;

  /// No description provided for @profilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Save venv + odoo-bin + settings as a profile for quick project creation.'**
  String get profilesSubtitle;

  /// No description provided for @profilesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No profiles yet. Create one to get started.'**
  String get profilesEmpty;

  /// No description provided for @deleteProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete profile?'**
  String get deleteProfileTitle;

  /// No description provided for @deleteProfileConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteProfileConfirm(String name);

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @profileName.
  ///
  /// In en, this message translates to:
  /// **'Profile Name'**
  String get profileName;

  /// No description provided for @profileNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Odoo 17'**
  String get profileNameHint;

  /// No description provided for @virtualEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Virtual Environment'**
  String get virtualEnvironment;

  /// No description provided for @selectVenv.
  ///
  /// In en, this message translates to:
  /// **'Select venv'**
  String get selectVenv;

  /// No description provided for @odooBinPath.
  ///
  /// In en, this message translates to:
  /// **'odoo-bin Path'**
  String get odooBinPath;

  /// No description provided for @odooBinPathHint.
  ///
  /// In en, this message translates to:
  /// **'/path/to/odoo/odoo-bin'**
  String get odooBinPathHint;

  /// No description provided for @selectOdooBin.
  ///
  /// In en, this message translates to:
  /// **'Select odoo-bin'**
  String get selectOdooBin;

  /// No description provided for @odooSourceDirectory.
  ///
  /// In en, this message translates to:
  /// **'Odoo Source Code Directory'**
  String get odooSourceDirectory;

  /// No description provided for @odooSourceHint.
  ///
  /// In en, this message translates to:
  /// **'/path/to/odoo (will be symlinked)'**
  String get odooSourceHint;

  /// No description provided for @selectOdooSourceDirectory.
  ///
  /// In en, this message translates to:
  /// **'Select Odoo source code directory'**
  String get selectOdooSourceDirectory;

  /// No description provided for @odooVersion.
  ///
  /// In en, this message translates to:
  /// **'Odoo Version'**
  String get odooVersion;

  /// No description provided for @odooVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Odoo {version}'**
  String odooVersionLabel(String version);

  /// No description provided for @databaseConnection.
  ///
  /// In en, this message translates to:
  /// **'Database Connection'**
  String get databaseConnection;

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to auto-generate'**
  String get passwordHint;

  /// No description provided for @sslMode.
  ///
  /// In en, this message translates to:
  /// **'SSL Mode'**
  String get sslMode;

  /// No description provided for @sslModeHint.
  ///
  /// In en, this message translates to:
  /// **'prefer, disable, require'**
  String get sslModeHint;

  /// No description provided for @venvLabel.
  ///
  /// In en, this message translates to:
  /// **'Venv: {path}'**
  String venvLabel(String path);

  /// No description provided for @odooBinLabel.
  ///
  /// In en, this message translates to:
  /// **'odoo-bin: {path}'**
  String odooBinLabel(String path);

  /// No description provided for @odooSrcLabel.
  ///
  /// In en, this message translates to:
  /// **'odoo src: {path}'**
  String odooSrcLabel(String path);

  /// No description provided for @dbLabel.
  ///
  /// In en, this message translates to:
  /// **'db: {user}@{host}:{port}'**
  String dbLabel(String user, String host, String port);

  /// No description provided for @pythonCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Python Configuration Check'**
  String get pythonCheckTitle;

  /// No description provided for @pythonCheckSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Detect installed Python versions, pip, and venv module availability.'**
  String get pythonCheckSubtitle;

  /// No description provided for @scanningPython.
  ///
  /// In en, this message translates to:
  /// **'Scanning for Python installations...'**
  String get scanningPython;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @noPythonFound.
  ///
  /// In en, this message translates to:
  /// **'No Python Found'**
  String get noPythonFound;

  /// No description provided for @noPythonFoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No Python installation detected. Please install Python 3.8+.'**
  String get noPythonFoundSubtitle;

  /// No description provided for @pythonVersion.
  ///
  /// In en, this message translates to:
  /// **'Python {version}'**
  String pythonVersion(String version);

  /// No description provided for @pathLabel.
  ///
  /// In en, this message translates to:
  /// **'Path: {path}'**
  String pathLabel(String path);

  /// No description provided for @pipVersion.
  ///
  /// In en, this message translates to:
  /// **'pip {version}'**
  String pipVersion(String version);

  /// No description provided for @venvModule.
  ///
  /// In en, this message translates to:
  /// **'venv module'**
  String get venvModule;

  /// No description provided for @venvTitle.
  ///
  /// In en, this message translates to:
  /// **'Virtual Environments'**
  String get venvTitle;

  /// No description provided for @registered.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get registered;

  /// No description provided for @scan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scan;

  /// No description provided for @createNew.
  ///
  /// In en, this message translates to:
  /// **'Create New'**
  String get createNew;

  /// No description provided for @venvRegisteredSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Saved virtual environments for quick access.'**
  String get venvRegisteredSubtitle;

  /// No description provided for @noRegisteredVenvs.
  ///
  /// In en, this message translates to:
  /// **'No registered venvs'**
  String get noRegisteredVenvs;

  /// No description provided for @noRegisteredVenvsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a new venv or scan & register existing ones.'**
  String get noRegisteredVenvsSubtitle;

  /// No description provided for @scanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a directory to find existing virtual environments.'**
  String get scanSubtitle;

  /// No description provided for @scanDirectory.
  ///
  /// In en, this message translates to:
  /// **'Scan Directory'**
  String get scanDirectory;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning...'**
  String get scanning;

  /// No description provided for @scanningVenvs.
  ///
  /// In en, this message translates to:
  /// **'Scanning for virtual environments...'**
  String get scanningVenvs;

  /// No description provided for @noVenvsFound.
  ///
  /// In en, this message translates to:
  /// **'No virtual environments found'**
  String get noVenvsFound;

  /// No description provided for @noVenvsFoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try scanning a different directory or increase depth.'**
  String get noVenvsFoundSubtitle;

  /// No description provided for @registerThisVenv.
  ///
  /// In en, this message translates to:
  /// **'Register this venv'**
  String get registerThisVenv;

  /// No description provided for @registeredChip.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get registeredChip;

  /// No description provided for @listInstalledPackages.
  ///
  /// In en, this message translates to:
  /// **'List installed packages'**
  String get listInstalledPackages;

  /// No description provided for @pipInstallPackage.
  ///
  /// In en, this message translates to:
  /// **'pip install package'**
  String get pipInstallPackage;

  /// No description provided for @installRequirements.
  ///
  /// In en, this message translates to:
  /// **'Install requirements.txt'**
  String get installRequirements;

  /// No description provided for @valid.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get valid;

  /// No description provided for @broken.
  ///
  /// In en, this message translates to:
  /// **'Broken'**
  String get broken;

  /// No description provided for @deleteVenvTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete virtual environment?'**
  String get deleteVenvTitle;

  /// No description provided for @deleteVenvConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from registered list?'**
  String deleteVenvConfirm(String name);

  /// No description provided for @alsoDeleteVenvFromDisk.
  ///
  /// In en, this message translates to:
  /// **'Also delete venv directory from disk'**
  String get alsoDeleteVenvFromDisk;

  /// No description provided for @registeredVenv.
  ///
  /// In en, this message translates to:
  /// **'Registered: {name}'**
  String registeredVenv(String name);

  /// No description provided for @filePNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found'**
  String get filePNotFound;

  /// No description provided for @renameVenv.
  ///
  /// In en, this message translates to:
  /// **'Rename venv'**
  String get renameVenv;

  /// No description provided for @labelField.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get labelField;

  /// No description provided for @labelHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Odoo 17 Production'**
  String get labelHint;

  /// No description provided for @createVenvSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a Python virtual environment for your Odoo project.'**
  String get createVenvSubtitle;

  /// No description provided for @pythonVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Python Version'**
  String get pythonVersionLabel;

  /// No description provided for @pythonVersionDetail.
  ///
  /// In en, this message translates to:
  /// **'Python {version} ({path})'**
  String pythonVersionDetail(String version, String path);

  /// No description provided for @noPythonWithVenv.
  ///
  /// In en, this message translates to:
  /// **'No Python with venv support found'**
  String get noPythonWithVenv;

  /// No description provided for @targetDirectory.
  ///
  /// In en, this message translates to:
  /// **'Target Directory'**
  String get targetDirectory;

  /// No description provided for @venvName.
  ///
  /// In en, this message translates to:
  /// **'Virtual Environment Name'**
  String get venvName;

  /// No description provided for @venvNameHint.
  ///
  /// In en, this message translates to:
  /// **'venv'**
  String get venvNameHint;

  /// No description provided for @createVenv.
  ///
  /// In en, this message translates to:
  /// **'Create Venv'**
  String get createVenv;

  /// No description provided for @installedPackages.
  ///
  /// In en, this message translates to:
  /// **'Installed Packages'**
  String get installedPackages;

  /// No description provided for @packagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} packages'**
  String packagesCount(int count);

  /// No description provided for @searchPackages.
  ///
  /// In en, this message translates to:
  /// **'Search packages...'**
  String get searchPackages;

  /// No description provided for @errorLabel.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorLabel(String error);

  /// No description provided for @packageHeader.
  ///
  /// In en, this message translates to:
  /// **'Package'**
  String get packageHeader;

  /// No description provided for @versionHeader.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get versionHeader;

  /// No description provided for @noPackagesFound.
  ///
  /// In en, this message translates to:
  /// **'No packages found.'**
  String get noPackagesFound;

  /// No description provided for @installPackagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Install Packages — {name}'**
  String installPackagesTitle(String name);

  /// No description provided for @packagesField.
  ///
  /// In en, this message translates to:
  /// **'Package(s)'**
  String get packagesField;

  /// No description provided for @packagesFieldHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. requests paramiko flask>=2.0'**
  String get packagesFieldHint;

  /// No description provided for @outputPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Output will appear here...'**
  String get outputPlaceholder;

  /// No description provided for @vscodeConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'VSCode Configuration'**
  String get vscodeConfigTitle;

  /// No description provided for @vscodeConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Generate .vscode/launch.json for Odoo debug.'**
  String get vscodeConfigSubtitle;

  /// No description provided for @configurationName.
  ///
  /// In en, this message translates to:
  /// **'Configuration Name'**
  String get configurationName;

  /// No description provided for @configurationNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Debug Polish Tax Odoo'**
  String get configurationNameHint;

  /// No description provided for @projectDirectoryVscode.
  ///
  /// In en, this message translates to:
  /// **'Project Directory (where .vscode/ will be created)'**
  String get projectDirectoryVscode;

  /// No description provided for @noRegisteredVenvsHint.
  ///
  /// In en, this message translates to:
  /// **'No registered venvs'**
  String get noRegisteredVenvsHint;

  /// No description provided for @generating.
  ///
  /// In en, this message translates to:
  /// **'Generating...'**
  String get generating;

  /// No description provided for @generateLaunchJson.
  ///
  /// In en, this message translates to:
  /// **'Generate launch.json'**
  String get generateLaunchJson;

  /// No description provided for @previewLabel.
  ///
  /// In en, this message translates to:
  /// **'Preview:'**
  String get previewLabel;

  /// No description provided for @folderStructureTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate Folder Structure'**
  String get folderStructureTitle;

  /// No description provided for @folderStructureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a standard Odoo development project structure.'**
  String get folderStructureSubtitle;

  /// No description provided for @generateStructure.
  ///
  /// In en, this message translates to:
  /// **'Generate Structure'**
  String get generateStructure;

  /// No description provided for @addons.
  ///
  /// In en, this message translates to:
  /// **'addons'**
  String get addons;

  /// No description provided for @thirdPartyAddons.
  ///
  /// In en, this message translates to:
  /// **'third_party_addons'**
  String get thirdPartyAddons;

  /// No description provided for @config.
  ///
  /// In en, this message translates to:
  /// **'config'**
  String get config;

  /// No description provided for @venv.
  ///
  /// In en, this message translates to:
  /// **'venv'**
  String get venv;

  /// No description provided for @noOutputYet.
  ///
  /// In en, this message translates to:
  /// **'No output yet...'**
  String get noOutputYet;

  /// No description provided for @colorOdooPurple.
  ///
  /// In en, this message translates to:
  /// **'Odoo Purple'**
  String get colorOdooPurple;

  /// No description provided for @colorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorBlue;

  /// No description provided for @colorTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get colorTeal;

  /// No description provided for @colorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorGreen;

  /// No description provided for @colorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colorOrange;

  /// No description provided for @colorRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colorRed;

  /// No description provided for @colorPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get colorPink;

  /// No description provided for @colorIndigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get colorIndigo;

  /// No description provided for @colorCyan.
  ///
  /// In en, this message translates to:
  /// **'Cyan'**
  String get colorCyan;

  /// No description provided for @colorDeepPurple.
  ///
  /// In en, this message translates to:
  /// **'Deep Purple'**
  String get colorDeepPurple;

  /// No description provided for @colorAmber.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get colorAmber;

  /// No description provided for @colorBrown.
  ///
  /// In en, this message translates to:
  /// **'Brown'**
  String get colorBrown;

  /// No description provided for @installPython.
  ///
  /// In en, this message translates to:
  /// **'Install Python'**
  String get installPython;

  /// No description provided for @installPythonTitle.
  ///
  /// In en, this message translates to:
  /// **'Install Python'**
  String get installPythonTitle;

  /// No description provided for @installPythonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select a Python version to install using your system package manager.'**
  String get installPythonSubtitle;

  /// No description provided for @selectVersion.
  ///
  /// In en, this message translates to:
  /// **'Select Version'**
  String get selectVersion;

  /// No description provided for @installing.
  ///
  /// In en, this message translates to:
  /// **'Installing...'**
  String get installing;

  /// No description provided for @installComplete.
  ///
  /// In en, this message translates to:
  /// **'Installation complete! Rescanning...'**
  String get installComplete;

  /// No description provided for @installFailed.
  ///
  /// In en, this message translates to:
  /// **'Installation failed. Check log for details.'**
  String get installFailed;

  /// No description provided for @uninstallPython.
  ///
  /// In en, this message translates to:
  /// **'Uninstall Python'**
  String get uninstallPython;

  /// No description provided for @uninstallPythonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to uninstall Python {version}?'**
  String uninstallPythonConfirm(String version);

  /// No description provided for @uninstalling.
  ///
  /// In en, this message translates to:
  /// **'Uninstalling...'**
  String get uninstalling;

  /// No description provided for @symlinkErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot create symlink'**
  String get symlinkErrorTitle;

  /// No description provided for @symlinkErrorDesc.
  ///
  /// In en, this message translates to:
  /// **'Windows requires Developer Mode to create symbolic links. The project was not created.'**
  String get symlinkErrorDesc;

  /// No description provided for @symlinkErrorSteps.
  ///
  /// In en, this message translates to:
  /// **'How to enable Developer Mode:'**
  String get symlinkErrorSteps;

  /// No description provided for @symlinkErrorStep1.
  ///
  /// In en, this message translates to:
  /// **'1. Open Windows Settings (Win + I)'**
  String get symlinkErrorStep1;

  /// No description provided for @symlinkErrorStep2.
  ///
  /// In en, this message translates to:
  /// **'2. Go to System > For developers'**
  String get symlinkErrorStep2;

  /// No description provided for @symlinkErrorStep3.
  ///
  /// In en, this message translates to:
  /// **'3. Turn on Developer Mode'**
  String get symlinkErrorStep3;

  /// No description provided for @symlinkErrorStep4.
  ///
  /// In en, this message translates to:
  /// **'4. Come back and try again'**
  String get symlinkErrorStep4;

  /// No description provided for @symlinkErrorRetry.
  ///
  /// In en, this message translates to:
  /// **'After enabling Developer Mode, try creating the project again.'**
  String get symlinkErrorRetry;

  /// No description provided for @packageManagerNotFound.
  ///
  /// In en, this message translates to:
  /// **'Package manager not found'**
  String get packageManagerNotFound;

  /// No description provided for @packageManagerNotFoundWindows.
  ///
  /// In en, this message translates to:
  /// **'winget is required to install Python. Please install App Installer from Microsoft Store.'**
  String get packageManagerNotFoundWindows;

  /// No description provided for @packageManagerNotFoundMac.
  ///
  /// In en, this message translates to:
  /// **'Homebrew is required. Install it from https://brew.sh'**
  String get packageManagerNotFoundMac;

  /// No description provided for @packageManagerNotFoundLinux.
  ///
  /// In en, this message translates to:
  /// **'apt and pkexec (polkit) are required to install Python.'**
  String get packageManagerNotFoundLinux;

  /// No description provided for @navOtherProjects.
  ///
  /// In en, this message translates to:
  /// **'Other Projects'**
  String get navOtherProjects;

  /// No description provided for @wsTitle.
  ///
  /// In en, this message translates to:
  /// **'Other Projects'**
  String get wsTitle;

  /// No description provided for @wsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage all your development projects. Quick access and open in VSCode.'**
  String get wsSubtitle;

  /// No description provided for @wsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, path, type...'**
  String get wsSearchHint;

  /// No description provided for @wsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No workspaces yet. Import a directory to get started.'**
  String get wsEmpty;

  /// No description provided for @wsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No workspaces match your search.'**
  String get wsNoMatch;

  /// No description provided for @wsFilterByType.
  ///
  /// In en, this message translates to:
  /// **'Filter by type'**
  String get wsFilterByType;

  /// No description provided for @wsShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get wsShowAll;

  /// No description provided for @wsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove workspace?'**
  String get wsDeleteTitle;

  /// No description provided for @wsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from the list?'**
  String wsDeleteConfirm(String name);

  /// No description provided for @wsImport.
  ///
  /// In en, this message translates to:
  /// **'Import Workspace'**
  String get wsImport;

  /// No description provided for @wsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Workspace'**
  String get wsEdit;

  /// No description provided for @wsDirectory.
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get wsDirectory;

  /// No description provided for @wsSelectDirectory.
  ///
  /// In en, this message translates to:
  /// **'Select workspace directory'**
  String get wsSelectDirectory;

  /// No description provided for @wsName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get wsName;

  /// No description provided for @wsType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get wsType;

  /// No description provided for @wsTypeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Flutter, React, .NET'**
  String get wsTypeHint;

  /// No description provided for @wsSelectType.
  ///
  /// In en, this message translates to:
  /// **'Select type'**
  String get wsSelectType;

  /// No description provided for @wsDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Client X frontend project'**
  String get wsDescriptionHint;

  /// No description provided for @wsizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get wsizeSmall;

  /// No description provided for @wsizeMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get wsizeMedium;

  /// No description provided for @wsizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get wsizeLarge;

  /// No description provided for @wsViewList.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get wsViewList;

  /// No description provided for @wsViewGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get wsViewGrid;

  /// No description provided for @favourite.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get favourite;

  /// No description provided for @unfavourite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get unfavourite;

  /// No description provided for @wsPort.
  ///
  /// In en, this message translates to:
  /// **'Port (optional)'**
  String get wsPort;

  /// No description provided for @wsPortHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 3000, 8080'**
  String get wsPortHint;

  /// No description provided for @nginxSettings.
  ///
  /// In en, this message translates to:
  /// **'Nginx Reverse Proxy'**
  String get nginxSettings;

  /// No description provided for @nginxConfDir.
  ///
  /// In en, this message translates to:
  /// **'conf.d Directory'**
  String get nginxConfDir;

  /// No description provided for @nginxConfDirHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. /path/to/conf.d'**
  String get nginxConfDirHint;

  /// No description provided for @nginxDomainSuffix.
  ///
  /// In en, this message translates to:
  /// **'Domain Suffix'**
  String get nginxDomainSuffix;

  /// No description provided for @nginxDomainSuffixHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. .namchamvinhcuu.test'**
  String get nginxDomainSuffixHint;

  /// No description provided for @nginxContainerName.
  ///
  /// In en, this message translates to:
  /// **'Docker Container Name'**
  String get nginxContainerName;

  /// No description provided for @nginxContainerNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. nginx'**
  String get nginxContainerNameHint;

  /// No description provided for @nginxSetup.
  ///
  /// In en, this message translates to:
  /// **'Setup Nginx'**
  String get nginxSetup;

  /// No description provided for @nginxRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove Nginx'**
  String get nginxRemove;

  /// No description provided for @nginxDomain.
  ///
  /// In en, this message translates to:
  /// **'{domain}'**
  String nginxDomain(String domain);

  /// No description provided for @nginxSetupSuccess.
  ///
  /// In en, this message translates to:
  /// **'Nginx configured: {domain}'**
  String nginxSetupSuccess(String domain);

  /// No description provided for @nginxRemoveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Nginx removed: {domain}'**
  String nginxRemoveSuccess(String domain);

  /// No description provided for @nginxFailed.
  ///
  /// In en, this message translates to:
  /// **'Nginx error: {error}'**
  String nginxFailed(String error);

  /// No description provided for @nginxNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configure Nginx in Settings first'**
  String get nginxNotConfigured;

  /// No description provided for @nginxConfirmRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove nginx config for \"{name}\"?'**
  String nginxConfirmRemove(String name);

  /// No description provided for @nginxNoPort.
  ///
  /// In en, this message translates to:
  /// **'Set a port first to setup Nginx'**
  String get nginxNoPort;

  /// No description provided for @nginxSaved.
  ///
  /// In en, this message translates to:
  /// **'Nginx settings saved'**
  String get nginxSaved;

  /// No description provided for @nginxSubdomain.
  ///
  /// In en, this message translates to:
  /// **'Subdomain'**
  String get nginxSubdomain;

  /// No description provided for @nginxPreviewDomain.
  ///
  /// In en, this message translates to:
  /// **'Domain: {domain}'**
  String nginxPreviewDomain(String domain);

  /// No description provided for @dockerStatus.
  ///
  /// In en, this message translates to:
  /// **'Docker'**
  String get dockerStatus;

  /// No description provided for @dockerInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get dockerInstalled;

  /// No description provided for @dockerNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get dockerNotInstalled;

  /// No description provided for @dockerRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get dockerRunning;

  /// No description provided for @dockerStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get dockerStopped;

  /// No description provided for @startDockerDesktop.
  ///
  /// In en, this message translates to:
  /// **'Start Docker'**
  String get startDockerDesktop;

  /// No description provided for @starting.
  ///
  /// In en, this message translates to:
  /// **'Starting...'**
  String get starting;

  /// No description provided for @dockerInstall.
  ///
  /// In en, this message translates to:
  /// **'Install Docker'**
  String get dockerInstall;

  /// No description provided for @dockerInstallTitle.
  ///
  /// In en, this message translates to:
  /// **'Install Docker'**
  String get dockerInstallTitle;

  /// No description provided for @dockerInstallSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Install Docker Desktop using your system package manager.'**
  String get dockerInstallSubtitle;

  /// No description provided for @dockerVersion.
  ///
  /// In en, this message translates to:
  /// **'{version}'**
  String dockerVersion(String version);

  /// No description provided for @dockerOpenDesktop.
  ///
  /// In en, this message translates to:
  /// **'Please open Docker Desktop to start the daemon.'**
  String get dockerOpenDesktop;

  /// No description provided for @nginxInitTitle.
  ///
  /// In en, this message translates to:
  /// **'Initialize Nginx Project'**
  String get nginxInitTitle;

  /// No description provided for @nginxInitSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create nginx folder structure with docker-compose, SSL certs, and config.'**
  String get nginxInitSubtitle;

  /// No description provided for @nginxInitBaseDir.
  ///
  /// In en, this message translates to:
  /// **'Base Directory'**
  String get nginxInitBaseDir;

  /// No description provided for @nginxInitFolderName.
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get nginxInitFolderName;

  /// No description provided for @nginxInitDomain.
  ///
  /// In en, this message translates to:
  /// **'Domain (for SSL cert)'**
  String get nginxInitDomain;

  /// No description provided for @nginxInitDomainHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. namchamvinhcuu.test'**
  String get nginxInitDomainHint;

  /// No description provided for @nginxImport.
  ///
  /// In en, this message translates to:
  /// **'Import Existing'**
  String get nginxImport;

  /// No description provided for @nginxPortCheck.
  ///
  /// In en, this message translates to:
  /// **'Port Check'**
  String get nginxPortCheck;

  /// No description provided for @nginxPortFree.
  ///
  /// In en, this message translates to:
  /// **'Port {port} is available'**
  String nginxPortFree(int port);

  /// No description provided for @nginxPortInUse.
  ///
  /// In en, this message translates to:
  /// **'Port {port} is in use by {process} (PID: {pid})'**
  String nginxPortInUse(int port, String process, String pid);

  /// No description provided for @nginxPortDocker.
  ///
  /// In en, this message translates to:
  /// **'Port {port} — Docker container \"{name}\"'**
  String nginxPortDocker(int port, String name);

  /// No description provided for @nginxDockerRunning.
  ///
  /// In en, this message translates to:
  /// **'Docker nginx is running'**
  String get nginxDockerRunning;

  /// No description provided for @nginxDockerStopped.
  ///
  /// In en, this message translates to:
  /// **'Docker nginx is not running'**
  String get nginxDockerStopped;

  /// No description provided for @dockerNotInstalledBanner.
  ///
  /// In en, this message translates to:
  /// **'Docker is not installed. Install Docker to use all features.'**
  String get dockerNotInstalledBanner;

  /// No description provided for @dockerNotRunningBanner.
  ///
  /// In en, this message translates to:
  /// **'Docker daemon is not running. Start Docker Desktop to use all features.'**
  String get dockerNotRunningBanner;

  /// No description provided for @dockerGoToSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get dockerGoToSettings;

  /// No description provided for @nginxKillProcess.
  ///
  /// In en, this message translates to:
  /// **'Kill Process'**
  String get nginxKillProcess;

  /// No description provided for @nginxKillConfirm.
  ///
  /// In en, this message translates to:
  /// **'Kill {process} (PID: {pid}) to free port {port}?'**
  String nginxKillConfirm(String process, String pid, int port);

  /// No description provided for @nginxKillSuccess.
  ///
  /// In en, this message translates to:
  /// **'Process killed. Port {port} is now free.'**
  String nginxKillSuccess(int port);

  /// No description provided for @nginxKillFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to kill process: {error}'**
  String nginxKillFailed(String error);

  /// No description provided for @nginxLocalDetected.
  ///
  /// In en, this message translates to:
  /// **'Local nginx detected'**
  String get nginxLocalDetected;

  /// No description provided for @nginxLocalDisableHint.
  ///
  /// In en, this message translates to:
  /// **'To disable local nginx from auto-starting:'**
  String get nginxLocalDisableHint;

  /// No description provided for @nginxLocalDisableMac.
  ///
  /// In en, this message translates to:
  /// **'sudo brew services stop nginx\nsudo launchctl disable system/org.nginx.nginx'**
  String get nginxLocalDisableMac;

  /// No description provided for @nginxLocalDisableLinux.
  ///
  /// In en, this message translates to:
  /// **'sudo systemctl stop nginx\nsudo systemctl disable nginx'**
  String get nginxLocalDisableLinux;

  /// No description provided for @nginxLocalDisableWindows.
  ///
  /// In en, this message translates to:
  /// **'net stop nginx\nsc config nginx start= disabled'**
  String get nginxLocalDisableWindows;

  /// No description provided for @nginxInitCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Structure'**
  String get nginxInitCreate;

  /// No description provided for @nginxDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Nginx Configuration?'**
  String get nginxDeleteTitle;

  /// No description provided for @nginxDeleteConfirmText.
  ///
  /// In en, this message translates to:
  /// **'This will remove nginx settings from the app.'**
  String get nginxDeleteConfirmText;

  /// No description provided for @nginxDeleteAlsoFolder.
  ///
  /// In en, this message translates to:
  /// **'Also delete nginx folder from disk'**
  String get nginxDeleteAlsoFolder;

  /// No description provided for @nginxDeleted.
  ///
  /// In en, this message translates to:
  /// **'Nginx configuration removed'**
  String get nginxDeleted;

  /// No description provided for @nginxInitSuccess.
  ///
  /// In en, this message translates to:
  /// **'Nginx project created at {path}'**
  String nginxInitSuccess(String path);

  /// No description provided for @nginxInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String nginxInitFailed(String error);

  /// No description provided for @nginxInitMkcertRequired.
  ///
  /// In en, this message translates to:
  /// **'mkcert is required to generate SSL certificates'**
  String get nginxInitMkcertRequired;

  /// No description provided for @nginxInitMkcertInstall.
  ///
  /// In en, this message translates to:
  /// **'Click the button below to install mkcert automatically.'**
  String get nginxInitMkcertInstall;

  /// No description provided for @nginxInvalidSubdomain.
  ///
  /// In en, this message translates to:
  /// **'Only lowercase letters, numbers and hyphens allowed'**
  String get nginxInvalidSubdomain;

  /// No description provided for @nginxDomainConflict.
  ///
  /// In en, this message translates to:
  /// **'This subdomain is already in use'**
  String get nginxDomainConflict;

  /// No description provided for @nginxLink.
  ///
  /// In en, this message translates to:
  /// **'Link existing Nginx'**
  String get nginxLink;

  /// No description provided for @nginxLinkSubdomain.
  ///
  /// In en, this message translates to:
  /// **'Existing subdomain'**
  String get nginxLinkSubdomain;

  /// No description provided for @nginxLinkHint.
  ///
  /// In en, this message translates to:
  /// **'Select the conf already created'**
  String get nginxLinkHint;

  /// No description provided for @nginxLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked to {domain}'**
  String nginxLinked(String domain);

  /// No description provided for @nginxPortConflict.
  ///
  /// In en, this message translates to:
  /// **'Port {port} is already proxied by \"{name}\"'**
  String nginxPortConflict(int port, String name);

  /// No description provided for @postgresStatus.
  ///
  /// In en, this message translates to:
  /// **'PostgreSQL Client Tools'**
  String get postgresStatus;

  /// No description provided for @postgresInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get postgresInstalled;

  /// No description provided for @postgresNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get postgresNotInstalled;

  /// No description provided for @postgresRunning.
  ///
  /// In en, this message translates to:
  /// **'Server running'**
  String get postgresRunning;

  /// No description provided for @postgresStopped.
  ///
  /// In en, this message translates to:
  /// **'Server stopped'**
  String get postgresStopped;

  /// No description provided for @postgresInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get postgresInstall;

  /// No description provided for @postgresInstallTitle.
  ///
  /// In en, this message translates to:
  /// **'Install PostgreSQL Client Tools'**
  String get postgresInstallTitle;

  /// No description provided for @postgresInstallSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Install client tools (psql, pg_dump, pg_restore, createdb, dropdb) to manage PostgreSQL databases.'**
  String get postgresInstallSubtitle;

  /// No description provided for @postgresClientTools.
  ///
  /// In en, this message translates to:
  /// **'Client Tools'**
  String get postgresClientTools;

  /// No description provided for @postgresClientNote.
  ///
  /// In en, this message translates to:
  /// **'Optional — Client tools (psql, pg_dump...) for manual database operations. Not required if you use PostgreSQL Docker, as Odoo connects directly and tools are available inside the container.'**
  String get postgresClientNote;

  /// No description provided for @postgresToolAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get postgresToolAvailable;

  /// No description provided for @postgresToolMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get postgresToolMissing;

  /// No description provided for @postgresServerStatus.
  ///
  /// In en, this message translates to:
  /// **'Server Status'**
  String get postgresServerStatus;

  /// No description provided for @postgresNoServer.
  ///
  /// In en, this message translates to:
  /// **'No PostgreSQL server detected (local or Docker)'**
  String get postgresNoServer;

  /// No description provided for @postgresContainer.
  ///
  /// In en, this message translates to:
  /// **'Container'**
  String get postgresContainer;

  /// No description provided for @postgresImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get postgresImage;

  /// No description provided for @postgresService.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get postgresService;

  /// No description provided for @postgresPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get postgresPort;

  /// No description provided for @postgresReady.
  ///
  /// In en, this message translates to:
  /// **'Accepting connections'**
  String get postgresReady;

  /// No description provided for @postgresNotReady.
  ///
  /// In en, this message translates to:
  /// **'Not responding'**
  String get postgresNotReady;

  /// No description provided for @postgresContainerRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get postgresContainerRunning;

  /// No description provided for @postgresContainerStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get postgresContainerStopped;

  /// No description provided for @postgresSetupDocker.
  ///
  /// In en, this message translates to:
  /// **'Setup PostgreSQL Docker'**
  String get postgresSetupDocker;

  /// No description provided for @postgresSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup PostgreSQL Docker'**
  String get postgresSetupTitle;

  /// No description provided for @postgresSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a PostgreSQL Docker project with docker-compose.'**
  String get postgresSetupSubtitle;

  /// No description provided for @postgresSetupBaseDir.
  ///
  /// In en, this message translates to:
  /// **'Base directory'**
  String get postgresSetupBaseDir;

  /// No description provided for @postgresSetupFolderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get postgresSetupFolderName;

  /// No description provided for @postgresSetupContainerName.
  ///
  /// In en, this message translates to:
  /// **'Container name'**
  String get postgresSetupContainerName;

  /// No description provided for @postgresSetupImage.
  ///
  /// In en, this message translates to:
  /// **'Docker image'**
  String get postgresSetupImage;

  /// No description provided for @postgresSetupUser.
  ///
  /// In en, this message translates to:
  /// **'Database user'**
  String get postgresSetupUser;

  /// No description provided for @postgresSetupPassword.
  ///
  /// In en, this message translates to:
  /// **'Database password'**
  String get postgresSetupPassword;

  /// No description provided for @postgresSetupDbName.
  ///
  /// In en, this message translates to:
  /// **'Default database'**
  String get postgresSetupDbName;

  /// No description provided for @postgresSetupPort.
  ///
  /// In en, this message translates to:
  /// **'Host port'**
  String get postgresSetupPort;

  /// No description provided for @postgresSetupNetwork.
  ///
  /// In en, this message translates to:
  /// **'Docker network'**
  String get postgresSetupNetwork;

  /// No description provided for @postgresSetupSuccess.
  ///
  /// In en, this message translates to:
  /// **'PostgreSQL Docker project created at {path}'**
  String postgresSetupSuccess(String path);

  /// No description provided for @importPython.
  ///
  /// In en, this message translates to:
  /// **'Import Python'**
  String get importPython;

  /// No description provided for @importPythonTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Python executable'**
  String get importPythonTitle;

  /// No description provided for @importPythonFilter.
  ///
  /// In en, this message translates to:
  /// **'Python executable|python3*;python*;python.exe'**
  String get importPythonFilter;

  /// No description provided for @importPythonInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not a valid Python executable'**
  String get importPythonInvalid;

  /// No description provided for @importPythonDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This Python is already in the list'**
  String get importPythonDuplicate;

  /// No description provided for @importPythonSuccess.
  ///
  /// In en, this message translates to:
  /// **'Added Python {version}'**
  String importPythonSuccess(String version);

  /// No description provided for @installVscode.
  ///
  /// In en, this message translates to:
  /// **'Install VSCode'**
  String get installVscode;

  /// No description provided for @installVscodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Visual Studio Code is not installed. Install it to open projects directly from the app.'**
  String get installVscodeSubtitle;

  /// No description provided for @envSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get envSetupTitle;

  /// No description provided for @envSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check and install prerequisites for Odoo development.'**
  String get envSetupSubtitle;

  /// No description provided for @envGit.
  ///
  /// In en, this message translates to:
  /// **'Git'**
  String get envGit;

  /// No description provided for @envGitDesc.
  ///
  /// In en, this message translates to:
  /// **'Version control — required to clone Odoo source code.'**
  String get envGitDesc;

  /// No description provided for @envDocker.
  ///
  /// In en, this message translates to:
  /// **'Docker'**
  String get envDocker;

  /// No description provided for @envDockerDesc.
  ///
  /// In en, this message translates to:
  /// **'Container runtime for nginx reverse proxy and PostgreSQL.'**
  String get envDockerDesc;

  /// No description provided for @envPython.
  ///
  /// In en, this message translates to:
  /// **'Python'**
  String get envPython;

  /// No description provided for @envPythonDesc.
  ///
  /// In en, this message translates to:
  /// **'Required runtime for Odoo. Python 3.10+ recommended.'**
  String get envPythonDesc;

  /// No description provided for @envPythonVersions.
  ///
  /// In en, this message translates to:
  /// **'{count} version(s) found'**
  String envPythonVersions(int count);

  /// No description provided for @envNginx.
  ///
  /// In en, this message translates to:
  /// **'Nginx'**
  String get envNginx;

  /// No description provided for @envNginxDesc.
  ///
  /// In en, this message translates to:
  /// **'Reverse proxy for HTTPS local development domains.'**
  String get envNginxDesc;

  /// No description provided for @envNginxConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get envNginxConfigured;

  /// No description provided for @envNginxNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get envNginxNotConfigured;

  /// No description provided for @envVscode.
  ///
  /// In en, this message translates to:
  /// **'VSCode'**
  String get envVscode;

  /// No description provided for @envVscodeDesc.
  ///
  /// In en, this message translates to:
  /// **'Recommended editor with Odoo debug support.'**
  String get envVscodeDesc;

  /// No description provided for @envCheckAll.
  ///
  /// In en, this message translates to:
  /// **'Check All'**
  String get envCheckAll;

  /// No description provided for @envAllGood.
  ///
  /// In en, this message translates to:
  /// **'All prerequisites are ready!'**
  String get envAllGood;

  /// No description provided for @envSomeIssues.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) need attention'**
  String envSomeIssues(int count);

  /// No description provided for @installed.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get installed;

  /// No description provided for @notInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get notInstalled;

  /// No description provided for @gitInstallTitle.
  ///
  /// In en, this message translates to:
  /// **'Install Git'**
  String get gitInstallTitle;

  /// No description provided for @gitInstallSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Git is required for cloning Odoo source code.'**
  String get gitInstallSubtitle;

  /// No description provided for @gitInstallMacNote.
  ///
  /// In en, this message translates to:
  /// **'On macOS, this will trigger the Xcode Command Line Tools installer.'**
  String get gitInstallMacNote;

  /// No description provided for @envAutoSetup.
  ///
  /// In en, this message translates to:
  /// **'Auto Setup'**
  String get envAutoSetup;

  /// No description provided for @envRestartRequired.
  ///
  /// In en, this message translates to:
  /// **'Restart Required'**
  String get envRestartRequired;

  /// No description provided for @envRestartMessage.
  ///
  /// In en, this message translates to:
  /// **'WSL has been installed. Please restart your computer, then run Auto Setup again to continue installing Docker.'**
  String get envRestartMessage;

  /// No description provided for @envRestartNow.
  ///
  /// In en, this message translates to:
  /// **'Restart Now'**
  String get envRestartNow;

  /// No description provided for @projectInfo.
  ///
  /// In en, this message translates to:
  /// **'Project Info'**
  String get projectInfo;

  /// No description provided for @projectInfoDomain.
  ///
  /// In en, this message translates to:
  /// **'Domain'**
  String get projectInfoDomain;

  /// No description provided for @projectInfoNginxNotSetup.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get projectInfoNginxNotSetup;

  /// No description provided for @projectInfoDbName.
  ///
  /// In en, this message translates to:
  /// **'Database Name'**
  String get projectInfoDbName;

  /// No description provided for @projectInfoDbNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. mydb'**
  String get projectInfoDbNameHint;

  /// No description provided for @createDatabase.
  ///
  /// In en, this message translates to:
  /// **'Create Database'**
  String get createDatabase;

  /// No description provided for @creatingDatabase.
  ///
  /// In en, this message translates to:
  /// **'Creating...'**
  String get creatingDatabase;

  /// No description provided for @dbCreated.
  ///
  /// In en, this message translates to:
  /// **'Database \"{name}\" created successfully!'**
  String dbCreated(String name);

  /// No description provided for @dbFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create database: {error}'**
  String dbFailed(String error);

  /// No description provided for @noPostgresContainer.
  ///
  /// In en, this message translates to:
  /// **'No PostgreSQL Docker container running'**
  String get noPostgresContainer;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @gitSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'GitHub Configuration'**
  String get gitSettingsTitle;

  /// No description provided for @gitSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Token and organization for git-repositories script (used in Odoo projects)'**
  String get gitSettingsDescription;

  /// No description provided for @gitToken.
  ///
  /// In en, this message translates to:
  /// **'GitHub Token'**
  String get gitToken;

  /// No description provided for @gitOrg.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get gitOrg;

  /// No description provided for @gitOrgHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. my-org'**
  String get gitOrgHint;

  /// No description provided for @workspaceViewTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspace — {name}'**
  String workspaceViewTitle(String name);

  /// No description provided for @workspaceView.
  ///
  /// In en, this message translates to:
  /// **'Workspace View'**
  String get workspaceView;

  /// No description provided for @workspaceViewScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning repositories...'**
  String get workspaceViewScanning;

  /// No description provided for @workspaceViewNoRepos.
  ///
  /// In en, this message translates to:
  /// **'No git repositories found in addons/'**
  String get workspaceViewNoRepos;

  /// No description provided for @workspaceViewRepoCount.
  ///
  /// In en, this message translates to:
  /// **'{count} repositories'**
  String workspaceViewRepoCount(int count);

  /// No description provided for @workspaceViewPullAll.
  ///
  /// In en, this message translates to:
  /// **'Pull All'**
  String get workspaceViewPullAll;

  /// No description provided for @workspaceViewPullSelected.
  ///
  /// In en, this message translates to:
  /// **'Pull Selected'**
  String get workspaceViewPullSelected;

  /// No description provided for @workspaceViewCommitPush.
  ///
  /// In en, this message translates to:
  /// **'Commit & Push'**
  String get workspaceViewCommitPush;

  /// No description provided for @workspaceViewCommitOnly.
  ///
  /// In en, this message translates to:
  /// **'Commit Only'**
  String get workspaceViewCommitOnly;

  /// No description provided for @workspaceViewSwitchBranch.
  ///
  /// In en, this message translates to:
  /// **'Switch Branch'**
  String get workspaceViewSwitchBranch;

  /// No description provided for @workspaceViewPublishBranch.
  ///
  /// In en, this message translates to:
  /// **'Publish Branch'**
  String get workspaceViewPublishBranch;

  /// No description provided for @workspaceViewPushSelected.
  ///
  /// In en, this message translates to:
  /// **'Push Selected'**
  String get workspaceViewPushSelected;

  /// No description provided for @workspaceViewChanged.
  ///
  /// In en, this message translates to:
  /// **'{count} changed'**
  String workspaceViewChanged(int count);

  /// No description provided for @workspaceViewBehind.
  ///
  /// In en, this message translates to:
  /// **'{count} behind'**
  String workspaceViewBehind(int count);

  /// No description provided for @workspaceViewAhead.
  ///
  /// In en, this message translates to:
  /// **'{count} ahead'**
  String workspaceViewAhead(int count);

  /// No description provided for @workspaceViewNewBranch.
  ///
  /// In en, this message translates to:
  /// **'New branch name'**
  String get workspaceViewNewBranch;

  /// No description provided for @workspaceViewCreateBranch.
  ///
  /// In en, this message translates to:
  /// **'Create Branch'**
  String get workspaceViewCreateBranch;

  /// No description provided for @workspaceViewFetching.
  ///
  /// In en, this message translates to:
  /// **'Fetching...'**
  String get workspaceViewFetching;

  /// No description provided for @workspaceViewPulling.
  ///
  /// In en, this message translates to:
  /// **'Pulling...'**
  String get workspaceViewPulling;

  /// No description provided for @workspaceViewPushing.
  ///
  /// In en, this message translates to:
  /// **'Pushing...'**
  String get workspaceViewPushing;

  /// No description provided for @workspaceViewSwitching.
  ///
  /// In en, this message translates to:
  /// **'Switching...'**
  String get workspaceViewSwitching;

  /// No description provided for @closeBehavior.
  ///
  /// In en, this message translates to:
  /// **'Close behavior'**
  String get closeBehavior;

  /// No description provided for @closeBehaviorExit.
  ///
  /// In en, this message translates to:
  /// **'Exit app'**
  String get closeBehaviorExit;

  /// No description provided for @closeBehaviorTray.
  ///
  /// In en, this message translates to:
  /// **'Minimize to system tray'**
  String get closeBehaviorTray;

  /// No description provided for @newWindow.
  ///
  /// In en, this message translates to:
  /// **'New Window'**
  String get newWindow;

  /// No description provided for @quitAll.
  ///
  /// In en, this message translates to:
  /// **'Quit All'**
  String get quitAll;

  /// No description provided for @trayShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get trayShow;

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get trayQuit;

  /// No description provided for @gitBranches.
  ///
  /// In en, this message translates to:
  /// **'Git Branches'**
  String get gitBranches;

  /// No description provided for @gitBranchLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get gitBranchLocal;

  /// No description provided for @gitBranchRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get gitBranchRemote;

  /// No description provided for @gitBranchPull.
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get gitBranchPull;

  /// No description provided for @gitBranchCommit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get gitBranchCommit;

  /// No description provided for @gitBranchPR.
  ///
  /// In en, this message translates to:
  /// **'PR'**
  String get gitBranchPR;

  /// No description provided for @gitBranchCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get gitBranchCreate;

  /// No description provided for @gitBranchCleanStale.
  ///
  /// In en, this message translates to:
  /// **'Clean stale'**
  String get gitBranchCleanStale;

  /// No description provided for @gitBranchPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish {branch}'**
  String gitBranchPublish(String branch);

  /// No description provided for @gitBranchPullBranch.
  ///
  /// In en, this message translates to:
  /// **'Pull {branch}'**
  String gitBranchPullBranch(String branch);

  /// No description provided for @gitBranchMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get gitBranchMerge;

  /// No description provided for @gitBranchDeleteBranch.
  ///
  /// In en, this message translates to:
  /// **'Delete branch'**
  String get gitBranchDeleteBranch;

  /// No description provided for @gitBranchChanged.
  ///
  /// In en, this message translates to:
  /// **'{count} changed'**
  String gitBranchChanged(int count);

  /// No description provided for @gitBranchBehind.
  ///
  /// In en, this message translates to:
  /// **'{count} behind'**
  String gitBranchBehind(int count);

  /// No description provided for @gitBranchCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Branch'**
  String get gitBranchCreateTitle;

  /// No description provided for @gitBranchBaseBranch.
  ///
  /// In en, this message translates to:
  /// **'Base branch'**
  String get gitBranchBaseBranch;

  /// No description provided for @gitBranchNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get gitBranchNameLabel;

  /// No description provided for @gitBranchNameHint.
  ///
  /// In en, this message translates to:
  /// **'feature/my-feature'**
  String get gitBranchNameHint;

  /// No description provided for @gitBranchDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Branch'**
  String get gitBranchDeleteTitle;

  /// No description provided for @gitBranchDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete local branch \"{branch}\"?'**
  String gitBranchDeleteConfirm(String branch);

  /// No description provided for @gitBranchForceDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Force Delete?'**
  String get gitBranchForceDeleteTitle;

  /// No description provided for @gitBranchForceDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Branch \"{branch}\" is not fully merged. Force delete?'**
  String gitBranchForceDeleteConfirm(String branch);

  /// No description provided for @gitBranchForceDelete.
  ///
  /// In en, this message translates to:
  /// **'Force Delete'**
  String get gitBranchForceDelete;

  /// No description provided for @gitBranchStaleBranches.
  ///
  /// In en, this message translates to:
  /// **'Stale Branches'**
  String get gitBranchStaleBranches;

  /// No description provided for @gitBranchStaleDesc.
  ///
  /// In en, this message translates to:
  /// **'These local branches no longer exist on remote:'**
  String get gitBranchStaleDesc;

  /// No description provided for @gitBranchDeleteCount.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} branch(es)'**
  String gitBranchDeleteCount(int count);

  /// No description provided for @gitMergeInto.
  ///
  /// In en, this message translates to:
  /// **'Merge {source} into {target}'**
  String gitMergeInto(String source, String target);

  /// No description provided for @gitMergeIntoCurrentDesc.
  ///
  /// In en, this message translates to:
  /// **'Update {current} with code from {source}'**
  String gitMergeIntoCurrentDesc(String current, String source);

  /// No description provided for @gitMergeIntoTargetDesc.
  ///
  /// In en, this message translates to:
  /// **'Push code from {current} to {target}'**
  String gitMergeIntoTargetDesc(String current, String target);

  /// No description provided for @prTitle.
  ///
  /// In en, this message translates to:
  /// **'Pull Request — {name}'**
  String prTitle(String name);

  /// No description provided for @prGhNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'GitHub CLI (gh) is not installed.'**
  String get prGhNotInstalled;

  /// No description provided for @prGhInstallHint.
  ///
  /// In en, this message translates to:
  /// **'Install: brew install gh (macOS)\n         winget install GitHub.cli (Windows)\n         apt install gh (Linux)'**
  String get prGhInstallHint;

  /// No description provided for @prBase.
  ///
  /// In en, this message translates to:
  /// **'Base:'**
  String get prBase;

  /// No description provided for @prTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get prTitleLabel;

  /// No description provided for @prDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get prDescriptionLabel;

  /// No description provided for @prCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create Pull Request'**
  String get prCreateButton;

  /// No description provided for @prCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get prCreated;

  /// No description provided for @prViewInBrowser.
  ///
  /// In en, this message translates to:
  /// **'View in Browser'**
  String get prViewInBrowser;

  /// No description provided for @gitViewOnGithub.
  ///
  /// In en, this message translates to:
  /// **'View on GitHub'**
  String get gitViewOnGithub;

  /// No description provided for @prNoChanges.
  ///
  /// In en, this message translates to:
  /// **'There are no changes.'**
  String get prNoChanges;

  /// No description provided for @prNoChangesDesc.
  ///
  /// In en, this message translates to:
  /// **'{base} is up to date with all commits from {current}.'**
  String prNoChangesDesc(String base, String current);

  /// No description provided for @prUncommittedTitle.
  ///
  /// In en, this message translates to:
  /// **'Uncommitted changes'**
  String get prUncommittedTitle;

  /// No description provided for @prUncommittedDesc.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) not committed.\nThese changes will NOT be included in the PR.\n\nCommit first, or continue anyway?'**
  String prUncommittedDesc(int count);

  /// No description provided for @prCommitFirst.
  ///
  /// In en, this message translates to:
  /// **'Commit first'**
  String get prCommitFirst;

  /// No description provided for @prContinueAnyway.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get prContinueAnyway;

  /// No description provided for @setupNginx.
  ///
  /// In en, this message translates to:
  /// **'Setup Nginx'**
  String get setupNginx;

  /// No description provided for @push.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get push;

  /// No description provided for @publishModules.
  ///
  /// In en, this message translates to:
  /// **'Publish Modules'**
  String get publishModules;

  /// No description provided for @publishModulesDesc.
  ///
  /// In en, this message translates to:
  /// **'Create GitHub repos for local modules without git'**
  String get publishModulesDesc;

  /// No description provided for @publishModulesNoModules.
  ///
  /// In en, this message translates to:
  /// **'All modules in addons/ already have git initialized'**
  String get publishModulesNoModules;

  /// No description provided for @publishModulesNoOrg.
  ///
  /// In en, this message translates to:
  /// **'Git organization not configured. Please edit the project and set the organization first.'**
  String get publishModulesNoOrg;

  /// No description provided for @publishModulesNoToken.
  ///
  /// In en, this message translates to:
  /// **'Git token not found. Please configure a git account in Settings > Git.'**
  String get publishModulesNoToken;

  /// No description provided for @publishModulesScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning local modules...'**
  String get publishModulesScanning;

  /// No description provided for @publishModulesCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating repos...'**
  String get publishModulesCreating;

  /// No description provided for @publishModulesSuccess.
  ///
  /// In en, this message translates to:
  /// **'Successfully published {name}'**
  String publishModulesSuccess(String name);

  /// No description provided for @publishModulesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to publish {name}: {error}'**
  String publishModulesFailed(String name, String error);

  /// No description provided for @publishModulesSelect.
  ///
  /// In en, this message translates to:
  /// **'Select modules to publish'**
  String get publishModulesSelect;

  /// No description provided for @publishModulesPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publishModulesPublish;

  /// No description provided for @publishModulesCreatingRepo.
  ///
  /// In en, this message translates to:
  /// **'Creating repo: {name}'**
  String publishModulesCreatingRepo(String name);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
