class_name Corpse
extends Node2D
## Corpse — purely-cosmetic dead-body view.
##
## 048-corpse-absorption. Spawned by CorpseManager on EventBus.actor_died, lives
## under <HexGrid>/Corpses (sibling of Actors), holds NO logic — just a body
## sprite that plays death animation, then lies still on the arena, then plays
## absorption animation when the manager triggers the post-final-wave ritual.
##
## NOT registered in ActorRegistry, NOT placed in HexGrid actor map. Spells,
## tile_effects, pathfinder, AOE — all blind to it. Only paths to removal:
## (a) dispose() called by manager after absorbed_arrived, (b) clear_all() on
## reset/scene-exit. See spec 048 §AC-15 (inertia / indestructibility).
##
## Animation: all durations / amplitudes read from GameSpeed [fx] each call,
## so F5 live-reload picks up new values for the NEXT death/absorption (already-
## running tweens finish with old values — see AC-13).

const FLASH_SHADER: Shader = preload("res://assets/shaders/flash.gdshader")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# Emitted when this corpse arrives at the heroine during absorption.
# Manager listens to this for per-arrival heroine scale-punch + mini-burst shake.
signal absorbed_arrived

# Internal — used by manager only (it await's play_death indirectly via timer).
signal death_anim_finished

@onready var _body: Sprite2D = $Body

# Initial scale captured at init() so absorption-shrink lerps from the right
# starting size (after death-shrink already applied).
var _start_scale: Vector2 = Vector2.ONE
var _topple_sign: float = 1.0  # ±1, picked at init for "fall left vs right"
var _disposed: bool = false


# ── Init ────────────────────────────────────────────────────────────────────

## Set up corpse from snapshot of the dying actor. Called by CorpseManager
## ONCE before mounting the corpse to the scene tree (or right after; either
## works as long as it's before play_death). texture must not be null —
## caller checks; if it sneaks through here we warn-once and bail (no crash).
func init(texture: Texture2D, world_pos: Vector2, flip_h: bool, base_scale: Vector2) -> void:
	if texture == null:
		GameLogger.warn("Corpse", "init: texture is null, corpse will be invisible")
	# Defer node-property writes until after _ready (when @onready resolves).
	# Caller spawns scene → add_child → _ready fires → this method may be
	# called before _ready completes if invoked before add_child. Guard with
	# is_node_ready trap from CLAUDE.md traps table.
	if not is_node_ready():
		ready.connect(init.bind(texture, world_pos, flip_h, base_scale), CONNECT_ONE_SHOT)
		return
	global_position = world_pos
	scale = base_scale
	_start_scale = base_scale
	_topple_sign = 1.0 if randf() < 0.5 else -1.0
	if _body != null:
		_body.texture = texture
		_body.flip_h = flip_h


# ── Death animation ─────────────────────────────────────────────────────────

## Awaitable death animation. Parallel: hop + blink + shrink + topple.
## Idempotent — second call no-op's.
func play_death() -> void:
	if _disposed:
		return
	if not is_node_ready():
		await ready
	if _body == null:
		return
	var total_sec: float = float(GameSpeed.get_value("fx", "corpse_death_total_sec", 0.65))
	var hop_h: float = float(GameSpeed.get_value("fx", "corpse_death_hop_height_px", 18.0))
	var blink_count: int = int(GameSpeed.get_value("fx", "corpse_death_blink_count", 3))
	var blink_intensity: float = float(GameSpeed.get_value("fx", "corpse_death_blink_intensity", 0.85))
	var shrink_to: float = float(GameSpeed.get_value("fx", "corpse_death_shrink_to", 0.85))
	var topple_deg: float = float(GameSpeed.get_value("fx", "corpse_death_topple_deg", 85.0))

	# Apply flash material (kept after death, used again in absorption).
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	mat.set_shader_parameter("flash_amount", 0.0)
	mat.set_shader_parameter("flash_color", Color.WHITE)
	_body.material = mat

	var tw: Tween = create_tween()

	# Hop: body local y goes 0 → -hop_h → 0 over total_sec/2 each leg.
	# Use parallel for first half, second half chains via parallel-then-default.
	var leg: float = total_sec * 0.5
	tw.tween_property(_body, "position:y", -hop_h, leg).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "position:y", 0.0, leg).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)

	# Parallel — blink. Blink_count peaks across total_sec.
	# Realised as a chain of 2*N tween_method steps (0→peak→0 per blink).
	var blink_tw: Tween = create_tween()
	var blink_step: float = total_sec / float(max(1, blink_count) * 2)
	for _i in blink_count:
		blink_tw.tween_method(_set_flash, 0.0, blink_intensity, blink_step).set_trans(Tween.TRANS_SINE)
		blink_tw.tween_method(_set_flash, blink_intensity, 0.0, blink_step).set_trans(Tween.TRANS_SINE)

	# Parallel — shrink. base → base * shrink_to.
	var shrink_tw: Tween = create_tween()
	shrink_tw.tween_property(self, "scale", _start_scale * shrink_to, total_sec).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

	# Parallel — topple. Rotation 0 → topple_rad over second half.
	var topple_tw: Tween = create_tween()
	topple_tw.tween_interval(total_sec * 0.4)  # wait until hop near apex
	topple_tw.tween_property(self, "rotation", deg_to_rad(topple_deg) * _topple_sign, total_sec * 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)

	# Update _start_scale to the post-death size so absorption shrinks from here.
	_start_scale = _start_scale * shrink_to

	await tw.finished
	death_anim_finished.emit()


