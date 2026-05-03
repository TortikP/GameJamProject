# 048-corpse-absorption — spec

**Owner:** Egor (battle loop, enemy lifecycle).
**Coordination:**
- **Andrey** (024 WaveController, 040 SkillOfferController) — добавляется одна точка прерывания в `WaveController._check_auto_clear` (await `corpses_absorbed` если cleared_idx — последняя волна). Не правим SkillOfferController — он сам по себе работает корректно после нашего await.
- **Andrey/Sergey** (047 FxDirector) — переиспользуем `flash.gdshader`. Не правим FxDirector, не добавляем туда новые кейсы.
**Status:** Draft (clarify-round pending — см. Open questions).

## Цель

1. **Death ritual.** Когда моб умирает (любая причина: damage / `kill_with_reason` / push-out crush) — он не «исчезает», а превращается в труп: пропадает HP-бар и иконки статусов, тушка подпрыгивает, мигает, уменьшается, заваливается на бок и остаётся лежать на гексе до конца боя. Несколько трупов на одном гексе просто наслаиваются.
2. **Absorption ritual.** После победы над **последней волной уровня**, до открытия skill_offer / level-completion-диалога — все накопленные трупы (с рандомным джиттером по времени старта и скорости) летят к героине по кубическим Безье-кривым (медленно-быстро-медленно), уменьшаясь и дисторсясь, «растворяются в ней». Героиня пульсирует/мигает, спавнятся круглые партиклы, экран дрожит. Управление у игрока на это время отбирается. Полная длительность ритуала фиксированная (для синхронизации звука).

## Scope-граница

**В скоупе:**
- Новый presentation-узел Corpse (`scenes/runtime/corpse.tscn` + `scripts/presentation/corpse.gd`) — Sprite2D + ShaderMaterial(`flash.gdshader`) + Tween-based анимация смерти и поглощения. Без бизнес-логики, без подключения к grid/registry.
- Новый runtime autoload `CorpseManager` (`scripts/runtime/corpse_manager.gd`) — слушает `EventBus.actor_died` (фильтр: не игрок), снимает данные с актёра до его cleanup'а (texture, position, scale, flip_h), спавнит Corpse, держит список живых трупов, оркеструет absorption-ритуал по запросу. Эмитит сигналы lifecycle (см. ниже).
- Новые `EventBus` сигналы: `actor_corpse_spawned`, `corpses_absorbing_started`, `corpses_absorbed`.
- Точка прерывания в `WaveController._check_auto_clear` (~3 строки): после `wave_cleared.emit`, если `cleared_idx == _level.waves.size() - 1` — `await EventBus.corpses_absorbed` ДО блока `_has_skill_offer_for(...)`.
- Новые ключи в `config/game_speed.cfg [fx]` для тюнинга длительностей (см. plan.md).
- Регистрация автолоада в `project.godot` (после `EventBus`, до `WaveController`-instances).
- Очистка корпсов на ресет / выход из боя (godmode F2 reset, выход в меню) — корпсы не должны утекать между ранами.

**Вне скоупа:**
- Per-enemy кастомные тушки/спрайты для трупов. Мы реюзаем `Body` текстуру актёра, поворот на бок делается через `rotation`. Если у Кати позже появится отдельный corpse-sprite per-enemy — отдельный спек.
- Звук death и absorption. Слот в API оставляем (`AudioDirector.play_sfx(id, pos)` callsite), но конкретные `sfx_id` — пустая StringName в этом спеке. Конкретику накатим в audio-pass.
- Particle textures от Кати. На время spec'а — простой круглый glow от `assets/sprites/` + `CircleShape2D`-генерируемые билборды через `GPUParticles2D` дефолтным шейдером. Если Катя пришлёт сферические партиклы — подключим текстурой, без правок кода.
- Меняющая поведение корпса логика: blocking движения, taunt-aura, resurrection. Корпсы — **чистая косметика**. Pathfinder через них ходит, спеллы их игнорируют, AI их не видит.
- Корпс игрока. Игрок умирает → game over, корпс не спавнится (защитная проверка в `CorpseManager`).

