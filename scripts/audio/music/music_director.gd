## MusicDirector — autoload. Owns the PCM pipeline and reacts to EventBus.
## Real-time PCM through AudioStreamGenerator; no audio assets loaded by default.
##
## Public API (used by Music Lab and _on_level_loaded):
##   set_bpm(bpm)
##   set_state(state)          state ∈ &"calm" / &"battle" / &"menu"
##   set_seed(seed)
##   set_layer_db(layer, db)
##   set_lead_density(calm, battle)
##   play_sting(name)

extends Node

const MIX_RATE:        int = 22050
const BUFFER_LEN_SEC:  float = 0.1
const CHUNK_SIZE:      int = 512

# Preloads — explicit paths, no class_name registry issues.
const _WaveTables     = preload("res://scripts/audio/music/synth/wavetables.gd")
const _ADSR           = preload("res://scripts/audio/music/synth/adsr.gd")
const _VoicePoolSrc   = preload("res://scripts/audio/music/synth/voice_pool.gd")
const _StateMixerSrc  = preload("res://scripts/audio/music/state_mixer.gd")
const _ConductorSrc   = preload("res://scripts/audio/music/conductor.gd")
const _HarmonySrc     = preload("res://scripts/audio/music/harmony.gd")
const _BassGenSrc     = preload("res://scripts/audio/music/generators/bass_gen.gd")
const _PadGenSrc      = preload("res://scripts/audio/music/generators/pad_gen.gd")
const _LeadGenSrc     = preload("res://scripts/audio/music/generators/lead_gen.gd")
const _DrumsGenSrc    = preload("res://scripts/audio/music/generators/drums_gen.gd")
const _StingPlayerSrc = preload("res://scripts/audio/music/stings/sting_player.gd")
const _PresetResolver = preload("res://scripts/audio/music/preset_resolver.gd")

# ── Internal state ────────────────────────────────────────────────────────────

var _player:   AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _buf:      PackedVector2Array

var _conductor:    Conductor   = null
var _harmony:      Harmony     = null
var _voice_pool:   VoicePool   = null
var _state_mixer:  StateMixer  = null
var _bass_gen:     BassGen     = null
var _pad_gen:      PadGen      = null
var _lead_gen:     LeadGen     = null
var _drums_gen:    DrumsGen    = null
var _sting_player: StingPlayer = null

var _rng:       RandomNumberGenerator = null
var _noise_rng: RandomNumberGenerator = null  # for drums/noise voices

var _playing:       bool = false
var _loading_level: bool = false  # R5: block main_menu reaction after run_started_requested
var _current_state: StringName = &"stopped"
var _pending_state: StringName = &""   # applies on next bar boundary

var _stop_timer_remaining: float = 0.0   # > 0 → count down then _stop()

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	WaveTables.bake()

	# Build subsystems.
	_conductor   = _ConductorSrc.new()
	_harmony     = _HarmonySrc.new()
	_voice_pool  = _VoicePoolSrc.new()
	_state_mixer = _StateMixerSrc.new()
	_bass_gen    = _BassGenSrc.new()
	_pad_gen     = _PadGenSrc.new()
	_lead_gen    = _LeadGenSrc.new()
	_drums_gen   = _DrumsGenSrc.new()
	_sting_player = _StingPlayerSrc.new()

	_voice_pool.state_mixer = _state_mixer

	_rng       = RandomNumberGenerator.new()
	_noise_rng = RandomNumberGenerator.new()

	# Stings JSON.
	_sting_player._ready_load()

	# Audio setup.
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"

	var stream: AudioStreamGenerator = AudioStreamGenerator.new()
	stream.mix_rate     = float(MIX_RATE)
	stream.buffer_length = BUFFER_LEN_SEC
	_player.stream = stream
	_player.play()
	_playback = _player.get_stream_playback()

	# Reusable render buffer (CHUNK_SIZE is max; resize below is safe).
	_buf.resize(CHUNK_SIZE)

	# EventBus subscriptions.
	EventBus.level_loaded.connect(_on_level_loaded)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_cleared.connect(_on_wave_cleared)
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.main_menu_entered.connect(_on_main_menu_entered)
	EventBus.run_started_requested.connect(_on_run_started_requested)
	if EventBus.has_signal("dialogue_started"):
		EventBus.dialogue_started.connect(_on_dialogue_started)
	if EventBus.has_signal("dialogue_finished"):
		EventBus.dialogue_finished.connect(_on_dialogue_finished)

# ── _process (hot path) ───────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Stop timer countdown.
	if _stop_timer_remaining > 0.0:
		_stop_timer_remaining -= delta
		if _stop_timer_remaining <= 0.0:
			_stop()
			return

	if not _playing:
		return

	var available: int = _playback.get_frames_available()
	while available >= CHUNK_SIZE:
		_render_chunk(CHUNK_SIZE)
		available -= CHUNK_SIZE
	if available > 0:
		_render_chunk(available)

# ── Public API (T046) ─────────────────────────────────────────────────────────

func set_bpm(bpm: float) -> void:
	_conductor.reset(bpm, _rng.seed)

func set_state(state: StringName) -> void:
	_pending_state = state   # applied on next bar

func set_seed(seed: int) -> void:
	_rng.seed       = seed
	_noise_rng.seed = seed + 1
	_harmony.reset(seed)
	_conductor.reset(_conductor.bpm, seed)

func set_layer_db(layer: StringName, db: float) -> void:
	_state_mixer.set_layer_db(layer, db)