# ── Absorption animation ────────────────────────────────────────────────────

## Awaitable cubic-Bezier flight to target_provider.call() over `motion_sec`
## actual seconds, after `start_delay` seconds of waiting in place.
## CorpseManager passes the SAME motion_sec for all corpses in a single ritual,
## adjusted by per-corpse speed_factor BEFORE the call (so motion_sec already
## includes the speed scaling). Bezier control points computed internally using
## absorption_bezier_perp_factor for slow-fast-slow profile.
##
## On arrival: emit absorbed_arrived, dispose self.
func play_absorption(
		target_provider: Callable,
		motion_sec: float,
		start_delay: float,
	) -> void:
	if _disposed:
		return
	if not is_node_ready():
		await ready
	if _body == null:
		dispose()
		return

	var perp_factor: float = float(GameSpeed.get_value("fx", "absorption_bezier_perp_factor", 0.18))
	var blink_period: float = float(GameSpeed.get_value("fx", "absorption_blink_period_sec", 0.12))
	var blink_intensity: float = float(GameSpeed.get_value("fx", "absorption_blink_intensity", 0.55))
	var shrink_to: float = float(GameSpeed.get_value("fx", "absorption_corpse_shrink_to", 0.0))

	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
		if _disposed:
			return

	var p0: Vector2 = global_position
	var perp_sign: float = 1.0 if randf() < 0.5 else -1.0
	var start_scale: Vector2 = scale

	# Bind all per-corpse params except t (which tween_method drives 0→1).
	# bind() appends args AFTER t, so _apply_absorption_step takes t FIRST.
	var step: Callable = _apply_absorption_step.bind(
		p0, target_provider, perp_factor, perp_sign,
		start_scale, shrink_to, motion_sec, blink_period, blink_intensity
	)
	var tw: Tween = create_tween()
	tw.tween_method(step, 0.0, 1.0, motion_sec)
	await tw.finished

	if not _disposed:
		absorbed_arrived.emit()
		dispose()


func _apply_absorption_step(
		t: float,
		p0: Vector2,
		target_provider: Callable,
		perp_factor: float,
		perp_sign: float,
		start_scale: Vector2,
		shrink_to: float,
		motion_sec: float,
		blink_period: float,
		blink_intensity: float,
	) -> void:
	if _disposed or _body == null:
		return
	# Sample target fresh each step — heroine may move / be replaced.
	var p3: Vector2 = target_provider.call() if target_provider.is_valid() else p0
	var diff: Vector2 = p3 - p0
	var dist: float = diff.length()
	var dir: Vector2 = diff.normalized() if dist > 0.001 else Vector2.RIGHT
	var perp: Vector2 = Vector2(-dir.y, dir.x) * perp_sign
	# Slight forward bias on P1, backward on P2 — the "tug" feel at endpoints.
	var p1: Vector2 = p0 + perp * dist * perp_factor + dir * dist * 0.05
	var p2: Vector2 = p3 + perp * dist * perp_factor - dir * dist * 0.05
	global_position = _cubic_bezier(p0, p1, p2, p3, t)
	# Scale lerp.
	scale = start_scale.lerp(start_scale * shrink_to, t)
	# Flash blink — fast oscillation at blink_period frequency.
	var elapsed_real: float = t * motion_sec
	var phase: float = fmod(elapsed_real, blink_period) / blink_period  # ∈ [0,1)
	var flash: float = sin(phase * PI) * blink_intensity                 # peak mid-period
	_set_flash(flash)


static func _cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var inv: float = 1.0 - t
	return inv * inv * inv * p0 \
		+ 3.0 * inv * inv * t * p1 \
		+ 3.0 * inv * t * t * p2 \
		+ t * t * t * p3


# ── Helpers ─────────────────────────────────────────────────────────────────

func _set_flash(amount: float) -> void:
	if _body == null:
		return
	var mat: ShaderMaterial = _body.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("flash_amount", clampf(amount, 0.0, 1.0))


## Idempotent free. Called by manager after absorption arrival, or directly
## via clear_all() on reset.
func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	queue_free()
