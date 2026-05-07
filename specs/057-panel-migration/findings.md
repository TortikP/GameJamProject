# 057 — Findings

Surprises encountered during T001–T013 implementation. Spec/plan didn't predict
these; surfacing here for review.

## F-057-IMPL-1 — `dialogue_trigger_panel.tscn` was an unused stub

**Discovered in:** T005.
**Decision made:** delete the file, don't re-create.
**Diverges from spec:** Q-057-2 → B (re-create) is now N/A.

### What was assumed in spec

Plan §dialogue_trigger_panel.tscn re-create assumed `scenes/dev/dialogue_trigger_panel.tscn`
was actively used by `map_editor.tscn` via `instance=...`. Andrey confirmed B (re-create
from scratch) on this assumption.

### What's actually true

`scenes/dev/dialogue_trigger_panel.tscn` was a 6-line stub:

```
[gd_scene load_steps=2 format=3 uid="uid://dialogue_trigger_panel"]
[ext_resource type="Script" path="res://scripts/presentation/dev/dialogue_trigger_panel.gd" id="1_dtp"]
[node name="DialogueTriggerPanel" type="PanelContainer"]
script = ExtResource("1_dtp")
```

`grep -rn "dialogue_trigger_panel.tscn\|uid://dialogue_trigger_panel"` across the
entire repo returned **zero matches**. `map_editor.tscn` line 166 (pre-057) created
DialogueTriggerPanel directly as `[node type="PanelContainer"] script=...`, not
through `instance=` on the stub .tscn. The stub never ran in the project.

### What was done

Stub deleted. DialogueTriggerPanel migrated to `instance=base_panel.tscn` directly
in `map_editor.tscn` — same pattern as the other 4 panels. Net result: one fewer
file, no functional change.

### Why this is fine

The plan-B re-create would have produced an identical-looking `.tscn` that nobody
references. Deleting + treating DTP like the other 4 reaches the same target with
less indirection.

### What if you'd rather have the .tscn back

Trivial to add: create `scenes/dev/dialogue_trigger_panel.tscn` with the inherited-
scene root pointing at `base_panel.tscn` + DTP script attached + exports set, then
change `map_editor.tscn` DialogueTriggerPanel node from `instance=base_panel.tscn`
to `instance=dialogue_trigger_panel.tscn`. Single follow-up commit. But there's no
visible benefit unless DTP starts being instantiated from multiple scenes.

---

## F-057-IMPL-2 — Godot 4 `super._ready()` trap

**Discovered in:** mid-T005.
**Severity:** would have silently broken all 5 panels in runtime — caught before push.

### The trap

In Godot 4, when a subclass overrides `_ready()`, **the parent's `_ready()` is NOT
called automatically.** The subclass `_ready()` fully replaces the parent's.

This is different from typical OOP languages with implicit super-init, and is a
behavior change relative to Godot 3 in some corner cases.

### Why this matters for spec 057

`BasePanel._ready()` does **all** of:
- `_resolve_nodes()` — find header/body/resize-frame nodes by NodePath
- `_compute_effective_flags()` — derive interactive flags from exports
- `_apply_chrome_visibility()` — pinned-mode handling
- `_apply_title()` — Localization lookup for header label
- `_apply_theme()` — UiTheme styleboxes for header + body
- `_setup_handlers()` — instantiate PanelDragHandler / Resize / Collapse / Lock
- `_setup_persistence()` — load saved layout from `user://layouts.cfg`
- `EventBus.ui_theme_reloaded.connect(_apply_theme)`
- `get_viewport().size_changed.connect(_on_viewport_size_changed)`

If we'd shipped without `super._ready()`:
- No drag, no resize, no collapse, no lock — all 5 panels frozen in their default
  position with broken `−`/`+` and lock icons.
- No persistence — layout never saved, never restored.
- No theme — header/body would render bare without styleboxes.
- Not even title shown (no Localization lookup).

In short: BasePanel would essentially do nothing.

### Initial draft was wrong

The first iteration of all 5 migrations had a comment that read:

> super._ready() is called automatically by Godot before this body runs.

This was wrong. The correct semantic is: parent `_ready()` is NOT auto-called when
subclass overrides; you must `super._ready()` explicitly.

### What was done

Patched all 5 panels (`floor_palette`, `object_palette`, `tool`, `level_meta`,
`dialogue_trigger`) to insert explicit `super._ready()` as the first line of their
`_ready()`. Comment updated to match reality.

### Recommendation

Add a row to **CLAUDE.md → Known Godot 4.6 traps** so this doesn't re-occur in
future BasePanel subclasses (or any other inheritance chain in the project). The
catalog precedent (`ui_catalog.tscn`) doesn't catch this because catalog panels
use bare `BasePanel` without subclass scripts — there's no override → no trap.

Suggested row:

```
| Subclass overriding _ready / _process / _input does NOT auto-invoke parent's.
  Godot 4 silently runs only the most-derived implementation. If your script
  `extends X` and X._ready does setup work, your override drops all of it
  unless you `super._ready()` first. | Always start the override with
  `super._ready()` (or `super._process(delta)` etc.) when extending a
  framework class with non-trivial lifecycle methods. Bare extension scripts
  (no `_ready` override) are unaffected — Godot calls the parent's. |
```

---

## F-057-IMPL-3 — DTP collapse-on-form-close UX divergence (minor)

**Discovered in:** T005 .gd refactor.
**Severity:** cosmetic, surfacing for transparency.

### What changed

The pre-057 `DialogueTriggerPanel._on_collapse_toggled` ad-hoc collapse handler
explicitly closed the edit form on collapse:

```gdscript
_form_container.visible = false  # always close form on collapse
_form_error_label.visible = false
```

Post-057, BasePanel's `PanelCollapseHandler` hides the entire `BodyPanel` —
form's `visible` state is not modified. So if user clicks "Add" → form opens →
user collapses panel → user re-expands → form is **still open**.

### Why this is acceptable

- It's user state. Preserving it through a collapse/expand round-trip is
  arguably better than silently closing — user keeps their work-in-progress.
- The original force-close was likely defensive. No bug repro is on file
  for "form open across collapse".
- Spec 057 explicitly aimed for "no UX redesign". This is a tiny side-effect
  of switching to BasePanel; reproducing the old behavior would require a
  signal handler on `BasePanel.collapsed_changed` and adding logic. Not in
  scope for a parse-error-fix spec.

### What if you want the old behavior back

Connect to `BasePanel.collapsed_changed(is_collapsed)` from inside DTP and
mirror the form-close logic. ~5 lines. Add as a chore: commit if Niikta or
Andrey reports the new behavior is annoying after using it.
