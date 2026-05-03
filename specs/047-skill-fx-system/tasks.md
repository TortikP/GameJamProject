# 047-skill-fx-system — tasks

- [x] T01 — `config/game_speed.cfg`: добавить блок `[fx]` с ключами `cast_animation_ms=180`, `collision_effect_ms=140`, `flash_color_intensity=0.85`, `telegraph_pulse_period_ms=1000`, `telegraph_pulse_intensity=0.4`.
- [x] T02 — `assets/shaders/flash.gdshader`: создать canvas_item шейдер с uniform `flash_amount` и `flash_color`.
- [x] T03 — `scripts/infrastructure/event_bus.gd`: добавить `signal ability_cast_started(caster_id, ability_id, victim_ids)` рядом с `ability_cast`. Doc-comment про timing относительно apply.
- [x] T04 — `scripts/infrastructure/audio_director.gd`: добавить `func play_sfx(id: StringName, world_pos: Variant = null) -> void`. Резолвит `res://assets/audio/sfx/<id>`, через `AudioStreamPlayer2D` если world_pos != null, иначе `AudioStreamPlayer`. Missing file → warn + return. Временная нода, queue_free на `finished`. Пустой id → return.
- [x] T05 — `scripts/presentation/fx_director.gd` (новый, autoload): preload flash.gdshader, реализовать `play_cast`, `play_collisions`, `play_sound_end`, `sync_telegraph_loops`, helpers `_flash_tween`, `_victim_flash_color`, `start_telegraph_loop`, `stop_telegraph_loop`. Поддерживать `_telegraph_loops` dict.
- [x] T06 — `project.godot`: зарегистрировать `FxDirector="*res://scripts/presentation/fx_director.gd"` в `[autoload]`. Положить ПОСЛЕ AudioDirector (FxDirector зависит от него) и UiTheme (на всякий случай для будущих theme-цветов).
- [x] T07 — `scripts/core/abilities/ability.gd`: split `cast()` на `resolve()` (pure, returns Dictionary plan) + `apply_resolved(plan, caster, ctx)` (apply + emit). `cast()` остаётся как `apply_resolved(resolve(...))` для back-compat. Doc-comment с timeline-секцией.
- [x] T08 — `scripts/core/skills/skill.gd`: переделать `cast` в корутину `cast(caster, ctxs, fx: Object = null) -> bool`. Per-ability: resolve → если plan empty skip → если fx != null `await fx.play_cast()` + `await fx.play_collisions()` → `apply_resolved` → если fx `play_sound_end()`. Cooldown / EventBus.skill_cast.emit логика без изменений (по any_resolved). `EventBus.ability_cast_started.emit` после resolve, перед FX-phase.
- [x] T09 — `scripts/presentation/godmode/cast_fsm.gd`: `_commit_cast` → `var did_cast: bool = await skill.cast(_ctrl.player, ctxs, FxDirector)`. `_commit_cast` уже async — изменений в caller'е (`commit_step`) не нужно.
- [x] T10 — `scripts/presentation/godmode/ai_driver.gd`: `skill.cast(enemy, ctxs)` → `await skill.cast(enemy, ctxs, FxDirector)`. Return value не используется.
- [x] T11 — `scripts/presentation/godmode/telegraph_renderer.gd`: в конце `refresh()` собрать массив всех живых AI-actors с непустым cast_intent, передать в `FxDirector.sync_telegraph_loops(...)`.
- [x] T12 — Smoke-проверка через grep / манusal mental-model:
   - `Skill.cast` всегда awaited
   - `Ability.cast` сохранил back-compat сигнатуру
   - shader-flash material всегда восстанавливается на `tw.finished` (no leak)
   - `_telegraph_loops` cleanup на actor death (через sync's diff: actor умер → нет в registry.all() → нет в should_loop → stop)
- [x] T13 — Commit, push на `egor/skill-fx-system`. Зацепить PR-URL из stderr.

## Addendum: collision_effect registry

- [x] T14 — `assets/shaders/fx/swipe.gdshader` — diagonal swipe band, uniform `angle` для caster→victim direction.
- [x] T15 — `assets/shaders/fx/impact_ring.gdshader` — radial expanding ring.
- [x] T16 — `assets/shaders/fx/heal_wave.gdshader` — horizontal wave bottom→top.
- [x] T17 — `assets/shaders/fx/stream_up.gdshader` — vertical streaks moving up.
- [x] T18 — `assets/shaders/fx/stream_down.gdshader` — vertical streaks moving down.
- [x] T19 — `assets/shaders/fx/hex_pulse.gdshader` — pulsing concentric ring on hex tile, transparent outside circle.
- [x] T20 — `data/fx/collision_effects.json` — registry с 6 default_* entries + `_meta` doc-блок.
- [x] T21 — `config/game_speed.cfg` — добавить `[fx] hex_effect_size_px=72`.
- [x] T22 — `scripts/presentation/fx_director.gd`:
   - `_load_fx_registry()` в `_ready()`
   - `_resolve_fx_entry(ability)` — direct lookup → auto-fallback → empty-on-load-fail
   - `_auto_pick_default(ability)` — Create>Heal>Damage>Status>Move
   - `_play_body_fx`, `_spawn_body_progress_tween`
   - `_play_hex_fx`, `_spawn_hex_progress_node` через MeshInstance2D + QuadMesh
   - `_apply_uniforms` — Array→Color/Vector3/Vector2 type-resolution
   - `_play_legacy_body_fx` — back-compat path при failed registry
   - `play_collisions` сигнатура `(caster, ability, plan, ctx)` диспетчит body vs hex
- [x] T23 — `scripts/core/skills/skill.gd` — обновить вызов `play_collisions(caster, ab, plan, ctxs[i])`.
- [x] T24 — Spec / plan addendum sections с resolution table, AC11-AC18, edit-without-code инструкции.
- [ ] T25 — Commit, push.
