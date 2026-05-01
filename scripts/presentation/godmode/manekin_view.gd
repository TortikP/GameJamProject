extends Actor
## Manekin — passive HP bag + simple melee. AI lives in GodmodeController.
##
## Visual is a child Sprite2D (red husk) attached in the scene file.
## On death, controller listens to `died` signal and removes from grid + scene.

## Skill ID this manekin uses on attack (set in scene). Empty = no attack.
@export var attack_skill_id: StringName = &""

## Coord this manekin will attack on its next turn, if any.
## (-1, -1) = no pending attack. Set by AI at end of turn, consumed at start.
var attack_intent_coord: Vector2i = Vector2i(-1, -1)

## Coord this manekin will MOVE to next turn (one step). (-1, -1) = stay put.
## Resolved before attack on the AI's turn — meaning the attack is from
## the move_intent position, not the current position.
var move_intent_coord: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	team = &"enemy"
	if max_hp <= 0:
		max_hp = 20
	super._ready()
	# Declare ability IDs so ActorInspector / MoveRangeOverlay can display range.
	if attack_skill_id != &"":
		var sk: Skill = SkillDatabase.get_skill(attack_skill_id)
		if sk != null:
			set_abilities(sk.get_ability_ids())
