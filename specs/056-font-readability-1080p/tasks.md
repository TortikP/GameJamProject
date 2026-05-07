# 056 — Tasks

Спек: [`spec.md`](./spec.md). Plan: [`plan.md`](./plan.md).

## Code (Claude в impl-команде)

- [ ] **T001.** `scripts/presentation/ui_theme.gd:145..209` — обновить 11 шрифтовых констант по таблице из [plan.md §Структура изменений.1](./plan.md):

  ```gdscript
  FS_DISPLAY    := 48   # было 32
  FS_HEADER     := 30   # было 20
  FS_BODY       := 24   # было 16
  FS_SMALL      := 22   # было 14
  FS_NUM_LARGE  := 36   # было 24
  FS_NUM_SMALL  := 22   # было 14
  FS_NUM_HUGE   := 64   # было 40
  FS_DIALOGUE_NAME := 72   # было 48
  FS_DIALOGUE_TEXT := 64   # было 40
  BAR_FONT_SIZE_OVERHEAD := 32   # было 22
  WAVE_NUMBER_FONT_SIZE  := 28   # было 18
  ```

  Сохранить порядок и имена. Добавить комментарий-блок `# 056:` рядом с существующим `# 047:` блоком (lines 137..144), кратко объясняющий mixed-×1.5 для 720p→1080p переезда. (AC1)

  Проверка после правки: `wc -l scripts/presentation/ui_theme.gd` должно остаться ~524..540 (увеличение только за счёт комментария).

- [ ] **T002.** Хардкоды → UiTheme. По одной правке на каждом callsite, без захвата соседних строк:

  - [ ] **T002a.** `scripts/presentation/main_menu.gd:98` — `80` → `UiTheme.FS_BODY * 5`. Обновить комментарий выше (lines 96-97): убрать «multiple of 16 so Pixellari stays crisp» (после 056 не выполняется), оставить «FS_BODY × 5 для иерархии». См. [plan.md §Структура изменений.2](./plan.md) для конкретного текста комментария.
  - [ ] **T002b.** `scripts/presentation/main_menu.gd:104` — `32` → `UiTheme.FS_DISPLAY`. Комментарий выше (lines 102-103): обновить «32 = FS_DISPLAY (pixel-perfect)» → «= FS_DISPLAY (бампится с UiTheme)».
  - [ ] **T002c.** `scripts/presentation/dev/map_editor_controller.gd:1470` — `18` → `UiTheme.FS_HEADER`.
  - [ ] **T002d.** `scripts/presentation/ui/wave_timeline.gd:314` — `11` → `UiTheme.FS_SMALL`. **Дополнительно:** строка 311 (`lbl.size = Vector2(28, 14)`) — поднять до `Vector2(36, 24)`, иначе текст 22px не вмещается по высоте (R4). Если визуально 36×24 «жмёт» соседние анкеры в timeline — записать в findings, подобрать в smoke.
  - [ ] **T002e.** `scripts/presentation/dev/spawners_overlay.gd:44` — `48` → `UiTheme.FS_DIALOGUE_NAME`.
  - [ ] **T002f.** `scripts/presentation/dev/spawners_overlay.gd:54` — `14` → `UiTheme.FS_SMALL`. (AC5)

- [ ] **T003.** Verification grep после T002. Из корня репы:

  ```bash
  grep -rnE 'add_theme_font_size_override\("(font_size|normal_font_size)", [0-9]+\)' scripts/presentation/
  ```

  Должно быть пусто. Если что-то осталось — добавить в T002. Допустимое исключение: callsite внутри `ui_theme.gd` сам по себе (например внутри `apply_label_kind`, использует переменную `fs`, не литерал — в выражение grep не матчится).

- [ ] **T004.** Tech-debt запись (опционально, в этой же ветке отдельным `chore:` коммитом). Если `docs/tech-debt.md` нет — создать с минимальной шапкой:

  ```markdown
  # Tech debt

  Список accepted compromises и debt'а вне текущих фич. Каждая запись имеет id `F-NNN-K` (привязка к спеку, который её surface'ил).

  Обновлять — когда трогаем фичу, родственную записи, и решаем чинить или нет.
  ```

  Добавить запись:

  > **F-056-1: dev-scene font_size hardcodes.** 6 мест в `scenes/dev/*.tscn`:
  > - `resolver_smoke.tscn:16` (14)
  > - `tile_objects_smoke.tscn:16` (14)
  > - `skill_offer_smoke.tscn:24` (22), `:49` (13)
  > - `dialogue_preview.tscn:21` (18)
  > - `godmode.tscn:112` (14)
  >
  > Не visible to users (smoke / dev-сцены). Миграция под `UiTheme.FS_*` отдельным `chore:` коммитом, когда появится повод трогать сцену. Не блокер.

