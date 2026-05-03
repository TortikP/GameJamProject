# 047-skill-fx-system — plan

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ cast_fsm._commit_cast (player)    ai_driver._resolve_cast_intent │
│         │                                  │                     │
│         │ await skill.cast(player, ctxs, FxDirector)             │
│         │                                  │                     │
│         └──────────────┬───────────────────┘                     │
│                        ▼                                         │
│ Skill.cast (coroutine, optional fx: Object)                      │
│   for each ability:                                              │
│     plan = ability.resolve(caster, ctx, level)   ← pure          │
│     if plan empty: skip                                          │
│     if fx:                                                       │
│       await fx.play_cast(caster, ability)        ← anim+sound    │
│       await fx.play_collisions(plan.victims, ability)            │
│     ability.apply_resolved(plan, caster, ctx)    ← effects emit  │
│     if fx: fx.play_sound_end(primary_pos, ability)               │
│   if any_resolved: cooldown += skill.cooldown                    │
│   EventBus.skill_cast.emit(...)                                  │
└──────────────────────────────────────────────────────────────────┘

         ┌──────────────────────────────────────────┐
         │ FxDirector (autoload, presentation/)     │
         │  - play_cast(caster, ability) coroutine  │
         │  - play_collisions(victims, ab) coroutine│
         │  - play_sound_end(pos, ab) sync          │
         │  - sync_telegraph_loops(actors) sync     │
         │  uses: shared flash.gdshader,            │
         │        AudioDirector.play_sfx(id, pos)   │
         └──────────────────────────────────────────┘
```

## API contracts

### `Ability` (split, scripts/core/abilities/ability.gd)

```gdscript
# NEW: pure resolve. No side effects, no signals, no apply.
func resolve(caster: Actor, ctx: Dictionary, level: int = 0) -> Dictionary
# Returns {} on bail (no targets / misconfigured / empty victims for non-create).
# Returns plan dict with keys:
#   "victims":      Array            — victims after caster-exclusion
#   "primary":      Variant          — primary target as resolved
#   "has_create":   bool             — at least one CreateEffect present
#   "create_hexes": Array[Vector2i]  — affected hexes for hex-pass (if has_create)
#   "level":        int              — captured for apply_resolved
# Plan is consumed by apply_resolved.

# NEW: apply phase. Mutates state, emits EventBus.ability_cast.
func apply_resolved(plan: Dictionary, caster: Actor, ctx: Dictionary) -> bool

# UNCHANGED entry-point (back-compat). Internally: resolve → apply_resolved.
func cast(caster: Actor, ctx: Dictionary, level: int = 0) -> bool
```

### `Skill` (scripts/core/skills/skill.gd)

```gdscript
# CHANGED: now coroutine, optional fx param. Awaits per-ability FX between
# resolve and apply when fx != null.
func cast(caster: Actor, ctxs: Array[Dictionary], fx: Object = null) -> bool
```

### `FxDirector` (NEW, scripts/presentation/fx_director.gd, autoload)

```gdscript
func play_cast(caster: Actor, ability: Ability) -> void          # coroutine, awaits anim
func play_collisions(victims: Array, ability: Ability) -> void   # coroutine, awaits flash duration
func play_sound_end(world_pos: Vector2, ability: Ability) -> void  # sync, fire-and-forget

func sync_telegraph_loops(enemies: Array) -> void  # diff-based per-actor loop sync
```

### `AudioDirector` (extend, scripts/infrastructure/audio_director.gd)

```gdscript
# NEW. id is StringName under res://assets/audio/sfx/. world_pos null = non-positional.
func play_sfx(id: StringName, world_pos: Variant = null) -> void
```

### `EventBus` (extend)

```gdscript
# NEW. Emitted from Skill.cast immediately before FX-phase of each resolved ability.
signal ability_cast_started(caster_id: StringName, ability_id: StringName, victim_ids: Array)
```

## Data: config/game_speed.cfg

```ini
[fx]
cast_animation_ms=180
collision_effect_ms=140
flash_color_intensity=0.85
telegraph_pulse_period_ms=1000
telegraph_pulse_intensity=0.4
```

## Shader

`assets/shaders/flash.gdshader` — single shader, multiplicative mix between texture and uniform `flash_color` weighted by `flash_amount` ∈ [0,1].

```glsl
shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    COLOR = vec4(mix(tex.rgb, flash_color.rgb, flash_amount), tex.a);
}
```

Applied via temporary `ShaderMaterial` set on `actor.get_node("Body")` Sprite2D, restored on tween finished.

## Color table (FxDirector internal)

```
caster anim:        Color.WHITE
telegraph loop:     Color(1.0, 0.7, 0.2)  amber
collision (victim): per first-effect type
  DamageEffect      Color(1.0, 0.3, 0.3)  red
  HealEffect        Color(0.4, 1.0, 0.4)  green
  StatusEffect      Color(1.0, 0.95, 0.3) yellow
  MoveEffect        Color(0.4, 0.85, 1.0) cyan
  CreateEffect      Color(0.85, 0.5, 1.0) purple
