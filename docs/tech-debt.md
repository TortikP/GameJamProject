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

