# 006-actors-info-window — spec

**Owner:** Andrey
**Status:** in-progress

## Цель

Info-окно в правом верхнем углу Godmode: показывает выбранного актёра — HP, stats (speed / damage_bonus / max_hp), и **список его абилок с тултипами**. Stats редактируемые через SpinBox (sandbox-режим). Абилки — read-only пипки с hover-тултипом.

Параллельно: Actor получает `speed` и `damage_bonus` поля, которые влияют на механику. Move-range overlay подсвечивает достижимые гексы.

Пилларс «полная информация» (CLAUDE.md §1.5.1): игрок видит всё, что умеет каждый участник арены.

## Acceptance criteria

### Actor model
- `Actor` получает `@export var speed: int = 1` и `@export var damage_bonus: int = 0`.
- Дефолты сохраняют текущее поведение — не breaking.
- `player.tscn` переопределяет `speed = 2` (delta видна сразу).

### Механика speed
- `godmode_controller._request_move`: разрешённый таргет — гекс с `(path.size() - 1) <= player.speed`.
- `speed = 0` → лог `cannot move (speed=0)`, move не происходит.

### Механика damage_bonus
- `DamageEffect.apply`: итоговый урон = `max(0, amount + caster.damage_bonus)`.
- `Ability.predicted_damage_to`: та же формула. Комментарий `# KEEP IN SYNC`.

### Move-range overlay
- Все достижимые гексы выбранного актёра подсвечены полупрозрачно (ally — голубой, enemy — красный). Текущий гекс актёра — акцентный зелёный.
- Обновляется при смене selected, смене speed, `world_turn_ended`, спавне/удалении манекена.

### LMB-логика (новая)
```
if active_ability.can_apply(player, ctx):  cast → tick
elif target_actor != null:                  select(target_actor)
else:                                       deselect() → selected = player
```
ESC → selected = player.

### Info-окно (ActorInspector)
- `PanelContainer` anchor TR, видно всегда (selected = player по умолчанию).
- Содержимое (VBoxContainer сверху вниз):
  - `Label` actor_id + `Label` team (серый).
  - HP: `Label` «hp / max_hp».
  - Три строки `SpinBox`: max_hp [1–200], damage_bonus [0–50], speed [0–6].
  - **Секция «Abilities»**: горизонтальный ряд пипок (один квадратик на абилку).
    - Пипка = `Button` (disabled, focus_none) с текстом — первая заглавная буква id абилки.
    - При hover — `Tooltip` с полным id + описанием эффекта (kind + amount если damage, иначе kind).
    - Данные берутся из `actor.get_abilities()` — новый метод на Actor (возвращает `Array[StringName]` id'шников).
  - Подсказка `Label` «ESC = back to player» мелким шрифтом.
- SpinBox-изменения применяются немедленно, тик не вызывают.
- При смерти inspected-актёра → selected = player.

### Откуда берутся абилки актёра
- **Player**: из SlotBar (слоты 0–3, пропускаем пустые).
- **Enemies**: из `attack_ability_id` поля (одна абилка, если не пустая).
- `Actor.get_abilities() -> Array[StringName]` — возвращает массив id. Для player контроллер заполняет через `actor.set_abilities([...])` при seed/смене слота. Для manekin — через `set_abilities([attack_ability_id])` в `_ready` manekin_view.

## Out of scope
- Иконки/спрайты абилок.
- Cooldown-индикаторы.
- Read-only режим инспектора в реальной боевой сцене.
- Тултип за пределами Godmode.
