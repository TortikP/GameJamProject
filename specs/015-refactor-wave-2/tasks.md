# 015-refactor-wave-2 — tasks

Sequential кластерами (по concern из findings.md slicing). Один кластер = один commit.

## A — F-004 + F-005 (doc-only, accepted compromises)

- [x] A1. `CLAUDE.md` § Hard rules / Architecture — добавить блок «Accepted compromises» после правила 5 (UiTheme).
- [x] A2. Commit: `docs(015): F-004+F-005 — accepted Actor/HexGrid Node2D compromise`.

## B — F-007 + F-008 (UiTheme misses)

- [x] B1. `scripts/presentation/ui_theme.gd` — добавить `const SHADOW_SOFT_COLOR := Color(0, 0, 0, 0.55)` после `WORLD_TEXT_OUTLINE_COLOR` block с комментарием-headline «Soft drop shadow».
- [x] B2. `scripts/presentation/intent_arrow.gd:14` — удалить `const COLOR_SHADOW`.
- [x] B3. `scripts/presentation/intent_arrow.gd:59,72` — все use-site'а `COLOR_SHADOW` → `UiTheme.SHADOW_SOFT_COLOR`.
- [x] B4. `scripts/presentation/arena_demo_controller.gd:91` — `Color(0.05, 0.80, 1.00)` → `UiTheme.SEM_MOVE`.
- [x] B5. Manual smoke: `arena_demo.tscn` (если запускается) — polygon серый, не cyan. IntentArrow визуально не изменился. (deferred to Egor)
- [x] B6. Commit: `feat(015): F-007+F-008 — UiTheme.SHADOW_SOFT_COLOR + cyan→SEM_MOVE`.

## C — F-009 + F-010 + F-011 + F-012 (GameSpeed [ui] keys)

- [ ] C1. `config/game_speed.cfg` `[ui]` секция — добавить 5 ключей:
  ```
  floating_number_duration_ms=700
  floating_number_crit_duration_ms=1100
  toast_fade_in_sec=0.18
  toast_fade_out_sec=0.20
  toast_default_duration_sec=2.5
  ```
- [ ] C2. `scripts/presentation/floating_number.gd:11-12` — удалить `const DURATION_MS`, `const CRIT_DURATION_MS`.
- [ ] C3. `scripts/presentation/floating_number.gd:_ready` — `var dur_ms` через `GameSpeed.get_value("ui", ..., default)`.
- [ ] C4. `scripts/presentation/toast_item.gd:setup` (line 44) — `0.18` → `GameSpeed.get_value("ui", "toast_fade_in_sec", 0.18)`.
- [ ] C5. `scripts/presentation/toast_item.gd:_dismiss` (line 52) — `0.20` → `GameSpeed.get_value("ui", "toast_fade_out_sec", 0.20)`.
- [ ] C6. `scripts/presentation/toast_layer.gd:12` — удалить `const DEFAULT_DURATION_SEC`.
- [ ] C7. `scripts/presentation/toast_layer.gd:_on_request` (line 40) — заменить `DEFAULT_DURATION_SEC` → `GameSpeed.get_value("ui", "toast_default_duration_sec", 2.5)`.
- [ ] C8. Manual smoke: floating number, toast — длительности соответствуют cfg, hot-reload (F5 на game_speed.cfg) меняет тайминги без перезапуска.
- [ ] C9. Commit: `feat(015): F-009..F-012 — GameSpeed [ui] keys for floating numbers + toasts`.

## D — F-013 (godmode_camera follow_target injection)

- [ ] D1. `scripts/presentation/godmode/godmode_camera.gd` — добавить `var _follow_target: Node2D = null` и метод `set_follow_target(target: Node2D) -> void`.
- [ ] D2. `scripts/presentation/godmode/godmode_camera.gd` — переименовать `_center_on_player` → `_center_on_target`. Логика: использовать `_follow_target`, fallback `find_child("Player", ...)`.
- [ ] D3. `scripts/presentation/godmode/godmode_camera.gd:_ready` — `_center_on_target.call_deferred()`.
- [ ] D4. `scripts/presentation/godmode/godmode_controller.gd:_place_player` — после `player.position = ...` (line 158): инжект `camera.set_follow_target(player)` через `get_node_or_null("../GodmodeCamera")` + `has_method` check.
- [ ] D5. Manual smoke: F5 godmode → камера на player. F1 спавн manekin'а — камера не двигается.
- [ ] D6. Commit: `feat(015): F-013 — godmode_camera follow_target injection`.

## E — F-014 (skill_cast aggregates target_ids)

- [ ] E1. `scripts/core/abilities/ability.gd` — добавить публичное поле `var last_target_ids: Array = []` после `@export var modifiers` block с doc-comment про overwrite-on-cast.
- [ ] E2. `scripts/core/abilities/ability.gd:cast` — перед `EventBus.ability_cast.emit(...)` (line 98): `last_target_ids = target_ids`.
- [ ] E3. `scripts/core/skills/skill.gd:cast` — внутри `for ab in abilities:` после `if resolved:` agg'ать ids в `all_target_ids` (без дубликатов).
- [ ] E4. Manual smoke: cast skill_debug_punch в godmode на manekin'а — Output не падает; добавить `print(target_ids)` в EventBus.skill_cast listener (временно) проверить непустой.
- [ ] E5. Commit: `fix(015): F-014 — Skill.cast aggregates target_ids from Ability.last_target_ids`.

## F — F-015 (single ctx.duplicate() in _try_rule)

- [ ] F1. `scripts/core/ai/enemy_ai_planner.gd:_try_rule` — поднять `var sel_ctx: Dictionary = ctx.duplicate()` перед циклом `for entry in matched:`.
- [ ] F2. Внутри цикла оставить только `sel_ctx["candidate_skill"] = s`, удалить дубликат-вызов.
- [ ] F3. Commit: `perf(015): F-015 — single sel_ctx.duplicate() outside _try_rule loop`.

## G — Closeout

- [ ] G1. Отметить все `[x]` в этом файле.
- [ ] G2. Commit: `docs(015): mark tasks [x]`.
- [ ] G3. Push, отдать PR-URL Egor'у в чат.

## Зависимости

- A независим (только doc).
- B независим.
- C независим (cfg + 3 файла).
- D независим (godmode pair).
- E независим (skill+ability pair).
- F независим (single function).
- Порядок A→B→C→D→E→F не строгий, можно параллелить, но коммитим сериями (по кластерам).
