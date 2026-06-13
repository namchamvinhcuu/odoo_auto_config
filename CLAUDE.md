# CLAUDE.md — Workspace Configuration (Flutter desktop)

Behavioral principles cho Claude trong dự án Flutter desktop (cấu hình Odoo — KHÔNG phải Odoo backend). Mọi version / path resolve dynamic từ `.fvmrc` / `pubspec.lock` / FVM symlink — không hardcode trong file này.

**Knowledge base ngoài file này:**
- 📚 `./.obsidian-vault/` — symlink Obsidian vault (atomic notes: `Architecture/` / `Features/` / `Knowledge-Base/` / `Fix-History/` / `Change-Log/`). Vào qua `Index.md`.
- 🛠 `./.claude/agents/` — sub-agents (`vault-curator` / `vault-debugger` / `flutter-reviewer` / `flutter-test-writer`) đã có procedure đầy đủ trong body.
- 📐 `./.claude/references/{sub-agent,review,test}-discipline.md` — discipline chung áp dụng tự động cho sub-agents.

**Priority khi conflict:** Project CLAUDE.md > `references/` > agent body.

### Per-machine setup (nếu `.obsidian-vault` chưa có)

Vault path tuỳ máy + cloud provider. User tự tạo symlink (machine-specific, không version control): `ln -s <vault-path> ./.obsidian-vault` → verify `ls .obsidian-vault/Index.md`. Symlink ở `.gitignore`. Fail → báo user setup trước, KHÔNG đoán path.

---

# BEHAVIORAL PRINCIPLES

Đọc tuần tự 1→15 theo lifecycle session:

| Phase | Principles |
| --- | --- |
| 🗣️ Communication | #1 Vietnamese |
| ⚙️ Environment | #2 FVM · #3 Upstream reference |
| 🧠 Plan | #4 Think · #5 Goal-driven · #6 Vault-first debug |
| ✍️ Code | #7 Simplicity · #8 Surgical · #9 Riverpod+SOLID · #10 i18n · #11 No hardcoded UI · #12 Cross-platform Process · #13 Comment-out not delete |
| ✅ Verify | #14 Test-driven quality |
| 📝 Document | #15 Knowledge loop |

Bias toward caution over speed. Trivial tasks → judgment.

> **Cross-stack rules sống ở global `~/.claude/CLAUDE.md`** (symlink → `shared/global/CLAUDE.md`) và KHÔNG lặp lại ở đây: orchestration spawn-first, Test-Driven Quality mandate, auto-run autonomy, "KHÔNG auto-run", dev vs production, memory 3-tầng, ngôn ngữ giao tiếp. File này chỉ chứa phần **Flutter/vault-specific extend** — không loosen ranh giới an toàn của global.

---

## 1. Ask in Vietnamese

Mọi câu hỏi / clarification / present alternatives / confirm destructive → **tiếng Việt** — quy tắc đầy đủ ở global `~/.claude/CLAUDE.md` §Ask in Vietnamese.

**Không áp dụng cho:** code, identifier, commit message, PR title, comment (theo convention module), error message copy từ tool/log.

---

## 2. Flutter SDK via FVM — Luôn dùng đúng version project

**Mọi lệnh Flutter PHẢI dùng FVM-resolved (`fvm flutter ...`). KHÔNG system flutter.**

```bash
which flutter                       # phải trỏ ~/fvm/default/bin/flutter
cat .fvmrc && flutter --version     # phải match
fvm install && fvm use --force      # nếu chưa khớp
```

PATH sai → fix `~/.zshrc`/`~/.bashrc`: `export PATH="$HOME/fvm/default/bin:$PATH"`.

**Common commands:** `fvm flutter pub get` · `test` · `analyze` · `gen-l10n` · `run -d <macos|linux|windows>` (⚠️ `-d` BẮT BUỘC, sai → "Target file not found") · `build <platform> --release`.

**Red flags:** `which flutter` trả `/usr/local/bin/` hoặc `/opt/homebrew/bin/`; version không match `.fvmrc`; build fail "requires Flutter SDK >= X.Y.Z" → version mismatch / system flutter.

Why: breaking changes giữa minor versions, pub package version constraint, reproducibility cross-machine. Cheatsheet: [[Knowledge-Base/Skill-Flutter-Dev]].

---

## 3. Upstream Framework Reference — tra cứu source thật

Khi nghi vấn Flutter / pub package API — query source thật, KHÔNG đoán theo training data.

