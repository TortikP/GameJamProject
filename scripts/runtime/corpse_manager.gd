extends Node
## CorpseManager — global corpse lifecycle for 048-corpse-absorption.
##
## Autoload (registered in project.godot AFTER EventBus). Listens to
## EventBus.actor_died, snapshots the dying actor's body before godmode_setup's
## cleanup queue_free's it, spawns a Corpse node under <HexGrid>/Corpses
## (sibling of <HexGrid>/Actors), runs the death animation, then the corpse
## just lies there until the post-final-wave absorption ritual is invoked by
## WaveController._check_auto_clear.
##
## Inertia (D-5 / AC-15): corpses are NOT registered in ActorRegistry and are
## NOT placed in HexGrid actor map. Spells, AOEs, tile_effects, pathfinder,
## wave_snapshot transitions all bypass them. Only ways out: absorption +
## clear_all().
##
## Empty-arena ritual (D-4): play_absorption_ritual still plays heroine-side
## FX for the full absorption_total_sec when the corpse list is empty —
## audio cue length stays the same.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const FLASH_SHADER: Shader = preload("res://assets/shaders/flash.gdshader")
const _CORPSE_SCENE: PackedScene = preload("res://scenes/runtime/corpse.tscn")

# Per-scene set of alive corpses. Cleared on run_started / scene_ready.
var _alive: Array = []

# Cached lookups; invalidated on clear_all.
var _registry: Node = null
var _corpse_root: Node = null

# Once we've warned about a missing-texture or missing-registry, don't spam.
var _warned_no_texture: bool = false
var _warned_no_registry: bool = false


func _ready() -> void:
	EventBus.actor_died.connect(_on_actor_died)
	EventBus.run_started.connect(_on_reset)
	EventBus.battle_started.connect(_on_reset)
	EventBus.scene_ready.connect(_on_scene_ready)


# ── Public ──────────────────────────────────────────────────────────────────

func has_corpses() -> bool:
	_compact()
	return not _alive.is_empty()


func corpse_count() -> int:
	_compact()
	return _alive.size()


## Plays the post-final-wave absorption ritual. Awaitable — coroutine returns
## after exactly `absorption_total_sec` regardless of corpse count (including
## zero — see D-4). target_provider is a Callable returning the heroine's
## current global_position. grid is optional and is used only for biome-tint
## resolution; null → neutral white tint.
func play_absorption_ritual(target_provider: Callable, grid = null) -> void:
	_compact()
	var corpses: Array = _alive.duplicate()
	var total_sec: float = float(GameSpeed.get_value("fx", "absorption_total_sec", 2.5))
	var biome_tint: Color = _resolve_biome_tint(grid)

	EventBus.corpses_absorbing_started.emit(corpses.size(), total_sec)

	# Heroine-side FX always run (D-4: empty list still plays full ritual).
	_start_camera_shake(total_sec)
	_spawn_heroine_particles(target_provider, biome_tint, total_sec)
	_start_heroine_pulse(target_provider, biome_tint, total_sec)

	# Per-corpse motion. All finish within total_sec by construction (see
	# spec §"Fixed-duration guarantee"): with effective = (total - max_jitter)
	# * min_sf, last corpse finish_t = max_jitter + effective/min_sf = total.
	if not corpses.is_empty():
		var max_jitter: float = float(GameSpeed.get_value("fx", "absorption_per_corpse_jitter_sec", 0.35))
		var speed_jitter: float = float(GameSpeed.get_value("fx", "absorption_speed_jitter", 0.15))
		var min_sf: float = max(0.01, 1.0 - speed_jitter)
		var max_sf: float = 1.0 + speed_jitter
		var effective: float = max(0.05, (total_sec - max_jitter) * min_sf)

		for c in corpses:
			if not is_instance_valid(c):
				continue
			var delay: float = randf() * max_jitter
			var sf: float = randf_range(min_sf, max_sf)
			var motion_sec: float = effective / sf
			# Per-arrival mini-burst shake + heroine scale-punch handled here.
			c.absorbed_arrived.connect(_on_corpse_arrived.bind(target_provider), CONNECT_ONE_SHOT)
			c.play_absorption(target_provider, motion_sec, delay)

	# Hold the full ritual duration for audio sync.
	await get_tree().create_timer(total_sec).timeout

	# Sweep any stragglers (defensive — math says they're all done).
	for c in corpses:
		if is_instance_valid(c):
			c.dispose()
	_alive.clear()
	EventBus.corpses_absorbed.emit()


## Immediate dispose of all corpses. No animation. Safe to call from anywhere.
func clear_all() -> void:
	for c in _alive:
		if is_instance_valid(c):
			c.dispose()
	_alive.clear()
	_registry = null
	_corpse_root = null


# ── EventBus handlers ───────────────────────────────────────────────────────

