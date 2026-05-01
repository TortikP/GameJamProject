extends Node2D
## HealthBar — small bar drawn above the parent Actor.
##
## Draws via _draw(); listens to parent Actor's `damaged` signal and
## redraws on change. Hidden when at full HP unless a damage preview
## is set (then shows current/max + a red strip indicating predicted loss).
##
## Palette comes from UiTheme — fill color follows hp_color_for thresholds
## (full → green, ≤30% → orange, ≤15% → red), outline follows team_color.
## Subscribes to EventBus.ui_theme_reloaded for hot-reload.

const WIDTH: float = 30.0
const HEIGHT: float = 4.0
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
	EventBus.ui_theme_reloaded.connect(queue_redraw)


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
	var fill_w: float = WIDTH * (hp_ratio - dmg_ratio)
	var preview_w: float = WIDTH * dmg_ratio
	var x: float = -WIDTH * 0.5
	var fill_color: Color = UiTheme.hp_color_for(hp_ratio)
	var team_outline: Color = UiTheme.team_color(_actor.team)
	# Background
	draw_rect(Rect2(x, y_offset, WIDTH, HEIGHT), UiTheme.HP_BG, true)
	# Fill = remaining HP after the predicted hit (color reflects threshold)
	if fill_w > 0.0:
		draw_rect(Rect2(x, y_offset, fill_w, HEIGHT), fill_color, true)
	# Preview strip = predicted damage (sits between fill and current end)
	if preview_w > 0.0:
		draw_rect(Rect2(x + fill_w, y_offset, preview_w, HEIGHT), UiTheme.HP_PREVIEW, true)
	# Frame — team-colored outline (Pillar 2 symmetry: same bar, team via color)
	draw_rect(Rect2(x, y_offset, WIDTH, HEIGHT), team_outline, false, 1.0)
	# Numbers above the bar
	var font: Font = ThemeDB.fallback_font
	var text: String = "%d/%d" % [_actor.hp, _actor.max_hp]
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
	draw_string(font, Vector2(-size.x * 0.5, y_offset - 2.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, UiTheme.TEXT)
