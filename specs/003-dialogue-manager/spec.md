# 003-dialogue-manager — spec

**Owner:** Andrey
**Status:** in progress

## Цель

В игре можно вызывать диалоги: имя говорящего, портрет, текст с typewriter, опционально иллюстрация, опционально голос (через `AudioDirector`). Система сама выбирает подходящую реплику под событие, не «сыграть-конкретный-id». Никита пишет контент в JSON без программистов после того, как этот спек закрыт.

Референс — Hades / Supergiant «Codex»-system (Greg Kasavin, GDC 2020): trigger + priority + used-tracking. Берём только эти три идеи. Граф-редактора и многоуровневых веток не делаем.

## Acceptance criteria

### Engine

- Два autoload в `project.godot` в порядке: `… → DialogueDB → DialogueManager`.
- `DialogueDB._ready()` сканит `data/dialogues/*.json` (кроме файлов с префиксом `_`), парсит, кладёт по id. Битый файл → `GameLogger.warn`, не краш.
- `DialogueDB` грузит `data/dialogues/_speakers.json` — справочник speaker → display_name + default_portrait + default_audio_layer.
- `DialogueManager.play(id: StringName, force: bool = false) -> bool` — играет указанную реплику. Если id отсутствует в DB → false + warn. Если **уже играет** и `force=false` → drop + warn, возврат false. Если `force=true` → enqueue, возврат true.
- `DialogueManager.request(event: StringName, context: Dictionary = {}, force: bool = false) -> StringName` — селектор. Если играет и не force → drop + warn, возврат `&""`. Если force → селектор резолвит id **в момент вызова** (не в момент dequeue), enqueue id, возврат id.
- Селекция: filter by tag → filter by conditions → drop played (once_per_run / once_per_session) → sort by priority desc → pick highest; при равенстве — невиденная, иначе random из них.
- Очередь FIFO. Поп очереди происходит только при **полном завершении сцены** (см. Scene atomicity ниже), не при завершении текущей реплики.

### Scene atomicity (правило)

«Сцена» — всё, что достижимо из стартовой реплики через `next` и `choices[*].next`. Сцена проигрывается **атомарно**: внешние `play`/`request` ждут конца **всей** сцены (включая выбор пользователя и его follow-up), а не текущей реплики. Без этого получаем: «player выиграл волну → диалог про волну → выбор → диалог про ачивку выклинивается между выбором и его ответом → возврат к ответу выбора». Это запрещено.

- Choice с `next: null` → сцена завершается сразу после клика по choice.
- Choice с `next: "id"` → переход к указанной реплике в той же сцене.
- Если `line.choices` непустой и `line.next` тоже задан — `next` игнорируется, choices приоритетнее. Валидация при загрузке: warn.
- Цикл (`next` ведёт на уже сыгранную в этой сцене реплику) → warn + завершение сцены. Защита от автора.
- На старте реплики — `EventBus.dialogue_started.emit(id)` и `AudioDirector.play_dialogue_audio(id, resolved_layer)`.
- На завершении сцены (последняя реплика отыграла или choice выбран) — `EventBus.dialogue_finished.emit(starting_id)`.
- Played-set чистится частично по `EventBus.run_started` (только `once_per_run`); `once_per_session` живёт всю игровую сессию (до перезапуска процесса).

### View

- `scenes/ui/dialogue_panel.tscn` — Control с панелью: portrait | (name + RichTextLabel + choices) | optional image-slot.
- Typewriter: скорость из `GameSpeed.get_value("ui", "dialogue_typewriter_chars_per_sec")`.
- Skip: первый клик/Space/Enter — долить весь текст; второй — next.
- Auto-advance: после полного показа текста, если choices пусты — ждать `dialogue_auto_advance_after_sec` и идти на `next`. Если `next` пуст — закрыть панель.
- Choices: до 3 кнопок, клик ведёт на `next` указанной choice.
- Текст рендерится через `RichTextLabel` с `bbcode_enabled=true` — это даёт `[b]/[i]/[color]` бесплатно и подготавливает `text_fx`.
- При `image != null` показать иллюстрацию в image-слоте; при `null` — слот скрыт.

### Content & smoke

- В репе `data/dialogues/_speakers.json` с минимум 3 speaker'ами (`narrator`, `rival`, `merchant`).
- Минимум 3 примера диалогов: `respawn_first.json` (простой), `respawn_choice.json` (с 2 choices), `boss_intro.json` (priority + conditions.min_run).
- В `main.tscn` — временная кнопка «Test dialogue» которая зовёт `DialogueManager.request(&"respawn", {"run_count": 1})`. Удаляется в фиче `005-roguelike-loop`.

### Dev preview

- `scenes/dev/dialogue_preview.tscn` — debug-сцена. ItemList всех id, поиск по подстроке, кнопка Play. Запускается отдельно (не из main), без зависимостей на боёвку. Это **наш «эдитор»** на джем. Папка `scenes/dev/` — конвенция для всех debug-сцен (preview диалогов, balance-tests Стасяна и т.п.).

### Acceptance verification

1. Открыть Godot, запустить main → видна кнопка «Test dialogue». Клик → панель появляется, typewriter идёт, портрет-плейсхолдер виден, в логе `[INFO][DialogueManager] play respawn_first`.
2. Клик мыши пока пишется → текст доливается мгновенно. Второй клик → панель закрывается, в логе `[INFO][DialogueManager] finished respawn_first`.
3. Открыть `dialogue_preview.tscn` → список из 3 диалогов. Выбрать `respawn_choice` → Play → видны 2 кнопки. Клик → next-реплика играет.
4. Запустить main, ничего не делать, прокликать кнопку 4 раза → реплика `respawn_first` сыграла **один раз** (она `once_per_session: true`), последующие request возвращают `&""` или другую реплику если есть.
5. Открыть `dialogue_preview.tscn`, отыграть `respawn_choice` целиком (выбор + его follow-up) — пока играется, в логе нет других диалогов даже если `EventBus.run_started` или другой триггер фиктивно дёрнуть с consol'и (scene atomicity).
6. В консоли при старте: `[INFO][DialogueDB] loaded N dialogues, M speakers`.

## Out of scope

- Граф-редактор / визуальный редактор веток.
- Ветки глубже 1 уровня выбора (CLAUDE.md / HANDOFF §9 запрещают).
- Локализация / i18n.
- Save persistence played-history (`_played_per_session` живёт только в памяти процесса; перезапуск = чистый старт; save-система когда-если появится — отдельная задача).
- **Реальная** реализация `text_fx` (shake/wave/fade) — поле зарезервировано в схеме, в коде no-op + warn если присутствует. Полноценные text-анимации — отдельная фича после джема либо если останется время в субботу.
- Реальные анимации `vfx_overlay` — то же самое, поле reserved-no-op.
- Глобальный flag-store (для `conditions.flags_required`/`flags_forbidden`). Поля в схеме есть, но пока всегда выполняются (пустой флаг-сет). Реальная проверка появится когда появится store.
- Реальные клипы в AudioDirector — продолжаем дёргать stub, диалоги уже готовы к интеграции.
- Параметризация текста (`Hello {player_name}`). Если очень захочется — добавим один спецтокен `{run_count}`, остальное — нет.

## Зависимости

- Собран на autoload'ах из 001-bootstrap.
- Не зависит от 002-hex-grid.
- Не блокирован контентом от Кати (используем placeholder-портреты — серый квадрат с именем speaker'а).
