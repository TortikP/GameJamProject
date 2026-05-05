class_name SpawnerPlaceholder
extends Node2D

## SpawnerPlaceholder — visual marker on a hex showing "an enemy is about to
## spawn here in N turns". Renders the spawner's reference sprite at half
## opacity plus a big number label overhead with a punch tween on each
## decrement. Removed by WaveController when timer hits 0 and the real actor
## instantiates (or when its wave changes before the timer ran out).
##
## Created by WaveController._apply_wave_snapshot. The owner sets
## `set_timer(n)` once on creation and again on each decrement. Actual
## instantiation of the real actor is the controller's job — this node is
## visual-only.
##
## Visual style:
##   - Sprite tinted via UiTheme (dim, no team color) so it reads as "ghost".
##   - Big number Label overhead with FS_NUM_OVERHEAD-ish font + outline
##     (visibility doctrine, CLAUDE.md §Visibility doctrine).
##   - Punch tween on decrement (scale 1.0 → 1.2 → 1.0) using GameSpeed
##     ui.wave_tick_anim_sec.
##
## Position is set externally (parent assigns position via tile_map_layer
## map_to_local). Z-index high enough to read over floor + objects but
## below floating combat numbers.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const UiThemeScript = preload("res://scripts/presentation/ui_theme.gd")
const EnemyDataLoader := preload("res://scripts/core/actors/enemy_data_loader.gd")

# Public state — set by WaveController.
var spawner_kind: StringName = &""   # &"enemy" only currently (player skipped)
var spawner_ref: StringName = &""    # e.g. &"boar", &"slime"
var coord: Vector2i = Vector2i.ZERO
var timer: int = 1

@onready var _sprite: Sprite2D = $Sprite
@onready var _label: Label = $Label

## Spec 050 rev3: shadow silhouette tint applied via modulate. RGB knocked
## down to ~30% so the placeholder reads as "darkened version of the actor
## about to spawn here" rather than a half-transparent ghost. Alpha kept
## near-opaque (0.85) so the silhouette stays solid against the hex grid.
const SHADOW_TINT: Color = Color(0.3, 0.3, 0.3, 0.85)


func _ready() -> void:
	z_index = 5  # above floor (z 0) + objects (z ~3), below floating numbers (z 8+)
	_apply_visuals()
	_refresh_label()


## Set or update the countdown number. Triggers the punch tween on
## decrement (not on the initial set).
func set_timer(new_timer: int) -> void:
	var was: int = timer
	timer = max(0, new_timer)
	if not is_node_ready():
		ready.connect(_refresh_label, CONNECT_ONE_SHOT)
		return
	_refresh_label()
	if was > timer:
		_punch()


func bind(kind: StringName, ref: StringName, c: Vector2i, t: int) -> void:
	spawner_kind = kind
	spawner_ref = ref
	coord = c
	timer = t


func _apply_visuals() -> void:
	if _sprite == null:
		return
	# Spec 050 rev3: resolve sprite dynamically from enemy data — no
	# hardcoded ENEMY_SPRITES dict, no manekin dependency. Each enemy JSON
	# in data/enemies/<id>.json owns its own sprite path; we read just that
	# field via EnemyDataLoader.get_sprite_path. If the kind isn't &"enemy",
	# the lookup returns "" and the sprite stays texture-less — placeholder
	# shows just the countdown label without a body.
	_sprite.texture = null
	if spawner_kind == &"enemy":
		var path: String = EnemyDataLoader.get_sprite_path(spawner_ref)
		if path != "":
			var tex := load(path) as Texture2D
			if tex != null:
				_sprite.texture = tex
			else:
				GameLogger.warn("SpawnerPlaceholder", "%s: failed to load sprite '%s'" % [spawner_ref, path])
	# Darken the silhouette via modulate. The Color() literal here is a
	# render modulator on the sprite, not a UI palette colour, so it
	# doesn't go through UiTheme.
	_sprite.modulate = SHADOW_TINT


func _refresh_label() -> void:
	if _label == null:
		return
	_label.text = str(timer)
	# Apply font + outline through UiTheme each refresh — cheap, idempotent,
	# keeps visuals consistent if UiTheme reloads.
	UiThemeScript.apply_label_kind(_label, "num_huge")
	UiThemeScript.apply_world_text_outline(_label)


func _punch() -> void:
	if _label == null:
		return
	# Scale tween 1.0 → 1.2 → 1.0. Two segments, total length from GameSpeed.
	var dur: float = float(GameSpeed.get_value("ui", "wave_tick_anim_sec", 0.2))
	var t: Tween = create_tween()
	_label.pivot_offset = _label.size * 0.5
	t.tween_property(_label, "scale", Vector2(1.2, 1.2), dur * 0.5)
	t.tween_property(_label, "scale", Vector2(1.0, 1.0), dur * 0.5)
