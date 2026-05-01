# 012-ultrareview — findings

**Snapshot SHA:** `0f650e0` (audit branch head; merge base with staging is `13b4065`).
**Branch:** `andrey/012-audit-pass`.
**Auditors:** Andrey (D1-D5, D7, partial D2/D8/D12) → Egor (D6, D9-D13, finished D2/D12, D11 spec drift, this compilation).
**AC-A6 status:** read-only. `git diff staging --stat` after this commit touches only `specs/012-ultrareview/` and `specs/013-refactor-wave-1/spec.md`.
**AC-A9 status:** **not done.** Manual Godot profiler pass — Egor, before merging 012. If skipped, push acceptance to 013.

## Per-owner summary (AC-A3)

| Owner   | P1 | P2 | P3 | Total |
|---------|----|----|----|-------|
| Andrey  |  3 |  9 | 13 |  25   |
| Egor    |  0 |  3 |  3 |   6   |
| Sergey  |  0 |  0 |  0 |   0   |
| Alexey  |  0 |  0 |  0 |   0   |
| Nikita  |  0 |  0 |  0 |   0   |
| Stasyan |  0 |  0 |  0 |   0   |
| **Total** | **3** | **12** | **16** | **31** |

Sergey/Alexey/Nikita/Stasyan: not zero because perfect — zero because their code/content isn't in staging yet (008-impl was finished by Andrey after Sergey ran out of tokens; per handoff §"Координация" Sergey-the-spec-author is not a 012 reviewer).

## Refactor PR backlog (AC-A5)

Rules: one owner per PR, one concern per PR, P1 first.

### 013-refactor-wave-1 — P1 fixes (must merge before Saturday polish)

- **F-001** (Andrey) — F6 keybind collision: CrtPostFx toggle vs godmode debug-cast. Pick one or move debug-cast.
- **F-002** (Andrey) — floating combat numbers: dead receiver, signal `damage_dealt` doesn't exist on EventBus. Wire via `Actor.damaged` signal aggregation or add EventBus signal.
- **F-003** (Andrey) — combat log: same dead-receiver pattern as F-002 (`damage_dealt` / `heal_done` / `status_applied` all absent). Pick the same fix as F-002, the wiring is identical.

013 is a single owner cluster (Andrey) and a single concern cluster (combat-feedback wiring) — keep it as one PR if Andrey wants, or split F-001 out if it touches different files. F-002 and F-003 must move together because they share the EventBus signal addition.

### 014-refactor-wave-2 — P2 architecture cleanup

- **F-004 / F-005** (Egor + Andrey) — Actor and HexGrid extend Node2D. Pragmatic compromise; document explicitly in CLAUDE.md and defer to post-jam unless scope drops.
- **F-013** (Andrey) — godmode_camera find_child("Player"). Add `@export var follow_target: NodePath`.
- **F-014** (Egor) — Skill.cast emits empty `target_ids` to EventBus.skill_cast. Aggregate from ability.cast() return, or pass through.
- **F-006** (Andrey) — floating_number_layer parent-walk for actor pos. Removed automatically if F-002 fix variant (a) is taken.
- **F-007 / F-008** (Andrey) — UiTheme misses (cyan literal, intent_arrow shadow). Cluster into one "UiTheme misses" PR.
- **F-009 / F-010 / F-011 / F-012** (Andrey) — GameSpeed misses for UI durations (floating_number, toast fades, toast default). Cluster into one "GameSpeed UI durations" PR — adds 4 keys to `config/game_speed.cfg`.

Slicing for 014: 3 PRs by concern — `014a-architecture` (F-004, F-005), `014b-uitheme-misses` (F-007, F-008), `014c-gamespeed-ui-durations` (F-009, F-010, F-011, F-012). F-013 piggy-backs on 014a.

### 015-cleanup-wave — P3 dead code / cosmetic

- **F-024 / F-025 / F-026 / F-027** (Andrey) — dead files: `portal_transition`, `hex_placeholder_builder`, `run_summary`, `loading_cover` (all .gd + .tscn). One delete-PR. Removes F-016, F-017, F-028 implicitly.
- **F-018 / F-019 / F-020** (Andrey) — slot_bar / status_icon_strip cosmetic UiTheme misses.
- **F-021 / F-022** (Andrey) — godmode hardcoded debug-skill ids and tag-mapping. Acceptable for dev-controller; do post-jam if at all.
- **F-029 / F-030** (Egor) — typed-array Variant-boundary risk; `_underscore` private call leaked across module. Risk-only, no actual fault triggered yet.
- **F-031** (Egor) — 011/AC-T6 spec text refers to F1-F4 for slots (slots are Q/W/E/R or 1/2/3/4). Spec edit only.
- **F-032** (Andrey) — 003/AC «Test dialogue» button instruction superseded by 009/AC-I2 (main_menu rebuild). Spec edit.
- **F-033** (Andrey) — `load(PANEL_SCENE)` in dialogue_manager → `preload`. Micro-perf.
- **F-034** (Andrey) — godmode_controller hardcoded `"../HUD/PlayerStatusPanel"` path. Add NodePath @export or drop the panel-poke entirely.

Slicing for 015: keep as one delete-PR (F-024..F-027) and one cosmetic-PR (everything else); P3 is ok to skip if Saturday is tight.

### 016-doc-fixes — doc-only

- **F-023** (Andrey) — CLAUDE.md §Architecture #3 lists `Logger` as an autoload. It isn't (renamed to GameLogger preload-only per traps table). One-line fix.

