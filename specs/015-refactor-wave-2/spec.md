# 015-refactor-wave-2 — P2 architectural cleanup

**Owner:** Andrey (per `specs/012-ultrareview/findings.md` §014-refactor-wave-2 backlog).
**Implementer:** Egor (override of AC-A5 owner-implements rule, granted in chat — same pattern as 013).
**Status:** Active.

## Назначение

Закрытие всех P2 findings из 012-ultrareview, оставшихся после 013 (combat-feedback wiring уже взят wave-1).

Слот 014 ушёл под Andrey/`spec014-temple` — этот pack идёт как 015, имя «refactor-wave-2» сохранено для прослеживаемости с findings.md (там F-IDs распределены по виртуальным меткам 014a/014b/014c).

**B-001 add-on (out-of-band):** в эту же ветку домержен баг-фикс preview-anchor для self-target abilities. Это нарушает «one concern per PR», но решение принято в чате (Egor) — отдельная ветка для одного 3-файлового баг-фикса даёт больше overhead'а на PR review, чем экономии. Если ревьюер 015 откажется — отщепим B-001 в отдельный 016 cherry-pick'ом.

## Findings — что закрываем

| ID | Sev | Файл | Что не работает | Кластер |
|---|---|---|---|---|
| F-004 | P2 | `scripts/core/actors/actor.gd:2` | `Actor extends Node2D` — core ↔ presentation смешаны. | `014a` (doc-only) |
| F-005 | P2 | `scripts/core/arena/hex_grid.gd:2,21-22` | `HexGrid extends Node2D` + `@export var tile_map_layer/vfx_overlay`. То же. | `014a` (doc-only) |
| F-007 | P2 | `scripts/presentation/arena_demo_controller.gd:91` | `Color(0.05, 0.80, 1.00)` raw cyan в `_create_placeholder_actor`. | `014b` |
| F-008 | P2 | `scripts/presentation/intent_arrow.gd:14` | `const COLOR_SHADOW: Color = Color(0, 0, 0, 0.55)` literal. | `014b` |
| F-009 | P2 | `scripts/presentation/floating_number.gd:11-12` | `DURATION_MS=700` / `CRIT_DURATION_MS=1100` хардкод. | `014c` |
| F-010 | P2 | `scripts/presentation/toast_item.gd:44` | `tween_property(..., 0.18)` хардкод fade-in. | `014c` |
| F-011 | P2 | `scripts/presentation/toast_item.gd:52` | `tween_property(..., 0.20)` хардкод fade-out. | `014c` |
| F-012 | P2 | `scripts/presentation/toast_layer.gd:12` | `const DEFAULT_DURATION_SEC: float = 2.5` хардкод. | `014c` |
| F-013 | P2 | `scripts/presentation/godmode/godmode_camera.gd:30` | `find_child("Player", true, false)` — fragile cross-tree lookup. | `014a` (piggy-back) |
| F-014 | P2 | `scripts/core/skills/skill.gd:54,63` | `all_target_ids` declared, never appended, эмитится `[]`. | `014a` |
| F-015 | P2 | `scripts/core/ai/enemy_ai_planner.gd:110` | `ctx.duplicate()` per-iteration в `_try_rule` — аллокация в AI hot path. | `014a` |
| B-001 | bug | `scripts/presentation/godmode/godmode_controller.gd:326` | AoE preview всегда использует hover_coord как primary для `area.get_affected_hexes`. При `target=SelfTarget` область следует за курсором, а при касте резко прыгает на caster — рассинхрон preview ↔ resolve. | `015-bugfix` (out-of-band) |

## Out of scope

- **F-006** — закрыт побочно в 013 (`world_pos` приходит в payload `damage_dealt`, parent-walk удалён).
- **F-016..F-031** (P3) — отдельный pack, не в этом PR.
- **«Real» split Actor/HexGrid → core (data) + view (Node2D)** — F-004/F-005 закрываются как «принятый компромисс» через docs, не код. Реальный split = post-jam, ~40 файлов трогать.
- **`Ability.cast` рефактор на возврат `Array`** — F-014 закрывается через `last_target_ids` field (non-breaking), не через изменение сигнатуры (которое требовало бы `breaking:` PR).
- **Любые правки P1** — все P1 закрыты в 013.

## Acceptance criteria

