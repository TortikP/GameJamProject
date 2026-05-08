# 061 — Implementation Plan

**Спек:** [`spec.md`](spec.md). Этот документ — *как именно* делаем. Спек — *что и зачем*.

## 0. Структура плана

Sequencing'ом разбит на **13 фаз** (соответствуют группам §10 спека). Каждая фаза — атомарная единица работы; в идеале — один-два коммита, один логический smoke-проход на конце. Фазы строго последовательны кроме явно отмеченных параллелей.

Внутри каждой фазы — конкретные технические решения (сигнатуры, файлы), risk anchors, proof-of-life критерий.

**Параллелизм:** Φ-1 (LevelData v3) и Φ-2 (is_special readers audit) могут идти параллельно после того как Φ-1 ввёл `is_wave_special()` helper. Остальные строго последовательно.

**Размер по фазам (предварительная оценка GDScript LOC):**

| Φ | Название | LOC (~) |
|---|---|---:|
| 1 | LevelData v3 + migration + validate | 130 |
| 2 | is_special readers audit + fix | 30 |
| 3 | wave_controller advance_mode runtime | 50 |
| 4 | WaveSettingsPanel skeleton + level/wave groups | 220 |
| 5 | WaveSettingsPanel spawner section | 130 |
| 6 | WaveSettingsPanel skill_offer port | 80 |
| 7 | WaveSettingsPanel dialogue triggers CRUD (level) | 220 |
| 8 | WaveSettingsPanel wave-section trigger mirror | 50 |
| 9 | EditorController public API + wiring | 100 |
| 10 | level_editor.tscn integration | scene |
| 11 | Loc-keys batch | json |
| 12 | Backward-compat smoke | smoke |
| 13 | Docs (`dialogue-triggers.md`, `_schema.md`) | docs |

WaveSettingsPanel total ~700 GDScript LOC (сумма Φ-4..Φ-8) — на границе soft cap 600 заявленного в spec.md AC32. Если на имплементации превысит — finding и пересмотр (extract trigger CRUD в sub-panel).

---

## Φ-1. LevelData v3 + migration + validate

**Что:** bump SCHEMA_VERSION → 3, расширить wave/spawner schema, добавить миграцию из v2/v1, обновить validate, добавить helper `is_wave_special`.

**Файл:** `scripts/core/maps/level_data.gd`.

### Φ-1.a. Constants + defaults

```gdscript
const SCHEMA_VERSION: int = 3   # 061: bump from 2 (added respawn_player, advance_mode, wave.music_config, spawner.amount/delay; is_special bool→String)

const DEFAULT_IS_SPECIAL: String = "normal"
const DEFAULT_ADVANCE_MODE: String = "timer"
const VALID_ADVANCE_MODES: Array[String] = ["timer", "clear", "timer_and_clear"]
const DEFAULT_SPAWNER_AMOUNT: int = 1
const DEFAULT_SPAWNER_DELAY: int = 1
```

`_make_empty_wave(idx)` обновить — добавить `is_special: "normal"`, `respawn_player: false`, `advance_mode: "timer"`, `music_config: {}`. Обратная совместимость с старым default `is_special: false` — не нужна, потому что `_make_empty_wave` используется только для свежесозданных пустых волн (которые мигрировать не из чего).

### Φ-1.b. Migration в `from_dict`

После цикла `lvl.waves.append(_wave_dict_from_arr(entry))` (текущая ~line 317) — новый блок миграции. Логика **идемпотентная**: если поле уже есть в правильном формате — оставляем; если нет или legacy — конвертим/добавляем. Это позволяет читать v3 файлы без двойного применения миграции и v2/v1 файлы с конверсией.

Псевдо-код:

```gdscript
# 061: forward migration to v3.
for i in lvl.waves.size():
    var w: Dictionary = lvl.waves[i]
    # is_special: bool → String
    var raw_is_special: Variant = w.get("is_special", DEFAULT_IS_SPECIAL)
    if raw_is_special is bool:
        w["is_special"] = "boss" if raw_is_special else "normal"
    elif raw_is_special is String:
        pass  # already v3
    else:
        w["is_special"] = DEFAULT_IS_SPECIAL  # malformed
    # respawn_player: add if missing
    if not w.has("respawn_player"):
        w["respawn_player"] = (i == 0)  # wave 0 implicit true; rest default false
    # advance_mode: add if missing
    if not w.has("advance_mode") or not (w["advance_mode"] is String):
        w["advance_mode"] = DEFAULT_ADVANCE_MODE
    # wave.music_config: add if missing
    if not w.has("music_config") or not (w["music_config"] is Dictionary):
        w["music_config"] = {}
    # spawner.amount/delay
    for s in w.get("spawners", []):
        if not s.has("amount") or int(s.get("amount", 0)) < 1:
            s["amount"] = DEFAULT_SPAWNER_AMOUNT
        if not s.has("delay") or int(s.get("delay", 0)) < 1:
            s["delay"] = DEFAULT_SPAWNER_DELAY
    lvl.waves[i] = w

lvl.version = SCHEMA_VERSION  # silently bump — file on disk may have been v1/v2
lvl._sync_active_wave_to_root()  # already exists, re-run after migration
```

**Risk anchor R-061-1:** статически-типизированные `Array[Dictionary]` поля — присваивание `w[k] = v` мутирует Dictionary, но если `w` получен из array — нужна проверка что мы пишем в тот же объект, не в копию. В GDScript Dictionary по reference, Array[Dictionary] хранит refs — значит `lvl.waves[i] = w` после мутаций избыточно, но **безопасно** оставить для читаемости. Не оптимизирую преждевременно.

**Risk anchor R-061-2:** `s` в `for s in w.get("spawners", []):` — это reference на dict в array. Мутация `s["amount"] = ...` пишется обратно. Smoke-чек — после миграции пере-сохранить и убедиться что в JSON `amount` появился.

### Φ-1.c. Сериализация в `to_dict`

`_spawners_to_arr` обновить — добавить `amount`/`delay` в выходной dict. `_wave_dict_to_arr` (если есть; иначе inline в `to_dict`) — добавить `respawn_player`/`advance_mode`/`music_config`. Ничего не дропаем — если поле есть, пишем; если нет (эдж: `_make_empty_wave` гарантирует есть) — defaults.