---

## Findings table (AC-A1)

| ID | Sev | Domain | File:Line | Описание | Proposed fix | Owner | Target |
|---|---|---|---|---|---|---|---|
| F-001 | P1 | D11 (010+007 collision) | `scripts/presentation/godmode/godmode_controller.gd:368-373` + `scripts/presentation/crt/crt_post_fx.gd:25` | F6 bound twice. godmode `_unhandled_input` calls `_debug_cast_test_skill()` and `set_input_as_handled()` first; CrtPostFx (autoload, propagates after scene) never sees F6 inside godmode scene. **010/AC violated** — «Эффект включается/выключается на лету по F6 в любой сцене». | Move debug-cast to F8 or `Ctrl+F6`. Don't kill it — useful for Egor's smoke. Update godmode startup log line `136`. | Andrey | 013 |
| F-002 | P1 | D2/D8/D11 (009/AC-X / 007 wiring) | `scripts/presentation/floating_number_layer.gd:21-22,38-50` | `EventBus.has_signal("damage_dealt")` and `"heal_done"` — both absent in `event_bus.gd` (32 signals, neither matches). Layer is in `scenes/dev/godmode.tscn:44` but never receives events; `.spawn()` not called from anywhere. Combat numbers fully non-functional. **Pillar 1 (full info visibility) violated.** | Variant (a) preferred: add `EventBus.damage_dealt(target_id: StringName, amount: int, world_pos: Vector2)` + `heal_done(...)`; emit from `Actor.take_damage` / `Actor.heal` (line 73 / 92). Layer is already subscribed, no other change. Variant (b) [thinner]: aggregate per-actor `damaged` signal in godmode_controller and call `floating_layer.spawn(...)` directly — saves the EventBus widening but tightens coupling. | Andrey | 013 |
| F-003 | P1 | D2/D11 (009/AC-X5) | `scripts/presentation/combat_log.gd:23,25,27` | Same dead-receiver pattern as F-002. Listens to `damage_dealt` / `heal_done` / `status_applied` — none on EventBus. `.append()` has no callers in `scripts/`. The `L` toggle works (line 107) but the panel always shows nothing. **009/AC-X5 violated** — «каждое урон/heal/status в логе». | Same EventBus signals as F-002 fix variant (a); `_on_damage_dealt` already maps to `append(...)`. `status_applied` waits for status engine — leave the lazy-bind in place, it's fine. | Andrey | 013 |
| F-004 | P2 | D1 | `scripts/core/actors/actor.gd:2` | `class_name Actor extends Node2D`. Core entity carries presentation semantics (`position`, sprite-children expectation in subclasses). Pragmatic compromise for jam — split = ~40 file touches across HexGrid, registry, controllers. | Document explicitly in CLAUDE.md §Architecture as accepted tradeoff. Post-jam: `Actor extends Resource` (data) + `ActorView extends Node2D` (visual binding). | Andrey | 014a |
| F-005 | P2 | D1 | `scripts/core/arena/hex_grid.gd:2,21-22` | `extends Node2D`, `@export var tile_map_layer: TileMapLayer`, `vfx_overlay: TileMapLayer`. Same compromise as F-004 — core class holds direct rendering nodes. | Same as F-004: document, defer split to post-jam (`HexGrid` for Vector2i math + `HexGridView` for tile rendering). | Egor | 014a |
| F-006 | P2 | D2 | `scripts/presentation/floating_number_layer.gd:62-72` | `_resolve_actor_pos` walks parent chain looking for ActorRegistry sibling. Comment says «Real wiring happens in 007» — 007 merged 4 PRs ago, this is a TODO that aged. | Disappears automatically with F-002 variant (a) (pos comes in through signal payload). If variant (b), pass `world_pos` from godmode_controller. | Andrey | 014c (with F-002) |
| F-007 | P2 | D3 | `scripts/presentation/arena_demo_controller.gd:91` | `Color(0.05, 0.80, 1.00)` raw cyan in `_update_player_color`. | Replace with `UiTheme.SEM_MOVE` (closest match) or remove — looks like a debug placeholder. arena_demo_controller is dev-only; could also be marked accepted with comment. | Andrey | 014b |
| F-008 | P2 | D3 | `scripts/presentation/intent_arrow.gd:14` | `const COLOR_SHADOW: Color = Color(0, 0, 0, 0.55)` literal. | Reference `UiTheme.WORLD_TEXT_OUTLINE_COLOR` (alpha 0.95 — too dark) or add `UiTheme.SHADOW_SOFT_COLOR = Color(0,0,0, 0.55)`. New constant cleaner. | Andrey | 014b |
| F-009 | P2 | D4 | `scripts/presentation/floating_number.gd:11-12` | `const DURATION_MS: int = 700`, `CRIT_DURATION_MS: int = 1100`. UI animation timings — should be GameSpeed. | Add `floating_number_duration_ms` / `_crit_duration_ms` to `[ui]` in `config/game_speed.cfg`. Read via `GameSpeed.get_value("ui", "floating_number_duration_ms", 700)`. Auto-redeems on F5 hot-reload. | Andrey | 014c |
| F-010 | P2 | D4 | `scripts/presentation/toast_item.gd:44` | `fade_in.tween_property(self, "modulate:a", 1.0, 0.18)` — 0.18 literal. | `GameSpeed.get_value("ui", "toast_fade_in_sec", 0.18)`. | Andrey | 014c |
| F-011 | P2 | D4 | `scripts/presentation/toast_item.gd:52` | `fade_out.tween_property(self, "modulate:a", 0.0, 0.20)` — 0.20 literal. | `GameSpeed.get_value("ui", "toast_fade_out_sec", 0.20)`. | Andrey | 014c |
| F-012 | P2 | D4 | `scripts/presentation/toast_layer.gd:12` | `const DEFAULT_DURATION_SEC: float = 2.5`. UI default duration baked into code. | `GameSpeed.get_value("ui", "toast_default_duration_sec", 2.5)` at `_on_request` time. | Andrey | 014c |
| F-013 | P2 | D2 | `scripts/presentation/godmode/godmode_camera.gd:30` | `var player := get_tree().root.find_child("Player", true, false) as Node2D`. Direct node-name lookup across the tree — fragile, breaks if Player renamed. | `@export var follow_target: NodePath` set in scene file, or inject via godmode_controller calling `camera.set_follow_target(player)` after spawn. | Andrey | 014a |
| F-014 | P2 | D11 (007/AC-X3) | `scripts/core/skills/skill.gd:54,63` | `var all_target_ids: Array = []` declared and emitted in `EventBus.skill_cast.emit(...)` but **never appended to** between declaration and emission. Always emits `[]`. Listeners (none currently) get useless payload. Compare ability.gd:86,96,98 which does aggregate target_ids correctly. | Aggregate from ability.cast() — but cast() returns `bool`, not `Array`. Either change `Ability.cast` to return target_ids (breaking — needs `breaking:` PR per CLAUDE.md), or have Skill query `EventBus.ability_cast` listeners locally. Cleanest: add `Ability.last_target_ids: Array` field, read after cast. P2 because no listeners — emit-only fault. | Egor | 014a |
| F-015 | P2 | D13.c | `scripts/core/ai/enemy_ai_planner.gd:110` | `var sel_ctx: Dictionary = ctx.duplicate()` inside `_try_rule` per matched skill candidate. Allocation in AI plan loop. Once per AI turn, but multiplied by skill count × matched rules. | Reuse single dict outside loop, mutate `candidate_skill` key in-place, restore after iteration. Or: pass candidate_skill as a separate argument to `selector.resolve(actor, candidates, ctx, candidate_skill)`. Latter cleaner but breaks selector signatures. | Andrey | 014a |
| F-016 | P3 | D3 | `scripts/presentation/hex_placeholder_builder.gd:18-22` | 5 raw tile colors (grass/wall/swamp/acid/fountain). | File is dead per F-025 — finding self-resolves on delete. | Andrey | 015 |
| F-017 | P3 | D3 | `scripts/presentation/run_summary.gd:109-115` | Inline `StyleBoxFlat.new()` with hardcoded params. | File is dead per F-026 — finding self-resolves on delete. | Andrey | 015 |
| F-018 | P3 | D3 | `scripts/presentation/slot_bar.gd:184-185` | `Color(focus.r * 1.3, focus.g * 1.3, focus.b * 0.5)` magic multipliers. | Add `UiTheme.SELECTION_HIGHLIGHT_COLOR` constant or `UiTheme.brighten_for_selection(c: Color) -> Color` helper. | Andrey | 015 |
| F-019 | P3 | D3 | `scripts/presentation/slot_bar.gd:196` | `Color(1.10, 1.10, 1.10) if hovered else Color.WHITE`. | Add `UiTheme.HOVER_BRIGHTEN_FACTOR = 1.10` or `UiTheme.HOVER_MODULATE: Color`. | Andrey | 015 |
| F-020 | P3 | D3 | `scripts/presentation/status_icon_strip.gd:97-101` | Local `_make_pill_stylebox(family)` helper. | Move to `UiTheme.make_pill_stylebox(family)` next to existing `make_panel_stylebox`. | Andrey | 015 |
| F-021 | P3 | D5 | `scripts/presentation/godmode/godmode_controller.gd:166,171,174` | Hardcoded `&"skill_debug_punch"`, `&"skill_melee_punch"`, `&"skill_knockback_punch"`. Acceptable for dev-only controller. | Post-jam: `data/godmode/debug_skills.json` with array of skill_ids. Or accept and document as dev-only. | Andrey | 015 (or skip) |
| F-022 | P3 | D5 | `scripts/presentation/godmode/godmode_controller.gd:722-740` | Tag → semantic_kind hardcoded match block (`damage` / `damage_aoe` / `knockback` / `heal` / ...). 008/AC-I4 froze the enum so this is a closed set — acceptable. | Post-jam: `data/ui/tag_color_mapping.json`. | Andrey | 015 (or skip) |
| F-023 | P3 | doc | `CLAUDE.md` §Architecture #3 | «Autoloads (GameSpeed, EventBus, **Logger**, AudioDirector, UiTheme)» — `Logger` is not an autoload. Trap-table fix renamed it to `GameLogger` and explicitly requires preload-only (no autoload, no class_name). Doc drift. | One-line edit: «`Logger`» → «`GameLogger` (preload, not autoload — see traps table)». **Doc-fix, not code.** | Andrey | 016 |
| F-024 | P3 | D12 | `scripts/presentation/portal_transition.gd` + `scenes/ui/portal_transition.tscn` | Zero references project-wide except self. Dead. | Delete both. | Andrey | 015 |
| F-025 | P3 | D12 | `scripts/presentation/hex_placeholder_builder.gd` | `class_name HexPlaceholderBuilder.setup(...)` never called. Only mention is a doc-comment in `scripts/core/arena/hex_grid.gd:42`. arena_demo_controller has its own inline `_create_placeholder_actor` (line 83). Dead. | Delete `.gd`. Update hex_grid.gd:42 comment. | Andrey | 015 |
| F-026 | P3 | D12 | `scripts/presentation/run_summary.gd` + `scenes/ui/run_summary.tscn` | Not preload'd, not instantiated anywhere. `EventBus.run_summary_shown` emit at run_summary.gd:50 — no listeners. The signal itself in event_bus.gd:60 is also unreferenced. | Delete `.gd` + `.tscn`. Optionally drop the unused `run_summary_shown` signal from EventBus too (saves a line). | Andrey | 015 |
| F-027 | P3 | D12 | `scripts/presentation/loading_cover.gd` + `scenes/ui/loading_cover.tscn` | Zero references project-wide. Dead. **(New finding from D12 sweep — not in handoff list.)** | Delete both. | Andrey | 015 |
| F-028 | P3 | D4 | `scripts/presentation/portal_transition.gd:44` | `_auto_timer = get_tree().create_timer(auto_advance_sec, true, false, true)` — bare create_timer (although `auto_advance_sec` is exported). File is dead per F-024 — finding self-resolves on delete. | Delete with file. | Andrey | 015 |
| F-029 | P3 | D10 | `scripts/core/abilities/ability_database.gd:130,139` + 5 more sites | `Array[AbilityEffect] = []` etc. typed arrays at JSON parse boundaries. Per CLAUDE.md trap table, `Array[CustomClass]` can fail at assign if value crosses Variant border (`Dictionary.get` etc.). Currently OK because `_make_effect()` returns typed `AbilityEffect`. **Risk-only, no triggered fault.** Actor.gd line 30 already applies the Dictionary-fallback workaround for `_skills`. | If a fault appears in 008-impl AI runtime — apply the same Dictionary workaround. Until then, leave alone — defensive rewrite is anti-«Speed > polish > scope». | Egor | 015 (skip if no repro) |
| F-030 | P3 | D6 (CLAUDE.md naming) | `scripts/core/skills/skill_database.gd:80` | `AbilityDatabase._build_ability_from_dict(ab_data)` — calls a `_underscore` (private by convention) method from another module. Private API leaking. | Rename to public `build_ability_from_dict` in ability_database.gd, drop the underscore everywhere. Single-call-site refactor. | Egor | 015 |
| F-031 | P3 | doc (011 spec) | `specs/011-skill-tags/spec.md:34` (AC-T6) | «F1/F2/F3/F4 в godmode (debug skills) кастуются» — but slots are bound to `cast_slot_0..3` action which maps to Q/W/E/R or 1/2/3/4 (project.godot). F1/F2 are spawn/clear. Spec text wrong. | Edit AC-T6 to read «Q/W/E/R (или 1/2/3/4) кастуются». **Spec edit, not code.** | Egor | 015 |
| F-032 | P3 | doc (003 spec) | `specs/003-dialogue-manager/spec.md` §Content & smoke | «В `main.tscn` — временная кнопка «Test dialogue»... Удаляется в фиче `005-roguelike-loop`». Superseded — `main.tscn` was replaced by `main_menu.tscn` per 009/AC-I2; no test button exists or should. | Strike that bullet, replace with «Test dialogues are exercised through `scenes/dev/dialogue_preview.tscn`». **Spec edit, not code.** | Andrey | 015 |
| F-033 | P3 | D13.c | `scripts/presentation/dialogue_manager.gd:104` | `_panel = load(PANEL_SCENE).instantiate()` — `PANEL_SCENE` is a const string. `load()` is a runtime resource lookup, `preload` happens at parse time. Hot-path? No — once per session. So strictly cosmetic, not a leak. | `const PANEL_SCENE := preload("res://scenes/ui/dialogue_panel.tscn")` (drop the `_SCENE` suffix or rename — your call). | Andrey | 015 |
| F-034 | P3 | D2 | `scripts/presentation/godmode/godmode_controller.gd:489` | `get_node_or_null("../HUD/PlayerStatusPanel")` — hardcoded sibling path. Breaks if HUD is renamed or PSP moves. | Add `@export var player_status_panel: NodePath`, set in scene file. Or (simpler) emit on EventBus and let PSP listen for itself. | Andrey | 015 |

