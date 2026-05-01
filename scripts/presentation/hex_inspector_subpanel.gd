extends VBoxContainer
## HexInspectorSubpanel — read-only panel showing the hex coord under the
## hover/inspect cursor: coord, tile kind, optional active effect.
##
## Currently lives inside ActorInspector as the HexSection sub-tree. T035
## refactors this out so the same widget can be reused in production arena
## scenes that don't need the full ActorInspector. ActorInspector keeps its
## hex section intact for backwards compat — this is a parallel component.
##
## Wiring: parent it under any HUD container. Call bind_hex(coord, kind, eff)
## to update. Call unbind_hex() to clear and hide.

@onready var _coord_label: Label  = $LabelHexCoord
@onready var _kind_label: Label   = $LabelHexKind
@onready var _effect_label: Label = $LabelHexEffect


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	hide()


func _apply_theme() -> void:
	UiTheme.apply_label_kind(_coord_label, "small")
	UiTheme.apply_label_kind(_kind_label, "body")
	_effect_label.add_theme_font_size_override("font_size", UiTheme.FS_SMALL)
	_effect_label.add_theme_color_override("font_color", UiTheme.SEM_DEBUFF)


func bind_hex(coord: Vector2i, tile_kind: StringName, effect_id: StringName) -> void:
	_coord_label.text = "(%d, %d)" % [coord.x, coord.y]
	_kind_label.text = String(tile_kind) if tile_kind != &"" else "—"
	if effect_id != &"":
		_effect_label.text = String(effect_id)
		_effect_label.show()
	else:
		_effect_label.hide()
	show()


func unbind_hex() -> void:
	hide()
