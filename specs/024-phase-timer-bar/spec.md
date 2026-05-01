# 024-phase-timer-bar — spec (RESERVED)

**Owner:** Andrey (driver), **Alexey** (roguelike-loop / wave-controller), **Stasyan** (баланс волн).
**Status:** Reserved — содержание заполняется утром, вне этой сессии.

## Цель (одно предложение)

Добавить в редактор таймлайн фаз боя: к моменту T_n спавнятся определённые враги/объекты в определённых местах, что превращает статичную карту в волновое сражение.

## Грубая модель (черновик на утро)

**В `LevelData` появляется массив `phases`:**
```
phases: Array[Dictionary] = [
  {
    "trigger": {"kind": "turn", "value": 0},     // или {"kind": "delay", "value": 5}
    "label": "Wave 1",
    "spawners": [{"coord": [..], "kind": "enemy", "ref": "manekin"}, ...],
    "objects":  [{"coord": [..], "object_id": "lava_pool"}, ...],
  },
  ...
]
```

Существующие `level.spawners` и `level.objects` — это «фаза 0» (initial state). Новые фазы накладываются сверху runtime'ом.

## Что нужно в редакторе

- Полоса-таймлайн снизу/сверху — горизонтальная, кликабельная по фазам.
- Кнопка «+ Phase» добавляет новую фазу с триггером после предыдущей.
- При выборе фазы все placement-операции в редакторе пишут в `level.phases[active].spawners/objects` вместо корневого `level.spawners/objects`.
- Визуально: на канве показываем суперпозицию (initial + selected phase = что игрок увидит после её триггера) с дифференциацией по цвету/прозрачности.

## Что нужно в рантайме

- `WaveController` (новая нода в боевой сцене) подписывается на `EventBus.world_turn_ended` или таймер, эмитит фазу когда trigger удовлетворён, инстанциирует через `LevelLoader._spawn_enemy` / `set_tile_object_id`.
- Это и есть upstream для будущего `005-roguelike-loop` — wave-encounters читают `LevelData.phases`.

## Open questions (большие, обсуждать утром)

- OQ-1: триггеры — только `turn` (хода прошло N) и `delay` (секунд прошло N), или также `event` (player вошёл в зону / убит конкретный враг / etc.)?
- OQ-2: можно ли фазой *удалять* объекты/спавнеры (например, лавалуж исчезает после wave 3)? Или фазы только additive?
- OQ-3: per-spawner overrides (HP, skills) — ввести вместе с phases или отдельной фичей? Зависит от 023.
- OQ-4: фазу можно отменить/пропустить через event («победа над боссом → wave 5 не спавнится»)?

## Зависимости

- 023 (editor UX) — base editor должен быть стабилен.
- Coordination с Alexey: WaveController либо его, либо Andrey'я; `005-roguelike-loop` будет потреблять.

## Размер

Большая. Потенциально 2 спеки: 024-phase-data-runtime (формат + WaveController), 024a-phase-editor-ui (таймлайн в редакторе). Решить утром.
