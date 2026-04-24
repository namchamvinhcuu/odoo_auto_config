# CLAUDE.md — Workspace Configuration (Flutter desktop)

Hướng dẫn làm việc cho Claude trong dự án `odoo_auto_config` — gồm **Behavioral Principles** + pointer tới knowledge base.

**Project Knowledge Base** sống trong Obsidian vault tại `./.obsidian-vault/` (symlink, atomic notes tổ chức theo `Architecture/` / `Features/` / `Knowledge-Base/` / `Fix-History/`). Khi cần reference về tech stack, modules, skills, bugs — đọc vault qua [`./.obsidian-vault/Index.md`](.obsidian-vault/Index.md).

### ⚙️ Per-machine setup (nếu `.obsidian-vault` chưa tồn tại)

Vault path khác nhau trên mỗi máy (sync qua OneDrive). Symlink `.obsidian-vault` resolve việc này — tạo 1 lần trên mỗi máy:

```bash
# Mac mini M4 (OneDrive trên external drive)
ln -s /Volumes/Data/OneDrive/Obsidian_Vault/Nam-Dev/Workspace-Configuration ./.obsidian-vault

# Linux Mint (OneDrive synced via rclone hoặc tương tự)
ln -s ~/OneDrive/Obsidian_Vault/Nam-Dev/Workspace-Configuration ./.obsidian-vault
```

Verify: `ls .obsidian-vault/Index.md` → phải resolve được. Symlink `.obsidian-vault` đã trong `.gitignore`.

Nếu vault chưa sync về máy hiện tại → restore từ OneDrive trước khi code.

### 📦 Archive

Snapshot cũ của CLAUDE.md + STRUCTURE.md (trước 2026-04-25) lưu tại [ARCHIVE.md](ARCHIVE.md). Không đọc để làm context thường — chỉ reference khi cần trace lịch sử.

---

# PHẦN 1 — BEHAVIORAL PRINCIPLES

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific knowledge in `.obsidian-vault/`.

**Ordering = session lifecycle.** Đọc tuần tự 1→10 để biết cần làm gì ở từng phase:

| Phase | Principles | Mục đích |
|-------|-----------|----------|
| 🗣️ Communication | #1 Ask in Vietnamese | Ngôn ngữ giao tiếp |
| ⚙️ Environment | #2 Flutter SDK via FVM, #9 Upstream Framework Reference | Setup tooling + tra cứu source |
| 🧠 Plan | #3 Think Before Coding, #4 Goal-Driven, #10 Vault-First Debug | Phân tích, success criteria, investigation |
| ✍️ Code | #5 Simplicity First, #6 Surgical Changes | Khi viết/sửa code |
| ✅ Verify | #7 Test-Driven Quality | Xác nhận hoạt động đúng |
| 📝 Document | #8 Knowledge Loop | Lưu lại tri thức |

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

## 2. Flutter SDK via FVM — Luôn dùng version đúng project

**KHI cần chạy Flutter (build, test, run, pub), LUÔN dùng FVM-resolved `flutter`. KHÔNG dùng system flutter.**

### Mandatory workflow

```bash
# 1) Verify FVM resolves đúng version
which flutter
# Mac mini M4: ~/fvm/default/bin/flutter (symlink → 3.41.6)
# Linux Mint:  ~/fvm/default/bin/flutter (symlink → 3.41.6)

# 2) Verify .fvmrc match
cat .fvmrc            # → {"flutter": "3.41.6"}
flutter --version     # phải hiện 3.41.6
```

Nếu `which flutter` KHÔNG trỏ tới `~/fvm/default/bin/` → PATH sai, sửa `~/.zshrc` (Mac) hoặc `~/.bashrc` (Linux).

### Common commands (auto-resolve qua FVM)