- [ ] **T005.** Создать пустой `specs/056-font-readability-1080p/findings.md` с заголовком и шапкой:

  ```markdown
  # 056 — Findings

  Список observations с smoke-прохода. Каждая запись — `F-056-K`, краткое описание, severity (low/med/high/blocker), действие (fix in branch / next spec / accepted).

  Заполняется по результатам T006–T010 в [`tasks.md`](./tasks.md). Если smoke прошёл чисто — записать «список пуст, бамп чистый».
  ```

  Файл — input для решения «чиним точечно в этой ветке vs новый спек по реверстке».

## Smoke (Andrey, manual в Godot после impl)

- [ ] **T006 (AC2).** Запуск из main menu → "Начать забег". Прохождение до первого диалога:
  - top_hud_bar: HP digits, score, wave counter — читаются без leaning in;
  - hex tooltip над любым тайлом (если показывается на hover) — читается;
  - dialogue panel: имя спикера крупно (72px), текст реплики крупно (64px); panel anchored, не overlapping HUD; текст не обрезается по высоте панели (R2);
  - heroine шаг → transition shader → следующая комната — без визуальных артефактов;
  - **F11** → fullscreen 1920×1080: те же шрифты pixel-perfect (multiples of 16 в кратных), фрактальные slight jaggy (приемлемо).

- [ ] **T007 (AC3).** Map editor:
  - Открыть `scenes/dev/map_editor.tscn` через Main menu.
  - Создать новую волну (или открыть существующую с >1 wave). Timer label: 30px, читается на sidebar.
  - Wave timeline numbers (W1, W2, ...): 28px, видны на каждом анкоре. Размер `Vector2(36, 24)` после T002d не наезжает на соседние анкеры.
  - Положить spawner на хекс. Spawner overlay glyph (буква): 72px, читается с расстояния. Tag: 22px, читается.
  - Sidebar (`offset_right = -376`) — все кнопки и labels внутри читаются, без overflow по горизонтали. Если overflow — F-056-2 в `findings.md`.

- [ ] **T008 (AC4).** Main menu:
  - Title: 120px (`FS_BODY × 5`) — самое крупное, доминирует в кадре.
  - Subtitle: 48px (`FS_DISPLAY`).
  - Кнопки в кнопочной панели — стандартный `FS_BODY = 24`. Все три уровня иерархии чётко различимы.
  - Title не уезжает за горизонтальные края viewport на 1920×1080. На windowed 1600×900 (downscaled) тоже.

- [ ] **T009 (AC2 + R1).** HP digit над юнитом:
  - Godmode F1 → spawn маникена.
  - HP-цифра над спрайтом: 32px (`BAR_FONT_SIZE_OVERHEAD`).
  - Помещается ли число в `BAR_WIDTH_OVERHEAD = 64.0`? Тест: 99, 999, 9999 (если HP так высоко поднимается). Если 999 не вмещается — F-056-3 в `findings.md`, точечный бамп `BAR_WIDTH_OVERHEAD: 64 → 80 или 96` коммитом в этой же ветке.
  - Visible с дефолтного zoom без приближения камерой.

- [ ] **T010 (AC6).** Regression sanity:
  - Mob spawn (godmode F1): движутся, кастуют, дамаг считается, HP digit обновляется.
  - Wave end → upgrade screen открывается, тексты на FS_BODY=24 читаются, кнопки апгрейдов кликабельны.
  - Dialogue trigger в level → panel открывается, `_text_lbl` без обрезки по высоте (R2). После закрытия диалога — управление возвращается.
  - F5 reload `game_speed.cfg` → не падает, console clean.
  - Никаких новых runtime warn'ов в консоли по всему smoke-проходу.

## Acceptance gate

Все T001–T003 закоммичены. T004 — опционально (можно оставить на последний chore-коммит дня). T005 — обязательно (нужен файл-сборник для смока). T006–T010 пройдены без блокирующих регрессий. Findings из T007/T008/T009 (если есть) — либо точечно зафиксены в этой ветке (R1, R4, F-056-3), либо записаны в `findings.md` для следующего спека (F-056-2). Ветка готова к PR в staging.
