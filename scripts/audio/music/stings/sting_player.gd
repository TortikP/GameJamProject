## StingPlayer — loads stings.json, routes play(name) to procedural or OGG stream.
## Procedural: ProcStings.dispatch_*(voice_pool, harmony).
## Stream: load(path) → AudioStreamPlayer one-shot.
##
## set_overrides(dict) accepts per-level sting name remapping.

class_name StingPlayer

const STINGS_PATH: String = "res://data/music/stings.json"

var _stings_config: Dictionary = {}
var _overrides: Dictionary = {}
var _warned_missing: Dictionary = {}   # warn-once per name

func _ready_load() -> void:
	if not FileAccess.file_exists(STINGS_PATH):
		push_warning("[StingPlayer] %s missing — stings disabled" % STINGS_PATH)
		return
	var f: FileAccess = FileAccess.open(STINGS_PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		push_error("[StingPlayer] malformed stings.json")
		return
	_stings_config = d.get("stings", {})

## Override sting name mappings from per-level config.
func set_overrides(overrides: Dictionary) -> void:
	_overrides = overrides

## Play a sting by name. Needs VoicePool and Harmony refs (for procedural).
## node_parent: a Node to attach one-shot AudioStreamPlayers to (for stream kind).
func play(name: StringName, harmony: Harmony, voice_pool: VoicePool,
		node_parent: Node) -> void:
	# Apply override first.
	var resolved: StringName = StringName(_overrides.get(name, name))

	var cfg: Variant = _stings_config.get(resolved, null)
	if cfg == null:
		if not _warned_missing.has(resolved):
			push_warning("[StingPlayer] unknown sting '%s'" % resolved)
			_warned_missing[resolved] = true
		return

	var kind: String = String(cfg.get("kind", "procedural"))
	match kind:
		"procedural":
			_play_procedural(String(cfg.get("preset", "")), harmony, voice_pool, node_parent)
		"stream":
			_play_stream(String(cfg.get("path", "")),
					float(cfg.get("volume_db", 0.0)), node_parent)
		_:
			push_warning("[StingPlayer] unknown sting kind '%s'" % kind)

# ── Private ──────────────────────────────────────────────────────────────────

func _play_procedural(preset: String, harmony: Harmony, voice_pool: VoicePool,
		_node_parent: Node) -> void:
	var noise_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	noise_rng.seed = randi()   # stings intentionally non-deterministic re: seed
	match preset:
		"blip_up":     ProcStings.dispatch_blip_up(voice_pool, harmony, noise_rng)
		"fanfare":     ProcStings.dispatch_fanfare(voice_pool, harmony, noise_rng)
		"descending":  ProcStings.dispatch_descending(voice_pool, harmony, noise_rng)
		"ping":        ProcStings.dispatch_ping(voice_pool, harmony, noise_rng)
		_:
			push_warning("[StingPlayer] unknown procedural preset '%s'" % preset)

func _play_stream(path: String, volume_db: float, node_parent: Node) -> void:
	if path.is_empty():
		push_warning("[StingPlayer] stream path empty")
		return
	if not ResourceLoader.exists(path):
		push_warning("[StingPlayer] stream path not found: %s" % path)
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		push_error("[StingPlayer] failed to load stream: %s" % path)
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	node_parent.add_child(player)
	player.stream = stream
	player.volume_db = volume_db
	player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	player.play()
	# Auto-free when done.
	player.finished.connect(player.queue_free)
