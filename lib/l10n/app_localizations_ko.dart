// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'Odoo Auto Config';

  @override
  String get navOdooProjects => 'Odoo 프로젝트';

  @override
  String get navProfiles => '프로필';

  @override
  String get navPythonCheck => 'Python 확인';

  @override
  String get navVenvManager => 'Venv 관리';

  @override
  String get navVscodeConfig => 'VSCode 설정';

  @override
  String get navSettings => '설정';

  @override
  String get cancel => '취소';

  @override
  String get delete => '삭제';

  @override
  String get save => '저장';

  @override
  String get create => '생성';

  @override
  String get edit => '편집';

  @override
  String get import_ => '가져오기';

  @override
  String get close => '닫기';

  @override
  String get install => '설치';

  @override
  String get refresh => '새로고침';

  @override
  String get rescan => '재검색';

  @override
  String get rename => '이름 변경';

  @override
  String get browse => '찾아보기...';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsSubtitle => '테마 및 외관을 사용자 정의합니다.';

  @override
  String get themeMode => '테마 모드';

  @override
  String get themeSystem => '시스템';

  @override
  String get themeLight => '밝게';

  @override
  String get themeDark => '어둡게';

  @override
  String get accentColor => '강조 색상';

  @override
  String get preview => '미리보기';

  @override
  String get filledButton => '채움 버튼';

  @override
  String get tonalButton => '톤 버튼';

  @override
  String get outlined => '윤곽선';

  @override
  String get language => '언어';

  @override
  String get projectsTitle => 'Odoo 프로젝트';

  @override
  String get projectsSubtitle =>
      '빠른 접근이 가능한 모든 Odoo 프로젝트. 기존 프로젝트를 가져오거나 새로 만드세요.';

  @override
  String get projectsSearchHint => '이름, 경로, 라벨, 포트로 검색...';

  @override
  String get projectsEmpty => '프로젝트가 없습니다. 빠른 생성 또는 가져오기를 사용하세요.';

  @override
  String get projectsNoMatch => '검색 결과가 없습니다.';

  @override
  String projectHttpPort(int port) {
    return 'HTTP: $port';
  }

  @override
  String projectLpPort(int port) {
    return 'LP: $port';
  }

  @override
  String get openInVscode => 'VSCode에서 열기';

  @override
  String get openFolder => '폴더 열기';

  @override
  String get removeFromList => '목록에서 제거';

  @override
  String get deleteProjectTitle => '프로젝트 삭제?';

  @override
  String deleteProjectConfirm(String name) {
    return '목록에서 \"$name\"을(를) 제거하시겠습니까?';
  }

  @override
  String get alsoDeleteFromDisk => '디스크에서 프로젝트 디렉토리도 삭제';

  @override
  String deletedPath(String path) {
    return '삭제됨: $path';
  }

  @override
  String failedToDelete(String error) {
    return '삭제 실패: $error';
  }

  @override
  String couldNotOpen(String path) {
    return '열 수 없음: $path';
  }

  @override
  String get couldNotOpenVscode => 'VSCode를 열 수 없습니다';

  @override
  String get editProject => '프로젝트 편집';

  @override
  String get importExistingProject => '기존 프로젝트 가져오기';

  @override
  String get projectDirectory => '프로젝트 디렉토리';

  @override
  String get browseToSelect => '선택하려면 찾아보기...';

  @override
  String get portsAutoDetected => 'odoo.conf에서 포트 자동 감지됨';

  @override
  String get projectName => '프로젝트 이름';

  @override
  String get descriptionOptional => '설명 (선택사항)';

  @override
  String get descriptionHint => '예: 고객 X를 위한 폴란드 세금 프로젝트';

  @override
  String get httpPort => 'HTTP 포트';

  @override
  String get longpollingPort => 'Longpolling 포트';

  @override
  String get selectProjectDirectory => '기존 Odoo 프로젝트 디렉토리 선택';

  @override
  String get quickCreateTitle => '빠른 생성';

  @override
  String get noProfilesFound => '프로필이 없습니다. 먼저 프로필을 만드세요.';

  @override
  String get profile => '프로필';

  @override
  String get baseDirectory => '기본 디렉토리';

  @override
  String get projectNameHint => '예: my_odoo_project';

  @override
  String get portsMustBeDifferent => 'HTTP와 longpolling 포트는 달라야 합니다';

  @override
  String get creating => '생성 중...';

  @override
  String get createProject => '프로젝트 생성';

  @override
  String get done => '완료!';

  @override
  String get profilesTitle => '프로필';

  @override
  String get newProfile => '새 프로필';

  @override
  String get profilesSubtitle => '빠른 프로젝트 생성을 위해 venv + odoo-bin 설정을 저장하세요.';

  @override
  String get profilesEmpty => '프로필이 없습니다. 하나를 만들어 시작하세요.';

  @override
  String get deleteProfileTitle => '프로필 삭제?';

  @override
  String deleteProfileConfirm(String name) {
    return '\"$name\"을(를) 삭제하시겠습니까?';
  }

  @override
  String get editProfile => '프로필 편집';

  @override
  String get profileName => '프로필 이름';

  @override
  String get profileNameHint => '예: Odoo 17';

  @override
  String get virtualEnvironment => '가상 환경';

  @override
  String get selectVenv => 'venv 선택';

  @override
  String get odooBinPath => 'odoo-bin 경로';

  @override
  String get odooBinPathHint => '/path/to/odoo/odoo-bin';

  @override
  String get selectOdooBin => 'odoo-bin 선택';

  @override
  String get odooSourceDirectory => 'Odoo 소스 코드 디렉토리';

  @override
  String get odooSourceHint => '/path/to/odoo (심볼릭 링크 생성)';

  @override
  String get selectOdooSourceDirectory => 'Odoo 소스 코드 디렉토리 선택';

  @override
  String get odooVersion => 'Odoo 버전';

  @override
  String odooVersionLabel(String version) {
    return 'Odoo $version';
  }

  @override
  String get databaseConnection => '데이터베이스 연결';

  @override
  String get host => '호스트';

  @override
  String get port => '포트';

  @override
  String get user => '사용자';

  @override
  String get password => '비밀번호';

  @override
  String get passwordHint => '비워두면 자동 생성';

  @override
  String get sslMode => 'SSL 모드';

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
  String get pythonCheckTitle => 'Python 구성 확인';

  @override
  String get pythonCheckSubtitle => '설치된 Python 버전, pip 및 venv 모듈 가용성을 감지합니다.';

  @override
  String get scanningPython => 'Python 설치를 검색 중...';

  @override
  String get error => '오류';

  @override
  String get noPythonFound => 'Python을 찾을 수 없음';

  @override
  String get noPythonFoundSubtitle =>
      'Python 설치가 감지되지 않았습니다. Python 3.8+를 설치하세요.';

  @override
  String pythonVersion(String version) {
    return 'Python $version';
  }

  @override
  String pathLabel(String path) {
    return '경로: $path';
  }

  @override
  String pipVersion(String version) {
    return 'pip $version';
  }

  @override
  String get venvModule => 'venv 모듈';

  @override
  String get venvTitle => '가상 환경';

  @override
  String get registered => '등록됨';

  @override
  String get scan => '검색';

  @override
  String get createNew => '새로 만들기';

  @override
  String get venvRegisteredSubtitle => '빠른 접근을 위해 저장된 가상 환경.';

  @override
  String get noRegisteredVenvs => '등록된 venv 없음';

  @override
  String get noRegisteredVenvsSubtitle => '새 venv를 만들거나 기존 venv를 검색하여 등록하세요.';

  @override
  String get scanSubtitle => '디렉토리를 검색하여 기존 가상 환경을 찾습니다.';

  @override
  String get scanDirectory => '검색 디렉토리';

  @override
  String get scanning => '검색 중...';

  @override
  String get scanningVenvs => '가상 환경을 검색 중...';

  @override
  String get noVenvsFound => '가상 환경을 찾을 수 없음';

  @override
  String get noVenvsFoundSubtitle => '다른 디렉토리를 검색하거나 깊이를 늘려보세요.';

  @override
  String get registerThisVenv => '이 venv 등록';

  @override
  String get registeredChip => '등록됨';

  @override
  String get listInstalledPackages => '설치된 패키지 목록';

  @override
  String get pipInstallPackage => 'pip install 패키지';

  @override
  String get installRequirements => 'requirements.txt 설치';

  @override
  String get valid => '유효';

  @override
  String get broken => '손상됨';

  @override
  String get deleteVenvTitle => '가상 환경 삭제?';

  @override
  String deleteVenvConfirm(String name) {
    return '등록 목록에서 \"$name\"을(를) 제거하시겠습니까?';
  }

  @override
  String get alsoDeleteVenvFromDisk => '디스크에서 venv 디렉토리도 삭제';

  @override
  String registeredVenv(String name) {
    return '등록됨: $name';
  }

  @override
  String get filePNotFound => '파일을 찾을 수 없음';

  @override
  String get renameVenv => 'venv 이름 변경';

  @override
  String get labelField => '라벨';

  @override
  String get labelHint => '예: Odoo 17 Production';

  @override
  String get createVenvSubtitle => 'Odoo 프로젝트를 위한 Python 가상 환경을 만듭니다.';

  @override
  String get pythonVersionLabel => 'Python 버전';

  @override
  String pythonVersionDetail(String version, String path) {
    return 'Python $version ($path)';
  }

  @override
  String get noPythonWithVenv => 'venv를 지원하는 Python을 찾을 수 없음';

  @override
  String get targetDirectory => '대상 디렉토리';

  @override
  String get venvName => '가상 환경 이름';

  @override
  String get venvNameHint => 'venv';

  @override
  String get createVenv => 'Venv 생성';

  @override
  String get installedPackages => '설치된 패키지';

  @override
  String packagesCount(int count) {
    return '$count개 패키지';
  }

  @override
  String get searchPackages => '패키지 검색...';

  @override
  String errorLabel(String error) {
    return '오류: $error';
  }

  @override
  String get packageHeader => '패키지';

  @override
  String get versionHeader => '버전';

  @override
  String get noPackagesFound => '패키지를 찾을 수 없습니다.';

  @override
  String installPackagesTitle(String name) {
    return '패키지 설치 — $name';
  }

  @override
  String get packagesField => '패키지';

  @override
  String get packagesFieldHint => '예: requests paramiko flask>=2.0';

  @override
  String get outputPlaceholder => '결과가 여기에 표시됩니다...';

  @override
  String get vscodeConfigTitle => 'VSCode 설정';

  @override
  String get vscodeConfigSubtitle => 'Odoo 디버그를 위한 .vscode/launch.json을 생성합니다.';

  @override
  String get configurationName => '설정 이름';

  @override
  String get configurationNameHint => '예: Debug Polish Tax Odoo';

  @override
  String get projectDirectoryVscode => '프로젝트 디렉토리 (.vscode/가 생성될 위치)';

  @override
  String get noRegisteredVenvsHint => '등록된 venv 없음';

  @override
  String get generating => '생성 중...';

  @override
  String get generateLaunchJson => 'launch.json 생성';

  @override
  String get previewLabel => '미리보기:';

  @override
  String get folderStructureTitle => '폴더 구조 생성';

  @override
  String get folderStructureSubtitle => '표준 Odoo 개발 프로젝트 구조를 만듭니다.';

  @override
  String get generateStructure => '구조 생성';

  @override
  String get addons => 'addons';

  @override
  String get thirdPartyAddons => 'third_party_addons';

  @override
  String get config => 'config';

  @override
  String get venv => 'venv';

  @override
  String get noOutputYet => '아직 출력이 없습니다...';

  @override
  String get colorOdooPurple => '오두 퍼플';

  @override
  String get colorBlue => '파랑';

  @override
  String get colorTeal => '틸';

  @override
  String get colorGreen => '초록';

  @override
  String get colorOrange => '주황';

  @override
  String get colorRed => '빨강';

  @override
  String get colorPink => '분홍';

  @override
  String get colorIndigo => '남색';

  @override
  String get colorCyan => '시안';

  @override
  String get colorDeepPurple => '짙은 보라';

  @override
  String get colorAmber => '호박색';

  @override
  String get colorBrown => '갈색';

  @override
  String get installPython => 'Python 설치';

  @override
  String get installPythonTitle => 'Python 설치';

  @override
  String get installPythonSubtitle => '시스템 패키지 관리자를 사용하여 설치할 Python 버전을 선택하세요.';

  @override
  String get selectVersion => '버전 선택';

  @override
  String get installing => '설치 중...';

  @override
  String get installComplete => '설치 완료! 재검색 중...';

  @override
  String get installFailed => '설치 실패. 로그를 확인하세요.';

  @override
  String get packageManagerNotFound => '패키지 관리자를 찾을 수 없음';

  @override
  String get packageManagerNotFoundWindows =>
      'Python을 설치하려면 winget이 필요합니다. Microsoft Store에서 App Installer를 설치하세요.';

  @override
  String get packageManagerNotFoundMac =>
      'Homebrew가 필요합니다. https://brew.sh에서 설치하세요.';

  @override
  String get packageManagerNotFoundLinux =>
      'Python을 설치하려면 apt와 pkexec(polkit)이 필요합니다.';

  @override
  String get navOtherProjects => '기타 프로젝트';

  @override
  String get wsTitle => '기타 프로젝트';

  @override
  String get wsSubtitle => '모든 개발 프로젝트를 관리합니다. 빠른 접근 및 VSCode에서 열기.';

  @override
  String get wsSearchHint => '이름, 경로, 유형으로 검색...';

  @override
  String get wsEmpty => '워크스페이스가 없습니다. 디렉토리를 가져와 시작하세요.';

  @override
  String get wsNoMatch => '검색 결과가 없습니다.';

  @override
  String get wsFilterByType => '유형별 필터';

  @override
  String get wsShowAll => '모두 표시';

  @override
  String get wsDeleteTitle => '워크스페이스 제거?';

  @override
  String wsDeleteConfirm(String name) {
    return '목록에서 \"$name\"을(를) 제거하시겠습니까?';
  }

  @override
  String get wsImport => '워크스페이스 가져오기';

  @override
  String get wsEdit => '워크스페이스 편집';

  @override
  String get wsDirectory => '디렉토리';

  @override
  String get wsSelectDirectory => '워크스페이스 디렉토리 선택';

  @override
  String get wsName => '이름';

  @override
  String get wsType => '유형';

  @override
  String get wsTypeHint => '예: Flutter, React, .NET';

  @override
  String get wsSelectType => '유형 선택';

  @override
  String get wsDescriptionHint => '예: 고객 X 프론트엔드 프로젝트';

  @override
  String get wsizeSmall => '작게';

  @override
  String get wsizeMedium => '보통';

  @override
  String get wsizeLarge => '크게';

  @override
  String get wsViewList => '목록 보기';

  @override
  String get wsViewGrid => '격자 보기';

  @override
  String get favourite => '즐겨찾기 추가';

  @override
  String get unfavourite => '즐겨찾기 제거';

  @override
  String get wsPort => '포트 (선택사항)';

  @override
  String get wsPortHint => '예: 3000, 8080';

  @override
  String get nginxSettings => 'Nginx 리버스 프록시';

  @override
  String get nginxConfDir => 'conf.d 디렉토리';

  @override
  String get nginxConfDirHint => '예: /path/to/conf.d';

  @override
  String get nginxDomainSuffix => '도메인 접미사';

  @override
  String get nginxDomainSuffixHint => '예: .namchamvinhcuu.test';

  @override
  String get nginxContainerName => 'Docker 컨테이너 이름';

  @override
  String get nginxContainerNameHint => '예: nginx';

  @override
  String get nginxSetup => 'Nginx 설정';

  @override
  String get nginxRemove => 'Nginx 제거';

  @override
  String nginxDomain(String domain) {
    return '$domain';
  }

  @override
  String nginxSetupSuccess(String domain) {
    return 'Nginx 설정 완료: $domain';
  }

  @override
  String nginxRemoveSuccess(String domain) {
    return 'Nginx 제거 완료: $domain';
  }

  @override
  String nginxFailed(String error) {
    return 'Nginx 오류: $error';
  }

  @override
  String get nginxNotConfigured => '설정에서 Nginx를 먼저 구성하세요';

  @override
  String nginxConfirmRemove(String name) {
    return '\"$name\"의 nginx 설정을 제거하시겠습니까?';
  }

  @override
  String get nginxNoPort => 'Nginx를 설정하려면 먼저 포트를 설정하세요';

  @override
  String get nginxSaved => 'Nginx 설정 저장됨';

  @override
  String get nginxSubdomain => '서브도메인';

  @override
  String nginxPreviewDomain(String domain) {
    return '도메인: $domain';
  }

  @override
  String get nginxDomainConflict => '이 서브도메인은 이미 사용 중입니다';

  @override
  String nginxPortConflict(int port, String name) {
    return '포트 $port은(는) 이미 \"$name\"에서 프록시 중입니다';
  }
}