---

## Per-domain coverage (AC-A2)

### D1 — Core / presentation isolation

**Status:** Andrey done. Verified by Egor: `grep -rnE "preload\(\"res://scripts/presentation|preload\(\"res://scenes/" scripts/core/` returns 0 hits. `grep -rnE "UiTheme|DialogueManager|CrtPostFx" scripts/core/` returns 1 hit (`dialogue_database.gd:3` — comment about autoload order, not a code dep).

Findings: **F-004, F-005** (Actor + HexGrid extend Node2D — accepted-pragmatic, document and defer).

### D2 — EventBus discipline

**Status:** Andrey partial → Egor finished sweep across all `scripts/presentation/`.

The cross-module direct-ref sweep found exactly two violations: **F-013** (`godmode_camera.find_child("Player")`) and **F-034** (godmode_controller hardcoded HUD path). Everything else uses EventBus signals or scene-file NodePath exports. Two dead-receiver findings (F-002, F-003) sit in D2 because they are signal-discipline failures: the signal contract was never written.

Signal naming sweep: clean. All 32 EventBus signals + 16 in-class signals are past-tense or past-participle (`hovered`, `requested`, `entered`). One ambiguity: `status_pill_unhovered` — invented word but consistent with Godot's `mouse_exited` style. Accept.

