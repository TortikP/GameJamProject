extends Node
## TelegraphRenderer — builds and tears down per-enemy cast telegraph hexes
## (primary damage tile + secondary AoE shape outlines) and movement intent
## arrows. Aggregates by coord across all live enemies' intents.

const TELEGRAPH_HEX_SCRIPT := preload("res://scripts/presentation/telegraph_hex.gd")
const INTENT_ARROW_SCRIPT := preload("res://scripts/presentation/intent_arrow.gd")

var _ctrl: Node = null

var _telegraph_hexes: Dictionary = {}  # Vector2i coord -> TelegraphHex node
var _intent_arrows: Dictionary = {}    # StringName actor_id -> IntentArrow node


func _ready() -> void:
	_ctrl = get_parent()


# ── Telegraph tag mapping (AC-I4) ────────────────────────────────────────────

## Maps a Skill's primary tag to TelegraphHex.semantic_tag (which UiTheme then
## resolves via semantic_color). Aggregation in refresh() already handles
## per-coord summing — this is one-shot per cast.
func tag_for_skill(skill: Skill) -> StringName:
	if skill == null or skill.behaviour_tags.is_empty():
		return &""  # → SEM_DAMAGE default (legacy / unknown)
	match skill.behaviour_tags[0]:
		&"damage", &"damage_aoe", &"knockback":
			return &"damage"
		&"heal":
			return &"heal"
		&"control":
			return &"control"
		&"debuff":
			return &"debuff"
		&"buff":
			return &"buff"
		&"summon":
			return &"create"
		&"mobility":
			return &"move"
	return &""


# ── Telegraph visuals ────────────────────────────────────────────────────────