```bash
FLUTTER_SDK=$(dirname $(dirname $(readlink -f $(which flutter))))
# Flutter widgets: $FLUTTER_SDK/packages/flutter/lib/src/{material,cupertino,widgets}/
# Pub package:    ~/.pub-cache/hosted/pub.dev/<pkg>-<version>/lib/  (version từ pubspec.lock)
```

**Why:** Flutter API đổi giữa minor versions (`WidgetState` rename, `MaterialState` deprecated…); pub major bump = breaking (Riverpod 2→3 `Notifier` API).

Không verify được → **nói rõ đang đoán**, không khẳng định. Sub-agents có upstream lookup table riêng trong `references/sub-agent-discipline.md`.

---

## 4. Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

- State assumptions explicitly. Uncertain → hỏi.
- Multiple interpretations → present, đừng pick im lặng.
- Simpler approach exists → nói. Push back khi đúng.

---

## 5. Goal-Driven Execution

Define success criteria trước khi code. Vague → outcome verify được:

- "Add validation" → "input X bị reject với message Y; input Z pass"
- "Fix bug" → "reproduce step A; sau fix không còn + regression guard"
- "Refactor X" → "behavior identical; diff không đụng logic branch"

Success criteria KHÔNG nhất thiết là tests — có thể manual repro / diff review / widget render / log. Multi-step → state plan ngắn với verify check mỗi step.

---

## 6. Vault-First Debug — spawn `vault-debugger` TRƯỚC khi sửa

User báo lỗi (screenshot / traceback / mô tả) → **spawn `vault-debugger`** (đọc vault `Architecture/` + `Fix-History/` + `Knowledge-Base/` + `Features/` rồi đối chiếu source) → main session áp diff đề xuất → spawn `flutter-reviewer` confirm.

**Why:** vault chứa mental model + lịch sử quyết định + pattern đã tested. Đọc code cold dễ fix bề mặt / rediscover bug / break logic khác. Procedure đầy đủ trong `agents/vault-debugger.md` + `references/sub-agent-discipline.md#Vault-First entry`.

Skip CHỈ khi: typo trivial 1-2 ký tự; user explicit "fix nhanh, không cần context".

---

## 7. Simplicity First

Minimum code that solves the problem. Nothing speculative.

- Không feature ngoài yêu cầu. Không abstraction cho code 1-lần-dùng. Không "flexibility" chưa request. Không error handling cho impossible scenarios.
- 200 dòng có thể 50 dòng → rewrite.

Senior engineer nhìn vào: "overcomplicated?" → simplify.

---

## 8. Surgical Changes

Touch only what you must. Clean up only your own mess.

- Không "improve" code/comment/format quanh chỗ sửa. Không refactor cái không hỏng. Match existing style.
- Dead code không liên quan → mention, đừng xoá. Orphan do MÌNH tạo → dọn.

Mỗi dòng đổi trace trực tiếp về request user.

---

## 9. Riverpod + SOLID — State Management Standard

**Code mới PHẢI dùng Riverpod (Notifier/AsyncNotifier). Tách logic khỏi UI. Widget > 500 dòng → split.**

- **State:** Riverpod 2.x `Notifier`/`AsyncNotifier` mutable, `Provider` immutable derived. KHÔNG `setState` cho non-trivial state, KHÔNG `StatefulWidget` mới (trừ animation/controller).
- **Layers:** `lib/notifiers/` (state) · `lib/services/`|`repositories/` (IO/network/Process/file) · `lib/widgets/`|`screens/` (render only — `ref.watch` state, `ref.read(provider.notifier).method()` action).
- **File size:** > 500 dòng → split subwidget suffix `_section.dart` / `_card.dart` / `_form.dart`.

```bash
grep -rn "setState(" lib/widgets/ lib/screens/
grep -rn "Process\.run\|http\.get\|File(" lib/widgets/ lib/screens/
find lib/widgets lib/screens -name "*.dart" -exec wc -l {} + | awk '$1 > 500'
```

Reference: [[Architecture/State-Management-Riverpod]], [[Knowledge-Base/Skill-Riverpod-Notifier]].

---

## 10. i18n Proactive — Localization First

**Mọi string user-facing PHẢI vào ARB files. KHÔNG hardcode trong widget.**

- ARB: `lib/l10n/intl_<locale>.arb` (locales từ `pubspec.yaml` → `flutter.generate`). Add string → thêm vào TẤT CẢ ARB files.
- Widget: `Text(AppLocalizations.of(context)!.keyName)`. Sau add → `fvm flutter gen-l10n`.
- Key naming: camelCase mô tả ngữ nghĩa, follow pattern ARB hiện tại.

**Detect:** `grep -rn 'Text("' lib/widgets/ lib/screens/ | grep -v 'l10n\|test'`

