# 004-godmode-base — spec

**Owner:** Andrey
**Status:** in-progress

## Цель

Минимальная Godmode-песочница на гекс-арене: игрок ходит, спавнит манекены, кастует абилку из QWER-слота — манекен получает урон и умирает. Мир тикает на каждом действии игрока. Это первый рабочий артефакт композиционной системы абилок и turn-loop, на который дальше навешиваются модификаторы, расы, AI, диалоги.

См. `THEME_PLAN.md` §3 (Godmode-first) и §4 (Ability composition) — этот документ их не дублирует.

## Acceptance criteria

- Сцена `scenes/dev/godmode.tscn` запускается из `main.tscn` отдельной кнопкой (рядом с "Arena Demo").
- Игрок виден на гекс-арене; **RMB по проходимому гексу** — игрок идёт по пути (через `HexGrid.move_actor`).
- На каждый шаг игрока **и** на каждый каст — `TurnManager` инкрементирует счётчик и эмитит `player_turn_ended`, затем `world_turn_ended`. Лейбл `Turn: N` сверху обновляется.
- **F1** — спавнит манекена под курсором (если гекс свободен и проходим). **F2** — очищает арену от всех манекенов.
- **Manekin** — без AI, имеет `hp` (из JSON), визуально красный гекс-полигон. При `hp <= 0` — `died` сигнал, удаление из сцены и из `HexGrid`.
- **Slot bar** внизу: 4 слота `Q W E R`, в каждом сидит `Ability` (или пусто). На старте Godmode слот Q заполнен `debug_punch` из `data/abilities/debug_punch.json`.
- **ЛКМ по манекену** при не-пустом активном слоте → каст: ability-контракт исполняется, манекен получает урон.
- Активный слот выбирается нажатием Q/W/E/R (или цифрой 1/2/3/4 — оба варианта триггерят каст слота). Текущий выбор подсвечен в UI.
- **Контракт абилки** реализован ровно по §4 THEME_PLAN: `Target.resolve()` → `Modifier.before_apply()` × N → `Effect.apply()` × targets → `Modifier.after_apply()` × N × targets → `Modifier.after_cast()` × N. Порядок модификаторов в массиве = порядок исполнения.
- Composition хранится в JSON-формате: `{id, target: {kind, params}, effect: {kind, params}, modifiers: [...]}`. Минимум один target-kind (`single_enemy`) и один effect-kind (`damage`) реализованы. `Modifier` — интерфейс есть, реализаций пока нет (пустой массив в JSON).
- Все тайминги — через `GameSpeed.wait("battle", ...)` или `"arena"`. Хардкоженных `create_timer` нет.
- EventBus получает: `player_turn_ended(turn: int)`, `world_turn_ended(turn: int)`, `actor_died(id: StringName)`, `ability_cast(caster_id: StringName, ability_id: StringName, targets: Array)`. Спекифично — не пересекается с существующими `spell_cast` (legacy, можно будет ретировать позже).
- Демо-сценарий: запустил godmode → шагнул RMB на гекс (Turn: 1 → 2 в HUD) → F1 спавн манекена → ЛКМ по манекену → манекен -5 hp → ещё 4 каста → манекен мёртв, удалён, в логах `actor_died`.

## Out of scope (этот PR)

- Модификаторы как реализации (только интерфейс). Реализации `knockback`, `chain`, etc — следующая фича.
- Дополнительные target-kind (`zone_circle`, `zone_line`, `ray`, `splash`) — следующая фича.
- Дополнительные effect-kind (`heal`, `dot`, `terraform`, `summon`, `control`, `movement`) — следующая фича.
- AI врагов: манекены тупые, ничего не делают на `world_turn_ended`. Простой taunt-AI — следующая фича.
- UI конструктора абилок (выбор target/effect/modifiers). Пока абилки только из JSON.
- Swap-loadout 1/2/3/4 (свопать композицию в активный слот). Текущая реализация: 1/2/3/4 = алиасы Q/W/E/R на каст. **TODO для следующего PR:** 1/2/3/4 как отдельная панель из ≥4 заготовленных абилок, кликом подкладываемых в QWER.
- Расы и моральный компас.
- Диалоги/голоса в Godmode.
- Кулдауны, мана, лимиты на каст — по THEME_PLAN их в Godmode и не вводим.
- Анимации каста (полёт снаряда, hit-flash) — отдельная фича polish.
- Перенос Godmode-инфры (TurnManager, ActorRegistry, Ability) в реальную roguelike-сцену — следующая фича.

## Acceptance verification

Запуск `scenes/main.tscn`, кнопка "Godmode":
1. Открывается сцена с гекс-ареной 10×10, игроком в центре, лейблом `Turn: 1` сверху, slot bar внизу с одним заполненным слотом Q (`debug_punch`).
2. RMB по проходимому гексу → игрок идёт, на каждом шаге счётчик растёт.
3. F1 → манекен спавнится под курсором, виден как красный гекс. Если коорд занят/непроходим — лог `[INFO][Godmode] cannot spawn at ...`, ничего не происходит.
4. ЛКМ по манекену → лог `[INFO][Ability] debug_punch: dummy_001 -5hp`. Счётчик ходов растёт.
5. Повторяя 4, манекен умирает: `[INFO][Actor] dummy_001 died`, удаляется из сцены и из HexGrid.
6. F2 → все манекены удалены.
7. F5 hot-reload `game_speed.cfg` меняет тайминги.

## Зависимости

- 002-hex-grid (HexGrid API) — в staging.
- 001-bootstrap (autoloads, GameSpeed config, EventBus).
- EventBus получает 4 новых сигнала (additive, не breaking).
- TurnManager — новый autoload.
- AbilityDatabase — новый autoload.

## Что считается breaking

- Переименование `HexGrid.place_actor / move_actor / step_actor / get_actor_at / coord_under_mouse` — не делаю, использую as-is.
- Сигнатуры новых сигналов EventBus — добавляются, не меняются.
