extends Node
## FxDirector — dispatch for Ability presentation channels.
##
## 047-skill-fx-system. Handles four channels stored on Ability resources
## (sound_start / sound_end / collision_effect / animation), driven by
## Skill.cast(... , fx) which awaits this node's coroutines between
## Ability.resolve and Ability.apply_resolved.
##
## Per-cast timeline:
##   t0       — play_cast(caster, ability)
##              ↳ AudioDirector.play_sfx(sound_start, caster_pos)  fire-and-forget
##              ↳ caster.Body shader-flash (white)                 awaitable
##   tA       — play_collisions(victims, ability)
##              ↳ each victim.Body shader-flash in parallel        awaitable
##   tA+B     — apply_resolved (effects emit damage_dealt / heal_done here)
##   tA+B     — play_sound_end(primary_pos, ability)               fire-and-forget
##
## All channels are individually null-safe: empty StringName → no-op, no delay.
## A fully-empty ability collapses to synchronous apply (back-compat).
##
## Telegraph mode: an AI actor with a non-null cast_intent gets a looping amber
## pulse on its Body. Driven from telegraph_renderer.refresh() via
## sync_telegraph_loops(...). Loop is independent from the one-shot caster
## anim — distinct color (amber vs white) and lower peak intensity.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const FLASH_SHADER: Shader = preload("res://assets/shaders/flash.gdshader")

# Color table — see specs/047-skill-fx-system/plan.md §"Color table".
const COLOR_CASTER: Color           = Color(1.0, 1.0, 1.0)
const COLOR_TELEGRAPH: Color        = Color(1.0, 0.7, 0.2)
const COLOR_DAMAGE: Color           = Color(1.0, 0.3, 0.3)
const COLOR_HEAL: Color             = Color(0.4, 1.0, 0.4)
const COLOR_STATUS: Color           = Color(1.0, 0.95, 0.3)
const COLOR_MOVE: Color             = Color(0.4, 0.85, 1.0)
const COLOR_CREATE: Color           = Color(0.85, 0.5, 1.0)

# StringName actor_id -> {tween: Tween, body: Sprite2D, prev_material: Material}
var _telegraph_loops: Dictionary = {}


func _ready() -> void:
	GameLogger.info("FxDirector", "ready")


# ── Public coroutines (called from Skill.cast) ───────────────────────────────

## Plays caster animation flash + sound_start. Awaits the flash duration.
## Sound is fire-and-forget. Either channel may be empty (independent no-op).
func play_cast(caster: Actor, ability: Ability) -> void:
	if caster == null or ability == null:
		return
	# Defensively stop any telegraph loop on this actor — the cast itself
	# supersedes the "I'm preparing this" hint.
	stop_telegraph_loop(caster.actor_id)

	# Sound first — starts in parallel with the flash (or alone if no anim).
	if ability.sound_start != &"":
		AudioDirector.play_sfx(ability.sound_start, caster.global_position)

	if ability.animation == &"":
		return  # nothing to await
	var body: Sprite2D = caster.get_node_or_null("Body") as Sprite2D
	if body == null:
		return
	var dur_ms: int = int(GameSpeed.get_value("fx", "cast_animation_ms", 180))
	var dur_s: float = float(dur_ms) / 1000.0
	await _flash_tween(body, COLOR_CASTER, dur_s)


## Plays collision flashes on all victims in parallel. Awaits the duration
## once — all flashes run independently and finish around the same moment.
func play_collisions(victims: Array, ability: Ability) -> void:
	if ability == null:
		return
	if ability.collision_effect == &"":
		return
	if victims.is_empty():
		return
	var dur_ms: int = int(GameSpeed.get_value("fx", "collision_effect_ms", 140))
	var dur_s: float = float(dur_ms) / 1000.0
	var color: Color = _victim_flash_color(ability)
	var any_started: bool = false
	for v in victims:
		if not (v is Actor):
			continue
		var actor: Actor = v
		if not actor.is_alive():
			# Dead victim shouldn't visually flash — apply_resolved already
			# guards via requires_alive_target on relevant effects.
			continue
		var body: Sprite2D = actor.get_node_or_null("Body") as Sprite2D
		if body == null:
			continue
		_flash_tween_no_wait(body, color, dur_s)
		any_started = true
	if not any_started:
		return
	# Single barrier wait — parallel flashes converge on this duration.
	await get_tree().create_timer(dur_s).timeout


## Fire-and-forget end-of-cast SFX cue at primary impact position.
func play_sound_end(world_pos: Vector2, ability: Ability) -> void:
	if ability == null or ability.sound_end == &"":
		return
	AudioDirector.play_sfx(ability.sound_end, world_pos)


# ── Telegraph loop sync (called from telegraph_renderer.refresh) ─────────────