- **AC-1 (F-004 / F-005):** В `CLAUDE.md` § Hard rules / Architecture добавлен абзац «Accepted compromises» с явным указанием, что `Actor` и `HexGrid` extend `Node2D` (а не `Resource` + ViewNode), и что это post-jam долг. Никаких code changes.
- **AC-2 (F-007):** В `arena_demo_controller.gd:_create_placeholder_actor` цвет polygon = `UiTheme.SEM_MOVE` (не raw `Color(...)`).
- **AC-3 (F-008):** В `ui_theme.gd` добавлена константа `SHADOW_SOFT_COLOR := Color(0, 0, 0, 0.55)` (рядом с `WORLD_TEXT_OUTLINE_COLOR`). В `intent_arrow.gd` `const COLOR_SHADOW` удалён, все 3 use-site'а ссылаются на `UiTheme.SHADOW_SOFT_COLOR`.
- **AC-4 (F-009):** В `config/game_speed.cfg` секция `[ui]` пополнена `floating_number_duration_ms=700`, `floating_number_crit_duration_ms=1100`. `floating_number.gd` читает их через `GameSpeed.get_value("ui", ...)` в `_ready` (текущие `const`-ы заменены), defaults = текущие значения.
- **AC-5 (F-010 / F-011):** В `[ui]` добавлены `toast_fade_in_sec=0.18`, `toast_fade_out_sec=0.20`. `toast_item.gd` читает их в `setup` / `_dismiss`.
- **AC-6 (F-012):** В `[ui]` добавлен `toast_default_duration_sec=2.5`. `toast_layer.gd` читает его в `_on_request` (`const DEFAULT_DURATION_SEC` удалён).
- **AC-7 (F-013):** `godmode_camera.gd` получает метод `set_follow_target(target: Node2D)`. `_center_on_player` сначала использует injected target, fallback к `find_child` остаётся как safety-net (godmode часто запускается standalone, NodePath @export не помогает потому что Player спавнится runtime'ом). `godmode_controller._place_player()` после позиционирования вызывает `_camera.set_follow_target(player)`.
- **AC-8 (F-014):** В `Ability` добавлено поле `var last_target_ids: Array = []`, заполняется внутри `cast()` перед `EventBus.ability_cast.emit`. В `Skill.cast` после успешного `ab.cast(...)` IDs берутся из `ab.last_target_ids` и agg'аются в `all_target_ids` (без дубликатов). При emit'е `EventBus.skill_cast` `target_ids` непустой, если хоть одна ability resolved.
- **AC-9 (F-015):** В `_try_rule` `var sel_ctx: Dictionary = ctx.duplicate()` вынесен из цикла; внутри только `sel_ctx["candidate_skill"] = s`. После цикла state очищать не нужно (sel_ctx уходит из scope в конце функции).
- **AC-10 (CLAUDE.md hard-rules check):** Никаких inline `Color(...)` в presentation, никаких bare `create_timer`, никаких новых хардкодов content. `class_name`-ы, snake_case past tense — без изменений.
- **AC-11 (B-001 self-target preview anchor):** В `AbilityTarget` добавлен виртуальный метод `preview_anchor_coord(caster_coord, hover_coord) -> Vector2i` (default = hover_coord). `SelfTarget` override → `caster_coord`. `godmode_controller` AoE preview loop вызывает `ab.target.preview_anchor_coord(...)` вместо передачи hover'а напрямую. Поведение: при `target=SelfTarget` зона висит на кастере и не двигается с мышкой; при `target=Hex/Entity` поведение прежнее (preview под курсором). При `area=SelfArea` подсвечивается тайл кастера (`SelfArea.get_affected_hexes` уже игнорирует primary — без изменений).

## Зависимости

- **Upstream:** 013 мержен в staging (combat-feedback signals + F-001 keybind move). ✓ присутствует на момент создания этой ветки.
- **Downstream:** P3 cleanup pack (dead files, godmode hardcoded debug-skill IDs) ждёт отдельной ветки.

## Risk

- **F-014 + Ability.last_target_ids field state.** Resource'ы могут шерится между Skill'ами. В нашем кодпасе — каждый `Skill` владеет своим `Array[Ability]`, но если две сущности когда-нибудь начнут шерить ability — `last_target_ids` будет race-d. Mitigation: doc-comment на поле «Overwritten on each cast(). Read immediately after cast() call by the same caller; do not cache.»
- **F-013 fallback retention.** `find_child("Player", ...)` оставлен как safety, потому что `godmode.tscn` запускается standalone (через F5 на сцене) — в этом случае godmode_controller_set_follow_target отработает как сейчас, но если кто-то запустит `godmode_camera.tscn` без controller'а (тестовая сцена) — find_child прежний путь.
- **GameSpeed [ui] keys** — новые ключи добавляют content в Andrey-owned `config/game_speed.cfg`. Override granted via chat (как 013). PR-time: Andrey approves diff на cfg.