func set_lead_density(calm: float, battle: float) -> void:
	_lead_gen.set_density(calm, battle)

func play_sting(name: StringName) -> void:
	_sting_player.play(name, _harmony, _voice_pool, self)

# ── EventBus handlers ─────────────────────────────────────────────────────────

func _on_level_loaded(level: LevelData) -> void:
	_loading_level = false
	var raw: Dictionary = {}
	if level != null:
		raw = level.music_config

	var cfg: Dictionary = _PresetResolver.resolve(raw)

	var level_name: String = level.name if level != null else "default"
	var seed_v: int = int(cfg.get("seed",
			_hash_str(level_name) & 0x7fffffff))
	var bpm: float        = float(cfg.get("bpm", 96.0))
	var base_state: StringName = StringName(cfg.get("base_state", "calm"))
	var muted: bool       = bool(cfg.get("muted", false))
	var stings_override: Dictionary = cfg.get("stings", {})
	var lead_calm: float  = float(cfg.get("lead_density_calm", 0.3))
	var lead_battle: float = float(cfg.get("lead_density_battle", 0.7))
	var pad_db: float     = float(cfg.get("pad_gain_db", 0.0))
	var drums_db: float   = float(cfg.get("drums_gain_db", 0.0))

	if muted:
		_stop()
		return

	_rng.seed       = seed_v
	_noise_rng.seed = seed_v + 1

	_conductor.reset(bpm, seed_v)
	_harmony.reset(seed_v)
	_voice_pool.reset()

	_state_mixer.set_layer_db(&"pad",   pad_db)
	_state_mixer.set_layer_db(&"drums", drums_db)
	_lead_gen.set_density(lead_calm, lead_battle)
	_sting_player.set_overrides(stings_override)

	_apply_state(base_state)
	_ensure_playing()

func _on_wave_started(_idx: int, _is_special: bool) -> void:
	set_state(&"battle")

func _on_wave_cleared(_idx: int, _unused: int) -> void:
	play_sting(&"wave_clear")
	set_state(&"calm")

func _on_level_completed(_score: int) -> void:
	play_sting(&"victory")
	_stop_timer_remaining = 2.0

func _on_run_ended(reason: String) -> void:
	if reason == "victory":
		play_sting(&"victory")
	else:
		play_sting(&"defeat")
	_stop_timer_remaining = 2.0

func _on_main_menu_entered() -> void:
	if _loading_level:
		return
	var menu_path: String = "res://data/music/main_menu.json"
	if not FileAccess.file_exists(menu_path):
		return
	var f: FileAccess = FileAccess.open(menu_path, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return
	var cfg: Dictionary = _PresetResolver.resolve(d)
	var seed_v: int = int(cfg.get("seed", 7777))
	var bpm: float  = float(cfg.get("bpm", 72.0))
	var state: StringName = StringName(cfg.get("base_state", "calm"))

	_rng.seed       = seed_v
	_noise_rng.seed = seed_v + 1
	_conductor.reset(bpm, seed_v)
	_harmony.reset(seed_v)
	_voice_pool.reset()
	_apply_state(state)
	_ensure_playing()

func _on_run_started_requested() -> void:
	_loading_level = true   # block main_menu_entered until level_loaded

func _on_dialogue_started(_id: StringName) -> void:
	# P3: duck −6 dB — simple bus volume tweak
	var bus_idx: int = AudioServer.get_bus_index("Music")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx,
				AudioServer.get_bus_volume_db(bus_idx) - 6.0)

func _on_dialogue_finished(_id: StringName) -> void:
	var bus_idx: int = AudioServer.get_bus_index("Music")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx,
				AudioServer.get_bus_volume_db(bus_idx) + 6.0)

# ── Render ────────────────────────────────────────────────────────────────────

func _render_chunk(n: int) -> void:
	if n <= 0:
		return
	_buf.resize(n)
	# Zero fill.
	for i in n:
		_buf[i] = Vector2.ZERO

	# Advance conductor; process events.
	var events: Array = _conductor.advance(n)
	for ev in events:
		var kind: StringName = ev[0]
		var idx: int         = ev[1]
		match kind:
			&"bar":
				# Apply pending state transition at bar boundary.
				if _pending_state != &"":
					_apply_state(_pending_state)
					_pending_state = &""
				_state_mixer.tick_bar()
				_harmony.tick_bar(_conductor.current_bar())
				# Notify generators of bar.
				_pad_gen.tick_bar(_harmony, _voice_pool, _noise_rng)
				_lead_gen.set_battle(_current_state == &"battle")
			&"beat":
				var beat_in_bar: int = idx % 4
				_bass_gen.tick_beat(beat_in_bar, _harmony, _voice_pool, _noise_rng)
				_lead_gen.tick_beat(beat_in_bar, _harmony, _voice_pool, _rng)
				_drums_gen.tick_beat(beat_in_bar, _harmony, _voice_pool, _noise_rng)

	_voice_pool.mix(_buf, n)
	_playback.push_buffer(_buf)

# ── Internal ──────────────────────────────────────────────────────────────────

func _apply_state(state: StringName) -> void:
	_current_state = state
	_state_mixer.set_state(state)
	_drums_gen.set_enabled(state == &"battle")
	_lead_gen.set_battle(state == &"battle")

func _ensure_playing() -> void:
	_stop_timer_remaining = 0.0
	if not _player.playing:
		_player.play()
		_playback = _player.get_stream_playback()
	_playing = true

func _stop() -> void:
	_playing = false
	_voice_pool.reset()

func _hash_str(s: String) -> int:
	return s.hash()
