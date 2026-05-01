# 012-ultrareview — spec

**Owner:** Egor (handed off from Andrey 2026-05-01 — partial audit done, see Handoff section)
**Status:** In progress — partial audit, ~30% coverage. Continuation required.

---

## Handoff (2026-05-01, andrey/Claude → egor)

**Snapshot SHA:** `13b4065` (Merge PR #36 `egor/008-plan-tasks` into staging — последний коммит на момент захода в аудит).
**Branch:** `andrey/012-audit-pass`. Pair-work, не переименовываем — коммить в неё. Если хочешь свой prefix — checkout новой ветки от текущей head, но истории всё равно мало, не критично.

### F-D0 (уже зафиксировано, до старта аудита)

PR #35 (012/spec → staging) был замержен только с первым коммитом (`40da41c`). Второй (`b1c512e`) — D13 leak/resource hygiene + AC-A9 manual профайлер от Egor + AC-A10 cross-ref правила — push прошёл уже после merge. В staging его не было. Я **cherry-pick'нул его в эту ветку** (`6092c49`) — D13/AC-A9/AC-A10 теперь в спеке, не теряются. Когда мерджим 012 в staging — придут вместе.

### Что покрыто (partial)

| Domain | Status | Findings |
|---|---|---|
| D1 — core/presentation isolation | ✅ done | 2 P2 |
| D2 — EventBus discipline | ⚠️ partial | 1 P1 + 2 P2; signal-naming clean. Cross-module direct refs не докопал (godmode→autoloads OK, но другие presentation файлы не прошёл сквозным грепом). |
| D3 — UiTheme единственный источник | ✅ done | 2 P2 + 5 P3 |
| D4 — GameSpeed для timings | ✅ done | 3 P2 |
| D5 — content в `data/` | ✅ done (light) | 2 P3 (accepted compromises) |
| D6 — naming conventions | ❌ not started | mechanical, ~5 минут |
| D7 — visibility doctrine | ✅ done | clean — 25 файлов presentation/ юзают UiTheme labels, 72 refs, draw_string_outline везде где нужно |
| D8 — Pillar 1 (full info visibility) | ⚠️ touched | 1 P1 (F-016) родился отсюда — combat numbers fully dead. Domain-pass не закончен. |
| D9 — Pillar 2 (player-monster symmetry) | ❌ not started | теперь у тебя в 008 реальный AI код, есть что проверять |
| D10 — Godot 4.6 traps | ❌ not started | mechanical, по строке trap-таблицы один grep — ~20 минут |
| D11 — spec ↔ impl drift | ❌ not started | 11 spec.md прочитать, для каждого проверить AC vs staging — самый трудоёмкий, ~2 часа |
| D12 — dead code / orphan scenes | ⚠️ partial | 3 кандидата найдены, нужен sweep всех presentation/ + scenes/ui/ |
| D13 — leak / resource hygiene | ❌ not started | mechanical greps по 7 подпунктам D13.a–D13.g (см. spec ниже) |

### Preliminary findings (НЕ финальный формат — раскладывать в `findings.md` по AC-A1)

Нумерация условная (`F-D?-NAME`) — в финальном `findings.md` дай свой `F-001`, `F-002` подряд. Это просто заметки.

#### P1 (критическое, **в 013-refactor-wave-1**)

- **F-D2-COMBAT-NUMBERS-DEAD** — `scripts/presentation/floating_number_layer.gd` целиком dead receiver:
  - Listen'ит `EventBus.damage_dealt` / `EventBus.heal_done` — этих сигналов в EventBus нет (32 сигнала, ни одного из этих).
  - `.spawn()` directly никто не вызывает (grep по godmode_controller, damage_effect.gd, heal_effect.gd, всему presentation/ — пусто).
  - FloatingNumberLayer instance'ится в `scenes/dev/godmode.tscn:44`, но в рантайме никогда не получает событий и никогда не отрисовывает числа.
  - **→ floating combat numbers полностью нефункциональны в актуальном геймплее.**
  - Нарушает Pillar 1 (full info visibility): игрок не видит damage numbers когда наносит/получает урон.
  - Точка остановки моего аудита — проследил до `scripts/core/actors/actor.gd:69` (`take_damage` эмитит локальный `damaged` signal на актере, но не на EventBus).
  - Fix-варианты для 013:
    - (a) Добавить `damage_dealt(target_id: StringName, amount: int, world_pos: Vector2)` в EventBus, эмитить из `Actor.take_damage` (требует знать world_pos — `actor.position` подойдёт). Layer уже подписан, ничего больше менять не надо.
    - (b) `godmode_controller` подписывается на `actor.damaged` каждой сущности и сам зовёт `floating_layer.spawn(...)`. Минусы: layer становится pull, godmode держит ref на layer.
    - (c) `EventBus.floating_number_requested(world_pos, amount, kind)` + emit'ы из `damage_effect.gd` / `heal_effect.gd`. Самый чистый, но требует знать pos в effect — обычно есть через target.

#### P2 (архитектурный долг, **в 014-refactor-wave-2**)

- **F-D1-ACTOR-NODE2D** — `scripts/core/actors/actor.gd:2` `extends Node2D`. Core сущность с visual-семантикой (`position`, Sprite2D-children). Pragmatic compromise для джема. Post-jam refactor: split в `Actor extends Resource` (data) + `ActorView extends Node2D` (визуал).
- **F-D1-HEXGRID-NODE2D** — `scripts/core/arena/hex_grid.gd:2,21-22` `extends Node2D`, `@export var tile_map_layer: TileMapLayer`, `vfx_overlay: TileMapLayer`. Тот же compromise. Post-jam: `HexGrid` (logic, Vector2i + offset math) + `HexGridView` (rendering).
- **F-D2-FNL-PARENT-WALK** — `scripts/presentation/floating_number_layer.gd:62-72` `_resolve_actor_pos` walks parent chain looking for ActorRegistry sibling. Comment `Real wiring happens in 007` — но 007 уже мерджен. Это TODO-завис. Если фиксим F-D2-COMBAT-NUMBERS-DEAD по варианту (a) — весь `_resolve_actor_pos` исчезает (pos приходит готовый).
- **F-D3-CYAN-LITERAL** — `scripts/presentation/arena_demo_controller.gd:91` `Color(0.05, 0.80, 1.00)` raw cyan. → `UiTheme.SEM_MOVE` или удалить (вероятно debug placeholder).
- **F-D3-INTENT-SHADOW** — `scripts/presentation/intent_arrow.gd:14` `const COLOR_SHADOW: Color = Color(0, 0, 0, 0.55)`. → reference `UiTheme.WORLD_TEXT_OUTLINE_COLOR` (alpha 0.95) или новый `UiTheme.SHADOW_SOFT` constant.
- **F-D4-FN-DURATION-CONST** — `scripts/presentation/floating_number.gd:11-12` `DURATION_MS = 700`, `CRIT_DURATION_MS = 1100`. → `GameSpeed.get_value("ui", "floating_number_duration_ms", 700)` + `..._crit_duration_ms`. Add to `config/game_speed.cfg`.
- **F-D4-TOAST-FADE-IN** — `scripts/presentation/toast_item.gd:44` `0.18` literal fade-in. → `GameSpeed.get_value("ui", "toast_fade_in_sec", 0.18)`.
- **F-D4-TOAST-FADE-OUT** — `scripts/presentation/toast_item.gd:52` `0.20` literal fade-out. → `GameSpeed.get_value("ui", "toast_fade_out_sec", 0.20)`.

#### P3 (косметика / низкий приоритет, **в 015+ если время**)

- **F-D3-TILE-COLORS** — `scripts/presentation/hex_placeholder_builder.gd:18-22` 5 raw tile colors (grass/wall/swamp/acid/fountain). См. F-D12-PLACEHOLDER-DEAD — файл скорее всего к удалению, тогда finding снимается автоматически.
- **F-D3-RUN-SUMMARY-STYLEBOX** — `scripts/presentation/run_summary.gd:109-115` inline `StyleBoxFlat.new()`. См. F-D12-RUN-SUMMARY-DEAD — файл orphan, finding снимается при удалении.
- **F-D3-SLOTBAR-FOCUS** — `scripts/presentation/slot_bar.gd:184-185` magic multipliers `focus.r * 1.3, focus.g * 1.3, focus.b * 0.5`. → `UiTheme.SELECTION_HIGHLIGHT_COLOR` или helper `UiTheme.brighten_for_selection(focus)`.
- **F-D3-SLOTBAR-HOVER** — `scripts/presentation/slot_bar.gd:196` `Color(1.10, 1.10, 1.10) if hovered else Color.WHITE`. → `UiTheme.HOVER_BRIGHTEN` constant.
- **F-D3-PILL-STYLEBOX** — `scripts/presentation/status_icon_strip.gd:97-101` local `_make_pill_stylebox(family)`. → `UiTheme.make_pill_stylebox(family)`.
- **F-D5-DEBUG-SKILLS** — `scripts/presentation/godmode/godmode_controller.gd:166,171,174` hardcoded `&"skill_debug_punch"`, `&"skill_melee_punch"`, `&"skill_knockback_punch"`. Acceptable for dev/debug controller. Post-jam: `data/godmode/debug_skills.json`.
- **F-D5-TAG-MAPPING** — `scripts/presentation/godmode/godmode_controller.gd:722-740` tag→semantic_kind hardcoded match. Closed enum из 008/AC-I4, acceptable. Post-jam: `data/ui/tag_color_mapping.json`.
- **F-D6-CLAUDE-MD-LOGGER** — `CLAUDE.md` §Architecture #3 пишет «Autoloads (GameSpeed, EventBus, **Logger**, AudioDirector, UiTheme)» — но `Logger` не autoload (trap-таблица говорит использовать `GameLogger` через `preload`). Doc drift. Update: «`Logger`» → «`GameLogger` (preload, not autoload — see traps table)». **Не код-finding,** doc-fix.
- **F-D12-PORTAL-DEAD** — `scripts/presentation/portal_transition.gd` + `scenes/ui/portal_transition.tscn`. Никем не preload'ится / не instance'ится (grep по всему scripts/+scenes/ — только селф-ссылки). Dead.
- **F-D12-PLACEHOLDER-DEAD** — `scripts/presentation/hex_placeholder_builder.gd`. `class_name HexPlaceholderBuilder.setup(...)` нигде не вызывается. `arena_demo_controller` имеет inline `_create_placeholder_actor` (line 83) и сам пишет в `tile_map_layer` (line 78). Только doc-comment в `hex_grid.gd:42` ссылается. Dead.
- **F-D12-RUN-SUMMARY-DEAD** — `scripts/presentation/run_summary.gd` + `scenes/ui/run_summary.tscn`. Никем не preload'ится / не instance'ится. `EventBus.run_summary_shown` emit'ится в `run_summary.gd:50` без listener'ов в проекте. Dead.

### Где копать дальше (priority order)

В порядке убывания прибыли:

1. **D11 spec ↔ impl drift** — самый трудоёмкий, но самый ценный. По одному `spec.md` на 001-011, читать AC, сверять со staging. Подозрение что F-D2-COMBAT-NUMBERS-DEAD — не одинокий: где-то ещё AC помечен `[x]` но behavior не реализован.
2. **D10 Godot 4.6 traps** — mechanical, по строке trap-таблицы CLAUDE.md один grep. 6 traps × 1 grep = 6 команд, ~20 минут.
3. **D13 leak / resource hygiene** — твоя домена (D13 primary reviewer + AC-A9 manual профайлер). Совмести с D10 — обе mechanical-grep heavy.
4. **D9 Pillar 2 (symmetry)** — теперь у тебя в 008 реальный AI код. Manekin как minimal Actor — все ли его поля используются? AI и player через одинаковые `grid.move_actor`/`ability.cast`? Hidden enemy-only damage paths? `Actor.take_damage` симметрично применяется к обоим?
5. **D6 naming** — самое лёгкое, на конец.
6. **Доделать D2** — sweep всех presentation/ файлов (за пределами godmode) на cross-module ссылки. Возможно ничего и нет, но проверить надо.
7. **Доделать D12** — sweep всех `class_name X` + `scenes/ui/*.tscn` на orphan: для каждого root scene/класса grep на usages.
8. **AC-A9 manual профайлер** — `profiler-snapshot.md`, ~30 минут в Godot 4.6 при реальном геймплее (волны манекенов + battle loop). Если не успеешь до finalization 012 — переноси acceptance в 013.
9. **Final `findings.md`** — собрать все findings (мои preliminary + твои новые) в формат AC-A1: единая таблица + per-domain секции + per-owner rollup (AC-A3) + per-spec drift (AC-A4) + AC-A5 backlog для 013.

### Замечания

- AC-A6: **read-only.** Если в процессе ловишь желание поправить опечатку — finding в `findings.md`, не fix в этом PR.
- F-D2-COMBAT-NUMBERS-DEAD — самое важное что я нашёл. Если докопаешь и подтвердишь — это первая P1 в 013, перед стасяновским balance.
- F-D6-CLAUDE-MD-LOGGER — doc-fix, можно либо записать как finding (тогда это часть 013/014), либо аккуратно поправить в этом же PR (формально нарушает AC-A6, но 1-строчная дока — обсуждаемо). На твоё усмотрение.
- Branch у тебя есть pull rights (project rule: pair-work). Просто `git fetch && git checkout andrey/012-audit-pass` и продолжай.

---

## Цель

Закончили 11 фич за ~50 часов (001-007, 009-011 — код в staging; 008 — спека). Нужен audit-pass до того как Стасян начинает balance-tuning, а команда — финальный polish-sprint в субботу.

Цель — собрать список нарушений правил `CLAUDE.md`, presentation-coupling, hardcoded content, дублирующейся логики и Godot 4.6 traps в **один документ** (`findings.md`), с severity и owner-tag, чтобы потом точечно разнести по 013+ refactor-PR'ам.

**Read-only.** Этот PR не правит ни строки кода и ни одного JSON. Все фиксы — в 013, 014, ...

Это не «pull-request review» в стиле GitHub — это сводный audit по всему staging как whole, с cross-cutting concerns которые нельзя увидеть в одном PR-ревью (например: «8 файлов в presentation/ имеют hardcoded `font_size` — все надо в `UiTheme`»).

## Зачем сейчас, а не на старте

- Большая часть проблем прорастает на стыке фич (007 ↔ 009 ↔ 011, godmode controller от 004 vs UI Kit от 009, CRT post-fx от 010 на чужие сцены).
- Visibility doctrine добавлена в `CLAUDE.md` ретроспективно (после 009/010) — нужно прогнать audit по всем уже сделанным presentation-файлам, не только новым.
- 008-impl ещё не написан Сергеем — зачищая мусор сейчас, даём ему чище базу.
- Стасян начинает balance в субботу — не должен править hardcoded modifier values если они внезапно остались в `.gd`.
- Cheaper to find dead code на 50-часовой кодбазе, чем на 70-часовой.

## Scope аудита (что покрываем)

| ID | Домен | Источник правила | Объём проверки |
|---|---|---|---|
| **D1** | Core/Presentation isolation | `CLAUDE.md` §Architecture #1-2 | Все `scripts/core/*.gd` — поиск импортов/зависимостей от `scripts/presentation/*` или `scenes/*`. Должно быть 0. |
| **D2** | EventBus discipline | `CLAUDE.md` §Architecture #4 | Все cross-module вызовы — через `EventBus.<signal>` или `EventBus.<signal>.connect`. Прямые `get_node`/`@onready` ссылки на чужой модуль = finding. |
| **D3** | UiTheme — единственный источник стилей | `CLAUDE.md` §Architecture #5 | grep по `scripts/presentation/` на `Color(`, `font_size`, `add_theme_*_override`, raw `StyleBoxFlat.new()` без `UiTheme.X` / `UiTheme.make_*_stylebox()`. Каждое — finding. |
| **D4** | GameSpeed для всех timings | `CLAUDE.md` §Timing #5-6 | grep по всему `scripts/` на `create_timer(<число>)`, `await get_tree().create_timer`, `Tween.tween_*(<число>)`, `await ... timeout` с literal-числом. Должно быть 0 без `GameSpeed.get_value(...)` или `GameSpeed.wait(...)`. |
| **D5** | Content в `data/`, не в коде | `CLAUDE.md` §Content #7-8 | grep по `scripts/core/` и `scripts/presentation/` на: stringized id скиллов/abilities/dialogues, литералы damage values, ability-arrays / modifier-arrays внутри `.gd`. |
| **D6** | Naming conventions | `CLAUDE.md` §Naming | Все новые файлы и `class_name` — соответствие правилам (`snake_case.gd`, `PascalCase` class, `_leading_underscore` private). Сигналы — past tense. |
| **D7** | Visibility doctrine | `CLAUDE.md` §Visibility doctrine | Все файлы из `scripts/presentation/` где рендерится in-world UI (HP, damage telegraph, status, floating combat numbers, overhead labels): hardcoded `font_size`, отсутствие `UiTheme.apply_world_text_outline(label)`, отсутствие `WORLD_TEXT_OUTLINE_*` в custom `_draw()`. Ретроспективная сверка. |
| **D8** | Pillar 1 — Full information visibility | `CLAUDE.md` §Design pillars | Любая логика с потенциалом «hidden damage»: enemy ability cast без telegraph, RNG в core без UI representation, статусы без icon strip, ability preview не отражает реальное поведение. |
| **D9** | Pillar 2 — Player-monster symmetry | `CLAUDE.md` §Design pillars | `Actor` поля и методы — все ли используются и enemy и player. AI — только через те же `grid.move_actor` / `ability.cast`, никаких enemy-only damage paths. Manekin / Player — на одном API. |
| **D10** | Godot 4.6 traps | `CLAUDE.md` §Godot 4.6 traps | Каждая ловушка из таблицы — grep по codebase: `func log(`, `class_name Logger`, `var x := load(`, `var x := <variant_func>`, bash-heredoc артефакты в `.gd`, `Array[CustomClass]` со cross-Variant assignments, `_ready` order risks (вызовы чужих nodes из `_ready` без `is_node_ready` guard). |
| **D11** | Spec ↔ implementation drift | per-spec AC | Для каждого 001-011: сравнить AC из `spec.md` с состоянием staging. Найти AC которые помечены `[x]` но не работают / поменяли поведение. |
| **D12** | Dead code / orphan scenes | n/a | Файлы под `scripts/` и `scenes/` без референсов из остального проекта (поиск `preload(...)`, `instantiate()`, `class_name` usage, scene root references). Кандидаты на удаление в 013+. |
| **D13** | Leak / resource hygiene (static-pass) | Godot 4.6 lifecycle docs | Static pattern-matching по типичным утечкам Godot. Не заменяет реальный профайлер (см. AC-A9), но ловит большинство проблем до того как они станут заметны. Подпункты: |
| | | | **D13.a Signal lifecycle** — каждый `EventBus.X.connect(...)` / `signal.connect(...)` в эфемерных нодах (битвенные actors, VFX, toasts, floating numbers) — есть ли парный `disconnect` либо `CONNECT_ONE_SHOT`, либо self-удаление через `tree_exiting`. Особое внимание `connect(callable.bind(self))` где self живёт меньше эмиттера. |
| | | | **D13.b Node lifecycle** — каждый `add_child(...)` / `instantiate()` динамической ноды — есть ли ясный путь до `queue_free()`. VFX, projectiles, telegraph hexes, floating combat numbers, toasts. |
| | | | **D13.c Hot-path allocations** — `_process` / `_physics_process` / `_draw` / per-cast код: `load("res://...")` (должен быть `preload` на module-level), `Resource.duplicate(true)`, `get_nodes_in_group(...)` без кэша, `find_child(...)` каждый кадр, new `Array`/`Dictionary`/string concat в горячем цикле. |
| | | | **D13.d Tween / Timer hygiene** — `create_tween()` на ноде которая может умереть до конца твина, `Timer` без `one_shot = true` где it should, `get_tree().create_timer().timeout` connect'ы с captured self. |
| | | | **D13.e Material / shader sharing** — `material.duplicate()` на каждый instance вместо shared `ShaderMaterial`. Проверить overlay/HP-bar/telegraph рендереры. |
| | | | **D13.f Unbounded growth** — массивы/словари которые только растут (combat log без cap, EventBus history если введён, particle pools, undo-стеки). |
| | | | **D13.g RID leaks** — `RenderingServer.<X>_create()` / `PhysicsServer.<X>_create()` без парного `free_rid()`. Скорее всего у нас 0, но проверить. |

## Acceptance criteria

- **AC-A1**: `specs/012-ultrareview/findings.md` создан, формат — единая таблица + поясняющие секции:
  ```
  | ID | Severity | Domain | File:Line | Описание | Proposed fix | Owner | Refactor PR target |
  ```
  Severity:
  - `P1` — баг / нарушение pillar / hidden damage / падение в рантайме / breaks a CLAUDE.md hard rule.
  - `P2` — нарушение CLAUDE.md правила, не падает, но архитектурный долг.
  - `P3` — косметика, naming, comments, dead code без вреда.
- **AC-A2**: Каждый домен D1-D12 имеет explicit секцию в `findings.md`, даже если нарушений нет (тогда — `Clean. N files checked.`). Доказательство покрытия — что не пропустили домен.
- **AC-A3**: Per-owner summary в начале `findings.md`:
  ```
  | Owner | P1 | P2 | P3 | Total |
  ```
  Owner определяется по prefix'у ветки/спеки feature, в которой родился код. Andrey — bootstrap/ui-kit/dialogue/godmode/crt/actors-info; Egor — hex/skill/abilities; Sergey — pending (008 impl ещё не существует, ничего не аудим); Alexey — n/a (ничего не мерджил); Stasyan — JSON content (data/skills, data/modifiers); Nikita — dialogue content (если уже есть JSON).
- **AC-A4**: Per-spec drift (D11) — секция в `findings.md` для каждого 001-011 с одним из:
  - `Spec ↔ impl: aligned` (AC выполнены, поведение совпадает),
  - `Spec ↔ impl: drift, см. F-NN, F-NN` (со списком нарушений),
  - `Spec ↔ impl: not applicable (docs/spec-only)`.
- **AC-A5**: Refactor PR backlog в конце `findings.md`:
  ```
  ### 013-refactor-wave-1: P1 fixes (must-merge before Saturday polish)
  - F-001 (Egor)
  - F-007 (Andrey)
  ...
  ### 014-refactor-wave-2: P2 architecture cleanup (Saturday morning)
  ...
  ### 015-content-migration: hardcoded → data/ (если найдено)
  ...
  ```
  Правила нарезки:
  - **Один owner на PR.** Не смешиваем.
  - **Один concern на PR.** «UI hardcodes» отдельно от «GameSpeed misses» отдельно от «dead code cleanup».
  - **P1 идёт первым,** в 013. P3 — последним, в самом конце или вовсе после джема.
- **AC-A6**: NO code or content files modified. `git diff staging --stat` после 012 показывает только файлы под `specs/012-ultrareview/` и `specs/013-refactor-wave-1/spec.md` (stub). Если в процессе аудита хочется поправить очевидную опечатку в комменте — **записать как finding, не править здесь.** Дисциплина дороже скорости.
- **AC-A7**: Не выдумывать findings ради количества. Если домен чистый — это валидный результат, написать `Clean. N files checked.` и идти дальше. Лучше короткий честный аудит, чем bloated шум.
- **AC-A8**: Findings — actionable, с конкретными `file:line`. Не «UI вообще не очень», а:
  ```
  presentation/health_bar.gd:42 — hardcoded FONT_SIZE = 9, должен быть UiTheme.BAR_FONT_SIZE_OVERHEAD
  ```
  Если file:line невозможен (концептуальное нарушение pillar'а) — указать минимум 2-3 file paths где симптом виден.
- **AC-A9** (manual, не покрывается Клодом): **Профайлер-проход в Godot 4.6 — Egor.** ~30 минут перед finalization 012. Открыть Debugger при реальном геймплее (минимум: 2-3 волны манекенов + portal-transition + battle loop с кастами всех 4 godmode скиллов), снять метрики и приложить как `specs/012-ultrareview/profiler-snapshot.md`:
  - **Monitors tab** — графики `Object/Resource/Node/Orphan Node` count во времени. Растёт между волнами линейно? leak. Стабилизируется? OK.
  - **Memory tab** — top resources by size. Подозрительные дубли (один и тот же Material/Texture несколько раз) → finding в P1/P2.
  - **Profiler tab** — frame budget. Что-то > 16ms на 60fps target? finding в P2 (или P1 если это всё время, не пик).
  - **Visual Profiler** — render bottlenecks если фреймы тяжёлые.
  Snapshot — это просто текстовый файл со скринами или цифрами «orphan count: start 12, после 3 волн 12, OK» / «Object count: 1840 → 2950 за 2 минуты, leak подозрение в X». Не нужен бенчмарк-grade отчёт, нужен sanity-check.
- **AC-A10**: D13 (static leak-pass) — **complementary,** не replacement профайлера. AC-A9 авторитетен по числам, D13 — по паттернам. Если static-pass говорит «leak risk в health_bar`, а профайлер показывает стабильный orphan count — finding остаётся как P3 «потенциальная утечка не проявилась, исправить если будет время». Если профайлер показывает leak а static-pass пуст — значит источник не в типичном паттерне, finding P1 «leak источник неизвестен, нужно investigate в 013».

## Out of scope

- **Любые правки кода или JSON** — это 013, 014, ... См. AC-A6.
- **008-impl review** — Сергей ещё не писал, нечего ревьюить. Спеку 008 (как документ) тоже не ревьюим — это работа Сергея/Егора в его PR.
- **Performance benchmarking** — отдельный concern. У нас есть AC-A9 (sanity-snapshot профайлера от Egor) и D13 (static leak-pass), этого достаточно для джем-тайминга. Полноценные бенчмарки с frame-time distribution, repro-сцены, цифры в xls — out of scope.
- **Visual polish / art critique** — Катя; обсуждение тонов/палитр — в чате, не в findings.
- **Spec sentence-level редактура** — мы аудитим код против спек, не сами спеки. Опечатки в spec-доках — отдельная нудная работа после джема.
- **CLAUDE.md правила сами по себе** — если правило кажется кривым, это discussion в чате/PR-комментах, не findings. Findings — только нарушения существующих правил.
- **Тесты / unit-test coverage** — у нас их нет и не вводим в этом аудите.
- **Refactor sequencing** — финальный порядок 013/014/...: AC-A5 даёт черновик, но решение «что мерджим первым в субботу утром» — Andrey + Egor перед открытием PR'ов, не в 012.
- **Спек-кит ритуалы** (constitution, prompts, и т.д.) — у нас урезанный adapt'нутый workflow, не строимся в полный spec-kit.

## Зависимости

- **Upstream:**
  - `origin/sergey/spec-008-enemy-ai` смержен в staging (закрытие Q-AI-1..6 + `sergey/HANDOFF.md`). До тех пор аудит не стартует — спека 008 в staging устаревшая, и часть D11-проверок завязана на финальный текст 008.
  - Если Сергей затягивает — Andrey принимает решение: либо ждём, либо аудитим без 008-update со ссылкой `[blocked: open PR]` в D11/008 секции.
- **Downstream:**
  - **013-refactor-wave-1** — берётся из AC-A5 backlog (P1 cluster). Открывается после approval 012.
  - **014, 015, ...** — последующие волны, scope и owner определяются также из AC-A5.
- **Параллельно безопасно:** любая активная feature-branch (008-impl, etc.) не блочится. 012 — только чтение staging.

## Координация

- **Andrey:** owner аудита. Делает static-проход D1-D13, открывает PR, тэгит каждого owner'a в комментарии PR с фильтром findings по их модулю (или просит Клода это сгенерировать).
- **Egor:** primary reviewer по D1, D2 (архитектура), D9 (symmetry), D10 (traps), D13 (leak patterns — самый знающий Godot internals). **Дополнительно — AC-A9: ручной профайлер-проход в Godot,** ~30 мин, со снятием snapshot перед мержем 012. Его findings — самые критичные, идут в 013.
- **Sergey:** не ревьюер 012 (его кода ещё нет в staging). Будет ревьюером 013+ в части AI/skill, когда 008-impl созреет.
- **Alexey:** ревьюер по D5/D11 в части data/dialogue если DialogueManager engine-side findings всплывут.
- **Nikita:** не ревьюер кода. Возможно фигурирует в findings по dialogue content (грамматика, тон) — отдельной секцией, low priority.
- **Stasyan:** не ревьюер 012. Получает резюме findings по `data/modifiers/`, `data/skills/` отдельным сообщением — backlog для balance-PR.

## Процесс работы (шаги для self / Клода если возьмёт implement)

1. **Снимок staging:** `git pull staging` после мержа 008-update. Зафиксировать SHA — `findings.md` валиден против этого среза.
2. **Систематический static-проход:** D1 → D13 в порядке, каждый домен — отдельная секция в `findings.md`. Не прыгать между доменами.
3. **Findings — на лету:** не накапливать в голове, фиксировать сразу. ID — `F-001`, `F-002`, ..., no skipping numbers.
4. **Профайлер-snapshot (AC-A9, Egor manual):** параллельно с пп.2-3 либо после. Файл `profiler-snapshot.md` рядом с findings. Если расходится со static-pass — кросс-ссылки в findings (см. AC-A10).
5. **Per-owner / per-spec rollup** в конце.
6. **Refactor backlog (AC-A5)** — последняя секция `findings.md`.
7. Коммит, push, тэгнуть owners в PR-комментариях.
8. Каждый owner read-only ревьюит свою часть. Approve или коррекции через PR-комменты.
9. После approval — 012 в staging, 013 стартует от него.

## Что после 012

- **013-refactor-wave-1** — slot уже зарезервирован (`specs/013-refactor-wave-1/spec.md` — stub). Заполняется из AC-A5 backlog после мержа 012.
- Если P1-findings = 0 (повезло, всё чисто) — 013 закрывается без PR, slot remains as «numbered slot consumed», следующая фича — 014.
- Если P1-findings много (тоже вероятно — мы 50 часов писали) — 013 содержит топовые, остальное в 014/015.

---

## TL;DR для команды

> «12 — это аудит, не правки. После него Андрей открывает 013-N с конкретными фиксами, разбитыми по модулям. До тех пор код-base не трогаем — параллельные feature-branch не блочатся.»
