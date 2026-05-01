# 019-tile-object-resolver — spec

**Owner:** Andrey (integration / follow-up to 018).
**Coordination required:** Egor — 3 additive public methods on `hex_grid.gd` (read-only + one write for on_destroy spawn). Purely additive, no API rename.
**Status:** Implement (this session).

## Цель

018 задекларировал контракт tile objects и эмитит EventBus сигналы, но никто их не слушает — данные без поведения. 019 добавляет runtime resolver: Node, который подписывается на эти сигналы и реализует все тригтерные режимы.

## Что делает resolver

| Источник сигнала | Триггер | Что делает resolver |
|---|---|---|
| `EventBus.tile_entered` | actor шагнул на тайл | если `obj.applies_on_enter` → apply `behavior_effect_id` |
| `EventBus.player_turn_ended` | каждый ход | `applies_on_turn_end` для стоящих; aura для всех в радиусе; тик linger-стеков |
| `EventBus.tile_object_actor_exited` | actor покинул тайл с объектом | если `obj.linger_effect_id != ""` → push в linger-стек actor'а |
| `damage_object(coord, amount, attacker_id)` | вызывает ability/spell-система | decrement runtime HP, emit `tile_object_damaged`, on hp≤0 → destroy |

Деструкция: очищает tile, эмитит `tile_object_destroyed`, применяет `on_destroy_effect_id` (overlay на grid), спавнит `on_destroy_spawn_object_id` (новый объект на том же тайле).

## Acceptance criteria

- **AC-1:** `TileObjectResolver` — `extends Node`, сцено-локальный. Создаётся контроллером арены, инициализируется через `setup(grid, object_reg, effect_reg, actor_reg)`. НЕ autoload.
- **AC-2:** `applies_on_enter` — `tile_entered` → эффект на actor, если объект есть и флаг true.
- **AC-3:** `applies_on_turn_end` — в `player_turn_ended`: для каждого живого actor'а на тайле с объектом, у которого флаг true → эффект.
- **AC-4:** `aura_radius` — в `player_turn_ended`: для каждого тайла с aura-объектом использует `grid.reachable_within(coord, radius, [])` → эффект всем actor'ам в зоне.
- **AC-5:** Linger — `tile_object_actor_exited` → push `{effect_id, turns_left}` в `_linger_stack[actor_id]`. Каждый `player_turn_ended` тикать: apply + decrement, убрать когда 0.
- **AC-6:** `damage_object(coord, amount, attacker_id)` — lazy-init `_runtime_hp[coord]` из `obj.hp`, decrement, emit `tile_object_damaged`. `applies_on_attacked` → effect on attacker. HP≤0 → `_destroy_object`.
- **AC-7:** `_destroy_object` — очищает `_runtime_hp[coord]`, вызывает `grid.set_tile_object_id(coord, &"")`, эмитит `tile_object_destroyed`. Если `on_destroy_effect_id != ""` → `grid.add_overlay_effect`. Если `on_destroy_spawn_object_id != ""` → `grid.set_tile_object_id(coord, new_id)`.
- **AC-8:** `applies_to` filter из tile_effect dict — player/enemy/neutral; resolver проверяет `actor.team` перед применением.
- **AC-9:** `HexGrid` получает 3 новых метода: `get_tile_object_id(coord)`, `set_tile_object_id(coord, id)`, `get_all_tile_object_ids() -> Dictionary`. Чисто аддитивно — Egor review.
- **AC-10:** Никакой логики в `TileObject` (pure data), никаких изменений в Actor.

## Out of scope

- Wire-up `damage_object()` из ability/spell-системы — вызов есть, подключение к Sergey-коду отдельно.
- Presentation: VFX/SFX при destroy — resolver эмитит сигнал, presentation слушает.
- `applies_on_attacked` без caller — метод рабочий, вызывает Sergey's код позже.
- Тесты / smoke-сцена (smoke_018 уже есть, extend по желанию).
