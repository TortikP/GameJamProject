extends Actor
## Manekin — passive HP bag + simple AI now driven by behavior_id.
##
## Visual is a child Sprite2D (red husk) attached in the scene file.
## On death, controller listens to `died` signal and removes from grid + scene.
##
## After 008: skill list, behavior_id, max_hp, team, speed are loaded from
## data/enemies/<enemy_data_id>.json. The scene only carries enemy_data_id
## so any new "manekin variant" is just another JSON file, no scene work.

const _EnemyDataLoader := preload("res://scripts/core/actors/enemy_data_loader.gd")

@export var enemy_data_id: StringName = &"manekin"


func _ready() -> void:
	team = &"enemy"
	_EnemyDataLoader.apply_to_actor(self, enemy_data_id)
	# Defaults if data missing: keep manekin alive with 20 HP so a misconfigured
	# scene doesn't silently spawn dead.
	if max_hp <= 0:
		max_hp = 20
	super._ready()
	# Declare ability IDs from loaded skills so ActorInspector / MoveRangeOverlay
	# can paint range overlays.
	var ability_ids: Array[StringName] = []
	for s in get_skills():
		if s == null:
			continue
		ability_ids.append_array((s as Skill).get_ability_ids())
	set_abilities(ability_ids)
