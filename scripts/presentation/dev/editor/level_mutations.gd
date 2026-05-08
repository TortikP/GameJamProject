class_name LevelMutations
extends RefCounted

## Stateless data-mutation primitives for LevelData arrays. Extracted
## from EditorController (Φ-6 of 060) to keep the controller under its
## 300-line hard cap (AC33). All methods are static — no instance state.
##
## These are pure-data ops; rendering / autosave / overlay sync stay
## in the controller (they're side-effects on engine resources, not
## on the LevelData dictionary).


## Update an existing floor_cells entry by coord, or append if missing.
## Schema (LevelData line 49):
##   {"coord": Vector2i, "source_id": int, "atlas_coord": Vector2i}
static func set_or_update_floor_cell(cells: Array, coord: Vector2i,
		source_id: int, atlas_coord: Vector2i) -> void:
	for cell in cells:
		if Vector2i(cell["coord"]) == coord:
			cell["source_id"] = source_id
			cell["atlas_coord"] = atlas_coord
			return
	cells.append({
		"coord": coord, "source_id": source_id, "atlas_coord": atlas_coord,
	})


## Remove all entries whose `coord` == coord. Returns true if anything
## was removed. Used by erase_floor / erase_spawner / erase_object /
## cascade_at across the three layers.
static func remove_at_coord(arr: Array, coord: Vector2i) -> bool:
	var changed := false
	for i in range(arr.size() - 1, -1, -1):
		if Vector2i(arr[i]["coord"]) == coord:
			arr.remove_at(i)
			changed = true
	return changed


## Refresh an overlay from the latest data array if it exists and
## exposes a `refresh` method. No-op otherwise — overlays may be null
## when the corresponding NodePath didn't resolve.
static func refresh_overlay(overlay: Node, data: Array) -> void:
	if overlay != null and overlay.has_method("refresh"):
		overlay.refresh(data)