```bash
fvm flutter pub get                  # install dependencies
fvm flutter run -d macos             # run trên Mac mini M4
fvm flutter run -d linux             # run trên Linux Mint
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
- Reproducibility cross-machine: cùng command trên Mac mini M4 + Linux Mint cho cùng kết quả

### Red flags — dừng lại

- `which flutter` trả `/usr/local/bin/flutter` hoặc `/opt/homebrew/bin/flutter` → đang dùng system flutter
- `flutter --version` không match `.fvmrc`
- Build fail "requires Flutter SDK >= X.Y.Z" → version mismatch

→ Cheatsheet chi tiết: [[Knowledge-Base/Skill-Flutter-Dev]].

### Autonomy với Flutter commands

`flutter pub get`, `flutter test`, `flutter analyze`, `flutter gen-l10n`, hot reload trên local dev → **auto-run, KHÔNG cần confirm**. Xem Principle #7 cho chi tiết.

## 3. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Chuyển yêu cầu mơ hồ thành outcome có thể verify trước khi code:

- "Add validation" → "Input X bị reject với message Y; input Z pass qua"
- "Fix the bug" → "Reproduce ở bước A, sau fix không còn + regression guard"
- "Refactor X" → "Behavior identical trước/sau; diff không đụng logic branch"
- "Add feature" → "Path A/B/C trên UI/API trả kết quả mong đợi"

Success criteria KHÔNG nhất thiết là tests — có thể là manual repro, diff review, screenshot widget render, log output. Tests là phương tiện mạnh nhất nhưng không phải duy nhất (chi tiết: Principle #7).

Multi-step tasks → state plan ngắn:

```
1. [Step] → verify: [check cụ thể]
2. [Step] → verify: [check cụ thể]
3. [Step] → verify: [check cụ thể]
```

Strong criteria → loop độc lập. Weak criteria ("make it work") → phải hỏi user liên tục.

## 5. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 6. Surgical Changes

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

## 7. Test-Driven Quality — Flutter testing

**Không task nào hoàn thành khi chưa verify hoạt động.** Sau khi implement bất kỳ logic nào:

### Verify methods (theo loại change)

| Change type | Verify command | Notes |
|-------------|----------------|-------|
| Pure Dart logic (helper, validator, parser) | `fvm flutter test test/<file>_test.dart` | Unit test |
| Widget render / interaction | `fvm flutter test` (widget test) | UI render + tap |
| State management (Riverpod) | Widget test với `ProviderScope.overrides` | Test notifier behavior |
| Navigation / dialog flow | Manual `fvm flutter run -d <platform>` | Full app flow desktop |
| Static checks | `fvm flutter analyze` | Type errors, lint |
| UI visual change | `fvm flutter run -d <platform>` + manual repro | Visual confirm |
| Cross-platform Process.run | [[Knowledge-Base/Skill-Audit-RunInShell]] script | Bắt buộc sau refactor |

### Autonomy — auto-run trên local dev (KHÔNG cần confirm)

#### A. Filesystem / git read-only

- `ls`, `find`, `grep`, `cat`, `head`, `tail` — list/search/read
- Native tools: Read, Glob, Grep
- Git read-only: `git status`, `git log`, `git diff`, `git show`, `git blame`
- Source lookup Flutter SDK / pub packages (Principle #9)

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
- `fvm flutter analyze` output: `No issues found!`
- Manual repro: bug không còn / feature hoạt động đúng theo success criteria
- Cross-platform Process call: pass audit script (xem [[Fix-History/RunInShell-Audit]])
- ❌ KHÔNG dùng "code compiles" làm proof — phải actually run + verify behavior

### Exception

Skip verify CHỈ khi:

- User explicitly nói "no tests needed"
- Trivial typo (1-2 ký tự, không ảnh hưởng logic)
- Comment-only changes
- UI visual tweak — confirm visually qua `fvm flutter run` thay vì test

## 8. Knowledge Loop — Vòng lặp tri thức

**Sau khi thực hiện thay đổi code hoặc giải quyết yêu cầu**, LUÔN thực hiện 5 bước (bắt buộc):

### Step 1 — Kiểm tra tính mới

Logic vừa code là **nghiệp vụ quan trọng** hoặc **kỹ thuật khó** → tạo/cập nhật vault note:

| Loại kiến thức | Folder + naming |
|---------------|-----------------|
| Reusable skill / operational know-how | `.obsidian-vault/Knowledge-Base/Skill-<Name>.md` |
| Multi-step workflow | `.obsidian-vault/Knowledge-Base/Workflow-<Name>.md` |
| Business feature mới | `.obsidian-vault/Features/<Feature>.md` |
| Architecture pattern | `.obsidian-vault/Architecture/<Topic>.md` |
| Fix pattern | xem Step 2 |

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

## 9. Upstream Framework Reference — tra cứu source thật

**Khi cần verify Flutter / package API (widget property, class signature, package method) — LUÔN query trong source thật. KHÔNG đoán.**

### Source locations (per-machine)

| Source | Mac mini M4 | Linux Mint |
|--------|-------------|------------|
| Flutter SDK | `~/fvm/versions/3.41.6/packages/flutter/lib/` | same |
| Material widgets | `~/fvm/versions/3.41.6/packages/flutter/lib/src/material/` | same |
| Cupertino widgets | `~/fvm/versions/3.41.6/packages/flutter/lib/src/cupertino/` | same |
| Pub packages | `~/.pub-cache/hosted/pub.dev/<pkg>-<version>/lib/` | same |

Resolve dynamic:

```bash
FLUTTER_SDK=$(dirname $(dirname $(readlink -f $(which flutter))))
echo $FLUTTER_SDK
# Cả Mac mini M4 và Linux Mint: ~/fvm/versions/3.41.6
ls $FLUTTER_SDK/packages/flutter/lib/src/widgets/
```

### Common pub package paths (dự án này)

```bash
# Riverpod (state management)
ls ~/.pub-cache/hosted/pub.dev/flutter_riverpod-2.6.1/lib/