**Exceptions:** logger/debug print, const technical strings (URL/env key/regex), test fixtures, identifier literal (version/hash/ID). Reference: [[Knowledge-Base/Skill-i18n-ARB]].

---

## 11. No Hardcoded UI Values — Constants Discipline

**UI dimensions PHẢI lấy từ `AppConstants`. KHÔNG raw `double`/`int` trong widget.**

- Padding/margin: `EdgeInsets.all(AppConstants.padding16)` · Radius: `BorderRadius.circular(AppConstants.radiusMedium)` · Size: `SizedBox(height: AppConstants.spacingS)`.
- Dialog: `AppDialog.show<T>` với size hint S/M/L (auto responsive + `SingleChildScrollView`).
- Colors: `Theme.of(context).colorScheme.X` hoặc `AppColors.X`, KHÔNG `Color(0xFF...)` raw.

```bash
grep -rn 'EdgeInsets\.all([0-9]\|SizedBox(height: [0-9]\|SizedBox(width: [0-9]\|BorderRadius\.circular([0-9]' lib/
grep -rn 'Color(0x' lib/ | grep -v 'app_constants\|app_colors\|theme'
```

**Exceptions:** `app_constants.dart` / `app_colors.dart` / `app_theme.dart` (định nghĩa); animation duration nội bộ; trị 0. Reference: `lib/core/constants/app_constants.dart`, [[Knowledge-Base/Skill-Responsive-Layout]].

---

## 12. Cross-Platform Process Safety

**Mọi `Process.run`/`Process.start` PHẢI cân nhắc `runInShell` + path separator + executable resolution per OS. Refactor đụng Process → BẮT BUỘC chạy audit script.**

- **`runInShell`:** Windows `true` cho `.bat`/`.cmd`/builtin (`dir`, `where`); Linux/macOS thường `false` (trừ khi cần shell expansion `*`/`~`/`$VAR`). Sai → silent fail 1 OS.
- **Path:** `path.join(...)` (package `path`), KHÔNG concat string. Windows `\` vs POSIX `/`.
- **Executable:** `Platform.isWindows ? 'where' : 'which'` hoặc cache absolute path từ user settings.
- **Env vars:** `Platform.environment['HOME'] ?? ...['USERPROFILE']`.
- **Line endings:** git porcelain Windows trả `\r\n` → strip `\r` khi parse.

```bash
grep -rn "Process\.run\|Process\.start" lib/ | grep -v "runInShell"
grep -rn "'which'\|'where'" lib/ | grep -v "Platform.is"
```

Why: desktop chạy 3 OS, sai 1 flag = fail 1 OS pass 2 OS → bug khó detect. Mandatory audit sau refactor: [[Knowledge-Base/Skill-Audit-RunInShell]]. References: [[Fix-History/RunInShell-Audit]], [[Fix-History/Git-Porcelain-Parsing]].

---

## 13. Comment Out, Don't Delete — Tắt tạm tính năng

**Tắt tạm feature (user request / phase rollout) → COMMENT OUT + TODO marker. KHÔNG delete code.**

- Tắt UI/method/route → comment + `// TODO(disable-YYYY-MM): re-enable khi <điều kiện>`.
- Delete CHỈ KHI: user explicit "xóa hẳn"; feature đã thay thế (cleanup sau migration); refactor được user approve session này.

```dart
// TODO(disable-2026-04): tắt tạm, re-enable khi backend ready
// ElevatedButton(onPressed: _onSubmit, child: Text(...)),
```

→ `grep 'TODO(disable-'` thấy ngay pending re-enable.

**Exception (delete OK):** dead code rõ ràng (unused import, orphan method, unreachable branch); code chỉ commit chưa push → revert thay vì comment.

---

## 14. Test-Driven Quality — spawn `flutter-test-writer` + zero analyze issues

**Mọi tác vụ thay đổi logic → spawn `flutter-test-writer`** (agent body có FVM detect, infra detect, runner table, AAA/regression guard, PASS verbatim, Verdict ✅/❌). Main session loop fix-test cho tới `✅ ALL PASS` mới end task. Procedure đầy đủ ở `agents/flutter-test-writer.md` + `references/test-discipline.md`.

**Verify methods theo loại change (Flutter-specific):**

