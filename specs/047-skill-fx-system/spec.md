# 047-skill-fx-system — spec

**Owner:** Egor
**Status:** Draft → Implement

## Goal (one sentence)

Дать каждой Ability видимый и слышимый отклик: анимация на кастере, звук старта, эффект попадания на жертвах — с правильной последовательностью «телеграф → удар → эффект» и поддержкой циклической телеграф-анимации для AI.

## Why now

Поля `sound_start / sound_end / collision_effect / animation` лежат в `Ability` с 026 без диспатча. Без обратной связи бой читается только по плавающим цифрам и обновлению HP-бара — недостаточно для Pillar 2 (CLAUDE.md «я слышу/вижу, что произошло»). Спека закрывает диспатч этих 4 каналов.

## Sequence per ability cast

```
t0       : Ability.resolve(caster, ctx, level) → plan
           ↓ (если plan пуст — skip ability, идём к следующей)
t0       : EventBus.ability_cast_started.emit(caster_id, ability_id, victim_ids)
t0       : AudioDirector.play_sfx(sound_start, caster_pos)            fire-and-forget
t0..tA   : caster.Body shader-flash                                   await
tA..tA+B : victim[*].Body shader-flash (parallel)                     await
tA+B     : Ability.apply_resolved(plan)                               урон/хил/статус, damage_dealt/heal_done emit
tA+B     : AudioDirector.play_sfx(sound_end, primary_pos)             fire-and-forget
tA+B     : EventBus.ability_cast.emit(...)                            конец, как раньше но позже по timeline
```

Все каналы независимо null-safe: `&""` → no-op, ничего не ждём.

## Acceptance criteria

- **AC1**: При cast способности с непустым `animation` на кастере проигрывается shader-flash длительностью `[fx] cast_animation_ms`. Cast явно ждёт окончания.
- **AC2**: При непустом `collision_effect` все живые victims одновременно получают shader-flash длительностью `[fx] collision_effect_ms`. Cast явно ждёт окончания.
- **AC3**: `sound_start` запускается в начале t0, параллельно с анимацией. `sound_end` — после apply_resolved. Оба fire-and-forget.
- **AC4**: Эффекты способности (damage / heal / status / move / create) применяются ТОЛЬКО после фазы коллизии. Цифры урона/хила всплывают после визуального удара.
- **AC5**: `Ability.resolve` вернул пустой план (нет victims на runtime, цели умерли и т.п.) — ability пропускается, FX не играет, apply не вызывается. Skill продолжает с следующей ability.
- **AC6**: Если хотя бы одна ability в Skill зарезолвилась — Skill уходит на cooldown по существующим правилам. Ни одна не зарезолвилась — cooldown НЕ начисляется (текущее поведение).
- **AC7**: `EventBus.ability_cast_started` эмитится перед FX-фазой каждой зарезолвленной ability с aggreg-ированным списком victim_ids.
- **AC8**: AI с активным `cast_intent`: на `Body` врага идёт зацикленный амбер-pulse (отличный от cast-flash). Cycle period = `[fx] telegraph_pulse_period_ms`. Loop стопается при сбросе `cast_intent` (после resolve / cancel / stun) — в течение одного `telegraph_renderer.refresh()`.
- **AC9**: Любой канал с пустой строкой (`&""`) не вызывает задержку и не эмитит сигналов. Ability с **всеми** пустыми каналами схлопывается обратно к синхронному apply (без visible delay сверх `ability_cast_delay`).
- **AC10**: Отсутствующий аудио-файл (путь из JSON указывает на несуществующий .wav) — `GameLogger.warn` + no-op, без краша. Текущие 55 JSON остаются как есть.

## Out of scope

- Реальные ассеты (sprites, звуки) — Катя/Никита, отдельная волна.
- Per-ability-кадровые анимации (AnimatedSprite2D, AnimationPlayer) — заглушка через shader-flash до прихода ассетов.
- Camera shake / hit-stop / particle FX (live в 029).
- Sequential cycle через все abilities скилла в телеграф-loop'е (текущая реализация — единый pulse если хоть у одной ability `animation != &""`).
- VFXDB / реестр anim/coll-effect ID → ассеты. Сейчас `convention path` под `assets/audio/sfx/` для звуков; для anim/coll value игнорируется (только non-empty флаг).

## Dependencies

- 026 — поля `sound_start/sound_end/collision_effect/animation` уже на `Ability`.
- 029 — родственная feedback-полировка; анимации тут — стаб, который заменится при наличии ассетов.

## Migration / breaking changes

- `Ability.cast` остаётся как back-compat sync wrapper (внутри: `resolve` + `apply_resolved`). Внешних callers нет (только Skill.cast).
- `Skill.cast` становится корутиной с опциональным параметром `fx: Object = null`. Все 2 существующих call-site'а (cast_fsm, ai_driver) обновляются на `await skill.cast(..., FxDirector)`.
- `EventBus.ability_cast` теперь эмитится **позже** во времени (после коллизий и apply). Для подписчиков `floating_number_layer` / `combat_log` это означает что цифры всплывают после флеша — желаемое поведение, не регресс.

## Sub-decisions (locked)

- **Shader-flash** на стандартный `Body` Sprite2D — единственный визуал на канале `animation` и `collision_effect` до прихода ассетов.
- **Цвета flash**:
  - caster anim: белый
  - victim collision: по первому effect type — DamageEffect=красный, HealEffect=зелёный, StatusEffect=жёлтый, MoveEffect=циан, CreateEffect=пурпур
  - telegraph loop: амбер `Color(1.0, 0.7, 0.2)` — отличимо
