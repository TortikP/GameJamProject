class_name EditorPalettePrefs
extends RefCounted

## Cross-session persistence for the level editor's palette state:
##   - active_layer: which of three layers is selected on launch.
##   - per-layer selection: the last item chosen in each palette.
##
## Stored in user://editor_palette_prefs.cfg. ConfigFile-based with
## flat keys per layer section — Variant round-trip is brittle for
## StringName / Vector2i / Dictionary, so we serialize each schema
## explicitly. All-static; no instance state.
##
## Flow on _ready:
##   load_active_layer → set _layers.active_layer
##   for each layer:
##     load_selection → palette.select_value(stored) if it matches
##                    → else palette.quick_select(1) for first-button
##
## Flow on selection change:
##   _on_layer_selection_changed → save_selection(layer_id, value)

const PATH := "user://editor_palette_prefs.cfg"
const SECTION_META := "meta"
const KEY_ACTIVE_LAYER := "active_layer"


## Persist a per-layer selection. value contract per layer:
##   hexes:    Dictionary{source_id, atlas_coord} OR StringName &"erase"
##   spawners: Dictionary{kind, ref}
##   objects:  Dictionary{object_id}
static func save_selection(layer_id: StringName, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # missing file is OK; ConfigFile reports err but state is empty
	var section := String(layer_id)
	if cfg.has_section(section):
		cfg.erase_section(section)
	match layer_id:
		LayersModel.LAYER_HEXES:
			if typeof(value) == TYPE_STRING_NAME and StringName(value) == &"erase":
				cfg.set_value(section, "erase", true)
			elif typeof(value) == TYPE_DICTIONARY:
				var d: Dictionary = value
				cfg.set_value(section, "source_id", int(d.get("source_id", 0)))
				var ac: Vector2i = d.get("atlas_coord", Vector2i.ZERO)
				cfg.set_value(section, "atlas_x", ac.x)
				cfg.set_value(section, "atlas_y", ac.y)
		LayersModel.LAYER_SPAWNERS:
			if typeof(value) == TYPE_DICTIONARY:
				var d: Dictionary = value
				cfg.set_value(section, "kind", String(d.get("kind", "")))
				cfg.set_value(section, "ref", String(d.get("ref", "")))
		LayersModel.LAYER_OBJECTS:
			if typeof(value) == TYPE_DICTIONARY:
				var d: Dictionary = value
				cfg.set_value(section, "object_id", String(d.get("object_id", "")))
	cfg.save(PATH)


## Read back a per-layer selection. Returns null on no record / parse
## failure — caller should fall back to first-button select.
static func load_selection(layer_id: StringName) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return null
	var section := String(layer_id)
	if not cfg.has_section(section):
		return null
	match layer_id:
		LayersModel.LAYER_HEXES:
			if bool(cfg.get_value(section, "erase", false)):
				return &"erase"
			return {
				"source_id": int(cfg.get_value(section, "source_id", 0)),
				"atlas_coord": Vector2i(
					int(cfg.get_value(section, "atlas_x", 0)),
					int(cfg.get_value(section, "atlas_y", 0)),
				),
			}
		LayersModel.LAYER_SPAWNERS:
			return {
				"kind": StringName(String(cfg.get_value(section, "kind", ""))),
				"ref": StringName(String(cfg.get_value(section, "ref", ""))),
			}
		LayersModel.LAYER_OBJECTS:
			return {
				"object_id": StringName(String(cfg.get_value(section, "object_id", ""))),
			}
	return null


static func save_active_layer(layer_id: StringName) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(SECTION_META, KEY_ACTIVE_LAYER, String(layer_id))
	cfg.save(PATH)


## Returns persisted active layer id, or LayersModel.LAYER_HEXES if no
## record exists.
static func load_active_layer() -> StringName:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return LayersModel.LAYER_HEXES
	var stored := String(cfg.get_value(SECTION_META, KEY_ACTIVE_LAYER, ""))
	if stored == "":
		return LayersModel.LAYER_HEXES
	return StringName(stored)