### Φ-1.d. Десериализация в `_wave_dict_from_arr`

Расширить чтение `respawn_player`/`advance_mode`/`music_config` (с дефолтами для legacy). `_spawners_arr_to_dicts_with_default_timer` переименовать в `_spawners_arr_to_dicts` (потому что теперь дефолтит больше чем timer) или оставить имя и добавить дефолты. **Решение:** оставить имя — вызов 1 раз, новый refactor имени без пользы. Просто внутри добавить `amount`/`delay` defaults.

### Φ-1.e. Validate расширение

В `validate()`:

```gdscript
# 061: new validations.
for i in waves.size():
    var w: Dictionary = waves[i]
    # advance_mode enum
    var am: String = str(w.get("advance_mode", DEFAULT_ADVANCE_MODE))
    if am not in VALID_ADVANCE_MODES:
        errors.append("Wave %d: advance_mode '%s' invalid (expected timer|clear|timer_and_clear)" % [i, am])
    # respawn_player on wave > 0 requires player spawner
    if i > 0 and bool(w.get("respawn_player", false)):
        var has_player: bool = false
        for s in w.get("spawners", []):
            if s.get("kind", &"") == &"player":
                has_player = true
                break
        if not has_player:
            errors.append("Wave %d: respawn_player=true but no player spawner on this wave" % i)
    # advance_mode "clear" w/o enemies = unwinnable
    if am == "clear":
        var has_enemy: bool = false
        for s in w.get("spawners", []):
            if s.get("kind", &"") == &"enemy":
                has_enemy = true
                break
        if not has_enemy:
            errors.append("WARN: Wave %d: advance_mode=clear but no enemy spawner — wave never advances" % i)
    # spawner amount/delay >= 1
    for s in w.get("spawners", []):
        var amt: int = int(s.get("amount", DEFAULT_SPAWNER_AMOUNT))
        if amt < 1:
            errors.append("Wave %d: spawner amount must be >= 1 (got %d)" % [i, amt])
        var dly: int = int(s.get("delay", DEFAULT_SPAWNER_DELAY))
        if dly < 1:
            errors.append("Wave %d: spawner delay must be >= 1 (got %d)" % [i, dly])
```

### Φ-1.f. Helper `is_wave_special`

```gdscript
## 061: derive bool from string is_special. Use this everywhere instead of
## bool(w.get("is_special", false)) — that breaks after v3 migration because
## bool("normal") = true in GDScript.
func is_wave_special(idx: int) -> bool:
    if idx < 0 or idx >= waves.size():
        return false
    return str(waves[idx].get("is_special", DEFAULT_IS_SPECIAL)) != "normal"
```

**Proof of life Φ-1:** unit-style проверка вручную через playtest — открыть редактор, загрузить `data/maps/1.json` (v2 файл), сохранить, убедиться что в JSON `version: 3`, новые поля присутствуют с дефолтами, `is_special` — строка `"normal"`. Diff между загрузкой и save'ом содержит только эти изменения.

**Объём:** ~130 строк net (миграция блок + validate расширения + helper + defaults в `_make_empty_wave` и сериализацию).

---

## Φ-2. is_special readers audit + fix

**Что:** Найти и исправить все места, читающие `is_special` напрямую как `bool` — после миграции `bool("normal") = true`, что сломает визуальные badge'и и логику.

**Изменения:**

| Файл | Строка | Текущее | Заменить на |
|---|---:|---|---|
| `scripts/presentation/ui/wave_timeline.gd` | 395 | `var is_special: bool = bool(w.get("is_special", false))` | `var is_special: bool = _level.is_wave_special(i)` |
| `scripts/presentation/ui/wave_timeline.gd` | 397 | (read) | (covered above) |
| `scripts/presentation/ui/wave_timeline.gd` | 498 | `if bool(w.get("is_special", false)):` | `if _level.is_wave_special(i):` |
| `scripts/presentation/dev/skill_offer_smoke_controller.gd` | 153 | `"is_special": false` | `"is_special": "normal"` |
| `scripts/presentation/dev/skill_offer_smoke_controller.gd` | 189 | `"is_special": false` | `"is_special": "normal"` |
| `scripts/presentation/dev/skill_offer_smoke_controller.gd` | 244 | `"is_special": false` | `"is_special": "normal"` |

