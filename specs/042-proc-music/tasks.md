# 042-proc-music — tasks

См. `spec.md` (acceptance) и `plan.md` (HOW). Tasks — что делать в порядке зависимостей. `[P1]` = блокирующее, `[P2]` = желательно, `[P3]` = nice-to-have. `[P]` = можно параллельно с предыдущим. `(depends T0XX)` = блокирующая зависимость.

## Phase 1 — Synth foundation (audio чтобы вообще зазвучало)

- [ ] T001 [P1] `scripts/audio/music/synth/wavetables.gd` — static. PackedFloat32Array размера 256: sine = sin(2π·i/256), triangle = ramp+fold, square = sign-based. Геттеры `sine(phase01)/triangle/square` с nearest-neighbor lookup. Linear interp оставить на T-POLISH.
- [ ] T002 [P1] `scripts/audio/music/synth/adsr.gd` — class_name ADSR. Поля: attack_samples, decay_samples, sustain_level, release_samples + state (Idle/Attack/Decay/Sustain/Release/Done) + sample-counter. `tick() -> float` возвращает текущий envelope, `gate_off()` уходит в Release, `is_finished() -> bool`. (no deps)
- [ ] T003 [P1] `scripts/audio/music/synth/voice_pool.gd` — class_name VoicePool. Внутри `_voices: Array[Voice]` фиксированно 6 штук, прероллокированы. `note_on(osc, freq, adsr_params, gain, layer) -> int` (берёт неактивный или steal'ит самый старый), `release(id)`, `release_all_layer(layer)`, `mix(buf, n)`. Voice — внутренний RefCounted; поля: active, osc, freq, phase, phase_inc, adsr, gain, layer. (depends T001, T002)
- [ ] T004 [P1] `scripts/audio/music/state_mixer.gd` — class_name StateMixer. `set_state(name)` ставит target gains для слоёв (`bass/pad/lead/drums`) — словарь по state. `tick_bar()` шагает текущие gain'ы к target по 1/N бар (default N=1 — т.е. за бар приходит). `get_layer_gain(layer) -> float` — VoicePool вызывает per-voice. (no deps)
- [ ] T005 [P1] `scripts/audio/music/conductor.gd` — class_name Conductor. `reset(bpm, seed)`, `advance(n) -> Array[(StringName, int)]`. Sample-counting clock из plan.md. Без allocations в hot path (events Array — переиспользуется или возвращает фиксированной длины). (no deps)

Smoke после Phase 1: создать в Main `_ready` MusicDirector-stub без EventBus, нажать кнопку → услышать sine на 440 Hz через VoicePool. Если щёлкает — починить ADSR ramp.

## Phase 2 — Harmony + generators (чтобы звучало как музыка, не как тест-тон)

- [ ] T006 [P1] `scripts/audio/music/harmony.gd` — class_name Harmony. Const PROGRESSION_AM (4 шт. (root, intervals)), SCALE_MINOR. `reset(seed)`. `tick_bar(bar_idx)` → меняет current_chord. `get_chord_tones(octave_offset) -> Array[int]`, `get_scale_tones(octave_offset) -> Array[int]`. `midi_to_freq(midi) -> float`. (no deps)
- [ ] T007 [P1] `scripts/audio/music/generators/bass_gen.gd` — class_name BassGen. `tick(events, harmony, voice_pool)`: на beat % 4 == 0 → note_on(triangle, root_midi=root-12, ADSR(20ms, 100ms, 0.6, 200ms), gain 0.5, layer "bass"). На beat % 4 == 2 → fifth (root+7-12). (depends T003, T006)
- [ ] T008 [P1] `scripts/audio/music/generators/pad_gen.gd` — class_name PadGen. На bar event → release prev voices, note_on на 3-й и 5-й ступенях аккорда (sine, slow ADSR 400ms attack, sustain 0.5, release 600ms), gain 0.25, layer "pad". (depends T003, T006)
- [ ] T009 [P1] `scripts/audio/music/generators/lead_gen.gd` — class_name LeadGen. На beat (1/4 grid; в P3 расширить до 1/8) с RNG-вероятностью (calm 0.3, battle 0.7) → выбираем ноту: на сильной доле (beat%2==0) chord_tone, на слабой scale tone. Octave +12 от bass. ADSR (10ms, 80ms, 0.4, 150ms). gain 0.35, layer "lead". RNG-инстанс передаётся снаружи (sharing с MusicDirector._rng). (depends T003, T006)
- [ ] T010 [P1] `scripts/audio/music/generators/drums_gen.gd` — class_name DrumsGen. Kick: на beat 1,3 → note_on(sine, 60Hz hard-coded, ADSR(2ms, 80ms, 0.0, 0ms), gain 0.7, layer "drums"). Hat: на beat 2,4 + offbeat (8th notes) → note_on(noise, 0Hz, ADSR(1ms, 30ms, 0.0, 0ms), gain 0.2, layer "drums"). Noise sample = `_rng.randf_range(-1,1)` per-sample (через VoicePool noise mode). (depends T003)

Smoke после Phase 2: вручную инстанцировать всё в test scene без EventBus, прокачать `_render_chunk` 22050×30 раз, услышать 30 секунд музыки на calm. Должно звучать как «спокойная атмосферка», не как шум.

## Phase 3 — MusicDirector + EventBus integration

- [ ] T011 [P1] `scripts/audio/music/music_director.gd` skeleton — autoload extends Node. `_ready`: создаёт AudioStreamPlayer + AudioStreamGenerator, подписывается на 7 EventBus сигналов (level_loaded, wave_started, wave_cleared, level_completed, run_ended, main_menu_entered, run_started_requested). Owns _conductor, _harmony, _voice_pool, _state_mixer, _generators[], _rng, _sting_player. (depends T003-T010)
- [ ] T012 [P1] `_render_chunk(n)` + `_process` — push-loop из plan.md. Собирает events от Conductor → раздаёт в каждый generator (bar events → harmony.tick_bar, pad_gen, state_mixer.tick_bar; beat events → bass_gen, lead_gen, drums_gen). VoicePool.mix → push_buffer. (depends T011)
- [ ] T013 [P1] `_on_level_loaded(level)` — read music_config, derive defaults, conductor.reset, harmony.reset, voice_pool.reset, state_mixer.set_state(base_state). Re-seed _rng. (depends T011)
- [ ] T014 [P1] `_on_wave_started` / `_on_wave_cleared` — set_state, при cleared — play_sting("wave_clear"). Pending state на bar boundary. (depends T011, T015)
- [ ] T015 [P1] `_on_level_completed(score)` — play_sting("victory"), schedule stop after 2s (Timer). (depends T011, T017)
- [ ] T016 [P1] `_on_run_ended(reason)` — play_sting("victory") if reason=="victory" else "defeat", stop after sting. (depends T011, T017)
- [ ] T017 [P1] `_on_main_menu_entered` — load `data/music/main_menu.json`, conductor.reset с этими параметрами, set_state(menu_base_state). Fade-in. `_on_run_started_requested` → fade-out (флаг `_loading_level=true`). На `_on_level_loaded` снимается. (depends T011)
- [ ] T018 [P2] `_on_dialogue_started` / `_on_dialogue_finished` — duck −6 dB. (depends T011) — может быть вырезано в P3 cut.
- [ ] T019 [P1] `project.godot` — добавить autoload `MusicDirector` после `EventBus`. (depends T011)

Smoke после Phase 3: запуск Main → меню звучит. Старт кампании → меню затухает, уровень звучит. Волна стартует → battle. Волна зачищена → ноль стинга пока (Phase 4) + calm. Уровень пройден → пока ничего. Ок.

## Phase 4 — Stings (replaceable)

- [ ] T020 [P1] `data/music/stings.json` — дефолтный mapping wave_clear/victory/defeat/pickup на procedural presets. (no deps)
- [ ] T021 [P1] `scripts/audio/music/stings/proc_stings.gd` — static. Функции `dispatch_blip_up(voice_pool, harmony)`, `dispatch_fanfare(...)`, `dispatch_descending(...)`, `dispatch_ping(...)`. Каждая накидывает 1-4 voice'а с задержками через ADSR delay (или sequential note_on per beat-counter — proc_stings owns свой mini-conductor). На layer "sting" — отдельно от музыки. (depends T003, T006)
- [ ] T022 [P1] `scripts/audio/music/stings/sting_player.gd` — class_name StingPlayer. Загрузка JSON в `_ready`. `play(name, harmony, voice_pool)`: lookup → branch на kind. Procedural → ProcStings.dispatch_*. Stream → создать одноразовый AudioStreamPlayer с loaded stream, играть, free через `finished` сигнал. `set_overrides(overrides)` — per-level override mapping. (depends T020, T021)
- [ ] T023 [P1] Wire StingPlayer в MusicDirector, expose `play_sting(name)`. Активные procedural-стинги микшируются через тот же VoicePool на layer "sting" (state_mixer держит layer "sting" gain=1.0 всегда, не зависит от calm/battle). (depends T011, T022)
- [ ] T024 [P2] [P] AC-7 manual smoke: вручную поправить `data/music/stings.json` → заменить victory на stream-вариант с любым тестовым WAV (можно временно положить `assets/audio/music/stings/test.wav` и удалить после теста — не коммитить!). Перезапустить — стинг из файла. Откатить JSON. (depends T023)

## Phase 5 — Per-level config + sample

- [ ] T025 [P1] `scripts/core/maps/level_data.gd` — добавить `var music_config: Dictionary = {}`. Обновить `to_dict` (+ключ), `from_dict` (read с `duplicate(true)` если Dictionary). Validate — soft warn если bpm out of range. ≤20 строк инкремент. (no deps)
- [ ] T026 [P1] [P] `data/maps/_schema.md` — секция `music_config` с полным описанием полей (см. spec §3). (depends T025)
- [ ] T027 [P1] `data/maps/sample_music_test.json` — минимальный уровень 5×5, одна волна с 1 enemy, `music_config: {seed: 42, bpm: 110, base_state: "calm", stings: {"victory": "fanfare"}}`. Для smoke загрузки через Main Menu → Load Custom Level. (depends T025)
- [ ] T028 [P1] AC-1 smoke (детерминизм): запустить sample_music_test.json дважды по 30 секунд, в `_render_chunk` накапливать hash буфера в файл, сравнить хеши. Должны совпасть бит-в-бит. Если нет — найти источник недетерминизма (RNG instance не пересоздан, system time used somewhere, etc.). (depends T013, T027)

## Phase 6 — Main menu config

- [ ] T029 [P1] `data/music/main_menu.json` — seed 7777, bpm 72, base_state "calm". (no deps)
- [ ] T030 [P1] AC-6 smoke: главное меню при старте проекта звучит. Старт кампании → плавный fade. Возврат в меню (через pause menu Exit to Menu) → fade обратно. (depends T017, T029)

## Phase 7 — Polish + perf

- [ ] T031 [P1] AC-10 perf check — запустить `sample_music_test.json` ≥5 минут на ноуте Andrey'я. Профайл `_render_chunk` через `Time.get_ticks_usec()`. Цель: < 2 ms средне на chunk, ноль underrun warnings. (depends T028)
- [ ] T032 [P2] Linear interpolation в WaveTables если на низких октавах слышен зерн-артефакт. ~5 строк. (depends T001, T031)
- [ ] T033 [P2] [P] Гладкие frequency changes — при смене chord pad'у release+re-attack, не моментально, чтобы убрать щелчок. (depends T008)
- [ ] T034 [P2] [P] Voice stealing — если все 6 заняты и приходит note_on, steal'ить самый старый в Release-фазе (или с самым низким envelope value). VoicePool. (depends T003)
- [ ] T035 [P2] AC-11 mute test — `AudioServer.set_bus_mute(bus, true)` → молчание мгновенно (Godot сам глушит на уровне bus, но проверить что MusicDirector не keeps doing work без смысла; если CPU держится — bypass `_render_chunk` если bus muted). (depends T012)
- [ ] T036 [P2] [P] HANDOFF.md — секция MusicDirector (см. plan.md «Что трогаем в HANDOFF»). +file tree update. (depends T011)
- [ ] T037 [P3] Linear interp WaveTables — если по T031 не нужно, делаем. (depends T032)
- [ ] T038 [P3] Dialogue ducking AC: `dialogue_started` → −6 dB на музыку, restore на `dialogue_finished`. (depends T018)
- [ ] T039 [P3] AC-12 grep test: `grep -rn "load.*\.ogg\|load.*\.wav" scripts/audio/music/` → попадает только в `sting_player.gd` под `kind == "stream"` веткой. Записать в комментарий теста.

## Phase 9 — Presets resolution

- [ ] T042 [P1] `data/music/presets.json` — 4 пресета: `calm_dungeon`, `tense_arena`, `boss_finale`, `menu_quiet` с цифрами из spec §8. (no deps)
- [ ] T043 [P1] `scripts/audio/music/preset_resolver.gd` — static. `resolve(raw) -> Dictionary`, `list_preset_ids() -> Array`. JSON load с ленивой инициализацией + warn-once на отсутствие файла / unknown preset id. (depends T042)
- [ ] T044 [P1] Wire PresetResolver в `_on_level_loaded` и `_on_main_menu_entered` — раньше `cfg = raw.duplicate(true)`, теперь `cfg = PresetResolver.resolve(raw)`. (depends T013, T017, T043)
- [ ] T045 [P1] AC-14 smoke: создать тест-уровень `data/maps/sample_preset_test.json` с `music_config: {"preset": "boss_finale"}` — звучит как boss_finale. Добавить override `bpm: 80` — bpm = 80, остальное от пресета. Указать невалидный preset id — warn в консоли, дефолтная музыка играет. (depends T044)
- [ ] T046 [P1] Расширить MusicDirector setter API: `set_bpm`, `set_state`, `set_seed`, `set_layer_db(layer, db)`, `set_lead_density(calm, battle)`, `play_sting(name)`. Используются и из `_on_level_loaded`, и из Music Lab. (depends T011)

## Phase 10 — Music Lab

- [ ] T047 [P1] `scenes/dev/music_lab.tscn` — Control + VBox layout по структуре из plan.md «Music Lab — UI structure». Без скрипта (привяжем в T048). (no deps)
- [ ] T048 [P1] `scripts/audio/music/dev/music_lab.gd` — extends Control. `_ready` подгружает MusicDirector, биндит UI events. Helper методы: `_make_slider_row(label, min, max, default, on_change)`, `_apply_params(dict)`, `_gather_current_params() -> Dictionary`. (depends T046, T047)
- [ ] T049 [P1] Music Lab: слайдеры BPM, lead_calm, lead_battle, pad_db, drums_db, master_db. На change — вызов в MusicDirector. (depends T048)
- [ ] T050 [P1] Music Lab: state dropdown (calm/battle/menu) + seed SpinBox + Re-roll button (`_rng.randi() & 0x7fffffff`). (depends T048)
- [ ] T051 [P1] Music Lab: preset dropdown заполняется через `PresetResolver.list_preset_ids()`. «Apply preset» — `_apply_params(PresetResolver.resolve({"preset": id}))`. (depends T043, T048)
- [ ] T052 [P1] Music Lab: A/B слоты в `_slot_a: Dictionary` / `_slot_b: Dictionary` + `_current_slot: StringName`. Save A → snapshot текущих UI значений. Switch A↔B → `_apply_params(_slot_a if current==B else _slot_b)`. (depends T048)
- [ ] T053 [P1] Music Lab: stings flow container. На `_ready` парсит `data/music/stings.json` (через тот же helper, что StingPlayer — вынести `sting_registry.gd` static helper если нужно), генерит кнопку на каждый. Click → `MusicDirector.play_sting(name)`. (depends T022, T048)
- [ ] T054 [P1] Music Lab: «Copy JSON» button — `DisplayServer.clipboard_set(JSON.stringify({"music_config": _gather_current_params()}, "  "))`. Toast «Copied to clipboard» через `EventBus.ui_toast_requested` (есть, проверил). (depends T048)
- [ ] T055 [P1] Music Lab: Stop / Start кнопки → MusicDirector `_stop()` / `_ensure_playing()` (publicize если private). (depends T046, T048)
- [ ] T056 [P1] AC-13 manual smoke: открыть `scenes/dev/music_lab.tscn` через F6 → музыка играет, слайдер BPM сдвигаем вправо → темп слышимо ускоряется, кнопка любого стинга → стинг звучит, Copy JSON → вставляем в новый level.json → запускаем уровень → звучит идентично лабу (с поправкой на стартовое состояние). (depends T049-T055)

## Phase 8 — Final integration + PR

- [ ] T040 [P1] Pass всех AC из spec — особенно AC-1 (детерминизм), AC-9 (минимум touch'ей), AC-10 (perf), AC-13 (Lab), AC-14 (presets). (depends все P1 выше)
- [ ] T041 [P1] Commit + push branch `andrey/proc-music`. Создать PR в staging через URL из push output. (depends T040)

## Cut list (если время кончается, режем в этом порядке)

1. T038 (dialogue ducking) — никто не заметит на джеме.
2. T037 (linear interp) — если T031 не показал артефактов.
3. T034 (voice stealing) — на 6 голосах при наших паттернах не должно происходить вообще.
4. T033 (smooth pad chord change) — если щёлкает только на стыке аккордов и никто не комментит — пофиг.
5. T052 (Music Lab A/B slots) — слайдеры всё равно работают, A/B без них — вручную: записал значения в notepad, поменял, восстановил. Меньше эргономики, но работает.
6. T054 (Copy JSON в Lab) — fallback: посмотреть на слайдеры глазами, написать JSON руками. Кривее, но можно.
7. Один из пресетов (например `menu_quiet`) — main_menu тогда использует явные поля, не пресет.
8. Один из стингов (например `pickup`) — если на presets'ах всех мало времени.
9. Lead generator (T009) полностью — bass+pad+drums дают базовый «звучит». Lead — топпинг.

**Не режем никогда:** AC-1 (детерминизм), AC-7 (sting replaceability), AC-9 (zero controller touches), AC-13 (Music Lab — это ключевое UX-обещание Andrey'ю), AC-14 (presets — без них Lab бесполезен). Эти инварианты держим.