func _on_actor_died(id: StringName) -> void:
	if id == &"" or id == &"player":
		return
	var registry: Node = _resolve_registry()
	if registry == null:
		return  # warned once inside _resolve_registry
	if not registry.has_method("get_actor"):
		return
	var actor = registry.get_actor(id)
	if actor == null:
		return  # already gone (race?) — nothing to snapshot
	var body: Sprite2D = actor.get_node_or_null("Body") as Sprite2D
	if body == null:
		return
	var texture: Texture2D = body.texture
	if texture == null:
		if not _warned_no_texture:
			GameLogger.warn("CorpseManager", "actor %s has Body without texture; skipping corpse" % id)
			_warned_no_texture = true
		return
	var world_pos: Vector2 = actor.global_position
	var flip_h: bool = body.flip_h
	# Combine actor and body scale so corpse renders at the same visible size
	# even if either layer was scaled non-uniformly.
	var base_scale: Vector2 = actor.scale * body.scale

	var corpse_root: Node = _resolve_corpse_root(actor)
	if corpse_root == null:
		return  # no place to mount; bail silently (already warned)

	var corpse: Corpse = _CORPSE_SCENE.instantiate() as Corpse
	corpse.name = String(id) + "_corpse"
	corpse_root.add_child(corpse)
	corpse.init(texture, world_pos, flip_h, base_scale)
	_alive.append(corpse)

	# Best-effort hex coord for the lifecycle signal.
	var coord: Vector2i = Vector2i(2147483647, 2147483647)  # sentinel = unknown
	if "position_hex" in actor:
		coord = actor.position_hex
	EventBus.actor_corpse_spawned.emit(coord, corpse)

	# Fire-and-forget death animation. Tween lives on the corpse itself.
	corpse.play_death()


func _on_reset() -> void:
	clear_all()


func _on_scene_ready(_kind: StringName) -> void:
	clear_all()


func _on_corpse_arrived(target_provider: Callable) -> void:
	# Per-arrival burst shake.
	var camera: Node = get_tree().get_first_node_in_group(&"main_camera")
	if camera != null and camera.has_method("shake"):
		var amp: float = float(GameSpeed.get_value("fx", "absorption_arrival_shake_amp_px", 2.5))
		var freq: float = float(GameSpeed.get_value("fx", "absorption_arrival_shake_freq", 30.0))
		var dur: float = float(GameSpeed.get_value("fx", "absorption_arrival_shake_sec", 0.12))
		camera.shake(amp, freq, dur)
	# Heroine scale-punch.
	_heroine_scale_punch(target_provider)


# ── Heroine-side FX ─────────────────────────────────────────────────────────

func _start_camera_shake(total_sec: float) -> void:
	var camera: Node = get_tree().get_first_node_in_group(&"main_camera")
	if camera == null or not camera.has_method("shake"):
		return
	var amp: float = float(GameSpeed.get_value("fx", "absorption_screen_shake_amp_px", 4.0))
	var freq: float = float(GameSpeed.get_value("fx", "absorption_screen_shake_freq", 22.0))
	camera.shake(amp, freq, total_sec)


func _spawn_heroine_particles(target_provider: Callable, biome_tint: Color, total_sec: float) -> void:
	if not target_provider.is_valid():
		return
	var heroine_pos: Vector2 = target_provider.call()
	var amount: int = int(GameSpeed.get_value("fx", "absorption_particle_amount", 64))
	var tint_mix: float = clampf(float(GameSpeed.get_value("fx", "absorption_particle_tint_mix", 0.65)), 0.0, 1.0)

	var p := GPUParticles2D.new()
	p.name = "AbsorptionParticles"
	p.amount = amount
	p.lifetime = total_sec
	p.one_shot = false
	p.preprocess = 0.0
	p.global_position = heroine_pos

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 24.0
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 30.0
	pm.initial_velocity_max = 80.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color = Color.WHITE
	p.process_material = pm

	var base: Color = UiTheme.ABSORPTION_PARTICLE_COLOR
	p.modulate = base.lerp(biome_tint, tint_mix)
	p.z_index = 10

	# Mount on the scene tree under whatever holds the heroine — using a
	# group lookup keeps coupling minimal. Falls back to root viewport.
	var arena: Node = get_tree().get_first_node_in_group(&"arena_fx_layer")
	if arena == null:
		arena = get_tree().current_scene
	if arena == null:
		return
	arena.add_child(p)
	p.emitting = true

	# Auto-free after ritual + tail.
	get_tree().create_timer(total_sec + 0.5).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)


