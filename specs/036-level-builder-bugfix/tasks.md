# 036 — Tasks

Sequential. Each task is committable on its own.

## T-1. Audit JSON sprite paths
- [ ] For each `data/enemies/*.json`: check `sprite` value points to a real file under `assets/sprites/enemies/`.
- [ ] Resolve any drift (e.g. `bush.json` → `assets/sprites/enemies/bush.png` exists; double-check all 12).
- [ ] Output: list of mismatches if any. If list is non-empty, fix in this task.

## T-2. Extend `EnemyDataLoader.apply_to_actor` to return view hints
- [ ] File: `scripts/core/actors/enemy_data_loader.gd`.
- [ ] Change return type `bool` → `Dictionary`. Empty dict = failure.
- [ ] Populate `out["sprite"]` = `"res://" + data["sprite"]` if `data.has("sprite")`.
- [ ] Update doc-comment to describe the dict contract.

## T-3. Update `manekin_view.gd` to apply sprite from hints
- [ ] File: `scripts/presentation/godmode/manekin_view.gd`.
- [ ] Call site reads new `Dictionary` return.
- [ ] Resolve `Body` sprite, `load(hints["sprite"]) as Texture2D`, assign.
- [ ] Keep fallback (`max_hp <= 0` → 20) intact.
- [ ] **Rename file** to `enemy_view.gd`. Update `class_name` if any. Update `ext_resource` path in any .tscn that references it.

## T-4. Create `scenes/dev/enemy.tscn`
- [ ] Copy `scenes/dev/manekin.tscn` as starting point.
- [ ] Drop the `Texture2D ext_resource`. Body keeps `Sprite2D` node, no texture.
- [ ] Set `texture_filter = 1` on Body (nearest, for pixel art).
- [ ] Keep `HealthBar` (script + y_offset = -50.0).
- [ ] Keep `StatusIconStrip` (instance from `res://scenes/ui/status_icon_strip.tscn`, center_anchor (0, -82)).
- [ ] Root node name: `Enemy`. Script: `enemy_view.gd` (renamed in T-3).
- [ ] `enemy_data_id = &""` (must be set by spawner).
- [ ] Set `team = &"enemy"`.

## T-5. Collapse `ENEMY_SCENES` in `level_loader.gd`
- [ ] File: `scripts/core/maps/level_loader.gd`.
- [ ] Replace `MANEKIN_SCENE` / `BUSH_SCENE` consts + `ENEMY_SCENES` dict with single `const ENEMY_SCENE: PackedScene = preload("res://scenes/dev/enemy.tscn")`.
- [ ] In `spawn_enemy_at`: drop `ENEMY_SCENES.has(enemy_id)` guard. Add upfront `FileAccess.file_exists("res://data/enemies/%s.json" % enemy_id)` check. If missing → warn + return null (same warn message — `unknown enemy_id` is still accurate).
- [ ] After `instantiate()`, set `enemy.enemy_data_id = enemy_id` BEFORE `add_child`.
- [ ] Apply same changes to private `_spawn_enemy`.
- [ ] Drop unused `MANEKIN_SCENE` / `BUSH_SCENE` preloads.

## T-6. Delete `bush.tscn` and `manekin.tscn`
- [ ] `git grep -F "manekin.tscn"` and `git grep -F "bush.tscn"` — list every reference.
- [ ] For each ref: replace with `enemy.tscn`. If the ref is in a dev sandbox with a placed instance, that instance needs `enemy_data_id` set in the inspector.
- [ ] Likely suspects: `scenes/dev/godmode.tscn`, `scenes/arena/` subscenes, anything that pre-instances an enemy at edit time.
- [ ] After all refs migrated: `git rm scenes/dev/bush.tscn scenes/dev/manekin.tscn`.

## T-7. Verify sprite imports
- [ ] Open Godot editor once on this branch. Let it import all 12 enemy sprites.
- [ ] `git status` — confirm `.import` files appear under `assets/sprites/enemies/`.
- [ ] If `.gitignore` excludes `*.import` → leave it, document in HANDOFF that first-open imports are required. If it doesn't → commit them with this PR for one-shot setup.

## T-8. Smoke test
- [ ] Build a test level in the map editor with one of each: angel, bear, bee, burning_bear, bush, fire_slime, lavender_lion, manekin, monkey, mushroom_boar, stapler, teapot.
- [ ] Save, reload as a level — confirm zero `unknown enemy_id` warnings, every enemy spawns with the correct sprite.
- [ ] Confirm existing saved levels (find one in `data/maps/`) still load cleanly.

## T-9. Cleanup pass
- [ ] Re-grep `manekin` across the repo — anything still referencing the removed scene/script/file should be flagged.
- [ ] Update CLAUDE.md ownership table or HANDOFF only if the architecture change deserves a note. Otherwise leave both alone (don't churn docs for a localized fix).

## Dependency graph

```
T-1 ──┐
      ├─→ T-2 ──→ T-3 ──→ T-4 ──→ T-5 ──→ T-6 ──→ T-7 ──→ T-8 ──→ T-9
      │                                  ↑
      └──────────────────────────────────┘   (T-1 results may need to flow into T-5's
                                              file_exists check or per-JSON fixes)
```

T-1 surfaces data issues early. T-2..T-5 are the core fix. T-6 is destructive cleanup, can't run before T-5 makes the new path live. T-7 is environmental. T-8/T-9 are validation.
