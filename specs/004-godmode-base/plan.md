# 004-godmode-base — plan

См. `spec.md` (что/зачем) и `THEME_PLAN.md` §4 (контракт абилок). Здесь — как.

## 1. Архитектура и слои

```
scripts/core/
  turn/
    turn_manager.gd          # autoload. Счётчик ходов. EventBus-сигналы.
  actors/
    actor.gd                 # Node2D. hp, max_hp, take_damage(), died сигнал.
  abilities/
    ability_target.gd        # абстрактный класс: resolve(caster, ctx) -> Array[ActorRef]
    ability_effect.gd        # абстрактный класс: apply(caster, target)
    ability_modifier.gd      # абстрактный: before_apply / after_apply / after_cast
    ability.gd               # Resource: target, effect, modifiers[]. cast(caster, ctx).
    ability_database.gd      # autoload. Загружает data/abilities/*.json в Dictionary.
    targets/
      single_enemy_target.gd # принимает ctx.target_id (StringName), возвращает [actor]
    effects/
      damage_effect.gd       # apply(caster, t) → t.take_damage(amount)

scripts/presentation/godmode/
  godmode_controller.gd      # инпут, спавн, локальный реестр актёров
  slot_bar.gd                # 4 слота, выбор активного, эмит cast_requested
  turn_counter.gd            # лейбл, слушает TurnManager
  manekin_view.gd            # визуал манекена (Node2D + Polygon2D + Actor)

scenes/dev/
  godmode.tscn               # инстанс hex_grid.tscn + UI + GodmodeController

data/abilities/
  debug_punch.json           # пример: single_enemy × damage(5)
```

Зависимости (никаких циклов):
- `core/abilities/*` ничего не знает про сцены/UI. Использует EventBus + ActorRegistry (см. §3).
- `core/actors/actor.gd` — чистый Node2D с HP. Visual прибит к нему как Polygon2D (placeholder).
- `presentation/godmode/*` зависит от `core`, не наоборот.

## 2. TurnManager (autoload)

```gdscript
# scripts/core/turn/turn_manager.gd
extends Node

var _turn: int = 1

func current() -> int:
    return _turn

func advance() -> void:
    EventBus.player_turn_ended.emit(_turn)
    _turn += 1
    EventBus.world_turn_ended.emit(_turn)
```

`advance()` зовёт godmode_controller когда:
- HexGrid.actor_step_finished для player → +1
- ability_cast (любой кастер-игрок) → +1

Не делаем тик от каждого пройденного шага в `move_actor` (он может пройти несколько клеток за один клик — это **один** ход игрока). Тик = по завершении движения. См. §5.

## 3. ActorRegistry — где живёт

Не делаю autoload. Создаю как Node `$ActorRegistry` внутри godmode-сцены, доступ через ссылку из контроллера. Это упрощает teardown сцены: при выходе из godmode реестр уничтожается вместе с актёрами. Никакого глобального состояния между сценами.

API:
```gdscript
class_name ActorRegistry
extends Node

var _by_id: Dictionary = {} # StringName -> Actor

func register(actor: Actor) -> void
func unregister(id: StringName) -> void
func get_actor(id: StringName) -> Actor       # null если нет
func get_at(grid: HexGrid, coord: Vector2i) -> Actor  # nil-safe lookup
```

Контракт абилок получает ActorRegistry через `ctx`:
```gdscript
ctx = {
    "registry": registry,
    "grid": grid,
    "target_id": StringName,   # для single_*
    "target_coord": Vector2i,  # для zone_*
}
```

## 4. Actor

```gdscript
# scripts/core/actors/actor.gd
class_name Actor
extends Node2D

signal died(id: StringName)
signal damaged(id: StringName, amount: int, hp_left: int)

@export var actor_id: StringName = &""
@export var max_hp: int = 100

var hp: int

func _ready() -> void:
    hp = max_hp

func take_damage(amount: int) -> void:
    if hp <= 0:
        return
    hp = max(0, hp - amount)
    damaged.emit(actor_id, amount, hp)
    if hp == 0:
        died.emit(actor_id)
        EventBus.actor_died.emit(actor_id)
```

Player и Manekin — оба `Actor` с разной визуализацией. Player инстансится в godmode-сцене, манекены создаются динамически контроллером (preload + instantiate).

## 5. Ability контракт — буквально по THEME_PLAN §4

