extends Node
## FxDirector — dispatch for Ability presentation channels.
##
## 047-skill-fx-system. Handles four channels stored on Ability resources
## (sound_start / sound_end / collision_effect / animation), driven by
## Skill.cast(... , fx) which awaits this node's coroutines between
## Ability.resolve and Ability.apply_resolved.
##
## Per-cast timeline:
##   t0       — play_cast(caster, ability, mood)
##              ↳ AudioDirector.play_sfx(sound_start, caster_pos)  fire-and-forget
##              ↳ caster.Body shader-flash from cast_flash registry  awaitable
##   tA       — play_collisions(caster, ability, plan, ctx, mood)
##              ↳ shader from per-context registry (swipe/impact_ring/...)  awaitable
##   tA+B     — apply_resolved (effects emit damage_dealt / heal_done here)
##   tA+B     — play_sound_end(primary_pos, ability)               fire-and-forget
##
## All channels are individually null-safe: empty StringName → no-op, no delay.
## A fully-empty ability collapses to synchronous apply (back-compat).
##
## Registry: data/fx/*.json. Each file holds 4 mood variants of one shader's
## context. FxDirector scans the directory at _ready and merges entries into
## a single _fx_registry dict. Naming convention is <context>_<mood>:
##   melee_*   ranged_*   heal_*   buff_*   debuff_*   summon_*   cast_*
## with moods: neutral / tranquility / ascended / burnout (canonical from
## MoodTracker.MOODS_SKILL).
##
## Resolution flow for ability.collision_effect (and analogously animation):
##   1. direct hit on the channel value   → use that entry
##   2. miss → <context>_<skill_mood>     → mood-themed fallback
##   3. miss → <context>_neutral          → context-only fallback
##   4. registry empty / load failed      → legacy single-color flash
##
## Where <context> is derived from the ability's first effect type and target
## range: melee/ranged/heal/buff/debuff/summon. Mood is passed by Skill.cast
## from skill.mood[0] (or "neutral" when empty).
##
## Registry kind dispatch:
##   "cast" — caster.Body via flash.gdshader (flash_amount tween 0→peak→0)
##   "body" — victim[*].Body via context shader (progress tween 0→1, parallel)
##   "hex"  — MeshInstance2D + QuadMesh per create_hex (progress tween 0→1)
##
## Telegraph mode: an AI actor with a non-null cast_intent gets a looping amber
## pulse on its Body. Driven from telegraph_renderer.refresh() via
## sync_telegraph_loops(...). Loop is independent from the one-shot caster
## anim — distinct color (amber vs white) and lower peak intensity.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const FLASH_SHADER: Shader = preload("res://assets/shaders/flash.gdshader")
const FX_REGISTRY_DIR := "res://data/fx"

# Color table — used ONLY for telegraph loop and the legacy fallback when
# the registry failed to load. Per-effect mood-themed colors live in the
# registry now (data/fx/*.json).
const COLOR_CASTER: Color           = Color(1.0, 1.0, 1.0)
const COLOR_TELEGRAPH: Color        = Color(1.0, 0.7, 0.2)
const COLOR_DAMAGE: Color           = Color(1.0, 0.3, 0.3)
const COLOR_HEAL: Color             = Color(0.4, 1.0, 0.4)
const COLOR_STATUS: Color           = Color(1.0, 0.95, 0.3)
const COLOR_MOVE: Color             = Color(0.4, 0.85, 1.0)
const COLOR_CREATE: Color           = Color(0.85, 0.5, 1.0)

const DEFAULT_MOOD: StringName = &"neutral"

# StringName actor_id -> {tween: Tween, body: Sprite2D, prev_material: Material}
var _telegraph_loops: Dictionary = {}

# StringName effect_id -> {shader: Shader, kind: String, duration_ms: int,
#                          uses_direction: bool, uniforms: Dictionary}
# Loaded once at _ready by scanning FX_REGISTRY_DIR. Empty if all loads
# failed — play_collisions / play_cast fall through to legacy code paths.
var _fx_registry: Dictionary = {}


