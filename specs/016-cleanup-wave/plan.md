# 016-cleanup-wave — plan

## Approach

Четыре кластера, каждый = один атомарный commit. Внутри кластера правки независимы по файлам, но семантически связаны.

- **A — deletes** (F-024..F-027 + F-016, F-017, F-028 self-resolve): удалить 4 пары `.gd`+`.tscn`, dropped EventBus signal, обновить doc-comment в `hex_grid.gd`.
- **B — UiTheme misses** (F-018, F-019, F-020): добавить 3 константы и 1 helper в `ui_theme.gd`, переписать use-sites в `slot_bar.gd` и `status_icon_strip.gd`.
- **C — code micro-fixes** (F-030, F-033, F-034): 1 rename, 1 preload, 1 NodePath @export.
- **D — spec text** (F-031, F-032): редактируем 2 spec.md.

Один PR — все 4 кластера. Slicing by concern уже произошёл на уровне 014/015; для P3 косметики separate-PR overhead дороже review-time.

## Dependencies

- A независим. Может пойти первым/последним без разницы.
- B независим (UiTheme + 2 consumer-файла).
- C независим (3 разных файла).
- D независим (только doc).

Порядок коммитов: A → B → C → D, чисто из-за читаемости diff'а (deletes show first, doc last).

## Files affected

### Cluster A (deletes)
- DELETE `scripts/presentation/portal_transition.gd`
- DELETE `scenes/ui/portal_transition.tscn`
- DELETE `scripts/presentation/hex_placeholder_builder.gd`
- DELETE `scripts/presentation/run_summary.gd`
- DELETE `scenes/ui/run_summary.tscn`
- DELETE `scripts/presentation/loading_cover.gd`
- DELETE `scenes/ui/loading_cover.tscn`
- EDIT `scripts/infrastructure/event_bus.gd` — drop `signal run_summary_shown(summary: Dictionary)` line.
- EDIT `scripts/core/arena/hex_grid.gd:42` — strip `HexPlaceholderBuilder.setup()` doc reference.

### Cluster B (UiTheme misses)
- EDIT `scripts/presentation/ui_theme.gd` — add constants `FOCUS_ACTIVE_CASTABLE`, `FOCUS_ACTIVE_DISABLED`, `HOVER_BRIGHTEN`; add `make_pill_stylebox(family)`.
- EDIT `scripts/presentation/slot_bar.gd:184-185,196` — replace inline `Color(...)`.
- EDIT `scripts/presentation/status_icon_strip.gd:96-114` — replace local `_make_pill_stylebox` + call site.

### Cluster C (code micro-fixes)
- EDIT `scripts/core/abilities/ability_database.gd` — rename method `_build_ability_from_dict` → `build_ability_from_dict`. Update self-call at line 108.
- EDIT `scripts/core/skills/skill_database.gd:81` — call site update.
- EDIT `scripts/presentation/dialogue_manager.gd:6,104` — `const PANEL_SCENE := preload(...)`, drop runtime `load()`.
- EDIT `scripts/presentation/godmode/godmode_controller.gd` — add `@export var player_status_panel_path: NodePath`, helper `_get_player_status_panel()`, swap 2 hardcoded path lookups.
- EDIT `scenes/dev/godmode.tscn:49-55` — add `player_status_panel_path = NodePath("../HUD/PlayerStatusPanel")`.

### Cluster D (spec text)
- EDIT `specs/011-skill-tags/spec.md:34` — F1/F2/F3/F4 → Q/W/E/R (или 1/2/3/4).
- EDIT `specs/003-dialogue-manager/spec.md` — §Content & smoke bullet 3 + §Acceptance verification step 1.

## Specifics

### Cluster B — UiTheme constants

Two constants instead of one helper because the use-sites in `slot_bar.gd:184-185` are static — the FOCUS-derived colors don't change per-frame, no reason to recompute via lambda. Pre-bake.

```gdscript
# ── Slot focus / hover modulation (009/T044+ slot_bar) ───────
# Active slot when castable: FOCUS yellow brightened ×1.3 with green knocked
# down ×0.5 (hue shift toward gold). Pre-baked from FOCUS literal — see slot_bar.
const FOCUS_ACTIVE_CASTABLE := Color(FOCUS.r * 1.3, FOCUS.g * 1.3, FOCUS.b * 0.5, 1.0)
# Active slot when not castable (out of range / cooldown): FOCUS desaturated.
const FOCUS_ACTIVE_DISABLED := Color(FOCUS.r,       FOCUS.g,       FOCUS.b * 0.7, 1.0)
# Hover brighten for filled-castable slots and similar interactive elements.
const HOVER_BRIGHTEN        := Color(1.10, 1.10, 1.10)
```

Note: `Color(FOCUS.r * 1.3, ...)` here in `ui_theme.gd` is allowed — это и есть source-of-truth слой, AC-12 явно allow's `Color(...)` inside ui_theme.gd. Const-init evaluates at parse time once, so no per-frame cost.

### Cluster B — make_pill_stylebox

Move `_make_pill_stylebox` from `status_icon_strip.gd:96-114` verbatim into `ui_theme.gd`, drop the underscore, exposed as `static func make_pill_stylebox(family: StringName) -> StyleBoxFlat`. Constants used inside (`UiTheme.SP_1`, `UiTheme.semantic_color`) are the same since we're moving into the same class — no rewrite needed.

### Cluster C — F-034 export

Pattern matches existing `slot_bar`/`inspector_path`/`overlay_path` exports. Helper:

```gdscript
func _get_player_status_panel() -> Node:
    if player_status_panel_path != NodePath(""):
        var psp := get_node_or_null(player_status_panel_path)
        if psp != null:
            return psp
    # Fallback: hardcoded path for standalone scene-tree variations (e.g. test scenes).
    return get_node_or_null("../HUD/PlayerStatusPanel")
```

Use site replaces 2 lines each. Ranges: `_ready` ~line 139 (bind_player), `_on_slot_activated` ~line 495 (set_active_spell).

### Cluster C — F-033 preload

```gdscript
const PANEL_SCENE := preload("res://scenes/ui/dialogue_panel.tscn")  # PackedScene
```

`_get_panel()` becomes:
```gdscript
_panel = PANEL_SCENE.instantiate()
```

(drop the `load(PANEL_SCENE)` wrapper)

## Smoke

Per cluster, after commit:
- A: project loads in Godot without parse errors. Search project-wide for deleted symbols → 0 hits.
- B: open `godmode.tscn` → slot_bar visuals same as before. Cast skill that applies a status (when status engine arrives — pill style unchanged for now).
- C: F-030 — godmode loads, casting skill (which goes through `SkillDatabase` → `AbilityDatabase.build_ability_from_dict`) doesn't crash. F-033 — F1 on `dialogue_preview.tscn` (or whichever launches dialogue) works. F-034 — godmode boot, PlayerStatusPanel binds (look for log line / verify HP shows on PSP); slot select pushes spell description.
- D: doc only, no smoke.

Manual smoke deferred to Egor on local machine. CI doesn't exist for the jam.

## HANDOFF.md links

- §728 (tasks.md priority convention) — P3 marker meaning.
- §1.5 (THEME_PLAN.md design pillars) — n/a, this is dev-debt cleanup.
- 012-ultrareview/findings.md §"Refactor PR backlog" — slicing source.
