# HANDOFF — джем-проект

> Документ для передачи контекста в новый чат Клода. Самодостаточен — содержит всё необходимое для продолжения работы. Сопутствующий артефакт: `jam-concept-pitch.md` (детальный концепт игры).

---

## 0. Как использовать этот документ в новом чате

Когда упрёшься в лимит текущего чата:

1. Открываешь новый чат с Клодом.
2. Первое сообщение: прикрепляешь этот файл (`HANDOFF.md`) + `jam-concept-pitch.md`.
3. Текст: *"Я работаю над джем-проектом. Контекст в файлах. Сейчас [текущий момент: вечер среды / утро четверга / после объявления темы / N-й час джема]. Текущая задача: [что делаешь]. Нужно: [конкретный запрос]."*
4. Клод подхватит и продолжит.

Этот документ — **внешняя память проекта**. Если правишь решения по ходу — обновляй его и кидай свежую версию в новый чат.

---

## 1. Quick context

**Кто:** команда из 7 человек. Доступ к репе у 6 (Катя работает через файлообмен).
- **Андрей** — менеджер-вайбкодер, UX, визионер, интеграция и polish. Claude Pro.
- **Егор** — программист, технарь, ядро механики (hex arena, battle loop, enemies). Claude Pro.
- **Сергей** — программист, spell-craft, modifier engine.
- **Алексей** — программист, roguelike loop, waves, portal, meta-screens UI, DialogueManager (engine).
- **Никита** — нарратив + вайбкодинг. Диалоги, flavor-тексты, тон. **Имеет Codex Pro ($20)**, может вайбкодить вспомогательные мелочи и итерировать тексты без программистов.
- **Стасян** — тех-геймдизайнер. Баланс, плейтест, контент модификаторов.
- **Катя** — художница. Тайлы, портреты, иконки, VFX. Доступа к репе нет, ассеты передаёт через файлообмен (Discord/Telegram), в репу заносит программист или Андрей через PR.

**Что:** игра на джем, **отдельный проект, отдельная репа** (не связано с Mother of Learning).

**Когда:**
- Сейчас: вечер среды. Setup новой репы, инфраструктура, заготовки.
- Завтра четверг до 19:00: подготовка модулей, которые работают под любую тему.
- Четверг 19:00: объявление темы (одна из 15, см. ниже).
- 72 часа джема: четверг вечер → суббота вечер.

**Концепт игры (default, может смениться после темы):**
Пошаговая магическая арена со спелл-крафтом через модификаторы (как Ball x Pit / Brotato), QWER-style слоты заклинаний, гекс-арена, рогаликовая петля в стиле Megabonk. Полный концепт — в `jam-concept-pitch.md`.

**Идентичность (не зависит от темы):**
- Перемотка плёнки между петлями.
- SFX → ИИ-голос → реальный человек по мере прогресса.
- Community-style мета-ирония, переключаемая на Гайман-тон под серьёзную тему.

---

## 2. Топ-15 тем джема

Одна из этих будет объявлена в четверг 19:00:

1. Время перестало работать
2. Действие имеет последствие
3. Иная точка зрения
4. Калейдоскоп
5. Квалиа
6. Метаморфозы
7. Нехватка места
8. Отражение
9. Падение
10. Самое красивое
11. Управление не тем персонажем
12. Уроборос
13. Цепная реакция
14. Эволюция
15. Это нельзя остановить

**Идеально ложатся на default-концепт:** 1, 2, 12, 13, 15.
**Лёгкие через смещение акцента:** 3, 6, 8, 14.
**Средние, требуют доработки:** 4, 9, 11.
**Сложные, могут потребовать другого концепта:** 5, 7, 10.

Подробный анализ каждой темы — в `jam-concept-pitch.md`.

---

## 3. LLM-ресурсы команды и подписки

**Текущая ситуация (вечер среды):** Stripe / Internal Server Error у Anthropic — это не разовый сбой, а системный пэйн последних 3-4 недель (декланы после 3DS, исчезающие gift-кредиты, "No Stripe subscription found" после прерванного чекаута, периодические инциденты с логином в claude.ai). **Егору оплату удалось пройти — Pro активен.**

**Кто чем пользуется:**
- **Андрей** — Claude Pro (claude.ai). Тащит сложные/длинные задачи команды, держит spec-driven контекст.
- **Егор** — Claude Pro. Технически сильнее Андрея в Godot, использует Клода точечно на тёмные углы Godot, не для постоянного вайбкодинга.
- **Никита** — Codex Pro ($20). Свой инструмент для диалогов, мелких помощников, content-итерации. Не зависит от Anthropic-стэка — это страховка на случай, если Anthropic снова ляжет.
- **Сергей, Алексей, Стасян, Катя** — без LLM-подписок. Задачи такие, что без LLM реально сделать.

**На джеме:**
- Если Anthropic снова ляжет (Stripe/login-инциденты бывали в апреле каждые 5-10 дней): Никита через Codex может разгрузить тех, у кого Клод недоступен — UI-копирайт, flavor-тексты, мелкие скрипты. План B живёт.
- Если кто-то из ключевых вылетит из-за билинга — берут токен другого, временно работают параллельно. После джема — нормализуют.

---

## 4. Технический стек

- **Engine:** Godot 4.6.2 (актуальный stable, март 2026). У всех на машинах патч-версия должна совпадать.
- **Язык:** только GDScript.
- **Платформа:** desktop (Win/Mac/Linux). Web-экспорт **не делаем** для джема — только если останется время в субботу и плейтест нужен через браузер.
- **VCS:** Git, хостинг — GitHub.
- **Контент:** JSON и `.tres` (Godot Resources). Никаких баз данных.
- **Звук:** встроенный Godot AudioStream. Если нужны interactive layers — слои AudioStreamPlayer с динамической громкостью.
- **CI/CD:** GitHub Actions для автосборки билдов на push в `main`. На джеме настраивается опционально, в первой половине пятницы. Если успеете — автодеплой билдов в itch.io draft.

