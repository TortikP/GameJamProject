# 042-proc-music — spec

**Owner:** Andrey (driver, full-stack: synth, conductor, generators, stings, integration).
**Coordination:** none. Self-contained module — touches только два файла за пределами `scripts/audio/music/`: `scripts/core/maps/level_data.gd` (одно опциональное поле) и `project.godot` (регистрация autoload). EventBus, WaveController, LevelLoader, MainMenu — **не трогаем**, всё через существующие сигналы.
**Status:** Draft.

## Цель

Процедурная (алгоритмическая, real-time PCM) музыка для джема. Без записанных WAV/MIDI/OGG в качестве источников нот. Задаётся семенем и набором правил, играет в меню и на уровнях, реагирует на боевые волны, бросает короткие стинги на ключевых событиях. Стинги должны быть легко заменимы на ручные OGG'и без правки кода — это главное эргономическое требование от Andrey.

Источник ТЗ — внешний бриф (см. чат). Бриф — наполовину нейрослоп, скоуп урезан радикально (см. «Что вырезано» внизу).

## Что вводится

### 1. Модуль `scripts/audio/music/`

Полностью изолированная подсистема. Один autoload `MusicDirector`, остальное — preload-классы. Никаких других node'ов в дереве сцены, никаких новых autoload'ов кроме одного.

Архитектурные слои (low → high):

1. **Wavetables** (`synth/wavetables.gd`) — одноразово запекает 256-сэмпловые таблицы sine/triangle/square. Шум — без таблицы, `randf_range(-1,1)` через seeded RNG.
2. **Voice / VoicePool** (`synth/voice_pool.gd`) — пул из 6 одновременных голосов. Voice = oscillator type + freq + ADSR state + amplitude. Push'ятся per-sample во фрейм-буфер.
3. **ADSR** (`synth/adsr.gd`) — четырёхфазный envelope с трекингом sample-индекса. Без allocations.
4. **Conductor** (`conductor.gd`) — счётчик в сэмплах: BPM → samples per beat → samples per bar. Триггерит `tick_beat(beat_idx)`, `tick_bar(bar_idx)`. Все генераторы синхронизируются через него.
5. **Harmony** (`harmony.gd`) — текущий аккорд (root MIDI + intervals), смена раз в 4 бара по фиксированной прогрессии Am–F–C–G (i–VI–III–VII в A natural minor). Один лад, точка.
6. **Генераторы** (`generators/*.gd`) — четыре независимых: `bass_gen`, `pad_gen`, `lead_gen`, `drums_gen`. На каждом тике решают «играть/не играть/что играть» по seeded RNG + правилам. Триггерят voices через VoicePool.
7. **MusicDirector** (`music_director.gd`, autoload) — оркестрирует. Owns AudioStreamPlayer + AudioStreamGenerator. Подписан на EventBus, мапит события → state/sting calls. Содержит per-state gain ramps по слоям.
8. **Stings** (`stings/sting_player.gd`, `stings/proc_stings.gd`) — параллельный однонотный/несколько-нотный voice над музыкой. Procedural presets + опциональная подгрузка стрима из файла (см. §4).

### 2. Состояния и реактивность

Два состояния, не четыре:

| State | Bass | Pad | Lead | Drums | BPM mult |
|---|---|---|---|---|---|
| `calm` | on | on | sparse (rest > note) | off | 1.0× |
| `battle` | on | on | dense (note > rest) | on | 1.2× |

Переход — gain-ramp по слою за **1 бар**, квантованно к началу следующего бара (не моментально). Дрожание/щелчков нет, потому что новые слои поднимаются с tail прежней фазы, а не «врезаются».

Mapping EventBus → состояние:

| Signal | Effect |
|---|---|
| `level_loaded(level)` | Read `music_config`, set seed, start music in `base_state` (default `calm`). |
| `wave_started(idx, is_special)` | Switch to `battle`. |
| `wave_cleared(idx, unused)` | Play sting `wave_clear`, switch to `calm`. |
| `level_completed(score)` | Play sting `victory`, stop music after sting tail (~2s). |
| `run_ended(reason)` | Play `victory` if reason==«victory», иначе `defeat`. Stop after sting. |
| `main_menu_entered` | Switch to menu config (separate seed/bpm), `calm` only. |
| `dialogue_started/finished` | (опционально, P3) duck music gain −6 dB. |

### 3. Per-level config: `LevelData.music_config: Dictionary`

Опциональное поле на корне LevelData (как `dialogue_triggers` в 039). Default — пустой dict, derive параметров из хеша `level.name` для детерминизма без явной конфигурации.

JSON shape:

