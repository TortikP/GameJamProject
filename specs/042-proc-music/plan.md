# 042-proc-music — plan

См. `spec.md` для acceptance + scope. Этот документ — **HOW**: API, file paths, data flow, integration points.

## File map

| Path | Status | Purpose |
|---|---|---|
| `scripts/audio/music/music_director.gd` | new | Autoload. Owns AudioStreamPlayer + AudioStreamGenerator. EventBus subscriptions. State machine (calm/battle/menu/stopped). Sting dispatch. |
| `scripts/audio/music/conductor.gd` | new | Sample-counting clock. BPM → samples-per-beat. Emits beat/bar callbacks via direct method calls (no signals — hot path). |
| `scripts/audio/music/harmony.gd` | new | Текущий аккорд (root + intervals). Прогрессия Am–F–C–G по 4 бара. `get_chord_tones()`, `get_scale_tones()`. |
| `scripts/audio/music/synth/wavetables.gd` | new | Static. Запекает 256-сэмпловые `Float32` (PackedFloat32Array): sine, triangle, square. |
| `scripts/audio/music/synth/adsr.gd` | new | ADSR state machine. 4 phase enum + tick(samples). Без allocations. |
| `scripts/audio/music/synth/voice_pool.gd` | new | Пул из 6 голосов. Voice = oscillator type + freq + ADSR + gain + phase. `note_on(osc, midi, adsr, gain, layer)` / `release(voice_id)` / `mix(buffer, num_samples)`. |
| `scripts/audio/music/generators/bass_gen.gd` | new | Triangle, root note на beat 1, fifth на beat 3 (полу-нотный паттерн). Низкая октава (MIDI ~36-48). |
| `scripts/audio/music/generators/pad_gen.gd` | new | Две sine voice'а на 3-й и 5-й ступенях аккорда, slow attack (~400ms), sustain через весь аккорд (4 бара), release при смене. |
| `scripts/audio/music/generators/lead_gen.gd` | new | Square, играет по сетке 1/8. Strong beats → chord tone. Weak beats → passing scale note или rest. RNG-driven (через seeded). Calm: ~30% note, battle: ~70% note. |
| `scripts/audio/music/generators/drums_gen.gd` | new | Kick = sine 60Hz, fast decay (~100ms). Hat = noise через ADSR ~30ms. Паттерн: kick on 1,3 / hat on 2,4 + offbeat 8ths. Битм-only (выключен в calm). |
| `scripts/audio/music/stings/sting_player.gd` | new | Загружает `data/music/stings.json`. `play(name, harmony)` — ветвится по `kind`: procedural → ProcStings, stream → AudioStreamPlayer.load(path).play(). |
| `scripts/audio/music/stings/proc_stings.gd` | new | Static. Presets: blip_up / fanfare / descending / ping. Каждый = последовательность (osc, midi, adsr, gain, delay_samples) → накидывает в VoicePool. |
| `scripts/audio/music/state_mixer.gd` | new | Per-layer gain ramps (target + current + step). Tick раз в bar. Используется director'ом для smooth state transitions. |
| `scripts/core/maps/level_data.gd` | edit | +поле `music_config: Dictionary = {}`. +сериализация в `to_dict` / `from_dict`. +валидация (типы, диапазон BPM 40..200). ~20 строк. |
| `project.godot` | edit | +1 autoload: `MusicDirector` (после `EventBus`, до `AudioDirector` — см. notes). |
| `data/music/stings.json` | new | Дефолтный mapping: 4 procedural preset'а. |
| `data/music/main_menu.json` | new | seed/bpm/state для меню. |
| `data/maps/_schema.md` | edit | +секция `music_config` с полным описанием полей. |
| `HANDOFF.md` | edit | +секция `MusicDirector` рядом с существующим `AudioDirector`. |
| `data/maps/sample_music_test.json` | new | Sample-уровень с явным `music_config` для smoke-теста (seed/bpm override). Минимальная карта 5×5, одна волна, один enemy. |

**Итого вне модуля:** 5 файлов (level_data, project.godot, _schema.md, HANDOFF.md, sample). Контроллеры — 0 файлов. EventBus — 0 правок.