---

## 5. Структура проекта Godot

Создаётся вечером среды. Простая, заточена под джем — не путать со сложной MoL-архитектурой.

```
jam-project/
├── project.godot
├── .gitignore                   # стандартный Godot 4 + IDE-файлы
├── CLAUDE.md                    # конвенции (см. секцию 7) — constitution в spec-driven терминах
├── HANDOFF.md                   # этот документ, operational context
├── PROJECT_INSTRUCTIONS.md      # содержимое для Project Settings в claude.ai
├── jam-concept-pitch.md         # концепт игры
├── README.md                    # как запустить, что где
├── specs/                       # spec-driven dev: spec.md/plan.md/tasks.md per feature
│   ├── 001-bootstrap/
│   ├── 002-hex-grid/
│   └── ...                      # см. секцию 19
├── config/
│   └── game_speed.cfg           # все тайминги, hot-reload по F5
├── data/
│   ├── modifiers/               # JSON-файлы модификаторов
│   ├── enemies/                 # JSON-файлы врагов
│   ├── spells/                  # JSON-файлы базовых заклинаний
│   └── dialogues/               # JSON-файлы диалогов
├── scenes/
│   ├── main.tscn                # точка входа
│   ├── arena/                   # боёвка (hex-арена, бой)
│   ├── meta/                    # метаэкраны (апгрейд, респаун, finale)
│   └── ui/                      # переиспользуемые UI-компоненты
├── scripts/
│   ├── core/                    # игровая логика (бой, спелл-крафт, прогрессия)
│   │   ├── arena/
│   │   ├── spells/              # модификатор-движок
│   │   ├── progression/         # волны, портал, метапрогрессия
│   │   └── dialogue/            # DialogueManager
│   ├── infrastructure/          # autoloads
│   │   ├── game_speed.gd
│   │   ├── event_bus.gd
│   │   ├── logger.gd
│   │   └── audio_director.gd
│   ├── presentation/            # UI-скрипты, VFX, polish
│   └── content/                 # хелперы загрузки JSON в Resources
├── assets/
│   ├── sprites/
│   ├── tiles/
│   ├── portraits/
│   ├── icons/                   # иконки модификаторов
│   ├── vfx/
│   ├── audio/
│   │   ├── sfx/
│   │   ├── music/
│   │   └── voice/               # SFX-бормотание, AI-голоса, human-голоса
│   └── fonts/
└── tests/                       # GUT, опционально
```

**Принцип:** `scripts/core/` ничего не знает про конкретные текстуры или звуки. `presentation/` зависит от `core/`. `infrastructure/` (autoloads) видна всем. Это упрощённая версия слоёв из MoL — ничего лишнего.

---

## 6. Autoloads (must-have на вечер среды)

Регистрируются в `project.godot` сразу.

### `GameSpeed` (`scripts/infrastructure/game_speed.gd`)

Читает `config/game_speed.cfg` при старте, перечитывает по F5. Все тайминги в игре читают значения отсюда.

```gdscript
extends Node

const CONFIG_PATH = "res://config/game_speed.cfg"
var _cfg: ConfigFile

func _ready():
    reload()

func reload() -> void:
    _cfg = ConfigFile.new()
    _cfg.load(CONFIG_PATH)
    print("[GameSpeed] config reloaded")

func get_value(section: String, key: String, default = 1.0):
    return _cfg.get_value(section, key, default)

func wait(section: String, key: String, default := 0.5) -> void:
    var t: float = get_value(section, key, default)
    await get_tree().create_timer(t).timeout

func _input(event):
    if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
        reload()
```

Стартовый `config/game_speed.cfg`:
```
[battle]
spell_resolve_speed=0.4
enemy_turn_speed=0.5
between_battles_pause=0.3

[ui]
dialogue_typewriter_chars_per_sec=60.0
dialogue_auto_advance_after_sec=3.0
upgrade_screen_min_display=2.0
respawn_animation_duration=1.5

[meta]
rewind_effect_duration=0.8
boss_intro_duration=3.0

[clock]
tick_animation_duration=0.2
```

**Правило для всей команды:** хардкоженных таймеров в коде не должно быть. PR с `await get_tree().create_timer(0.5)` без обёртки `GameSpeed.wait(...)` — отклоняется на ревью.

### `RunScore` (`scripts/infrastructure/run_score.gd`) — добавлен в 024

Per-run счётчик очков. `RunScore.add(delta)` → `total += delta` + emit `score_changed(total, delta)`. Подписан на `EventBus.run_started` для авто-сброса при новом ране (godmode emits run_started в `_ready`). Используется WaveController'ом (auto-clear → `add(turns_to_next - turns_into_wave)`) и HUD виджетом `score_corner.tscn`.

### `EventBus` (`scripts/infrastructure/event_bus.gd`)

Глобальный сигнал-хаб. Все системы публикуют и слушают через него.

```gdscript
extends Node

# Бой
signal battle_started(arena_id)
signal battle_ended(victory: bool)
signal turn_started(actor_id)
signal spell_cast(actor_id, spell_id, targets: Array)

# Прогрессия
signal wave_spawned(wave_index: int)
signal portal_opened
signal upgrade_offered(options: Array)
signal upgrade_chosen(modifier_id)

# Waves (024) — runtime wave lifecycle, separate from legacy wave_spawned.
# WaveController emits these; HUD wave_timeline + score_corner + 025
# level_dialogues subscribe.
signal wave_started(index: int, is_special: bool)
signal wave_cleared(index: int, unused_turns: int)
signal level_completed(total_score: int)
signal actor_spawned(actor_id: StringName)

# Run-цикл
signal run_started
signal run_ended(reason: String)
signal rewind_started
signal rewind_finished

# Диалоги
signal dialogue_started(dialogue_id)
signal dialogue_finished(dialogue_id)
```

