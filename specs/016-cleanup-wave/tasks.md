# 016-cleanup-wave — tasks

Sequential кластерами (A→B→C→D). Один кластер = один commit. Внутри кластера правки независимы по файлам.

## A — F-024..F-027 + self-resolve F-016/F-017/F-028 (deletes)

- [ ] A1. `git rm scripts/presentation/portal_transition.gd scenes/ui/portal_transition.tscn` (F-024, F-028).
- [ ] A2. `git rm scripts/presentation/hex_placeholder_builder.gd` (F-025, F-016).
- [ ] A3. `scripts/core/arena/hex_grid.gd:42` — переписать doc-comment, убрать упоминание `HexPlaceholderBuilder.setup()`.
- [ ] A4. `git rm scripts/presentation/run_summary.gd scenes/ui/run_summary.tscn` (F-026, F-017).
- [ ] A5. `scripts/infrastructure/event_bus.gd` — удалить `signal run_summary_shown(summary: Dictionary)`.
- [ ] A6. `git rm scripts/presentation/loading_cover.gd scenes/ui/loading_cover.tscn` (F-027).
- [ ] A7. Sanity grep: `git grep -nE "portal_transition|HexPlaceholderBuilder|run_summary|loading_cover"` — должно остаться только в `specs/` (история) и в `specs/012-ultrareview/findings.md` (наш ссылочный документ).
- [ ] A8. Commit: `chore(016): F-024..F-027 — delete dead presentation files (portal_transition, hex_placeholder_builder, run_summary, loading_cover)`.

## B — F-018 + F-019 + F-020 (UiTheme misses)

- [ ] B1. `scripts/presentation/ui_theme.gd` — добавить блок констант `FOCUS_ACTIVE_CASTABLE`, `FOCUS_ACTIVE_DISABLED`, `HOVER_BRIGHTEN` после `# ── State ──` секции.
- [ ] B2. `scripts/presentation/ui_theme.gd` — добавить `static func make_pill_stylebox(family: StringName) -> StyleBoxFlat` после `make_button_stylebox`. Скопировать тело из `status_icon_strip.gd:96-114` 1:1 (заменив `UiTheme.semantic_color(family)` → `semantic_color(family)`, `UiTheme.SP_1` → `SP_1`).
- [ ] B3. `scripts/presentation/slot_bar.gd:184-185` — заменить inline `Color(focus.r * 1.3, ...)` блок на `UiTheme.FOCUS_ACTIVE_CASTABLE if castable else UiTheme.FOCUS_ACTIVE_DISABLED`. Удалить локальную `var focus := UiTheme.FOCUS` если стала unused.
- [ ] B4. `scripts/presentation/slot_bar.gd:196` — заменить `Color(1.10, 1.10, 1.10)` → `UiTheme.HOVER_BRIGHTEN`.
- [ ] B5. `scripts/presentation/status_icon_strip.gd` — удалить локальный `func _make_pill_stylebox(family: StringName) -> StyleBoxFlat` (lines 96-114).
- [ ] B6. `scripts/presentation/status_icon_strip.gd` — call site (search for `_make_pill_stylebox(`) → `UiTheme.make_pill_stylebox(...)`.
- [ ] B7. Sanity: `grep -n "Color(" scripts/presentation/slot_bar.gd` — никаких новых литералов кроме `Color(UiTheme.X.r, ...)` форм по `TEXT_DIM`/`TEXT_FAINT` (которые уже были).
- [ ] B8. Commit: `feat(016): F-018+F-019+F-020 — UiTheme.FOCUS_ACTIVE_*, HOVER_BRIGHTEN, make_pill_stylebox`.

## C — F-030 + F-033 + F-034 (code micro-fixes)

- [ ] C1. `scripts/core/abilities/ability_database.gd:114` — `func _build_ability_from_dict(...)` → `func build_ability_from_dict(...)`.
- [ ] C2. `scripts/core/abilities/ability_database.gd:108` — self-call update.
- [ ] C3. `scripts/core/skills/skill_database.gd:81` — `AbilityDatabase._build_ability_from_dict(...)` → `AbilityDatabase.build_ability_from_dict(...)`.
- [ ] C4. Sanity: `git grep _build_ability_from_dict` returns 0.
- [ ] C5. `scripts/presentation/dialogue_manager.gd:6` — `const PANEL_SCENE := "res://..."` → `const PANEL_SCENE := preload("res://scenes/ui/dialogue_panel.tscn")`.
- [ ] C6. `scripts/presentation/dialogue_manager.gd:104` — `_panel = load(PANEL_SCENE).instantiate()` → `_panel = PANEL_SCENE.instantiate()`.
- [ ] C7. `scripts/presentation/godmode/godmode_controller.gd` — добавить `@export var player_status_panel_path: NodePath` рядом с `inspector_path`.
- [ ] C8. `scripts/presentation/godmode/godmode_controller.gd` — добавить `func _get_player_status_panel() -> Node` helper (см. plan.md).
- [ ] C9. `scripts/presentation/godmode/godmode_controller.gd:139` — `var psp := get_node_or_null("../HUD/PlayerStatusPanel")` → `var psp := _get_player_status_panel()`.
- [ ] C10. `scripts/presentation/godmode/godmode_controller.gd:495` — то же самое.
- [ ] C11. `scenes/dev/godmode.tscn:49-55` GodmodeController node — добавить строку `player_status_panel_path = NodePath("../HUD/PlayerStatusPanel")`.
- [ ] C12. Commit: `refactor(016): F-030+F-033+F-034 — public build_ability_from_dict, preload dialogue_panel, godmode PSP NodePath @export`.

## D — F-031 + F-032 (spec text)

- [ ] D1. `specs/011-skill-tags/spec.md:34` — «F1/F2/F3/F4 в godmode (debug skills) кастуются» → «Q/W/E/R (или 1/2/3/4) в godmode (debug skills) кастуются».
- [ ] D2. `specs/003-dialogue-manager/spec.md` §Content & smoke — bullet 3 (`В main.tscn — временная кнопка "Test dialogue"...`) переписать: «Test dialogues are exercised through `scenes/dev/dialogue_preview.tscn` (см. ниже §Dev preview) — main.tscn кнопки больше нет (см. 009/AC-I2 main_menu rebuild).»
- [ ] D3. `specs/003-dialogue-manager/spec.md` §Acceptance verification step 1 — переписать на flow через `dialogue_preview.tscn` или удалить вместе с указанием что main.tscn-flow устарел; step 2 (mid-typewriter click) скорректировать чтобы он привязался к dialogue_preview play или к first-loop respawn trigger вместо main-button-click.
- [ ] D4. Commit: `docs(016): F-031+F-032 — fix spec drift in 011 (slots) and 003 (test button)`.

## E — Closeout

- [ ] E1. Отметить все `[x]` в этом файле.
- [ ] E2. Commit: `docs(016): mark tasks [x]`.
- [ ] E3. `git push -u origin egor/016-cleanup-wave`. PR-URL отдать Egor'у в чат.

## Зависимости

- A независим (deletes).
- B независим (UiTheme + 2 consumer-файла).
- C независим (3 разных файла + scene update).
- D независим (только doc).
- Порядок A→B→C→D не строгий, но коммитим в этом порядке для читаемости diff'а.
