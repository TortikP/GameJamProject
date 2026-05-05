# 036 — Level builder / runtime enemy spawn asymmetry

**Owner:** Egor
**Type:** Bugfix
**Touches:**
- `scripts/core/maps/level_loader.gd` (root cause)
- `scripts/presentation/godmode/manekin_view.gd` (sprite from JSON)
- `scenes/dev/manekin.tscn` (rename → generic enemy.tscn, drop hardcoded texture)
- `scenes/dev/bush.tscn` (delete — replaced by generic scene)
- `data/enemies/*.json` (verify `sprite` field on all 12 entries)

## Problem

Map editor lets the user place 12 enemy types (`angel`, `bear`, `bee`, `burning_bear`, `bush`, `fire_slime`, `lavender_lion`, `manekin`, `monkey`, `mushroom_boar`, `stapler`, `teapot` — anything in `data/enemies/*.json`). Runtime can spawn only **2** of them (`manekin`, `bush`). Everything else fails at level load with:

```
[WARN][LevelLoader] spawn_enemy_at: unknown enemy_id 'bear' at (-8, -4)
```

The level data file is fine. The JSON files are fine. The bug is that **the editor is data-driven and the loader is not**.

## Root cause

`scripts/core/maps/level_loader.gd:26-29`:

```gdscript
const ENEMY_SCENES: Dictionary = {
    &"manekin": MANEKIN_SCENE,
    &"bush": BUSH_SCENE,
}
```

Hardcoded id → `PackedScene` map. Compare with the editor side, `scripts/presentation/dev/object_palette_panel.gd:147-159`:

```gdscript
var dir := DirAccess.open(ENEMIES_DIR)   # res://data/enemies/
...
while fname != "":
    if not dir.current_is_dir() and fname.ends_with(".json"):
        var enemy_id := fname.get_basename()
        _content.add_child(_make_spawner_button(label, &"enemy", StringName(enemy_id)))
```

Editor scans the JSON dir → exposes everything. Runtime asks a hand-maintained dict → only `manekin` + `bush` known. The two sides drift any time someone adds a JSON without touching `level_loader.gd`. PR #64 was exactly that — added 10 sprites + 10 JSONs, didn't touch the loader.

Why `player` isn't affected: `_spawn_player` is a separate path with its own `PLAYER_SCENE` preload, never goes through `ENEMY_SCENES`.

Why `bush` isn't affected: only enemy that has both a `.tscn` and a dict entry. Coincidence of being the original placeholder.

## Secondary symptom (same architectural smell)

`bush.tscn` and `manekin.tscn` are nearly identical — same script (`manekin_view.gd`), same `HealthBar`, only the texture and `enemy_data_id` differ. Texture is hardcoded as `ext_resource` in the scene:

```
[ext_resource type="Texture2D" path="res://assets/sprites/bush.png" id="3_sprite"]
```

But the JSON already carries `"sprite": "assets/sprites/enemies/bush.png"`. The sprite-path field is currently **dead data** — view never reads it. Any naïve fix that just adds 10 missing scenes ([scenes/dev/bear.tscn, bee.tscn, …]) reproduces this dead-data anti-pattern 10× over.

## Fix direction

Make the loader symmetric to the editor: **one generic enemy scene**, sprite loaded from JSON `sprite` field. Then `ENEMY_SCENES` collapses to a single `ENEMY_SCENE` constant — no per-enemy maintenance.

After the fix:
- Adding an enemy = drop `<id>.json` + `<id>.png` into the right folders. No code, no scene work.
- Editor and runtime both scan the same source of truth.
- `manekin.tscn` and `bush.tscn` are deleted; replaced by `enemy.tscn`.

## Out of scope

- `SkillDatabase` warning about `skill_debug_punch` — same pattern smell, separate spec. Don't bundle.
- Sprite import status (`.import` files missing in `assets/sprites/enemies/`) — likely fixes itself on next editor open; if not, a one-line fix separately.
- Per-enemy custom view tweaks (different healthbar offsets, status-strip positions) — current scenes already differ here. Punted to follow-up: read offsets from JSON too. Not blocking.

## Acceptance criteria

- [ ] Level with all 12 enemy types loads with zero `unknown enemy_id` warnings.
- [ ] Adding a new `data/enemies/<id>.json` + `assets/sprites/enemies/<id>.png` makes that enemy placeable in editor AND spawnable at runtime, no GDScript changes.
- [ ] `level_loader.gd` no longer contains a per-enemy id list.
- [ ] `bush.tscn` and `manekin.tscn` removed; `enemy.tscn` is the only enemy scene.
- [ ] Existing levels (any saved before this PR) still load — `enemy_id`s in their JSON resolve through the new path.