## Что вводится

### 1. Сцена `scenes/runtime/corpse.tscn`

```
Corpse (Node2D, scripts/presentation/corpse.gd)
├── Sprite2D (Body)              # texture set on init, ShaderMaterial(flash)
└── (Particle slot reserved)     # spawned/freed during absorption only
```

Свойства узла:
- `name = "<actor_id>_corpse"` (постфикс `_corpse` — требование Egor'а).
- `z_index = 3` (ниже живых актёров z=4, но выше тайлов).
- `process_mode = PROCESS_MODE_PAUSABLE` (на паузе анимация замирает).

### 2. API `Corpse` (scripts/presentation/corpse.gd)

```gdscript
class_name Corpse
extends Node2D

# One-shot init from CorpseManager. Caller passes everything Corpse needs to
# stand alone — no registry/grid lookups from here.
func init(texture: Texture2D, world_pos: Vector2, flip_h: bool, base_scale: Vector2) -> void

# Death animation. Returns when finished (~0.6s, GameSpeed-driven). Idempotent.
func play_death() -> void  # awaitable

# Absorption flight to a target world-space point. Total duration fixed across
# all corpses (passed by manager so audio can be cued once).
# `start_delay_sec` and `speed_factor` introduce per-corpse jitter.
# Bezier control points computed internally for slow-fast-slow profile.
func play_absorption(target_pos_provider: Callable, total_sec: float, start_delay_sec: float, speed_factor: float) -> void  # awaitable

# Cleanup hook. Frees the node. Called by CorpseManager on absorption-end / reset.
func dispose() -> void
```

### 3. Autoload `CorpseManager` (scripts/runtime/corpse_manager.gd)

Зарегистрирован в `project.godot` после EventBus:

```gdscript
extends Node
class_name CorpseManager

# Public API
func has_corpses() -> bool
func corpse_count() -> int
func play_absorption_ritual(target_provider: Callable) -> void  # async; emits started/absorbed
func clear_all() -> void  # immediate dispose, no animation; for reset/scene exit

# EventBus connections
# - actor_died → _on_actor_died (filter: id != "player", actor must exist in registry)
# - run_started, scene_ready (battle reload) → clear_all
```

Логика `_on_actor_died(id)`:
1. `if id == &"player"` → return.
2. `var actor = registry.get_actor(id)` — если null → return (актёр уже улетел через прямой queue_free вне нашей цепочки).
3. Снимаем `body = actor.get_node_or_null("Body") as Sprite2D`. Если null → warn-once, return.
4. Снимаем `world_pos = actor.global_position`, `flip_h = body.flip_h`, `base_scale = actor.scale * body.scale`, `texture = body.texture`.
5. Инстанцируем Corpse, mount под `_get_corpse_root()` (см. ниже), `init(...)`, `_alive_corpses.append(corpse)`, `EventBus.actor_corpse_spawned.emit(actor.position_hex, corpse)` (если есть `position_hex`, иначе пропускаем поле или передаём `Vector2i(INF,INF)`).
6. `corpse.play_death()` — fire-and-forget.

`_get_corpse_root()`: ищет `grid/Corpses` под текущим `HexGrid`-узлом (через `actor.get_parent().get_parent()` или registry-resolved grid). Если узла нет — создаёт `Node2D` с именем `"Corpses"` рядом с `Actors`. Однократно.

### 4. Новые `EventBus` сигналы

```gdscript
# 048: corpse lifecycle
signal actor_corpse_spawned(coord: Vector2i, corpse_node: Node)
signal corpses_absorbing_started(count: int, total_sec: float)
signal corpses_absorbed
```

`actor_corpse_spawned` — на случай если presentation-слой захочет дополнительно реагировать (например, краткая вспышка на гексе). Не используется в этом спеке, задел на будущее.

### 5. Точка прерывания в `WaveController._check_auto_clear`

Diff-set (~5 строк):

```gdscript
EventBus.wave_cleared.emit(cleared_idx, unused)

# 048: absorption ritual on final wave only, BEFORE skill_offer + dialogue.
if _is_final_wave(cleared_idx) and CorpseManager.has_corpses():
    CorpseManager.play_absorption_ritual(_player_world_pos_provider())
    await EventBus.corpses_absorbed

if _has_skill_offer_for(cleared_idx):
    await EventBus.skill_offer_closed
_advance_wave()
```

`_is_final_wave(idx)` — приватный helper: `idx == _level.waves.size() - 1`.
`_player_world_pos_provider()` — `Callable` возвращающий `Vector2` через `registry.get_actor(&"player").global_position`. Передаём callable, а не значение, чтобы движение игрока во время ритуала (если оно вдруг произойдёт) трекалось живьём.

### 6. Геометрия Безье

Кубический Безье `B(t) = (1-t)³P0 + 3(1-t)²t·P1 + 3(1-t)t²·P2 + t³P3`, t ∈ [0,1].

- `P0 = corpse_start_pos`
- `P3 = target_pos_provider.call()` (heroine, sampled per-frame в начале каждого тика анимации)
- `P1 = P0 + perp_offset * A_short` — близкий к старту control, заставляет начало быть медленным/висеть.
- `P2 = P3 + perp_offset * B_short` — близкий к концу control, заставляет финал тоже быть медленным.
- `perp_offset` — нормаль к (P3-P0), знак случайный per-corpse, чтобы траектории веером.
- `A_short / B_short` — длины ~ `0.18 * |P3-P0|` (короткие → медленный заход и подход).
- Скорость per-corpse регулируется `speed_factor` ∈ [0.85, 1.15] (jitter), общая длительность фиксированная.

### 7. Конфиг (`config/game_speed.cfg [fx]`)

Новые ключи:

```ini
[fx]
# 048-corpse-absorption — death ritual (per-corpse, on actor_died)
corpse_death_total_sec=0.65
corpse_death_hop_height_px=18.0
corpse_death_blink_count=3
corpse_death_blink_intensity=0.85
corpse_death_shrink_to=0.85
corpse_death_topple_deg=85.0

# 048-corpse-absorption — absorption ritual (post-final-wave, all corpses)
absorption_total_sec=2.5
absorption_per_corpse_jitter_sec=0.35     ; max start_delay_sec per corpse
absorption_speed_jitter=0.15              ; speed_factor ∈ [1-x, 1+x]
absorption_bezier_perp_factor=0.18        ; A_short / B_short relative to flight length
absorption_blink_period_sec=0.12          ; absorption-blink (fast, distinct from death-blink)
absorption_blink_intensity=0.55
absorption_corpse_shrink_to=0.0           ; final scale at arrival
absorption_heroine_pulse_count=4
absorption_heroine_scale_punch=1.06
absorption_heroine_tint_mix=0.5           ; 0=pure white, 1=pure biome tint (heroine flash)
absorption_screen_shake_amp_px=4.0        ; monotonic background
absorption_screen_shake_freq=22.0
absorption_arrival_shake_amp_px=2.5       ; per-arrival mini-burst
absorption_arrival_shake_freq=30.0
absorption_arrival_shake_sec=0.12
absorption_particle_amount=64
absorption_particle_tint_mix=0.65         ; 0=pure ABSORPTION_PARTICLE_COLOR, 1=pure biome tint
```

### 8. Дрожание экрана

Реализуем мини-функцию на `GodmodeCamera`: `shake(amp_px, freq, duration_sec)` — добавляет `offset = Vector2(noise_x, noise_y) * amp` поверх follow-режима, угасает к нулю по cosine. ≤15 строк, не лезем в существующую логику follow / zoom / pan. CorpseManager вызывает `camera.shake(...)` один раз в начале absorption и опционально на каждое прибытие (см. OQ-3).

### 9. Партиклы

`GPUParticles2D` инстанцируется CorpseManager'ом на героине в начале absorption:
- `amount = 64`, `lifetime = absorption_total_sec`, `one_shot = false` (continuous emission), texture — круглый glow (assets уже есть для стрима — `stream_up.gdshader`-овская атмосфера переиспользуется или простой `CircleShape2D`-эмиссия).
- Цвет — UiTheme-managed нейтральный белый/мятный (через новую константу `UiTheme.ABSORPTION_PARTICLE_COLOR` чтобы не хардкодить).
- На каждом «прибытии» корпса (callback `corpse.absorbed_arrived`) — `emitting = true` пик/burst, либо отдельный одноразовый burst.

## Acceptance criteria

- **AC-1 (death visual).** Любой моб (любой `enemy_data_id`) при HP=0 или `kill_with_reason` визуально превращается в труп: HP-бар и status-strip исчезают **до** старта анимации; sprite подпрыгивает на `corpse_death_hop_height_px`, мигает `corpse_death_blink_count` раз через flash.gdshader, ужимается до `corpse_death_shrink_to`, поворачивается на `corpse_death_topple_deg` градусов; полная длительность = `corpse_death_total_sec`.
- **AC-2 (corpse persists).** После окончания AC-1 узел остаётся в дереве сцены, лежит на хексе, не реагирует на ввод/AI/спеллы. Pathfinder, MoveRangeOverlay, target-pickers ведут себя так, будто его нет (visual-only). При нескольких смертях на одном гексе — наслаиваются (Z по порядку добавления).
- **AC-3 (no leak).** Ресет F2 (godmode), выход в main menu, перезапуск ActiveGame через CampaignController — корпсы освобождаются (`CorpseManager.clear_all()`), узел `Corpses` пуст. Никаких корпсов между ранами / уровнями.
- **AC-4 (no player corpse).** Если умирает игрок — корпс не спавнится. Существующий game-over flow сохраняется.
- **AC-5 (sequencing).** На последней волне после `wave_cleared.emit`: (1) если `has_corpses()` — `play_absorption_ritual` стартует, эмитится `corpses_absorbing_started(count, total_sec)`; (2) `WaveController` ждёт `corpses_absorbed`; (3) **только после** этого начинается обычный `skill_offer`-flow (если есть offer на финальной волне) и `_advance_wave` → `level_completed`.
- **AC-6 (input lock).** На время absorption-ритуала игрок не может двигаться/кастовать/паузить. Реализовать через `WaveController._is_transitioning = true` на старте ритуала + clear на `corpses_absorbed`. Owners (`godmode_controller._unhandled_input`) уже читают `wave_controller.is_transitioning()`.
- **AC-7 (fixed duration).** `absorption_total_sec` уважается с точностью ≤ 1 кадр на любом числе корпсов. Полная анимация (включая последний прибывший) укладывается в `total_sec` ровно. Нужна для будущего звуко-наложения (`AudioDirector.play_sfx("absorption_ritual", heroine_pos)` с длительностью ≈ `total_sec`).
- **AC-8 (Bezier feel).** Каждый корпс летит по Безье (slow-fast-slow), с per-corpse jitter старта (`±absorption_per_corpse_jitter_sec`) и скорости (`speed_factor ∈ [1-x, 1+x]`). Веер траекторий (perpendicular-offset со случайным знаком). Корпсы уменьшаются по ходу полёта (linear scale до `absorption_corpse_shrink_to`) и пульсируют через flash.gdshader (`absorption_blink_*` — частота заметно выше, чем у death-blink, чтобы визуально отличался).
- **AC-9 (heroine reaction).** Героиня пульсирует через flash на каждый период (`absorption_heroine_pulse_count` равных интервалов в течение `total_sec`). Цвет flash = `lerp(WHITE, biome_tint, absorption_heroine_tint_mix)` где `biome_tint` — цвет доминирующего `tile_kind` арены (см. D-3, plan §"Biome aspect"), `absorption_heroine_tint_mix ∈ [0,1]` (config-key, дефолт 0.5 — половина от чистого biome). На каждое «прибытие» корпса — scale-punch до `absorption_heroine_scale_punch` и обратно (~80мс, через Tween).
- **AC-9b (no biome → neutral).** Если арена не содержит ни одного walkable тайла **или** доминирующий kind = `&""` / неизвестен — `biome_tint = WHITE`, эффективный flash остаётся нейтральным. AC не блокируется.
- **AC-10 (screen shake).** На старте absorption камера получает монотонный `shake(absorption_screen_shake_amp_px, absorption_screen_shake_freq, absorption_total_sec)` — фоновый, угасает к нулю. Дополнительно: на каждое `corpse.absorbed_arrived` — мини-burst `shake(absorption_arrival_shake_amp_px, absorption_arrival_shake_freq, absorption_arrival_shake_sec)` (низкая амплитуда, короткая длительность, ~0.12с). Burst-shake накладывается аддитивно на фоновый через тот же `offset` канал — оба активны параллельно, реализация в `GodmodeCamera.shake()` поддерживает совмещение (см. plan.md).
- **AC-11 (particles).** Над героиней спавнится `GPUParticles2D` (`amount=64`, lifetime ≈ `total_sec`) на старте absorption. `modulate = lerp(UiTheme.ABSORPTION_PARTICLE_COLOR, biome_tint, absorption_particle_tint_mix)` (config-key, дефолт 0.65 — biome-tint доминирует). Удаляется (`queue_free`) через `total_sec + 0.5` для естественного fadeout.
- **AC-12 (no corpses → empty ritual).** Если на финальной волне корпсов нет — `play_absorption_ritual` всё равно играет heroine-side эффекты (pulse + particles + shake) полную длительность `absorption_total_sec`, без полёта корпсов. `corpses_absorbing_started(0, total_sec)` эмитится в начале, `corpses_absorbed` — после `total_sec`. Звук кладётся одинаково в оба варианта.
- **AC-13 (GameSpeed).** Все длительности и амплитуды читаются через `GameSpeed.get_value("fx", "...")`. F5 (live reload) применяется к **следующей** death-/absorption-итерации; уже играющие tween'ы доигрывают со старыми значениями. Никаких bare `create_timer(N)`.
- **AC-14 (touch budget).** Изменения вне новых файлов:
  - `scripts/runtime/wave_controller.gd` — ≤8 строк (сигнатуры + 1 await + 1 helper).
  - `scripts/infrastructure/event_bus.gd` — 3 новых signal.
  - `scripts/presentation/godmode/godmode_controller.gd` — 0 строк (убран `actor.queue_free()` НЕ трогаем — корпс это **отдельный** узел, актёр queue_free'ится как раньше).
  - `scripts/presentation/godmode/godmode_camera.gd` — ≤25 строк (метод `shake()` + два-канала аккумулятор + per-frame offset apply).
  - `scripts/runtime/actor_registry.gd` — 1 строка (`add_to_group(&"actor_registry")`).
  - `project.godot` — 1 строка autoload.
  - `config/game_speed.cfg` — раздел `[fx]` пополняется (см. §7 plan.md).
  - `scripts/presentation/ui_theme.gd` — 2 константы (`ABSORPTION_PARTICLE_COLOR`, `BIOME_TINTS` Dictionary).
- **AC-15 (corpse inertia / indestructibility).** Корпс — только presentation-узел под `grid/Corpses`. Не присутствует в `ActorRegistry`, не лежит в `HexGrid._tiles[*].actor_id`, не реагирует на ввод/коллизии/area2d. Следствия (тестируем):
  - Pathfinder через гекс с корпсом проходит как через пустой (move_cost не меняется).
  - AOE-спеллы / тайл-эффекты (lava `damage_zone`, ice slow, и т.п.) не могут «убить» / удалить / повредить корпс — он не принадлежит damage-системе.
  - Wave-transition (`_apply_wave_snapshot`) **не очищает** корпсы — снапшот меняет floor/objects/spawners, но Corpses-узел отдельный.
  - Ability targeting (single-target, AOE-pick, line) не предлагает корпс как цель и не считает его за occupant'а.
  - Корпс исчезает только через (a) `play_absorption` → `dispose`, (b) `clear_all` (ресет). Других путей нет.

## Resolved decisions (clarify-round 1, Egor)

- **D-1 (skill_offer ordering on final wave).** Absorption играется **первым** до конца, потом skill_offer / level-completion-диалог. Соответствует AC-5.
- **D-2 (camera shake).** План — монотонный shake на всю длительность ритуала **+** мини-burst-shake на каждое прибытие корпса (короткий, низкая амплитуда, см. plan.md). Оба вкладываются в `offset` через тот же канал — мини-burst складывается с монотонным фоном.
- **D-3 (heroine pulse colour).** Нейтральный белый flash **+** biome-aspect tint текущей арены: считаем доминирующий `tile_kind` по всем walkable-гексам через `grid.get_all_walkable_coords()` + `grid.get_tile_kind(coord)`, мапим на цвет (см. plan.md §"Biome aspect"). Tint применяется к partics и к flash heroine, корпсы остаются в нейтральном flash. Дёшево — один проход за O(N) гексов в начале ритуала.
- **D-4 (no-corpses → empty ritual).** AC-12 переписан: если `has_corpses() == false`, ритуал всё равно играется с heroine-side эффектами (pulse + particles + shake), без полёта корпсов, **полная длительность `absorption_total_sec` соблюдается** (для звука).
- **D-5 (corpse inertia / indestructibility).** Корпсы **полностью инертны**: не блокируют движение, не таргетятся, не отсасывают AOE/DOT/тайл-эффекты, не разрушаются ничем. Единственная причина исчезновения — absorption (на финальной волне) или `clear_all()` (ресет/выход). Ни один спелл / тайл-эффект / wave-transition не может убрать корпс с арены раньше времени. См. AC-15.

## Open questions (deferred / non-blocking)

- **OQ-2 (corpse persistence через map_editor playtest reset).** Если playtest перезапускает уровень — корпсы должны очищаться. Сейчас `clear_all()` цепляется на `EventBus.scene_ready`/`run_started`/`battle_started`. Editor-playtest может не эмитить часть этих сигналов. Audit на T019, тогда же фиксим если что.

## Зависимости

- 024 (WaveController) — точка прерывания в `_check_auto_clear`. Изменения минимальные, без breaking-API.
- 040 (SkillOfferController) — order-dependency только. Не правим этот файл.
- 047 (FxDirector / flash.gdshader) — переиспользуем shader, без правок registry.
- 029-feedback-polish — закрывает пункт «Death animation manekin'ов» из его catalog (line 24). После мержа 048 этот пункт в 029 cancel'ится.

## Out of scope

- Per-enemy corpse-sprite (отдельная художественная задача, на Катю).
- Звуковая часть (death-thud, absorption-whoosh, heroine-pulse) — оставляем callsite-слот, контент — audio-pass.
- Death анимации **игрока** (game-over flow — отдельный спек).
- Resurrection / corpse-revival механики.
- Corpse blocking / aura / interactability (см. Scope-граница, корпсы — косметика).
- Mood-tint партиклов / pulse'а героини (см. OQ-4).
- Web-build performance audit для GPUParticles2D (на десктопе нет вопросов; web — отдельный пас если будем web-buildить).