```json
{
  "music_config": {
    "seed": 1234,                       // optional int. Default = hash(level.name) & 0x7fffffff
    "bpm": 96,                          // optional float, 40..200. Default 96.
    "base_state": "calm",               // optional, "calm" | "battle". Default "calm".
    "stings": {                         // optional. Override sting id per event.
      "wave_clear": "blip_up",
      "victory":    "fanfare",
      "defeat":     "descending"
    },
    "muted": false                      // optional bool. Default false. Useful for cinematic levels.
  }
}
```

Все поля опциональны. Файл уровня без `music_config` → дефолты. Это даёт Stasyan'у нулевой барьер: ничего не редактирует — дефолтная музыка с per-level seed играет.

Editor UI **не делается в этом спеке**. Designers редактируют JSON напрямую (документация в `data/maps/_schema.md`). Если будет время — отдельный спек 04N с панелью в `LevelMetaPanel`.

### 4. Stings — JSON-driven, заменимые

`data/music/stings.json`:

```json
{
  "version": 1,
  "stings": {
    "wave_clear": { "kind": "procedural", "preset": "blip_up" },
    "victory":    { "kind": "procedural", "preset": "fanfare" },
    "defeat":     { "kind": "procedural", "preset": "descending" },
    "pickup":     { "kind": "procedural", "preset": "ping" }
  }
}
```

Чтобы заменить один стинг записанным OGG'ом — меняем одну запись:

```json
"victory": { "kind": "stream", "path": "res://assets/audio/music/stings/victory.ogg", "volume_db": 0 }
```

`MusicDirector.play_sting(name)` → `StingPlayer` смотрит config:
- `kind: "procedural"` → синтезирует через preset.
- `kind: "stream"` → `load(path)` (OGG/WAV — формат любой, что Godot ест), играет на отдельном AudioStreamPlayer.

Procedural presets (v1, в коде, в `proc_stings.gd`):
- `blip_up` — две ноты вверх по chord, square, ~0.4 s.
- `fanfare` — арпеджио мажорного аккорда (взять C major на момент стинга), 4 ноты, ~1.2 s.
- `descending` — три ноты вниз по minor scale, triangle, ~1.0 s, slow attack.
- `ping` — одна нота sine с reverb-имитацией через delayed-attack второй копии, ~0.5 s.

### 5. Main menu

`data/music/main_menu.json`:

```json
{
  "seed": 7777,
  "bpm": 72,
  "base_state": "calm",
  "muted": false
}
```

При `EventBus.main_menu_entered` MusicDirector грузит этот config, fade-in 1 бар. При `EventBus.run_started` (заходим в кампанию) — fade-out 1 бар, дальше `level_loaded` поднимет уровневую музыку.

### 6. Audio bus

Музыка играется на bus `Music` (если такой есть в `default_bus_layout.tres`) или на `Master` fallback. Глобальный mute через `AudioServer.set_bus_mute`. Громкость музыки — `Music` bus volume в Settings, не наша забота.

## Acceptance criteria

