# 015-refactor-wave-2 — plan

## API changes

### Ability (`scripts/core/abilities/ability.gd`) — F-014

Добавить публичное поле и заполнять его внутри `cast()`:

```gdscript
## Last cast()'s resolved target IDs. Read immediately after cast() returns
## true; not safe to cache (overwritten on every cast call). Skill aggregates
## these into its own EventBus.skill_cast emit (014a / F-014).
var last_target_ids: Array = []
```

В `cast()` перед `EventBus.ability_cast.emit(caster.actor_id, id, target_ids)` (line 98) добавить:
```gdscript
last_target_ids = target_ids
```

Сигнатура `cast()` НЕ меняется (`-> bool`). Существующие callers (Skill, godmode_controller direct cast paths) не ломаются.

### Skill (`scripts/core/skills/skill.gd`) — F-014

В `cast()` после `var resolved: bool = ab.cast(caster, ctx)` если `resolved` — agg'ать ids:

```gdscript
if resolved:
    any_resolved = true
    for tid in ab.last_target_ids:
        if tid not in all_target_ids:
            all_target_ids.append(tid)
```

`all_target_ids` уже декларирован на line 54, эмит на line 63 — не трогаются.

### UiTheme (`scripts/presentation/ui_theme.gd`) — F-008

Добавить рядом с `WORLD_TEXT_OUTLINE_COLOR` (после line 93):
```gdscript
# ── Soft drop shadow ─────────────────────────────────────────
# Lighter than world-text outline (alpha 0.95). For arrow shadows, panel
# elevations, anything where the shadow shouldn't compete with the foreground.
const SHADOW_SOFT_COLOR := Color(0, 0, 0, 0.55)
```

### IntentArrow (`scripts/presentation/intent_arrow.gd`) — F-008

- Удалить `const COLOR_SHADOW: Color = Color(0, 0, 0, 0.55)` (line 14).
- Все 3 use-site'а в `_draw()` (lines 59, 72) → `UiTheme.SHADOW_SOFT_COLOR`.

### ArenaDemoController (`scripts/presentation/arena_demo_controller.gd`) — F-007

`poly.color = Color(0.05, 0.80, 1.00)` (line 91) → `poly.color = UiTheme.SEM_MOVE`.

### config/game_speed.cfg — F-009 / F-010 / F-011 / F-012

В секцию `[ui]` добавить (порядок по логике):
```ini
floating_number_duration_ms=700
floating_number_crit_duration_ms=1100
toast_fade_in_sec=0.18
toast_fade_out_sec=0.20
toast_default_duration_sec=2.5
```

F5-hot-reload работает auto (GameSpeed подхватывает).

### FloatingNumber (`scripts/presentation/floating_number.gd`) — F-009

- Удалить `const DURATION_MS: int = 700` и `const CRIT_DURATION_MS: int = 1100` (lines 11-12).
- В `_ready()` (line 68) `var dur_ms: int = ...` заменить на чтение из GameSpeed:
  ```gdscript
  var dur_ms: int = int(GameSpeed.get_value(
      "ui",
      "floating_number_crit_duration_ms" if text.begins_with("CRIT") else "floating_number_duration_ms",
      1100 if text.begins_with("CRIT") else 700,
  ))
  ```

### ToastItem (`scripts/presentation/toast_item.gd`) — F-010 / F-011

- В `setup()` (line 44): `0.18` → `GameSpeed.get_value("ui", "toast_fade_in_sec", 0.18)`.
- В `_dismiss()` (line 52): `0.20` → `GameSpeed.get_value("ui", "toast_fade_out_sec", 0.20)`.

### ToastLayer (`scripts/presentation/toast_layer.gd`) — F-012

- Удалить `const DEFAULT_DURATION_SEC: float = 2.5` (line 12).
- В `_on_request` (line 40): `DEFAULT_DURATION_SEC` → `GameSpeed.get_value("ui", "toast_default_duration_sec", 2.5)`.

### GodmodeCamera (`scripts/presentation/godmode/godmode_camera.gd`) — F-013

- Добавить:
  ```gdscript
  var _follow_target: Node2D = null

  func set_follow_target(target: Node2D) -> void:
      _follow_target = target
      if is_inside_tree():
          _center_on_target()
  ```
- Переименовать `_center_on_player` → `_center_on_target`. Логика:
  ```gdscript
  func _center_on_target() -> void:
      var target: Node2D = _follow_target
      if target == null:
          # Fallback for standalone-scene runs (no controller injection).
          target = get_tree().root.find_child("Player", true, false) as Node2D
      if target != null:
          global_position = target.global_position
  ```
- В `_ready` оставить `_center_on_target.call_deferred()`.

### GodmodeController (`scripts/presentation/godmode/godmode_controller.gd`) — F-013