## Diff-based sync: starts loops on actors with cast_intent that don't have
## one running, stops loops on actors that no longer should pulse (intent
## cleared / actor died / actor not in `live_intent_actors`).
func sync_telegraph_loops(live_intent_actors: Array) -> void:
	# Set of actor_ids that SHOULD have a loop right now. Defensive null-checks
	# because callers can pass mixed lists.
	var should_loop: Dictionary = {}
	for a in live_intent_actors:
		if not (a is Actor):
			continue
		var actor: Actor = a
		if not actor.is_alive():
			continue
		var intent_v: Variant = actor.cast_intent
		if intent_v == null:
			continue
		var ci: CastIntent = intent_v as CastIntent
		if ci == null or not ci.is_valid():
			continue
		var skill: Skill = SkillDatabase.get_skill(ci.skill_id)
		if skill == null or skill.abilities.is_empty():
			continue
		var first_ab: Ability = skill.abilities[0]
		if first_ab == null or first_ab.animation == &"":
			continue
		should_loop[actor.actor_id] = actor

	# Start newly-needed loops.
	for aid in should_loop.keys():
		if not _telegraph_loops.has(aid):
			_start_telegraph_loop(should_loop[aid] as Actor)

	# Stop loops that should no longer run. Snapshot keys before mutation.
	for aid in _telegraph_loops.keys().duplicate():
		if not should_loop.has(aid):
			stop_telegraph_loop(aid)


## Public — used by play_cast to defensively kill a stale loop. Safe no-op
## if no loop is running for this actor.
func stop_telegraph_loop(actor_id: StringName) -> void:
	if not _telegraph_loops.has(actor_id):
		return
	var entry: Dictionary = _telegraph_loops[actor_id]
	var tw: Variant = entry.get("tween")
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()
	var body: Variant = entry.get("body")
	if body is Sprite2D and is_instance_valid(body):
		(body as Sprite2D).material = entry.get("prev_material")
	_telegraph_loops.erase(actor_id)


# ── Internals ────────────────────────────────────────────────────────────────

func _start_telegraph_loop(actor: Actor) -> void:
	if actor == null:
		return
	var body: Sprite2D = actor.get_node_or_null("Body") as Sprite2D
	if body == null:
		return
	var period_ms: int = int(GameSpeed.get_value("fx", "telegraph_pulse_period_ms", 1000))
	var intensity: float = float(GameSpeed.get_value("fx", "telegraph_pulse_intensity", 0.4))
	var period_s: float = float(period_ms) / 1000.0
	var prev_material: Material = body.material
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	mat.set_shader_parameter("flash_color", COLOR_TELEGRAPH)
	mat.set_shader_parameter("flash_amount", 0.0)
	body.material = mat
	# Looped tween pulses 0 → intensity → 0 over the configured period.
	var tw: Tween = create_tween().set_loops()
	tw.tween_property(mat, "shader_parameter/flash_amount", intensity, period_s * 0.5)
	tw.tween_property(mat, "shader_parameter/flash_amount", 0.0, period_s * 0.5)
	_telegraph_loops[actor.actor_id] = {
		"tween": tw,
		"body": body,
		"prev_material": prev_material,
	}


## Coroutine — applies one-shot shader-flash and awaits its tween. Restores
## the body's previous material on finish (or on early invalidation).
func _flash_tween(body: Sprite2D, color: Color, dur_s: float) -> void:
	if body == null or dur_s <= 0.0:
		return
	var prev_material: Material = body.material
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	var peak: float = float(GameSpeed.get_value("fx", "flash_color_intensity", 0.85))
	mat.set_shader_parameter("flash_color", color)
	mat.set_shader_parameter("flash_amount", 0.0)
	body.material = mat
	# 30/70 split — quick rise, longer decay reads as "impact + afterglow".
	var tw: Tween = create_tween()
	tw.tween_property(mat, "shader_parameter/flash_amount", peak, dur_s * 0.3)
	tw.tween_property(mat, "shader_parameter/flash_amount", 0.0, dur_s * 0.7)
	await tw.finished
	if is_instance_valid(body):
		body.material = prev_material


## Fire-and-forget variant for parallel collision flashes. Same restoration
## logic via tween_callback so material is cleared even though we don't await.
func _flash_tween_no_wait(body: Sprite2D, color: Color, dur_s: float) -> void:
	if body == null or dur_s <= 0.0:
		return
	var prev_material: Material = body.material
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	var peak: float = float(GameSpeed.get_value("fx", "flash_color_intensity", 0.85))
	mat.set_shader_parameter("flash_color", color)
	mat.set_shader_parameter("flash_amount", 0.0)
	body.material = mat
	var tw: Tween = create_tween()
	tw.tween_property(mat, "shader_parameter/flash_amount", peak, dur_s * 0.3)
	tw.tween_property(mat, "shader_parameter/flash_amount", 0.0, dur_s * 0.7)
	tw.tween_callback(func() -> void:
		if is_instance_valid(body):
			body.material = prev_material
	)


## Picks victim flash color based on the first effect type. Multi-effect
## abilities (e.g. damage+status) pick the dominant signal — damage > heal >
## status > move > create — matching the order users care about visually.
func _victim_flash_color(ability: Ability) -> Color:
	if ability == null or ability.effects.is_empty():
		return COLOR_DAMAGE  # safest fallback
	for eff in ability.effects:
		if eff is DamageEffect:
			return COLOR_DAMAGE
	for eff in ability.effects:
		if eff is HealEffect:
			return COLOR_HEAL
	for eff in ability.effects:
		if eff is StatusEffect:
			return COLOR_STATUS
	for eff in ability.effects:
		if eff is MoveEffect:
			return COLOR_MOVE
	for eff in ability.effects:
		if eff is CreateEffect:
			return COLOR_CREATE
	return COLOR_DAMAGE