- **Audio** — `AudioStreamPlayer2D` через `AudioDirector.play_sfx(id, world_pos)`, без пула, временные ноды с `queue_free` после `finished`.
- **Asset path resolution** — convention: `res://assets/audio/sfx/` + значение из JSON. `animation` / `collision_effect` поля сейчас не резолвятся в путь, только проверяются на `is_empty`.
- **Telegraph mapping** — берём `skill.abilities[0].animation` как proxy за skill-уровень (Skill сам не имеет поля).

---

## Addendum: collision_effect default shader registry

Расширение того же канала `collision_effect`. Заменяет single-color flash на per-effect шейдеры. Существующая single-color реализация остаётся как ultimate fallback (когда registry не загрузился).

### 6 default-шейдеров

| ID                | Kind | Шейдер                                       | Эффект                                                     |
|-------------------|------|----------------------------------------------|------------------------------------------------------------|
| `default_melee`   | body | `assets/shaders/fx/swipe.gdshader`           | Дуга-slash в направлении caster→victim, leading edge + trail |
| `default_ranged`  | body | `assets/shaders/fx/impact_ring.gdshader`     | Радиальное кольцо от центра спрайта                        |
| `default_heal`    | body | `assets/shaders/fx/heal_wave.gdshader`       | Горизонтальная волна снизу вверх                           |
| `default_buff`    | body | `assets/shaders/fx/stream_up.gdshader`       | Вертикальные потоки вверх                                  |
| `default_debuff`  | body | `assets/shaders/fx/stream_down.gdshader`     | Вертикальные потоки вниз                                   |
| `default_summon`  | hex  | `assets/shaders/fx/hex_pulse.gdshader`       | Мигающий круг на спавн-тайле (MeshInstance2D + QuadMesh)   |

Все шейдеры — `canvas_item`, единый uniform `progress: float [0,1]` который Tween гонит за `duration_ms`. Цвета, ширины полос, длительности — в `data/fx/collision_effects.json`.

### Editable извне

`data/fx/collision_effects.json` — registry effect_id → `{shader, kind, duration_ms, uses_direction, uniforms}`. Stasyan/тех.дизайнер может править цвета и длительности без кода.

`uniforms` — словарь `name → value`:
- 4-element array → `Color`
- 3-element array → `Vector3`
- 2-element array → `Vector2`
- scalar → `float` / `int`

Сами .gdshader тоже редактируются (Godot пересобирает на сохранении).

### Resolution flow для `ability.collision_effect`

1. **Empty (`&""`)** → no-op, no delay (текущее поведение, сохранено)
2. **Direct hit** в registry (например, `&"default_melee"`) → используется зарегистрированный шейдер
3. **Miss** (текущие 55 JSON ссылаются на нерезолвимые `.prefab` стабы) → auto-pick `default_*` по первому effect-type:
   - `CreateEffect` → `default_summon`
   - `HealEffect` → `default_heal`
   - `DamageEffect` → `default_ranged`
   - `StatusEffect` → `default_debuff`
   - `MoveEffect` → `default_buff`
4. **Registry не загрузился вообще** → legacy single-color flash (back-compat, не регрессия)

Auto-pick использует priority order Create>Heal>Damage>Status>Move. Damage > Status: для способности «нанеси урон + наложи burn» visceral красный flash важнее чем жёлтый status-tint. Create > всё: иначе summon-only ability рендерил бы body-flash на пустом списке victims = тишина.

### Hex-mode дispatch

Когда `entry.kind == "hex"`:
- читается `plan.create_hexes` (заполняется в `Ability.resolve` при `has_create=true`)
- для каждого hex'а: `MeshInstance2D` + `QuadMesh` размером `[fx] hex_effect_size_px=72`, `position = grid.tile_map_layer.map_to_local(coord)`, `z_index=4` (выше TelegraphHex.z=3, ниже акторов)
- shader без `texture(TEXTURE,UV)` — рисует прямо, прозрачный фон для bbox
- `queue_free` на `tween.finished`

Если способность без CreateEffect, но с явным `collision_effect: default_summon` в JSON — `create_hexes` пустой, hex_fx no-op'ит. Документировано как known limitation: kind:hex имеет смысл только для CreateEffect-абилок.

### Acceptance criteria addendum

- **AC11**: Шейдеры default_melee/ranged/heal/buff/debuff корректно проигрываются на `victim.Body` Sprite2D.
- **AC12**: default_summon рендерится на coord'е каждого `create_hexes` через MeshInstance2D, не на victim'ах.
- **AC13**: `data/fx/collision_effects.json` поправили (например `stripe_color`) → следующий каст использует новые значения. Reload кеша происходит на старте сцены.
- **AC14**: `ability.collision_effect = &"default_melee"` явно в JSON → используется swipe независимо от effect type. Override работает.
- **AC15**: `collision_effect` с нерезолвимым значением (текущие 55 JSON) → fallback по effect type. Все способности рендерят что-то осмысленное.
- **AC16**: Удалили `data/fx/collision_effects.json` → fallback на legacy single-color flash, не краш.
- **AC17**: `default_melee` использует direction caster→victim — попадание в восток vs запад выглядит зеркально.
- **AC18**: Hex effect не сужает квад до круга через scale — рисует прозрачным за пределами круга в шейдере. Bbox 72×72 невидим вне эффекта.

### Out of scope (addendum)

- Knockback shader, dispel shader, dot shader — паттерны заложены, имплементить когда понадобятся.
- Per-status custom collision_effect (burn vs freeze разные visuals) — пока всё `default_debuff`.
- Combined-effect rendering (damage flash AND summon ring одновременно для hybrid способностей) — channel один, пока выбираем top-priority.
- F5 hot-reload `collision_effects.json` — registry грузится на `_ready` один раз. Hot-reload через рестарт сцены или добавить в `GameSpeed._unhandled_input` отдельным callback'ом.
