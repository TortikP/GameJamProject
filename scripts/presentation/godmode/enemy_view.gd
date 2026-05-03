extends Actor
## EnemyView — generic enemy presentation. Body sprite, HP bar, status strip.
##
## Driven entirely by enemy_data_id → data/enemies/<id>.json. Sets max_hp,
## team, speed, behavior_id, skills, AND body texture from the JSON. The scene
## itself (enemy.tscn) carries no per-enemy specifics — just the structural
## node tree. To add a new enemy: drop JSON + sprite, no scene work.
##
## On death, controller listens to `died` signal and removes from grid + scene.

const _EnemyDataLoader := preload("res://scripts/core/actors/enemy_data_loader.gd")
const SpriteFit := preload("res://scripts/infrastructure/sprite_fit.gd")

## Set by spawner BEFORE add_child so _ready picks up the right JSON.
## Default is &"" — a scene with no id will fall back to manekin defaults
## below (kept for safety; in practice spawner always sets this).
@export var enemy_data_id: StringName = &""


func _ready() -> void:
	team = &"enemy"
	var hints: Dictionary = _EnemyDataLoader.apply_to_actor(self, enemy_data_id)
	# Defaults if data missing: keep enemy alive with 20 HP so a misconfigured
	# spawner doesn't silently spawn dead.
	if max_hp <= 0:
		max_hp = 20
	# Apply view hints — currently just the body sprite. View resolves Sprite2D
	# child by convention name "Body" (matches every enemy.tscn node tree).
	if hints.has("sprite"):
		var body := get_node_or_null("Body") as Sprite2D
		if body == null:
			GameLogger.warn("EnemyView", "%s: Body Sprite2D not found, sprite hint ignored" % enemy_data_id)
		else:
			var tex := load(hints["sprite"]) as Texture2D
			if tex == null:
				GameLogger.warn("EnemyView", "%s: failed to load sprite '%s'" % [enemy_data_id, hints["sprite"]])
			else:
				body.texture = tex
				# Spec 050: scale Body so displayed width == tile width (128),
				# preserving aspect. Replaces per-enemy hardcoded scale tweaks.
				SpriteFit.fit_to_tile_width(body)
	super._ready()
	# Declare ability IDs from loaded skills so ActorInspector / MoveRangeOverlay
	# can paint range overlays.
	var ability_ids: Array[StringName] = []
	for s in get_skills():
		if s == null:
			continue
		ability_ids.append_array((s as Skill).get_ability_ids())
	set_abilities(ability_ids)
