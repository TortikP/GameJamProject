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

# Public state — set by WaveController.
var spawner_kind: StringName = &""   # &"enemy" only currently (player skipped)
var spawner_ref: StringName = &""    # e.g. &"manekin"
var coord: Vector2i = Vector2i.ZERO
var timer: int = 1

@onready var _sprite: Sprite2D = $Sprite
@onready var _label: Label = $Label

# Manekin sprite is the only enemy art today. When new enemies are added,
# extend this map; falls back to a generic "?" rendering.
const ENEMY_SPRITES: Dictionary = {
	&"manekin": preload("res://assets/sprites/manekin.png"),
}


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
	# Pick texture from ref. Unknown ref → leave whatever was set in the
	# scene (manekin by default).
	if ENEMY_SPRITES.has(spawner_ref):
		_sprite.texture = ENEMY_SPRITES[spawner_ref]
	# Half-transparent + neutral tint — placeholder shouldn't read as a
	# living actor. The Color() literal here is an alpha modulator on the
	# sprite, not a UI palette colour, so it doesn't go through UiTheme.
	_sprite.modulate = Color(1.0, 1.0, 1.0, 0.45)


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