func refresh() -> void:
	var grid: HexGrid = _ctrl.grid
	var registry: ActorRegistry = _ctrl.registry
	# Clear all current visuals.
	for poly in _telegraph_hexes.values():
		if is_instance_valid(poly):
			poly.queue_free()
	_telegraph_hexes.clear()
	for arr in _intent_arrows.values():
		if is_instance_valid(arr):
			arr.queue_free()
	_intent_arrows.clear()

	# Aggregate per-coord telegraph state across all enemies' intents.
	# Each hex tracks (tag, damage). Damage only sums when both intents are damage-class.
	# 029 / req-6: also collect per-intent area-shape hexes so we can paint
	# secondary outlines for AoE skills (the affected tiles around the
	# primary target). entry: {tag, area_hexes: Array[Vector2i]} per coord.
	var by_coord: Dictionary = {}   # Vector2i -> {tag: StringName, damage: int}
	# Per-intent area-shape collection. Built separately because area can extend
	# beyond the primary target_coord and we want to draw secondary outlines on
	# coords NOT already in by_coord (= primary takes priority over secondary).
	var area_coords: Dictionary = {}   # Vector2i -> StringName tag (first one wins)
	for actor in registry.all():
		if not (actor is Actor):
			continue
		var enemy: Actor = actor
		# 044: render telegraphs for any AI-controlled actor, not only enemies —
		# player-side summoned creatures (spec 041 + 044) need their cast/move
		# intents visible to the player too. Pillar 1 / full information.
		# Variable name `enemy` retained for diff minimisation; semantically
		# now means "AI-controlled world actor".
		if enemy == _ctrl.player or not enemy.is_alive():
			continue

		# Cast telegraph: hex + color from primary tag, damage number for damage-class only.
		var intent: Variant = enemy.cast_intent
		if intent == null:
			pass
		else:
			var ci: CastIntent = intent as CastIntent
			if ci != null and ci.is_valid():
				var coord: Vector2i = ci.target_coord
				if ci.target_id != &"":
					var live: Vector2i = grid.get_coord(ci.target_id)
					if live != Vector2i(-1, -1):
						coord = live
				if coord != Vector2i(-1, -1):
					var skill: Skill = SkillDatabase.get_skill(ci.skill_id)
					var tag: StringName = tag_for_skill(skill)
					var dmg: int = 0
					if tag == &"damage" or tag == &"":
						# Predict only for damage-class. tag=="" → legacy fallback (treat as damage).
						var target_actor: Actor = null
						if ci.target_id != &"":
							target_actor = registry.get_actor(ci.target_id)
						if target_actor != null and skill != null:
							dmg = skill.predicted_damage_to(enemy, target_actor, {})
					if by_coord.has(coord):
						var prev: Dictionary = by_coord[coord]
						# Sum damage only when both are damage-class with same tag; else keep first.
						if prev.tag == tag and (tag == &"damage" or tag == &""):
							prev.damage += dmg
						# 049 / AC-5: keep the first attacker's skill ref for the
						# icon. Aggregating multiple skills into one hex is rare
						# and the visual answer of "show the dominant icon" is
						# fine — first-write-wins matches existing tag aggregation.
					else:
						by_coord[coord] = {"tag": tag, "damage": dmg, "skill": skill}
					# 029 / req-6: collect AoE-affected hexes for this intent.
					# Skill.area lives on each Ability; iterate them and ask for
					# the affected tiles given caster + target. Area can be null
					# (single-target spells); skip those — primary hex above is
					# already enough.
					if skill != null:
						var caster_coord: Vector2i = grid.get_coord(enemy.actor_id)
						for ab in skill.abilities:
							var ability := ab as Ability
							if ability == null or ability.area == null:
								continue
							var anchor: Vector2i = coord
							if ability.target != null:
								anchor = ability.target.preview_anchor_coord(caster_coord, coord)
							var affected: Array[Vector2i] = ability.area.get_affected_hexes(
									caster_coord, anchor, grid)
							for ac in affected:
								if not area_coords.has(ac):
									area_coords[ac] = tag

		# Movement arrow — one per enemy with a planned move.
		var mv: Vector2i = enemy.move_intent_coord
		if mv != Vector2i(-1, -1):
			var enemy_coord: Vector2i = grid.get_coord(enemy.actor_id)
			if enemy_coord != Vector2i(-1, -1):
				var arrow: Node2D = INTENT_ARROW_SCRIPT.new()
				arrow.position = Vector2.ZERO
				arrow.z_index = 4  # above telegraph hex, below actors
				grid.add_child(arrow)
				arrow.set("origin", grid.tile_map_layer.map_to_local(enemy_coord))
				arrow.set("target", grid.tile_map_layer.map_to_local(mv))
				_intent_arrows[enemy.actor_id] = arrow

	# Render one telegraph hex per threatened coord.
	for coord in by_coord.keys():
		var hex: Node2D = TELEGRAPH_HEX_SCRIPT.new()
		hex.position = grid.tile_map_layer.map_to_local(coord)
		hex.z_index = 3
		var entry: Dictionary = by_coord[coord]
		hex.set("semantic_tag", entry.tag)
		hex.set("damage", entry.damage)   # 0 = no number drawn (heal/buff/etc.)
		# 049 / AC-5: skill ref drives icon (texture or letter fallback) at hex
		# center. Null skill (legacy / non-skill telegraph) → TelegraphHex skips
		# icon draw cleanly.
		hex.set("icon_skill", entry.get("skill", null))
		grid.add_child(hex)
		_telegraph_hexes[coord] = hex

	# 029 / req-6: secondary AoE-shape hexes — outline-only so they read as
	# "the spell will sweep through here" without competing with the primary
	# damage-bearing hex. Skip coords already painted as primary.
	for area_coord in area_coords.keys():
		if _telegraph_hexes.has(area_coord):
			continue
		var sec: Node2D = TELEGRAPH_HEX_SCRIPT.new()
		sec.position = grid.tile_map_layer.map_to_local(area_coord)
		sec.z_index = 3
		sec.set("semantic_tag", area_coords[area_coord])
		sec.set("outline_only", true)
		grid.add_child(sec)
		_telegraph_hexes[area_coord] = sec

	# 047-skill-fx-system: cyclic shader-flash on AI casters that have a
	# planned cast_intent. FxDirector keeps its own per-actor loop state and
	# diffs against the array we pass — we just send the live AI-controlled
	# set. Loops self-stop when the actor disappears from the array (intent
	# cleared after resolve, actor died, animation field empty for the skill).
	var intent_actors: Array = []
	for actor in registry.all():
		if not (actor is Actor):
			continue
		var ai_actor: Actor = actor
		if ai_actor == _ctrl.player or not ai_actor.is_alive():
			continue
		if ai_actor.cast_intent == null:
			continue
		intent_actors.append(ai_actor)
	FxDirector.sync_telegraph_loops(intent_actors)


func clear() -> void:
	for poly in _telegraph_hexes.values():
		if is_instance_valid(poly):
			poly.queue_free()
	_telegraph_hexes.clear()
	for arr in _intent_arrows.values():
		if is_instance_valid(arr):
			arr.queue_free()
	_intent_arrows.clear()


## Best-effort damage forecast for an enemy's pending cast against the player.
## Kept as a thin shim for any external caller (ActorInspector, etc.) that wants
## a quick "what will hit me next turn" number — telegraph rendering itself
## inlines the same lookup in refresh().
func enemy_attack_damage(enemy: Actor) -> int:
	var intent_v: Variant = enemy.cast_intent
	if intent_v == null:
		return 0
	var ci: CastIntent = intent_v as CastIntent
	if ci == null or not ci.is_valid():
		return 0
	var skill: Skill = SkillDatabase.get_skill(ci.skill_id)
	if skill == null:
		return 0
	var tag: StringName = tag_for_skill(skill)
	if tag != &"damage" and tag != &"":
		return 0
	return skill.predicted_damage_to(enemy, _ctrl.player, {})
