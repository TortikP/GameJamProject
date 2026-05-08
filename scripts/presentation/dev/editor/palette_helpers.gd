class_name PaletteHelpers
extends RefCounted

## Shared helpers for editor palettes (HexTilePalette, SpawnerPalette,
## ObjectPalette). Three palettes use the same icon button + 1-9 badge
## UX, so it lives here as a single static helper rather than copy-
## pasted three times.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")

## Uniform icon size across all three palettes (spec 060 visuals).
## 72×72 — large enough that pixel-art enemy sprites and hex tiles
## both read cleanly; LayersPanel min size accommodates ~3 per row.
const ICON_SIZE := Vector2(72, 72)

const _BADGE_COLOR := Color(1.0, 1.0, 0.4, 0.9)


## Build a standard icon button: fixed ICON_SIZE, ButtonGroup-ready
## toggle, optional Texture2D icon, glyph fallback when texture is
## null (used for "no asset" cases — Player has no sprite, missing
## enemy / object PNGs degrade to a single-letter monogram). Caller
## connects `pressed` and adds to a container.
static func make_icon_button(group: ButtonGroup, label: String,
		texture: Texture2D = null, fallback_glyph: String = "") -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = group
	btn.custom_minimum_size = ICON_SIZE
	btn.tooltip_text = label
	if texture != null:
		btn.icon = texture
		btn.expand_icon = true
	else:
		btn.text = fallback_glyph if fallback_glyph != "" else label.substr(0, 1).to_upper()
	UiTheme.apply_button_styling(btn)
	return btn


## Safe texture load with res:// normalization. Returns null on any
## failure (path empty, file missing, resource not a Texture2D).
## Used by SpawnerPalette (enemy JSON `sprite` field) and ObjectPalette
## (TileObject.sprite_path) — both go through this so the failure mode
## (-> button gets the glyph fallback) is uniform.
static func load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var p: String = path if path.begins_with("res://") else "res://" + path
	if not ResourceLoader.exists(p):
		return null
	var res: Resource = load(p)
	return res as Texture2D


## Decorate the first up-to-9 buttons with a Label showing the keyboard
## digit (1-9) in the top-left corner. The Label is mouse_filter=IGNORE
## so it doesn't intercept clicks. Buttons beyond index 8 are not
## decorated and not reachable via 1-9 quick-select (spec.md AC14).
static func decorate_quick_select_badges(buttons: Array[Button]) -> void:
	var n: int = mini(9, buttons.size())
	for i in range(n):
		var btn := buttons[i]
		if btn == null or not is_instance_valid(btn):
			continue
		var badge := Label.new()
		badge.name = "QuickSelectBadge"
		badge.text = str(i + 1)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_color_override("font_color", _BADGE_COLOR)
		badge.position = Vector2(2, 2)
		btn.add_child(badge)