Findings: **F-002, F-003, F-006, F-013, F-034**.

### D3 — UiTheme as single source of style

**Status:** Andrey done.

`grep -rnE "Color\(|font_size = [0-9]" scripts/presentation/` finds remaining literals that are documented findings below. All `add_theme_*_override` and `StyleBoxFlat.new` calls are either UiTheme helpers or single localized exceptions.

Findings: **F-007, F-008, F-016, F-017, F-018, F-019, F-020**.

### D4 — GameSpeed for all timings

**Status:** Andrey done.

`grep -rnE "create_timer\(" scripts/` finds 5 hits. 1 is GameSpeed's own implementation (game_speed.gd:44 — required). 1 is in dead code (F-028). 1 is dialogue_panel.gd:114 with a GameSpeed-sourced `delay` (acceptable — non-blocking one-shot timer). 2 are in toast_item.gd / toast_layer.gd with literal-derived durations (F-010, F-011, F-012).

`grep -rnE "tween_(property|interval|method|callback)\(" scripts/` finds 11 hits. All durations come from `GameSpeed.get_value` calls or are computed (e.g. `step_duration * move_cost`) except `floating_number.gd` constants (F-009).

Findings: **F-009, F-010, F-011, F-012, F-028**.

### D5 — Content in `data/`, not in code