# window_manager (desktop window control)
ls ~/.pub-cache/hosted/pub.dev/window_manager-0.5.1/lib/

# system_tray
ls ~/.pub-cache/hosted/pub.dev/system_tray-2.0.3/lib/

# file_picker
ls ~/.pub-cache/hosted/pub.dev/file_picker-8.0.0/lib/
```

### Mandatory workflow khi nghi vấn API

1. **Xác định target:** widget / class / package nghi vấn?
2. **Grep / read source:**
   ```bash
   grep -rn "class CircleAvatar" ~/fvm/versions/3.41.6/packages/flutter/lib/src/material/
   grep -rn "class WindowManager" ~/.pub-cache/hosted/pub.dev/window_manager-0.5.1/lib/
   ```
3. **Đối chiếu với code custom** trong `lib/` để phát hiện sai lệch.
4. Chỉ đưa fix sau khi xác nhận source.

### Tại sao bắt buộc

- Flutter API thay đổi giữa minor versions (3.40 → 3.41: `WidgetState` rename, `MaterialState` deprecated)
- Pub package major bump = breaking changes (Riverpod 2 → 3 thay đổi `Notifier` API)
- Đoán dựa training data (cutoff 2026-01) → fix sai → bugs mới

### Red flags — dừng lại

- "Tôi nghĩ widget này có property X..." → grep trước
- "Riverpod chắc có method Y..." → đọc source
- "API version này vẫn dùng Z..." → check changelog hoặc source

→ Nếu không verify được, **nói rõ là đang đoán**, không khẳng định.

## 10. Vault-First Debug — đọc vault TRƯỚC khi đọc code

**Khi user báo lỗi (screenshot, traceback, mô tả) — KHÔNG đọc code ngay. Quét `.obsidian-vault/` TRƯỚC.**

### Thứ tự investigation bắt buộc

1. **Quét `.obsidian-vault/` lần lượt:**
   - `Architecture/` — hiểu flow nghiệp vụ liên quan ([[Architecture/Multi-Instance-IPC]], [[Architecture/Dialog-System]], [[Architecture/State-Management-Riverpod]], etc.)
   - `Fix-History/` — tìm bug tương tự đã fix, xem root cause + pattern. Grep theo keyword triệu chứng.
   - `Knowledge-Base/` — pattern / gotcha về Flutter / Riverpod / cross-platform Process
   - `Features/` — context business logic
2. **Đối chiếu source thật** (Principle #9 nếu cần check Flutter / package source)
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
├── Architecture/                 # patterns, flows, hierarchy (10 notes)
├── Features/                     # business capabilities (20 notes)
├── Knowledge-Base/               # principles + skills + workflows + rules (25 notes)
└── Fix-History/                  # bug fixes (24 notes)
```

Symlink target tuỳ máy — xem section "Per-machine setup" ở đầu file. Nếu symlink không tồn tại → restore vault từ OneDrive trước khi tiếp tục.

### Vault Read Order (đầu session)

1. `CLAUDE.md` (file này) — auto-loaded, principles + protocol
2. `MEMORY.md` — auto-loaded user/feedback memory
3. `./.obsidian-vault/Current-State.md` — dự án ĐANG ở đâu (active focus, version, in-flight, next)
4. `./.obsidian-vault/Index.md` — knowledge map khi cần navigate
5. `./.obsidian-vault/Change-Log.md` — 3 entries gần nhất. Đọc `Change-Log/YYYY-MM.md` nếu cần lịch sử sâu
6. Atomic notes — on-demand khi `Current-State` hoặc task reference

### Vault Write Order (cuối session, nếu có code/doc change)

Áp dụng 5 steps Principle #8 Knowledge Loop:

1. Step 1-3: Update atomic notes + bidirectional links + `Index.md`
2. Step 4A — Change-Log: APPEND ở TOP của `Change-Log/YYYY-MM.md` + refresh `Change-Log.md` 3 entries
3. Step 4B — Current-State: OVERWRITE `Current-State.md`
4. Step 5: Báo user "Đã cập nhật [[file-1]], [[file-2]]..."

**Key distinction:** Change-Log = lịch sử (append), Current-State = hiện tại (overwrite). Đừng trộn 2 mục đích này.