Все имена сигналов — past tense, snake_case. **Не переименовываются** без согласования с владельцем модуля, который их слушает.

### `Logger` (`scripts/infrastructure/logger.gd`)

Простой:

```gdscript
extends Node

enum Level { DEBUG, INFO, WARN, ERROR }

func log(level: int, tag: String, msg: String) -> void:
    var prefix := "[%s][%s]" % [Level.keys()[level], tag]
    print("%s %s" % [prefix, msg])

func info(tag: String, msg: String) -> void: log(Level.INFO, tag, msg)
func warn(tag: String, msg: String) -> void: log(Level.WARN, tag, msg)
func error(tag: String, msg: String) -> void: log(Level.ERROR, tag, msg)
func debug(tag: String, msg: String) -> void: log(Level.DEBUG, tag, msg)
```

### `AudioDirector` (`scripts/infrastructure/audio_director.gd`)

Заготовка на вечер среды, наполняется по мере. Идея: централизованное управление звуковыми слоями, поддержка эскалации SFX → AI → human.

### `MusicDirector` (`scripts/audio/music/music_director.gd`) — добавлен в 042

Процедурный музыкальный движок. Real-time PCM через `AudioStreamGenerator`, без аудиоассетов в сорсе. Два состояния (`calm`/`battle`), JSON-конфигурируемые стинги (заменяемые на OGG без правки кода). Подписан на EventBus: `level_loaded`, `wave_started`, `wave_cleared`, `level_completed`, `run_ended`, `main_menu_entered`, `run_started_requested`.

Архитектура (low→high): `Wavetables` → `ADSR` → `VoicePool` → `Conductor` + `Harmony` + `StateMixer` → `BassGen`/`PadGen`/`LeadGen`/`DrumsGen` → `MusicDirector` → `StingPlayer`.

Per-level конфиг в `LevelData.music_config` (опциональный, `{}`=дефолты). Меню-конфиг в `data/music/main_menu.json`. Стинги в `data/music/stings.json` (swap OGG: `"kind":"stream","path":"res://..."` в одной строке JSON). Пресеты в `data/music/presets.json`.

**Публичный API** (Music Lab и `_on_level_loaded`): `set_bpm`, `set_state`, `set_seed`, `set_layer_db(layer, db)`, `set_lead_density(calm, battle)`, `play_sting(name)`.

**Music Lab**: `scenes/dev/music_lab.tscn` — F6 для запуска. Слайдеры (BPM, lead density, gain), A/B слоты, стинг-кнопки, «Copy JSON» в clipboard (готово к вставке в level.json). Что слышишь в лабе = что услышишь в игре с тем же конфигом.

Полная архитектура: `specs/042-proc-music/`.

---

## 7. CLAUDE.md для новой репы

Кладёшь в корень репо вечером среды. Все Клоды (твой, Егора, программистов, тех-ГД) читают это первым делом каждой сессии.

