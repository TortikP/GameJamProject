# 026-skill-system-v3 — plan

**Spec:** [`spec.md`](./spec.md) · **Status:** Ready for /tasks → /implement (after Egor approves plan)

## Архитектурный обзор

Расширение схемы 021 + переход cast-API на `Array[Dictionary]` + переключение
парсинга эффектов с `kind`-discriminator на key-presence-fan-out.

```
Skill
├── + icon (новое, хранение)
└── cast(caster, ctxs: Array[Dictionary])  ◄── ИЗМЕНЁННАЯ СИГНАТУРА
       │
       └── for i in abilities.size():
              abilities[i].cast(caster, ctxs[i], self.level)

Ability
├── - sound (упразднено)
├── + sound_start / sound_end / collision_effect (новые)
└── cast(caster, ctx, level)  ◄── без изменений (021)

AbilityDatabase._make_effect (NEW)
       └── ОДИН dict → N инстансов в registry-order:
           damage → heal → status → move_type → entity_id

godmode_controller (NEW: state-machine для phase-1 collection)
       └── per-ability target picker → ctxs[] → Skill.cast(player, ctxs)
```

## Ключевые принципы

1. **Hard rename, no shim.** `sound` → `sound_start` без alias-периода; `kind` в effects вычищается без legacy-парсера; `max_chain_length`/`radius` на area-блоках только новые имена в JSON. Идиоматично 021.
2. **Effect-разворот на парсе, не в рантайме.** `AbilityDatabase` создаёт N типизированных `AbilityEffect` инстансов из одного JSON-объекта. `Ability.cast` ничего не знает о fan-out — он просто итерирует `effects[]` как и сейчас. Это сохраняет per-class `apply_level` / `apply` без переписывания.
3. **Registry-order детерминирован.** Документируется в `EFFECT_KEY_ORDER` константе в `AbilityDatabase`. Tests / debug-cast'ы фиксируют порядок.
4. **Phase 1 collection в caller'е, не в Skill/Ability.** Core (`Skill.cast`) — pure: получает готовые ctxs, применяет. UI/AI диспатчинг — в presentation.
5. **AI = broadcast.** AI пока не умеет per-ability. На границе вызова — `ctxs = [ctx] * abilities.size()`. Простой адаптер, no engine refactor.

## File changes

### Изменяемые

| Путь | Изменение | Размер |
|---|---|---|
| `scripts/core/skills/skill.gd` | +`icon: StringName`, `cast(caster, ctxs: Array[Dictionary])`, drop old single-ctx сигнатура | ~10 строк |
| `scripts/core/abilities/ability.gd` | rename `sound` → `sound_start`, +`sound_end`, +`collision_effect`. `cast()` без изменений (ctx — Dictionary) | ~5 |
| `scripts/core/abilities/ability_database.gd` | `_make_effect` — fan-out по эффект-ключам, registry-order; `_make_area` — JSON-key remap для `area_max_chain_length` / `area_radius`; парсинг `sound_start`/`sound_end`/`collision_effect` | ~40 |
| `scripts/core/skills/skill_database.gd` | парсинг `icon` | +3 |
| `scripts/presentation/godmode/godmode_controller.gd` | state-machine phase-1 collection в `_cast_slot` / `_request_cast_active`; ESC/right-click cancel; AI broadcast в `_resolve_cast_intent` | ~80 |
| `scripts/presentation/cast_range_overlay.gd` | `show_range` для конкретной ability (не all-of-skill, как сейчас) — добавить overload или переключить семантику | ~10 |

### Не трогаются

