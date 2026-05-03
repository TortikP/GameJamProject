# 048-corpse-absorption — tasks

Зависимости — линейные, в указанном порядке. Параллелить можно T003 ↔ T004, T009 ↔ T010.

## Phase A — Death ritual

- [ ] **T001** — `scripts/infrastructure/event_bus.gd`: добавить 3 сигнала (`actor_corpse_spawned`, `corpses_absorbing_started`, `corpses_absorbed`) в новой секции `# 048-corpse-absorption`. Проверка: проект компилируется, `EventBus.corpses_absorbed` доступен из любого скрипта.
- [ ] **T002** — `scripts/runtime/actor_registry.gd`: в `_ready()` добавить `add_to_group(&"actor_registry")`. Это даёт CorpseManager способ найти registry без injection. Проверка: в godmode F1-spawn маникена → `get_tree().get_first_node_in_group(&"actor_registry")` возвращает узел.
- [ ] **T003** — `config/game_speed.cfg`: добавить новые ключи в `[fx]` (см. spec §7). Не трогать существующие. Проверка: F5 в godmode reload'ит конфиг без ошибок.
- [ ] **T004** — `scenes/runtime/corpse.tscn`: создать сцену (Corpse Node2D + Body Sprite2D с дефолтным материалом=ShaderMaterial(flash.gdshader) + закомментированный slot для Particle).
- [ ] **T005** — `scripts/presentation/corpse.gd`: реализовать `init`, `play_death`, `play_absorption`, `dispose` per spec §2 + plan §"Bezier math". Включая защитные проверки (texture == null → no-op + warn). Включая константу `BEZIER_PERP_FACTOR` из GameSpeed.
- [ ] **T006** — `scripts/runtime/corpse_manager.gd`: реализовать autoload per plan §"CorpseManager". Логика:
  - `_ready()` — connect EventBus сигналов.
  - `_on_actor_died(id)` — фильтр игрока, snapshot, spawn, mount, `play_death()` fire-and-forget, `_alive.append`.
  - `play_absorption_ritual(target_provider)` — корутина: emit `corpses_absorbing_started`, lock через `_ritual_running=true`, parallel `play_absorption` на все корпсы, await all, emit `corpses_absorbed`, dispose все, clear `_alive`. Sentinel: пустой `_alive` → emit started+absorbed в одном фрейме.
  - `clear_all()` — фор-каждый dispose, `_alive.clear()`.
- [ ] **T007** — `project.godot`: зарегистрировать `CorpseManager` autoload-ом сразу после `EventBus`. Проверка: глобальный доступ `CorpseManager.has_corpses()` из любого скрипта без preload.
- [ ] **T008** — Smoke godmode F1: spawn маникен → убить (любым скиллом) → убедиться что (1) HP-бар исчезает мгновенно при HP=0, (2) тушка прыгает/мигает/уменьшается/заваливается, (3) после анимации лежит на гексе и pathfinder через неё ходит. Игрок может закастовать через корпс свободно.

## Phase B — Absorption ritual

- [ ] **T009** — `scripts/presentation/godmode/godmode_camera.gd`: добавить `shake(amp, freq, duration)` + per-frame `offset` apply per plan. Не ломать существующие follow / zoom / pan тесты. Smoke: вызвать `camera.shake(8, 22, 1.0)` из debug консоли — камера дёргается секунду, возвращается в ноль.
- [ ] **T010** — `scripts/presentation/ui_theme.gd`: добавить `const ABSORPTION_PARTICLE_COLOR := Color(0.85, 0.95, 1.0, 0.9)` в палитру. Проверка: ничто другое не стало розовым.
- [ ] **T011** — `corpse_manager.gd`: дополнить `play_absorption_ritual` heroine-side эффектами:
  - 1× `camera.shake(amp, freq, total_sec)` найдя камеру через `get_tree().get_first_node_in_group(&"main_camera")` (T012 добавит группу).
  - 1× `GPUParticles2D` спавн над heroine, `texture` = простой круг (assets reuse, см. T013), `amount=64`, `lifetime=total_sec`, `process_material` базовый. После `total_sec + 0.5` — `queue_free`.
  - Параллельно: heroine flash-pulse Tween — `absorption_heroine_pulse_count` равных периодов через flash.gdshader (применяем материал к heroine.Body или создаём временный).
  - На каждое `corpse.absorbed_arrived` — heroine scale-punch до `absorption_heroine_scale_punch` и обратно за ~80мс через Tween.