## Data flow (high-level)

```
EventBus.level_loaded(level)
    ↓
MusicDirector._on_level_loaded(level)
    - read level.music_config (or derive defaults from level.name hash)
    - Conductor.reset(bpm, seed)
    - Harmony.reset(seed)
    - VoicePool.reset()
    - StateMixer.set_state(config.base_state)  # ramp from current
    - generators: enabled per state
    ↓
_process(delta) [hot path, ~60Hz]
    - num_to_push = generator_playback.get_frames_available()
    - if num_to_push > 0:
        - while needed > 0:
            chunk = min(needed, 512)
            buffer = PackedVector2Array(chunk filled with zeros)
            Conductor.advance_samples(chunk)  # → may emit beat/bar via direct callback
            for each generator: generator.tick(chunk, buffer, ...)
                — каждый generator на beat/bar callback от Conductor решает note_on
            VoicePool.mix(buffer, chunk)
            generator_playback.push_buffer(buffer)
            needed -= chunk
    ↓
EventBus.wave_started(idx, is_special)
    ↓
MusicDirector._on_wave_started → StateMixer.set_state(&"battle") on next bar boundary
    ↓
EventBus.wave_cleared(idx, unused) → play_sting("wave_clear") + set_state(&"calm")
    ↓
EventBus.level_completed(score) → play_sting("victory"), schedule stop after sting tail
```

**Quantization:** state changes не моментальные — `set_state(target)` пишет в `_pending_state`, реальный switch на ближайшем `Conductor.tick_bar`. Гарантирует, что новый слой не врезается в середину фразы.

## Audio runtime detail

### AudioStreamGenerator setup

```gdscript
# music_director.gd in _ready():
_player = AudioStreamPlayer.new()
add_child(_player)
_player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
var stream := AudioStreamGenerator.new()
stream.mix_rate = MIX_RATE  # const, default 22050
stream.buffer_length = BUFFER_LEN_SEC  # const, 0.1 sec
_player.stream = stream
_player.play()
_playback = _player.get_stream_playback()  # AudioStreamGeneratorPlayback
```

Playback в `_process`:

```gdscript
const CHUNK_SIZE := 512  # frames per push
const MIX_RATE := 22050

func _process(_delta: float) -> void:
    if _muted_or_stopped:
        return
    var available := _playback.get_frames_available()
    while available >= CHUNK_SIZE:
        _render_chunk(CHUNK_SIZE)
        available -= CHUNK_SIZE
    # tail — push smaller chunk if any (avoids drift)
    if available > 0:
        _render_chunk(available)
```

`_render_chunk(n)`:
1. `_buf.resize(n)`; обнулить (через `fill(Vector2.ZERO)`).
2. `Conductor.advance(n)` → внутри tick'ов вызывает `_on_beat` / `_on_bar` callbacks → генераторы решают note_on.
3. `VoicePool.mix(_buf, n)` — каждый активный голос пишет в buffer (`buf[i] += vec * sample`).
4. `StingPlayer.mix(_buf, n)` — если активный sting procedural, миксует поверх (sting через свой mini-VoicePool).
5. `_playback.push_buffer(_buf)`.

`_buf` — переиспользуемый `PackedVector2Array`, создаётся раз в `_ready`, ресайз внутри безопасен.

### Conductor

```gdscript
class_name Conductor extends RefCounted

var bpm: float = 96.0
var samples_per_beat: float
var sample_pos: int = 0   # absolute samples since reset
var beat_pos: int = -1    # last beat index emitted

func reset(new_bpm: float, _seed: int) -> void:
    bpm = new_bpm
    samples_per_beat = 60.0 / bpm * MIX_RATE
    sample_pos = 0
    beat_pos = -1

# Returns array of (kind, idx) events fired during these N samples.
# Kind ∈ {&"beat", &"bar"}. Каллер передаёт в генераторы.
func advance(num_samples: int) -> Array:
    var events: Array = []
    var end_pos := sample_pos + num_samples
    while true:
        var next_beat := int((beat_pos + 1) * samples_per_beat)
        if next_beat >= end_pos: break
        beat_pos += 1
        events.append([&"beat", beat_pos])
        if beat_pos % 4 == 0: events.append([&"bar", beat_pos / 4])
    sample_pos = end_pos
    return events
```

