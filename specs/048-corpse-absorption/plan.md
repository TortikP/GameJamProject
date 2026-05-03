# 048-corpse-absorption — plan

## Architecture

```
            EventBus.actor_died(id)
                      │
        ┌─────────────┴─────────────┐
        ▼                           ▼
CorpseManager (autoload)    godmode_controller._on_actor_died_for_cleanup
  (connect order: first;     (existing — clears grid, unregisters,
   autoload _ready before     queue_free's the actor node)
   scene tree _ready'ies)
        │
        │ snapshot {texture, world_pos, flip_h, base_scale}
        │ from registry.get_actor(id) BEFORE cleanup runs
        │
        ▼
   spawn Corpse @ world_pos under grid/Corpses
        │
        ▼
   corpse.play_death() ───> tween: hop + blink + shrink + topple
                                                  │
                                                  ▼ corpse stays in tree
                                                    (visual-only, no logic)


            WaveController._check_auto_clear   (final wave only)
                      │
                      ▼
            CorpseManager.play_absorption_ritual(player_pos_provider)
                      │
                      ├─> EventBus.corpses_absorbing_started(N, total_sec)
                      ├─> camera.shake(amp, freq, total_sec)
                      ├─> spawn GPUParticles2D on heroine
                      ├─> heroine pulse-flash loop (N pulses over total_sec)
                      │
                      └─> for each corpse: play_absorption(target_provider, total_sec, jitter_t, jitter_speed)
                                                       │
                                                       ▼ Bezier flight + shrink + blink
                                                       │ (ends within total_sec ± 1 frame for ALL corpses)
                                                       ▼ corpse.dispose()
                      │
                      ▼ all corpses done
            EventBus.corpses_absorbed
                      │
                      ▼
            WaveController resumes: skill_offer → _advance_wave → level_completed
```

## Files

### New

- `scripts/runtime/corpse_manager.gd` — autoload, ~150 строк.
- `scripts/presentation/corpse.gd` — `class_name Corpse extends Node2D`, ~180 строк.
- `scenes/runtime/corpse.tscn` — корпс-сцена (3 узла).

### Modified

- `scripts/infrastructure/event_bus.gd` — +3 signals (`actor_corpse_spawned`, `corpses_absorbing_started`, `corpses_absorbed`), +1 секционный комментарий.
- `scripts/runtime/wave_controller.gd` — +helper `_is_final_wave`, +5 строк в `_check_auto_clear` (await блок). Strict ≤8 строк туда.
- `scripts/presentation/godmode/godmode_camera.gd` — public `shake(amp_px: float, freq: float, duration_sec: float) -> void`, internal per-frame `_shake_offset` apply в `_process`. ≤15 строк.
- `config/game_speed.cfg` — пополняется `[fx]` (см. spec §7).
- `scripts/presentation/ui_theme.gd` — `const ABSORPTION_PARTICLE_COLOR := Color(...)`.
- `project.godot` — autoload registration `CorpseManager` после `EventBus`.

## API contracts

### `Corpse` (scripts/presentation/corpse.gd)

```gdscript
class_name Corpse
extends Node2D

# Lifecycle: init → play_death → (idle, lying on arena) → play_absorption → dispose

signal death_anim_finished
signal absorbed_arrived  # emitted when this corpse reaches heroine (for per-arrival FX hook)

# CorpseManager-only entry. Pass everything; no registry/grid lookups inside Corpse.
func init(texture: Texture2D, world_pos: Vector2, flip_h: bool, base_scale: Vector2) -> void

# Awaitable. Reads tunables from GameSpeed [fx] each call.
# Internally: parallel Tween of {position.y (hop), flash_amount (blink x N), scale, rotation}.
# After tween_finished — leaves node in final state (toppled, smaller), ready to wait.
func play_death() -> void

# Awaitable. Bezier flight to target_provider.call() with per-corpse jitter.
# All corpses started within 0..jitter window MUST finish within total_sec.
# Internally:
#   - delay start_delay_sec (jitter)
#   - per-frame: t = clamp((elapsed - start_delay) / (total_sec - max_jitter) * speed_factor, 0, 1)
#   - position = bezier(P0, P1, P2, P3(t)) where P3 sampled fresh each frame
#   - scale = lerp(start_scale, shrink_to, t)
#   - flash_amount = blink at absorption_blink_period_sec with intensity
#   - on t == 1: emit absorbed_arrived, dispose()
func play_absorption(target_provider: Callable, total_sec: float, start_delay_sec: float, speed_factor: float) -> void

# Free node (queue_free). Idempotent.
func dispose() -> void
```

### `CorpseManager` (scripts/runtime/corpse_manager.gd)

