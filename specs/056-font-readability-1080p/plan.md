# 056 — Plan: Font readability bump (1080p tuning)

Спек: [`spec.md`](./spec.md). Все Q-056-1..4 резолвлены.

## Что дальше (TL;DR)

Три точечные правки + tech-debt log:

1. `scripts/presentation/ui_theme.gd:145..209` — 11 шрифтовых констант на новые значения (см. таблицу ниже). Комментарий-блок `# 056:` добавлен.
2. 5 user-facing скриптов — миграция `add_theme_font_size_override(..., <число>)` → ссылка на `UiTheme.FS_*`.
3. `docs/tech-debt.md` — новая запись про 6 dev-scene хардкодов (опционально в этой же ветке отдельным `chore:` коммитом).

Остальное — manual smoke в Godot (T006–T010 в [`tasks.md`](./tasks.md)).

## Архитектурное обоснование

- **UiTheme — единый источник правды.** 11 констант управляют ~100 callsites через `apply_label_kind()` плюс 8 прямых ссылок `UiTheme.FS_*`. Бамп 11 чисел → бамп всего UI. Это и есть архитектурный смысл UiTheme: централизованный font scaling. Спек 047 уже использовал этот рычаг (FS_BODY 14 → 16, FS_HEADER 18 → 20, BAR_FONT_SIZE_OVERHEAD 18 → 22). Спек 056 делает то же самое, на ×1.5.
- **Pixellari + bitmap rendering.** `FONT_ANTIALIASING_NONE` стоит в UiTheme, шрифт рендерится как bitmap. Источник 16px — кратные 16 (`32, 48, 64`) идут pixel-perfect. Фрактальные размеры (`24, 30, 36, 22`) — менее crisp, но **уже использовались в 720p-версии** (`FS_NUM_LARGE=24`, `BAR_FONT_SIZE_OVERHEAD=22`, `WAVE_NUMBER_FONT_SIZE=18`). Команда исторически приняла, что не каждый размер кратен 16 — это guideline, не закон. Mixed-strategy сохраняет привычное компромиссное качество.
- **Mixed scaling vs strict ×1.5 / ×1.6.** Strict ×1.5: пропорции точные, но `FS_NUM_HUGE` становится 60 (не кратно 16, jaggy на крупных). Strict ×1.6 со снапом на 16: на больших размерах crispest, но `FS_BODY` становится 26 (не кратно 16, и сильнее искажает иерархию). Mixed (этот спек): большие размеры (`NUM_HUGE`, `DIALOGUE_TEXT`, `DISPLAY`, `DIALOGUE_NAME`, `BAR_OVERHEAD`) идут на ближайшее кратное 16 (`64, 64, 48, 72, 32`); средние (`BODY`, `SMALL`, `NUM_LARGE`) — строгий ×1.5 (`24, 22, 36`). Коэффициент де-факто 1.45..1.6, иерархия не плавает.
- **Хардкоды → UiTheme.** 5 user-facing мест с `font_size = N` уже сегодня дублируют то, что есть в `FS_*`. Миграция занимает по строке на место и закрывает CLAUDE.md правило (visibility doctrine: «No hardcoded `FONT_SIZE = 9` constants in scripts»). Без миграции эти места не подхватят будущих бампов и начнут «отставать» от остального UI после следующего resolution change.

## Структура изменений

### 1. `scripts/presentation/ui_theme.gd:145..209` — bump table

| Константа | Было (720p) | Стало (1080p) | Множитель | Кратное 16 | Заметка |
|---|---:|---:|---:|---|---|
| `FS_DISPLAY` | 32 | **48** | ×1.5 | ✓ | заголовки экранов |
| `FS_HEADER` | 20 | **30** | ×1.5 | – | секции, чуть мельче DISPLAY |
| `FS_BODY` | 16 | **24** | ×1.5 | – | основной текст |
| `FS_SMALL` | 14 | **22** | ×1.57 | – | подписи; round-to-even |
| `FS_NUM_LARGE` | 24 | **36** | ×1.5 | – | числа в HUD |
| `FS_NUM_SMALL` | 14 | **22** | ×1.57 | – | mirror `FS_SMALL` |
| `FS_NUM_HUGE` | 40 | **64** | ×1.6 | ✓ | crits, читаются с расстояния |
| `FS_DIALOGUE_NAME` | 48 | **72** | ×1.5 | – | имя спикера, ×3 от FS_BODY |
| `FS_DIALOGUE_TEXT` | 40 | **64** | ×1.6 | ✓ | реплика, ≈×2.7 от FS_BODY |
| `BAR_FONT_SIZE_OVERHEAD` | 22 | **32** | ×1.45 | ✓ | HP над юнитом, visibility-критично |
| `WAVE_NUMBER_FONT_SIZE` | 18 | **28** | ×1.55 | – | round-to-even, ≈`FS_SMALL+6` |