```gdscript
# scripts/core/abilities/ability.gd
class_name Ability
extends Resource

@export var id: StringName
@export var target: AbilityTarget
@export var effect: AbilityEffect
@export var modifiers: Array[AbilityModifier] = []

func cast(caster: Actor, ctx: Dictionary) -> void:
    var targets: Array = target.resolve(caster, ctx)
    if targets.is_empty():
        GameLogger.info("Ability", "%s: no targets" % id)
        return
    for m in modifiers: m.before_apply(caster, targets, ctx)
    for t in targets:
        effect.apply(caster, t, ctx)
        for m in modifiers: m.after_apply(caster, t, ctx)
    for m in modifiers: m.after_cast(caster, targets, ctx)
    EventBus.ability_cast.emit(caster.actor_id, id, targets.map(func(a): return a.actor_id))
```

Интерфейсы (абстрактные базы):

```gdscript
class_name AbilityTarget
extends Resource
func resolve(_caster: Actor, _ctx: Dictionary) -> Array: return []

class_name AbilityEffect
extends Resource
func apply(_caster: Actor, _target: Actor, _ctx: Dictionary) -> void: pass

class_name AbilityModifier
extends Resource
func before_apply(_caster, _targets, _ctx) -> void: pass
func after_apply(_caster, _target, _ctx) -> void: pass
func after_cast(_caster, _targets, _ctx) -> void: pass
```

Конкретные реализации:
```gdscript
# targets/single_enemy_target.gd
class_name SingleEnemyTarget extends AbilityTarget
func resolve(caster: Actor, ctx: Dictionary) -> Array:
    var registry: ActorRegistry = ctx.get("registry")
    var id: StringName = ctx.get("target_id", &"")
    var actor: Actor = registry.get_actor(id) if registry else null
    if actor == null or actor == caster: return []
    return [actor]

# effects/damage_effect.gd
class_name DamageEffect extends AbilityEffect
@export var amount: int = 1
func apply(_caster: Actor, target: Actor, _ctx: Dictionary) -> void:
    target.take_damage(amount)
```

## 6. JSON-формат абилки → Resource

```json
{
  "id": "debug_punch",
  "target": {"kind": "single_enemy"},
  "effect": {"kind": "damage", "amount": 5},
  "modifiers": []
}
```

`AbilityDatabase` парсит JSON и собирает `Ability` Resource через `_make_target/_make_effect/_make_modifier` switch на `kind`. Регистры:
```gdscript
const TARGET_KINDS := {
    "single_enemy": preload("res://scripts/core/abilities/targets/single_enemy_target.gd"),
}
const EFFECT_KINDS := {
    "damage": preload("res://scripts/core/abilities/effects/damage_effect.gd"),
}
const MODIFIER_KINDS := {} # пусто на этом PR
```

Добавить новый тип компонента = новый класс + строка в реестре. Без рефакторинга движка.

## 7. Slot bar и инпут

`SlotBar` (HBoxContainer):
- 4 `SlotButton` (TextureRect + Label "Q/W/E/R"), показывает иконку или name абилки.
- `set_slot(index: int, ability: Ability)` / `get_slot(index: int) -> Ability` / `set_active(index: int)`.
- Сигнал `slot_activated(index: int)` — для UI-подсветки.
- Каст триггерится контроллером, не самим SlotBar (UI ничего не знает про каст).

Инпут (godmode_controller._unhandled_input):
- `KEY_Q/W/E/R` или `KEY_1/2/3/4` (action `cast_slot_0..3`) → запросить каст. Цель = актёр под курсором (если есть). Если цели нет — лог `[INFO][Godmode] no target`, без тика.
- `MOUSE_BUTTON_RIGHT` pressed → `grid.move_actor(player_id, coord_under_mouse())`. По завершении — `TurnManager.advance()`.
- `MOUSE_BUTTON_LEFT` pressed → если есть активный слот И под курсором актёр-не-игрок → каст. Это альтернатива нажатию Q/W/E/R. (Удобство: выбрал ability клавишей, кликнул врага.)
- `KEY_F1` → `_spawn_manekin(coord_under_mouse())`. Не тикает мир.
- `KEY_F2` → `_clear_manekins()`. Не тикает мир.

Цель для single-target абилок резолвится так:
```gdscript
var coord := grid.coord_under_mouse()
var target_id := grid.get_actor_at(coord)
ctx = {"registry": registry, "grid": grid, "target_id": target_id, "target_coord": coord}
```

## 8. Манекен — спавн и удаление

