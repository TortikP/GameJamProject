extends Node2D
## HealthBar — small bar drawn above the parent Actor.
##
## Listens to the parent Actor's `damaged` signal and redraws on change.
## Hidden when at full HP to reduce visual noise. Drawn via _draw() — no
## child nodes required.

const WIDTH: float = 30.0
const HEIGHT: float = 4.0
const Y_OFFSET: float = -24.0
const COLOR_BG: Color = Color(0.10, 0.10, 0.10, 0.85)
const COLOR_HP: Color = Color(0.30, 0.85, 0.30, 1.0)
const COLOR_FRAME: Color = Color(0, 0, 0, 0.6)

var _actor: Actor


func _ready() -> void:
	_actor = get_parent() as Actor
	if _actor == null:
		push_warning("HealthBar: parent is not Actor")
		return
	_actor.damaged.connect(_on_damaged)


func _on_damaged(_id: StringName, _amount: int, _hp_left: int) -> void:
	queue_redraw()


func _draw() -> void:
	if _actor == null or _actor.max_hp <= 0:
		return
	if _actor.hp >= _actor.max_hp:
		return  # hide at full HP
	var ratio: float = float(_actor.hp) / float(_actor.max_hp)
	var x: float = -WIDTH * 0.5
	draw_rect(Rect2(x, Y_OFFSET, WIDTH, HEIGHT), COLOR_BG, true)
	draw_rect(Rect2(x, Y_OFFSET, WIDTH * ratio, HEIGHT), COLOR_HP, true)
	draw_rect(Rect2(x, Y_OFFSET, WIDTH, HEIGHT), COLOR_FRAME, false, 1.0)