func _start_heroine_pulse(target_provider: Callable, biome_tint: Color, total_sec: float) -> void:
	if not target_provider.is_valid():
		return
	var heroine: Node2D = _resolve_heroine()
	if heroine == null:
		return
	var body: Sprite2D = heroine.get_node_or_null("Body") as Sprite2D
	if body == null:
		return

	var pulse_count: int = max(1, int(GameSpeed.get_value("fx", "absorption_heroine_pulse_count", 4)))
	var tint_mix: float = clampf(float(GameSpeed.get_value("fx", "absorption_heroine_tint_mix", 0.5)), 0.0, 1.0)
	var blink_intensity: float = float(GameSpeed.get_value("fx", "absorption_blink_intensity", 0.55))
	var flash_color: Color = Color.WHITE.lerp(biome_tint, tint_mix)

	var prev_material: Material = body.material
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	mat.set_shader_parameter("flash_amount", 0.0)
	mat.set_shader_parameter("flash_color", flash_color)
	body.material = mat

	var step: float = total_sec / float(pulse_count * 2)
	var tw: Tween = create_tween()
	var setter: Callable = _set_heroine_flash.bind(body, mat)
	for _i in pulse_count:
		tw.tween_method(setter, 0.0, blink_intensity, step).set_trans(Tween.TRANS_SINE)
		tw.tween_method(setter, blink_intensity, 0.0, step).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_restore_heroine_material.bind(body, mat, prev_material))


# 048: helpers — kept as named methods (not lambdas) to avoid the multiline
# lambda parser fragility documented in CLAUDE.md trap table.
func _set_heroine_flash(amount: float, body: Sprite2D, mat: ShaderMaterial) -> void:
	if not is_instance_valid(body) or body.material != mat:
		return
	mat.set_shader_parameter("flash_amount", clampf(amount, 0.0, 1.0))


func _restore_heroine_material(body: Sprite2D, mat: ShaderMaterial, prev: Material) -> void:
	if is_instance_valid(body) and body.material == mat:
		body.material = prev


func _heroine_scale_punch(_target_provider: Callable) -> void:
	var heroine: Node2D = _resolve_heroine()
	if heroine == null:
		return
	var punch: float = float(GameSpeed.get_value("fx", "absorption_heroine_scale_punch", 1.06))
	var base: Vector2 = heroine.scale
	var tw: Tween = create_tween()
	tw.tween_property(heroine, "scale", base * punch, 0.04).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(heroine, "scale", base, 0.06).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)


# ── Helpers ─────────────────────────────────────────────────────────────────

func _resolve_registry() -> Node:
	if _registry != null and is_instance_valid(_registry):
		return _registry
	_registry = get_tree().get_first_node_in_group(&"actor_registry")
	if _registry == null and not _warned_no_registry:
		GameLogger.warn("CorpseManager", "no ActorRegistry found in group; corpses won't spawn this scene")
		_warned_no_registry = true
	return _registry


# Find or create the Corpses sibling under whatever node holds Actors.
# The actor's parent is conventionally <HexGrid>/Actors.
func _resolve_corpse_root(actor: Node) -> Node:
	if _corpse_root != null and is_instance_valid(_corpse_root):
		return _corpse_root
	if actor == null:
		return null
	var actors_parent: Node = actor.get_parent()
	if actors_parent == null:
		return null
	var grid_root: Node = actors_parent.get_parent()  # <HexGrid>
	if grid_root == null:
		return null
	var existing: Node = grid_root.get_node_or_null("Corpses")
	if existing != null:
		_corpse_root = existing
		return existing
	var n := Node2D.new()
	n.name = "Corpses"
	# Inherit grid transform so corpse world coords match the same space.
	grid_root.add_child(n)
	_corpse_root = n
	return n


func _resolve_heroine() -> Node2D:
	var registry: Node = _resolve_registry()
	if registry == null or not registry.has_method("get_actor"):
		return null
	var actor = registry.get_actor(&"player")
	return actor as Node2D


# Drop freed corpses from the alive list. Cheap; called before count checks.
func _compact() -> void:
	var i: int = _alive.size() - 1
	while i >= 0:
		if not is_instance_valid(_alive[i]):
			_alive.remove_at(i)
		i -= 1


# Biome tint by dominant tile_kind across walkable cells. Cheap O(N).
# WHITE fallback for null grid / empty arena / unknown kind.
func _resolve_biome_tint(grid) -> Color:
	if grid == null:
		return Color.WHITE
	if not grid.has_method("get_all_walkable_coords"):
		return Color.WHITE
	if not grid.has_method("get_tile_kind"):
		return Color.WHITE
	var counts: Dictionary = {}
	for c in grid.get_all_walkable_coords():
		var k: StringName = grid.get_tile_kind(c)
		if k == &"":
			continue
		counts[k] = int(counts.get(k, 0)) + 1
	if counts.is_empty():
		return Color.WHITE
	var top_kind: StringName = &""
	var top_count: int = 0
	for k in counts.keys():
		if counts[k] > top_count:
			top_count = counts[k]
			top_kind = k
	if UiTheme != null:
		return UiTheme.biome_tint_for(top_kind)
	return Color.WHITE