`MANEKIN_SCENE` = preload PackedScene с Actor + Polygon2D (красный гекс).
```gdscript
func _spawn_manekin(coord: Vector2i) -> void:
    if not grid.is_walkable(coord) or grid.get_actor_at(coord) != &"":
        GameLogger.info("Godmode", "cannot spawn at %s" % str(coord))
        return
    var idx := _next_manekin_idx
    _next_manekin_idx += 1
    var id := StringName("dummy_%03d" % idx)
    var actor: Actor = MANEKIN_SCENE.instantiate()
    actor.actor_id = id
    actor.position = grid.tile_map_layer.map_to_local(coord)
    grid.get_node("Actors").add_child(actor)
    grid.place_actor(id, coord)
    actor.died.connect(_on_actor_died)
    registry.register(actor)
```

`_on_actor_died(id)`:
```gdscript
var actor := registry.get_actor(id)
if actor == null: return
grid.clear_actor(id)
registry.unregister(id)
actor.queue_free()
```

## 9. Turn counter UI

`TurnCounter extends Label`:
```gdscript
func _ready() -> void:
    EventBus.world_turn_ended.connect(_on_turn)
    text = "Turn: %d" % TurnManager.current()
func _on_turn(turn: int) -> void:
    text = "Turn: %d" % turn
```

Размещён в `godmode.tscn` как `CanvasLayer/HUD/TurnLabel` сверху-слева. Минимальный стиль на этом PR.

## 10. config/game_speed.cfg — что добавить

Текущий `[arena]` уже есть. Дополняю:
```
[godmode]
spawn_animation_duration=0.0   # без анимации спавна на этом PR
ability_cast_delay=0.05        # короткая пауза после каста перед follow-up tick
```

## 11. project.godot — что добавить

Новые input actions:
- `cast_slot_0` — Q или 1
- `cast_slot_1` — W или 2
- `cast_slot_2` — E или 3
- `cast_slot_3` — R или 4
- `godmode_spawn_dummy` — F1
- `godmode_clear` — F2

Префикс `godmode_*` — потому что это dev-only биндинги. `cast_slot_*` — общие, переиспользуются в реальной roguelike-сцене.

Конфликт с существующими `hex_move_top/top_left/...` (Q/W/E/A/S/D на step) — не разрешаю, потому что:
- `arena_demo` Егора использует свои `hex_move_*`.
- Godmode не использует `hex_move_*`, использует только RMB.
- Один и тот же ключ в двух разных action-ах — Godot обрабатывает оба, но в разных сценах слушают разные. Не ломаемся.

При выходе хех-демо в продакшен надо будет почистить — не на этом PR.

## 12. EventBus — какие сигналы добавить

```gdscript
# Turn loop
signal player_turn_ended(turn: int)
signal world_turn_ended(turn: int)

# Combat
signal ability_cast(caster_id: StringName, ability_id: StringName, target_ids: Array)
signal actor_died(id: StringName)
```

`spell_cast` (старый, legacy) не трогаю — пусть лежит. `ability_cast` — новый канон.

## 13. main.tscn — добавить кнопку Godmode

Рядом с Arena Demo кнопкой. Меняю `scripts/main.gd`:
```gdscript
const GODMODE_SCENE := "res://scenes/dev/godmode.tscn"
# ... в _ready() добавить кнопку аналогично Arena Demo, _on_godmode_pressed() → change_scene_to_file
```

## 14. Что НЕ делаю в этом PR (страховка от scope creep)

- Не трогаю `arena_demo_controller.gd` Егора.
- Не трогаю dialogue_*. Связь "godmode-каст триггерит реплику" — следующая фича.
- Не пишу UI конструктора абилок. JSON руками — норм для этого PR.
- Не пишу зональные/ray-таргеты, modifiers, эффекты помимо damage. Spec явно ограничивает.
- Не добавляю persistence (сохранение состояния godmode между сессиями). Каждый запуск с нуля.

## 15. Точки риска

- **Resource subclass instantiation из JSON**. Godot 4.6 при `.new()` на скрипт-Resource может не подцепить `@export` если не использовать `.tres`. Митигация: вручную создаём instance, вручную выставляем поля по dict — без сериализации в `.tres`. Если будет проблема — в `CLAUDE.md` traps добавлю строку.
- **HexGrid `_moving` lock** — блокирует следующие шаги во время async traversal. Если игрок сделает RMB-RMB подряд, второй проигнорируется. Это ОК на этом PR, но в roguelike нужен queue. Помечаю в TODO.
- **`EventBus.spell_cast` vs `ability_cast`** — не путать. На этом PR никто не слушает `spell_cast`, проверю.
- **Actor as Node2D** vs Resource. Выбрал Node2D потому что нужно position в сцене. Минусы: нельзя сериализовать как Resource для save. Плюсы: натурально с движком. Save game не в скоупе.
