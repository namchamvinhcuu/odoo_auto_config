# CLAUDE.md — Workspace Configuration (Flutter desktop)

Hướng dẫn làm việc cho Claude trong dự án — gồm **Behavioral Principles** + pointer tới knowledge base. **Portable across máy:** principles không hardcode version/path, mọi giá trị resolve dynamic từ `.fvmrc` / `pubspec.lock` / FVM symlink.

**Project Knowledge Base** sống trong Obsidian vault, truy cập qua symlink `./.obsidian-vault/` (atomic notes tổ chức theo `Architecture/` / `Features/` / `Knowledge-Base/` / `Fix-History/`). Khi cần reference về tech stack, modules, skills, bugs — đọc vault qua [`./.obsidian-vault/Index.md`](.obsidian-vault/Index.md).

### ⚙️ Per-machine setup (nếu `.obsidian-vault` chưa tồn tại)

Vault path tuỳ máy + tuỳ cloud provider user dùng (OneDrive / Google Drive / Dropbox / iCloud / local clone…). Symlink `.obsidian-vault` ở root project là **abstraction duy nhất Claude cần biết** — Claude KHÔNG đọc target path, chỉ đọc qua symlink.

**Trách nhiệm setup symlink thuộc về user** (machine-specific, không version control):

```bash
# Generic form — user thay <vault-path> bằng path thực tế trên máy hiện tại
ln -s <vault-path> ./.obsidian-vault

# Verify symlink resolve được
ls .obsidian-vault/Index.md
```

Symlink `.obsidian-vault` đã trong `.gitignore`. Nếu trên máy mới chưa có → user tự tạo symlink trỏ tới vault đã sync về máy đó (qua bất kỳ cloud provider nào).

Nếu `ls .obsidian-vault/Index.md` fail → báo user setup symlink trước khi tiếp tục, KHÔNG đoán path.

---

# PHẦN 1 — BEHAVIORAL PRINCIPLES

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific knowledge in `.obsidian-vault/`.

**Ordering = session lifecycle.** Đọc tuần tự 1→15 để biết cần làm gì ở từng phase:

| Phase            | Principles                                                                                                                                                                     | Mục đích                                      |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------- |
| 🗣️ Communication | #1 Ask in Vietnamese                                                                                                                                                           | Ngôn ngữ giao tiếp                            |
| ⚙️ Environment   | #2 Flutter SDK via FVM, #3 Upstream Framework Reference                                                                                                                        | Setup tooling + tra cứu source                |
| 🧠 Plan          | #4 Think Before Coding, #5 Goal-Driven, #6 Vault-First Debug                                                                                                                   | Phân tích, success criteria, investigation    |
| ✍️ Code          | #7 Simplicity First, #8 Surgical Changes, #9 Riverpod + SOLID, #10 i18n Proactive, #11 No Hardcoded UI Values, #12 Cross-Platform Process Safety, #13 Comment Out Don't Delete | Khi viết/sửa code                             |
| ✅ Verify        | #14 Test-Driven Quality                                                                                                                                                        | Xác nhận hoạt động đúng + zero analyze issues |
| 📝 Document      | #15 Knowledge Loop                                                                                                                                                             | Lưu lại tri thức                              |

**Tradeoff:** caution over speed. Trivial tasks: dùng judgment.

---

## 1. Ask in Vietnamese

**Every clarifying question or user-facing prompt must be in Vietnamese.**

Khi hỏi user về:

- Clarifying questions về task mơ hồ → tiếng Việt
- Presenting alternatives ("A hay B?") → tiếng Việt
- Requesting missing info (file paths, config values, credentials) → tiếng Việt
- Surfacing tradeoffs với recommendation → tiếng Việt
- Confirming destructive actions → tiếng Việt

**KHÔNG áp dụng cho** (giữ ngôn ngữ project):

- Code, variable/function/identifier names
- Commit messages, PR titles, CHANGELOG entries
- Code comments (theo convention module)
- File / vault note names
- Error messages copy từ tools/logs