func _ready() -> void:
	_load_fx_registry()
	GameLogger.info("FxDirector", "ready (fx entries: %d)" % _fx_registry.size())


func _load_fx_registry() -> void:
	var dir: DirAccess = DirAccess.open(FX_REGISTRY_DIR)
	if dir == null:
		GameLogger.warn("FxDirector", "registry dir missing: %s — falling back to legacy flash" % FX_REGISTRY_DIR)
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		# Skip directories, dotfiles, non-json files, .import sidecars.
		if not dir.current_is_dir() and fname.ends_with(".json") and not fname.begins_with("."):
			_load_fx_file("%s/%s" % [FX_REGISTRY_DIR, fname])
		fname = dir.get_next()
	dir.list_dir_end()


func _load_fx_file(path: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		GameLogger.warn("FxDirector", "registry open failed: %s" % path)
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		GameLogger.warn("FxDirector", "registry not a dict: %s" % path)
		return
	var loaded: int = 0
	for k in (parsed as Dictionary).keys():
		if String(k).begins_with("_"):
			continue   # _meta — comments / docstring, not entries
		var entry: Variant = (parsed as Dictionary)[k]
		if not (entry is Dictionary):
			continue
		var entry_d: Dictionary = entry
		var shader_path: String = String(entry_d.get("shader", ""))
		if shader_path == "" or not ResourceLoader.exists(shader_path):
			GameLogger.warn("FxDirector", "fx '%s': missing shader %s" % [k, shader_path])
			continue
		var shader: Shader = load(shader_path) as Shader
		if shader == null:
			GameLogger.warn("FxDirector", "fx '%s': failed to load shader" % k)
			continue
		var key: StringName = StringName(k)
		if _fx_registry.has(key):
			GameLogger.warn("FxDirector", "fx '%s': duplicate key (overwriting) — last file wins" % k)
		_fx_registry[key] = {
			"shader": shader,
			"kind": String(entry_d.get("kind", "body")),
			"duration_ms": int(entry_d.get("duration_ms", 200)),
			"uses_direction": bool(entry_d.get("uses_direction", false)),
			"uniforms": entry_d.get("uniforms", {}),
		}
		loaded += 1
	GameLogger.info("FxDirector", "registry loaded %s: %d entries" % [path.get_file(), loaded])


# ── Public coroutines (called from Skill.cast) ───────────────────────────────

## Plays caster animation flash + sound_start. Awaits the flash duration.
## Sound is fire-and-forget. Either channel may be empty (independent no-op).
##
## 047 addendum: animation channel now resolves through the registry. Direct
## hit on `ability.animation` → mood-themed cast_<mood> → cast_neutral →
## legacy white flash. Color comes from entry.uniforms.flash_color.
func play_cast(caster: Actor, ability: Ability, mood: StringName = DEFAULT_MOOD) -> void:
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

	var entry: Dictionary = _resolve_anim_entry(ability, mood)
	if entry.is_empty():
		# Legacy path: pre-registry white flash with default config duration.
		var dur_ms: int = int(GameSpeed.get_value("fx", "cast_animation_ms", 180))
		await _flash_tween(body, COLOR_CASTER, float(dur_ms) / 1000.0)
		return
	# Registry path: same flash.gdshader, color comes from entry uniforms.
	var dur_s: float = float(entry.get("duration_ms", 180)) / 1000.0
	var color: Color = _color_from_entry(entry, "flash_color", COLOR_CASTER)
	await _flash_tween(body, color, dur_s)


## 047 addendum: dispatches to registry-resolved shader (body or hex kind).
## Falls back to legacy single-color flash when registry not loaded.
##
##   caster   — for swipe direction in body kind (uses_direction=true)
##   ability  — channel id source (collision_effect)
##   plan     — Ability.resolve output: uses "victims" (body) and "create_hexes" (hex)
##   ctx      — passes through "grid" for hex-mode local-pos lookup
##   mood     — skill.mood[0] from caller, drives <context>_<mood> auto-pick
func play_collisions(
		caster: Actor, ability: Ability, plan: Dictionary, ctx: Dictionary,
		mood: StringName = DEFAULT_MOOD
	) -> void:
	if ability == null or ability.collision_effect == &"":
		return
	var entry: Dictionary = _resolve_fx_entry(ability, mood)
	if entry.is_empty():
		# Registry not loaded → keep the pre-addendum behavior (legacy flash).
		await _play_legacy_body_fx(plan.get("victims", []), ability)
		return
	var kind: String = entry.get("kind", "body")
	if kind == "hex":
		var grid: Node = ctx.get("grid")
		await _play_hex_fx(plan.get("create_hexes", []), grid, entry)
	else:
		await _play_body_fx(caster, plan.get("victims", []), entry)


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

# ── Collision FX dispatch (047 addendum) ─────────────────────────────────────

## Picks the registry entry for an ability's collision_effect, mood-aware.
## Resolution: direct hit → <context>_<mood> → <context>_neutral → empty
## (caller falls back to legacy flash). Mood is passed in by Skill.cast.
func _resolve_fx_entry(ability: Ability, mood: StringName) -> Dictionary:
	if _fx_registry.is_empty():
		return {}
	# 1. Direct hit on the channel value (e.g. "melee_burnout" set by hand).
	if _fx_registry.has(ability.collision_effect):
		return _fx_registry[ability.collision_effect]
	# 2. <context>_<mood> auto-fallback.
	var ctx: StringName = _ability_context(ability)
	var mood_id: StringName = StringName("%s_%s" % [str(ctx), str(mood)])
	if _fx_registry.has(mood_id):
		return _fx_registry[mood_id]
	# 3. <context>_neutral final fallback (registry partially populated).
	var neutral_id: StringName = StringName("%s_%s" % [str(ctx), str(DEFAULT_MOOD)])
	if _fx_registry.has(neutral_id):
		return _fx_registry[neutral_id]
	return {}


## Picks the registry entry for an ability's animation channel. Same flow
## as _resolve_fx_entry but always over cast_<mood> entries (no per-context
## variants — caster-side flash is purely mood-themed).
func _resolve_anim_entry(ability: Ability, mood: StringName) -> Dictionary:
	if _fx_registry.is_empty():
		return {}
	# 1. Direct hit (e.g. someone wired a custom flash by hand).
	if _fx_registry.has(ability.animation):
		return _fx_registry[ability.animation]
	# 2. cast_<mood>.
	var mood_id: StringName = StringName("cast_%s" % str(mood))
	if _fx_registry.has(mood_id):
		return _fx_registry[mood_id]
	# 3. cast_neutral.
	var neutral_id: StringName = StringName("cast_%s" % str(DEFAULT_MOOD))
	if _fx_registry.has(neutral_id):
		return _fx_registry[neutral_id]
	return {}


## Derives a context tag (melee/ranged/heal/buff/debuff/summon) from an
## ability's effect chain and target shape. Drives the <context>_<mood>
## auto-pick. Priority: Create > Heal > Damage > Status > Move; Damage
## further splits melee (target.range==1) vs ranged (anything else).
##
## Note: Damage > Status because a damage flash is more visceral than a
## status tint on a "deal damage and apply burn" combined ability. Create
## takes top because it needs hex-mode dispatch — wrong fallback would
## render a body flash on a typically-empty victim list for pure summons.
func _ability_context(ability: Ability) -> StringName:
	if ability == null or ability.effects.is_empty():
		return &"ranged"
	for eff in ability.effects:
		if eff is CreateEffect:
			return &"summon"
	for eff in ability.effects:
		if eff is HealEffect:
			return &"heal"
	for eff in ability.effects:
		if eff is DamageEffect:
			return &"melee" if _is_melee_target(ability) else &"ranged"
	for eff in ability.effects:
		if eff is StatusEffect:
			return &"debuff"
	for eff in ability.effects:
		if eff is MoveEffect:
			return &"buff"
	return &"ranged"


func _is_melee_target(ability: Ability) -> bool:
	if ability == null or ability.target == null:
		return false
	# ActorTarget and HexTarget both expose `range`. range==1 = adjacency.
	# range==0 = self only (not melee). range>1 or -1 = ranged.
	if ability.target is ActorTarget:
		return (ability.target as ActorTarget).range == 1
	if ability.target is HexTarget:
		return (ability.target as HexTarget).range == 1
	return false


## Best-effort Color extraction from a registry entry's uniforms dict.
## JSON arrays of length 4 become Color; raw Color values pass through;
## anything else → fallback (so missing uniforms don't crash).
func _color_from_entry(entry: Dictionary, key: String, fallback: Color) -> Color:
	var u: Variant = entry.get("uniforms", {})
	if not (u is Dictionary):
		return fallback
	if not (u as Dictionary).has(key):
		return fallback
	var v: Variant = (u as Dictionary)[key]
	if v is Array and (v as Array).size() == 4:
		var arr: Array = v
		return Color(arr[0], arr[1], arr[2], arr[3])
	if v is Color:
		return v
	return fallback


## body kind: ShaderMaterial on each victim's Body Sprite2D, parallel.
## Awaits a single barrier — all per-victim tweens converge on this duration.
func _play_body_fx(caster: Actor, victims: Array, entry: Dictionary) -> void:
	if victims.is_empty():
		return
	var dur_s: float = float(entry.get("duration_ms", 200)) / 1000.0
	var any_started: bool = false
	for v in victims:
		# 048 follow-up: guard against freed instances. Race exists when an
		# AI turn (or chained ability) kills a victim during the play_cast
		# await window — `v is Actor` on a freed Object throws. Pre-048 was
		# rare in practice; corpse spawn paths make it hit-able. Use
		# is_instance_valid to peek without dereferencing.
		if not is_instance_valid(v):
			continue
		if not (v is Actor):
			continue
		var actor: Actor = v
		if not actor.is_alive():
			continue
		var body: Sprite2D = actor.get_node_or_null("Body") as Sprite2D
		if body == null:
			continue
		_spawn_body_progress_tween(caster, actor, body, entry, dur_s)
		any_started = true
	if not any_started:
		return
	await get_tree().create_timer(dur_s).timeout


func _spawn_body_progress_tween(
		caster: Actor, victim: Actor, body: Sprite2D,
		entry: Dictionary, dur_s: float
	) -> void:
	var prev_material: Material = body.material
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = entry.get("shader") as Shader
	_apply_uniforms(mat, entry.get("uniforms", {}))
	# Direction uniform set per-victim from caster→victim vector. Without
	# uses_direction, swipe-style shaders just default to angle=0 (horizontal).
	if bool(entry.get("uses_direction", false)) and caster != null:
		var dx: float = victim.global_position.x - caster.global_position.x
		var dy: float = victim.global_position.y - caster.global_position.y
		mat.set_shader_parameter("angle", atan2(dy, dx))
	mat.set_shader_parameter("progress", 0.0)
	body.material = mat
	var tw: Tween = create_tween()
	tw.tween_property(mat, "shader_parameter/progress", 1.0, dur_s)
	tw.tween_callback(func() -> void:
		if is_instance_valid(body):
			body.material = prev_material
	)


## hex kind: spawn a MeshInstance2D + QuadMesh at each create_hex world pos,
## tween its progress 0→1, free on completion. The hex_pulse shader paints
## directly without sampling TEXTURE so the mesh needs no texture binding.
func _play_hex_fx(create_hexes: Array, grid: Node, entry: Dictionary) -> void:
	if create_hexes.is_empty() or grid == null:
		return
	var tile_layer: TileMapLayer = grid.get("tile_map_layer") as TileMapLayer
	if tile_layer == null:
		GameLogger.warn("FxDirector", "hex fx: grid.tile_map_layer null")
		return
	var dur_s: float = float(entry.get("duration_ms", 600)) / 1000.0
	var size_px: float = float(GameSpeed.get_value("fx", "hex_effect_size_px", 72))
	var any_started: bool = false
	for hex_v in create_hexes:
		if not (hex_v is Vector2i):
			continue
		var hex_coord: Vector2i = hex_v
		var local_pos: Vector2 = tile_layer.map_to_local(hex_coord)
		_spawn_hex_progress_node(grid, local_pos, entry, dur_s, size_px)
		any_started = true
	if not any_started:
		return
	await get_tree().create_timer(dur_s).timeout


func _spawn_hex_progress_node(
		parent: Node, local_pos: Vector2, entry: Dictionary,
		dur_s: float, size_px: float
	) -> void:
	var mi: MeshInstance2D = MeshInstance2D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size_px, size_px)
	mi.mesh = quad
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = entry.get("shader") as Shader
	_apply_uniforms(mat, entry.get("uniforms", {}))
	mat.set_shader_parameter("progress", 0.0)
	mi.material = mat
	mi.position = local_pos
	# Above tilemap (z=0) and telegraph_hex (z=3), below actors (typically
	# higher). Just enough to read on top of overlays without occluding play.
	mi.z_index = 4
	parent.add_child(mi)
	var tw: Tween = create_tween()
	tw.tween_property(mat, "shader_parameter/progress", 1.0, dur_s)
	tw.tween_callback(func() -> void:
		if is_instance_valid(mi):
			mi.queue_free()
	)


