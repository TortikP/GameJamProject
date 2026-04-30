extends Actor
## Manekin — passive HP bag for godmode testing. No AI.
##
## Visual is a child Polygon2D (red hex r=16) attached in the scene file.
## On death, controller listens to `died` signal and removes from grid + scene.

func _ready() -> void:
	team = &"enemy"
	if max_hp <= 0:
		max_hp = 20
	super._ready()
