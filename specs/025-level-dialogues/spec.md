# 025-level-dialogues — spec (RESERVED)

**Owner:** Andrey (driver, integration), **Nikita** (контент диалогов), **Alexey** (engine — DialogueManager).
**Status:** Reserved — содержание заполняется позже, вне этой сессии.

## Цель (одно предложение)

В рамках уровней (боевая сцена) системно играют диалоги — на старте уровня, на ключевых событиях (волна, смерть врага-ключа, низкий HP, портал) и на специфических триггерах от карты, чтобы повествование жило поверх боя без хардкода в сценах.

## Грубая модель (черновик)

Существует engine `DialogueManager` (003) и контент-формат `data/dialogues/*.json`. Эта спека — про **триггеры** на уровне, а не про engine.

**Где живёт привязка триггеров:**
- Вариант A: в `LevelData` — массив `triggers: [{event, dialogue_id_or_request, conditions}]`. Карта-зависимая, пишется в редакторе уровней (расширение 020).
- Вариант B: глобальный `level_dialogues.json` — `{event_pattern: [dialogue_request, ...]}` с условиями `level_id`, `wave`, `actor_kind`. Не привязан к карте, легче переиспользовать.
- Скорее всего гибрид: per-level overrides + global default'ы.

**Какие события подписываем:**
- `EventBus.battle_started(level_id)` — intro.
- `EventBus.wave_started(wave_index)` (когда 024 закроется).
- `EventBus.actor_died(actor)` — фильтр по `actor.id` или тегам.
- `EventBus.actor_hp_threshold_crossed(actor, ratio)` — на «my hp < 30%» / boss low.
- `EventBus.portal_entered` / `level_completed` — outro.
- Custom hooks от 019-tile-object-resolver (наступил на алтарь → реплика).

## Что нужно в редакторе (если вариант A или гибрид)

- В `MapEditor` — отдельная панель «Triggers» (рядом с волнами 024). Добавить trigger: выбор события + dialogue_id (или request-event) + условия.
- Список текущих триггеров уровня — редактируется/удаляется как и спавнеры.

## Что нужно в рантайме

- Новый `LevelDialogueDirector` (autoload или нода в боевой сцене) — подписывается на EventBus, читает триггеры из `LevelData.triggers` + global pool, при матче зовёт `DialogueManager.request(event, ctx)`.
- Уважает scene atomicity (003): если уже играет — drop с warn (не интрузивный force, кроме intro/outro).
- Cooldown / once-per-wave / once-per-run флаги через тот же `played_set` `DialogueManager`.

## Open questions (на утро)

- OQ-1: per-level triggers vs global pool vs гибрид — выбрать архитектуру.
- OQ-2: интеграция с 024 phases — диалог как побочный эффект `phase.on_start` (поле в фазе) или отдельный канал триггеров?
- OQ-3: триггеры на действия игрока (cast specific spell, kill streak) — нужны для джема или out_of_scope?
- OQ-4: позиция диалогового панели — поверх боя (modal-like, пауза?) или сбоку (бой продолжается)? Влияет на pacing.
- OQ-5: в редакторе нужен preview (proigrat dialogue не выходя из редактора)? Или достаточно `scenes/dev/dialogue_preview.tscn`?
- OQ-6: контент — Никита пишет в каком объёме? Триггеров под каждую волну/смерть/портал — счёт идёт на десятки реплик. Cut-list.

## Зависимости

- 003 (DialogueManager engine) — must.
- 020 (map-editor) — если триггеры per-level, расширяем редактор.
- 024 (waves) — `wave_started` событие приходит оттуда.
- 019 (tile-object-resolver) — кастомные хуки от объектов.

## Размер

Средняя. Основной риск — объём контента (Никита) и интеграция с 024 (если phases не закрыты).
