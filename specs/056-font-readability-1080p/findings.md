# 056 — Findings

Список observations со smoke-прохода. Каждая запись — `F-056-K`, краткое описание, severity (low / med / high / blocker), действие (fix in branch / next spec / accepted).

Заполняется по результатам T006–T010 в [`tasks.md`](./tasks.md). Если smoke прошёл чисто — записать «список пуст, бамп чистый» и удалить файл (или оставить как marker).

---

## Pre-populated (заранее ожидаемые риски, surface'ятся в smoke)

### F-056-1 — `scenes/dev/*.tscn` font_size hardcodes — `low`

6 мест в smoke / dev сценах. Не visible to users. Перенесено в `docs/tech-debt.md`. **Status:** logged, deferred.

### F-056-2 — `(заглушка)` sidebar / panel overflow после бампа — `?`

Surface'ить в T007/T008 если есть. Конкретный sidebar или panel, что именно overflow'ит, при каком разрешении (1600×900 windowed vs 1920×1080 fullscreen).

### F-056-3 — `(заглушка)` HP digit overflow в `BAR_WIDTH_OVERHEAD = 64` при `BAR_FONT_SIZE_OVERHEAD = 32` — `?`

Surface'ить в T009. Конкретное HP-значение, при котором не вмещается. Вероятный фикс: `BAR_WIDTH_OVERHEAD: 64.0 → 80.0` или `96.0`. Точечный коммит в этой ветке.

### F-056-4 — `(заглушка)` `FS_DIALOGUE_TEXT = 64` визуально доминирует — `?`

Surface'ить в T006 если диалог занимает слишком много vertical canvas. Вероятный фикс: `FS_DIALOGUE_TEXT: 64 → 56`. Точечный коммит в этой ветке.

---

## New findings from smoke

_(заполняется по ходу T006–T010)_
