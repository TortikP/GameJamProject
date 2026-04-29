# 003-dialogue-manager — tasks

`[x]` — done. `[ ]` — outstanding. `[P1]` блокирующее, `[P2]` ценное, `[P3]` nice-to-have / known gap.
`[P]` — задача параллелится с другими в той же части.

## Часть 1 — engine

- [ ] T001 [P1] `scripts/core/dialogue/dialogue_line.gd` — RefCounted data-class. Поля по схеме из plan.md. Static `from_dict(d) -> DialogueLine` с дефолтами и валидацией обязательных полей (id/speaker/text). Без `class_name` — explicit preload в потребителях.
- [ ] T002 [P1] `scripts/core/dialogue/dialogue_database.gd` — Node для autoload. `_ready()`: сканит `data/dialogues/*.json` (skip префикс `_`), парсит каждый через `dialogue_line.from_dict`, складывает в `_lines: Dictionary[StringName, DialogueLine]`. Битый JSON → warn + skip. Дубликат id → warn + override. (depends T001)
- [ ] T003 [P1] DialogueDB: загрузка `data/dialogues/_speakers.json` в `_speakers: Dictionary[StringName, Dictionary]`. (depends T002)
- [ ] T004 [P1] DialogueDB: API `get_line(id) -> DialogueLine`, `has_line(id) -> bool`, `get_speaker(id) -> Dictionary`. (depends T002, T003)
- [ ] T005 [P1] DialogueDB: `find_by_event(event, context, played) -> DialogueLine` по алгоритму из plan.md. Возвращает `null` если ничего не подошло. (depends T004)
- [ ] T006 [P1] `scripts/core/dialogue/dialogue_manager.gd` — Node для autoload. `play(id, force=false) -> bool`, `request(event, context = {}, force=false) -> StringName`, `is_playing() -> bool`, `clear_queue()`. Внутренний state: `_queue`, `_played_per_run`, `_played_per_session`, `_current_panel`, `_scene_start_id`, `_scene_visited`. (depends T004, T005)
- [ ] T007 [P1] DialogueManager: подписка на `EventBus.run_started` → `_played_per_run.clear()`. (depends T006)
- [ ] T008 [P1] DialogueManager: на старте каждой реплики — `EventBus.dialogue_started.emit(id)` + `AudioDirector.play_dialogue_audio(id, resolved_layer)`. На завершении сцены — `EventBus.dialogue_finished.emit(_scene_start_id)`. (depends T006)
- [ ] T009 [P1] DialogueManager: scene atomicity + cycle detection. `_scene_visited` чистится в начале каждой сцены, ре-вход на тот же id → warn + end_scene. Pop очереди только в end_scene, не на завершении реплики. (depends T006)
- [ ] T010 [P1] DialogueManager: choice handling. Choice с `next: null` → end_scene; с `next: "id"` → переход; ссылка на несуществующий id → warn + end_scene. (depends T006)
- [ ] T011 [P1] `project.godot` — добавить в `[autoload]` после AudioDirector: `DialogueDB="*res://scripts/core/dialogue/dialogue_database.gd"`, затем `DialogueManager="*res://scripts/core/dialogue/dialogue_manager.gd"`. (depends T002, T006)

## Часть 2 — view

- [ ] T012 [P1] `scenes/ui/dialogue_panel.tscn` — иерархия из plan.md (Panel + HBox + Portrait + VBox{Name, RichTextLabel(bbcode), Choices} + Image).
- [ ] T013 [P1] `scripts/presentation/dialogue_panel.gd` — `show_line(line, speaker_data)`, typewriter через `visible_characters` + `Tween` (скорость из GameSpeed). Сигналы `text_completed`, `line_ended`, `choice_picked(index: int)`. (depends T012)
- [ ] T014 [P1] DialoguePanel: skip-логика. `_unhandled_input`: первый клик/Space/Enter — мгновенно показать весь текст; второй — emit `line_ended`. (depends T013)
- [ ] T015 [P1] DialoguePanel: auto-advance. Если `line.choices` пуст и текст дописан — таймер `dialogue_auto_advance_after_sec` → emit `line_ended`. (depends T013)
- [ ] T016 [P1] DialoguePanel: рендер choices. До 3 кнопок, на клик emit `choice_picked(i)`, скрыть кнопки. Choice с `next: null` валидна — Manager обработает как end_scene. (depends T013)
- [ ] T017 [P1] DialoguePanel: portrait + image. Если файла нет — placeholder через `_make_placeholder_texture(speaker_id)` (серый ImageTexture с надписью). Image-слот hidden если `line.image == null`. Сосуществуют — оба видимы при наличии. (depends T013)
- [ ] T018 [P1] DialogueManager инстанцирует `dialogue_panel.tscn` в новый `CanvasLayer`, добавляет в root как child. На каждый `play` — переиспользуем экземпляр. На end_scene — hide, не free. (depends T006, T012)