**Why:** User là người Việt; hỏi tiếng Anh tốn thêm parsing step → response chậm và kém chính xác hơn.

---

## 2. Flutter SDK via FVM — Luôn dùng version đúng project

**KHI cần chạy Flutter (build, test, run, pub), LUÔN dùng FVM-resolved `flutter`. KHÔNG dùng system flutter.**

### Mandatory workflow

```bash
# 1) Verify FVM resolves đúng version (mọi máy: ~/fvm/default/bin/flutter)
which flutter
# → ~/fvm/default/bin/flutter (symlink tới version theo .fvmrc)

# 2) Đọc version pin từ project (KHÔNG hardcode trong CLAUDE.md)
cat .fvmrc            # → {"flutter": "X.Y.Z"} - version dự án pin
flutter --version     # phải match X.Y.Z

# 3) Nếu chưa cài đúng version
fvm install
fvm use --force
```

Nếu `which flutter` KHÔNG trỏ tới `~/fvm/default/bin/` → PATH sai, sửa `~/.zshrc` (Mac) hoặc `~/.bashrc` (Linux):

```bash
export PATH="$HOME/fvm/default/bin:$PATH"
```

### Common commands (auto-resolve qua FVM)

```bash
fvm flutter pub get                  # install dependencies
fvm flutter run -d macos             # run trên macOS
fvm flutter run -d linux             # run trên Linux
fvm flutter run -d windows           # run trên Windows
fvm flutter test                     # unit + widget tests
fvm flutter analyze                  # static analysis (lint + type check)
fvm flutter gen-l10n                 # generate localization delegate
fvm flutter build macos --release    # release macOS (DMG + ZIP)
fvm flutter build linux --release    # release Linux (AppImage / deb / rpm)
fvm flutter build windows --release  # release Windows (MSIX + EVB portable)
```

⚠️ Flag `-d` bắt buộc cho `run` — `fvm flutter run macOS` (không `-d`) báo "Target file not found".

### Tại sao

- Breaking changes giữa Flutter minor versions (3.40 → 3.41 thay đổi widget API)
- Pub packages có Flutter version constraint — sai version → packages reject
- Reproducibility cross-machine: cùng command trên mọi máy (macOS / Linux / Windows) cho cùng kết quả

### Red flags — dừng lại

- `which flutter` trả `/usr/local/bin/flutter` hoặc `/opt/homebrew/bin/flutter` → đang dùng system flutter
- `flutter --version` không match `.fvmrc`
- Build fail "requires Flutter SDK >= X.Y.Z" → version mismatch

→ Cheatsheet chi tiết: [[Knowledge-Base/Skill-Flutter-Dev]].

### Autonomy với Flutter commands

`flutter pub get`, `flutter test`, `flutter analyze`, `flutter gen-l10n`, hot reload trên local dev → **auto-run, KHÔNG cần confirm**. Xem Principle #14 cho chi tiết.

---

## 3. Upstream Framework Reference — tra cứu source thật

**Khi cần verify Flutter / package API (widget property, class signature, package method) — LUÔN query trong source thật. KHÔNG đoán.**

### Source locations (resolve dynamic, không hardcode version)

| Source            | Resolve pattern                                         | Lý do dùng dynamic                  |
| ----------------- | ------------------------------------------------------- | ----------------------------------- |
| Flutter SDK       | `$(dirname $(dirname $(readlink -f $(which flutter))))` | Version từ `.fvmrc`, đổi → path đổi |
| Material widgets  | `<FLUTTER_SDK>/packages/flutter/lib/src/material/`      | Cùng SDK, sub-folder                |
| Cupertino widgets | `<FLUTTER_SDK>/packages/flutter/lib/src/cupertino/`     | Cùng SDK, sub-folder                |
| Pub packages      | `~/.pub-cache/hosted/pub.dev/<pkg>-<version>/lib/`      | Version từ `pubspec.lock`           |

### Mandatory workflow khi nghi vấn API

