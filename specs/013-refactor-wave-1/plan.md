# 013-refactor-wave-1 — plan

## API changes

### EventBus (`scripts/infrastructure/event_bus.gd`)

Добавить в раздел Combat (после `actor_died`):

```gdscript
# Combat feedback (013 — emits driven by Actor.take_damage / Actor.heal)
signal damage_dealt(target_id: StringName, amount: int, world_pos: Vector2)
signal heal_done(target_id: StringName, amount: int, world_pos: Vector2)
```

Без `breaking:` префикса в коммите — это additive, не ломает контракт. Ничего не переименовывается, listener'ы (floating_number_layer, combat_log) уже ждут эти имена через `has_signal()` lazy-bind.

### Actor (`scripts/core/actors/actor.gd`)

- В `take_damage(amount)` после `damaged.emit(...)` (line 73) добавить:
  ```gdscript
  EventBus.damage_dealt.emit(actor_id, amount, global_position)
  ```
- В `heal(amount)` после `damaged.emit(actor_id, -healed, hp)` (line 92) добавить:
  ```gdscript
  EventBus.heal_done.emit(actor_id, healed, global_position)
  ```
  `healed` (positive) — то, что реально восстановилось после `mini(max_hp, ...)` clamp.

`damaged.emit(...)` НЕ удаляется и НЕ меняется — legacy сигнал, на нём висят HealthBar и intent_arrow. Это два параллельных контракта по разной семантике (raw HP delta vs UI feedback), документировать в комментарии у emit'а.

### FloatingNumberLayer (`scripts/presentation/floating_number_layer.gd`)

- Сигнатура `_on_damage_dealt(target_id, amount)` → `_on_damage_dealt(target_id, amount, world_pos: Vector2)`. То же для `_on_heal_done`.
- Тело: `spawn(to_local(world_pos), amount, &"damage")`. Параметр `target_id` остаётся для `_throttle()`.
- **Удалить** `_resolve_actor_pos()` (lines 61-73) — больше не нужен, F-006 закрыт.
- Обновить блок-комментарий в шапке (строки 7-10) — убрать «Until those exist, callers can spawn() directly. We connect lazily — only if the signal exists on EventBus at _ready time.» → «EventBus signals damage_dealt/heal_done существуют с 013, lazy-bind через has_signal() сохранён для test scenes без EventBus.»

### CombatLog (`scripts/presentation/combat_log.gd`)

- `_on_damage_dealt(target_id, amount)` → `_on_damage_dealt(target_id, amount, _world_pos: Vector2)`. Параметр игнорируется, имя с подчёркиванием подавляет unused warning.
- То же для `_on_heal_done`.
- `status_applied` lazy-bind не трогать — out of scope (AC-5).
- Шапочный комментарий (lines 5-6): уточнить «damage_dealt/heal_done — 013, status_applied — TBD».

### Godmode controller (`scripts/presentation/godmode/godmode_controller.gd`)

- Удалён F8 keybind block в `_unhandled_input` (раньше — F6 → перенесён на F8 → теперь снят полностью).
- Удалена функция `_debug_cast_test_skill()` (~30 строк, единственный caller был F-хоткей). Заменена коротким комментарием-маркером, что smoke-test теперь делается RMB-assign'ом скилла в slot bar.
- Startup log line чистый — без F6/F8.

## Что НЕ трогается

- Actor.damaged signal (legacy, used by HealthBar/intent_arrow).
- Skill / Ability.cast — F-014 (P2/014).
- floating_number.gd — `world_pos` параметр в `setup()` остаётся как есть, спавн идёт через layer.
- ActorRegistry — больше не нужен для resolve_pos, но узел остаётся (используется godmode и пр.).

## Проверка вручную (Egor, ~2 минуты в Godot 4.6.2)

1. Открыть `scenes/dev/godmode.tscn`, F5.
2. F6 — должен переключиться CRT. В консоли: `[CrtPostFx] toggled OFF`. Снова F6 — `ON`.
3. ~~F8 — каст test_vamp_strike~~ — снято в follow-up: smoke-test через RMB-assign `test_vamp_strike` в QWER slot.
4. F1 — спавн manekin. ЛКМ + Q (slot 0) — каст skill_debug_punch. Над manekin должно появиться красное `−N`. В лог CombatLog (L) добавилась строка `T... ? hits manekin_1 -N`.
5. Если manekin спавнит у player — каст skill_debug_heal на себя (?). Если нет хил-скилла в slot — пропустить heal проверку, AC-2/3 для heal накроется тестами 014a.

## Risk

- **Heal путь** не очевидно покрывается debug-skill'ами в текущем slot bar. Если skill_debug_heal не сидит ни в одном slot, эмит произойдёт но визуально проверить нельзя в godmode без тестового хила. Acceptable risk: код-путь идентичен damage'у, тесты 007 покрывают heal logic.
- Новый `EventBus.damage_dealt.emit` в `Actor.take_damage` — vector произвольное число подписчиков. Сейчас 2 (layer + log). Cost — два signal call'а на каждый удар. На 100 ударах в секунду — пренебрежимо.