## Часть 3 — content seed

- [ ] T019 [P2] `data/dialogues/_speakers.json` — `narrator`, `rival`, `merchant`. Поля по схеме из plan.md. Портреты — пути на несуществующие файлы (placeholder сработает).
- [ ] T020 [P2] `data/dialogues/respawn_first.json` — реплика narrator с тегом `respawn`, `once_per_session: true`, priority 10.
- [ ] T021 [P2] `data/dialogues/respawn_choice.json` — реплика с 2 choices: один ведёт на follow-up id, второй — `next: null` (для проверки end_scene на choice).
- [ ] T022 [P2] `data/dialogues/boss_intro.json` — priority 100, conditions.min_run=2, тег `boss_intro`, `once_per_run: true`.

## Часть 4 — dev preview

- [ ] T023 [P2] `scenes/dev/dialogue_preview.tscn` — Control с ItemList (left), LineEdit (top, поиск), Button «Play», DialoguePanel (instanced). Папка `scenes/dev/` — новая, для всех debug-сцен.
- [ ] T024 [P2] `scripts/presentation/dialogue_preview.gd` — наполнить ItemList из `DialogueDB._lines.keys()` (фильтр по подстроке), на кнопку — `DialogueManager.play(selected_id, true)` (force=true, чтобы тестировать в любом состоянии). (depends T023, T006)

## Часть 5 — smoke

- [ ] T025 [P1] `scripts/main.gd` + `scenes/main.tscn` — добавить временную Button «Test dialogue». На pressed — `DialogueManager.request(&"respawn", {"run_count": 1})` (force=false, ambient-семантика). Комментарий: `# TODO: remove in feature 005-roguelike-loop`. (depends T011, T018)
- [ ] T026 [P1] Acceptance прогон по списку из spec.md §«Acceptance verification». 6 пунктов, ставить ok / нет рядом с каждым. Если что-то не проходит — фиксить или фиксировать как known gap.

## Часть 6 — known gaps (не блокеры для merge)

- [ ] T027 [P3] `text_fx` реализация (shake/wave/fade-in). Поле в схеме, в коде no-op + warn раз на запуск. Делается отдельной фичей `00X-dialogue-text-fx` после джема либо в субботу если останется время.
- [ ] T028 [P3] `image`-слот реальные ассеты от Кати. Сейчас слот рендерит то, что в JSON; пока пути отсутствуют — никто не указывает image, слот скрыт. Активация — после получения первой иллюстрации.
- [ ] T029 [P3] `AudioDirector` реальные клипы. Сейчас дёргается stub. Активируется параллельно по мере наполнения AudioDirector.
- [ ] T030 [P3] Глобальный flag-store. `conditions.flags_required` / `flags_forbidden` в JSON есть, но при пустом context.flags они всегда выполняются. Реальная проверка — когда появится store, в отдельной фиче.
- [ ] T031 [P3] Save persistence played-history. `_played_per_session` живёт только в памяти процесса. Save-система когда появится — читает и восстанавливает. +5 строк, не делаем заранее.
- [ ] T032 [P3] Параметризация текста (`{run_count}`, `{player_name}`). По спросу. Сейчас текст рендерится как есть.

## Часть 7 — merge

- [ ] T033 [P1] PR `andrey/dialogue-manager → staging`. Ревью Егором.
- [ ] T034 [P2] После merge — обновить `Currently claimed` таблицу в CLAUDE.md (поставить рядом с 003 пометку «engine done», когда engine + view + 3 примера контента в staging).
