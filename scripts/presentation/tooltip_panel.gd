extends PanelContainer
## TooltipPanel — generic tooltip surface. Single instance lives on a HUD
## CanvasLayer; called from anywhere via show_tooltip(anchor, title, body).
##
## Auto-suppression: listens to EventBus.ui_modal_opened — while any modal
## is open, hides itself and ignores show requests. ui_modal_closed re-enables.
##
## Positioning: anchored above-or-below `anchor` Control. If anchor isn't
## given, just uses current global mouse position.

@onready var _title_label: Label = $VBox/TitleLabel
@onready var _body_label: Label  = $VBox/BodyLabel

var _suppressed: bool = false


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	EventBus.ui_modal_opened.connect(_on_modal_opened)
	EventBus.ui_modal_closed.connect(_on_modal_closed)


func _apply_theme() -> void:
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox(true))
	UiTheme.apply_label_kind(_title_label, "header")
	UiTheme.apply_label_kind(_body_label, "small")


## Show the tooltip with optional anchor. If anchor is null, positions at
## the mouse pointer with a small offset. Body string supports plain text.
func show_tooltip(anchor: Control, title: String, body: String = "") -> void:
	if _suppressed:
		return
	_title_label.text = Localization.t(title, title)
	if body.is_empty():
		_body_label.hide()
	else:
		_body_label.text = Localization.t(body, body)
		_body_label.show()
	# Make sure size is computed before placement.
	visible = true
	# Defer placement one frame so the panel has its final size to position by.
	call_deferred("_place_near", anchor)


func hide_tooltip() -> void:
	visible = false


func _place_near(anchor: Control) -> void:
	if not visible:
		return
	var screen_size: Vector2 = get_viewport_rect().size
	var pad: float = float(UiTheme.SP_2)
	var pos: Vector2
	if anchor != null and is_instance_valid(anchor):
		var rect := anchor.get_global_rect()
		# Prefer above the anchor; fall back to below if no room.
		var above_y: float = rect.position.y - size.y - pad
		var below_y: float = rect.position.y + rect.size.y + pad
		pos = Vector2(rect.position.x, above_y if above_y >= 0.0 else below_y)
	else:
		pos = get_global_mouse_position() + Vector2(12.0, 12.0)
	# Clamp to screen.
	pos.x = clampf(pos.x, pad, screen_size.x - size.x - pad)
	pos.y = clampf(pos.y, pad, screen_size.y - size.y - pad)
	global_position = pos


func _on_modal_opened(_id: StringName) -> void:
	_suppressed = true
	hide_tooltip()


func _on_modal_closed(_id: StringName) -> void:
	# We don't track modal-stack depth here — the host (godmode/arena) is
	# responsible for not flooding modal events out of order. After last
	# close, the next show_tooltip call works normally.
	_suppressed = false