### Voice / VoicePool

```gdscript
# Voice — POD struct via Dictionary or fixed-fields class. Use class for type-safety.
class_name Voice extends RefCounted
var active: bool = false
var osc: int = 0   # 0 sine, 1 triangle, 2 square, 3 noise
var freq: float = 0.0
var phase: float = 0.0
var phase_inc: float = 0.0
var adsr: ADSR
var gain: float = 0.0
var layer: StringName = &""  # for state mixer routing
var rng_seed: int = 0   # for noise channel determinism

# VoicePool.mix:
func mix(buf: PackedVector2Array, n: int) -> void:
    for v in _voices:
        if not v.active: continue
        var layer_gain := _state_mixer.get_layer_gain(v.layer)
        for i in n:
            var env := v.adsr.tick()
            if env <= 0.0 and v.adsr.is_finished():
                v.active = false; break
            var s: float
            match v.osc:
                0: s = WaveTables.sine(v.phase)
                1: s = WaveTables.triangle(v.phase)
                2: s = WaveTables.square(v.phase)
                3: s = _noise_sample(v)  # seeded
            s *= env * v.gain * layer_gain
            buf[i] += Vector2(s, s)
            v.phase = fmod(v.phase + v.phase_inc, 1.0)
```

`WaveTables.sine(phase)` — `_table[int(phase * 256) & 255]`. Linear interp если время позволит — иначе nearest-neighbor (для 22050 Hz и 256 точек phase шаг крупнее, но на нижних октавах слышно артефакт; добавим линейную интерполяцию в P2 если будет время — см. tasks T-POLISH).

### Harmony

```gdscript
const PROGRESSION_AM := [
    [21, [0, 3, 7]],   # A minor (A C E)
    [17, [0, 4, 7]],   # F major (F A C)
    [12, [0, 4, 7]],   # C major (C E G)
    [19, [0, 4, 7]],   # G major (G B D)
]

# A natural minor scale in MIDI offsets from root A:
const SCALE_MINOR := [0, 2, 3, 5, 7, 8, 10]  # 7 notes, octave at +12
```

Harmony.tick_bar(bar_idx) → меняет current chord на `PROGRESSION_AM[bar_idx % 4]`.
`get_chord_tones() -> Array[int]` — [root+oct, root+intervals[0]+oct, ...]
`get_scale_tones() -> Array[int]` — root + SCALE_MINOR.

### Per-level config wiring

```gdscript
# music_director.gd
func _on_level_loaded(level: LevelData) -> void:
    var cfg: Dictionary = level.music_config if level != null else {}
    var seed_v: int = int(cfg.get("seed", _hash_str(level.name) & 0x7fffffff))
    var bpm: float = float(cfg.get("bpm", 96.0))
    var base_state: StringName = StringName(cfg.get("base_state", "calm"))
    var muted: bool = bool(cfg.get("muted", false))
    var stings_override: Dictionary = cfg.get("stings", {})

    if muted:
        _stop()
        return
    _conductor.reset(bpm, seed_v)
    _harmony.reset(seed_v)
    _rng.seed = seed_v
    _voice_pool.reset()
    _state_mixer.set_state(base_state)  # ramp
    _sting_player.set_overrides(stings_override)
    _ensure_playing()
```

### LevelData edit (минимальный)

```gdscript
# В шапке:
var music_config: Dictionary = {}

# в to_dict() — добавить ключ:
"music_config": music_config.duplicate(true),

# в from_dict() — ridge case:
if d.has("music_config") and d["music_config"] is Dictionary:
    lvl.music_config = (d["music_config"] as Dictionary).duplicate(true)

# в validate() — soft warn-only (не блокирует save):
if music_config.has("bpm"):
    var bpm := float(music_config["bpm"])
    if bpm < 40.0 or bpm > 200.0:
        errors.append("WARN: music_config.bpm %.1f out of [40, 200]" % bpm)
```

Ничего больше в LevelData не правим.

## Project.godot autoload