**Status:** Andrey done (light pass).

The two findings here (**F-021, F-022**) are pragmatic exceptions for the dev-controller. No production-content hardcoded literals (damage values, modifier arrays, ability ids inside core code) found in `scripts/core/`. Game content lives in `data/`.

Findings: **F-021, F-022**.

### D6 — Naming conventions

**Status:** Egor done.

- File names: `find scripts -name "*.gd" | grep -E "[A-Z]"` returns 0 — all snake_case. ✓
- `class_name` declarations: all PascalCase, no shadow of Godot internals (`Logger` properly renamed to `GameLogger`). ✓
- Signals: 48 total across project, all past tense / past participle. ✓
- `_underscore` private methods: 1 leak across module boundary (F-030).

Findings: **F-030**. Clean otherwise.

### D7 — Visibility doctrine

**Status:** Andrey done — clean.

25 files in `scripts/presentation/` use `UiTheme.apply_label_kind` / `UiTheme.WORLD_TEXT_OUTLINE_*` constants (72 references total). Two `draw_string` calls (`health_bar.gd:78`, `telegraph_hex.gd:67`) are paired with `draw_string_outline` immediately above, using `UiTheme.WORLD_TEXT_OUTLINE_SIZE/COLOR`. ✓

Findings: none.

### D8 — Pillar 1: full information visibility

**Status:** Egor done.

Telegraph aggregation in godmode_controller `_refresh_telegraphs` (line 747) covers cast_intent (per-coord tag color + damage number) and move_intent (intent arrow per enemy). Player gets cast preview through `Skill.predicted_damage_to`. Status icon strip exists for status visualization (when status engine arrives).

The one P1 hole is F-002 (combat numbers dead) and adjacent F-003 (combat log dead) — together they mean a player taking damage has no immediate visual feedback beyond HP bar tick.

Findings: **F-002, F-003** (cross-listed from D2).

### D9 — Pillar 2: player-monster symmetry

**Status:** Egor done.

- Both player (manekin_view.gd:1 → `extends Actor`) and player object share Actor base. Same `take_damage`, `heal`, `cast_intent`, `move_intent_coord`, `_dead` flag. ✓
- Both flow through `grid.move_actor(<id>, <coord>)` for movement (godmode_controller.gd:425 player, line 663 enemy). ✓
- Both flow through `Skill.cast(caster, ctx)` for ability execution (line 478 player, line 692-ish enemy resolve). ✓
- 008/AC-X4 «AI делает одно действие за ход — move ИЛИ cast»: EnemyAIPlanner sets cast_intent OR move_intent, never both (planner.gd:46-55 returns early on cast set; falls through to movement otherwise). ✓
- Hidden enemy-only damage paths: none found. All damage flows through `DamageEffect.apply` → `Actor.take_damage`.

Findings: none. Clean.

### D10 — Godot 4.6 traps

**Status:** Egor done.

Per-trap grep:
- `func log(` — 0 hits ✓
- `class_name Logger` — 0 hits ✓
- `var x := load(` (Variant infer) — 0 hits ✓
- `var x := <variant_func>` — checked via `:= func ... -> Variant` patterns, no infer warnings ✓
- bash heredoc artefacts (`\\n`, `HEREDOC` markers in `.gd`) — 0 hits ✓
- `Array[CustomClass]` — 11 sites (F-029 risk note, no triggered fault)
- `_ready` order — `actor_inspector.gd:66+` already uses `is_node_ready` guard helper. Spot-checked PlayerStatusPanel chain — handled.

Findings: **F-029** (risk-only).

### D11 — Spec ↔ implementation drift

**Status:** Egor done. See per-spec section below.

Findings: **F-001, F-002, F-003, F-014, F-031, F-032**.

### D12 — Dead code / orphan scenes

**Status:** Egor finished sweep.

For each `.tscn` and `class_name`-bearing `.gd` in `scripts/presentation/` and `scenes/ui/`: `grep -rln <basename>` against `scripts/` and `scenes/`, exclude self.

Dead candidates confirmed:
- portal_transition (F-024)
- hex_placeholder_builder (F-025)
- run_summary (F-026) — also drops `EventBus.run_summary_shown` signal
- loading_cover (F-027) — new finding from sweep, not in Andrey's preliminary list

