extends Node2D
## HealthBar — small bar drawn above the parent Actor.
##
## Draws via _draw(); listens to parent Actor's `damaged` signal and
## redraws on change. Hidden when at full HP unless a damage preview
## is set (then shows current/max + a red strip indicating predicted loss).

const WIDTH: float = 30.0
const HEIGHT: float = 4.0
const COLOR_BG: Color = Color(0.10, 0.10, 0.10, 0.85)
const COLOR_HP: Color = Color(0.30, 0.85, 0.30, 1.0)
const COLOR_PREVIEW: Color = Color(0.95, 0.20, 0.20, 0.95)
const COLOR_FRAME: Color = Color(0, 0, 0, 0.6)
const COLOR_TEXT: Color = Color(1, 1, 1, 0.95)
const FONT_SIZE: int = 9

@export var y_offset: float = -24.0  # tweak per scene if sprite size differs

var _actor: Actor
var _preview_damage: int = 0


func _ready() -> void:
	_actor = get_parent() as Actor
	if _actor == null:
		push_warning("HealthBar: parent is not Actor")
		return
	_actor.damaged.connect(_on_damaged)


func _on_damaged(_id: StringName, _amount: int, _hp_left: int) -> void:
	queue_redraw()


## Set predicted incoming damage. 0 to clear. Used by hover-preview UI.
func set_preview_damage(amount: int) -> void:
	if _preview_damage == amount:
		return
	_preview_damage = amount
	queue_redraw()


func _draw() -> void:
	if _actor == null or _actor.max_hp <= 0:
		return
	# Always draw — bar is part of actor identity, not just damage indicator.
	var hp_ratio: float = float(_actor.hp) / float(_actor.max_hp)
	var dmg_ratio: float = clampf(float(_preview_damage) / float(_actor.max_hp), 0.0, hp_ratio)
	var green_w: float = WIDTH * (hp_ratio - dmg_ratio)
	var red_w: float = WIDTH * dmg_ratio
	var x: float = -WIDTH * 0.5
	# Background
	draw_rect(Rect2(x, y_offset, WIDTH, HEIGHT), COLOR_BG, true)
	# Green = remaining HP after the predicted hit
	if green_w > 0.0:
		draw_rect(Rect2(x, y_offset, green_w, HEIGHT), COLOR_HP, true)
	# Red = predicted damage strip (sits between green and current end)
	if red_w > 0.0:
		draw_rect(Rect2(x + green_w, y_offset, red_w, HEIGHT), COLOR_PREVIEW, true)
	# Frame
	draw_rect(Rect2(x, y_offset, WIDTH, HEIGHT), COLOR_FRAME, false, 1.0)
	# Numbers above the bar
	var font: Font = ThemeDB.fallback_font
	var text: String = "%d/%d" % [_actor.hp, _actor.max_hp]
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
	draw_string(font, Vector2(-size.x * 0.5, y_offset - 2.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, COLOR_TEXT)