| Change | Verify |
| --- | --- |
| Pure Dart logic | `fvm flutter test test/<file>_test.dart` (unit) |
| Widget render/interaction | `fvm flutter test` (widget test) |
| Riverpod state | Widget test + `ProviderScope.overrides` |
| Navigation / dialog flow | Manual `fvm flutter run -d <platform>` |
| UI visual change | `fvm flutter run` + manual repro |
| i18n change | `fvm flutter gen-l10n` + run + switch locale (cả en + vi) |
| Cross-platform Process | Audit script [[Knowledge-Base/Skill-Audit-RunInShell]] |
| Static checks | `fvm flutter analyze` — **0 issue** kể cả info |

### Autonomy — cross-stack rules + Flutter extras (main session boundary)

Áp dụng "Auto-run trên local dev — KHÔNG hỏi confirm" + "VẪN phải confirm trước" của user-global CLAUDE.md. Flutter-specific extension:

- **Auto-run (extra):** `fvm flutter test`/`analyze`/`gen-l10n`/`pub get`/`pub upgrade <specific-pkg>`/`clean`/`run -d <platform>`, `dart format`/`fix --apply`, audit `runInShell` script.
- **Confirm trước (extra):** `fvm flutter build <platform> --release` (artifact distribute), `bash release.sh`/`.\release.ps1` (bump+tag+push), `fvm flutter pub upgrade` (full — break constraints).

### Completion criteria

- Test-writer Verdict `✅ ALL PASS` (count > 0 nếu logic change) — chi tiết PASS pattern trong `test-discipline.md`.
- `fvm flutter analyze` → `No issues found!` (không chấp nhận info/warning level dư).
- Manual repro: bug không còn / feature đúng theo success criteria.
- Cross-platform Process: pass audit script.
- ❌ KHÔNG dùng "code compiles" làm proof.

**Skip verify CHỈ khi:** user explicit "no tests needed"; trivial typo 1-2 ký tự; comment-only; UI visual tweak (confirm visually qua `fvm flutter run`).

---

## 15. Knowledge Loop — spawn `vault-curator` end-of-session

**Sau code change cần persist** — main session:

1. **Prep scratch** `/tmp/<task-slug>-summary.md` (format trong `agents/vault-curator.md#Input bắt buộc`): Type (bug-fix/feature/refactor/skill) + Diff summary + Tested (PASS verbatim) + Modules touched + Open questions + Related skill/fix-history.
2. **Spawn `vault-curator`** — agent xử lý: tạo Atomic notes (Skill/Feature), Fix-History (nếu bug-fix), Cross-links Index, Change-Log APPEND `YYYY-MM.md`, Current-State OVERWRITE, STRUCTURE.md sync (nếu có).
3. **Báo cáo cuối câu trả lời:** "Tôi đã cập nhật tài liệu tại [[File-1]], [[File-2]]…" (đọc từ `/tmp/<task-slug>-curator.md`).

**Distinction:** Change-Log = lịch sử (APPEND) · Current-State = hiện tại (OVERWRITE). Đừng trộn — curator enforce.

**Skip curator CHỈ khi:** session read-only/exploratory không code change; typo/comment-only.

---

## 📂 Vault Layout & Load Order

```
./.obsidian-vault/
├── Index.md                  # knowledge map (đọc khi navigate)
├── Current-State.md          # live snapshot — OVERWRITE end-of-session
├── Change-Log.md             # TOC + 3 entries gần nhất inline
├── Change-Log/YYYY-MM.md     # monthly archives (APPEND at top)
├── Architecture/             # patterns, flows, hierarchy
├── Features/                 # business capabilities
├── Knowledge-Base/           # principles + skills + workflows + rules
└── Fix-History/              # bug fixes
```

> **Memory contract:** vault = tầng **L3 (durable knowledge)**. Episodic ("đã làm gì khi nào") → **AgentMemory (L2)**, KHÔNG chép tay vào vault. Chi tiết: `.claude/references/memory-contract.md` + global `~/.claude/CLAUDE.md` §Memory & context.

**Đầu session — load order:** `CLAUDE.md` (auto) → `MEMORY.md` (auto, L1) → AgentMemory context (auto-inject nếu server có; resume sâu `/handoff`·`/recall <topic>`) → `Current-State.md` (**slim ≤30KB — ảnh chụp hiện tại, KHÔNG phải lịch sử**) → `Index.md` → `Change-Log.md` (3 entries; lịch sử sâu → `Change-Log/YYYY-MM.md` hoặc `/recall`) → Atomic notes on-demand.

**Cuối session — write protocol:** spawn `vault-curator` (xem #15). Sub-agents (`reviewer` / `test-writer` / `debugger`) KHÔNG ghi vault — chỉ trả output về main.

---

**Guidelines working if:** ít unnecessary changes, ít rewrites do overcomplication, clarifying questions đến TRƯỚC implementation chứ không phải sau mistake.
