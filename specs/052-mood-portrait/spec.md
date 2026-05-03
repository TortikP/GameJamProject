# 052 — Mood-driven heroine portrait in dialogue

**Owner:** Egor
**Status:** Ready for /implement
**Upstream:** 038-mood-counter (`MoodTracker`, `EventBus.player_mood_changed`)
**Type:** Feature (presentation only)

## Цель

Когда говорит главгероиня (`speaker == &"heroine"`) — показывать в `DialoguePanel` портрет, соответствующий её текущему dominant mood. Mood приходит из `MoodTracker.get_dominant()` и обновляется через `EventBus.player_mood_changed`.

Для прочих speaker'ов (narrator / rival / merchant) ничего не меняется.

## Маппинг mood → файл (тематический)

| dominant mood | портрет |
|---|---|
| `tranquility` | `assets/portraits/aspect_forest.png` |
| `burnout`     | `assets/portraits/aspect_fire.png` |
| `ascended`    | `assets/portraits/aspect_heaven.png` |
| `neutral`     | — нет mood-файла, fall through |
| `chimera`     | — нет mood-файла, fall through |

Маппинг — `const MOOD_PORTRAIT: Dictionary` локально в `dialogue_panel.gd`. Не выносим в JSON / `UiTheme` / `MoodTracker` — единственный consumer, KISS. Существующие `aspect_*.png` файлы Кати используем как есть, ничего не переименовываем.

## Priority chain (heroine speaker)

1. `line.portrait` — explicit per-line override. Выигрывает всегда. (В data сегодня не используется ни в одной реплике.)
2. `MOOD_PORTRAIT.get(_dominant_mood)` — если есть маппинг и файл существует.
3. `speaker_data.default_portrait` — текущий fallback (сегодня указывает на отсутствующий `heroine_neutral.png` → пропускается).
4. `_make_placeholder()` — `default_portrait.png` или сгенерированный quad.

Для не-heroine speaker'ов цепочка [1, 3, 4] — без изменений.

## Когда обновлять

Портрет резолвится в `show_line()` — на каждой реплике. Mood берётся из `_dominant_mood`, кешированного из `EventBus.player_mood_changed`. **Live-update портрета во время уже отрисованной реплики не делаем** — следующая реплика подхватит. Это упрощает state-machine и избавляет от мигающих смен портрета во время typewriter'а.

`_dominant_mood` инициализируется в `&"neutral"` (соответствует all-zero состоянию `MoodTracker`'а). На случай, если `MoodTracker` уже эмитнул что-то до connect'а (порядок autoload'ов) — в `_ready` под if-guard'ом синхронизируемся через `MoodTracker.get_dominant()`.

## Acceptance Criteria

- **AC-1.** speaker = `heroine`, dominant = `tranquility` → portrait = `aspect_forest.png`.
- **AC-2.** speaker = `heroine`, dominant = `burnout` → portrait = `aspect_fire.png`.
- **AC-3.** speaker = `heroine`, dominant = `ascended` → portrait = `aspect_heaven.png`.
- **AC-4.** speaker = `heroine`, dominant ∈ {`neutral`, `chimera`} → нет mood-файла → шаг 2 пропускается → портрет = `default_portrait.png` (через placeholder, поскольку `heroine_neutral.png` отсутствует).
- **AC-5.** speaker ∈ {`narrator`, `rival`, `merchant`} → цепочка идентична до-фичи; mood игнорируется.
- **AC-6.** У реплики задан `line.portrait` → он выигрывает у mood-маппинга (priority 1).
- **AC-7.** Mood-файл маппится, но физически отсутствует на диске → шаг 2 пропускается, идём дальше по цепочке.
- **AC-D1.** `MoodTracker` autoload отсутствует / EventBus не эмитнул → `_dominant_mood = &"neutral"`, шаг 2 для heroine не находит маппинг → цепочка работает как до фичи. No crash, no warn-spam.
- **AC-D2** (mid-dialogue mood change). RMB-замена скилла во время реплики — текущая реплика не перерисовывается (портрет фиксируется на `show_line()`). Следующая реплика подхватит новый mood.

## Out of scope

- HUD-портрет в `player_status_panel` — портрета в .tscn нет, добавление вне scope (отдельная задача, если попросят).
- Per-line `mood_portrait` override в JSON dialogues — пока не требуется. `line.portrait` уже даёт способ зашить конкретный файл.
- Анимация перехода между портретами при смене mood — нет.
- Файлы `aspect_neutral.png` / `aspect_chimera.png` от Кати — не запрашиваются. Если придут позже — добавятся в `MOOD_PORTRAIT` одной строкой каждый.
- Переименование/перегенерация существующих `aspect_*.png` — не трогаем.
