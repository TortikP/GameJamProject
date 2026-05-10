# Tech debt

Список accepted compromises и debt'а вне текущих фич. Каждая запись имеет id `F-NNN-K` (привязка к спеку, который её surface'ил).

Обновлять — когда трогаем фичу, родственную записи, и решаем чинить или нет. Нет полиции — если запись отстала, отстала; главное чтобы она была честной когда обновляется.

---

## F-056-1 — dev-scene `font_size` hardcodes

**Surface'ил:** spec 056. **Severity:** low. **Не visible to users.**

6 мест в `scenes/dev/*.tscn` с прямым `theme_override_font_sizes/font_size = N`, не через `UiTheme.FS_*`:

| Файл | Строка | Значение | Под какую FS_* (после 056) |
|---|---:|---:|---|
| `scenes/dev/resolver_smoke.tscn` | 16 | 14 | `FS_SMALL` (=22) |
| `scenes/dev/tile_objects_smoke.tscn` | 16 | 14 | `FS_SMALL` (=22) |
| `scenes/dev/skill_offer_smoke.tscn` | 24 | 22 | `FS_SMALL` (=22) |
| `scenes/dev/skill_offer_smoke.tscn` | 49 | 13 | `FS_SMALL` (=22) |
| `scenes/dev/dialogue_preview.tscn` | 21 | 18 | `FS_HEADER` (=30) или `WAVE_NUMBER_FONT_SIZE` (=28) — на глаз |
| `scenes/dev/godmode.tscn` | 112 | 14 | `FS_SMALL` (=22) |

**План:** мигрировать под `UiTheme.FS_*` отдельным `chore:` коммитом, когда появится повод трогать сцену (например при открытии под текущую задачу). Не блокер — это smoke-сцены, юзер их не видит.

**Замечание по `.tscn` синтаксису:** в сценах нельзя сослаться на константу из скрипта напрямую. Миграция — либо через `Theme` resource (один общий `default_theme.tres`, на который ссылаются эти сцены), либо переписать setup из кода в `_ready()` сцены. Первый путь чище, второй — точечный. Решать в момент миграции.

---

## F-061-2 — LevelMetaPanel resize не работает

**Surface'ил:** spec 061 (extended dev). **Severity:** low. **User-visible:** да, но edge case — большинство пользователей не пытается ресайзить эту панель.

При наведении курсора на края/углы LevelMetaPanel курсор не меняется на стрелочки ресайза. У всех остальных панелей (LayersPanel, WaveSettings, WavePicker) на той же `BasePanel`-инфраструктуре — работает.

**Что проверено:**

- `resizable=true`, `is_resizable()=true`, `is_locked()=false` — идентично с layers (диагностический print показал)
- `ResizeFrame` присутствует, `visible=true`
- `_ResizeHandler` создан и добавлен в дерево
- Замок UI открыт визуально и логически
- Замена раздельной сцены `level_meta_panel.tscn` (как у других панелей) вместо script-swap'а в `level_editor.tscn` — не помогло
- Перенос `_file_dialog` с panel root в body — не помогло

**Гипотезы (непроверенные):**

- что-то в `_build_body()` создаёт Control который перекрывает hit-zones handles. FileDialog (Window) — самый подозрительный, но не подтверждено
- panel inner content (LineEdit + кнопки) MOUSE_FILTER_STOP не пропускает hover дальше до ResizeFrame — но это не должно мешать handles вне body

**План:** Не блокер для merge'а 061. Открыть отдельный фикс когда кто-то полезет в `panel_*_handler` инфраструктуру — там точечно сравнить путь mouse-cascade meta vs layers через подключение `_input` ловушки в handler'е.

---

## F-061-3 — 10 устаревших ui_* ключей без локализации

**Surface'ил:** `tests/check_localization_keys.py` при бутстрапе (061). **Severity:** low. **User-visible:** да, но fallback-строки в коде покрывают (рендерится английский по умолчанию).

10 ключей `ui_*` используются в коде (`Localization.t(...)` или `&"ui_..."`) но отсутствуют либо пусты в `data/localization/{en,ru}.json`. Все — до 061; таких регрессий 061 не вносит (две, которые внёс — `ui_wave_panel_skill_offer{,_preview}` — починены в этой ветке).

**Список и предполагаемое происхождение:**