В `_place_player` (line 153) после `player.position = ...` (line 158) добавить:
```gdscript
var camera: Node = get_node_or_null("../GodmodeCamera")
if camera != null and camera.has_method("set_follow_target"):
    camera.set_follow_target(player)
```

`get_node_or_null` + `has_method` — для случая, когда controller запускается без камеры в тестовой сцене.

### EnemyAIPlanner (`scripts/core/ai/enemy_ai_planner.gd`) — F-015

В `_try_rule` (line 102 area):
- Перед циклом `for entry in matched:` (line 105) поднять:
  ```gdscript
  var sel_ctx: Dictionary = ctx.duplicate()
  ```
- Внутри цикла оставить только `sel_ctx["candidate_skill"] = s` (line 111). Удалить переписывание дубликата.

### CLAUDE.md — F-004 / F-005 doc note

В § Architecture (Hard rules) после правила 5 (UiTheme) добавить новый блок:

```markdown
### Accepted compromises (post-jam debt)

- **`Actor extends Node2D`** (`scripts/core/actors/actor.gd`) — core entity carries
  presentation semantics (`position`, sprite-children expectation in subclasses).
  Pragmatic compromise for jam — proper split would touch ~40 files. Post-jam:
  `Actor extends Resource` (data) + `ActorView extends Node2D` (visual binding).
- **`HexGrid extends Node2D`** (`scripts/core/arena/hex_grid.gd`) — same shape;
  holds `tile_map_layer` and `vfx_overlay` `TileMapLayer` exports directly.
  Post-jam: `HexGrid` for `Vector2i` math + `HexGridView` for rendering.

These are tracked in `specs/012-ultrareview/findings.md` (F-004, F-005), accepted
in 015-refactor-wave-2 as documented debt.
```

## Что НЕ трогается

- `Actor.gd`, `HexGrid.gd` — code path не меняется (только doc-mention в CLAUDE.md).
- `Ability.cast` сигнатура — `bool` остаётся; добавляется только новое поле.
- `EventBus.skill_cast` / `EventBus.ability_cast` сигнатуры — без изменений (имя/parameter list).
- 013-changed файлы (Actor.take_damage, floating_number_layer, combat_log, godmode_controller F6) — никакого retreading.
- Scene-файлы (`.tscn`): ни одного — F-013 чинится через runtime injection, не @export.

## Проверка вручную (Egor, ~5 минут в Godot 4.6.2)

1. **F5** на `scenes/dev/godmode.tscn`. Должно заработать без stderr-warnings/parse-errors.
2. **F-013:** камера центрируется на Player при загрузке. Спавн manekin'а (F1) — камера не сдвигается (target = player, не последний spawned).
3. **F-014:** assign skill `skill_debug_punch` на Q-slot. ЛКМ по manekin'у. В Output:
   - `[Ability] skill_debug_punch_basic cast by player → ...` (логирование без изменений)
   - `[Skill] skill_debug_punch cast by player → cd=...`
   - При наличии listener'ов на `EventBus.skill_cast` (нет в текущем staging) — `target_ids` непустой; проверить можно через GodmodeController `_on_skill_cast` если добавить debug-print.
4. **F-009:** floating number над manekin'ом по таймингам = 700ms (default). Поправить в `config/game_speed.cfg` (`floating_number_duration_ms=2000`), F5 на `game_speed.cfg` (live reload) — следующий удар с длинным fade.
5. **F-010/F-011/F-012:** trigger toast через любой `EventBus.ui_toast_requested.emit("test", 0, &"info")` (или reload settings panel'ом — у которого есть toast). Default 2.5s, fade ~0.18s. Поправить в cfg, hot-reload, увидеть разницу.
6. **F-007:** в `scenes/arena/arena_demo.tscn` (если ещё запускается) — placeholder polygon player'а должен быть `SEM_MOVE` (светло-серый), не cyan.
7. **F-008:** `IntentArrow` в playthrough (008-AI tick) — drop-shadow визуально не отличим от текущего (тот же alpha 0.55).
8. **F-015:** профайлер не нужен — это micro-opt; smoke-test = AI планирует → Output `[AIPlanner]` без crash'а.

## Risk

- **F-014 race на shared Ability resource.** Если ability шарится между skill'ами и оба cast'ятся в одном кадре — `last_target_ids` второго перетрёт первое до того как первый skill его прочитает. В текущем кодпасе `Skill.cast` синхронный (`for ab in abilities: ab.cast()`), читает `ab.last_target_ids` сразу после `ab.cast()` return. Cross-skill case в одном frame не существует — turn manager последователен. Doc-comment на поле — defensive measure.
- **GameSpeed cfg merge conflict.** Andrey может одновременно править `[ui]` секцию (009-ui-kit). Mitigation: новые ключи добавляются строкой-в-конец секции, не перетасовка.
- **`_center_on_target` rename.** Public — нет (private с underscore). Не ломает API.