```bash
# 1) Resolve Flutter SDK path
FLUTTER_SDK=$(dirname $(dirname $(readlink -f $(which flutter))))
echo $FLUTTER_SDK
ls $FLUTTER_SDK/packages/flutter/lib/src/widgets/

# 2) Grep widget / class trong Flutter source
grep -rn "class CircleAvatar" $FLUTTER_SDK/packages/flutter/lib/src/material/

# 3) Resolve pub package version từ pubspec.lock + grep
PKG=flutter_riverpod
PKG_DIR=$(ls -d ~/.pub-cache/hosted/pub.dev/$PKG-*/lib/ 2>/dev/null | sort -V | tail -1)
echo $PKG_DIR
grep -rn "class Notifier" $PKG_DIR

# 4) Đối chiếu với code custom trong lib/ → phát hiện sai lệch
# 5) Chỉ đưa fix sau khi xác nhận source
```

### Tại sao bắt buộc

- Flutter API thay đổi giữa minor versions (`WidgetState` rename, `MaterialState` deprecated, ...)
- Pub package major bump = breaking changes (Riverpod 2 → 3 thay đổi `Notifier` API)
- Đoán dựa training data → fix sai → bugs mới
- Hardcode version trong CLAUDE.md → stale khi project bump → false reference

### Red flags — dừng lại

- "Tôi nghĩ widget này có property X..." → grep trước
- "Riverpod chắc có method Y..." → đọc source
- "API version này vẫn dùng Z..." → check changelog hoặc source

→ Nếu không verify được, **nói rõ là đang đoán**, không khẳng định.

---

## 4. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

---

## 5. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Chuyển yêu cầu mơ hồ thành outcome có thể verify trước khi code:

- "Add validation" → "Input X bị reject với message Y; input Z pass qua"
- "Fix the bug" → "Reproduce ở bước A, sau fix không còn + regression guard"
- "Refactor X" → "Behavior identical trước/sau; diff không đụng logic branch"
- "Add feature" → "Path A/B/C trên UI/API trả kết quả mong đợi"