| Key | en | ru | Owner-spec |
|---|---|---|---|
| `ui_cancel` | ❌ | ❌ | generic, 009-ui-kit area |
| `ui_panel` | ❌ | ❌ | 055-ui-panels |
| `ui_toast_requested` | ❌ | ❌ | 009-ui-kit |
| `ui_campaign_defeat_body_text` | ✅ | ❌ | campaign system |
| `ui_campaign_defeat_menu_button_text` | ✅ | ❌ | campaign system |
| `ui_campaign_defeat_title_text` | ✅ | ❌ | campaign system |
| `ui_consequence_move` | ✅ | ❌ | consequence system |
| `ui_skill_offer_smoke_status_label_text` | ✅ | ❌ | dev/smoke (skill_offer_smoke_controller.gd) |
| `ui_skill_offer_smoke_title_text` | ✅ | ❌ | dev/smoke |
| `ui_top_hud_bar_help_button_tooltip_text` | ✅ | ❌ | HUD |

Перечислены в `tests/localization_baseline.txt` — тест зелёный с baseline'ом, ловит только новые регрессии.

**План:** Cleanup-чур (1 PR, ~30 минут): добавить недостающие переводы, удалить ключи из baseline'а. Не блокирует 061 merge. Когда сделаем — `tests/check_localization_keys.py` сам напечатает stale baseline entries как hint.
---

## F-061-4 — office_intro.json: collision player+object на одной клетке

**Surface'ил:** `tests/test_061_migration.gd` при бутстрапе (061). **Severity:** low. **User-visible:** нет в шиппинге (карта используется как intro-сцена).

`office_intro.json` имеет на тайле `(3, 2)` одновременно `object_on_chair` и `player` spawner. Валидатор `LevelData.validate()` ловит как `tile already occupied`, но судя по имени объекта и сцене — задумывалось «игрок сидит на стуле в офисном интро», т.е. это намеренный co-occupation, а не баг данных.

**Что нужно решить (cleanup-чур):**

- Если поведение в игре ОК — релаксировать validate: разрешить `kind: "player"` сосуществовать с object на той же клетке, или ввести явный флаг `allow_object_underfoot` на спавнере.
- Если поведение в игре ломается (например, чёрный квадрат под игроком) — переписать карту: object отдельно, player отдельно.

В тестах файл занесён в `tests/maps_validate_baseline.txt` — миграция и roundtrip всё равно проверяются, но `validate()` пропускается. После решения — убрать строку из baseline'а.
---

## F-061-5 — три dev-фикстуры с turns_to_next>0 на последней волне

**Surface'ил:** `tests/test_061_migration.gd` (061). **Severity:** trivial. **User-visible:** нет (все три — dev fixtures).

Три файла в `data/maps/` имеют последнюю волну с `turns_to_next != 0`, валидатор требует `== 0` (ttn=0 = «финальная волна, ничего не ждём после»):

- `sample_dialogues.json` — fixture для spec 003 dialogue-системы
- `sample_music_test.json` — fixture для music_director'а
- `sample_preset_test.json` — fixture для preset-системы

Все три — одно-волновые/двух-волновые тестовые карты, не игровой контент.

**Варианты cleanup'а:**

1. **Быстрый (1 минута):** открыть каждый в редакторе → последнюю волну → ttn=0 → save. После — убрать строки из `tests/maps_validate_baseline.txt`.
2. **Архитектурный:** релакс валидатора — `last_wave_ttn_must_be_zero` warn, не error. Аргумент: dev-фикстуры с одной волной могут иметь ttn>0 как «не достигнуто», а полноценные уровни всё равно проверяются другими invariants. Решение по запросу tech-designer'а (Stasyan).
---

## F-061-6 — pas-058 R6 пересмотрен: lock не блокирует tab switching

**Surface'ил:** smoke-проверка 061 в редакторе (Andrey). **Severity:** medium UX. **User-visible:** да.

Спека 058 (`plan.md:337`) задокументировала R6 как: «если panel locked, ни drag, ни click-переключение табов не работает», и тут же пометила решение как «surface при имплементации, AC из spec не проверяет locked state — finding на будущее или smoke ad-hoc».

Smoke 061 surface'ил это: на залоченной WaveSettings-панели нельзя переключать табы — это контр-интуитивно. Lock в UX-смысле = «не двигай структурно» (drag/resize/detach), но переключение таба — это view-state, не редактирование data, и должно оставаться доступным независимо от lock'а.

**Что сделано:** Перенёс `is_locked()` check из `_on_tab_button_gui_input` (press handler) в `_detach_tab_active_drag` (drag handler). Click-switch теперь работает на залоченной панели; detach (drag-отрыв таба) по-прежнему блокируется — структурное изменение остаётся под lock'ом. Collapsed-проверка осталась в press handler (collapsed = body скрыт, switch'ить не во что).

**Owner spec'а 058** может откатить если решит что оригинальный intent был правильным — прецедента в реальном UX не было, R6 явно был open question.
