# 016-cleanup-wave — P3 dead code / cosmetic

**Owner:** Andrey (per `specs/012-ultrareview/findings.md` §015-cleanup-wave backlog).
**Implementer:** Egor (override of AC-A5 owner-implements rule, granted in chat — same pattern as 013, 015).
**Status:** Active.

## Назначение

Закрытие P3 findings из 012-ultrareview, оставшихся после 013/015. Дешёвый пасс по dead-code и косметике.

Слот 015 ушёл под `egor/015-refactor-wave-2` — в findings.md этот pack помечен как «015-cleanup-wave», но реальный номер бамплен на 016 для прослеживаемости с веткой `egor/016-cleanup-wave`.

## Findings — что закрываем

| ID | Sev | Файл | Что не работает | Кластер |
|---|---|---|---|---|
| F-016 | P3 | `scripts/presentation/hex_placeholder_builder.gd:18-22` | 5 raw tile colors — self-resolves on F-025 delete. | `A-deletes` |
| F-017 | P3 | `scripts/presentation/run_summary.gd:109-115` | Inline `StyleBoxFlat.new()` — self-resolves on F-026 delete. | `A-deletes` |
| F-018 | P3 | `scripts/presentation/slot_bar.gd:184-185` | `Color(focus.r * 1.3, focus.g * 1.3, focus.b * 0.5)` magic multipliers. | `B-uitheme` |
| F-019 | P3 | `scripts/presentation/slot_bar.gd:196` | `Color(1.10, 1.10, 1.10) if hovered else Color.WHITE`. | `B-uitheme` |
| F-020 | P3 | `scripts/presentation/status_icon_strip.gd:97-101` | Local `_make_pill_stylebox(family)` helper. | `B-uitheme` |
| F-024 | P3 | `scripts/presentation/portal_transition.gd` + `.tscn` | Zero refs project-wide. Dead. | `A-deletes` |
| F-025 | P3 | `scripts/presentation/hex_placeholder_builder.gd` | Never called. Doc-comment in `hex_grid.gd:42` — only mention. | `A-deletes` |
| F-026 | P3 | `scripts/presentation/run_summary.gd` + `.tscn` | Not preload'd, not instantiated. Signal `run_summary_shown` has no listeners. | `A-deletes` |
| F-027 | P3 | `scripts/presentation/loading_cover.gd` + `.tscn` | Zero refs project-wide. Dead. | `A-deletes` |
| F-028 | P3 | `scripts/presentation/portal_transition.gd:44` | Bare `create_timer(...)` — self-resolves on F-024 delete. | `A-deletes` |
| F-030 | P3 | `scripts/core/skills/skill_database.gd:80` | `AbilityDatabase._build_ability_from_dict(...)` — `_underscore`-private leaking across module. | `C-code` |
| F-031 | P3 | `specs/011-skill-tags/spec.md:34` (AC-T6) | «F1/F2/F3/F4 в godmode (debug skills) кастуются» — slots are Q/W/E/R or 1/2/3/4. F1/F2 are spawn/clear. Spec drift. | `D-spec-text` |
| F-032 | P3 | `specs/003-dialogue-manager/spec.md` §Content & smoke | «В `main.tscn` — временная кнопка «Test dialogue»...» — `main.tscn` was replaced by `main_menu.tscn` per 009/AC-I2. Spec drift. | `D-spec-text` |
| F-033 | P3 | `scripts/presentation/dialogue_manager.gd:104` | `_panel = load(PANEL_SCENE).instantiate()` — runtime resource lookup; `preload` is parse-time. Cosmetic, once-per-session call. | `C-code` |
| F-034 | P3 | `scripts/presentation/godmode/godmode_controller.gd:139,495` | `get_node_or_null("../HUD/PlayerStatusPanel")` — hardcoded sibling path. Breaks if HUD renamed or PSP moves. | `C-code` |

## Out of scope

- **F-021 / F-022** (godmode hardcoded debug-skill ids, tag → semantic_kind mapping) — findings.md marks both as "acceptable for dev-only controller, do post-jam if at all". Skip.
- **F-023** (CLAUDE.md `Logger` doc drift) — earmarked in findings.md for a separate `016-doc-fixes` slice. Skip here, will be picked up separately if anyone bothers (1-line edit).
- **F-029** (typed-array Variant boundary risk) — findings.md says "Risk-only, no triggered fault. Defensive rewrite is anti-«Speed > polish > scope»." Skip until a fault appears.
- Any P1/P2 — closed in 013 / 015.

## Acceptance criteria

