# 021-skill-system-v2 — plan

**Spec:** [`spec.md`](./spec.md) · **Status:** Ready for /implement

## Архитектурный обзор

Расширение существующего контракта 007 без структурных изменений lifecycle. Точечные точки воздействия:

```
Skill
├── + name / tooltip / desc / mood / level / behaviour_tags (rename tags)
└── cast(caster, ctx)  →  for ab in abilities: ab.cast(caster, ctx, level)
                                                                    ▲
                                                                    │ новое
Ability
├── + sound / animation (хранение, без dispatch)
└── cast(caster, ctx, level)
       │
       ├── target_dup = target.duplicate(); target_dup.apply_level(level)
       ├── area_dup   = area.duplicate();   area_dup.apply_level(level)
       └── for victim, for eff:
              eff_dup = eff.duplicate()
              eff_dup.apply_level(level)
              _apply_param_modifiers(eff_dup, modifiers)
              eff_dup.apply(...)
```

Ключевые принципы:

- **Самореакция компонентов на level.** Базовый класс — virtual no-op, подкласс знает свою формулу. Никакого `if eff is DamageEffect: eff.damage *= ...` в `Ability.cast`.
- **Порядок: сначала `apply_level`, потом `_apply_param_modifiers`.** Уровень — базовая прогрессия (вшита в навык), модификаторы — гранулярные крафт-аффиксы поверх. Стек: `((base_after_level) + Σadds) × Π muls`.
- **Дюпликаты, базы не трогать.** Skill/Ability Resource'ы шарятся между кастами, мутировать запрещено.

## File changes

### Изменяемые

| Путь | Изменение | Размер |
|---|---|---|
| `scripts/core/skills/skill.gd` | +5 export'ов, rename tags→behaviour_tags, level в cast | ~15 строк |
| `scripts/core/abilities/ability.gd` | +2 export'а (sound/animation), `cast(...,level)`, `predicted_damage_to(...,level)`, target.duplicate+apply_level | ~20 |
| `scripts/core/abilities/ability_target.gd` | +virtual `apply_level` | +3 |
| `scripts/core/abilities/ability_area.gd` | +virtual `apply_level` | +3 |
| `scripts/core/abilities/ability_effect.gd` | +virtual `apply_level` | +3 |
| `scripts/core/abilities/effects/damage_effect.gd` | override `apply_level` | +5 |
| `scripts/core/abilities/effects/heal_effect.gd` | override `apply_level` | +5 |
| `scripts/core/abilities/effects/status_effect.gd` | override `apply_level` (duration) | +4 |
| `scripts/core/abilities/effects/move_effect.gd` | override `apply_level` (duration only) | +4 |
| `scripts/core/abilities/effects/create_effect.gd` | rename `game_object_id`→`entity_id`, no-op apply_level (можно опустить) | +0 кода / rename |
| `scripts/core/abilities/areas/chain_area.gd` | +`@export var radius: int = 1`, BFS-step с радиусом, override `apply_level` (max_chain_length) | +15 |
| `scripts/core/abilities/areas/zone_circle_area.gd` | override `apply_level` (radius) | +4 |
| `scripts/core/abilities/areas/self_area.gd` | — (no-op default достаточен) | 0 |
| `scripts/core/abilities/targets/hex_target.gd` | override `apply_level` (range) | +4 |
| `scripts/core/abilities/targets/object_target.gd` | override `apply_level` (range) — даже на stub'е, чтобы не забыть | +4 |
| `scripts/core/abilities/targets/self_target.gd` | — | 0 |
| `scripts/core/abilities/ability_database.gd` | rename `entity`→`actor` в `TARGET_KINDS`, перепреlоad на `actor_target.gd`, парсинг `sound`/`animation` | ~5 |
| `scripts/core/skills/skill_database.gd` | парсинг `name`/`tooltip`/`desc`/`mood`/`level`, rename `tags`→`behaviour_tags` | ~15 |
| `scripts/core/ai/enemy_ai_planner.gd` | `s.tags` → `s.behaviour_tags` (2 строки) | 2 |
| `scripts/presentation/godmode/godmode_controller.gd` | `skill.tags` → `skill.behaviour_tags` (2 строки) | 2 |

### Переименовываемые (через `git mv`)

| From | To |
|---|---|
| `scripts/core/abilities/targets/entity_target.gd` | `scripts/core/abilities/targets/actor_target.gd` |

Внутри файла: `class_name EntityTarget` → `class_name ActorTarget`.

### Новые JSON-фикстуры

