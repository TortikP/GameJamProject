# 056 — Font readability bump (1080p tuning)

**Обсуждали:** Андрей (идея), мозг.
**Статус:** ready (Q-056-1..4 резолвлены, идём в plan + tasks).

## Что дальше

1. ✅ Спек одобрен Андреем, Q-056-1..4 резолвлены.
2. Plan + tasks (этот же набор коммитов).
3. Имплементация (отдельная команда).

## Resolved decisions

- **Q-056-1 → A.** Бампим все 11 шрифтовых констант UiTheme разом, не точечно. Иерархия (`display > header > body > small`; `num_huge >> num_large > num_small`) сохраняется пропорционально, типографика остаётся внутренне согласованной.
- **Q-056-2 → C, mixed scaling.** Базовый множитель ×1.5 (1280×720 → 1920×1080 по линии). На больших размерах, где ближайшее кратное 16 совпадает с ×1.5, снапим туда (`FS_DISPLAY 32 → 48`, `FS_DIALOGUE_NAME 48 → 72`, `BAR_FONT_SIZE_OVERHEAD 22 → 32`, `FS_NUM_HUGE 40 → 64`, `FS_DIALOGUE_TEXT 40 → 64` — последние два немного тянут на ×1.6 ради pixel-perfect Pixellari). На средних размерах (`FS_BODY`, `FS_SMALL`, `FS_NUM_LARGE`) держим строгий ×1.5: пропорциональность важнее crispness, и команда уже исторически принимала фрактальные размеры (`FS_NUM_LARGE=24`, `BAR_FONT_SIZE_OVERHEAD=22`, `WAVE_NUMBER_FONT_SIZE=18`).
- **Q-056-3 → B.** Sidebar layouts, FileDialog'и (F-054-1) и любая реверстка панелей — out of scope. Этот спек — только размеры шрифтов. Если после бампа какой-то sidebar overflow'ит / режет текст — собираем в `findings.md`, отдельный спек.
- **Q-056-4 → A.** Хардкоды `font_size = N` в скриптах мигрируем под существующие `FS_*` константы. Никаких новых констант (`FS_TITLE`, `FS_TIMER`) не плодим — текущих 11 хватает на все user-facing случаи. Title в main_menu остаётся параметризованным как `FS_BODY × 5` (так и был задуман — комментарий в коде это явно фиксирует).

## Проблема

После переезда на 1920×1080 (spec 054) шрифты стали визуально мельче ~×1.5. UiTheme константы остались tuned под 1280×720 — это было сознательное out-of-scope решение спека 054 («текст станет мельче, приемлемо; если конкретный label станет нечитаем — точечный PR через UiTheme»). Спек 054 даже предусмотрел задачу T008/AC6 в smoke: «текст где-то нечитаем (UiTheme constant остался 720p-tuned) → какой label». Реальный smoke вернулся не с одним label'ом, а с системной читаемостью UI body-text.

Архитектурно правка простая: bump 11 констант в `scripts/presentation/ui_theme.gd`. Все scene'ы и скрипты, которые ходят через `UiTheme.FS_*` (~8 прямых ссылок) и `UiTheme.apply_label_kind()` (~100 callsites), подхватят новые значения без правки. Плюс 5 user-facing хардкодов мигрируют под FS_* в том же PR.

## Цель

1. **Поднять 11 шрифтовых констант UiTheme** на ×1.5 mixed (см. таблицу в plan.md). Покрывает `FS_DISPLAY/HEADER/BODY/SMALL`, `FS_NUM_*`, `FS_DIALOGUE_*`, `BAR_FONT_SIZE_OVERHEAD`, `WAVE_NUMBER_FONT_SIZE`.
2. **Мигрировать 5 user-facing хардкодов** (`main_menu.gd:98/104`, `map_editor_controller.gd:1470`, `wave_timeline.gd:314`, `spawners_overlay.gd:44/54`) под существующие `FS_*` константы.
3. **Зафиксировать tech-debt** про 6 хардкодов в `scenes/dev/*.tscn` (smoke-сцены, юзер не видит) — миграция позже отдельным `chore:` коммитом.
4. **Не реверстать UI panels** под новые шрифты. Если после бампа какой-то sidebar overflow'ит / режет текст — собираем в `findings.md`, отдельный спек.