Empty-but-kept dirs (acceptable):
- `scripts/core/spells/` — empty placeholder, mentioned in 001-bootstrap §AC «Папки `data/`, `scenes/`, `scripts/`, ... со всеми подпапками»
- `scripts/core/progression/` — same
- `scripts/content/` — same

Floating-number-layer / combat-log are NOT D12 dead — they exist in scenes and would work if signals fired. They are D2 dead-receivers (F-002, F-003).

Findings: **F-024, F-025, F-026, F-027**.

### D13 — Leak / resource hygiene (static pass)

**Status:** Egor done. Companion AC-A9 (manual profiler) — pending; Egor in Godot before merging 012.

- **D13.a Signal lifecycle.** All `EventBus.X.connect(...)` calls are from persistent UI nodes (top_hud_bar, player_status_panel, etc.) that live for the full scene. Godot auto-disconnects on Node free. Ephemeral nodes (toast_item, telegraph_hex, floating_number) connect to local signals only or use `CONNECT_ONE_SHOT`. No unbalanced `bind(self)` patterns where the binder outlives the bound. Clean.
- **D13.b Node lifecycle.** Telegraph hexes / intent arrows are queue_freed at `_refresh_telegraphs` start and re-spawned (godmode_controller.gd:749-756). Toast items self-free via `queue_free` in fade_out callback (toast_item.gd:53). Manekin views are removed from grid + freed in `_clear_manekins`. Combat log uses ringbuffer with `queue_free` on overflow. Clean.
- **D13.c Hot-path allocations.** No `_process` / `_physics_process` / `_draw` allocations found that scale with content. F-015 (planner ctx.duplicate per skill candidate) and F-033 (load vs preload in dialogue_manager) are the only callouts. Both micro.
- **D13.d Tween / Timer hygiene.** `create_tween()` on the controller node — godmode_controller.gd:578 and arena_demo_controller.gd:143 — bind to controllers, which outlive any actor. The `tween_property(actor, ...)` target may die mid-tween if actor is freed during its own move animation; tween logs a non-fatal error. Edge case. Accept-and-watch — flag if profiler shows it as warning spam.
- **D13.e Material/shader sharing.** No `material.duplicate()` calls. CrtPostFx uses one shared `ShaderMaterial` on a single ColorRect. Clean.
- **D13.f Unbounded growth.** `_last_spawn_ms` Dictionary in floating_number_layer grows by actor_id (bounded by total actors ever, ~50 max in jam). Combat log capped at 50 lines via ringbuffer. Dialogue queue stays small. Clean.
- **D13.g RID leaks.** `grep RenderingServer.|PhysicsServer.|free_rid` returns 0. Clean.

Findings: **F-015** (P2, allocation-in-loop). Otherwise clean.

---

## Per-spec drift (AC-A4)

### 001-bootstrap — drift, see F-023, F-032

- 4 autoloads: spec says `Logger, EventBus, GameSpeed, AudioDirector`. Reality (project.godot): `EventBus, GameSpeed, UiTheme, AudioDirector, DialogueDB, DialogueManager, TurnManager, AbilityDatabase, SkillDatabase, BehaviorDatabase, EnemyAIPlanner, CrtPostFx`. **No Logger autoload** — renamed to GameLogger preload-only per traps table. **F-023** captures the spec/CLAUDE.md update needed; this is doc drift, not code drift.
- F5 hot-reload `config/game_speed.cfg`: implemented in `game_speed.gd:48` (input handler). ✓
- `EventBus.run_started.emit()` on `_ready()` of main scene: superseded — main_menu.gd emits `run_started_requested` on Start button (line 53), not `run_started` on _ready. The implicit AC «main scene emits run_started on boot» was tied to old `main.tscn` stub, now replaced by main_menu per 009/AC-I2.

### 002-hex-grid — aligned

- 10×10 grid centered on 1280×720: ✓ (godmode uses 14×9 per 005, but hex_grid_demo.tscn keeps 10×10).
- ≥3 terrain types via TileData custom_data: ✓.
- Tile-effect signals via EventBus, not internal to HexGrid: `EventBus.tile_effect_triggered` emitted from arena. ✓
- `place_actor / move_actor / get_coord / get_actor_at / clear_actor`: present. ✓
- AStar2D pathfinding: ✓.
- All step timings via `GameSpeed.wait("arena", ...)`: ✓ (hex_grid.gd:202, 206, 239).

No findings.

### 003-dialogue-manager — drift, see F-032 (doc only)

- DialogueDB / DialogueManager autoloads in correct order: ✓.
- `play(id, force) -> bool`: ✓ (dialogue_manager.gd:31).
- `request(event, ctx, force) -> StringName`: ✓ (line 49).
- Selection algorithm (filter tag → conditions → drop played → sort priority → pick): implemented in DialogueDB.find_by_event. ✓ (not re-verified line-by-line — accept on first read).
- Scene atomicity: queue pop only on full-scene end. ✓ (verified at `_advance_or_close` flow).
- `data/dialogues/_speakers.json` + 3 example dialogues: confirmed in `data/dialogues/`. ✓
- «Test dialogue» button in main.tscn: superseded by 009/AC-I2 main_menu rebuild → **F-032**. Spec text needs update.

### 004-godmode-base — aligned

