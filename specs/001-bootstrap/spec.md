# 001-bootstrap — spec

**Owner:** Andrey
**Status:** in progress

## Цель

Репа готова к пятничному кодингу: базовая инфраструктура Godot-проекта собрана, autoloads работают, F5 hot-reload конфига работает, владельцы модулей знают где что лежит.

## Acceptance criteria

- 5 коллабораторов с write-доступом (Егор, Сергей, Алексей, Никита, Стасян) + Андрей-владелец = 6 в репе.
- Branch protection на `main` (push только Андрей/Егор) и `staging` (PR-only, ≥1 approval).
- Godot 4.6.2 проект открывается без ошибок, запускается, главная сцена показывает Label "Jam Project Ready".
- 4 autoload зарегистрированы и работают: Logger, EventBus, GameSpeed, AudioDirector.
- При `_ready()` главной сцены: `EventBus.run_started.emit()` отрабатывает, Logger пишет в консоль.
- F5 в работающей игре перечитывает `config/game_speed.cfg` без рестарта (видно в логах).
- Папки `data/`, `scenes/`, `scripts/`, `assets/`, `config/`, `specs/` созданы со всеми подпапками из HANDOFF §5.
- Личные папки `andrey/ egor/ nikita/ sergey/ alexey/ stasyan/` с README созданы.
- В корне: `CLAUDE.md`, `HANDOFF.md`, `PROJECT_INSTRUCTIONS.md`, `README.md`.
- PR `andrey/bootstrap → staging` смерджен.

## Out of scope

- HexGrid (это `002-hex-grid`).
- DialogueManager (это `003-dialogue-manager`).
- Любая игровая логика (бой, спеллы, враги).
- CI/CD, автосборки, itch.io интеграция.
- `jam-concept-pitch.md` — отдельный документ, попадёт в репу отдельно.

## Acceptance verification

Андрей открывает Godot 4.6.2, открывает `project.godot`, нажимает F5 (или кнопку Play). В консоли должно появиться примерно:

```
[INFO][AudioDirector] ready (stub)
[INFO][GameSpeed] config reloaded
[INFO][Main] boot complete; emitting run_started
[INFO][Main] run_started signalled — EventBus is alive
```

На экране — Label "Jam Project Ready". Нажатие F5 в игре добавляет ещё одну строку `[INFO][GameSpeed] config reloaded` — значит hot-reload жив.
