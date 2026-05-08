class_name PaletteHelpers
extends RefCounted

## Shared helpers for editor palettes (HexTilePalette, SpawnerPalette,
## ObjectPalette). Three palettes use the same "digit badge in corner
## of first 9 buttons" UX, so it lives here as a single static helper
## rather than copy-pasted three times.

const _BADGE_COLOR := Color(1.0, 1.0, 0.4, 0.9)


## Decorate the first up-to-9 buttons in `buttons` with a Label showing
## the keyboard digit (1-9) in the top-left corner. The Label is added
## as a child of each Button with mouse_filter=IGNORE so it doesn't
## intercept clicks. Buttons beyond index 8 are not decorated and not
## reachable via 1-9 quick-select (spec.md AC14).
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
