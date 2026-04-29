# 001-bootstrap — tasks

`[x]` — done in this PR. `[ ]` — outstanding (Andrey or Egor finishes manually in GitHub UI / locally).

## Часть 1 — доступы (вне Клода, через GitHub UI)

- [ ] T001 [P1] Добавить 5 коллабораторов с write на TortikP/GameJamProject: Егор, Сергей, Алексей, Никита, Стасян.
- [x] T002 [P1] Ветка `staging` от `main` — уже была создана, на момент PR существует.
- [ ] T003 [P1] Branch protection на `main`: PR-only, push разрешён только Andrey и Egor через bypass-список / CODEOWNERS.
- [ ] T004 [P1] Branch protection на `staging`: PR-only, ≥1 approval. (Зависит от T002.)

## Часть 2 — структура проекта (этот PR)

- [x] T005 [P1] Godot 4.6.2 проект инициализирован: `project.godot` в корне.
- [x] T006 [P1] Структура папок из HANDOFF §5; `.gitkeep` в пустых leaf-папках.
- [x] T007 [P1] `.gitignore` (был при init репы — оставлен как есть, покрывает Godot 4 + IDE).

## Часть 3 — autoload (этот PR)

- [x] T008 [P1] `scripts/infrastructure/logger.gd`.
- [x] T009 [P1] `scripts/infrastructure/event_bus.gd` — все сигналы из HANDOFF §6.
- [x] T010 [P1] `scripts/infrastructure/game_speed.gd` — F5 hot-reload, `wait()` + `get_value()`.
- [x] T011 [P1] `scripts/infrastructure/audio_director.gd` — stub, наполняется по ходу.
- [x] T012 [P1] 4 autoload зарегистрированы в `project.godot` в порядке: Logger → EventBus → GameSpeed → AudioDirector. (depends T008–T011)

## Часть 4 — конфиги и точка входа (этот PR)

- [x] T013 [P1] `config/game_speed.cfg` со стартовыми значениями из HANDOFF §6.
- [x] T014 [P1] `scripts/main.gd` — `_ready()` зовёт `EventBus.run_started.emit()`, `_on_run_started()` логирует.
- [x] T015 [P1] `scenes/main.tscn` — Node + CanvasLayer + Label "Jam Project Ready", `main.gd` прицеплен, сигнал `EventBus.run_started` подключён.

## Часть 5 — документы (этот PR)

- [x] T016 [P1] `CLAUDE.md` в корень — конституция из HANDOFF §7.
- [x] T017 [P1] `HANDOFF.md` в корень.
- [x] T018 [P1] `PROJECT_INSTRUCTIONS.md` в корень — **шаблон с placeholder'ом для токена**, без реального токена.
- [x] T019 [P1] `README.md` в корень — что и как запустить.
- [x] T020 [P1] `specs/001-bootstrap/{spec,plan,tasks}.md`.

## Часть 6 — личные папки (этот PR)

- [x] T021 [P1] Папки `andrey/ egor/ nikita/ sergey/ alexey/ stasyan/` с README, объясняющим назначение.

## Часть 7 — мердж и проверка (вне Клода)

- [ ] T022 [P1] Андрей мерджит PR `andrey/bootstrap → staging` после ревью Егором.
- [ ] T023 [P1] Андрей открывает `project.godot` в Godot 4.6.2 локально, нажимает Play. Видит в консоли:
  ```
  [INFO][AudioDirector] ready (stub)
  [INFO][GameSpeed] config reloaded
  [INFO][Main] boot complete; emitting run_started
  [INFO][Main] run_started signalled — EventBus is alive
  ```
  и Label "Jam Project Ready" на экране.
- [ ] T024 [P2] F5 в работающей игре — в консоли `[INFO][GameSpeed] config reloaded`.
- [ ] T025 [P2] PR `staging → main` (когда Андрей решит, что staging достаточно стабилен).

## Часть 8 — известные пробелы (не блокеры для merge)

- [ ] T026 [P3] `jam-concept-pitch.md` — концепт-документ. Андрей кладёт отдельно, не блокер для bootstrap.
- [ ] T027 [P3] `assets/icon.svg` — иконка проекта. Без неё Godot использует дефолт. Катя добавит когда дойдут руки.
