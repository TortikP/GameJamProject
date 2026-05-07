<!--
  ============================================================================
  JAM-ERA ARCHIVE ABOVE — ACTUAL RULES BELOW
  ============================================================================

  Этот файл был расшарен публично как пример работы с Claude в режиме джема.
  Та версия сохранена ниже как исторический артефакт. Текущие правила —
  под маркером ACTUAL_RULES_BELOW в самом низу.

  Claude: пролистай до маркера `<!-- ACTUAL_RULES_BELOW -->`. Всё выше — архив,
  не используй как источник правил. Применяй только правила под маркером.
  -->

# Jam Project — Conventions (jam-era archive)

> **Архивный документ.** Это снимок правил времён 72-часового джема. Сохранён
> как публичный пример. Для актуальных правил — пролистай до маркера
> `<!-- ACTUAL_RULES_BELOW -->` в конце файла.
>
> `PROJECT_INSTRUCTIONS.md` в корне репо тоже архивный — не использовать.

## Context
Post-jam extended development. Theme («Метаморфозы») announced; concept settled — see [`docs/design/`](docs/design/) (`VISION.md`, `PILLARS.md`, `aspects.md`, `DECISIONS.md`). Team of 7 (6 in repo, +Katya outside).

**Current concept** (1-line): turn-based hex tactics, story-driven roguelike with meta-progression. Heroine is an escapist who jumps into fantasy worlds; killing enemies absorbs their **aspects** — a meta-resource of identity that gates dialogue branches, builds, and endings. Aspect progress hidden by default (Pillars-style). Builds are thematic (office / meme / fantasy / psycho / detective), not mechanical (damage / shield / AOE).

**Authoritative state:** [`docs/design/DECISIONS.md`](docs/design/DECISIONS.md) (ratified decisions), [`docs/FEATURES.md`](docs/FEATURES.md) (lazy-backfill registry of what actually works). The pre-theme `jam-concept-pitch.md` was deleted 2026-05-07 (DECISIONS) — much of it never materialized; do not pull facts from old commits of that file.

## Stack
- Godot 4.6.2 (patch versions must match across team)
- GDScript only
- JSON / .tres for content
- Desktop builds (web only if time permits Saturday)

## Design pillars

These two override implementation convenience. PRs that violate them get a hard re-think before merge. Full discussion in `THEME_PLAN.md` §1.5.

1. **Full information visibility.** The player sees everything needed to make an informed (or least-bad) tactical decision *before* committing to it. HP, statuses, incoming threats with damage numbers, ability previews, castability — all on screen, no hidden RNG, no surprise damage. Loss should feel like "I misjudged", never "the game cheated me".

2. **Player–monster symmetry.** Monsters use the same `Actor` and `Ability` (`Target × Effect × Modifier`) contracts as the player. AI is a controller that picks actions from the same primitives the player uses (`grid.move_actor`, `ability.cast`) — not a parallel system. The implicit test: you should be able to take control of any enemy and play it as a character.

What this forbids in practice: enemy-only damage paths, AI-only fields on Actor, hidden RNG rolls behind the scenes, attacks that resolve without a telegraph, "mysterious" status effects without UI representation. When in doubt, ask "would the player accept losing 30% HP to this without warning?" — if no, fix the visibility before merging.

## Visibility doctrine

Pillar 1 only works if information is **read at default zoom in 0.3 seconds**. A 9-pixel HP digit on a 1280-wide screen is invisible during play even if it's technically on screen. Rule of thumb: if you have to lean toward the monitor or pause to parse a number, it's too small.

Concrete:

- **All in-world numeric/textual UI** (HP digits, HP bar, damage telegraphs, floating combat numbers, status icons over actors) must use sizes from `UiTheme.BAR_*_OVERHEAD` and `UiTheme.FS_NUM_*`. **No hardcoded `FONT_SIZE = 9` constants in scripts.** If a new size is needed, add a named constant to `UiTheme` first.
- **All in-world text wears a strong dark outline** via `UiTheme.apply_world_text_outline(label)` (Labels) or `draw_string_outline(...)` with `UiTheme.WORLD_TEXT_OUTLINE_*` constants (custom `_draw()`). Reason: combat text sits over hex grid + actor sprites + VFX simultaneously; without outline it disappears on busy frames.
- **Default size > minimum size.** When choosing between "fits the layout" and "reads at a glance", choose readability. If layout breaks, the layout is wrong, not the font.
- **Crit and incoming-damage numbers go even bigger** — `FS_NUM_HUGE` for crits, `BAR_FONT_SIZE_OVERHEAD` for telegraphs. These are the moments the player most needs to see clearly.
- This rule applies retroactively — when you touch any presentation file, audit any hardcoded sizes inside and convert to UiTheme constants in the same PR.

