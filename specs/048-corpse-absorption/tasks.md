# 048-corpse-absorption — tasks

Зависимости — линейные, в указанном порядке. Параллелить можно T003 ↔ T004, T009 ↔ T010.
Decisions D-1..D-5 фиксированы, OQ-2 решается на T019 (non-blocking).

## Phase A — Death ritual

- [x] **T001** — `scripts/infrastructure/event_bus.gd`: добавить 3 сигнала (`actor_corpse_spawned`, `corpses_absorbing_started`, `corpses_absorbed`) в новой секции `# 048-corpse-absorption`. Проверка: проект компилируется, `EventBus.corpses_absorbed` доступен из любого скрипта.
- [x] **T002** — `scripts/runtime/actor_registry.gd`: в `_ready()` добавить `add_to_group(&"actor_registry")`. Это даёт CorpseManager способ найти registry без injection. Проверка: в godmode F1-spawn маникена → `get_tree().get_first_node_in_group(&"actor_registry")` возвращает узел.
- [x] **T003** — `config/game_speed.cfg`: добавить новые ключи в `[fx]` (см. spec §7, включая mini-burst `absorption_arrival_shake_*`, biome mix-ratio `absorption_heroine_tint_mix` / `absorption_particle_tint_mix`, `absorption_particle_amount`). Не трогать существующие. Проверка: F5 в godmode reload'ит конфиг без ошибок.
- [x] **T004** — `scenes/runtime/corpse.tscn`: создать сцену (Corpse Node2D + Body Sprite2D с дефолтным материалом=ShaderMaterial(flash.gdshader) + закомментированный slot для Particle).
- [x] **T005** — `scripts/presentation/corpse.gd`: реализовать `init`, `play_death`, `play_absorption`, `dispose` per spec §2 + plan §"Bezier math". Включая защитные проверки (texture == null → no-op + warn). Включая константу `BEZIER_PERP_FACTOR` из GameSpeed.
- [x] **T006** — `scripts/runtime/corpse_manager.gd`: реализовать autoload per plan §"CorpseManager". Логика:
  - `_ready()` — connect EventBus сигналов.
  - `_on_actor_died(id)` — фильтр игрока, snapshot из registry до cleanup, spawn под `grid/Corpses` (sibling от `Actors`!), mount, `play_death()` fire-and-forget, `_alive.append`.
  - `play_absorption_ritual(target_provider, grid)` — корутина: emit `corpses_absorbing_started(_alive.size(), total_sec)`, разрешить biome-tint (см. plan §"Biome aspect"), spawn heroine particles + heroine pulse loop + monotonic camera shake, parallel `play_absorption` на все корпсы (jitter старт + speed_factor). Connect `absorbed_arrived` корпсов на per-arrival mini-burst shake + heroine scale-punch. Await `total_sec` (а НЕ all corpses finished — фикс. длительность даже если один корпс по jitter'у припоздает на 0.01с — всё равно держим контракт). Emit `corpses_absorbed`. Dispose все, clear `_alive`. **Sentinel D-4:** пустой `_alive` → всё равно играем heroine-side эффекты `total_sec`, в конце эмитим `corpses_absorbed`.
  - `clear_all()` — фор-каждый dispose, `_alive.clear()`.
  - `_resolve_biome_tint(grid)` — per plan, count `tile_kind` через `grid.get_all_walkable_coords()` + `grid.get_tile_kind(coord)`, top-1 → `UiTheme.biome_tint_for(kind)`.
- [x] **T007** — `project.godot`: зарегистрировать `CorpseManager` autoload-ом сразу после `EventBus`. Проверка: глобальный доступ `CorpseManager.has_corpses()` из любого скрипта без preload.
- [ ] **T008** — Smoke godmode F1: spawn маникен → убить (любым скиллом) → убедиться что (1) HP-бар исчезает мгновенно при HP=0, (2) тушка прыгает/мигает/уменьшается/заваливается, (3) после анимации лежит на гексе и pathfinder через неё ходит, (4) **спеллы не могут её уничтожить** — кастуем AOE на гекс с корпсом, корпс остаётся (D-5).

## Phase B — Absorption ritual

- [x] **T009** — `scripts/presentation/godmode/godmode_camera.gd`: добавить `shake(amp, freq, duration)` с **multi-layer аддитивным** аккумулятором (`_shake_layers` array). Per-frame `_process` суммирует все активные слои → `offset`. Истёкшие слои удаляются. Не ломать существующие follow / zoom / pan тесты. Smoke: вызвать `camera.shake(8, 22, 1.0)` и сразу `camera.shake(3, 30, 0.15)` ×3 — оба эффекта складываются, через 1с фоновый затух, через 0.15с burst-ы тоже. ≤25 строк суммарно.
- [x] **T010** — `scripts/presentation/ui_theme.gd`: добавить
  - `const ABSORPTION_PARTICLE_COLOR := Color(0.85, 0.95, 1.0, 0.9)` (нейтральный fallback).
  - `const BIOME_TINTS: Dictionary = { &"forest": Color(0.55,0.85,0.45), &"heaven": Color(0.85,0.92,1.00), &"lava": Color(1.00,0.45,0.20), &"ice": Color(0.55,0.80,1.00) }`.
  - `static func biome_tint_for(kind: StringName) -> Color: return BIOME_TINTS.get(kind, Color.WHITE)`.
  Проверка: ничто другое не стало розовым.
- [x] **T011** — `corpse_manager.gd`: дополнить `play_absorption_ritual` heroine-side эффектами:
  - 1× monotonic `camera.shake(absorption_screen_shake_amp_px, absorption_screen_shake_freq, absorption_total_sec)` найдя камеру через `get_tree().get_first_node_in_group(&"main_camera")`.
  - **Per-arrival burst:** на каждый `corpse.absorbed_arrived` сигнал — `camera.shake(absorption_arrival_shake_amp_px, absorption_arrival_shake_freq, absorption_arrival_shake_sec)` + heroine scale-punch.
  - 1× `GPUParticles2D` спавн над heroine, `texture` per T013, `amount=absorption_particle_amount`, `lifetime=absorption_total_sec`, `modulate = lerp(UiTheme.ABSORPTION_PARTICLE_COLOR, biome_tint, absorption_particle_tint_mix)`. После `total_sec + 0.5` — `queue_free`.
  - heroine flash-pulse Tween: `absorption_heroine_pulse_count` периодов через flash.gdshader, цвет `flash_color = lerp(WHITE, biome_tint, absorption_heroine_tint_mix)`. Применяем материал к `heroine.Body` (heroine == `registry.get_actor(&"player")`).
- [x] **T012** — `scripts/presentation/godmode/godmode_camera.gd`: в `_ready()` `add_to_group(&"main_camera")`. (Та же группа-паттерн что T002 для registry.)
- [x] **T013** — partice texture: проверить если в `assets/sprites/` уже есть круглый glow-спрайт (8–16px) — переиспользовать. Если нет — простой `assets/sprites/fx/particle_dot.png` 16×16 от Кати или dev-placeholder через `ImageTexture` build. **Защита от R3 (no asset):** если ничего нет → `GPUParticles2D` без texture (квадратный default Godot — норм для джема).
- [x] **T014** — `scripts/runtime/wave_controller.gd`: добавить `_is_final_wave(idx)` helper + 7-строчный await-блок per plan §"WaveController diff". Проверка: ≤ 8 строк изменений всего, передан `grid` в `play_absorption_ritual`.
- [ ] **T015** — Smoke на финальной волне: загрузить sample-уровень с 1-2 волнами, в последней волне 3 моба → убить всех → дождаться `wave_cleared`. Ожидаемое: (1) все 3 трупа лежат на арене → (2) absorption ритуал стартует (started signal в логе) → (3) все 3 летят к героине по разным траекториям → (4) на каждое прибытие heroine punch'ает scale + мини-burst shake → (5) фоновый shake камеры всё это время → (6) после **ровно `total_sec`** — `corpses_absorbed` signal → (7) если у волны skill_offer — открывается модалка (после absorption per AC-5) → (8) `level_completed` после закрытия модалки.

## Phase C — Robustness

- [ ] **T016** — Edge: финальная волна без мобов (только тайл-эффекты убили предпоследнего) — `has_corpses()=false`, **ритуал ВСЁ РАВНО играется** (heroine pulse + particles + shake) полную длительность, `corpses_absorbed` эмитится через `total_sec`, level_completed не виснет. AC-12 / D-4.
- [ ] **T017** — Edge: игрок умирает в финальной волне раньше последнего врага. Сейчас → game-over flow. Проверить что CorpseManager не пытается ритуал стартовать (wave_cleared не эмитится, мы не доходим до нашего кода). AC-4.
- [ ] **T018** — Edge: ресет F2 в godmode после нескольких смертей — корпсы пропадают, `_alive` clear, никаких leak'ов в дереве сцены. AC-3.
- [ ] **T019** — Edge: переход между уровнями в ActiveGame (CampaignController). На `scene_ready` — `clear_all()` срабатывает. Editor playtest reset (OQ-2): проверить что и здесь чисто; если нет — добавить hook на соответствующий editor signal. AC-3.
- [ ] **T020** — Edge: `Body` texture = null (плохо сконфигурированный enemy_data_id) — корпс не спавнится, warn-once в лог, no crash. R4.
- [ ] **T021** — Edge: Bezier математика на 50 рандомных корпсах с jitter — все `t==1` наступают в окне `[0, absorption_total_sec]` ± 1 кадр. Plan §"Fixed-duration guarantee". Print-debug в одном из smoke runs.
- [x] **T021b** — **Inertia инварианты (D-5).** Сценарии:
  1. Спавн корпса → `registry.has_actor(&"<id>_corpse") == false`. ✓ (нет регистрации).
  2. Спавн корпса → `grid.get_actor_at(coord) != &"<id>_corpse"`. ✓ (нет в grid'е).
  3. Кастуем AOE-fire на гекс с корпсом — корпс остаётся, флешка/визуал AOE НАД корпсом по Z-order. ✓
  4. Wave 1 → 2 transition с 5 корпсами от wave 1 — все 5 продолжают лежать в wave 2 без визуальных скачков. ✓
  5. Pathfinder: `grid.find_path(A, B)` через гекс с корпсом — путь не блокирован. ✓
- [ ] **T022** — F5 live-reload во время лежащих трупов → следующий death использует новые длительности, текущие лежащие — не трогать. AC-13.
- [ ] **T023** — Biome-tint smoke: загрузить 4 разных уровня с доминирующими kind'ами (forest / heaven / lava / ice) — heroine pulse и particles в каждом случае подкрашены соответствующим цветом. Чисто-grass arena → green tint. Mixed (например 5 lava / 3 forest) → lava tint (доминирует). Empty / no walkable → WHITE fallback. AC-9 / AC-9b.

## Phase D — Polish & docs

- [x] **T024** — `HANDOFF.md`: добавить секцию `## 22. 048-corpse-absorption — точки интеграции` со статусом ветки, что введено, точки интеграции с 040 (skill_offer ordering) и 029 (death-animation cancel из catalog'а).
- [x] **T025** — `CLAUDE.md` ownership table: добавить строку `048-corpse-absorption (CorpseManager autoload, Corpse scene, WaveController final-wave hook) | Egor`.
- [x] **T026** — Self-review diff: убедиться что **AC-14 touch budget** соблюдён (≤8 строк wave_controller, ≤25 godmode_camera, 0 godmode_controller, 1 actor_registry, 1 project.godot, 2 константы + helper в ui_theme).

## Cut list (если время поджимает)

В порядке агрессивного отрезания:
1. **T023 biome-tint** → нейтральный белый везде. AC-9 cut в части biome, AC-9b остаётся (defaults fall through).
2. **T011 partial — particles** — без партиклов. Тогда AC-11 cut, остаётся shake + heroine pulse.
3. **Per-arrival burst (T011 partial)** — оставить только monotonic shake. AC-10 упрощается.
4. **T012 + T009 shake полностью** — без shake. AC-10 cut, остаётся flight + heroine pulse + particles.
5. **Bezier → linear interpolation** — cubic заменяется на `lerp(P0, P3, t)` с easing curve. AC-8 «Bezier feel» cut.

Минимальный shippable scope: T001–T008 + T014 + T015 + T016 + T018 + T021b. Death + absorption flight + heroine input lock + inertia инвариант — без heroine FX / shake / particles / biome.