```

## Telegraph loop hook

`telegraph_renderer.refresh()` already iterates all live AI-controlled actors and reads `actor.cast_intent`. At the end of `refresh()`, after primary/secondary hex paint:

```gdscript
FxDirector.sync_telegraph_loops(_collect_intent_actors())
```

`FxDirector` keeps `_telegraph_loops: Dictionary[StringName, Dictionary]`:
- start: actor has cast_intent + skill.abilities[0].animation != &"" → spawn looped tween, save prev material
- stop: actor not in current set → kill tween, restore prev material, erase entry

`play_cast` defensively calls `stop_telegraph_loop(caster.actor_id)` first to avoid material conflict if loop somehow still running at cast moment.

## Touched files

**New**:
- `specs/047-skill-fx-system/{spec,plan,tasks}.md`
- `assets/shaders/flash.gdshader`
- `scripts/presentation/fx_director.gd`

**Modified**:
- `scripts/core/abilities/ability.gd` — split into resolve + apply_resolved + back-compat cast
- `scripts/core/skills/skill.gd` — coroutine cast with fx param
- `scripts/infrastructure/audio_director.gd` — play_sfx
- `scripts/infrastructure/event_bus.gd` — ability_cast_started signal
- `scripts/presentation/godmode/cast_fsm.gd` — await skill.cast(..., FxDirector)
- `scripts/presentation/godmode/ai_driver.gd` — await skill.cast(..., FxDirector)
- `scripts/presentation/godmode/telegraph_renderer.gd` — sync_telegraph_loops at end of refresh
- `project.godot` — autoload FxDirector
- `config/game_speed.cfg` — `[fx]` block

## Testing

- Manual в godmode: каст любой способности с непустыми каналами → видим белый flash на player, цветной flash на цели, цифры урона ПОСЛЕ flash'a.
- Каст способности с пустой `animation` (любой ability с `animation == &""`) → no flash на кастере, фаза t0..tA = 0.
- AI с cast_intent → амбер pulse на враге, исчезает в момент caster anim самого каста.
- Удар по цели на 1 HP, цель умирает: 2-я ability того же скилла должна skip'нуть FX (нет victims), без краша. Cooldown скилла начисляется (1-я зарезолвилась).
- Способность без victims на runtime (цель ушла из range) → ability skipped, нет ни flash, ни damage числа. Если все abilities скипнулись → cooldown НЕ начисляется.

---

## Addendum: collision_effect registry

### Sequence (updated)

```
play_collisions(caster, ability, plan, ctx):
  if ability.collision_effect == &"":            return       # no-op
  entry = _resolve_fx_entry(ability)
  if entry.is_empty():                           # registry not loaded
      await _play_legacy_body_fx(victims, ability)            # back-compat
      return
  if entry.kind == "hex":
      await _play_hex_fx(create_hexes, grid, entry)
  else:
      await _play_body_fx(caster, victims, entry)
```

### `_resolve_fx_entry(ability)` resolution table

| ability.collision_effect            | _fx_registry result                | Behavior                                  |
|-------------------------------------|------------------------------------|-------------------------------------------|
| `&""`                               | n/a (early return)                 | no-op                                     |
| `default_melee` (direct match)      | swipe entry                        | swipe on victim Body                      |
| `angel_…/foo.prefab` (no match)     | `_auto_pick_default()` → registry  | fallback shader by effect type            |
| any                                 | registry not loaded                | `_play_legacy_body_fx` (single-color)     |

### `_auto_pick_default(ability)` priority

```
CreateEffect  → default_summon
HealEffect    → default_heal
DamageEffect  → default_ranged
StatusEffect  → default_debuff
MoveEffect    → default_buff
none of above → default_ranged   (last resort)
```

### Files (addendum)

**New**:
- `assets/shaders/fx/swipe.gdshader`
- `assets/shaders/fx/impact_ring.gdshader`
- `assets/shaders/fx/heal_wave.gdshader`
- `assets/shaders/fx/stream_up.gdshader`
- `assets/shaders/fx/stream_down.gdshader`
- `assets/shaders/fx/hex_pulse.gdshader`
- `data/fx/collision_effects.json`

**Modified**:
- `scripts/presentation/fx_director.gd`:
  - `_load_fx_registry()` at `_ready`
  - `_resolve_fx_entry`, `_auto_pick_default`
  - `_play_body_fx` (registry-driven progress tween) replacing per-effect color flash
  - `_play_hex_fx` (MeshInstance2D + QuadMesh on grid)
  - `_apply_uniforms` (JSON values → shader_parameter)
  - `_play_legacy_body_fx` keeps the old single-color path as ultimate fallback
- `scripts/core/skills/skill.gd` — `play_collisions` signature `(caster, ability, plan, ctx)`
- `config/game_speed.cfg` — added `[fx] hex_effect_size_px=72`

### Shader uniform conventions

All registered shaders follow this contract for FxDirector to drive them generically:
- `progress: float [0, 1]` — required, tweened by FxDirector
- `angle: float` — set ONLY for entries with `uses_direction: true` (radians, caster→victim)
- everything else — set once from `entry.uniforms` at material creation, never tweened

### Editing without code changes

- Tweak any uniform value in `data/fx/collision_effects.json` → restart scene (hot-reload not in scope).
- Edit any `.gdshader` source → Godot recompiles on save.
- Add a new effect: write `assets/shaders/fx/foo.gdshader`, add `"foo"` entry in JSON, reference from skill JSON `collision_effect: "foo"`.
- Map effect type to a different default: change auto-pick precedence in `_auto_pick_default` (this IS code, by design — it's the dispatch policy).
