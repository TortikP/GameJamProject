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
6. All tunables live in `config/game_speed.cfg`. F5 reloads it live.

### Content
7. Modifiers, enemies, spells, dialogues are JSON files in `data/`.
   Programmers build engines; designers fill data files.
8. Don't hardcode content in GDScript. If a modifier needs new code, that's
   a new modifier *type*, not a new modifier.

### Naming
- Files: `snake_case.gd`, `snake_case.tscn`
- Classes (`class_name`): `PascalCase`
- Signals: `snake_case` past tense (`battle_started`, `wave_spawned`)
- Constants: `SCREAMING_SNAKE_CASE`
- Private members: `_leading_underscore`

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
| `cat > file.gd << 'HEREDOC'` для записи GDScript — bash single-quoted heredoc сохраняет `\\n` как литеральный `\n`, `\\"` как `\"`, итого escape-последовательности в строках GDScript ломаются и Godot выдаёт Parse error. | Писать GDScript файлы через `python3 -c "with open(...) as f: f.write(content)"` или через `create_file` tool. Никаких bash heredoc для .gd файлов. |
| `Array[CustomClass]` (типизованный массив с пользовательским классом) — Godot 4.6 при присваивании `arr[i] = value` делает строгую проверку, и сюрприз: **даже plain `Array` иногда отказывается принять `Resource`-подкласс**, если значение пришло через Variant-границу (`Dictionary.get()`, duck-typed call на `Node` без `as`-каста, параметр функции с типом `CustomClass`). Падает с `Invalid assignment of index 'N' (on base: 'Array' or 'Array[X]') with value of type 'Resource (X)'`. | Кувалда: `var _store: Dictionary = {}` вместо Array. У словаря значения не типизуются совсем. Доступ `_store[i] = v` / `_store.get(i, null)`. На границах функций — параметры без типа (`func set(i: int, v) -> void`) либо явно `Variant`. Принимаем потерю автокомплита. Для джемного кода — это меньшее зло. |