## Set shader uniforms from a JSON-shaped Dictionary. Arrays-of-floats become
## the matching Color/Vector3/Vector2 type so shaders' source_color and vec
## uniforms get the right Variant kind.
func _apply_uniforms(mat: ShaderMaterial, uniforms: Variant) -> void:
	if not (uniforms is Dictionary):
		return
	for k in (uniforms as Dictionary).keys():
		var v: Variant = (uniforms as Dictionary)[k]
		if v is Array:
			var arr: Array = v
			match arr.size():
				4: mat.set_shader_parameter(k, Color(arr[0], arr[1], arr[2], arr[3]))
				3: mat.set_shader_parameter(k, Vector3(arr[0], arr[1], arr[2]))
				2: mat.set_shader_parameter(k, Vector2(arr[0], arr[1]))
				_: mat.set_shader_parameter(k, v)
		else:
			mat.set_shader_parameter(k, v)


## Legacy single-color flash — fallback path used only when the registry
## failed to load (no JSON at FX_REGISTRY_PATH or parse error). Preserves
## pre-addendum behavior so a missing data file degrades to "everything
## still flashes, just generic" instead of silent no-fx.
func _play_legacy_body_fx(victims: Array, ability: Ability) -> void:
	if victims.is_empty():
		return
	var dur_ms: int = int(GameSpeed.get_value("fx", "collision_effect_ms", 140))
	var dur_s: float = float(dur_ms) / 1000.0
	var color: Color = _victim_flash_color(ability)
	var any_started: bool = false
	for v in victims:
		# 048 follow-up: same race as _play_body_fx — guard freed instances.
		if not is_instance_valid(v):
			continue
		if not (v is Actor):
			continue
		var actor: Actor = v
		if not actor.is_alive():
			continue
		var body: Sprite2D = actor.get_node_or_null("Body") as Sprite2D
		if body == null:
			continue
		_flash_tween_no_wait(body, color, dur_s)
		any_started = true
	if not any_started:
		return
	await get_tree().create_timer(dur_s).timeout


# ── Telegraph + caster-anim internals ────────────────────────────────────────

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