- [ ] **T012** — `scripts/presentation/godmode/godmode_camera.gd`: в `_ready()` `add_to_group(&"main_camera")`. (Та же группа-паттерн что T002 для registry.)
- [ ] **T013** — partice texture: проверить если в `assets/sprites/` уже есть круглый glow-спрайт (8–16px) — переиспользовать. Если нет — простой `assets/sprites/fx/particle_dot.png` 16×16 от Кати или dev-placeholder через `ImageTexture` build. **Защита от R3 (no asset):** если ничего нет → `GPUParticles2D` без texture (квадратный default Godot — норм для джема).
- [ ] **T014** — `scripts/runtime/wave_controller.gd`: добавить `_is_final_wave(idx)` helper + 5-строчный await-блок per plan §"WaveController diff". Проверка: ≤ 8 строк изменений всего.
- [ ] **T015** — Smoke на финальной волне: загрузить sample-уровень с 1-2 волнами, в последней волне 3 моба → убить всех → дождаться `wave_cleared`. Ожидаемое: (1) все 3 трупа лежат на арене → (2) absorption ритуал стартует (started signal в логе) → (3) все 3 летят к героине по разным траекториям → (4) на каждое прибытие heroine punch'ает scale, partlcles burst → (5) shake камеры всё это время → (6) после `total_sec` — `corpses_absorbed` signal → (7) если у волны skill_offer — открывается модалка (в правильной последовательности per AC-5) → (8) `level_completed` после закрытия модалки.

## Phase C — Robustness

- [ ] **T016** — Edge: финальная волна без мобов (только тайл-эффекты убили предпоследнего) — `has_corpses()=false`, ритуал no-op'ит, `corpses_absorbed` всё равно эмитится в том же фрейме, level_completed не виснет. AC-12.
- [ ] **T017** — Edge: игрок умирает в финальной волне раньше последнего врага. Сейчас → game-over flow. Проверить что CorpseManager не пытается ритуал стартовать (wave_cleared не эмитится, мы не доходим до нашего кода). AC-4.
- [ ] **T018** — Edge: ресет F2 в godmode после нескольких смертей — корпсы пропадают, `_alive` clear, никаких leak'ов в дереве сцены. AC-3.
- [ ] **T019** — Edge: переход между уровнями в ActiveGame (CampaignController). На `scene_ready` — `clear_all()` срабатывает. AC-3.
- [ ] **T020** — Edge: `Body` texture = null (плохо сконфигурированный enemy_data_id) — корпс не спавнится, warn-once в лог, no crash. R4.
- [ ] **T021** — Edge: Bezier математика на 50 рандомных корпсах с jitter — все `t==1` наступают в окне `[0, absorption_total_sec]` ± 1 кадр. Plan §"Fixed-duration guarantee". Print-debug в одном из smoke runs.
- [ ] **T022** — F5 live-reload во время лежащих трупов → следующий death использует новые длительности, текущие лежащие — не трогать. AC-13.

## Phase D — Polish & docs

- [ ] **T023** — `HANDOFF.md`: добавить секцию `## 22. 048-corpse-absorption — точки интеграции` со статусом ветки, что введено, точки интеграции с 040 (skill_offer ordering) и 029 (death-animation cancel из catalog'а).
- [ ] **T024** — `CLAUDE.md` ownership table: добавить строку `048-corpse-absorption (CorpseManager autoload, Corpse scene, WaveController final-wave hook) | Egor`.
- [ ] **T025** — Self-review diff: убедиться что **AC-14 touch budget** соблюдён (≤8 строк wave_controller, ≤15 godmode_camera, 0 godmode_controller, 1 project.godot, 1 ui_theme).

## Open questions (gate перед T011 / T015)

Перед началом Phase B — Egor подтверждает (или правит) **OQ-1, OQ-3, OQ-4, OQ-5** в spec.md. OQ-2 решается на T019.

## Cut list (если время поджимает)

В порядке агрессивного отрезания:
1. **T010, T011 partial** — heroine pulse + scale-punch отдельно от particles. Если шейдеры героини по какой-то причине не привязываются (heroine — отдельный actor, тот же sprite-pattern должен работать; если нет — режем пульс).
2. **T011 particles полностью** — без партиклов. Тогда AC-11 cut, остаётся shake + heroine pulse.
3. **T012 + T009 shake полностью** — без shake. AC-10 cut, остаётся flight + heroine pulse + particles.
4. **Bezier → linear interpolation** — cubic заменяется на `lerp(P0, P3, t)` с easing curve. AC-8 «Bezier feel» cut, fly остаётся прямолинейным с slow-fast-slow ease.
5. **Phase C edge cases** — урезаем до T016 (no-corpses) и T018 (reset). T017 + T020 — defer на 029-feedback-polish если не дойдут руки.

Минимальный shippable scope: T001–T008 + T014 + T015 + T016 + T018. Это death + absorption flight без heroine FX и shake — но контракт с WaveController закрыт, можно дополнить later без breaking.
