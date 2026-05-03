extends Node2D
## HealthBar — bar drawn above the parent Actor.
##
## Draws via _draw(); listens to parent Actor's `damaged` signal and
## redraws on change. Hidden when at full HP unless a damage preview
## is set (then shows current/max + a red strip indicating predicted loss).
##
## Sizing comes from UiTheme.BAR_*_OVERHEAD — visibility doctrine in CLAUDE.md
## says world UI reads at default zoom or it doesn't ship. HP digits use
## draw_string_outline for crisp dark outline so they read against grass,
## fire, blood, hex tiles, anything.
##
## Palette comes from UiTheme — fill color follows hp_color_for thresholds
## (full → green, ≤30% → orange, ≤15% → red), outline follows team_color.
## Subscribes to EventBus.ui_theme_reloaded for hot-reload.

@export var y_offset: float = -28.0  # tweak per scene if sprite size differs

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
	var width: float = UiTheme.BAR_WIDTH_OVERHEAD
	var height: float = UiTheme.BAR_HEIGHT_OVERHEAD
	var font_size: int = UiTheme.BAR_FONT_SIZE_OVERHEAD
	# Always draw — bar is part of actor identity, not just damage indicator.
	var hp_ratio: float = float(_actor.hp) / float(_actor.max_hp)
	var dmg_ratio: float = clampf(float(_preview_damage) / float(_actor.max_hp), 0.0, hp_ratio)
	var fill_w: float = width * (hp_ratio - dmg_ratio)
	var preview_w: float = width * dmg_ratio
	var x: float = -width * 0.5
	var fill_color: Color = UiTheme.hp_color_for(hp_ratio)
	var team_outline: Color = UiTheme.team_color(_actor.team)
	# Background
	draw_rect(Rect2(x, y_offset, width, height), UiTheme.HP_BG, true)
	# Fill = remaining HP after the predicted hit (color reflects threshold)
	if fill_w > 0.0:
		draw_rect(Rect2(x, y_offset, fill_w, height), fill_color, true)
	# Preview strip = predicted damage (sits between fill and current end)
	if preview_w > 0.0:
		draw_rect(Rect2(x + fill_w, y_offset, preview_w, height), UiTheme.HP_PREVIEW, true)
	# Frame — team-colored outline (Pillar 2 symmetry: same bar, team via color),
	# 2px wide so it reads at the new bar size.
	draw_rect(Rect2(x, y_offset, width, height), team_outline, false, 2.0)
	# Numbers above the bar — outline first for contrast on any background,
	# then fill text. 051: when a damage preview is active, render
	# "current → after" so the player reads the predicted outcome of the
	# next click directly. Otherwise fall back to "hp/max_hp".
	var font: Font = ThemeDB.fallback_font
	var text: String
	if _preview_damage > 0:
		text = "%d → %d" % [_actor.hp, max(0, _actor.hp - _preview_damage)]
	else:
		text = "%d/%d" % [_actor.hp, _actor.max_hp]
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos: Vector2 = Vector2(-size.x * 0.5, y_offset - 4.0)
	draw_string_outline(font, text_pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size,
		UiTheme.WORLD_TEXT_OUTLINE_SIZE, UiTheme.WORLD_TEXT_OUTLINE_COLOR)
	draw_string(font, text_pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, UiTheme.TEXT)
