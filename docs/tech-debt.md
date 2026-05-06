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