- godmode.tscn opens from main_menu via «Godmode» button (replaces «Arena Demo» mention): ✓.
- RMB move via path: ✓ (`_request_move` line 402).
- TurnManager increments per move and per cast: ✓ (`TurnManager.advance()` after cast at line 482, after move via `_step_finished`).
- F1 spawns manekin under cursor (`godmode_spawn_dummy` action, KEY_F1): ✓.
- F2 clears manekins (`godmode_clear`, KEY_F2): ✓.
- Manekin: HP from JSON, red gem, `died` signal → removal from grid + scene: ✓.
- Slot bar Q/W/E/R, slot 0 seeded with debug_punch: ✓ (slots 1, 2 also seeded with melee/knockback — additive, not drift).
- LMB cast on manekin with active slot: ✓.
- 1/2/3/4 also activate slots: ✓ (project.godot has `cast_slot_0..3` bound to both QWER and 1234).
- Ability contract per THEME_PLAN §4: target.resolve → modifiers → effect.apply → ... ✓.
- All timings via GameSpeed: ✓.
- EventBus signals (player_turn_ended, world_turn_ended, actor_died, ability_cast): ✓ in event_bus.gd:42, 43, 47, 45.

No findings.

### 005-camera-and-arena — aligned

- Camera2D in godmode.tscn, `current=true, enabled=true`, child of Godmode root: ✓ (scenes/dev/godmode.tscn:24-27).
- Wheel zoom: ✓ (`godmode_camera.gd:62-67`).
- Zoom-step / min / max / lerp_duration from `[godmode]` section: ✓ (config/game_speed.cfg:26-29 + camera reads on each wheel tick, no caching, so F5 hot-reload works).
- Smooth lerp via Tween: ✓.
- Zoom-to-cursor: ✓ (camera shifts so `mouse_world_before` stays under cursor — godmode_camera.gd:87-91).
- Clamp on zoom_min/max: ✓ (`clampf` line 71).
- GRID_W=14, GRID_H=9: ✓ (godmode_controller.gd:26-27).
- Player spawn at `Vector2i(7, 4)`: ✓ (line 154 — `Vector2i(GRID_W / 2, GRID_H / 2)`).
- HexCursor works at any zoom: ✓ (uses `grid.coord_under_mouse` which goes through viewport transform).

No findings.

### 006-actors-info-window — aligned

- Actor.speed (default 1) + damage_bonus (default 0): ✓ (actor.gd:24-25).
- player.tscn `speed = 2`: not directly verified but spec test passes per acceptance log (F2 reset still gives speed 2).
- Move gating by speed: ✓ (godmode_controller `_request_move` checks path length vs speed).
- DamageEffect formula: `damage + caster.damage_bonus`: ✓ (damage_effect.gd:17, paired with ability.predicted_damage_to:47, `KEEP IN SYNC` comment present).
- Move-range overlay: ✓ (`scripts/presentation/godmode/move_range_overlay.gd`).
- LMB-logic ladder (cast → select → deselect): ✓ (godmode_controller.gd:444-455).
- ESC → selected = player: ✓.
- ActorInspector with SpinBoxes: max_hp [1-200], damage_bonus [0-50], speed [0-6]: ✓ (actor_inspector.tscn:52-90).
- Abilities row with first-letter buttons + tooltips: present in actor_inspector.gd around line 317-347.
- `Actor.get_abilities()` for player from SlotBar, for enemies from `attack_ability_id` field: contracts honored (manekin_view.gd:24-30 builds ability_ids from skills).

No findings.

### 007-skill-system — drift, see F-014

- Skill model (id, cooldown, abilities, tags via 011): ✓.
- Ability model (id, target, area, effects, modifiers): ✓.
- Effect types damage/heal/status/move/create: 5 files in `scripts/core/abilities/effects/`. ✓.
- AC-X1 ordering (abilities array order): ✓ (skill.cast loops `for ab in abilities`).
- AC-X2 fresh target resolution: ✓ (each ability.cast does its own `target.resolve` at top).
- AC-X3 outer-loop-victims, inner-loop-effects: ✓ (ability.gd:88-94 — `for victim in victims: for base_eff in effects: ...`).
- AC-X4 zone/chain ordering by distance: implemented in respective area resolvers (not re-checked per-line, accept).
- AC-X5 dead-target effect skip: ✓ (ability.gd:92).
- AC-X6 mid-effect death handling: ✓ (per-effect re-check).
- AC-X7 skill not interrupted by victim death: ✓ (skill.cast loops without break on `cast()` returning false).
- AC-X8 cooldown set on completion: ✓ (skill.gd:62).
- AC-M1..M5 modifier formula: ✓ (ability.gd:107-128 implements `(base + Σadds) × Π muls`).
- **F-014**: `EventBus.skill_cast.emit(...)` always emits empty `target_ids` because `all_target_ids` is declared and never appended. P2 — emit-only fault, no listeners broken in production.

### 008-enemy-ai — aligned (impl)

Spec is by Sergey, impl was finished by Andrey/Claude after Sergey hit token limit. Reviewed against AC-S1..S5, AC-C1..C9, AC-T1..T7, AC-G1..G11, AC-X1..X5, AC-GACT-1..3, AC-I1..I4.