## Acceptance criteria

- **AC1.** `scripts/presentation/ui_theme.gd:145..209` — 11 шрифтовых констант обновлены по таблице из plan.md §Структура изменений.1. Имена и порядок не меняются. Добавлен комментарий-блок `# 056:` рядом с существующим `# 047:` блоком, кратко объясняющий mixed-×1.5 для 720p→1080p переезда.
- **AC2.** Запуск story_campaign, прохождение до первого диалога: top_hud_bar (HP, score, wave) читается без leaning in; HP digit над юнитом виден на дефолтном zoom; dialogue panel — name 72px, text 64px, panel anchored, без обрезания и без overlap'а HUD.
- **AC3.** Map editor: timer label (30px), wave timeline numbers (28px), spawner overlay glyph (72px) и tag (22px) — все читаются на 1080p canvas без увеличения масштаба.
- **AC4.** Main menu: title (`FS_BODY × 5 = 120px`), subtitle (`FS_DISPLAY = 48px`), кнопки (`FS_BODY = 24px`) — три уровня иерархии чётко различимы.
- **AC5.** Хардкоды `font_size = <число>` в `main_menu.gd`, `map_editor_controller.gd`, `wave_timeline.gd`, `spawners_overlay.gd` — заменены на ссылки `UiTheme.FS_*`. Verification: `grep -rnE 'add_theme_font_size_override\("(font_size|normal_font_size)", [0-9]+\)' scripts/presentation/` возвращает пусто (или только legacy-locations, явно зафиксенные в Findings).
- **AC6.** Никаких новых runtime warn'ов в консоли. Никаких регрессий core gameplay (mob spawn / wave end / dialogue trigger / F5 reload `game_speed.cfg`).

## Out of scope

- **Реверстка sidebar'ов** под новые шрифты (например `offset_right = -376` в map_editor sidebar). Если text overflow'ит — finding в `findings.md`, отдельный спек.
- **FileDialog sizes 720×480** (F-054-1 — `level_meta_panel.gd:117`, `main_menu.tscn:96/103`). Не readable issue, а layout — точечный коммит вне этого спека.
- **Settings menu для пользовательского font scale** — задача под Steam launch (Mark), не сюда.
- **Большой [spec-M] «Читаемость интерфейса»** из `planning/plan.md` — типографика + контраст + иерархия, зависит от UX-болей с плейтестов, шире чем просто бамп размеров. Этот спек его не отменяет, а закрывает «нечитаемо» как срочный пункт.
- **Хардкоды в `scenes/dev/*.tscn`** (resolver_smoke, tile_objects_smoke, skill_offer_smoke, dialogue_preview, godmode) — smoke-сцены, юзер не видит. Запись в `docs/tech-debt.md` отдельной задачей.
- **Pixellari font file и AA settings** — не трогаем. AA/hinting/subpixel остаются OFF (bitmap rendering).

## Findings (для других)

- **F-056-1** (Andrey/Stasyan): 6 хардкодов `theme_override_font_sizes/font_size = N` в `scenes/dev/*.tscn` (`resolver_smoke.tscn:16`, `tile_objects_smoke.tscn:16`, `skill_offer_smoke.tscn:24/49`, `dialogue_preview.tscn:21`, `godmode.tscn:112`). Не visible to users (smoke / dev-сцены). Tech-debt entry в `docs/tech-debt.md` — мигрируется под `UiTheme.FS_*` отдельным `chore:` коммитом, когда будет повод трогать сцену.
- **F-056-2** (Andrey): после бампа возможен overflow в sidebar'ах / FileDialog'ах / любых Control с фиксированной шириной, считавшейся под старые размеры шрифта. Findings собираются в `specs/056-font-readability-1080p/findings.md` по результатам smoke (T007/T008/T009).
- **F-056-3** (Egor): `BAR_WIDTH_OVERHEAD = 64.0` / `BAR_HEIGHT_OVERHEAD = 10.0` остаются неизменными, тогда как `BAR_FONT_SIZE_OVERHEAD` 22 → 32. Если 32-px digit `999` не помещается в 64×10 бар — потребуется бамп размеров бара. Surface при smoke T009. Точечный фикс в этой же ветке, если поймаем; иначе finding в `findings.md`.