**Не трогаем:**
- `scripts/runtime/skill_offer_controller.gd:158`, `tutorial_director.gd:879`, `campaign_controller.gd:116`, `music_director.gd:232`, `wave_timeline.gd:544` — все читают `_is_special: bool` из EventBus сигнатуры (signal'а сигнатура не меняется, derive в wave_controller).
- `scripts/runtime/wave_controller.gd:142, 145` — изменяется в Φ-3.
- `scripts/core/maps/level_data.gd` — изменяется в Φ-1.

**Risk anchor R-061-3:** `_level` в `wave_timeline.gd` — может быть `null` в момент пересчёта геометрии (initial render). Helper `is_wave_special` на null'е грохнется. Mitigation: в `wave_timeline.gd` `if _level == null: continue` уже стоит выше; читаем helper только внутри этого guard'а. Smoke — открыть playtest на v3 карте с `boss` волной, убедиться что timeline показывает «boss»-маркер на правильной волне.

**Proof of life Φ-2:** загрузить любую v2 карту (например `sample_skill_offer.json` где `wave[2].is_special = true`), пройти в playtest. Wave 2 должна показываться визуально как special (golden background или whatever — текущий стиль). После save'а карта v3, пере-загружаем — то же самое.

**Объём:** ~30 строк изменений (мостовые точки + локальный fix).

---

## Φ-3. wave_controller advance_mode runtime

**Что:** реализовать `"timer"` (текущее), `"clear"`, `"timer_and_clear"` режимы в `wave_controller.gd`.

**Файл:** `scripts/runtime/wave_controller.gd`.

### Φ-3.a. State + signal subscription

В classfields:

```gdscript
# 061: advance_mode state.
# True means current wave's auto-advance is gated on EventBus.wave_cleared.
# Set by _check_advance() for "timer_and_clear" when ttn drops to 0,
# or by _start_wave() for "clear" right at wave start.
var _waiting_for_clear: bool = false
```

В `_ready` или where signals connected — подписаться на `EventBus.wave_cleared`:

```gdscript
EventBus.wave_cleared.connect(_on_wave_cleared)
```

(Имя сигнала — найти в `event_bus.gd`. Если `wave_cleared(idx)` — параметр idx; примем что signature `wave_cleared(wave_index: int)`.)

### Φ-3.b. Advance gate logic

Текущая логика advance (в `_advance_wave_or_complete` / `_on_world_turn_ended` — посмотреть в коде, упростим до функции `_check_advance`):

```gdscript
func _check_advance() -> void:
    if _current_wave_index >= _level.waves.size():
        return
    var w: Dictionary = _level.waves[_current_wave_index]
    var mode: String = str(w.get("advance_mode", LevelData.DEFAULT_ADVANCE_MODE))
    var ttn_zero: bool = int(w.get("turns_to_next", 0)) <= 0  # после декремента в текущем ходе
    match mode:
        "timer":
            if ttn_zero:
                _advance_to_next_wave()
        "clear":
            # никогда не advance по timer'у; только по wave_cleared (см. _on_wave_cleared)
            _waiting_for_clear = true
        "timer_and_clear":
            if ttn_zero:
                _waiting_for_clear = true
            # advance не происходит здесь; ждём _on_wave_cleared

func _on_wave_cleared(_idx: int) -> void:
    if _waiting_for_clear:
        _waiting_for_clear = false
        _advance_to_next_wave()
```

`_start_wave(idx)` сбрасывает `_waiting_for_clear = false` в начале волны и устанавливает в `true` если `advance_mode == "clear"`.

### Φ-3.c. is_special derive

Lines 142, 145 (прямой `bool(w.get("is_special", false))` при emit'е `EventBus.wave_started`):

```gdscript
var is_special_bool: bool = _level.is_wave_special(_current_wave_index)
EventBus.wave_started.emit(_current_wave_index, is_special_bool)
```

Сигнал `wave_started(index: int, is_special: bool)` остаётся неизменным — все 5 рантайм консьюмеров продолжают работать.

### Φ-3.d. Pillar 1 visual indicator

В runtime HUD (где счётчик волны / wave UI). Где это живёт — в playtest сцене найти. Минимум: текстовый префикс `«(waiting for clear)»` рядом с счётчиком когда `_waiting_for_clear == true`. Полноценный визуал (иконка / цвет) — defer в follow-up если будет нужно. Локализационный ключ: `ui_wave_waiting_for_clear`.

**Risk anchor R-061-4:** какой именно сигнал EventBus сообщает о clear — нужно проверить. `wave_cleared`? `all_enemies_dead`? Если такого сигнала нет вообще — придётся добавить (small EventBus extension). В этом случае: проверка enemies-alive живёт где-то (`actor_registry`?) — подписка туда.

**Mitigation:** в Φ-3 первой задачей — открыть `event_bus.gd` и `wave_controller.gd`, найти где сейчас фиксируется «волна закончилась» — это и есть точка интеграции. Если оно сейчас inline в wave_controller (не сигнал) — extract в сигнал в этом же спеке, маленький EventBus add не страшно (не breaking).

**Proof of life Φ-3:** создать тестовую карту вручную через JSON: 2 волны, wave 0 имеет `advance_mode: "timer_and_clear"`, `turns_to_next: 3`, 1 enemy spawner на wave 0. Запустить playtest. Подтвердить:
1. На turn 0-2 счётчик ходов идёт (3,2,1).
2. На turn 3 счётчик 0 — но wave не advance'ится (visual: «waiting for clear» префикс).
3. Убить enemy → wave_cleared event → advance в wave 1.
Альтернативный сценарий: убить enemy на turn 1 (раньше timeout) → advance немедленно.

**Объём:** ~50 строк (state + advance logic + on_cleared + is_special derive).

---

## Φ-4. WaveSettingsPanel skeleton + level/wave groups

**Что:** Создать панель, наполнить группами `level` и `wave` (без spawner / skill_offer / triggers — те идут в Φ-5..7).

**Файлы:**
- `scripts/presentation/dev/wave_settings_panel.gd` (новый)
- `scenes/dev/wave_settings_panel.tscn` (новый)

### Φ-4.a. Class skeleton

```gdscript
class_name WaveSettingsPanel
extends BasePanel
## 061-wave-data-and-settings: правая панель Level Editor с группами для
## редактирования level/wave/spawners/skill_offer/dialogue_triggers/music_config.
## Wave-scoped группы рефлектят активную волну (set_active_wave).
## Level-scoped группы — глобальные для всего LevelData.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# Wave navigation signals — controller выполняет mutation через LevelData.
signal wave_switch_requested(idx: int)
signal wave_add_requested(after_idx: int)
signal wave_copy_requested(after_idx: int)
signal wave_delete_requested(idx: int)
# Generic wave field updates.
signal wave_field_changed(idx: int, field: String, value: Variant)
# Spawner CRUD (Φ-5).
signal spawner_field_changed(coord: Vector2i, fields: Dictionary)
# Dialogue trigger CRUD (Φ-7).
signal trigger_created(trigger_dict: Dictionary)
signal trigger_updated(old_id: StringName, trigger_dict: Dictionary)
signal trigger_deleted(trigger_id: StringName)
# Skill offer (Φ-6, port из удалённого wave_panel.gd).
signal skill_offer_changed(idx: int, offer: Variant)
signal skill_offer_preview_requested(idx: int)

var _level: LevelData = null
var _active_wave: int = 0

# Group containers (built in _ready).
var _wave_switcher: ItemList
var _switcher_btn_add: Button
var _switcher_btn_copy: Button
var _switcher_btn_delete: Button
var _level_section: VBoxContainer  # level-scoped fields + dialogue triggers (Φ-7)
var _wave_section: VBoxContainer   # active wave fields
var _spawner_section: VBoxContainer  # Φ-5
var _skill_offer_section: VBoxContainer  # Φ-6
var _wave_triggers_section: VBoxContainer  # Φ-8 mirror

# Wave field controls (built in _build_wave_section).
var _wave_is_special_edit: LineEdit
var _wave_ttn_spin: SpinBox
var _wave_respawn_check: CheckBox
var _wave_advance_mode_dropdown: OptionButton

# Refresh guard — prevents programmatic updates from emitting signals.
var _refreshing: bool = false


func _ready() -> void:
    super._ready()  # BasePanel header + drag/resize/persistence
    _build_body()


func bind_level(level: LevelData) -> void:
    _level = level
    _active_wave = 0 if level == null else level.get_active_wave_index()
    _refresh_all()


func set_active_wave(idx: int) -> void:
    _active_wave = idx
    _refresh_active_wave_fields()
    # Φ-8: also refresh wave-section trigger mirror.

func select_trigger(_id: StringName) -> void:
    pass  # Φ-7
```

### Φ-4.b. WaveSwitcher build

В `_build_body`:

```gdscript
func _build_body() -> void:
    var body := get_body_container()
    if body == null: return
    var vbox := VBoxContainer.new()
    body.add_child(vbox)

    # 1. WaveSwitcher row
    var switcher_box := _build_wave_switcher()
    vbox.add_child(switcher_box)

    # 2. Level group (level-scoped triggers — Φ-7)
    _level_section = _build_level_section()
    vbox.add_child(_level_section)

    # 3. Wave group (active wave fields)
    _wave_section = _build_wave_section()
    vbox.add_child(_wave_section)

    # 4-6. Spawner / SkillOffer / Wave-triggers — заглушки на Φ-4, наполняются Φ-5/6/8
    _spawner_section = VBoxContainer.new(); _spawner_section.name = "SpawnerSection"
    vbox.add_child(_spawner_section)
    _skill_offer_section = VBoxContainer.new(); _skill_offer_section.name = "SkillOfferSection"
    vbox.add_child(_skill_offer_section)
    _wave_triggers_section = VBoxContainer.new(); _wave_triggers_section.name = "WaveTriggersSection"
    vbox.add_child(_wave_triggers_section)
```

WaveSwitcher = `ItemList` + 3 кнопки (`+ Wave`, `Copy from prev`, `Delete`) в HBox. На select — emit `wave_switch_requested`.

### Φ-4.c. Level section (без триггеров пока)

В Φ-4 — заглушка с label «Level scope (triggers — Φ-7)». В Φ-7 наполняется CRUD'ом.

### Φ-4.d. Wave section

Поля активной волны:

```gdscript
func _build_wave_section() -> VBoxContainer:
    var box := VBoxContainer.new(); box.name = "WaveSection"
    box.add_child(_make_section_header("ui_wavesettings_wave_header", "Wave"))

    # is_special LineEdit
    var is_special_row := HBoxContainer.new()
    is_special_row.add_child(_make_label("ui_wavesettings_is_special", "Is special"))
    _wave_is_special_edit = LineEdit.new()
    _wave_is_special_edit.placeholder_text = Localization.t("ui_wavesettings_is_special_hint", "normal | boss | miniboss_*")
    _wave_is_special_edit.text_submitted.connect(func(t):
        if not _refreshing: wave_field_changed.emit(_active_wave, "is_special", t)
    )
    _wave_is_special_edit.focus_exited.connect(func():
        if not _refreshing: wave_field_changed.emit(_active_wave, "is_special", _wave_is_special_edit.text)
    )
    is_special_row.add_child(_wave_is_special_edit)
    box.add_child(is_special_row)

    # turns_to_next SpinBox
    var ttn_row := HBoxContainer.new()
    ttn_row.add_child(_make_label("ui_wavesettings_ttn", "Turns to next"))
    _wave_ttn_spin = SpinBox.new()
    _wave_ttn_spin.min_value = 0; _wave_ttn_spin.max_value = 999; _wave_ttn_spin.step = 1
    _wave_ttn_spin.value_changed.connect(func(v):
        if not _refreshing: wave_field_changed.emit(_active_wave, "turns_to_next", int(v))
    )
    ttn_row.add_child(_wave_ttn_spin)
    box.add_child(ttn_row)

    # respawn_player CheckBox (hidden on wave 0 in _refresh)
    _wave_respawn_check = CheckBox.new()
    _wave_respawn_check.text = Localization.t("ui_wavesettings_respawn_player", "Respawn player on this wave")
    _wave_respawn_check.toggled.connect(func(v):
        if not _refreshing: wave_field_changed.emit(_active_wave, "respawn_player", v)
    )
    box.add_child(_wave_respawn_check)

    # advance_mode OptionButton
    var am_row := HBoxContainer.new()
    am_row.add_child(_make_label("ui_wavesettings_advance_mode", "Advance mode"))
    _wave_advance_mode_dropdown = OptionButton.new()
    _wave_advance_mode_dropdown.add_item(Localization.t("ui_wavesettings_advance_timer", "Timer"))
    _wave_advance_mode_dropdown.add_item(Localization.t("ui_wavesettings_advance_clear", "Clear"))
    _wave_advance_mode_dropdown.add_item(Localization.t("ui_wavesettings_advance_timer_and_clear", "Timer + Clear"))
    _wave_advance_mode_dropdown.item_selected.connect(func(i):
        if _refreshing: return
        var mode: String = ["timer", "clear", "timer_and_clear"][i]
        wave_field_changed.emit(_active_wave, "advance_mode", mode)
    )
    am_row.add_child(_wave_advance_mode_dropdown)
    box.add_child(am_row)
    return box
```

`_refresh_active_wave_fields`:

```gdscript
func _refresh_active_wave_fields() -> void:
    if _level == null or _active_wave < 0 or _active_wave >= _level.waves.size():
        return
    var w: Dictionary = _level.waves[_active_wave]
    _refreshing = true
    _wave_is_special_edit.text = str(w.get("is_special", "normal"))
    _wave_ttn_spin.value = int(w.get("turns_to_next", 0))
    _wave_respawn_check.button_pressed = bool(w.get("respawn_player", false))
    _wave_respawn_check.visible = (_active_wave > 0)  # wave 0 implicit true
    var mode: String = str(w.get("advance_mode", "timer"))
    var idx: int = ["timer", "clear", "timer_and_clear"].find(mode)
    _wave_advance_mode_dropdown.selected = max(0, idx)
    _refreshing = false
```

### Φ-4.e. Scene `wave_settings_panel.tscn`

Inherited Scene из `base_panel.tscn`. Skeleton:
- Default size: 360×600.
- Default anchors: right edge, top.
- Title: `«Wave Settings»` (loc-key `ui_wavesettings_title`).

**Risk anchor R-061-5:** Inherited Scene + script с `_build_body` programmatically — паттерн уже используется (см. удалённый `dialogue_trigger_panel.gd`). Должно работать. Но если BasePanel resolve'ит nodes по @onready — `_build_body` после `super._ready()` правильный порядок.

**Proof of life Φ-4:** запустить редактор. Видим WaveSettingsPanel справа. WaveSwitcher показывает «Wave 0» (single-wave map). Wave-секция показывает поля активной волны. Add/Copy/Delete нажимаются (без эффекта пока — controller wiring в Φ-9).

**Объём:** ~220 строк GDScript + scene.

---

## Φ-5. WaveSettingsPanel spawner section

**Что:** В `_spawner_section` строим список спаунеров активной волны + edit-form под кликом.

**Файл:** `scripts/presentation/dev/wave_settings_panel.gd`.

### Φ-5.a. Spawners list

В `_build_spawner_section`:

```gdscript
func _build_spawner_section() -> Control:
    var box := VBoxContainer.new()
    box.add_child(_make_section_header("ui_wavesettings_spawners_header", "Spawners"))
    _spawner_list = ItemList.new()
    _spawner_list.item_selected.connect(_on_spawner_selected)
    box.add_child(_spawner_list)

    _spawner_form = _build_spawner_form()  # collapsible edit form
    _spawner_form.visible = false
    box.add_child(_spawner_form)
    return box
```

`_refresh_spawner_list` — итерация по `_level.waves[_active_wave].spawners`, для каждого добавляет строку: `«{kind} {ref} @ ({coord.x}, {coord.y}) · t={timer} a={amount} d={delay}»`.

### Φ-5.b. Edit form

Form содержит:
- `kind` Label (read-only — change kind через delete+paint, AC12)
- `ref` OptionButton (для enemy — список из EnemyDB; для player — пустой/disabled)
- `timer` SpinBox (≥1)
- `amount` SpinBox (≥1) — рядом badge `(schema-only)` если amount > 1 (тэг про runtime warn-once)
- `delay` SpinBox (≥1) — disabled если amount=1

Все controls на change emit'ят `spawner_field_changed(coord, {field: value})`. Coord хранится в `_selected_spawner_coord: Vector2i`.

### Φ-5.c. Refresh on wave switch

`set_active_wave(idx)` → `_refresh_spawner_list()` → form скрывается до нового select'а.

**Risk anchor R-061-6:** ref OptionButton должен брать список enemy_id из EnemyDB. Нужно посмотреть как SpawnerPalette (060) этот список тянет — переиспользовать тот же source. Если EnemyDB не предоставляет enumeration API — добавить `get_all_ids() -> Array[StringName]` (тривиальное расширение).

**Proof of life Φ-5:** в карте с enemy spawner'ом — кликнуть по строке в списке spawner'ов в WaveSettingsPanel → форма открылась с текущими значениями → изменить timer/amount/delay → сохранить → пере-загрузить → значения остались.

**Объём:** ~130 строк.

---

## Φ-6. WaveSettingsPanel skill_offer port

**Что:** Перенести `_build_skill_offer_section` из удалённого `wave_panel.gd` (можно подсмотреть в `673e377^:scripts/presentation/dev/wave_panel.gd`, строки ~`_build_skill_offer_section`).

**Файл:** `scripts/presentation/dev/wave_settings_panel.gd`.

### Φ-6.a. Port

Старая секция: pool dropdown + count SpinBox + 4 CheckBox'а (allow_upgrade/replace/skip/exclude_owned) + preview button. Сигналы: `skill_offer_changed(idx, offer)` / `skill_offer_preview_requested(idx)` — те же что в спецификации (AC32).

Адаптация:
- Замена `_active_wave_index` на `_active_wave` (имя поля в новом классе).
- `_so_refreshing` guard остаётся (защита от программного refresh).
- Build вызывается из `_build_body` после spawner_section.

### Φ-6.b. Refresh on wave switch

`set_active_wave(idx)` → `_refresh_skill_offer_section()` (как в старом коде — bind полей из `_level.waves[_active_wave].skill_offer`).

**Risk anchor R-061-7:** старый `_build_skill_offer_section` ссылался на `UiThemeScript` (preload в старом файле). В новом WaveSettingsPanel preload UiTheme уже есть (стандартный паттерн). Все ссылки `UiThemeScript.X` заменить на `UiTheme.X`.

**Proof of life Φ-6:** загрузить карту с `skill_offer` (например `sample_skill_offer.json`), переключаться между волнами, секция показывает корректные значения. Изменить count → автосейв → reload → значение сохранилось.

**Объём:** ~80 строк (port + adaptation).

---

## Φ-7. WaveSettingsPanel dialogue triggers CRUD (level)

**Что:** В level-секции — полноценный CRUD по `LevelData.dialogue_triggers`. Reuse паттерна из удалённого `dialogue_trigger_panel.gd` (`673e377^:scripts/presentation/dev/dialogue_trigger_panel.gd`).

**Файл:** `scripts/presentation/dev/wave_settings_panel.gd`.

### Φ-7.a. Список + кнопки

В `_build_level_section`:

```gdscript
_triggers_list = ItemList.new()
_triggers_list.item_selected.connect(_on_trigger_selected)
# row format: "{id} · {event} · → {dialogue_id}"

# button row
_btn_trigger_add = Button.new(); _btn_trigger_add.text = "Add"
_btn_trigger_edit = Button.new(); _btn_trigger_edit.text = "Edit"
_btn_trigger_dupe = Button.new(); _btn_trigger_dupe.text = "Duplicate"
_btn_trigger_del = Button.new(); _btn_trigger_del.text = "Delete"
# ... wired в _on_trigger_action
```

### Φ-7.b. Edit form

Collapsible под списком. Поля:

- **`id`** — `LineEdit`, плейсхолдер `«trigger ID — для логов и once-tracking»`. Подпись над полем — loc-key `ui_trigger_id_help` («Trigger ID — уникален в пределах уровня. Для редактор-референса и once-tracking. ≠ dialogue_id.»).
- **`event`** — `OptionButton` с `CURATED_EVENTS = ["level_started", "wave_about_to_start", "wave_started", "wave_cleared", "world_turn_ended", "skill_offer_about_to_open", "skill_offer_closed", "level_completed"]` + последний пункт `«Custom...»` который раскрывает LineEdit для произвольного event.
- **`dialogue_id`** — `OptionButton` с filter (в Godot нет нативного searchable dropdown — реализую как LineEdit + popup с фильтрованным списком; или просто OptionButton + LineEdit-фильтр для топ-N матчей). Список из `DialogueDB.get_all_ids()`. Если `DialogueDB` пуст — placeholder `«(no dialogues loaded)»`. Подпись — loc-key `ui_trigger_dialogue_help` («Dialogue — что играть. Ключ из DialogueDB.»).
- **`play_mode`** — pair `RadioButton`-style (но Godot — `CheckButton`-pair с одним active, или OptionButton с двумя элементами). Используем OptionButton с двумя items — проще.
- **`conditions`** — chip-list с включаемыми условиями. Каждое condition — `CheckBox + value editor`:
  - `wave_index: int` (CheckBox + SpinBox)
  - `absolute_turn: int` (CheckBox + SpinBox)
  - `cleared_in_turns_lt: int` (CheckBox + SpinBox)
  - `chance: float [0.0, 1.0]` (CheckBox + SpinBox с шагом 0.05)
  - `mood: String` (CheckBox + LineEdit) — для будущих aspect/mood gates (запас, не блокер)
  - `once_per_run: bool` (просто CheckBox)
- **Save / Cancel buttons** — Save → emit `trigger_created` (если new) или `trigger_updated(old_id, t)` (если edit). Cancel — закрывает форму без emit'а.

### Φ-7.c. State machine

`_editing: bool = false`, `_editing_new: bool = false`. Add → `_editing = true; _editing_new = true; _open_form_blank()`. Edit → `_editing = true; _editing_new = false; _open_form_with(t)`. Save / Cancel → `_close_form()`.

### Φ-7.d. Validation в форме

Перед emit — локальная валидация (повтор `DialogueTrigger.validate`):
- `id` non-empty, unique within level (проверка против `_level.dialogue_triggers`).
- `event` non-empty.
- `play_mode in {request, play}`.
Если валидация не прошла — error-label под формой, не emit'ить.

### Φ-7.e. Refresh

`_refresh_triggers_list` — чистка и заполнение `_triggers_list` из `_level.dialogue_triggers`. Вызывается на `bind_level`, `set_active_wave` (для wave-section mirror в Φ-8), и после каждой CRUD-операции (через `bind_level` re-bind контроллером).

**Risk anchor R-061-8:** `DialogueDB.get_all_ids()` существует ли уже как public API? Если нет — нужно проверить, как старый `dialogue_trigger_panel.gd` это делал. По комменту в spec'е 039 (`AC-D18`): «Список — `DialogueDB.get_all_ids()`. Если DB пустая — placeholder». Если уже есть — переиспользуем; если нет — небольшое расширение DialogueDB (тривиально).

**Risk anchor R-061-9:** Searchable dialogue_id picker — это маленький UX вопрос. Если базовый OptionButton достаточен (≤30 диалогов в db) — не делаем filter, просто sort по алфавиту. Если 100+ — нужен фильтр. Сейчас (по содержимому `data/dialogues/`) скорее ≤30 — отложим filter до плейтеста.

**Proof of life Φ-7:** в редакторе нажать Add в level-секции → форма открылась → заполнить id `test_trig`, event `level_started`, dialogue_id (выбрать из dropdown), play_mode `play` → Save → строка появилась в списке → save карты → пере-загрузить → trigger в `LevelData.dialogue_triggers`.

**Объём:** ~220 строк.

---

## Φ-8. WaveSettingsPanel wave-section trigger mirror

**Что:** В `_wave_triggers_section` показать read-only список триггеров с `conditions.wave_index == _active_wave`. Клик переводит фокус в level-секцию на эту запись.

**Файл:** `scripts/presentation/dev/wave_settings_panel.gd`.

### Φ-8.a. Mirror list

```gdscript
func _refresh_wave_triggers_mirror() -> void:
    _wave_triggers_list.clear()
    if _level == null: return
    for t in _level.dialogue_triggers:
        var c: Dictionary = t.get("conditions", {})
        if c.has("wave_index") and int(c["wave_index"]) == _active_wave:
            _wave_triggers_list.add_item("[%s] %s → %s" % [t.get("id"), t.get("event"), t.get("dialogue_id")])
```

### Φ-8.b. Click → focus в level-секции

```gdscript
func _on_wave_mirror_selected(idx: int) -> void:
    var t: Dictionary = _filtered_wave_triggers[idx]
    select_trigger(StringName(t.get("id", "")))  # уже определён в Φ-7
```

`select_trigger(id)` находит индекс в level-list, выбирает row, открывает edit form.

**Proof of life Φ-8:** карта с триггером `wave_index=1`. Переключиться на wave 1 в WaveSwitcher → wave-section mirror показывает trigger. Клик → level-section подсветил эту запись и открыл edit form.

**Объём:** ~50 строк.

---

## Φ-9. EditorController public API + wiring

**Что:** добавить методы для wave nav + dialogue triggers CRUD + wire WaveSettingsPanel.

**Файл:** `scripts/presentation/dev/editor/editor_controller.gd`.

### Φ-9.a. New methods

Новые публичные:

```gdscript
func set_active_wave(idx: int) -> void:
    if _level == null: return
    if idx < 0 or idx >= _level.waves.size(): return
    _level.set_active_wave_index(idx)
    _io.refresh_grid_from_level(_level, _hexes_overlay, _objects_overlay, _spawners_overlay)
    _wave_settings_panel.set_active_wave(idx)
    _io.enqueue_autosave(_level)

func add_wave(after_idx: int) -> void:
    if _level == null: return
    var new_idx: int = after_idx + 1
    var w: Dictionary = LevelData._make_empty_wave(new_idx)
    _level.waves.insert(new_idx, w)
    _reindex_waves()
    _on_immediate_persist()
    set_active_wave(new_idx)

func copy_wave_from_prev(after_idx: int) -> void:
    if _level == null or after_idx < 0: return
    var src: int = after_idx
    var new_idx: int = after_idx + 1
    var w: Dictionary = _level.make_wave_copy_no_spawners(src, new_idx)
    _level.waves.insert(new_idx, w)
    _reindex_waves()
    _on_immediate_persist()
    set_active_wave(new_idx)

func delete_wave(idx: int) -> void:
    if _level == null or _level.waves.size() <= 1: return  # не удаляем последнюю
    if idx < 0 or idx >= _level.waves.size(): return
    _level.waves.remove_at(idx)
    _reindex_waves()
    var new_active: int = clampi(idx, 0, _level.waves.size() - 1)
    _on_immediate_persist()
    set_active_wave(new_active)

func update_wave_field(idx: int, field: String, value: Variant) -> void:
    # Локальная валидация на принимаемых значениях. Если invalid — toast WARN, без commit.
    if _level == null or idx < 0 or idx >= _level.waves.size(): return
    var w: Dictionary = _level.waves[idx]
    match field:
        "is_special":
            w["is_special"] = str(value)  # free-form
        "turns_to_next":
            w["turns_to_next"] = int(value)
        "respawn_player":
            w["respawn_player"] = bool(value)
        "advance_mode":
            var mode: String = str(value)
            if mode in LevelData.VALID_ADVANCE_MODES:
                w["advance_mode"] = mode
            else:
                EventBus.toast.emit("Invalid advance_mode: " + mode, 2)
                return
        "music_config":
            # JSON parse — если parse failed, toast WARN.
            var parsed = JSON.parse_string(str(value))
            if parsed is Dictionary:
                w["music_config"] = parsed
            else:
                EventBus.toast.emit("music_config: invalid JSON", 2)
                return
        _:
            push_warning("update_wave_field: unknown field " + field)
            return
    _level.waves[idx] = w
    _io.enqueue_autosave(_level)

func update_spawner(coord: Vector2i, fields: Dictionary) -> void:
    if _level == null: return
    _level.sync_root_to_active_wave()
    for i in _level.spawners.size():
        var s: Dictionary = _level.spawners[i]
        if s.get("coord", Vector2i.ZERO) == coord:
            for k in fields:
                s[k] = fields[k]
            _level.spawners[i] = s
            break
    _io.enqueue_autosave(_level)

func add_dialogue_trigger(t: Dictionary) -> bool:
    if _level == null: return false
    var dt := DialogueTrigger.from_dict(t)
    var errs: Array[String] = dt.validate()
    if not errs.is_empty():
        EventBus.toast.emit("trigger validation: " + errs[0], 2)
        return false
    # Uniqueness
    for raw in _level.dialogue_triggers:
        if raw.get("id", "") == t.get("id", ""):
            EventBus.toast.emit("trigger id already exists: " + str(t.get("id")), 2)
            return false
    _level.dialogue_triggers.append(t.duplicate(true))
    _io.enqueue_autosave(_level)
    _wave_settings_panel.bind_level(_level)  # rebind triggers list
    return true

func update_dialogue_trigger(old_id: StringName, t: Dictionary) -> bool:
    # similar — find by old_id, replace if validates
    ...

func delete_dialogue_trigger(id: StringName) -> bool:
    # find by id, remove
    ...

# Helper
func _reindex_waves() -> void:
    for i in _level.waves.size():
        _level.waves[i]["index"] = i

func _on_immediate_persist() -> void:
    # bypass debounce — call _io.save() directly through enqueue with 0 timer.
    # Or expose _io.save_immediately(level). Decision in implementation.
    _io.save_immediately(_level) if _io.has_method("save_immediately") else _io.enqueue_autosave(_level)
```

### Φ-9.b. Wire signals

В `_ready` (или там где остальные wirings):

```gdscript
_wave_settings_panel = $HUD/WaveSettingsPanel
_wave_settings_panel.bind_level(_level)
_wave_settings_panel.wave_switch_requested.connect(set_active_wave)
_wave_settings_panel.wave_add_requested.connect(add_wave)
_wave_settings_panel.wave_copy_requested.connect(copy_wave_from_prev)
_wave_settings_panel.wave_delete_requested.connect(delete_wave)
_wave_settings_panel.wave_field_changed.connect(update_wave_field)
_wave_settings_panel.spawner_field_changed.connect(update_spawner)
_wave_settings_panel.trigger_created.connect(add_dialogue_trigger)
_wave_settings_panel.trigger_updated.connect(update_dialogue_trigger)
_wave_settings_panel.trigger_deleted.connect(delete_dialogue_trigger)
# skill_offer signals — port из старого _wire_wave_panel.
```

### Φ-9.c. Hard cap bump

Текущий cap 300 (AC33 060). Новые методы добавляют ~80 строк (set/add/copy/delete + update_wave_field + update_spawner + 3 trigger CRUD + wirings). Поднятие cap с 300 → **350** (AC33 061).

**Risk anchor R-061-10:** `EventBus.toast` сигнал — существует? Из 060'ной памяти знаю что toast идёт через EventBus. Проверить и подкорректировать. Если иначе (через ToastLayer прямо) — соответствующая корректировка.

**Risk anchor R-061-11:** `_io.save_immediately` метод — может не существовать. EditorIO в 060 имеет `enqueue_autosave` (debounce) и `save` (через UI кнопку). `save_immediately` для wave-mutation — нужен новый метод, или использовать `enqueue_autosave` с debounce'ом 1.5s (acceptable для ADD/DELETE — не критично).

**Решение:** использовать `enqueue_autosave` везде, без `save_immediately`. Если debounce окажется проблемой при quick add+delete — добавим `_io.flush_pending_autosave()` отдельным task'ом.

**Proof of life Φ-9:** в редакторе нажать «+ Wave» → новая волна появляется в WaveSwitcher → переключиться на неё → грид перерисовался (пустая волна) → save → пере-загрузить → wave 1 на месте.

**Объём:** ~100 строк.

---

## Φ-10. level_editor.tscn integration

**Что:** добавить `WaveSettingsPanel` instance в HUD сцены.

**Файл:** `scenes/dev/level_editor.tscn`.

Добавить:

```
[ext_resource type="PackedScene" uid="uid://..." path="res://scenes/dev/wave_settings_panel.tscn" id="X_wsp"]

[node name="WaveSettingsPanel" parent="HUD" instance=ExtResource("X_wsp")]
```

Default position — правый край (anchors right=1.0, top=0.0). Default size заданы в `wave_settings_panel.tscn`.

**Risk anchor R-061-12:** конфликт с LayersPanel в default layout. LayersPanel сейчас (060) — где? Если тоже справа — наложатся. Mitigation: при первом запуске WaveSettingsPanel offset вниз от LayersPanel (через default top anchor + height LayersPanel). Layout persistence (058) запомнит после первого drag.

**Proof of life Φ-10:** запуск редактора, обе панели видны, не перекрываются.

**Объём:** scene-only (~10 строк tscn).

---

## Φ-11. Loc-keys batch

**Что:** добавить новые ключи в `data/localization/{en,ru}.json`.

**Список ключей:**

```
ui_wavesettings_title
ui_wavesettings_wave_header
ui_wavesettings_level_header
ui_wavesettings_spawners_header
ui_wavesettings_skill_offer_header
ui_wavesettings_dialogue_triggers_header
ui_wavesettings_wave_triggers_header
ui_wavesettings_is_special
ui_wavesettings_is_special_hint
ui_wavesettings_ttn
ui_wavesettings_respawn_player
ui_wavesettings_advance_mode
ui_wavesettings_advance_timer
ui_wavesettings_advance_clear
ui_wavesettings_advance_timer_and_clear
ui_wavesettings_music_config
ui_wavesettings_music_config_hint
ui_wavesettings_switcher_add
ui_wavesettings_switcher_copy
ui_wavesettings_switcher_delete
ui_wave_waiting_for_clear
ui_trigger_id_help
ui_trigger_dialogue_help
ui_trigger_event_custom
ui_trigger_play_mode_request
ui_trigger_play_mode_play
ui_trigger_condition_wave_index
ui_trigger_condition_absolute_turn
ui_trigger_condition_cleared_in_turns_lt
ui_trigger_condition_chance
ui_trigger_condition_mood
ui_trigger_condition_once_per_run
ui_trigger_btn_add
ui_trigger_btn_edit
ui_trigger_btn_dupe
ui_trigger_btn_delete
ui_trigger_btn_save
ui_trigger_btn_cancel
ui_trigger_validate_id_dup
ui_spawner_form_kind
ui_spawner_form_ref
ui_spawner_form_timer
ui_spawner_form_amount
ui_spawner_form_amount_schema_only
ui_spawner_form_delay
```

**Объём:** ~45 ключей × 2 языка = ~90 entries.

---

## Φ-12. Backward-compat smoke (AC34-36)

**Что:** Manual smoke-проход всех существующих карт. Проверка load → save → reload roundtrip.

**Список карт для smoke:**

| Файл | Особенность |
|---|---|
| `data/maps/1.json` | базовая v2, 1 wave |
| `data/maps/sample_skill_offer.json` | многоволновая, есть skill_offer + is_special=true |
| `data/maps/story_map_03.json` | Никитина концовочная, многоволновая |
| любой Никитин черновик из последних коммитов | дополнительно |

**Чек-лист каждой карты:**

1. Load в редактор → ошибок нет, toast'ы только ожидаемые WARN'ы.
2. WaveSwitcher показывает все волны.
3. Переключаться между волнами → grid переключается, поля Wave-секции корректны.
4. Триггеры (если есть) — в level-секции списком, wave-mirror показывает релевантные.
5. Save → JSON `version: 3`, новые поля присутствуют.
6. Reload → idempotent diff (после нормализации).
7. Playtest этой карты — нет регрессий относительно того что было в v2.

Smoke-чек-лист попадает в `tasks.md` Φ-12 как T-061-N задачи.

**Объём:** smoke-only.

---

## Φ-13. Docs

**Файл 1:** `docs/systems/level-editor/dialogue-triggers.md` (новый).

Содержание:
- Концепт триггера (одна строка из 039 + ссылка на спек).
- Таблица CURATED_EVENTS с семантикой (когда стреляет, какие conditions релевантны).
- Разница `id` vs `dialogue_id` — explicit пример с двумя триггерами с одним dialogue_id и разными conditions.
- Conditions cookbook: «срабатывает на 3+ ходу wave 2», «10% chance», «cleared в ≤3 хода», etc.
- Снимки экрана UI WaveSettingsPanel level-секции.

**Файл 2:** `data/maps/_schema.md` (обновление если есть; иначе создать).

Содержание:
- Top-level fields: `name`, `version`, `tileset_path`, `waves[]`, `dialogue_triggers[]`, `music_config`.
- Wave entry: ссылка на §7 design.md + текущий список полей v3.
- Spawner entry: список полей v3.
- Migration notes: что меняется v2→v3, что forward-only.

**Объём:** docs ~150 строк суммарно.

---

## Глобальные риски

- **R-061-13: WaveSettingsPanel становится монолитом 700 LOC.** Soft cap 600 нарушится. Mitigation: extract trigger CRUD в `wave_dialogue_section.gd` если на Φ-7 размер угрожает. Решать на месте.
- **R-061-14: Bool→String миграция повсеместно сломает что-то незамеченное.** Audit Φ-2 покрывает 6 точек, но могут быть и другие (например в JSON-обработке или сторонних читалках). Mitigation: расширенный grep по `is_special` в качестве части тасок Φ-2; если найдены новые — добавить в audit list.
- **R-061-15: advance_mode runtime ломает существующий gameplay.** Default `"timer"` обеспечивает обратную совместимость, но если новые гарды (`_waiting_for_clear`) ошибочно срабатывают — wave navigation в продакшн картах может зависнуть. Mitigation: AC36 smoke включает playthrough существующих карт, проверка что wave-progression идентична до/после.

## Открытые вопросы для имплементации

- **OQ-061-IMPL-1:** какой именно сигнал EventBus сообщает о clear? Resolved в Φ-3 первой задачей через grep. Если нет — расширяем EventBus.
- **OQ-061-IMPL-2:** `EventBus.toast` сигнал — точное имя/сигнатура. Проверить в `event_bus.gd` в первой имплементационной задаче.
- **OQ-061-IMPL-3:** dialogue_id picker filter — нужен ли. Defer до плейтеста; если дiaлог-список больше 30 — добавить отдельным таском.

→ См. [`tasks.md`](tasks.md).