Success criteria KHÔNG nhất thiết là tests — có thể là manual repro, diff review, screenshot widget render, log output. Tests là phương tiện mạnh nhất nhưng không phải duy nhất (chi tiết: Principle #14).

Multi-step tasks → state plan ngắn:

```
1. [Step] → verify: [check cụ thể]
2. [Step] → verify: [check cụ thể]
3. [Step] → verify: [check cụ thể]
```

Strong criteria → loop độc lập. Weak criteria ("make it work") → phải hỏi user liên tục.

---

## 6. Vault-First Debug — đọc vault TRƯỚC khi đọc code

**Khi user báo lỗi (screenshot, traceback, mô tả) — KHÔNG đọc code ngay. Quét `.obsidian-vault/` TRƯỚC.**

### Thứ tự investigation bắt buộc

1. **Quét `.obsidian-vault/` lần lượt:**
   - `Architecture/` — hiểu flow nghiệp vụ liên quan ([[Architecture/Multi-Instance-IPC]], [[Architecture/Dialog-System]], [[Architecture/State-Management-Riverpod]], etc.)
   - `Fix-History/` — tìm bug tương tự đã fix, xem root cause + pattern. Grep theo keyword triệu chứng.
   - `Knowledge-Base/` — pattern / gotcha về Flutter / Riverpod / cross-platform Process
   - `Features/` — context business logic
2. **Đối chiếu source thật** (Principle #3 nếu cần check Flutter / package source)
3. **Xác định:**
   - Bug cùng root cause với bug cũ? → tái sử dụng fix pattern
   - Flow nào bị impact? Logic đã tested có ảnh hưởng?
4. **Propose fix tôn trọng logic cũ** — không patch triệu chứng làm hỏng flow khác

### Tại sao bắt buộc

Vault chứa: mental model (architecture), lịch sử quyết định (tại sao code viết như vậy), pattern fix đã tested. Đọc code cold không có context → dễ:

- **Fix bề mặt:** patch triệu chứng, không root cause → bug tái xuất hiện
- **Sửa hỏng business rule:** không biết constraint đã document
- **Rediscover bug đã fix:** lãng phí thời gian phân tích cũ
- **Break logic cũ:** fix mới invalidate pattern đã thông qua

### Exception

Skip vault scan CHỈ khi:

- Lỗi trivial (typo 1-2 ký tự)
- User explicitly bảo "fix nhanh, không cần đọc context"

---

## 7. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

---

## 8. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: every changed line should trace directly to user's request.

---

## 9. Riverpod + SOLID — State Management Standard

**Code mới PHẢI dùng Riverpod (Notifier/AsyncNotifier) cho state. Tách logic khỏi UI. Widget file > 500 dòng → split.**

### Rules

- **State management:** Riverpod 2.x — `Notifier`/`AsyncNotifier` cho mutable state, `Provider` cho immutable derived value. KHÔNG dùng `setState` cho non-trivial state, KHÔNG dùng `StatefulWidget` mới (trừ animation/controller stateful).
- **Layer separation:**
  - `lib/notifiers/` — Riverpod notifiers (state + state mutations)
  - `lib/services/` hoặc `lib/repositories/` — IO, network, Process.run, file system
  - `lib/widgets/` hoặc `lib/screens/` — chỉ render. Nhận state qua `ref.watch`, gửi action qua `ref.read(notifierProvider.notifier).method()`
- **File size limit:** widget file > 500 dòng → red flag. Tách subwidget cùng folder, suffix `_section.dart` / `_card.dart` / `_form.dart` theo role.

### Detect violations

```bash
# Widget mới có setState (cho non-trivial state)
grep -rn "setState(" lib/widgets/ lib/screens/

# IO trực tiếp trong widget
grep -rn "Process\.run\|http\.get\|File(" lib/widgets/ lib/screens/

# File widget > 500 dòng
find lib/widgets lib/screens -name "*.dart" -exec wc -l {} + | awk '$1 > 500'
```

### Why

SOLID: Single Responsibility (widget render, notifier state, service IO). Test được Riverpod notifier với `ProviderScope.overrides` mà không cần widget. File nhỏ → đọc/diff dễ, conflict ít khi merge.

→ Reference: [[Architecture/State-Management-Riverpod]], [[Knowledge-Base/Skill-Riverpod-Notifier]] (nếu vault có).

---

## 10. i18n Proactive — Localization First

**Mọi string user-facing PHẢI vào ARB files trước khi commit. KHÔNG hardcode string trong widget build.**

### Rules

- **ARB files:** `lib/l10n/intl_en.arb`, `intl_vi.arb`, ... cho mỗi locale supported (đọc `pubspec.yaml` → `flutter.generate` để xác định locale list).
- **Add string:** thêm vào TẤT CẢ ARB files (en + vi + locales khác). Thiếu 1 file = missing translation runtime.
- **Trong widget:** `Text(AppLocalizations.of(context)!.keyName)`, KHÔNG `Text("Hello")`.
- **Sau add:** chạy `fvm flutter gen-l10n` để regenerate delegate.
- **Key naming:** camelCase mô tả ngữ nghĩa, thống nhất pattern hiện tại (xem ARB files để follow convention).

### Detect violations

```bash
# Raw string literal trong widget (heuristic, có false positive)
grep -rn 'Text("' lib/widgets/ lib/screens/ | grep -v 'l10n\|test'
grep -rn "Text('" lib/widgets/ lib/screens/ | grep -v 'l10n\|test'

# AppBar/Dialog title hardcode
grep -rn 'title: Text("' lib/
```

### Exceptions (KHÔNG cần i18n)

- Logger / debug print: keep raw English (developer-only)
- Const technical strings (URL, env key, command name, regex pattern)
- Test fixtures
- Identifier hiển thị literal (version number, hash, ID)

### Why

Project support nhiều locale (en, vi, ...). Hardcode 1 string = 1 missing translation = bug khi user switch locale. Add string vào ARB sau khi commit code → dễ quên → ship feature thiếu i18n.

→ Reference: [[Knowledge-Base/Skill-i18n-ARB]] (nếu vault có).

---

## 11. No Hardcoded UI Values — Constants Discipline

**UI dimensions (padding, radius, size, spacing) PHẢI lấy từ `AppConstants`. KHÔNG hardcode raw `double`/`int` trong widget.**

### Rules

- **Padding/margin:** `EdgeInsets.all(AppConstants.padding16)`, KHÔNG `EdgeInsets.all(16)`
- **Radius:** `BorderRadius.circular(AppConstants.radiusMedium)`, KHÔNG `BorderRadius.circular(8)`
- **Sizes:** `SizedBox(height: AppConstants.spacingS)`, KHÔNG `SizedBox(height: 12)`
- **Dialog:** dùng `AppDialog.show<T>` với size hint S/M/L → auto responsive width per breakpoint, wrap `SingleChildScrollView` để tránh overflow
- **Colors:** `Theme.of(context).colorScheme.X` hoặc `AppColors.X`, KHÔNG `Color(0xFF...)` raw trong widget

### Detect violations

```bash
# Raw EdgeInsets / SizedBox với số
grep -rn 'EdgeInsets\.all([0-9]' lib/
grep -rn 'EdgeInsets\.symmetric.*: [0-9]' lib/
grep -rn 'SizedBox(height: [0-9]' lib/
grep -rn 'SizedBox(width: [0-9]' lib/

# Hardcode color
grep -rn 'Color(0x' lib/ | grep -v 'app_constants\|app_colors\|theme'

# Raw radius
grep -rn 'BorderRadius\.circular([0-9]' lib/
```

### Exceptions

- File `app_constants.dart` / `app_colors.dart` / `app_theme.dart` (đó là nơi định nghĩa)
- Animation duration / curve constants nội bộ widget animation
- Trị 0 (`EdgeInsets.zero`, `SizedBox.shrink`)

### Why

Single source of truth → đổi spacing/theme 1 lần ảnh hưởng toàn app. Tránh inconsistency (file A dùng 12, file B dùng 14 → UI vỡ rhythm). Responsive: `AppConstants` có thể tính theo breakpoint, raw value cứng nhắc.

→ Reference: `lib/core/constants/app_constants.dart`, [[Knowledge-Base/Skill-Responsive-Layout]] (nếu vault có).

---

## 12. Cross-Platform Process Safety

**Mọi `Process.run` / `Process.start` PHẢI cân nhắc `runInShell` + path separator + executable resolution per platform. Sau refactor đụng tới Process call → BẮT BUỘC chạy audit script.**

### Rules

- **`runInShell`:**
  - Windows: `true` cho `.bat`/`.cmd`/builtin (`dir`, `where`, ...)
  - Linux/macOS: thường `false`, trừ khi cần shell expansion (`*`, `~`, `$VAR`)
  - Wrong flag → command silent fail trên platform sai
- **Path separator:** dùng `path.join(...)` (package `path`), KHÔNG concat string `'foo/bar'`. Windows = `\`, POSIX = `/`.
- **Executable resolution:**
  - `which` (Linux/macOS) vs `where` (Windows) → wrap qua helper hoặc cache absolute path từ user settings
  - `Platform.isWindows ? 'where' : 'which'`
- **Environment vars:** `Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']`
- **Line endings:** parse stdout split `\n` thường OK, nhưng git porcelain Windows trả `\r\n` → strip `\r`

### Mandatory after Process refactor

Chạy audit script (xem [[Knowledge-Base/Skill-Audit-RunInShell]]) — script tự grep `Process.run`/`Process.start` và check flag/path conformance qua 3 OS.

### Detect violations

```bash
# Hardcoded path separator
grep -rn "'/.*'" lib/services/ lib/repositories/ | grep -v "http\|https"
grep -rn '\\\\' lib/services/ lib/repositories/

# Process.run thiếu cân nhắc runInShell
grep -rn "Process\.run\|Process\.start" lib/ | grep -v "runInShell"

# Hardcoded which/where
grep -rn "'which'\|'where'" lib/ | grep -v "Platform.is"
```

### Why

Desktop Flutter chạy 3 OS (macOS/Linux/Windows). 1 sai sót `runInShell` hoặc path = command fail trên 1 OS, pass 2 OS còn lại → bug khó detect khi dev chỉ test 1 máy. Đặc biệt nguy hiểm: Windows sai `runInShell=false` cho builtin → silent fail không log, user không biết.

→ Reference: [[Knowledge-Base/Skill-Audit-RunInShell]], [[Fix-History/RunInShell-Audit]], [[Fix-History/Git-Porcelain-Parsing]].

---

## 13. Comment Out, Don't Delete — Tắt tạm tính năng

**Khi tắt tạm feature (theo user request hoặc theo phase rollout), COMMENT OUT + thêm TODO marker. KHÔNG delete code.**

### Rules

- **Tắt UI tạm:** comment out widget block + `// TODO(disable-YYYY-MM): re-enable khi <điều kiện>`
- **Tắt method tạm:** comment + TODO + reason ngắn
- **Tắt route/feature flag:** comment usage + giữ implementation
- **Delete CHỈ KHI:**
  - User explicit "xóa hẳn"
  - Feature đã thay thế bằng implementation mới (cleanup sau migration)
  - Refactor được user approve trong session

### Format TODO marker

```dart
// TODO(disable-2026-04): tắt tạm theo yêu cầu, re-enable khi backend ready
// Widget gốc:
// ElevatedButton(
//   onPressed: _onSubmit,
//   child: Text(AppLocalizations.of(context)!.submit),
// ),
```

→ Grep `TODO\(disable-` thấy ngay tất cả pending re-enable.

### Exception (delete được)

- Dead code rõ ràng (unused import, orphan method, unreachable branch) — delete OK, không cần comment
- Code chỉ commit chưa push → revert / `git reset` thay vì comment

### Why

- Tắt tạm = thường re-enable sau → comment giữ context (logic, prop, callback) ngay tại chỗ
- Delete + git history vẫn còn nhưng "khuất tầm mắt" → dễ quên implement lại khi tới phase enable
- TODO marker grep được → review nhanh trước release: "feature nào đang tắt?"

---

## 14. Test-Driven Quality — Flutter testing + Zero analyze issues

**Không task nào hoàn thành khi chưa verify hoạt động + `fvm flutter analyze` PASS với 0 issue (kể cả info level).**

### Verify methods (theo loại change)

| Change type                                 | Verify command                                   | Notes                              |
| ------------------------------------------- | ------------------------------------------------ | ---------------------------------- |
| Pure Dart logic (helper, validator, parser) | `fvm flutter test test/<file>_test.dart`         | Unit test                          |
| Widget render / interaction                 | `fvm flutter test` (widget test)                 | UI render + tap                    |
| State management (Riverpod)                 | Widget test với `ProviderScope.overrides`        | Test notifier behavior             |
| Navigation / dialog flow                    | Manual `fvm flutter run -d <platform>`           | Full app flow desktop              |
| Static checks                               | `fvm flutter analyze`                            | **Zero issues** — kể cả info level |
| UI visual change                            | `fvm flutter run -d <platform>` + manual repro   | Visual confirm                     |
| i18n change                                 | `fvm flutter gen-l10n` + run + switch locale     | Verify cả en + vi                  |
| Cross-platform Process.run                  | [[Knowledge-Base/Skill-Audit-RunInShell]] script | Bắt buộc sau refactor              |

### Autonomy — auto-run trên local dev (KHÔNG cần confirm)

#### A. Filesystem / git read-only

- `ls`, `find`, `grep`, `cat`, `head`, `tail` — list/search/read
- Native tools: Read, Glob, Grep
- Git read-only: `git status`, `git log`, `git diff`, `git show`, `git blame`
- Source lookup Flutter SDK / pub packages (Principle #3)

#### B. Test + verify execution

- `fvm flutter test` (any file or all tests)
- `fvm flutter analyze`
- `fvm flutter gen-l10n`
- `dart format <file>`, `dart fix --apply`
- `dart analyze <file>`
- Audit `runInShell` script (xem [[Knowledge-Base/Skill-Audit-RunInShell]])

#### C. Pub / build (development)

- `fvm flutter pub get`, `fvm flutter pub upgrade <specific-package>`
- `fvm flutter clean` (xóa build cache)
- Hot reload (`r`) / hot restart (`R`) trong session đang chạy
- Debug build local: `fvm flutter run -d <macos|linux|windows>`

#### D. Ephemeral temp files

- Redirect output `/tmp/*` cho stdout/stderr capture
- `mktemp` cho scratch data (diff XML/JSON, inspect log dài)
- Delete/rewrite `/tmp/*` do Claude tạo trong session

**Workflow:** verify/test/search → **chạy luôn**, report kết quả. KHÔNG hỏi "bạn muốn tôi chạy test không?" / "có cần capture log không?". Default là CHẠY.

### KHÔNG auto-run — confirm trước

- `fvm flutter build <platform> --release` → user confirm (build artifact, có thể distribute)
- `bash release.sh` / `.\release.ps1` → bump version + tag + push, user confirm
- `fvm flutter pub upgrade` (toàn bộ, không specific package) → có thể break version constraints
- Destructive filesystem: `rm -rf`, xóa folder lớn, overwrite uncommitted work
- Destructive git: `push --force`, `reset --hard`, `branch -D`
- Git commit / push — luôn cần user explicit request

### Completion criteria

- `fvm flutter test` output: `All tests passed!` với count > 0 (nếu có tests)
- `fvm flutter analyze` output: `No issues found!` — **KHÔNG chấp nhận info/warning level dư**
- Manual repro: bug không còn / feature hoạt động đúng theo success criteria
- Cross-platform Process call: pass audit script (xem [[Fix-History/RunInShell-Audit]])
- ❌ KHÔNG dùng "code compiles" làm proof — phải actually run + verify behavior

### Exception

Skip verify CHỈ khi:

- User explicitly nói "no tests needed"
- Trivial typo (1-2 ký tự, không ảnh hưởng logic)
- Comment-only changes
- UI visual tweak — confirm visually qua `fvm flutter run` thay vì test

---

## 15. Knowledge Loop — Vòng lặp tri thức

**Sau khi thực hiện thay đổi code hoặc giải quyết yêu cầu**, LUÔN thực hiện 5 bước (bắt buộc):

### Step 1 — Kiểm tra tính mới

Logic vừa code là **nghiệp vụ quan trọng** hoặc **kỹ thuật khó** → tạo/cập nhật vault note:

| Loại kiến thức                        | Folder + naming                                     |
| ------------------------------------- | --------------------------------------------------- |
| Reusable skill / operational know-how | `.obsidian-vault/Knowledge-Base/Skill-<Name>.md`    |
| Multi-step workflow                   | `.obsidian-vault/Knowledge-Base/Workflow-<Name>.md` |
| Business feature mới                  | `.obsidian-vault/Features/<Feature>.md`             |
| Architecture pattern                  | `.obsidian-vault/Architecture/<Topic>.md`           |
| Fix pattern                           | xem Step 2                                          |

File đã tồn tại → update section thay vì tạo mới.

### Step 2 — Ghi nhật ký Fix

Vừa **sửa bug** → tạo file trong `Fix-History/`. Hiện vault dùng naming ngắn gọn (tên bug, không prefix `Fix-`). Content structure:

```markdown
# Fix — <Tên bug ngắn>

## Symptom

[Triệu chứng + error log]

## Root cause

[Nguyên nhân gốc]

## Fix

[Diff/pattern/workaround + code]

## Related

- [[Index]]
- [[…related notes]]
```

Xem template mẫu: [[Fix-History/RunInShell-Audit]] hoặc [[Fix-History/Git-Porcelain-Parsing]].

### Step 3 — Cập nhật liên kết

- Add link vào `.obsidian-vault/Index.md` section đúng (Architecture / Features / Knowledge-Base / Fix-History)
- Add `## Related` section trong file mới link tới atomic notes liên quan với `[[ ]]`
- Bidirectional: file target cũng add `[[new-file]]` vào Related

### Step 4 — Update Change-Log + Current-State

**A. Change-Log (chronological session log) — APPEND:**

- Monthly file: `.obsidian-vault/Change-Log/YYYY-MM.md` (VD: `Change-Log/2026-04.md`)
- Append entry MỚI ở **TOP** (reverse chronological)
- Refresh `Change-Log.md` (root TOC): copy 3 entries gần nhất inline, cũ hơn chỉ giữ link

**B. Current-State (live snapshot) — OVERWRITE:**

- File: `.obsidian-vault/Current-State.md`
- Overwrite các sections: Active focus, Version (nếu bump), In-flight work (✅/⏳), Open questions, Known issues, Modules touched, Next session priorities, Last test run
- KHÔNG append — always re-write để reflect TRẠNG THÁI HIỆN TẠI

**Rollover tháng mới:** tạo `Change-Log/YYYY-MM.md` mới + add link vào `Change-Log.md` "Monthly archives" + append entry đầu tháng vào file mới.

### Step 5 — Báo cáo

Cuối câu trả lời có thay đổi documentation:

> "Tôi đã cập nhật tài liệu tại **Tên-file.md** để lưu giữ ngữ cảnh này."

Nhiều file → list hết: "Tôi đã cập nhật [[file-1]], [[file-2]], [[file-3]]..."

**Why:** Knowledge loop đảm bảo session work không bị mất. Session sau đọc vault (đặc biệt `Current-State.md`) sẽ thấy đầy đủ context — không phải "rediscover" cùng pattern hoặc hỏi lại user.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

## 📂 Project knowledge location (Obsidian-first workflow)

```
./.obsidian-vault/                # symlink → Obsidian vault path (per-machine)
├── Index.md                      # knowledge map (read 1st khi navigate)
├── Current-State.md              # live snapshot — OVERWRITTEN end-of-session
├── Change-Log.md                 # TOC + 3 entries gần nhất inline
├── Change-Log/
│   └── YYYY-MM.md                # monthly archives (APPEND new entry at top)
├── Architecture/                 # patterns, flows, hierarchy
├── Features/                     # business capabilities
├── Knowledge-Base/               # principles + skills + workflows + rules
└── Fix-History/                  # bug fixes
```

Symlink target tuỳ máy + tuỳ cloud provider user setup — xem section "Per-machine setup" ở đầu file. Nếu symlink không tồn tại hoặc resolve fail → báo user setup trước khi tiếp tục, KHÔNG đoán path.

### Vault Read Order (đầu session)

1. `CLAUDE.md` (file này) — auto-loaded, principles + protocol
2. `MEMORY.md` — auto-loaded user/feedback memory
3. `./.obsidian-vault/Current-State.md` — dự án ĐANG ở đâu (active focus, version, in-flight, next)
4. `./.obsidian-vault/Index.md` — knowledge map khi cần navigate
5. `./.obsidian-vault/Change-Log.md` — 3 entries gần nhất. Đọc `Change-Log/YYYY-MM.md` nếu cần lịch sử sâu
6. Atomic notes — on-demand khi `Current-State` hoặc task reference

### Vault Write Order (cuối session, nếu có code/doc change)

Áp dụng 5 steps Principle #15 Knowledge Loop:

1. Step 1-3: Update atomic notes + bidirectional links + `Index.md`
2. Step 4A — Change-Log: APPEND ở TOP của `Change-Log/YYYY-MM.md` + refresh `Change-Log.md` 3 entries
3. Step 4B — Current-State: OVERWRITE `Current-State.md`
4. Step 5: Báo user "Đã cập nhật [[file-1]], [[file-2]]..."

**Key distinction:** Change-Log = lịch sử (append), Current-State = hiện tại (overwrite). Đừng trộn 2 mục đích này.
