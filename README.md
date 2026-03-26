# Odoo Auto Config

Flutter desktop app (macOS/Linux/Windows) giup developer Odoo thiet lap va quan ly moi truong phat trien.

## Installation (Windows)

### Cach 1: Chay truc tiep (Portable)

Copy toan bo folder `build\windows\x64\runner\Release\` va chay `odoo_auto_config.exe`.

### Cach 2: Cai dat bang MSIX

MSIX duoc ky bang self-signed certificate. Truoc khi cai `.msix`, ban can cai certificate truoc.

#### Buoc 1: Cai dat Certificate

**Cach A: Dung PowerShell (Admin)**

1. Mo PowerShell voi quyen **Run as Administrator**
2. Chay lenh sau (thay duong dan tuong ung):

```powershell
$pwd = ConvertTo-SecureString -String "odoo123" -Force -AsPlainText
Import-PfxCertificate -FilePath "C:\duong\dan\toi\certificate.pfx" -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" -Password $pwd
```

**Cach B: Cai thu cong qua GUI**

1. Double-click file `certificate.pfx`
2. Chon **Local Machine** → Next
3. Nhap password: `odoo123` → Next
4. Chon **Place all certificates in the following store** → Browse
5. Chon **Trusted People** → OK → Next → Finish

#### Buoc 2: Cai dat MSIX

Double-click file `odoo_auto_config.msix` → nhan **Install**.

### Go cai dat (Uninstall)

**Cach 1:** Click phai vao app **Odoo Auto Config** trong Start Menu → **Uninstall**.

**Cach 2:** Vao **Settings** → **Apps** → **Installed apps** → tim "Odoo Auto Config" → nhan **⋯** → **Uninstall**.

**Cach 3:** Dung PowerShell:

```powershell
Get-AppxPackage *odoo-auto-config* | Remove-AppxPackage
```

> Luu y: Du lieu cau hinh tai `~/.config/odoo_auto_config/` se khong bi xoa khi uninstall. Xoa thu cong neu can.

## Build

### Yeu cau

- Flutter SDK ^3.9.2 (FVM managed)
- Visual Studio 2022 voi C++ desktop workload (cho Windows build)

### Build Windows (Portable)

```bash
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\odoo_auto_config.exe`

### Build MSIX (Windows Installer)

```bash
flutter clean
flutter pub get
dart run msix:create --install-certificate false
```

Output: `build\windows\x64\runner\Release\odoo_auto_config.msix`

### Build macOS

```bash
flutter build macos --release
```

Xem them CLAUDE.md de biet cach tao DMG installer.

## Development

```bash
flutter run -d windows   # hoac macos, linux
```