- **AC-1 (детерминизм):** запуск уровня с `music_config.seed = 42` дважды → bit-identical PCM-выход за первые 30 секунд (smoke: записать буфер, сравнить хешем).
- **AC-2 (no assets in repo):** `find assets/audio/music -type f \( -name '*.wav' -o -name '*.ogg' -o -name '*.mid' \)` пусто после спека (стинги procedural, дефолт). Заменимость через JSON — спек поддерживает, реальные ассеты — отдельный коммит вне спека.
- **AC-3 (states transitions):** `EventBus.wave_started` → drums и lead density поднимаются в течение ≤1 бар; `EventBus.wave_cleared` → drums затихают, sting проигран, состояние calm в течение ≤1 бар.
- **AC-4 (lifecycle):** `level_loaded` запускает музыку с seed/BPM из `music_config` (или дефолтов); `level_completed` проигрывает victory sting и останавливает музыку.
- **AC-5 (run end):** `run_ended("victory")` → victory sting; `run_ended` с любым другим reason → defeat sting.
- **AC-6 (main menu):** возврат в меню после рана → fade-out, fade-in menu config; повторный заход в кампанию → fade-out menu, level music через `level_loaded`.
- **AC-7 (sting swappability):** изменить в `data/music/stings.json` запись `victory` на `{kind:"stream", path:"res://path/to/test.ogg"}`, перезапустить — стинг играется из файла. Никаких правок кода.
- **AC-8 (per-level override):** уровень с `music_config.seed=7, bpm=110, stings.victory="fanfare"` использует именно их вместо дефолтов.
- **AC-9 (минимум touch'ей):** изменения вне `scripts/audio/music/` и `data/music/`:
  - `scripts/core/maps/level_data.gd` — +поле `music_config: Dictionary` + сериализация (≤20 строк добавить).
  - `project.godot` — +1 autoload `MusicDirector`.
  - `data/maps/_schema.md` — +секция `music_config`.
  - `HANDOFF.md` — +ссылка на §MusicDirector.
  - **Контроллеры (wave/level/main_menu/editor) — 0 правок.**
- **AC-10 (perf):** на ноуте Andrey'я 60 FPS sustained ≥5 минут геймплея, в Godot console — ноль `AudioStreamGeneratorPlayback: buffer underrun` warnings. Если не выходим — fallback на mix_rate=16000 + voice_pool=4.
- **AC-11 (mute respected):** `Music` bus mute → молчание мгновенно, без хвоста ADSR.
- **AC-12 (no jam-rule violation):** код не загружает ни одного аудио-файла из `assets/audio/music/` если `stings.json` весь procedural. Проверка — search по `load(.*\.ogg)` в коде модуля = 0 хитов кроме stream-стингов.

## Risks

- **R1 (perf, high):** GDScript wavetable synth × 6 voices × 22050 Hz может underrun'ить на слабых машинах. **Митигация:** push в чанках по 512 сэмплов с приоритетом по `get_frames_available()`, fallback mix_rate=16000 + 4 голоса. Если совсем плохо — отключить lead-генератор как самый дорогой и оставить bass+pad+drums.
- **R2 (artifacts, medium):** щелчки на смене аккорда / state. **Митигация:** все gain-changes через ramp ≥1 ms; смена частоты у sustain'ящегося голоса — через release+re-attack, не моментально.
- **R3 (стинги звучат плохо, high):** procedural stings — placeholder звучание. **Митигация:** именно поэтому JSON-driven swap. Спек шипит с procedural дефолтами; кто-то из команды записывает реальные стинги в OGG в субботу — подменяет три строчки JSON, всё.
- **R4 (random ≠ музыка):** сид правильный, ноты в ладу — но если генераторы тупо randf'ят без структуры, выйдет «AI-noise». **Митигация:** lead играет ноты строго из текущего аккорда на сильных долях, проходящие — на слабых; bass — root/fifth по чёткому ритму; pad — sustain'ит chord-tone'ы. Структура держится за прогрессией, не за тонкими правилами.
- **R5 (главное меню перекрывает уровень):** если `main_menu_entered` и `level_loaded` приходят в одном кадре (не должны, но мало ли) — последний выигрывает. **Митигация:** в MusicDirector flag `_loading_level: bool` — после `run_started_requested` блокируем reaction на `main_menu_entered` до `level_loaded`.

## Что вырезано из исходного брифа (нейрослоп)

| Бриф предлагал | Вердикт |
|---|---|
| 4 состояния (Idle/Exploration/Tension/Combat) | ✂ Только calm + battle. У игры нет «exploration» vs «tension» как отдельных скриптуемых состояний. |
| Major + pentatonic + natural minor | ✂ Только natural minor. Тональное разнообразие ≠ интересность для джема. |
| Low-pass filter, LFO/vibrato/AM, delay/echo, swing | ✂ Все BONUS в самом брифе. Игнор. «Мягкость» — через миксование sine с triangle в одной таблице. |
| Motif system с вариациями | ✂ Структуру даёт прогрессия + ритм-сетка, не «motif algorithm». |
| `density / dissonance / harmony speed` параметры на состояние | ✂ Две ручки достаточно: какие слои on, какой BPM mult. |
| C# реализация | ✂ GDScript. Бриф это допускает явно. |
| «Probabilistic + rule-based» для каждого генератора | ⚠ Только для lead и для drum-вариаций. Bass — детерминирован (root/fifth по сетке). Pad — детерминирован (chord tones). Перерасход RNG = ноль профита. |
| `MusicState.Combat` через C# enum API | ✂ String/StringName state names — `&"calm"`, `&"battle"`, `&"menu"`. |

## Out of scope (явно не делаем сейчас)

- Editor panel для редактирования `music_config` (правка через JSON руками).
- Hot reload `stings.json` / `music_config` без перезапуска уровня.
- LFO, filter, delay, swing, vibrato — могут быть в follow-up спеке.
- Major scale, lydian, etc. — не нужны.
- Per-wave music states (battle/calm на каждой волне отдельно вместо «все волны = battle»).
- SFX, voice, dialogue audio — это территория `AudioDirector` (HANDOFF §AudioDirector).
- Запись/экспорт PCM в файл (если кому надо «послушать вне игры» — это сторонний скрипт).
- Save/load music state между сессиями (детерминируется сидом, не нужно).