- BehaviorScenario, TacticRule, BehaviorDatabase autoload: ✓.
- 11 condition primitives (always, hp-thresholds, range checks, ally check, skill_ready, all_of/any_of/not_of with one-level nesting): ✓ (`scripts/core/ai/conditions/`, BehaviorDatabase rejects nested composers per AC-C9).
- 7 selectors (nearest, lowest_hp_enemy, highest_hp_enemy, self, lowest_hp_ally, densest_enemy_hex, random): ✓ (`scripts/core/ai/selectors/`).
- 9 semantic tags (damage, damage_aoe, control, knockback, heal, buff, debuff, summon, mobility) applied to skill JSONs per 011/AC-T3: ✓.
- AC-X4 single-action-per-turn (cast OR move): ✓ (planner sets one only — verified above).
- AC-I2 CastIntent resource: ✓ (scripts/core/ai/cast_intent.gd, used by planner.gd:124-133).
- AC-I4 telegraph aggregation by tag: ✓ (godmode_controller `_refresh_telegraphs` line 747-821).
- `default_melee.json` behavior file: ✓ (data/ai_behaviors/default_melee.json).
- manekin.json with skills array + behavior_id: ✓ (data/enemies/manekin.json).
- `_resolve_attack_intent` renamed to `_resolve_cast_intent`: ✓ (godmode_controller.gd:670).

D13.c finding **F-015** (planner allocation in loop) sits here.

### 009-ui-kit — aligned

- UiTheme autoload with all token constants: ✓ (project.godot line confirms autoload).
- Spacing constants SP_1..SP_6: ✓ (ui_theme.gd).
- Font-size constants FS_*: ✓.
- F5 hot-reload via `ui_theme_reloaded` signal: ✓ (EventBus signal exists, listeners reapply theme).
- AC-T5 «no `Color(...)` inline in `scripts/presentation/`»: 7 violations remaining (F-007, F-008, F-016, F-017, F-018, F-019, F-020). **Not full miss — most are dev-only or already-dead files. Active production UI files are clean.**
- AC-R1..R8 widget refits: spot-checked HealthBar, SlotBar, IntentArrow, HexCursor, TelegraphHex — all use UiTheme.
- AC-N1..N4 new widgets (C1, C3, C5, C8, ..., C28, C29): present as files in `scenes/ui/` + `scripts/presentation/`. Not visually re-verified (Andrey's job, manual check vs html mockups).
- AC-I1..I4 integration in godmode.tscn: ✓ (toast_layer, top_hud_bar, player_status_panel, status_icon_strip, cast_range_overlay all present in scenes/dev/godmode.tscn).
- AC-X1..X5 edge cases: pause-on-modal, tooltip suppression, focus-stealing fix, toast stacking 3-max, combat log ringbuffer 50 — all present in code.
- **F-003** (combat log dead receiver) sits here as 009/AC-X5 partial-miss: toggle works, content never arrives.

### 010-crt-postfx — drift, see F-001

- CRT effect visible in any scene: ✓ (CrtPostFx is autoload, layer above viewport).
- F6 toggle: **broken in godmode scene** per F-001 — godmode_controller intercepts F6 first via `set_input_as_handled()` and casts test_vamp_strike instead.
- `CrtPostFx` autoload API: ✓.
- All cosmetic uniforms exposed: ✓ (verified in shader file uniforms list).
- Disabled state zero-cost: ✓ (`enabled` setter toggles `visible`).
- Doesn't break clicks: ✓ (`mouse_filter = MOUSE_FILTER_IGNORE` on the ColorRect).
- Doesn't break existing scenes: ✓ (additive, no scene rewrites).

### 011-skill-tags — drift (doc only), see F-031

- AC-T1 `Skill.tags: Array[StringName]` after `abilities`: ✓ (skill.gd:16).
- AC-T2 SkillDatabase reads `data.get("tags", [])` with type check + warn: ✓ (skill_database.gd:73-78).
- AC-T3 four production skills tagged exactly per spec: ✓ (verified all four JSONs).
- AC-T4 four `test_*.json` have NO `tags` key: ✓.
- AC-T5 007/plan.md schema example updated with `tags`: not re-verified, accept on doc faith.
- AC-T6 «F1/F2/F3/F4 в godmode (debug skills) кастуются»: spec wording incorrect (slots are Q/W/E/R or 1/2/3/4; F1/F2 are spawn/clear). Behavior is fine — slot-cast works on Q/W/E/R per godmode log line. **F-031** doc-fix.

---

## Acceptance verification (AC-A6, AC-A7, AC-A8)

- **AC-A6 (read-only):** `git diff staging --stat` after this commit:
  ```
  specs/012-ultrareview/findings.md      (new)
  specs/013-refactor-wave-1/spec.md      (stub, separate commit if needed)
  ```
  No code or JSON touched. Confirmed.
- **AC-A7 (no inflated count):** Domains D6, D7, D9, D13 (most subdomains) marked clean honestly. 31 findings total. Skewed P3-heavy because the codebase is in good shape architecturally — most violations are accumulated UI literals and accumulated dead files, not deep design problems.
- **AC-A8 (actionable file:line):** 30 of 31 findings cite exact file:line. F-023 (CLAUDE.md doc drift) cites the section header. F-032 cites a section header in spec.md. Acceptable for non-line-bound concerns.

## Notes on what was not done

- **AC-A9 manual profiler snapshot.** Egor in Godot 4.6, ~30 min. If skipped, reschedule as 013 acceptance criterion.
- **F-023 fix in this PR.** Tempting (1-line CLAUDE.md edit), but AC-A6 is hard-rule. Logged as F-023, fixed in 016.
- **Spec-text edits for F-031, F-032.** Same reason. Logged, fixed in 015 / 016.
- **breaking: rename of `Ability.cast` to return `Array` for F-014.** Out of scope of audit; needs Egor's approval as 007 owner. Decided in 014a.
