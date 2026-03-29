// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'Workspace Configuration';

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
  String get general => '일반';

  @override
  String get cloneOdooSource => 'Odoo 클론';

  @override
  String get cloneOdooTitle => 'Odoo 소스 클론';

  @override
  String get cloneOdooSubtitle => '개발을 위해 GitHub에서 Odoo 소스 코드를 클론합니다.';

  @override
  String get cloneOdooFolder => '폴더 이름';

  @override
  String get shallowClone => '얕은 클론 (--depth 1, 빠른 다운로드)';

  @override
  String get cloning => '클론 중...';

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
  String get uninstallPython => 'Python 제거';

  @override
  String uninstallPythonConfirm(String version) {
    return 'Python $version을(를) 제거하시겠습니까?';
  }

  @override
  String get uninstalling => '제거 중...';

  @override
  String get symlinkErrorTitle => '심볼릭 링크를 만들 수 없습니다';

  @override
  String get symlinkErrorDesc =>
      'Windows에서 심볼릭 링크를 만들려면 개발자 모드를 활성화해야 합니다. 프로젝트가 생성되지 않았습니다.';

  @override
  String get symlinkErrorSteps => '개발자 모드 활성화 방법:';

  @override
  String get symlinkErrorStep1 => '1. Windows 설정 열기 (Win + I)';

  @override
  String get symlinkErrorStep2 => '2. 시스템 > 개발자용으로 이동';

  @override
  String get symlinkErrorStep3 => '3. 개발자 모드 켜기';

  @override
  String get symlinkErrorStep4 => '4. 돌아와서 다시 시도';

  @override
  String get symlinkErrorRetry => '개발자 모드를 활성화한 후 프로젝트를 다시 만들어 보세요.';

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
  String get dockerStatus => 'Docker';

  @override
  String get dockerInstalled => '설치됨';

  @override
  String get dockerNotInstalled => '설치되지 않음';

  @override
  String get dockerRunning => '실행 중';

  @override
  String get dockerStopped => '중지됨';

  @override
  String get startDockerDesktop => 'Docker Desktop 시작';

  @override
  String get starting => '시작 중...';

  @override
  String get dockerInstall => 'Docker 설치';

  @override
  String get dockerInstallTitle => 'Docker 설치';

  @override
  String get dockerInstallSubtitle =>
      '시스템 패키지 관리자를 사용하여 Docker Desktop을 설치합니다.';

  @override
  String dockerVersion(String version) {
    return '$version';
  }

  @override
  String get dockerOpenDesktop => 'Docker Desktop을 열어 데몬을 시작하세요.';

  @override
  String get nginxInitTitle => 'Nginx 프로젝트 초기화';

  @override
  String get nginxInitSubtitle =>
      'docker-compose, SSL 인증서, 설정이 포함된 nginx 폴더 구조를 생성합니다.';

  @override
  String get nginxInitBaseDir => '기본 디렉토리';

  @override
  String get nginxInitFolderName => '폴더 이름';

  @override
  String get nginxInitDomain => '도메인 (SSL 인증서용)';

  @override
  String get nginxInitDomainHint => '예: namchamvinhcuu.test';

  @override
  String get nginxImport => '기존 가져오기';

  @override
  String get nginxPortCheck => '포트 확인';

  @override
  String nginxPortFree(int port) {
    return '포트 $port 사용 가능';
  }

  @override
  String nginxPortInUse(int port, String process, String pid) {
    return '포트 $port이(가) $process에 의해 사용 중 (PID: $pid)';
  }

  @override
  String nginxPortDocker(int port, String name) {
    return '포트 $port — Docker 컨테이너 \"$name\"';
  }

  @override
  String get nginxDockerRunning => 'Docker nginx 실행 중';

  @override
  String get nginxDockerStopped => 'Docker nginx 중지됨';

  @override
  String get dockerNotInstalledBanner =>
      'Docker가 설치되지 않았습니다. 모든 기능을 사용하려면 Docker를 설치하세요.';

  @override
  String get dockerNotRunningBanner =>
      'Docker 데몬이 실행되지 않았습니다. 모든 기능을 사용하려면 Docker Desktop을 시작하세요.';

  @override
  String get dockerGoToSettings => '설정으로 이동';

  @override
  String get nginxKillProcess => '프로세스 종료';

  @override
  String nginxKillConfirm(String process, String pid, int port) {
    return '포트 $port을(를) 해제하기 위해 $process (PID: $pid)을(를) 종료하시겠습니까?';
  }

  @override
  String nginxKillSuccess(int port) {
    return '프로세스가 종료되었습니다. 포트 $port이(가) 사용 가능합니다.';
  }

  @override
  String nginxKillFailed(String error) {
    return '프로세스 종료 실패: $error';
  }

  @override
  String get nginxLocalDetected => '로컬 nginx 감지됨';

  @override
  String get nginxLocalDisableHint => '로컬 nginx 자동 시작을 비활성화하려면:';

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
  String get nginxInitCreate => '구조 생성';

  @override
  String get nginxDeleteTitle => 'Nginx 설정 삭제?';

  @override
  String get nginxDeleteConfirmText => '앱에서 nginx 설정이 제거됩니다.';

  @override
  String get nginxDeleteAlsoFolder => '디스크에서 nginx 폴더도 삭제';

  @override
  String get nginxDeleted => 'Nginx 설정이 제거되었습니다';

  @override
  String nginxInitSuccess(String path) {
    return '$path에 nginx 프로젝트가 생성되었습니다';
  }

  @override
  String nginxInitFailed(String error) {
    return '실패: $error';
  }

  @override
  String get nginxInitMkcertRequired => 'SSL 인증서 생성에 mkcert가 필요합니다';

  @override
  String get nginxInitMkcertInstall => '아래 버튼을 클릭하여 mkcert를 자동으로 설치하세요.';

  @override
  String get nginxInvalidSubdomain => '소문자, 숫자, 하이픈만 허용됩니다';

  @override
  String get nginxDomainConflict => '이 서브도메인은 이미 사용 중입니다';

  @override
  String get nginxLink => '기존 Nginx 연결';

  @override
  String get nginxLinkSubdomain => '기존 서브도메인';

  @override
  String get nginxLinkHint => '이전에 생성한 conf 선택';

  @override
  String nginxLinked(String domain) {
    return '연결됨: $domain';
  }

  @override
  String nginxPortConflict(int port, String name) {
    return '포트 $port은(는) 이미 \"$name\"에서 프록시 중입니다';
  }

  @override
  String get postgresStatus => 'PostgreSQL Client Tools';

  @override
  String get postgresInstalled => '설치됨';

  @override
  String get postgresNotInstalled => '설치되지 않음';

  @override
  String get postgresRunning => '서버 실행 중';

  @override
  String get postgresStopped => '서버 중지됨';

  @override
  String get postgresInstall => '설치';

  @override
  String get postgresInstallTitle => 'PostgreSQL 클라이언트 도구 설치';

  @override
  String get postgresInstallSubtitle =>
      'PostgreSQL 데이터베이스를 관리하기 위한 클라이언트 도구(psql, pg_dump, pg_restore, createdb, dropdb)를 설치합니다.';

  @override
  String get postgresClientTools => '클라이언트 도구';

  @override
  String get postgresClientNote =>
      '클라이언트 도구는 PostgreSQL 서버(로컬 또는 Docker)에 연결하는 데 사용됩니다. Docker를 사용하면 서버 설치가 필요 없습니다.';

  @override
  String get postgresToolAvailable => '사용 가능';

  @override
  String get postgresToolMissing => '없음';

  @override
  String get postgresServerStatus => '서버 상태';

  @override
  String get postgresNoServer => 'PostgreSQL 서버가 감지되지 않았습니다 (로컬 또는 Docker)';

  @override
  String get postgresContainer => '컨테이너';

  @override
  String get postgresImage => '이미지';

  @override
  String get postgresService => '서비스';

  @override
  String get postgresPort => '포트';

  @override
  String get postgresReady => '연결 수락 중';

  @override
  String get postgresNotReady => '응답 없음';

  @override
  String get postgresContainerRunning => '실행 중';

  @override
  String get postgresContainerStopped => '중지됨';

  @override
  String get postgresSetupDocker => 'PostgreSQL Docker 설정';

  @override
  String get postgresSetupTitle => 'PostgreSQL Docker 설정';

  @override
  String get postgresSetupSubtitle =>
      'docker-compose로 PostgreSQL Docker 프로젝트를 생성합니다.';

  @override
  String get postgresSetupBaseDir => '기본 디렉토리';

  @override
  String get postgresSetupFolderName => '폴더 이름';

  @override
  String get postgresSetupContainerName => '컨테이너 이름';

  @override
  String get postgresSetupImage => 'Docker 이미지';

  @override
  String get postgresSetupUser => 'DB 사용자';

  @override
  String get postgresSetupPassword => 'DB 비밀번호';

  @override
  String get postgresSetupDbName => '기본 데이터베이스';

  @override
  String get postgresSetupPort => '호스트 포트';

  @override
  String get postgresSetupNetwork => 'Docker 네트워크';

  @override
  String postgresSetupSuccess(String path) {
    return '$path에 PostgreSQL Docker 프로젝트가 생성되었습니다';
  }
}