- Все effect-классы (`damage_effect.gd` / `heal_effect.gd` / `status_effect.gd` / `move_effect.gd` / `create_effect.gd`) — internals не меняются. `apply_level` / `apply` без правок.
- Все target / area-классы — internals не меняются (только AbilityDatabase remap'ит JSON-ключи на area).
- `enemy_ai_planner.gd` — broadcast делается на границе вызова в godmode_controller, не в планировщике.
- `Skill.predicted_damage_to`, `Skill.is_ready`, `Skill.tick_cooldown`, `Skill.can_apply` — без изменений.

### Новые файлы

- `data/skills/test_combo_multikey_effect.json` — single ability с multi-key effect объектом (damage + status в одном).

### Мигрируемые JSON (in-place)

Все 14 файлов в `data/skills/`. Точечные правки:

- **Effects:** убрать `"kind": "..."` из каждого эффект-объекта. Поля (`damage`, `heal`, `status`, `move_type`, `move_distance`, `entity_id`) — остаются.
- **Areas (chain):** `"max_chain_length"` → `"area_max_chain_length"`, `"radius"` → `"area_radius"` (если присутствуют).
- **Areas (zone_circle):** `"radius"` → `"area_radius"`.
- **Abilities:** `"sound": "..."` → `"sound_start": "..."` (если присутствует — сейчас все пустые, миграция тривиальна).
- Новые поля (`icon`, `sound_end`, `collision_effect`) — НЕ добавляем (default `&""` безопасен).

Список файлов для миграции:
```
data/skills/skill_debug_punch.json
data/skills/skill_knockback_punch.json
data/skills/skill_manekin_attack.json
data/skills/skill_melee_punch.json
data/skills/test_area_strike.json
data/skills/test_chain_lightning.json
data/skills/test_combo_actor_chain_damage.json
data/skills/test_combo_actor_chain_move.json
data/skills/test_combo_hex_circle_create.json
data/skills/test_combo_hex_circle_damage_status.json
data/skills/test_combo_self_self_heal.json
data/skills/test_level_scaling.json
data/skills/test_target_area_strike.json
data/skills/test_vamp_strike.json
```

## Module API contracts

### `Skill` (изменения)

```gdscript
class_name Skill
extends Resource

@export var id: StringName = &""
@export var name: String = ""
@export var tooltip: String = ""
@export var desc: String = ""
@export var icon: StringName = &""              # 026 — НОВОЕ
@export var cooldown: int = 0
@export var behaviour_tags: Array[StringName] = []
@export var mood: Array[StringName] = []
@export var level: int = 0
@export var abilities: Array[Ability] = []

var _cd_remaining: int = 0

func is_ready() -> bool
func can_apply(caster: Actor, ctx: Dictionary) -> bool   # ctx — для can_apply pre-check (одинокий)
func predicted_damage_to(caster: Actor, target: Actor, ctx: Dictionary) -> int
func get_ability_ids() -> Array[StringName]
func cast(caster: Actor, ctxs: Array[Dictionary]) -> bool   # 026 — ИЗМЕНЕНО
func tick_cooldown(by: int = 1) -> void
```

`can_apply` остаётся single-ctx — это pre-check для grey-out UI, оперирует первой ability'ей. Если игрок не может скастить вообще — multi-step picker не запускается.

`cast()` — strict: `ctxs.size() == abilities.size()`, иначе error log + return false.

### `Ability` (изменения)

```gdscript
class_name Ability
extends Resource

@export var id: StringName = &""
@export var sound_start: StringName = &""        # 026 — было `sound` в 021
@export var sound_end: StringName = &""          # 026 — НОВОЕ
@export var collision_effect: StringName = &""   # 026 — НОВОЕ
@export var animation: StringName = &""          # без изменений
@export var target: AbilityTarget
@export var area: AbilityArea
@export var effects: Array[AbilityEffect] = []
@export var modifiers: Array[ParameterModifier] = []

var last_target_ids: Array = []

func can_apply(caster: Actor, ctx: Dictionary) -> bool
func predicted_damage_to(caster: Actor, t: Actor, ctx: Dictionary, level: int = 0) -> int
func cast(caster: Actor, ctx: Dictionary, level: int = 0) -> bool   # без изменений
```

### `AbilityDatabase._make_effect` — переписан

```gdscript
# 026 — registry-order для разворота multi-key effect-объекта.
# damage → heal → status → move → create
const EFFECT_KEY_ORDER: Array[StringName] = [&"damage", &"heal", &"status", &"move_type", &"entity_id"]

const EFFECT_KIND_BY_KEY: Dictionary = {
    &"damage":    preload("res://scripts/core/abilities/effects/damage_effect.gd"),
    &"heal":      preload("res://scripts/core/abilities/effects/heal_effect.gd"),
    &"status":    preload("res://scripts/core/abilities/effects/status_effect.gd"),
    &"move_type": preload("res://scripts/core/abilities/effects/move_effect.gd"),
    &"entity_id": preload("res://scripts/core/abilities/effects/create_effect.gd"),
}

func _make_effects_from_dict(data: Dictionary, ability_id: String) -> Array[AbilityEffect]:
    if data.has("kind"):
        GameLogger.warn("AbilityDatabase", "%s: legacy 'kind' key in effect dict — ignoring (026 schema)" % ability_id)
    var out: Array[AbilityEffect] = []
    for key in EFFECT_KEY_ORDER:
        if not data.has(key):
            continue
        var script: GDScript = EFFECT_KIND_BY_KEY[key]
        var inst: AbilityEffect = script.new()
        # Apply ALL keys from the source dict (each effect ignores keys it doesn't define).
        # set() silently no-ops on missing properties — safe broadcast.
        for k in data.keys():
            if k == "kind":
                continue
            inst.set(k, data[k])
        out.append(inst)
    if out.is_empty():
        GameLogger.info("AbilityDatabase", "%s: effect dict has no recognised keys — skipping" % ability_id)
    return out
```

Замена для каждого `eff_data` в `build_ability_from_dict`:
```gdscript
# 021:
# var e := _make_effect(eff_data); if e != null: effects.append(e)
# 026:
for e in _make_effects_from_dict(eff_data, id):
    effects.append(e)
```

Старый `_make_effect` удаляется. Старая `EFFECT_KINDS` константа — заменена на `EFFECT_KIND_BY_KEY` (без `kind`-ключа в качестве дискриминатора).

**Почему `inst.set(k, data[k])` для всех ключей:** GDScript `Object.set(name, value)` на отсутствующем property — no-op (warn в editor, без crash). DamageEffect получит `damage=10`, проигнорирует `move_type`. MoveEffect получит `move_type/move_distance`, проигнорирует `damage`. Общие поля (`duration`, `requires_alive_target`) — попадают в обоих.

### `AbilityDatabase._make_area` — JSON-key remap

```gdscript
const AREA_KEY_REMAP: Dictionary = {
    "chain": {
        "area_max_chain_length": "max_chain_length",
        "area_radius":            "radius",
    },
    "zone_circle": {
        "area_radius": "radius",
    },
}

func _make_area(data: Dictionary) -> AbilityArea:
    var kind: String = data.get("kind", "")
    var script: Variant = AREA_KINDS.get(kind)
    if script == null:
        GameLogger.warn("AbilityDatabase", "unknown area kind: '%s'" % kind)
        return null
    var inst: Object = script.new()
    var remap: Dictionary = AREA_KEY_REMAP.get(kind, {})
    for key in data.keys():
        if key == "kind":
            continue
        var script_key: String = remap.get(key, key)   # remap if known, else passthrough
        inst.set(script_key, data[key])
    return inst as AbilityArea
```

GDScript-поля (`max_chain_length`, `radius` в `chain_area.gd` / `zone_circle_area.gd`) — **не переименовываются**. JSON-ключ → script-property mapping живёт только в `_make_area`. Это даёт grep-friendly префикс в JSON без массового touch'а кода / резервирует пространство имён для будущих area-полей.

### `Ability.cast` — без изменений

Lifecycle 021 неизменён. Effect-разворот происходит на парсе — `Ability.effects` к моменту cast уже содержит N разнесённых типизированных инстансов в registry-order. Никаких runtime-проверок.

### `Skill.cast` — новая сигнатура

```gdscript
func cast(caster: Actor, ctxs: Array[Dictionary]) -> bool:
    if not is_ready():
        GameLogger.info("Skill", "%s on cooldown (%d remaining)" % [id, _cd_remaining])
        return false

    if ctxs.size() != abilities.size():
        GameLogger.error("Skill", "%s: ctxs.size()=%d, abilities.size()=%d — mismatch" % [id, ctxs.size(), abilities.size()])
        return false

    var any_resolved: bool = false
    var all_target_ids: Array = []

    for i in abilities.size():
        var resolved: bool = abilities[i].cast(caster, ctxs[i], level)
        if resolved:
            any_resolved = true
            for tid in abilities[i].last_target_ids:
                if not all_target_ids.has(tid):
                    all_target_ids.append(tid)

    if any_resolved:
        _cd_remaining = cooldown
        EventBus.skill_cast.emit(caster.actor_id, id, all_target_ids)
        GameLogger.info("Skill", "%s cast by %s → cd=%d" % [id, caster.actor_id, _cd_remaining])

    return any_resolved
```

Hard break vs 021: caller'ы получат parse error на старом single-Dictionary вызове. Это намеренно — компилятор/runtime поймает в момент миграции.

## Player cast state-machine

Новая state в `godmode_controller.gd`. Минимальный API внутри контроллера, без отдельного класса (jam-scope).

```gdscript
# State for multi-step cast collection.
var _cast_in_progress: bool = false
var _cast_skill: Skill = null
var _cast_step: int = 0              # current ability index in skill.abilities
var _cast_ctxs: Array[Dictionary] = []  # collected so far
```

### Entry: игрок жмёт ЛКМ при активном слоте

`_request_cast_active` вместо одного-shot вызова `_cast_slot` запускает state-machine:

```
1. skill = active slot
2. if skill == null or not skill.can_apply(player, mouse_ctx): return
3. _cast_skill = skill
4. _cast_step = 0
5. _cast_ctxs = []
6. _cast_in_progress = true
7. _begin_step()
```

`_begin_step()`:
```
ab = _cast_skill.abilities[_cast_step]
if ab.target.kind is SelfTarget:
    UI: показать «Confirm» prompt (см. ниже)
else:
    cast_range_overlay.show_range_for_ability(player, ab)  # одна ability, не all-skill
```

### Step commit

ЛКМ по гексу (или confirm-action для self-target):
```
1. coord = mouse_coord (для self → caster_coord)
2. target_id = grid.get_actor_at(coord) (для self → player.actor_id)
3. ctx = {"registry": registry, "grid": grid, "target_id": target_id, "target_coord": coord}
4. _cast_ctxs.append(ctx)
5. _cast_step += 1
6. if _cast_step == _cast_skill.abilities.size():
       _commit_cast()
   else:
       _begin_step()
```

`_commit_cast()`:
```
1. cast_range_overlay.hide_range()
2. did_cast = _cast_skill.cast(player, _cast_ctxs)
3. _reset_cast_state()
4. if did_cast:
       await GameSpeed.wait("godmode", "ability_cast_delay")
       TurnManager.advance()
```

### Cancel

ESC, right-click, переключение слота, или клик вне валидного гекса — все ведут в `_cancel_cast()`:
```
1. cast_range_overlay.hide_range()
2. _reset_cast_state()
   (no cooldown, no commit, no turn advance)
```

`_reset_cast_state()`:
```
_cast_in_progress = false
_cast_skill = null
_cast_step = 0
_cast_ctxs = []
```

### Self-confirm UI

`target.kind is SelfTarget` — каст-overlay не показывает обычные target hexes. Вместо этого:
- `cast_range_overlay.show_self_confirm(player_coord)` — подсветка гекса под игроком тем же стилем, что и обычный target hex (но цвет = SEM_BUFF / тёплый, не SEM_DEBUFF). Визуально читаемо как «целишь в себя».
- Один из triggers commit'ит шаг:
  - повторное нажатие активного слота;
  - ЛКМ по гексу под caster'ом.

Реализация — расширение `cast_range_overlay.gd`: добавить `show_self_confirm(coord, color)`. ~10 строк.

### Single-ability fast path

Если `skill.abilities.size() == 1` — UX неотличим от 021: один target step → cast. State-machine остаётся (для единообразия), но игрок не замечает разницы.

## AI broadcast

`_resolve_cast_intent` (godmode_controller, строка ~792 текущего файла):

```gdscript
# 026: AI broadcasts a single ctx to all abilities. Per-ability AI targeting
# is out of scope — see spec §"Out of scope".
var ctx: Dictionary = {
    "registry": registry, "grid": grid,
    "target_id": target_id, "target_coord": target_coord,
}
var ctxs: Array[Dictionary] = []
for _i in skill.abilities.size():
    ctxs.append(ctx)
skill.cast(enemy, ctxs)
```

Один-line адаптер. Никаких изменений в `enemy_ai_planner.gd` / `CastIntent` — они продолжают планировать ОДНУ цель, fan-out — на границе вызова.

## Migration of data/skills/*.json

Скрипт миграции (одноразовый, не комитим в репо — выполняется руками):

```python
# Apply to each *.json:
# 1. Drop "kind" from every effect dict.
# 2. Rename area keys: max_chain_length → area_max_chain_length, radius → area_radius.
# 3. Rename ability key: sound → sound_start.
```

Применить через скрипт `python3 -c "..."` (см. tasks T07). После — `git diff data/skills/*.json` сверяет, потом `git add -p`.

## Order matters

- **Парсер ДО рантайма.** К моменту первой `Ability.cast` все эффекты уже разнесены в `effects[]` registry-order. `Ability.cast` не должен ничего знать про fan-out.
- **`apply_level` ДО `_apply_param_modifiers`** (как 021).
- **`Skill.cast` НЕ итерирует ctx внутри ability.** Каждая ability получает СВОЙ ctx из `ctxs[i]`. Внутри ability lifecycle — без изменений.

## ChainArea / ZoneCircleArea — без изменений

GDScript-поля `max_chain_length` / `radius` остаются. JSON-ключи `area_max_chain_length` / `area_radius` переводятся в скрипт-имена через `AREA_KEY_REMAP` в `_make_area`. Никакого touch'а в areas/*.gd.

## Acceptance gate plan→tasks

- [x] API-контракты приняты (Egor, чат 02.05).
- [x] Effect-разворот: parse-time fan-out + registry-order (Egor, чат 02.05).
- [x] `ability.id` keep (Egor, чат 02.05).
- [x] Phase-1 collection в caller'е, не в Skill (plan-decision, очевидное продолжение spec §"Per-ability target selection").
- [x] AI = broadcast ctxs-fan-out (plan-decision, явное в spec §"AI flow").
- [x] Hard rename без backcompat (как 021, AC-M3).