В тот же файл — комментарий-блок `# 056:` добавляется к существующему `# 047:` блоку (lines 137..144), кратко объясняющий mixed-×1.5 + ссылку на спек 056.

### 2. Хардкоды → UiTheme (5 user-facing мест)

| Файл:строка | Было | Стало | Логика |
|---|---|---|---|
| `main_menu.gd:98` | `80` | `UiTheme.FS_BODY * 5` | Старый комментарий в коде: «80 = FS_BODY × 5». При FS_BODY=24 → 120, ×1.5 от 80 точно. Параметризация сохраняет авторскую мысль. |
| `main_menu.gd:104` | `32` | `UiTheme.FS_DISPLAY` | Старый комментарий: «32 = FS_DISPLAY». При FS_DISPLAY=48 → 48, та же связь. |
| `map_editor_controller.gd:1470` | `18` | `UiTheme.FS_HEADER` | Был ≈ FS_HEADER−2; объединяем (FS_HEADER=30 после бампа). |
| `wave_timeline.gd:314` | `11` | `UiTheme.FS_SMALL` | Был < FS_SMALL=14 даже в 720p (accumulated debt). После бампа 22 — ×2 на этом одном label. Если визуально станет навязчиво — точечный downgrade в smoke. |
| `spawners_overlay.gd:44` | `48` | `UiTheme.FS_DIALOGUE_NAME` | Был = старое FS_DIALOGUE_NAME=48. Семантически — «крупный одиночный символ», совпадает с tier'ом имени спикера. → 72. |
| `spawners_overlay.gd:54` | `14` | `UiTheme.FS_SMALL` | Был = старое FS_SMALL=14. → 22. |

Комментарии в коде вокруг этих строк (особенно в `main_menu.gd:96..105` где есть подробное обоснование «80 = FS_BODY × 5, multiple of 16 so Pixellari stays crisp») — обновляются: убирается «multiple of 16», добавляется «после 056 = `FS_BODY × 5` остаётся пропорциональным относительно body, кратность 16 не сохраняется в этой версии — приемлемо для once-per-session screen».

### Что НЕ трогаем

- `BAR_WIDTH_OVERHEAD = 64.0` / `BAR_HEIGHT_OVERHEAD = 10.0` — размеры HP-бара. Если 32px digit не вмещается в 64×10 — финдинг F-056-3, точечный bump в той же ветке (или отдельный коммит).
- 6 хардкодов в `scenes/dev/*.tscn` — tech-debt entry, отдельный chore.
- Layout values (margins, panel widths, sidebar offsets) — out of scope (Q-056-3.B).
- Pixellari font file и AA settings — out of scope.
- `default_font_size` в `_load_default_font` (line 500/504 — `FS_BODY`) — это уже ссылка на константу, бампится автоматом.

## Risks & mitigations

- **R1.** Какой-то label в anchored UI overflow'ит по горизонтали (в первую очередь HP digit над юнитом если не вмещается в `BAR_WIDTH_OVERHEAD = 64`).
  Mitigation: T009 visual smoke. Если overflow — финдинг F-056-3 с конкретным labe'ом, точечный bump bar width в этой же ветке (вероятный фикс — `BAR_WIDTH_OVERHEAD: 64 → 80 или 96`).
- **R2.** `FS_DIALOGUE_TEXT = 64` (был 40) делает диалог визуально доминирующим — текст занимает заметную долю vertical canvas.
  Mitigation: dialogue_panel anchored снизу с фиксированным offset, label rescales вниз через `autowrap_mode` если высота переполняется. Если визуально неловко — точечный downgrade `FS_DIALOGUE_TEXT 64 → 56` в финиш-смоке. Не блокер AC.
- **R3.** Pixellari на `FS_NUM_LARGE=36` / `FS_HEADER=30` / `FS_SMALL=22` / `WAVE_NUMBER=28` — фрактальные размеры, может выглядеть jaggy на больших mob'ах.
  Mitigation: команда уже исторически приняла фрактальные размеры (см. предыдущие 22, 18, 24 в коде). Если конкретный label выглядит явно хуже остального — записать в `findings.md`, точечный snap на ближайшее кратное 16 в финиш-смоке.
- **R4.** `wave_timeline.gd:314` лейбл шёл с size `Vector2(28, 14)` (line 311) при font_size=11. После бампа до 22 текст не вмещается в 14px по высоте → обрезается.
  Mitigation: T002d при миграции — поднять `lbl.size = Vector2(28, 14)` до `Vector2(36, 24)` или подобрать в смоке. Tasks T002d покрывает это.

## Smoke plan

См. [`tasks.md`](./tasks.md) T006–T010.