```markdown
# Jam Project — Conventions

## Context
Game jam project. 72 hours from Thursday 19:00. Team of 7 (6 in repo, +Katya outside).
Theme will be announced Thursday 19:00 from a list of 15.
Default concept: turn-based magical arena with spell-crafting via modifiers,
hex grid, roguelike loop. See jam-concept-pitch.md for details.

## Stack
- Godot 4.6.2 (patch versions must match across team)
- GDScript only
- JSON / .tres for content
- Desktop builds (web only if time permits Saturday)

## Hard rules

### Architecture
1. scripts/core/ knows nothing about specific textures, audio files, or scenes.
2. scripts/presentation/ depends on core, not the other way around.
3. Autoloads (GameSpeed, EventBus, Logger, AudioDirector) are accessible from anywhere.
4. Cross-system communication goes through EventBus signals, not direct references.

### Timing
5. NO hardcoded timer values. Use `GameSpeed.wait(section, key)` or read 
   `GameSpeed.get_value(...)`. PRs with bare `create_timer(0.5)` are rejected.
6. All tunables live in config/game_speed.cfg. F5 reloads it live.

### Content
7. Modifiers, enemies, spells, dialogues are JSON files in data/.
   Programmers build engines; designers fill data files.
8. Don't hardcode content in GDScript. If a modifier needs new code, that's 
   a new modifier *type*, not a new modifier.

### Naming
- Files: snake_case.gd, snake_case.tscn
- Classes (class_name): PascalCase
- Signals: snake_case past tense (battle_started, wave_spawned)
- Constants: SCREAMING_SNAKE_CASE
- Private members: _leading_underscore

## Module ownership

| Module | Owner |
|--------|-------|
| Hex arena, battle loop, enemies | Egor |
| Spell-craft, modifier engine | Sergey |
| Roguelike loop, waves, portal, meta-screens UI, DialogueManager (engine) | Alexey |
| UX integration, polish, audio direction, tone | Andrey |
| Balance, modifier content, playtest | Stasyan |
| Dialogue content, flavor texts, voice direction | Nikita (uses Codex Pro) |
| Tiles, portraits, icons, VFX | Katya (assets via file exchange, no repo access) |

Owner has final say on their module's public API. Renaming public methods or 
signals requires PR with `breaking:` prefix and owner's approval.

## Git workflow

Two-tier branching:
- `main` — protected. Direct push only by Andrey and Egor. Stable, deployable. PRs to main only from `staging`.
- `staging` — integration branch. Feature PRs merge here. Reviewed but lower bar than main.
- `<user>/<short-name>` — individual work. Created off `staging`, merged back via PR. `<user>` is the lowercase author name (`andrey`, `egor`, `nikita`, `sergey`, `alexey`, `stasyan`). Owner is implicit in the prefix — no need for separate ownership comments.

Flow:
1. `git checkout staging && git pull && git checkout -b egor/your-thing`
2. Work, commit, push.
3. PR `egor/your-thing → staging`. Reviewed by another human (Claude can help, human signs off).
4. Periodically (when staging is stable): Andrey or Egor opens PR `staging → main`, smoke-tests, merges.

Rules:
- No direct push to main except Andrey/Egor.
- No direct push to staging — even owners use PRs.
- One branch per task. Don't mix tasks in one branch.
- Branch prefix matches the author. Pair work: one person owns the branch, the other commits to it; don't do `andrey-egor/...`.
- Conflict resolution: owner of the affected module merges first; others rebase.
- Claude push access (when token configured): only to `<user>/*` branches and PRs to `staging`. Never to main directly.

## Don't

- Don't refactor files outside your current task.
- Don't rename public APIs without owner consent.
- Don't push to main directly.
- Don't add libraries/addons without team agreement.
- Don't bypass GameSpeed for timings.
- Don't bypass EventBus for cross-module communication.
- Don't hardcode content in scripts.
- Don't expand scope without team agreement. Read scope section in pitch doc.

## Don't (for non-coders)

- Don't edit code files directly. Edit JSON in data/ and ask a programmer 
  if a new modifier *type* is needed.
- Don't commit large unoptimized assets. Compress sprites before committing.

## Claude usage

- Each Claude session starts with reading this file and jam-concept-pitch.md.
- For unfamiliar files, Claude reads them before suggesting changes.
- Claude proposes plans before writing more than 30 lines of code.
- If Claude suggests an abstraction "for the future", reject it. We have 72 hours.

## Speed > polish > scope

If running out of time on Saturday:
1. Cut scope first.
2. Ship what's stable.
3. Polish only what's already working.
4. Never push broken code to main on Saturday afternoon.
```

---

## 8. План на вечер среды (сейчас)

Цель — собрать инфраструктуру, чтобы завтра утром все могли начать работать.

**Часы 1–2: репа и доступы.**
- **Репа уже создана: https://github.com/TortikP/GameJamProject.** Сейчас наполняется.
- Добавь 5 коллабораторов с write: **Егор, Сергей, Алексей, Никита, Стасян**. Кате доступ не нужен (работает через файлообмен).
- Создай ветку `staging` от `main`.
- Branch protection на `main`: direct push разрешён только Андрею и Егору (через bypass-список или CODEOWNERS), всё остальное — через PR из `staging`.
- Branch protection на `staging`: direct push запрещён всем, мердж только через PR с минимум 1 approval.
- Кинь всем ссылку + краткое описание branch-стратегии (см. §7 в CLAUDE.md) в общий чат.
- Сгенерируй fine-grained personal access token для Клода с правами write только в этой репе. Токен передавай через защищённый канал (1Password, gpg-encrypted, временный paste с авто-удалением — **не в чат**). Положи токен в `PROJECT_INSTRUCTIONS.md` (содержимое для Project Settings в claude.ai), но **не коммить файл с реальным токеном** — в репе только шаблон с placeholder'ом.

**Часы 2–3: структура проекта.**
- Локально создаёшь Godot-проект `jam-project/` в свежей репе.
- `.gitignore` — стандартный для Godot 4 (можно нагенерить через [gitignore.io](https://gitignore.io) с тегами `godot` + ваша IDE).
- Создаёшь все папки из секции 5, в пустые кладёшь `.gdkeep`.
- `project.godot` — настройка autoloads (GameSpeed, EventBus, Logger, AudioDirector).
- Пишешь четыре autoload-файла из секции 6.
- `config/game_speed.cfg` — стартовая версия.
- В корень: `CLAUDE.md` из секции 7, **`HANDOFF.md` (этот документ)**, **`jam-concept-pitch.md`**, **`PROJECT_INSTRUCTIONS.md` (шаблон с placeholder'ом для токена)**. Чтобы любой Клод/Codex в команде имел контекст из репы.
- Папка `specs/` создаётся пустой с `.gitkeep`. Внутрь сразу кладёшь `specs/001-bootstrap/` со spec/plan/tasks (см. §19).
- Короткий `README.md` — что это, как запустить, ссылка на CLAUDE.md и HANDOFF.md.
- Один initial commit прямо в `main` (это разовое исключение — дальше всё через PR в staging).

**Часы 3–4: первый PR с базовой сценой.**
- Ветка `andrey/bootstrap` (от `staging`).
- `scenes/main.tscn` — пустая сцена с Label "Jam Project Ready" и подписан на `EventBus.run_started` для проверки.
- На `_ready()` вызываешь `EventBus.run_started.emit()`, лог пишет в консоль.
- PR `andrey/bootstrap → staging`. Обзор Егором (или кем-то из доступных). Merge в staging.
- Когда staging стабилен — Андрей или Егор открывает PR `staging → main`, мерджит.

**После этого можно расходиться спать или продолжить с заготовками** (секция 9).

**Контроль:** к концу вечера среды у вас:
- Репа https://github.com/TortikP/GameJamProject с правильной структурой.
- 5 коллабораторов с write (Егор, Сергей, Алексей, Никита, Стасян) + Андрей-владелец = 6 в репе.
- Branch protection на main и staging; ветка staging создана.
- 4 рабочих autoload.
- `game_speed.cfg` с hot-reload по F5.
- CLAUDE.md, HANDOFF.md, jam-concept-pitch.md, PROJECT_INSTRUCTIONS.md в корне.
- Личные папки `andrey/ egor/ nikita/ sergey/ alexey/ stasyan/` с README.
- `specs/001-bootstrap/` со spec/plan/tasks как образец.
- Первый merged PR (`andrey/bootstrap → staging`, опционально дальше в main).

---

## 9. Опциональные заготовки на вечер среды или утро четверга

Это модули, которые **работают под любую тему**. Если есть силы — делаете заранее. Если нет — после темы.

### `HexGrid` (Егор)

`scripts/core/arena/hex_grid.gd` + `scenes/arena/hex_grid.tscn`.
- TileMap с гекс-тайлсетом (в Godot 4: TileSet → Shape → Hexagon).
- 5 разноцветных тайлов 64×64 как заглушки.
- Camera2D с панорамированием на drag правой кнопкой.
- Метод `coord_under_mouse() -> Vector2i`.
- Сигнал `hex_clicked(coord: Vector2i)`.
- Подсветка под курсором (можно сразу).

Этот модуль нужен под любой концепт с гекс-картой. Под не-гексовый концепт — выкидывается без потерь.

### `DialogueManager` (Алексей)

`scripts/presentation/dialogue_manager.gd` + `scenes/ui/dialogue_panel.tscn`.
- Autoload-стиль, но как обычный класс (для тестируемости).
- Лежит в `presentation/`, а не `core/`, потому что инстанцирует и владеет UI-панелью. `scripts/core/dialogue/` остаётся для чисто-данных (`dialogue_database.gd`, `dialogue_line.gd`).
- Читает `data/dialogues/*.json` при старте.
- API: `play(dialogue_id: String)`, `play_random_by_tag(tag: String)`, очередь.
- Сигналы через EventBus: `dialogue_started`, `dialogue_finished`.
- `DialoguePanel` — портрет + имя + typewriter-текст + 2-3 кнопки выбора (опционально).
- Skip по любой клавише или клику. Auto-advance после `dialogue_auto_advance_after_sec` из GameSpeed.

JSON-формат:
```json
{
  "id": "respawn_first_time",
  "speaker": "narrator",
  "portrait": "res://assets/portraits/narrator_neutral.png",
  "text": "Again? Already?",
  "audio_layer": "sfx",
  "tags": ["respawn", "early_game"],
  "choices": []
}
```

`audio_layer` — `sfx`, `ai_voice`, `human` — управляется AudioDirector.

Под любую тему DialogueManager работает идентично — меняется только контент.

### `GameSpeed` уже сделан в секции 6.

Этих трёх модулей + 4 autoload + структура — **достаточно** чтобы пятница утро началась с продуктивного кодинга, не с setup-боли.

---

## 10. Утро четверга до объявления темы

Тема в 19:00. У тебя весь день. Не сиди в ожидании.

**Что делать:**
- Финализировать заготовки (если не сделали в среду).
- Подготовить **3-4 шаблона для разных тем** в виде заметок: "если выпадет 'Цепная реакция', делаем X. Если 'Иная точка зрения', делаем Y." 30 минут — серьёзно облегчат вечер.
- Катя рисует **универсальные элементы**: общий UI-стиль, шрифт, палитра, базовые формы тайлов. Не привязанные к теме.
- Никита пишет **универсальные реплики** (респаун, победа, поражение) в нейтральном тоне. Под тему просто перепишет тонально.
- Стасян готовит **шаблон JSON для модификаторов** и пробует написать первые 5-10 как образец. Под тему адаптирует названия.
- Ты с Егором — финализируешь заготовки и **проводишь dry-run параллельной работы**: 30 минут пишете что-то простое в две ветки, мерджите, ловите проблемы интеграции.

**Что НЕ делать:**
- Не писать игровую логику. Тема может всё поломать.
- Не привязываться к концепту слишком сильно. Это default, но не финал.
- Не уставать. Вечером четверга — мозговой штурм всем составом, силы нужны.

---

## 11. После объявления темы (четверг 19:00–22:00)

**Первые 2 часа — обсуждение, не кодинг.** Это критично.

Программа:
1. **20 минут** — индивидуально. Каждый записывает свои первые мысли по теме. Никаких обсуждений пока.
2. **30 минут** — раунд по кругу. Каждый озвучивает свою главную идею. Никаких споров, только слушать.
3. **30 минут** — групповая критика default-концепта под тему. Пройдитесь по `jam-concept-pitch.md`, секция "Натягивание на темы". Если для вашей темы есть пометка — стартуете оттуда.
4. **20 минут** — финальное решение. Идём с default-концептом? С модификацией? С другим? Голосование, но не demokratия — Андрей и Егор имеют право вето на технически нерабочие идеи.
5. **20 минут** — декомпозиция. Кто что делает в пятницу до полудня.

**Критерии "идём с default-концептом":**
- Тема из идеальных или лёгких (см. секцию 2).
- Все 7 человек согласны.
- Программисты подтверждают, что ядро собирается за пятницу.

**Критерии "берём что-то другое":**
- Тема сложная, нет загорания у команды.
- Кто-то из ключевых членов категорически против.
- За первые 2 часа концепт не вызывает энергии.

**Если идёте с другим концептом:** заготовки HexGrid/DialogueManager/GameSpeed всё равно полезны. Autoloads — тем более. Не паникуйте.

**После 22:00 четверга — спать.** Серьёзно. Кодинг с пятницы утра. Даже если кажется, что есть запал — спите. 72 часа без сна — провал.

---

## 12. Workflow на 72 часа джема

### Пятница утром (старт)

- Все на ветках `<имя>/<своя-задача>` (`egor/hex-grid`, `sergey/modifier-engine`, etc).
- Андрей координирует, проверяет прогресс каждые 2 часа.
- Голосовой канал Discord/Telegram открыт постоянно. Текстовый — для ownership-объявлений ("я взял X").

### Пятница вечером (точка проверки 1)

К концу дня пятницы должны работать:
- Hex-арена с одним юнитом игрока, одним типом врага.
- Один спелл с одним модификатором, кастуется по клику на гекс.
- Бой на 1 волну заканчивается победой/поражением.
- Один диалог проигрывается при респауне.

Если **что-то из этого не работает** — суббота начинается с **резки скоупа**, не с добавления фич. См. секцию 14.

### Суббота утром

К утру субботы должно играться:
- Полный run от начала до босса (10-15 минут).
- 4 заклинания, 10+ модификаторов в пуле.
- Экран апгрейда между боями.
- Несколько диалогов в run'е.
- Перемотка плёнки на респауне.

**Если играется — остаток дня = polish и контент.** Не новые фичи. Катя доделывает ассеты, Никита заливает диалоги, Стасян балансирует.

### Суббота днём

- Финальные диалоги.
- ИИ-голос на ключевых репликах (опционально).
- Музыкальные слои (опционально).
- Финальный приём (скип отключён + реальный голос) — если успели записать живой голос. Если не записали — без него, не страшно.

### Суббота вечер (последние 3 часа)

**Не пишем код.**
- Финальная сборка билда.
- Тестирование на чужой машине, если есть возможность.
- Запись короткого трейлера / геймплейного видео.
- Загрузка на itch.io (или куда требует джем).
- Заполнение описания страницы джема.

**Дедлайн — приоритет №1.** Лучше залить чуть менее полированный билд за час до дедлайна, чем за минуту после.

---

## 13. Параллельная работа на 6 в репе (7 в команде)

### Базовые принципы

- **Каждый объявляет ownership** перед началом задачи. В голосе или в текстовом канале: "беру `scripts/core/arena/hex_grid.gd` и `scenes/arena/hex_grid.tscn` на 2 часа".
- **Никто не трогает чужой файл** без согласования с владельцем.
- **Public API объявленных модулей не переименовывается** без PR с `breaking:` префиксом.
- **Синки голосом каждые 2-3 часа** — короткие, по 5 минут. "Что я сделал, что планирую, на что упёрся".
- **Катя вне репы.** Её ассеты заносит в репу программист или Андрей через PR с собственной ветки (например `andrey/assets-batch1` или `alexey/portrait-assets`) → staging.

### Code review

- Все PR ревьюит другой человек **глазами** перед merge.
- Клода можно использовать как ассистента ревью: копируешь diff, просишь найти проблемы.
- Не используем GitHub-боты для авто-merge на джеме. Слишком высок риск merge'а сломанного кода.

### Конфликты

Если двое одновременно упёрлись в один файл:
1. Сначала договариваются голосом.
2. Если конфликт остаётся — owner модуля принимает решение.
3. Если owner — третий человек, обращаются к Андрею.

### Катя и Никита

- **Катя** работает в любом удобном инструменте, итоговые ассеты передаёт через файлообмен (Discord/Telegram). В репу заносит **программист или Андрей** через PR со своей ветки (например `andrey/assets-batch1`) → staging, проверяя сжатие и пути.
- **Никита** редактирует JSON в `data/dialogues/` напрямую (имеет доступ к репе и Codex Pro для помощи). Если упирается — Codex генерит шаблон, он правит. Андрей или Алексей ревьюят PR.

### Стасян (тех-ГД)

- Балансирует через JSON в `data/modifiers/`, `data/enemies/`. Не трогает код.
- Плейтест каждые 2-3 часа после того, как игра запускается. Фидбек — в общий канал.

---

## 14. Защита от расширения скоупа

**Самый частый провал джема — не недостаток времени, а избыток амбиций.** Раз в 4 часа Андрей задаёт команде вопрос: **"что мы можем выкинуть?"**

Список того, что **никогда** не делается на джеме:

- Мультиплеер.
- Сохранение прогресса между сессиями (для джем-демо не нужно).
- Полноценные настройки (графика, звук, биндинги).
- Меню паузы со всеми опциями (примитивная — да, полная — нет).
- Локализация. Делаете на одном языке, точка.
- Ачивки.
- Туториал. Заменяется одним экраном с подсказками управления.
- Кастомизация персонажа.
- Интро-катсцены длиннее 10 секунд.
- Любая фича, которая "украсит, но не нужна для core experience".

Если кто-то предлагает добавить — Андрей спрашивает: **"что мы за это выкидываем?"** Это не значит "нет". Это значит "если хочешь добавить, скажи что убираешь".

---

## 15. Если что-то идёт не по плану

### "Концепт не работает к пятнице вечером"

Не паника. Что делать:
1. Собираете команду на 30 минут.
2. Определяете, **что именно** не работает: ядро механики, контент, технические проблемы?
3. **Радикально режете скоуп.** Может, это не "магическая арена с модификаторами и QWER", а "магическая арена с одним заклинанием и пятью модификаторами". Это всё ещё игра.
4. Продолжаете с урезанным скоупом до утра субботы.

### "Один из программистов выпал (заболел, форс-мажор)"

- Его модуль перераспределяется или режется из скоупа. У вас всего 3 программиста — потеря одного критична, режьте скоуп агрессивно.
- Не пытайтесь сохранить весь план. Сохраните игру.

### "Катя не успевает с ассетами"

- Используйте placeholder-арт (квадраты, геометрические фигуры) для всего, кроме 2-3 ключевых экранов.
- Катя доделывает только то, что **видно за первые 5 минут плейтеста**.

### "Никита пишет слишком много"

- Половина не попадёт в игру. Это нормально.
- Берите топ-15 реплик по эмоциональному весу.

### "Хотим добавить фичу X"

Один вопрос: **"что мы выкидываем?"** Если ответа нет — фича не добавляется.

---

## 16. После джема

- **Не откатывайтесь к Mother of Learning сразу.** Отдых день-два минимум.
- Ретроспектива через 2-3 дня всем составом: что зашло, что нет, кого хотим в команду MoL.
- Если джемный концепт зашёл и хочется развивать — **обсуждаете отдельно**, может стать самостоятельным проектом.
- Если зашёл movement-engine или модификатор-движок — переносится в MoL `content/jam_game/` на пост-джемном цикле.

---

## 17. Полезные ссылки и материалы

- [Red Blob Games — Hexagonal Grids](https://www.redblobgames.com/grids/hexagons/) — единственное, что нужно прочитать про гекс-математику.
- [Godot 4 Docs](https://docs.godotengine.org/en/4.6/) — общая документация.
- [Godot TileMap (4.6)](https://docs.godotengine.org/en/4.6/classes/class_tilemap.html) — для гекс-тайлмапа.
- [GUT (Godot Unit Test)](https://github.com/bitwes/Gut) — если будете тесты писать. На джеме обычно нет.
- [The Alexandrian — RPG game structures](https://thealexandrian.net/) — для вдохновения по геймдизайну (полезно, не критично).

---

## 18. Текущее состояние и следующее действие

**Сейчас:** вечер среды. Андрей с Егором садятся за setup.

**Репа:** https://github.com/TortikP/GameJamProject (создана, наполняется).

**Spec-driven dev:** включён. `specs/` живёт в репе. Каждая фича — папка `specs/NNN-name/` с `spec.md`, `plan.md`, `tasks.md`. Подробности — секция 19.

**Branch model:** `<user>/<task> → staging → main`. Префикс ветки — имя автора (`andrey/`, `egor/`, ...). Push в main только Андрей и Егор. См. §7 "Git workflow".

**Следующее действие — фича 001-bootstrap (`specs/001-bootstrap/tasks.md`):**
1. Доступы 5 коллабораторов (Егор, Сергей, Алексей, Никита, Стасян) и branch protection (см. §8).
2. Создание ветки `staging`.
3. Локально создать Godot-проект со структурой из секции 5.
4. Написать 4 autoload из секции 6.
5. Положить `CLAUDE.md`, `HANDOFF.md`, `jam-concept-pitch.md`, `PROJECT_INSTRUCTIONS.md` в корень.
6. Initial commit на main. Затем `andrey/bootstrap → staging` → ревью → merge.

Если за вечер успеваете дойти до заготовок (секция 9) — отлично, это будут фичи `002-hex-grid` (Егор) и `003-dialogue-manager` (Алексей). Если нет — сделаете утром четверга.

**Не работайте после полуночи.** Серьёзно. Завтра тема + 72 часа интенсива. Силы нужны.

**В работе сейчас:** `020-map-editor` (data-driven mouse-driven editor для карт: пол/объекты/спавнеры → `data/maps/*.json`, Playtest сразу в бой). Ветка `andrey/020-map-editor-impl`, spec/plan/tasks в `specs/020-map-editor/`. После мержа Стасян может рисовать карты мышью или править JSON руками по `data/maps/_schema.md`. **Смерженное в staging:** `018-tile-objects` (data-driven статика тайлов: камни/лава/фонтаны/бочки), `019-tile-object-resolver` (runtime триггеры этих объектов).

**032-controller-refactor (in-PR, ветка `andrey/controller-refactor`):** `godmode_controller.gd` распилен с 1432 строк до 225 — 8 sibling-нод под GodmodeController в `scripts/presentation/godmode/`: `godmode_setup.gd` (288), `ai_driver.gd` (224), `godmode_input.gd` (210), `telegraph_renderer.gd` (194), `hover_dispatcher.gd` (193), `cast_fsm.gd` (169), `manekin_spawner.gd` (77), `step_animator.gd` (24). Контроллер держит селекшн-фасад (`select`/`inspect_hex`/`bind_hex_at`/`refresh_overlay`/`deselect_to_player`), SlotBar signal pump, ability picker, `_resolve_modules` и `_is_wave_transitioning` proxy. Pattern: модули читают shared state через `_ctrl.X` (controller as facade), нет EventBus-шума. Параллельно — tileset consolidation: `scenes/dev/godmode_terrain.tres` удалён, `scenes/arena/tilesets/hex_terrain.tres` (`tile_shape = HEXAGON`, 128×80) — единственный TileSet в проекте (sample maps + level_data + map_editor + floor_palette перенаправлены). B-001 верифицирован закрытым (гарды `is_instance_valid` в обеих фазах AI после переноса). B-003 (move-overlay не отрисовывается) — теоретически закрыт ещё в 029 геометрической edge-detection, тайлсет-консолидация снимает остаточный риск. **Pending Andrey:** ручная смок-проверка в Godot editor по T29 (procedural godmode + sample.json Playtest + sample_waves.json Playtest). **B-002** (`UiTheme.apply_label_kind` static-call warning) — out-of-scope, отдельным PR.

---

**Удачи. Документ обновляется по ходу — после ключевых решений правьте его и перекидывайте свежую версию в новые чаты Клода.**

---

## 19. Spec-driven development workflow

Каждая фича перед кодом получает три файла в `specs/NNN-feature-name/`:

- **`spec.md`** (что и зачем): цель фичи, acceptance criteria, out-of-scope, owner. Без HOW, без библиотек, без архитектуры. ≤ 1 страница.
- **`plan.md`** (как): API между модулями, file paths, схемы данных, точки интеграции с EventBus. Может ссылаться на разделы HANDOFF.md вместо дублирования.
- **`tasks.md`** (чеклист): пронумерованные таски `T001`, `T002`, ... с приоритетами `[P1]` / `[P2]` / `[P3]`, отметкой параллельности `[P]`, путями файлов и зависимостями `(depends T00X)`. Один таск — один логический шаг с конкретным выходом.

### Жёсткие правила

1. Не пропускать фазы. Если кто-то говорит "давай сразу код" — сначала пиши spec, даже короткий.
2. Implement-режим: один таск за раз, отметить `[x]`, остановиться, подтвердить с командой/Клодом, следующий. Не лупиться через все 18 одним рывком.
3. Таск отмечается `[x]` только если работает. Полу-готовый — `[ ]` с пометкой что не доделано.
4. Не зипуй и не "финализируй" проект до субботы вечера.

### Адаптация под джем (важно — это не энтерпрайзный spec-kit)

- **Clarify-фаза** = голос в дискорде на 30 секунд. Не пишем формальный Q&A в файле.
- `spec.md` без user stories. Сразу acceptance criteria.
- `plan.md` заточен на API/контракты между модулями (это критично для параллельной работы) и file paths.
- Нумерация фич сквозная: `001-bootstrap`, `002-hex-grid`, `003-modifier-engine`, `004-dialogue-manager`, и так далее.
- Если фича выпала из скоупа — папку не удаляем, в `spec.md` ставим `**Status: dropped** — причина: ...`. История решений.

### Образец 001-bootstrap

Собирается вечером среды как первая фича и одновременно как пример формата для команды.

`specs/001-bootstrap/spec.md`:
- **Цель:** репа готова к пятничному кодингу.
- **Acceptance:** 5 коллабораторов с write (Егор, Сергей, Алексей, Никита, Стасян) + Андрей; branch protection на main и staging; Godot 4.6.2 проект с 4 рабочими autoload; F5 hot-reload `game_speed.cfg` работает; первый PR `andrey/bootstrap → staging` смерджен.
- **Out of scope:** HexGrid, DialogueManager, любая игровая логика, CI/CD.
- **Owner:** Андрей.

`specs/001-bootstrap/plan.md`: ссылка на HANDOFF.md §5 (структура), §6 (autoload-код), §7 (CLAUDE.md). Дублировать смысла нет.

`specs/001-bootstrap/tasks.md` (T001 … T018) — детально расписан в чате при старте setup'а. Базовая структура:

```
- [ ] T001 [P1] Доступы 5 коллабораторов на TortikP/GameJamProject (write): Егор, Сергей, Алексей, Никита, Стасян
- [ ] T002 [P1] Ветка staging от main (depends T001)
- [ ] T003 [P1] Branch protection main: push только Andrey/Egor, PR-only из staging
- [ ] T004 [P1] Branch protection staging: PR-only, 1 approval (depends T002)
- [ ] T005 [P1] Локально Godot 4.6.2 проект jam-project/
- [ ] T006 [P1] Структура папок из §5, .gitkeep в пустые
- [ ] T007 [P1] .gitignore (Godot 4 + IDE)
- [ ] T008 [P1] scripts/infrastructure/game_speed.gd
- [ ] T009 [P1] scripts/infrastructure/event_bus.gd
- [ ] T010 [P1] scripts/infrastructure/logger.gd
- [ ] T011 [P1] scripts/infrastructure/audio_director.gd (stub)
- [ ] T012 [P1] 4 autoload в project.godot (depends T008-T011)
- [ ] T013 [P1] config/game_speed.cfg стартовый
- [ ] T014 [P1] CLAUDE.md, HANDOFF.md, jam-concept-pitch.md, PROJECT_INSTRUCTIONS.md в корень
- [ ] T016 [P1] README.md краткий в корень
- [ ] T017 [P1] specs/001-bootstrap/{spec,plan,tasks}.md
- [ ] T018 [P1] Initial commit на main (depends T002-T017)
- [ ] T019 [P1] andrey/bootstrap: scenes/main.tscn + EventBus.run_started.emit() в _ready()
- [ ] T020 [P1] PR andrey/bootstrap → staging → ревью Егором → merge (depends T019)
- [ ] T021 [P2] Проверить F5 hot-reload game_speed.cfg
- [ ] T022 [P2] PR staging → main, merge (когда staging стабилен)
```

### Дальнейшие фичи (заготовки)

- `002-hex-grid` — owner Egor (см. §9).
- `003-dialogue-manager` — owner Alexey (см. §9).
- `004-modifier-engine` — owner Sergey (после темы).
- `005-roguelike-loop` — owner Alexey (после темы).
- `006-meta-screens` — owner Alexey (после темы).

Темы заготовок (002, 003) можно разрабатывать в параллель вечером среды или утром четверга. Темы 004-006 — после объявления темы джема, потому что они привязаны к концепту.

## 20. 039-dialogue-triggers — точки интеграции

**Статус (2026-05-03):** PR открыт, ждёт ревью. Реализовано всё из spec.

### Что добавлено

- `scripts/core/dialogue/dialogue_trigger.gd` — value class (`from_dict`, `to_dict`, `validate`).
- `LevelData.dialogue_triggers: Array[Dictionary]` — персистентно в JSON, backward-compatible.
- `EventBus`: новые сигналы `wave_about_to_start(index)` и `level_loaded(level)`.
- `WaveController`: эмитит `battle_started` из `start_level`, `wave_about_to_start` перед snapshot N>0, `battle_ended(true)` на `level_completed`.
- `scripts/runtime/level_dialogue_director.gd` — autoload. Слушает `level_loaded` → кэширует level; `battle_started` → коннектит хендлеры по уникальным event; `battle_ended` → дисконнектит.
- `WaveTimeline`: `set_dialogue_trigger_markers(triggers, level)` — violet circles в `Mode.EDIT`. Click → `dialogue_trigger_marker_clicked(id)`.
- `scenes/dev/dialogue_trigger_panel.tscn` + `dialogue_trigger_panel.gd` — CRUD sidebar. Сигналы → controller.
- `map_editor_controller.gd`: `_wire_dialogue_trigger_panel`, `_refresh_timeline_dialogue_markers`, CRUD handlers.
- `data/maps/sample_dialogues.json` — smoke-уровень, 5 триггеров.

### Точка интеграции с 040 (wave-skill-choice)

040 должен добавить в `EventBus`:
```gdscript
signal skill_offer_about_to_open(wave_index: int, ...)
signal skill_offer_closed(wave_index: int, ...)
```
Director подключится к ним автоматически когда trigger `event` = `"skill_offer_about_to_open"` / `"skill_offer_closed"` встретится в level JSON. До мержа 040 — warn-once в лог, триггеры мёртвы, остальные работают.

### Известные ограничения (post-jam)

- Editor: ConfirmModal не задействован для Delete (прямой emit сигнала). Добавить при наличии времени.
- Markers: tooltip при hover — не реализован (P3, cut из scope). Позиция marker Y считается от `BAR_Y - ANCHOR_RADIUS - 6` — если добавятся anchors другого размера, пересмотреть.
- `_refresh_timeline_dialogue_markers()` ищет Timeline по hardcoded path `VBox/TimelineRow/Timeline` внутри WavePanel — хрупко если WavePanel перестроится.