```ini
[autoload]
...
EventBus="*res://scripts/infrastructure/event_bus.gd"
MusicDirector="*res://scripts/audio/music/music_director.gd"
AudioDirector="*res://scripts/infrastructure/audio_director.gd"
...
```

Порядок: после `EventBus` (использует), до/рядом `AudioDirector` (не зависит, но логически в audio-домене).

## Stings JSON loader

`StingPlayer._ready()`:

```gdscript
func _ready() -> void:
    var path := "res://data/music/stings.json"
    if not FileAccess.file_exists(path):
        push_warning("[StingPlayer] %s missing — stings disabled" % path)
        return
    var f := FileAccess.open(path, FileAccess.READ)
    var d: Variant = JSON.parse_string(f.get_as_text())
    if not (d is Dictionary):
        push_error("[StingPlayer] malformed stings.json"); return
    _stings_config = d.get("stings", {})
```

`play(name)`:
1. Если `_overrides.has(name)` → перенаправляем `name = _overrides[name]`.
2. Lookup `_stings_config[name]`. Нет — warn-once, return.
3. По `kind`:
   - `"procedural"` → `ProcStings.dispatch(preset, _voice_pool, _harmony.get_current_chord())`.
   - `"stream"` → load AudioStream из `path`, push в одноразовый AudioStreamPlayer (на отдельном bus или том же `Music`).

Stream-стинг — допускает любой формат, что Godot поддерживает (OGG / WAV / MP3). Volume_db опционально.

## Determinism

Один `RandomNumberGenerator` на весь модуль (`MusicDirector._rng`). Сбрасывается в `_on_level_loaded` со значением `seed_v`. Все генераторы получают **указатель** (RefCounted shared) на этот RNG, не свой.

Шум для drums и для noise-osc — отдельный RNG, тоже сидится из `seed_v + 1` (чтобы не корреляровал с lead-нотами). Тоже sample-deterministic.

Sample-точная воспроизводимость гарантируется тем, что Conductor считает sample_pos монотонно, а все решения «играть/не играть» принимаются на beat/bar callbacks от Conductor (а не на `_process` ticks от движка). Так что разное FPS на разных машинах ≠ разный output.

## Что трогаем в HANDOFF.md

Добавить секцию:

```
### `MusicDirector` (`scripts/audio/music/music_director.gd`)

Procedural music engine (042). Real-time PCM through AudioStreamGenerator,
no audio assets in source. Two states (calm/battle), JSON-configured stings
(swappable for OGG without code change). Subscribes to EventBus level/wave/menu
signals. Per-level config in LevelData.music_config (optional). Main menu
config in data/music/main_menu.json. Stings registry in data/music/stings.json.
See specs/042-proc-music for full architecture.
```

И в file tree — добавить `scripts/audio/music/` ветку и `data/music/`.

## Tuning parameters

Если звучит плохо после имплементации — крутить **в этом порядке**:

1. **BPM** в `data/music/main_menu.json` и в дефолте на уровне (96 calm, 96×1.2=115 battle). 80–120 безопасный коридор.
2. **Lead density** (`generators/lead_gen.gd::CALM_NOTE_PROB` / `BATTLE_NOTE_PROB`) — 0.3 / 0.7 default. Снизить если шумно, поднять если скучно.
3. **Pad gain** — слишком гудит → −3 dB. Слишком тонко → +2 dB.
4. **ADSR на drums** — kick decay 60ms ↔ 120ms сильно меняет «character».
5. **Прогрессия** — Am–F–C–G база; для контраста на одной волне попробовать i-VII-VI-VII (Am-G-F-G) — мажорный D9-vibe заменится на минорное настойчивое.

Не трогать: mix_rate, chunk_size, voice pool size — это perf-knobs, не musical.

## Open questions / разрулить при имплементации

- `Music` audio bus — есть ли он в `default_bus_layout.tres`? Если нет — добавляем (в спеке считаем что добавим, иначе fallback на `Master`).
- Linear interpolation в WaveTables — нужна или nearest-neighbor хватит на 22050? Решим во время AC-10 (perf профайла).
- `dialogue_started/finished` ducking — P3, может вырезать вообще.
