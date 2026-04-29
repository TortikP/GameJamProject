# 001-bootstrap — plan

## Подход

Никаких архитектурных решений вне того, что уже описано в HANDOFF. Этот спек — про сборку каркаса, не про дизайн.

- Структура файлов: HANDOFF.md §5
- Autoload-код: HANDOFF.md §6
- Конвенции (CLAUDE.md): HANDOFF.md §7 → копируется в `CLAUDE.md` в корне репы
- Branch model: HANDOFF.md §7 (внутри CLAUDE.md), §18

## Файлы, которые добавляются в репу этой фичей

### Корневые
- `CLAUDE.md` — конституция (из HANDOFF §7)
- `HANDOFF.md` — operational context (этот документ)
- `PROJECT_INSTRUCTIONS.md` — шаблон для claude.ai Project Settings (с placeholder'ом для токена, **без реального токена**)
- `README.md` — короткий, что и как запустить
- `project.godot` — Godot config с зарегистрированными autoload'ами
- `.gitignore` — был при init, оставляем

### Конфиги
- `config/game_speed.cfg` — стартовые тайминги из HANDOFF §6

### Autoload (порядок загрузки важен — Logger первый, остальные могут на него ссылаться)
- `scripts/infrastructure/logger.gd`
- `scripts/infrastructure/event_bus.gd`
- `scripts/infrastructure/game_speed.gd`
- `scripts/infrastructure/audio_director.gd` — stub

### Главная сцена
- `scripts/main.gd` — emit `EventBus.run_started` в `_ready()`
- `scenes/main.tscn` — Node + CanvasLayer + Label "Jam Project Ready", прицеплен `main.gd`, подключен сигнал `EventBus.run_started → _on_run_started`

### Структура папок (с .gitkeep в пустых)
- `data/{modifiers,enemies,spells,dialogues}/`
- `scenes/{arena,meta,ui}/`
- `scripts/core/{arena,spells,progression,dialogue}/`
- `scripts/{presentation,content}/`
- `assets/{sprites,tiles,portraits,icons,vfx,fonts}/`
- `assets/audio/{sfx,music,voice}/`

### Личные папки (с README)
- `andrey/`, `egor/`, `nikita/`, `sergey/`, `alexey/`, `stasyan/`

### Spec-папка
- `specs/001-bootstrap/{spec,plan,tasks}.md` (этот набор)

## Контракты, которые этой фичей фиксируются на всю команду

- **Все имена сигналов EventBus** (см. `scripts/infrastructure/event_bus.gd`). Их можно дополнять, но переименовывать существующие — только через PR с префиксом `breaking:` и согласованием с владельцем модуля-слушателя.
- **Все секции/ключи `config/game_speed.cfg`**. Переименование → breaking PR.
- **Сигнатуры `GameSpeed.wait/get_value`, `Logger.info/warn/error/debug`**. Это базовое API, на нём всё.
- **Ownership-таблица в CLAUDE.md** — кто что трогает.

## Точки интеграции

- `scenes/main.tscn` будет заменена на нормальное главное меню в фиче `006-meta-screens` или раньше. До тех пор — служит smoke-test'ом.
- `AudioDirector` — пока stub. Наполняется в полу-реальном времени Андреем по ходу джема.

## Риски и mitigation

- **Godot patch version mismatch** — у разных людей могут быть разные минорные версии 4.6.x. Mitigation: в README указано 4.6.2 как обязательная. Андрей пингует команду в общем чате.
- **Branch protection mis-configured** — Клод не может проверить через API (egress block), Андрей делает руками через GitHub UI и подтверждает в чате.
- **Autoload load order** — `GameSpeed.reload()` зовёт `Logger.error()` если конфиг не грузится. Поэтому Logger зарегистрирован первым в `[autoload]`. Если в будущем добавятся новые autoload'ы — порядок чекать.