```gdscript
extends Node
# class_name omitted — autoload pattern (referenced as `CorpseManager` globally).

const _Corpse = preload("res://scripts/presentation/corpse.gd")
const _CORPSE_SCENE: PackedScene = preload("res://scenes/runtime/corpse.tscn")

var _alive: Array[Corpse] = []
var _ritual_running: bool = false
var _corpse_root: Node = null  # cached lazy under HexGrid

func _ready() -> void:
    EventBus.actor_died.connect(_on_actor_died)
    EventBus.run_started.connect(_on_run_started)
    EventBus.battle_started.connect(_on_run_started)  # broader reset hook
    EventBus.scene_ready.connect(_on_scene_ready)

# Public ─────────────────────────────────────────────────────────────────

func has_corpses() -> bool
func corpse_count() -> int
func corpse_positions() -> Array[Vector2]    # for debug overlay (no implementation in 048)

## Plays absorption animation for all alive corpses. Emits started/absorbed.
## target_provider — Callable returning Vector2 (heroine global_position).
## Coroutine: await this for the full duration.
func play_absorption_ritual(target_provider: Callable) -> void

## Immediate dispose of all corpses (no animation). For reset / scene exit.
func clear_all() -> void

# Internal ───────────────────────────────────────────────────────────────

func _on_actor_died(id: StringName) -> void
# 1. Filter: id == "" or id == "player" → return
# 2. registry = get_node_or_null("/root/...") -- actor lookup (see below)
# 3. Snapshot {texture, pos, flip, scale} → spawn Corpse → mount → play_death()

func _resolve_registry() -> ActorRegistry
# Looks up via current battle scene root. Cached after first hit.

func _resolve_corpse_root() -> Node
# Looks up Corpses node under HexGrid; creates if missing. Cached.

func _heroine_provider() -> Callable
# Returns Callable closing over registry; resolves player pos per call.

func _on_run_started() -> void:  clear_all()
func _on_scene_ready(_kind: StringName) -> void:  clear_all()
```

#### Registry lookup contract

`Actor` — Node2D mounted somewhere under the battle scene. `actor_died` only carries `id`. We need the actor node BEFORE `_on_actor_died_for_cleanup` queue_free's it.

Options considered:
1. **Read from registry** — `ActorRegistry` is a Node injected on `HexGrid`. CorpseManager finds it via `get_tree().get_first_node_in_group(&"actor_registry")` (need to ensure ActorRegistry adds itself to that group on `_ready`). Works for godmode + wave-loaded levels.
2. **Have actor_died carry the node** — breaking change to a heavily-used signal. Rejected.
3. **Have CorpseManager listen to actor.died directly** — requires connecting at spawn time → coupling spawn paths. Rejected.

Option 1 is cleanest. If ActorRegistry isn't currently in a group — adding it is one line in `actor_registry.gd::_ready`. Plan task T002 covers this.

**Connection ordering**: autoload `_ready` runs before scene-tree `_ready`. CorpseManager autoload connects to `actor_died` first; godmode_setup connects cleanup later. Godot calls handlers in connection order → CorpseManager runs BEFORE the actor is freed. ✓

### `WaveController` diff (scripts/runtime/wave_controller.gd)

Around line 411–423 (current `_check_auto_clear` tail):

```gdscript
GameLogger.info("WaveController", "wave_cleared %d (unused=%d)" % [_current_wave_index, unused])
var cleared_idx: int = _current_wave_index
EventBus.wave_cleared.emit(cleared_idx, unused)

# 048-corpse-absorption — final-wave ritual BEFORE skill_offer/dialogue.
# CorpseManager emits corpses_absorbed even on no-op (empty corpse list).
if _is_final_wave(cleared_idx):
    var heroine_provider := func() -> Vector2:
        var p: Actor = registry.get_actor(&"player") if registry else null
        return p.global_position if p else Vector2.ZERO
    CorpseManager.play_absorption_ritual(heroine_provider)
    await EventBus.corpses_absorbed

if _has_skill_offer_for(cleared_idx):
    await EventBus.skill_offer_closed
_advance_wave()
```

Plus helper:

```gdscript
# 048: cleared_idx is final iff there's no waves[cleared_idx+1].
func _is_final_wave(cleared_idx: int) -> bool:
    return cleared_idx >= _level.waves.size() - 1
```

### `GodmodeCamera` diff (scripts/presentation/godmode/godmode_camera.gd)

Add module state and method:

```gdscript
var _shake_amp: float = 0.0
var _shake_freq: float = 0.0
var _shake_t: float = 0.0
var _shake_total: float = 0.0

func shake(amp_px: float, freq: float, duration_sec: float) -> void:
    _shake_amp = amp_px
    _shake_freq = freq
    _shake_t = 0.0
    _shake_total = max(0.0001, duration_sec)

func _process(delta: float) -> void:
    # ... existing follow / zoom logic ...
    if _shake_total > 0.0 and _shake_t < _shake_total:
        _shake_t += delta
        var atten: float = 1.0 - (_shake_t / _shake_total)        # linear decay; cosine if needed
        var phase: float = _shake_t * _shake_freq * TAU
        offset = Vector2(sin(phase) * 0.7, cos(phase * 1.31)) * _shake_amp * atten
    elif _shake_total > 0.0:
        offset = Vector2.ZERO
        _shake_total = 0.0
```

