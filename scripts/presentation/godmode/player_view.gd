extends Actor
## PlayerView — Player presentation. Tiny subclass of Actor that auto-fits
## the Body Sprite2D to tile width on _ready. Mirror of EnemyView's pattern,
## but for the static player.tscn (where texture is baked into the scene
## rather than loaded from JSON at runtime).
##
## All Player-specific defaults (max_hp, team, speed, status_immunities) live
## in player.tscn @export overrides as before — this script only adds the
## sprite-fit hook on top of Actor._ready.
##
## Spec 050.

const SpriteFit = preload("res://scripts/infrastructure/sprite_fit.gd")


func _ready() -> void:
	var body := get_node_or_null("Body") as Sprite2D
	if body != null:
		SpriteFit.fit_to_tile_width(body)
	super._ready()