## Hard rules

### Architecture
1. scripts/core/ knows nothing about specific textures, audio files, or scenes.
2. scripts/presentation/ depends on core, not the other way around.
3. Autoloads (GameSpeed, EventBus, AudioDirector, UiTheme) are accessible from anywhere. Stateless logging via `GameLogger` — preload-only utility, see traps table.
4. Cross-system communication goes through EventBus signals, not direct references.
5. UI colors and spacing — only via `UiTheme.X`. No `Color(...)` inline in `scripts/presentation/`. New stylebox? `UiTheme.make_*_stylebox()`. New label kind? Extend `UiTheme.apply_label_kind`.
6. Hex polygon geometry — via `HexGeometry.flat_top_polygon(layer.tile_set.tile_size)` (preload `scripts/infrastructure/hex_geometry.gd`). No hardcoded `RADIUS = 60.0` in overlays — `tile_size` in the .tres is the single source of truth, polygons inscribe into the tile bbox at draw time. See spec 022.
7. **One TileSet — `scenes/arena/tilesets/hex_terrain.tres`** (`tile_shape = HEXAGON`, `tile_size = Vector2i(128, 80)`). Source 0 = `godmode_atlas.png` (Katya's hand-drawn green grass tile at 128×80 — the default visible floor everywhere; tagged `tile_kind = &"forest"` for legacy reasons). Source 1 = `hex_atlas.png` — 8 painterly variant tiles at 128×80 stitched horizontally: 2× `forest`, 3× `heaven`, 2× `lava` (effect_id `damage_zone`), 1× `ice`. Used in editor for marking tile_kind variations and for visually mixing biomes. All scenes (godmode procedural sandbox, map editor, every loaded level) reference this single .tres file. Per 032: `scenes/dev/godmode_terrain.tres` was deleted in the consolidation PR — adding a second tileset re-introduces shape-mismatch bugs (B-003 origin) and divergent neighbour topology (`*_SIDE` enums). Don't.

### Timing
5. NO hardcoded timer values. Use `GameSpeed.wait(section, key)` or read
   `GameSpeed.get_value(...)`. PRs with bare `create_timer(0.5)` are rejected.
6. All tunables live in `config/game_speed.cfg`. F5 reloads it live.

### Content
7. Modifiers, enemies, spells, dialogues are JSON files in `data/`.
   Programmers build engines; designers fill data files.
8. Don't hardcode content in GDScript. If a modifier needs new code, that's
   a new modifier *type*, not a new modifier.
9. Don't hardcode player-facing text anywhere. Visible strings in scenes,
   scripts, data files, UI, popups, toasts, tooltips, maps, enemies, skills,
   and dialogues must use stable localization keys that exist in both
   `data/localization/en.json` and `data/localization/ru.json`. Language-neutral
   values like pure numbers, timers, icon glyphs, ids, paths, and debug-only
   internal tokens are the only normal exceptions. See
   `data/localization/README.md`.

### Naming
- Files: `snake_case.gd`, `snake_case.tscn`
- Classes (`class_name`): `PascalCase`
- Signals: `snake_case` past tense (`battle_started`, `wave_spawned`)
- Constants: `SCREAMING_SNAKE_CASE`
- Private members: `_leading_underscore`

### Accepted compromises (post-jam debt)

The following violate the "core knows nothing of presentation" rule above. They are
accepted for the duration of the jam and tracked in `specs/012-ultrareview/findings.md`
(F-004, F-005). Don't rewrite them in 72h — the cost is ~40 file touches across
HexGrid, registry, controllers.

- **`Actor extends Node2D`** (`scripts/core/actors/actor.gd`) — core entity carries
  presentation semantics (`position`, sprite-children expectation in subclasses).
  Post-jam: `Actor extends Resource` (data) + `ActorView extends Node2D` (visual binding).
- **`HexGrid extends Node2D`** with `@export var tile_map_layer / vfx_overlay`
  (`scripts/core/arena/hex_grid.gd`) — same shape; core class holds direct rendering nodes.
  Post-jam: `HexGrid` for `Vector2i` math + `HexGridView` for tile rendering.

New code in `scripts/core/` must still NOT introduce additional Node2D dependencies
or presentation references. The compromise is grandfathered, not a license to expand.

## Module ownership — claim-on-PR

We don't pre-assign owners. You **claim** a module by opening the first PR
(or first spec) for it. Whoever lands first owns the public API. Until claimed,
anyone can take it — say so in chat first so two people don't pick the same
thing in parallel.

After claim: rename or break the public API → PR with `breaking:` prefix +
claimer's approval. Same rule as before, just no upfront table.

### Suggested lanes (skills, not contracts)

Hints — pick from here if you don't know what to grab. Not binding.

| Module | Suggested lead |
|--------|----------------|
| Hex arena, battle loop, enemies | Egor (strongest Godot dev) |
| Spell-craft, modifier engine | Sergey |
| Roguelike loop, waves, portal, meta-screens UI | Alexey |
| Dialogue engine | any programmer |
| Dialogue content, flavor texts, voice direction | Nikita |
| UX integration, polish, audio direction, tone | Andrey |
| Balance, modifier content, playtest | Stasyan |
| Tiles, portraits, icons, VFX | Katya (file exchange, no repo) |

### Currently claimed

Append yourself when you start a feature.

| Feature / module | Claimer |
|---|---|
| 001-bootstrap, infrastructure (autoloads, GameSpeed config) | Andrey |
| 002-hex-grid (spec) | Egor |
| 003-dialogue-manager | Andrey |
| 007-skill-system (Skill, Ability, Area, Effect, ParameterModifier engines) | Egor |
| 009-ui-kit (spec; Phase 4 blocked on 007 + 008) | Andrey |
| 018-tile-objects (data class + registry, HexGrid wiring, EventBus signals) | Sergey (spec) → Andrey (impl) |
| 021-skill-system-v2 (loc keys, mood, level scaling, sound/animation, entity→actor) | Egor |
| 024-wave-editor (LevelData waves, WaveController, WaveTimeline, RunScore, push-out) | Andrey |
| 032-controller-refactor (godmode_controller split into 8 modules, tileset consolidation) | Andrey |
| 038-mood-counter (player narrative tracker driven by equipped skills, JSON mood vocab rename) | Egor |
| 041-effect-create-entity (CreateEffect impl: object/actor summon + summoned status) | Egor |
| 039-dialogue-triggers (LevelData triggers, LevelDialogueDirector, WaveTimeline markers, DialogueTriggerPanel editor) | Andrey |
| 040-wave-skill-choice (per-wave skill_offer schema, SkillOfferController autoload, modal + card UI, WavePanel section, WaveTimeline markers) | Andrey |
| 045-intro-cutscene (CutscenePlayer + IntroDirector autoloads, office_intro level, is_intro semantics) | Andrey |
| 048-corpse-absorption (CorpseManager autoload, Corpse scene, GodmodeCamera multi-layer shake, WaveController final-wave hook, biome tint) | Egor |
| 049-ux-rehaul (HexTooltip, EnemyDetailsPanel, EnemyMovePath, SkillFormatter human, TelegraphHex icon, CastRangeOverlay grey-out, kill ActorInspector + selection) | Egor |

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
- Claude push access: only to `<user>/*` branches and PRs to `staging`. Never to main directly.

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

- Don't edit code files directly. Edit JSON in `data/` and ask a programmer
  if a new modifier *type* is needed.
- Don't commit large unoptimized assets. Compress sprites before committing.

## Claude usage

- Each Claude session starts with reading this file and `HANDOFF.md`.
- For unfamiliar files, Claude reads them before suggesting changes.
- If Claude suggests an abstraction "for the future" — reject it. We have 72 hours.
- Network constraint: from Claude's container, `github.com` works (git ops) but `api.github.com` is blocked. PR creation/merging is done by humans in the browser via the URL Claude prints from `git push` output.

## Speed > polish > scope

If running out of time on Saturday:
1. Cut scope first.
2. Ship what's stable.
3. Polish only what's already working.
4. Never push broken code to main on Saturday afternoon.

## Known Godot 4.6 traps

A growing list of GDScript / Godot 4.6 gotchas we've actually hit. Read this before writing GDScript — Claude's training data has more Godot 3 examples than 4, so don't trust pattern memory blindly. **When in doubt, link to `docs.godotengine.org/en/4.6/classes/class_X.html` and read the actual signature.**

When we hit a new trap, append a row here in the same PR that fixes it.

| Trap | Fix |
|---|---|
| `func log(...)` in a class — GDScript resolves bare `log(...)` calls to `@GlobalScope.log` (natural logarithm, 1 arg). Defining a method `log` doesn't shadow it. | Rename the method to `_log` or anything else. Don't try to "override" global math functions. |
| **Logger / utility classes**: `class_name Logger` collides with an internal Godot C++ class `Logger` (defined in `core/io/logger.h`). The parser resolves `Logger.method()` to that engine class, not your script, and you get `Static function "info()" not found in base "GDScriptNativeClass"` plus a "shadows a native class" warning. Same shape of error appears with autoload registration of utility classes. Renaming to anything non-colliding (e.g. `GameLogger`) is the only reliable fix. | For any stateless utility script: don't use names that match Godot internals (Logger is one of them — avoid). Use a project-prefixed name (`GameLogger`, `JamMath`, etc.). Don't use `class_name` or autoload — instead, explicit preload at the top of consumers: `const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")`. Methods are `static func name(...)` (multi-line — inline form misbehaves in 4.6). This pattern doesn't depend on the global class registry. |
| `var x := load("res://path/to/script.gd").new()` — `:=` не может вывести тип, `load()` возвращает `Resource`, `.new()` — `Object`. Godot падает с "Cannot infer the type". | Явная аннотация: `var x: Object = load(...).new()`. |
| `var x := func_returning_variant(...)` — функция с `-> Variant` или duck-typed call (`node.has_method` → `node.method()`) возвращает `Variant`, `:=` пытается вывести тип, варнинг "The variable type is being inferred from a Variant value" с включённым warnings-as-errors → parse error. | Явная аннотация `var x: Variant = ...`. Альтернатива — переписать функцию-источник, чтобы возвращала конкретный тип с sentinel-значением (`Vector2.INF` вместо `null`). Для джем-скорости — Variant аннотация дешевле. |
| **`_ready` order trap.** Godot вызывает `_ready` снизу-вверх по дереву сцены (дети раньше родителей), а среди siblings — в порядке появления в .tscn. Если node A в `_ready` вызывает метод node B из соседнего sub-tree который идёт **позже** в дереве — у B `@onready` ещё `null`. Краш: `Invalid assignment of property 'text' on a base object of type 'Nil'`. Реальный пример: `GodmodeController` (дочерний root'а, идёт раньше) вызывает `PlayerStatusPanel.bind_player()` из `HUD/` (идёт позже) — у PSP `@onready var _name_label` ещё не resolved. | Защита на стороне callee: первой строкой `if not is_node_ready(): ready.connect(method.bind(args), CONNECT_ONE_SHOT); return`. Это работает для любых вызовов из чужого `_ready` без перестройки порядка нод в .tscn. Не использовать `call_deferred` в caller'е — это перенесёт проблему на следующий call-site. |
| `cat > file.gd << 'HEREDOC'` для записи GDScript — bash single-quoted heredoc сохраняет `\\n` как литеральный `\n`, `\\"` как `\"`, итого escape-последовательности в строках GDScript ломаются и Godot выдаёт Parse error. | Писать GDScript файлы через `python3 -c "with open(...) as f: f.write(content)"` или через `create_file` tool. Никаких bash heredoc для .gd файлов. |
| `Array[CustomClass]` (типизованный массив с пользовательским классом) — Godot 4.6 при присваивании `arr[i] = value` делает строгую проверку, и сюрприз: **даже plain `Array` иногда отказывается принять `Resource`-подкласс**, если значение пришло через Variant-границу (`Dictionary.get()`, duck-typed call на `Node` без `as`-каста, параметр функции с типом `CustomClass`). Падает с `Invalid assignment of index 'N' (on base: 'Array' or 'Array[X]') with value of type 'Resource (X)'`. | Кувалда: `var _store: Dictionary = {}` вместо Array. У словаря значения не типизуются совсем. Доступ `_store[i] = v` / `_store.get(i, null)`. На границах функций — параметры без типа (`func set(i: int, v) -> void`) либо явно `Variant`. Принимаем потерю автокомплита. Для джемного кода — это меньшее зло. |

<!-- ============================================================================ -->
<!-- ACTUAL_RULES_BELOW                                                           -->
<!-- ============================================================================ -->

# Conventions — actual rules

> Это раздел с **текущими** правилами. Всё выше — архив джем-эпохи, держится для
> исторической справки и для людей, пришедших по старым публичным ссылкам.
> При работе над проектом используй только правила из этого раздела.

## Контекст

Пост-джем расширенная разработка. Команда: 7 человек (Андрей, Егор, Никита, Сергей, Алексей, Стасян, Марк) + Катя через файлообмен. Сроков нет, идёт работа на качество.

Stack: Godot 4.6.2 + GDScript, JSON / .tres для контента. Десктоп-сборки.

## Где какая память живёт

Источники истины — **в этом порядке** при поиске информации:

- **`docs/design/`** — концептуальная память: почему так. Содержит:
  - `PILLARS.md` — дизайн-пилларсы (фильтр для всех фич)
  - `DECISIONS.md` — журнал ратифицированных решений (не редактируется, отменяется новой записью)
  - `OPEN-QUESTIONS.md` — открытые вопросы с уникальными `Q-NN`
  - `GLOSSARY.md` — стабильные термины
  - `VISION.md`, `REFERENCES.md`, `aspects.md` — концепция, отсылки, конкретные дизайн-доки
- **`docs/FEATURES.md`** — реестр фич с текущим статусом (lazy backfill — заполняется когда трогаем фичу).
- **`docs/agents/`** — система агентов с роутингом через `@`-меншны. См. ниже.
- **`planning/plan.md`** — текущий план спеков и задач.
- **`specs/NNN-name/`** — исторический лог решений по конкретным фичам (что планировали в момент X).
- **Этот файл (`CLAUDE.md`)** — конвенции, которые не меняются от фичи к фиче (архитектура, naming, git workflow).

## Система агентов

Агент — `.md`-файл в `docs/agents/`, меняющий фрейм Claude (тон, фокус, запреты, обязанности) под конкретный тип задачи. Адресуется через `@<имя>` в любом месте сообщения:

```
@design-keeper зафиксируй, что мы решили скрывать прогресс аспектов
```

Полное описание системы — `docs/agents/README.md`. Что важно знать всегда:

- **Явный тэг `@<имя>`** — Claude читает соответствующий `.md`-файл и работает в этом фрейме до конца ответа, потом возвращается в дефолтный режим («мозг»).
- **Без тэга, но запрос ложится на агента** — Claude спрашивает: «как @X? или @Y?».
- **Без тэга и без явного матча** — Claude отвечает как мозг (этот файл + `docs/design/`).
- **Текущие агенты** — список в `docs/agents/README.md`. Сейчас рабочий: `@design-keeper`.

## Конвенция «Обсуждали:» вместо «Овнер:»

Овнеры в спеках, доках и решениях **не указываются**. Вместо этого — поле «Обсуждали:» с маркером `(идея)` для автора инициативы. Пример:

```
Обсуждали: Андрей (идея), Сергей, Никита.
```

Овнерство закрепляется только по явному запросу Андрея или мозга. Каждый берёт задачу которая нравится. Полное описание — DECISIONS, запись 2026-05-05.

## Hard rules

Эти правила пережили джем без изменений и продолжают действовать. Полные секции с деталями — выше в архивной части (см. «## Hard rules»). Кратко:

### Архитектура
- `scripts/core/` ничего не знает о текстурах, аудио, сценах.
- `scripts/presentation/` зависит от core, не наоборот.
- Cross-system communication — через EventBus сигналы, не прямые ссылки.
- Autoloads (GameSpeed, EventBus, AudioDirector, UiTheme) доступны отовсюду. Логирование — через `GameLogger` (preload, не autoload).
- UI цвета и spacing — только через `UiTheme.X`. Никаких `Color(...)` inline в `scripts/presentation/`.
- Геометрия гексов — через `HexGeometry.flat_top_polygon(layer.tile_set.tile_size)`. Никаких хардкоженных `RADIUS` в overlay'ях.
- **Один TileSet** — `scenes/arena/tilesets/hex_terrain.tres`. Не заводить второй (см. spec 032 про последствия).

### Тайминг
- Никаких хардкоженных таймеров. Только `GameSpeed.wait(section, key)` или `GameSpeed.get_value(...)`.
- Все tunables живут в `config/game_speed.cfg`. F5 перезагружает live.

### Контент
- Modifiers, enemies, spells, dialogues — JSON в `data/`. Программисты пишут движки, дизайнеры заполняют данные.
- Не хардкодить контент в GDScript. Если модификатору нужен новый код — это новый *тип* модификатора.
- Не хардкодить player-facing текст. Все видимые строки — через локализационные ключи в `data/localization/{en,ru}.json`. См. `data/localization/README.md`.

### Naming
- Файлы: `snake_case.gd`, `snake_case.tscn`
- Классы (`class_name`): `PascalCase`
- Сигналы: `snake_case` past tense (`battle_started`, `wave_spawned`)
- Константы: `SCREAMING_SNAKE_CASE`
- Приватные члены: `_leading_underscore`

### Accepted compromises (legacy джем-долг)

`Actor extends Node2D` и `HexGrid extends Node2D` нарушают «core knows nothing of presentation». Это grandfathered долг, не лицензия расширять. Новый код в `scripts/core/` не должен вводить дополнительные Node2D зависимости или презентационные ссылки.

## Git workflow

Two-tier branching:
- **`main`** — protected. Прямой push только Андрей и Егор. Стабильный, deployable. PR в main только из `staging`.
- **`staging`** — интеграционная ветка. Feature PR'ы мерджатся сюда. Ревью обязательно.
- **`<user>/<short-name>`** — индивидуальная работа. Создаётся от `staging`, мерджится через PR. `<user>` — lowercase имя автора.

Поток:
1. `git checkout staging && git pull && git checkout -b <user>/your-thing`
2. Работаешь, коммитишь, пушишь.
3. PR `<user>/your-thing → staging`. Ревью человеком (Claude может помочь, человек подписывает).
4. Периодически: Андрей или Егор открывает PR `staging → main`, smoke-tests, мерджит.

Claude push access: только в `<user>/*` ветки и PR в `staging`. Никогда напрямую в main.

## Don't

- Не рефакторить файлы вне текущей задачи. Если cruft мешает — отдельный `chore:` коммит или запись в tech-debt.
- Не переименовывать публичные API без согласия claimer'а модуля.
- Не пушить в main напрямую.
- Не добавлять библиотеки/аддоны без team agreement.
- Не байпасить GameSpeed для таймингов.
- Не байпасить EventBus для cross-module коммуникации.
- Не хардкодить контент в скриптах.
- Не предлагать абстракции «на будущее». Если есть второй конкретный use-case — обсудим.

## Don't (для не-кодеров)

- Не редактировать код напрямую. Редактировать JSON в `data/`, спросить программиста если нужен новый *тип* модификатора.
- Не коммитить большие неоптимизированные ассеты. Сжать спрайты перед коммитом.

## Claude usage

- Каждая сессия Claude начинается с чтения этого файла (актуальной части под маркером) и `planning/plan.md`.
- Для незнакомых файлов Claude читает их перед предложением изменений.
- Network constraint: из контейнера Claude `github.com` работает (git ops), но `api.github.com` заблокирован. PR создание/мердж делает человек в браузере по URL'у который Claude печатает из `git push` output.

## Known Godot 4.6 traps

Список traps живёт в архивной части файла выше (см. «## Known Godot 4.6 traps»). Список актуален — Godot 4.6 не сменился, traps те же. Когда ловим новый — добавляем строку в той же таблице тем же PR'ом, который трап чинит.