Audit current `_process` to make sure shake-offset doesn't fight follow-mode's `position` writes — shake writes `offset` (Camera2D's secondary), follow writes `position`. Independent in Godot 4.6 Camera2D math. ✓

## Bezier math (in corpse.gd)

```gdscript
static func _cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
    var inv: float = 1.0 - t
    return inv*inv*inv * p0 \
         + 3.0 * inv*inv * t * p1 \
         + 3.0 * inv * t*t * p2 \
         + t*t*t * p3
```

Per-frame in absorption:

```gdscript
var t: float = clamp((now - start_delay_sec) / effective_duration * speed_factor, 0.0, 1.0)
var p3: Vector2 = target_provider.call()
var dir: Vector2 = (p3 - _start_pos).normalized() if _start_pos != p3 else Vector2.RIGHT
var perp: Vector2 = Vector2(-dir.y, dir.x) * _perp_sign
var dist: float = _start_pos.distance_to(p3)
var p1: Vector2 = _start_pos + perp * dist * BEZIER_PERP_FACTOR + dir * dist * 0.05  # tiny forward bias for "tugness" feel
var p2: Vector2 = p3 + perp * dist * BEZIER_PERP_FACTOR - dir * dist * 0.05
global_position = _cubic_bezier(_start_pos, p1, p2, p3, t)
```

Sampling P3 fresh per frame is intentional — heroine может (теоретически) подвинуться (анимация heroine pulse через scale; сама позиция не двигается, но если позже добавится heroine drift во время ритуала — Bezier подхватит).

## Fixed-duration guarantee

`absorption_total_sec` — фиксированная общая длительность. Каждый корпс получает `start_delay_sec ∈ [0, jitter]`. Чтобы все успели:

```
effective_duration = total_sec - max_jitter   # safe upper bound
per_corpse_finish_t = start_delay_sec + effective_duration / speed_factor
```

При `speed_factor ∈ [0.85, 1.15]`, `effective_duration / speed_factor ∈ [0.87 * eff, 1.18 * eff]`. Берём `effective_duration = total_sec - jitter - jitter_speed_safety_margin` где `jitter_speed_safety_margin = total_sec * 0.05` (5% запас на медленных). Итого: при `total_sec=2.5`, `jitter=0.35`: `effective ≈ 2.0s`, last corpse завершается ≤ `0.35 + 2.0 / 0.85 ≈ 2.70s` — **превышает** total_sec.

Fix: `effective_duration = (total_sec - max_jitter) * min_speed_factor` где `min_speed_factor = 1 - absorption_speed_jitter`. Тогда:
```
last_finish_t = max_jitter + effective / speed_factor
              ≤ max_jitter + (total_sec - max_jitter) * min_sf / min_sf
              = total_sec ✓
```

T005 включает unit-тест-на-математике — print-debug на 50 рандомных корпсах, что все t==1 наступают в `[0, total_sec]`.

## Tween rules (Godot 4.6)

- Все tween'ы стартуем через `create_tween().tween_property(...)` с `set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)` для скейла, `EASE_IN_OUT` для opacity/flash. Хоп — `TRANS_QUART, EASE_OUT`.
- `tween.parallel()` для параллельных каналов (hop || blink || shrink || topple).
- `await tween.finished` — основной способ дождаться окончания.
- Process mode `PROCESS_MODE_PAUSABLE` — на паузе анимации замирают (если игра паузнётся посреди ритуала через debug-key).
- Не использовать `create_timer(N)` напрямую — все длительности через `GameSpeed.get_value(...)`.

## Risks

- **R1 — actor.queue_free() race с CorpseManager._on_actor_died.** Если cleanup-callback подключился раньше CorpseManager — корпс не успеет снять данные с актёра (queue_free мгновенно делает get_node_or_null null'ом? нет, не мгновенно — через cleanup в конце фрейма). Но всё равно: гарантируем connection order через autoload-первенство. Если найдём при тестировании что не работает — fallback: подключаемся к `actor.died` напрямую при `EventBus.actor_spawned` (автоспавн уже эмитит этот сигнал).
- **R2 — registry lookup отказывает в map_editor playtest.** Editor's playtest mounts a separate scene tree. Проверка на T010 — если registry недоступен → `clear_all()` no-op'ит, абсорпция skip'ается gracefully.
- **R3 — GPUParticles2D performance.** 64 partics × `total_sec`=2.5 = ~160 одновременных. На десктопе незаметно. Если web-build будет тормозить — уменьшить `amount` в конфиге (ключ `absorption_particle_amount` можно добавить позже).
- **R4 — Corpse у моба заспавнившегося но не успевшего получить Body texture** (`enemy_data_id == &""`). `Body.texture` будет null → корпс будет невидимый прямоугольник. Защита: если `texture == null` — пропускаем спавн корпса (warn-once в лог). Не критично.
- **R5 — Shake камера во время follow-mode.** Если 043-camera-follow перетирает `position` каждый фрейм — `offset` независим, не должен биться. Тест на T011.

## Out-of-band coordination

После мержа этого спека в staging — Andrey знает что 029-feedback-polish line 24 («Death animation manekin'ов — сейчас просто исчезают, нужен fall/dissolve») закрывается. В 029 spec.md делаем cancel-комментарий к этой строке (не в этом PR — отдельным ).