```
data/skills/test_combo_actor_chain_damage.json
data/skills/test_combo_hex_circle_damage_status.json
data/skills/test_combo_self_self_heal.json
data/skills/test_combo_actor_chain_move.json
data/skills/test_combo_hex_circle_create.json
data/skills/test_level_scaling.json
```

### Мигрируемые JSON'ы (in-place)

```
data/skills/skill_debug_punch.json
data/skills/skill_melee_punch.json
data/skills/skill_manekin_attack.json
data/skills/skill_knockback_punch.json
data/skills/test_area_strike.json
data/skills/test_chain_lightning.json
data/skills/test_target_area_strike.json
data/skills/test_vamp_strike.json
```

Точечные изменения:
- `"tags"` → `"behaviour_tags"` (где есть)
- `"kind": "entity"` → `"kind": "actor"` (где есть)
- `game_object_id` ключ в create-эффекте → `entity_id` (на текущий момент таких в JSON нет, но добавим в новых тестах)
- Опциональные `name`/`tooltip`/`desc`/`mood`/`level`/`sound`/`animation` НЕ добавляем в production JSON'ы (default'ы безопасны), кроме `test_level_scaling.json` (там `level: 2` явно).

## Module API contracts

### `Skill` (расширение)

```gdscript
class_name Skill
extends Resource

@export var id: StringName = &""
@export var name: String = ""
@export var tooltip: String = ""
@export var desc: String = ""
@export var cooldown: int = 0
@export var behaviour_tags: Array[StringName] = []   # was: tags
@export var mood: Array[StringName] = []
@export var level: int = 0
@export var abilities: Array[Ability] = []

# Runtime state
var _cd_remaining: int = 0

func is_ready() -> bool
func can_apply(caster: Actor, ctx: Dictionary) -> bool
func predicted_damage_to(caster: Actor, target: Actor, ctx: Dictionary) -> int
func get_ability_ids() -> Array[StringName]
func cast(caster: Actor, ctx: Dictionary) -> bool   # внутри: ab.cast(caster, ctx, self.level)
func tick_cooldown(by: int = 1) -> void
```

`name` хранится как `String` (не `StringName`) — это loc-key, может быть длинным, не интернируется.

### `Ability` (расширение)

```gdscript
class_name Ability
extends Resource

@export var id: StringName = &""
@export var sound: StringName = &""        # новое
@export var animation: StringName = &""    # новое
@export var target: AbilityTarget
@export var area: AbilityArea
@export var effects: Array[AbilityEffect] = []
@export var modifiers: Array[ParameterModifier] = []

var last_target_ids: Array = []

func can_apply(caster: Actor, ctx: Dictionary) -> bool
func predicted_damage_to(caster: Actor, t: Actor, ctx: Dictionary, level: int = 0) -> int
func cast(caster: Actor, ctx: Dictionary, level: int = 0) -> bool
```

### Virtual `apply_level(level: int)` контракт

```gdscript
# AbilityTarget / AbilityArea / AbilityEffect — base no-op
func apply_level(_level: int) -> void:
    pass

# Подкласс — пример (DamageEffect):
func apply_level(level: int) -> void:
    if level <= 0: return
    damage = int(floor(damage * (1.0 + 0.2 * level)))
```

Контракт: вызывается **на duplicate'е** перед `resolve()`/`apply()`. Идемпотентность не требуется (вызывается один раз). Уровень 0 — гарантия no-op (раняя проверка в каждом override).

## Lifecycle: `Ability.cast(caster, ctx, level)`

```
1. if target == null or area == null or effects.is_empty(): error → false

2. target_dup = target.duplicate()
   target_dup.apply_level(level)
   primary = target_dup.resolve(caster, ctx)
   if primary == null: return false

3. area_dup = area.duplicate()
   area_dup.apply_level(level)
   _apply_param_modifiers(area_dup, modifiers)   # модификаторы поверх level
   victims = area_dup.resolve(caster, primary, ctx)

4. if victims.is_empty(): return false
   exclude_caster если primary == caster

5. for victim in victims:
       for base_eff in effects:
           eff_dup = base_eff.duplicate()
           eff_dup.apply_level(level)             # уровень
           _apply_param_modifiers(eff_dup, modifiers)  # модификаторы поверх
           if eff_dup.requires_alive_target and _is_dead(victim): continue
           eff_dup.apply(caster, victim, ctx)

6. last_target_ids = ...
   EventBus.ability_cast.emit(caster.actor_id, id, target_ids)
7. return true
```

Order matters: `apply_level` ⇒ `_apply_param_modifiers`. Уровень — базовая шкала, модификаторы — поверх.

## Lifecycle: `Skill.cast(caster, ctx)`