- **AC-1 (F-024 + F-028):** Files `scripts/presentation/portal_transition.gd` и `scenes/ui/portal_transition.tscn` удалены. `git grep -i portal_transition` returns 0 matches in `scripts/`, `scenes/`, `data/`, `config/`. Dead bare `create_timer` (F-028) уходит вместе с файлом.
- **AC-2 (F-025 + F-016):** Файл `scripts/presentation/hex_placeholder_builder.gd` удалён. Doc-comment в `scripts/core/arena/hex_grid.gd:42` обновлён — упоминание `HexPlaceholderBuilder.setup()` убрано (либо переписано на «controller paints tiles before initialize()», либо доку удалить целиком). `git grep HexPlaceholderBuilder` returns 0 matches in `scripts/`, `scenes/`. (Spec-history mentions в `specs/002-hex-grid/` оставляем — это исторический артефакт.)
- **AC-3 (F-026 + F-017):** `scripts/presentation/run_summary.gd` + `scenes/ui/run_summary.tscn` удалены. Сигнал `signal run_summary_shown(summary: Dictionary)` удалён из `scripts/infrastructure/event_bus.gd`. `git grep run_summary` returns 0 matches in `scripts/`, `scenes/`.
- **AC-4 (F-027):** `scripts/presentation/loading_cover.gd` + `scenes/ui/loading_cover.tscn` удалены. `git grep loading_cover` returns 0 matches.
- **AC-5 (F-018 + F-019):** В `ui_theme.gd` добавлены константы `FOCUS_ACTIVE_CASTABLE: Color`, `FOCUS_ACTIVE_DISABLED: Color` (готовые цвета — без runtime вычислений из `FOCUS.r/g/b`), и `HOVER_BRIGHTEN: Color := Color(1.10, 1.10, 1.10)`. `slot_bar.gd:184-185,196` использует константы вместо inline `Color(...)`. `grep "Color(" scripts/presentation/slot_bar.gd` показывает только `Color(UiTheme.TEXT_FAINT, 1.0)` / `Color(UiTheme.TEXT_DIM.r, ..., 1.0)` style — никаких новых литералов.
- **AC-6 (F-020):** В `ui_theme.gd` добавлен `static func make_pill_stylebox(family: StringName) -> StyleBoxFlat` рядом с `make_panel_stylebox`. `status_icon_strip.gd` — локальный `_make_pill_stylebox` удалён, call site вызывает `UiTheme.make_pill_stylebox(family)`. Visual: pill style не изменился.
- **AC-7 (F-030):** `AbilityDatabase._build_ability_from_dict` переименован в публичный `build_ability_from_dict`. Внутренний call site (`ability_database.gd:108`) и внешний (`skill_database.gd:81`) обновлены. Никаких других сайтов нет (sanity: `git grep _build_ability_from_dict` returns 0).
- **AC-8 (F-033):** `dialogue_manager.gd` — `const PANEL_SCENE := "res://scenes/ui/dialogue_panel.tscn"` (string) → `const PANEL_SCENE := preload("res://scenes/ui/dialogue_panel.tscn")` (PackedScene). `_get_panel()` — `load(PANEL_SCENE).instantiate()` → `PANEL_SCENE.instantiate()`.
- **AC-9 (F-034):** В `godmode_controller.gd` добавлен `@export var player_status_panel_path: NodePath`. Оба use-site (line 139, 495) используют `_get_player_status_panel()` helper (single get_node_or_null с fallback на старый hardcoded path для совместимости со standalone-запусками). В `scenes/dev/godmode.tscn` GodmodeController node — добавлен `player_status_panel_path = NodePath("../HUD/PlayerStatusPanel")`. (PauseMenu lookup на line 359 — отдельная история, не в scope F-034.)
- **AC-10 (F-031):** `specs/011-skill-tags/spec.md:34` — «F1/F2/F3/F4 в godmode (debug skills) кастуются» → «Q/W/E/R (или 1/2/3/4) в godmode (debug skills) кастуются».
- **AC-11 (F-032):** `specs/003-dialogue-manager/spec.md` §Content & smoke — bullet про «В `main.tscn` — временная кнопка ...» удалён или переписан. §Acceptance verification step 1 (там же ссылается на «main → видна кнопка») переписан под `dialogue_preview.tscn` flow.
- **AC-12 (CLAUDE.md hard-rules check):** Никаких inline `Color(...)` в presentation (slot_bar.gd чист). Никаких bare `create_timer`. Никаких новых хардкодов content. `class_name`-ы, snake_case past tense — без изменений. `Color()` остаётся допустимым внутри `ui_theme.gd` (it's the source).

## Зависимости

- **Upstream:** 015 мержен в staging. ✓ (egor/015-refactor-wave-2 уже на staging согласно branch listing).
- **Downstream:** —

## Risk

- **F-025 удаление и зависимость от `class_name`.** `HexPlaceholderBuilder` объявлен через `class_name`, что регистрирует его в global class registry. После удаления файла Godot перебилдит script cache при следующем запуске. Если кто-то имеет несохранённую сцену с ссылкой на `HexPlaceholderBuilder` — она сломается. Mitigation: `git grep -i HexPlaceholderBuilder` confirmed only doc-comment use.
- **F-026 удаление сигнала `run_summary_shown`.** Если в чьей-то WIP-ветке сидит `EventBus.run_summary_shown.connect(...)` — будет parse error на rebase. Risk principal: нет, mitigation — none, fix on rebase.
- **F-034 fallback.** Старый hardcoded `"../HUD/PlayerStatusPanel"` оставляем как safety-fallback (как в 015/F-013 для godmode_camera) — godmode иногда тестируется через variations of scene tree.
- **F-033 preload race.** `preload` happens at parse time. `dialogue_manager.gd` is autoload registered after DialogueDB. The panel scene itself doesn't depend on autoloads at preload time (verified: `dialogue_panel.tscn` only ext_resource on the panel script). No circular import risk.
