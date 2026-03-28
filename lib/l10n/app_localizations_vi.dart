// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'Workspace Configuration';

  @override
  String get navOdooProjects => 'Dự án Odoo';

  @override
  String get navProfiles => 'Hồ sơ';

  @override
  String get navPythonCheck => 'Kiểm tra Python';

  @override
  String get navVenvManager => 'Quản lý Venv';

  @override
  String get navVscodeConfig => 'Cấu hình VSCode';

  @override
  String get navSettings => 'Cài đặt';

  @override
  String get cancel => 'Hủy';

  @override
  String get delete => 'Xóa';

  @override
  String get save => 'Lưu';

  @override
  String get create => 'Tạo';

  @override
  String get edit => 'Sửa';

  @override
  String get import_ => 'Nhập';

  @override
  String get close => 'Đóng';

  @override
  String get install => 'Cài đặt';

  @override
  String get refresh => 'Làm mới';

  @override
  String get rescan => 'Quét lại';

  @override
  String get rename => 'Đổi tên';

  @override
  String get browse => 'Duyệt...';

  @override
  String get settingsTitle => 'Cài đặt';

  @override
  String get settingsSubtitle => 'Tùy chỉnh giao diện và hiển thị.';

  @override
  String get themeMode => 'Tùy chỉnh giao diện';

  @override
  String get themeSystem => 'Hệ thống';

  @override
  String get themeLight => 'Sáng';

  @override
  String get themeDark => 'Tối';

  @override
  String get accentColor => 'Màu chủ đạo';

  @override
  String get preview => 'Xem trước';

  @override
  String get filledButton => 'Nút đặc';

  @override
  String get tonalButton => 'Nút tonal';

  @override
  String get outlined => 'Viền';

  @override
  String get language => 'Ngôn ngữ';

  @override
  String get projectsTitle => 'Dự án Odoo';

  @override
  String get projectsSubtitle =>
      'Tất cả dự án Odoo với truy cập nhanh. Nhập dự án có sẵn hoặc tạo mới.';

  @override
  String get projectsSearchHint => 'Tìm theo tên, đường dẫn, nhãn, port...';

  @override
  String get projectsEmpty =>
      'Chưa có dự án. Dùng Tạo nhanh hoặc Nhập để thêm.';

  @override
  String get projectsNoMatch => 'Không có dự án phù hợp.';

  @override
  String projectHttpPort(int port) {
    return 'HTTP: $port';
  }

  @override
  String projectLpPort(int port) {
    return 'LP: $port';
  }

  @override
  String get openInVscode => 'Mở trong VSCode';

  @override
  String get openFolder => 'Mở thư mục';

  @override
  String get removeFromList => 'Xóa khỏi danh sách';

  @override
  String get deleteProjectTitle => 'Xóa dự án?';

  @override
  String deleteProjectConfirm(String name) {
    return 'Xóa \"$name\" khỏi danh sách?';
  }

  @override
  String get alsoDeleteFromDisk => 'Đồng thời xóa thư mục dự án trên ổ đĩa';

  @override
  String deletedPath(String path) {
    return 'Đã xóa: $path';
  }

  @override
  String failedToDelete(String error) {
    return 'Xóa thất bại: $error';
  }

  @override
  String couldNotOpen(String path) {
    return 'Không thể mở: $path';
  }

  @override
  String get couldNotOpenVscode => 'Không thể mở VSCode';

  @override
  String get editProject => 'Sửa dự án';

  @override
  String get importExistingProject => 'Nhập dự án có sẵn';

  @override
  String get projectDirectory => 'Thư mục dự án';

  @override
  String get browseToSelect => 'Duyệt để chọn...';

  @override
  String get portsAutoDetected => 'Ports được tự động phát hiện từ odoo.conf';

  @override
  String get projectName => 'Tên dự án';

  @override
  String get descriptionOptional => 'Mô tả (tùy chọn)';

  @override
  String get descriptionHint => 'VD: Dự án thuế Ba Lan cho khách hàng X';

  @override
  String get httpPort => 'Cổng HTTP';

  @override
  String get longpollingPort => 'Cổng Longpolling';

  @override
  String get selectProjectDirectory => 'Chọn thư mục dự án Odoo có sẵn';

  @override
  String get quickCreateTitle => 'Tạo nhanh';

  @override
  String get noProfilesFound => 'Chưa có hồ sơ. Vui lòng tạo hồ sơ trước.';

  @override
  String get profile => 'Hồ sơ';

  @override
  String get baseDirectory => 'Thư mục gốc';

  @override
  String get projectNameHint => 'VD: my_odoo_project';

  @override
  String get portsMustBeDifferent => 'Cổng HTTP và longpolling phải khác nhau';

  @override
  String get creating => 'Đang tạo...';

  @override
  String get createProject => 'Tạo dự án';

  @override
  String get done => 'Hoàn tất!';

  @override
  String get profilesTitle => 'Hồ sơ';

  @override
  String get newProfile => 'Hồ sơ mới';

  @override
  String get profilesSubtitle =>
      'Lưu cấu hình venv + odoo-bin để tạo dự án nhanh.';

  @override
  String get profilesEmpty => 'Chưa có hồ sơ. Tạo một hồ sơ để bắt đầu.';

  @override
  String get deleteProfileTitle => 'Xóa hồ sơ?';

  @override
  String deleteProfileConfirm(String name) {
    return 'Xóa \"$name\"?';
  }

  @override
  String get editProfile => 'Sửa hồ sơ';

  @override
  String get profileName => 'Tên hồ sơ';

  @override
  String get profileNameHint => 'VD: Odoo 17';

  @override
  String get virtualEnvironment => 'Môi trường ảo';

  @override
  String get selectVenv => 'Chọn venv';

  @override
  String get odooBinPath => 'Đường dẫn odoo-bin';

  @override
  String get odooBinPathHint => '/đường/dẫn/tới/odoo/odoo-bin';

  @override
  String get selectOdooBin => 'Chọn odoo-bin';

  @override
  String get odooSourceDirectory => 'Thư mục mã nguồn Odoo';

  @override
  String get odooSourceHint => '/đường/dẫn/tới/odoo (sẽ tạo symlink)';

  @override
  String get selectOdooSourceDirectory => 'Chọn thư mục mã nguồn Odoo';

  @override
  String get odooVersion => 'Phiên bản Odoo';

  @override
  String odooVersionLabel(String version) {
    return 'Odoo $version';
  }

  @override
  String get databaseConnection => 'Kết nối cơ sở dữ liệu';

  @override
  String get host => 'Host';

  @override
  String get port => 'Port';

  @override
  String get user => 'Tên đăng nhập';

  @override
  String get password => 'Mật khẩu';

  @override
  String get passwordHint => 'Để trống sẽ tự động tạo';

  @override
  String get sslMode => 'Chế độ SSL';

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
  String get pythonCheckTitle => 'Kiểm tra cấu hình Python';

  @override
  String get pythonCheckSubtitle =>
      'Phát hiện các phiên bản Python, pip và module venv đã cài đặt.';

  @override
  String get scanningPython => 'Đang quét các phiên bản Python...';

  @override
  String get error => 'Lỗi';

  @override
  String get noPythonFound => 'Không tìm thấy Python';

  @override
  String get noPythonFoundSubtitle =>
      'Không phát hiện Python nào. Vui lòng cài đặt Python 3.8+.';

  @override
  String pythonVersion(String version) {
    return 'Python $version';
  }

  @override
  String pathLabel(String path) {
    return 'Đường dẫn: $path';
  }

  @override
  String pipVersion(String version) {
    return 'pip $version';
  }

  @override
  String get venvModule => 'module venv';

  @override
  String get venvTitle => 'Môi trường ảo';

  @override
  String get registered => 'Đã đăng ký';

  @override
  String get scan => 'Quét';

  @override
  String get createNew => 'Tạo mới';

  @override
  String get venvRegisteredSubtitle =>
      'Các môi trường ảo đã lưu để truy cập nhanh.';

  @override
  String get noRegisteredVenvs => 'Chưa có venv nào';

  @override
  String get noRegisteredVenvsSubtitle =>
      'Tạo venv mới hoặc quét và đăng ký venv có sẵn.';

  @override
  String get scanSubtitle => 'Quét thư mục để tìm các môi trường ảo có sẵn.';

  @override
  String get scanDirectory => 'Thư mục quét';

  @override
  String get scanning => 'Đang quét...';

  @override
  String get scanningVenvs => 'Đang quét tìm môi trường ảo...';

  @override
  String get noVenvsFound => 'Không tìm thấy môi trường ảo';

  @override
  String get noVenvsFoundSubtitle => 'Thử quét thư mục khác hoặc tăng độ sâu.';

  @override
  String get registerThisVenv => 'Đăng ký venv này';

  @override
  String get registeredChip => 'Đã đăng ký';

  @override
  String get listInstalledPackages => 'Xem danh sách package';

  @override
  String get pipInstallPackage => 'pip install package';

  @override
  String get installRequirements => 'Cài đặt requirements.txt';

  @override
  String get valid => 'Hợp lệ';

  @override
  String get broken => 'Hỏng';

  @override
  String get deleteVenvTitle => 'Xóa môi trường ảo?';

  @override
  String deleteVenvConfirm(String name) {
    return 'Xóa \"$name\" khỏi danh sách?';
  }

  @override
  String get alsoDeleteVenvFromDisk => 'Đồng thời xóa thư mục venv trên ổ đĩa';

  @override
  String registeredVenv(String name) {
    return 'Đã đăng ký: $name';
  }

  @override
  String get filePNotFound => 'Không tìm thấy file';

  @override
  String get renameVenv => 'Đổi tên venv';

  @override
  String get labelField => 'Nhãn';

  @override
  String get labelHint => 'VD: Odoo 17 Production';

  @override
  String get createVenvSubtitle => 'Tạo môi trường ảo Python cho dự án Odoo.';

  @override
  String get pythonVersionLabel => 'Phiên bản Python';

  @override
  String pythonVersionDetail(String version, String path) {
    return 'Python $version ($path)';
  }

  @override
  String get noPythonWithVenv => 'Không tìm thấy Python hỗ trợ venv';

  @override
  String get targetDirectory => 'Thư mục đích';

  @override
  String get venvName => 'Tên môi trường ảo';

  @override
  String get venvNameHint => 'venv';

  @override
  String get createVenv => 'Tạo Venv';

  @override
  String get installedPackages => 'Packages đã cài';

  @override
  String packagesCount(int count) {
    return '$count packages';
  }

  @override
  String get searchPackages => 'Tìm packages...';

  @override
  String errorLabel(String error) {
    return 'Lỗi: $error';
  }

  @override
  String get packageHeader => 'Package';

  @override
  String get versionHeader => 'Phiên bản';

  @override
  String get noPackagesFound => 'Không tìm thấy package.';

  @override
  String installPackagesTitle(String name) {
    return 'Cài đặt Packages — $name';
  }

  @override
  String get packagesField => 'Package(s)';

  @override
  String get packagesFieldHint => 'VD: requests paramiko flask>=2.0';

  @override
  String get outputPlaceholder => 'Kết quả sẽ hiển thị ở đây...';

  @override
  String get vscodeConfigTitle => 'Cấu hình VSCode';

  @override
  String get vscodeConfigSubtitle =>
      'Sinh file .vscode/launch.json để debug Odoo.';

  @override
  String get configurationName => 'Tên cấu hình';

  @override
  String get configurationNameHint => 'VD: Debug Odoo Thuế Ba Lan';

  @override
  String get projectDirectoryVscode => 'Thư mục dự án (nơi tạo .vscode/)';

  @override
  String get noRegisteredVenvsHint => 'Chưa có venv đăng ký';

  @override
  String get generating => 'Đang tạo...';

  @override
  String get generateLaunchJson => 'Tạo launch.json';

  @override
  String get previewLabel => 'Xem trước:';

  @override
  String get folderStructureTitle => 'Tạo cấu trúc thư mục';

  @override
  String get folderStructureSubtitle =>
      'Tạo cấu trúc thư mục dự án Odoo tiêu chuẩn.';

  @override
  String get generateStructure => 'Tạo cấu trúc';

  @override
  String get addons => 'addons';

  @override
  String get thirdPartyAddons => 'third_party_addons';

  @override
  String get config => 'config';

  @override
  String get venv => 'venv';

  @override
  String get noOutputYet => 'Chưa có kết quả...';

  @override
  String get colorOdooPurple => 'Tím Odoo';

  @override
  String get colorBlue => 'Xanh dương';

  @override
  String get colorTeal => 'Xanh mòng két';

  @override
  String get colorGreen => 'Xanh lá';

  @override
  String get colorOrange => 'Cam';

  @override
  String get colorRed => 'Đỏ';

  @override
  String get colorPink => 'Hồng';

  @override
  String get colorIndigo => 'Chàm';

  @override
  String get colorCyan => 'Lam';

  @override
  String get colorDeepPurple => 'Tím đậm';

  @override
  String get colorAmber => 'Hổ phách';

  @override
  String get colorBrown => 'Nâu';

  @override
  String get installPython => 'Cài đặt Python';

  @override
  String get installPythonTitle => 'Cài đặt Python';

  @override
  String get installPythonSubtitle =>
      'Chọn phiên bản Python để cài đặt bằng trình quản lý gói hệ thống.';

  @override
  String get selectVersion => 'Chọn phiên bản';

  @override
  String get installing => 'Đang cài đặt...';

  @override
  String get installComplete => 'Cài đặt hoàn tất! Đang quét lại...';

  @override
  String get installFailed =>
      'Cài đặt thất bại. Kiểm tra log để biết chi tiết.';

  @override
  String get packageManagerNotFound => 'Không tìm thấy trình quản lý gói';

  @override
  String get packageManagerNotFoundWindows =>
      'Cần winget để cài Python. Vui lòng cài App Installer từ Microsoft Store.';

  @override
  String get packageManagerNotFoundMac =>
      'Cần Homebrew. Cài đặt tại https://brew.sh';

  @override
  String get packageManagerNotFoundLinux =>
      'Cần apt và pkexec (polkit) để cài đặt Python.';

  @override
  String get navOtherProjects => 'Dự án khác';

  @override
  String get wsTitle => 'Dự án khác';

  @override
  String get wsSubtitle =>
      'Quản lý tất cả dự án phát triển. Truy cập nhanh và mở trong VSCode.';

  @override
  String get wsSearchHint => 'Tìm theo tên, đường dẫn, loại...';

  @override
  String get wsEmpty => 'Chưa có workspace. Nhập thư mục để bắt đầu.';

  @override
  String get wsNoMatch => 'Không có workspace phù hợp.';

  @override
  String get wsFilterByType => 'Lọc theo loại';

  @override
  String get wsShowAll => 'Hiện tất cả';

  @override
  String get wsDeleteTitle => 'Xóa workspace?';

  @override
  String wsDeleteConfirm(String name) {
    return 'Xóa \"$name\" khỏi danh sách?';
  }

  @override
  String get wsImport => 'Nhập Workspace';

  @override
  String get wsEdit => 'Sửa Workspace';

  @override
  String get wsDirectory => 'Thư mục';

  @override
  String get wsSelectDirectory => 'Chọn thư mục workspace';

  @override
  String get wsName => 'Tên';

  @override
  String get wsType => 'Loại';

  @override
  String get wsTypeHint => 'VD: Flutter, React, .NET';

  @override
  String get wsSelectType => 'Chọn loại';

  @override
  String get wsDescriptionHint => 'VD: Dự án frontend cho khách hàng X';

  @override
  String get wsizeSmall => 'Nhỏ';

  @override
  String get wsizeMedium => 'Vừa';

  @override
  String get wsizeLarge => 'Lớn';

  @override
  String get wsViewList => 'Dạng danh sách';

  @override
  String get wsViewGrid => 'Dạng lưới';

  @override
  String get favourite => 'Thêm vào yêu thích';

  @override
  String get unfavourite => 'Bỏ yêu thích';

  @override
  String get wsPort => 'Port (tùy chọn)';

  @override
  String get wsPortHint => 'VD: 3000, 8080';

  @override
  String get nginxSettings => 'Nginx Reverse Proxy';

  @override
  String get nginxConfDir => 'Thư mục conf.d';

  @override
  String get nginxConfDirHint => 'VD: /đường/dẫn/tới/conf.d';

  @override
  String get nginxDomainSuffix => 'Hậu tố domain';

  @override
  String get nginxDomainSuffixHint => 'VD: .namchamvinhcuu.test';

  @override
  String get nginxContainerName => 'Tên Docker Container';

  @override
  String get nginxContainerNameHint => 'VD: nginx';

  @override
  String get nginxSetup => 'Cấu hình Nginx';

  @override
  String get nginxRemove => 'Gỡ Nginx';

  @override
  String nginxDomain(String domain) {
    return '$domain';
  }

  @override
  String nginxSetupSuccess(String domain) {
    return 'Đã cấu hình Nginx: $domain';
  }

  @override
  String nginxRemoveSuccess(String domain) {
    return 'Đã gỡ Nginx: $domain';
  }

  @override
  String nginxFailed(String error) {
    return 'Lỗi Nginx: $error';
  }

  @override
  String get nginxNotConfigured => 'Cấu hình Nginx trong Cài đặt trước';

  @override
  String nginxConfirmRemove(String name) {
    return 'Gỡ cấu hình nginx cho \"$name\"?';
  }

  @override
  String get nginxNoPort => 'Cần thiết lập port trước khi cấu hình Nginx';

  @override
  String get nginxSaved => 'Đã lưu cấu hình Nginx';

  @override
  String get nginxSubdomain => 'Subdomain';

  @override
  String nginxPreviewDomain(String domain) {
    return 'Domain: $domain';
  }

  @override
  String get dockerStatus => 'Docker';

  @override
  String get dockerInstalled => 'Đã cài đặt';

  @override
  String get dockerNotInstalled => 'Chưa cài đặt';

  @override
  String get dockerRunning => 'Đang chạy';

  @override
  String get dockerStopped => 'Đã dừng';

  @override
  String get dockerInstall => 'Cài đặt Docker';

  @override
  String get dockerInstallTitle => 'Cài đặt Docker';

  @override
  String get dockerInstallSubtitle =>
      'Cài đặt Docker Desktop bằng trình quản lý gói hệ thống.';

  @override
  String dockerVersion(String version) {
    return '$version';
  }

  @override
  String get dockerOpenDesktop => 'Vui lòng mở Docker Desktop để khởi động.';

  @override
  String get nginxInitTitle => 'Khởi tạo Nginx Project';

  @override
  String get nginxInitSubtitle =>
      'Tạo cấu trúc thư mục nginx với docker-compose, SSL certs và config.';

  @override
  String get nginxInitBaseDir => 'Thư mục gốc';

  @override
  String get nginxInitFolderName => 'Tên thư mục';

  @override
  String get nginxInitDomain => 'Domain (cho SSL cert)';

  @override
  String get nginxInitDomainHint => 'VD: namchamvinhcuu.test';

  @override
  String get nginxImport => 'Nhập có sẵn';

  @override
  String get nginxPortCheck => 'Kiểm tra Port';

  @override
  String nginxPortFree(int port) {
    return 'Port $port sẵn sàng';
  }

  @override
  String nginxPortInUse(int port, String process, String pid) {
    return 'Port $port đang bị chiếm bởi $process (PID: $pid)';
  }

  @override
  String nginxPortDocker(int port, String name) {
    return 'Port $port — Docker container \"$name\"';
  }

  @override
  String get nginxDockerRunning => 'Docker nginx đang chạy';

  @override
  String get nginxDockerStopped => 'Docker nginx chưa chạy';

  @override
  String get dockerNotInstalledBanner =>
      'Docker chưa được cài đặt. Cài Docker để sử dụng đầy đủ chức năng.';

  @override
  String get dockerNotRunningBanner =>
      'Docker daemon chưa chạy. Khởi động Docker Desktop để sử dụng đầy đủ chức năng.';

  @override
  String get dockerGoToSettings => 'Đi tới Cài đặt';

  @override
  String get nginxKillProcess => 'Dừng tiến trình';

  @override
  String nginxKillConfirm(String process, String pid, int port) {
    return 'Dừng $process (PID: $pid) để giải phóng port $port?';
  }

  @override
  String nginxKillSuccess(int port) {
    return 'Đã dừng tiến trình. Port $port đã sẵn sàng.';
  }

  @override
  String nginxKillFailed(String error) {
    return 'Không thể dừng tiến trình: $error';
  }

  @override
  String get nginxLocalDetected => 'Phát hiện nginx cài trực tiếp';

  @override
  String get nginxLocalDisableHint =>
      'Để tắt nginx local không tự khởi động lại:';

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
  String get nginxInitCreate => 'Tạo cấu trúc';

  @override
  String get nginxDeleteTitle => 'Xóa cấu hình Nginx?';

  @override
  String get nginxDeleteConfirmText =>
      'Thao tác này sẽ xóa cấu hình nginx khỏi ứng dụng.';

  @override
  String get nginxDeleteAlsoFolder => 'Đồng thời xóa thư mục nginx trên ổ đĩa';

  @override
  String get nginxDeleted => 'Đã xóa cấu hình Nginx';

  @override
  String nginxInitSuccess(String path) {
    return 'Đã tạo nginx project tại $path';
  }

  @override
  String nginxInitFailed(String error) {
    return 'Thất bại: $error';
  }

  @override
  String get nginxInitMkcertRequired => 'Cần mkcert để tạo chứng chỉ SSL';

  @override
  String get nginxInitMkcertInstall =>
      'Cài đặt: brew install mkcert (macOS) hoặc apt install mkcert (Linux)';

  @override
  String get nginxInvalidSubdomain =>
      'Chỉ cho phép chữ thường, số và dấu gạch ngang';

  @override
  String get nginxDomainConflict => 'Subdomain này đã được sử dụng';

  @override
  String get nginxLink => 'Liên kết Nginx có sẵn';

  @override
  String get nginxLinkSubdomain => 'Subdomain có sẵn';

  @override
  String get nginxLinkHint => 'Chọn conf đã tạo trước đó';

  @override
  String nginxLinked(String domain) {
    return 'Đã liên kết: $domain';
  }

  @override
  String nginxPortConflict(int port, String name) {
    return 'Port $port đã được proxy bởi \"$name\"';
  }
}