```
1. if not is_ready(): return false
2. for ab in abilities:
       ab.cast(caster, ctx, self.level)
3. _cd_remaining = cooldown
4. EventBus.skill_cast.emit(...)
5. return true
```

## Data schema example — `data/skills/test_level_scaling.json`

```json
{
  "id": "test_level_scaling",
  "name": "skill.test_level_scaling.name",
  "tooltip": "skill.test_level_scaling.tooltip",
  "desc": "skill.test_level_scaling.desc",
  "cooldown": 2,
  "behaviour_tags": ["damage", "heal"],
  "mood": ["toxic"],
  "level": 2,
  "abilities": [
    {
      "id": "tls_dmg",
      "sound": "snd_strike",
      "animation": "anim_punch",
      "target": {"kind": "actor", "range": -1},
      "area":   {"kind": "chain", "max_chain_length": 1, "radius": 1},
      "effects": [
        {"kind": "damage", "duration": 0, "damage": 100}
      ],
      "modifiers": []
    },
    {
      "id": "tls_heal",
      "sound": "snd_pulse",
      "animation": "anim_heal",
      "target": {"kind": "self"},
      "area":   {"kind": "self"},
      "effects": [
        {"kind": "heal", "duration": 0, "heal": 50}
      ],
      "modifiers": []
    }
  ]
}
```

Ожидание при касте: damage `100 * 1.4 = 140`, heal `50 * 1.2 = 60` (floor).

## ChainArea с radius — алгоритм

Для текущей цепи (radius=1) ничего не меняется — BFS на 1 шаг ⇔ direct neighbors.

Для radius>1 на каждом звене:
1. Из `current_coord` — BFS на до `radius` шагов через `grid.get_walkable_neighbours`.
2. Среди достигнутых hex'ов — отфильтровать те, где есть alive non-caster Actor, ещё не visited.
3. Выбрать ближайший по BFS-distance (первый встреченный — ближайший по построению BFS).
4. Если найден — добавить в результат, current_coord ← his_coord. Иначе — break.
5. Visited tracking сохраняется между звеньями.

Имплементационная заметка: можно переиспользовать `grid.reachable_within(current, radius, [])` и итерировать в порядке возрастания BFS-расстояния (если `reachable_within` гарантирует сортировку — проверить и если нет, BFS написать вручную).

## Парсер `_apply_params` — без изменений

`AbilityDatabase._apply_params` уже использует `inst.set(key, data[key])` — он автоматически подхватит новые поля (`sound`, `animation`, `radius` на ChainArea, `entity_id` в CreateEffect, `name`/`tooltip`/`desc`/`mood`/`level`/`behaviour_tags` через `SkillDatabase`). Главное — добавить эти `@export`'ы на ресурсах.

## Renaming entity → actor

`git mv scripts/core/abilities/targets/entity_target.gd scripts/core/abilities/targets/actor_target.gd` + правка `class_name`.

`AbilityDatabase.TARGET_KINDS`:
```gdscript
"actor": preload("res://scripts/core/abilities/targets/actor_target.gd"),
# ↑ ключ "entity" удаляется, не coexist
```

JSON в data/skills: `"kind": "entity"` → `"kind": "actor"` во всех файлах одной волной.

Потребителей `EntityTarget` (как класс по имени) в коде нет — grep на `EntityTarget` показал только сам файл. Безопасный rename.

## Migration of existing data/skills/*.json

| Файл | Изменение |
|---|---|
| `skill_debug_punch.json` | `tags`→`behaviour_tags`, `entity`→`actor` |
| `skill_melee_punch.json` | то же |
| `skill_manekin_attack.json` | то же |
| `skill_knockback_punch.json` | то же |
| `test_area_strike.json` | `entity`→`actor` (если есть; сейчас self) |
| `test_chain_lightning.json` | `entity`→`actor` |
| `test_target_area_strike.json` | hex — без изменений |
| `test_vamp_strike.json` | `entity`→`actor` |

## Out of plan (намеренно)

- Сохранение level в save/load — out of scope (level пока set'ится в JSON для тестов).
- Per-level icons / визуал — UI задача, не движок.
- AI выбор abilities внутри skill по `behaviour_tags` — `behaviour_tags` живут на Skill, не Ability (как и в 008).
- Скейлинг chain.radius / move_distance / `mood`/`name` от level — нет (не указано в формулах).

## Acceptance gate plan→implement

- [x] API-контракты приняты (Egor, текущий чат).
- [x] Уровень-формулы зафиксированы (Egor, текущий чат).
- [x] `apply_level` живёт внутри подкласса (Egor's clarify).
- [x] Hard rename без backcompat (spec AC-M3).
