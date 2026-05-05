# 040-wave-skill-choice — plan

См. `spec.md` для acceptance + scope. Этот документ — **HOW**.

## File map

| Path | Status | Purpose |
|---|---|---|
| `scripts/core/maps/level_data.gd` | edit | Per-wave `skill_offer` пишется/читается through `waves[i]` Dictionary. Validate-rules. |
| `data/maps/_schema.md` | edit | +секция `waves[i].skill_offer`. |
| `data/skill_offer_pools/basic.json` | new | Sample pool с 6-8 скиллами из `data/skills/`. |
| `data/skill_offer_pools/_schema.md` | new | Документация pool format'а. |
| `scripts/runtime/skill_offer_controller.gd` | new | Autoload. Pool scan + flow controller + apply logic. |
| `scripts/runtime/player_skill_adapter.gd` | new (only if needed) | Tonkий wrapper над PlayerSkillSet/slots если в core нет публичного API для add/upgrade/replace. |
| `scripts/infrastructure/event_bus.gd` | edit | +2 signals: `skill_offer_about_to_open(idx, count, pool_id)`, `skill_offer_closed(idx, picked_id, mode)`. |
| `project.godot` | edit | +1 autoload: `SkillOfferController` после `SkillDatabase` (или эквивалент). |
| `scenes/ui/skill_offer_modal.tscn` | new | Modal overlay (Control + CenterPanel + cards row). |
| `scripts/presentation/ui/skill_offer_modal.gd` | new | Modal logic — open/close, await pick, replace-slot submenu. |
| `scenes/ui/skill_offer_card.tscn` | new | Один card prefab (icon + name + mode badge + mood + desc). |
| `scripts/presentation/ui/skill_offer_card.gd` | new | Card script — bind data, hover/click, emit `card_clicked`. |
| `scripts/presentation/dev/wave_panel.gd` | edit | +SkillOfferSection collapsible. |
| `scenes/dev/wave_panel.tscn` | edit | +UI nodes для секции. |
| `scripts/presentation/ui/wave_timeline.gd` | edit | +marker рендер для skill_offer (EDIT и RUNTIME). |
| `scripts/presentation/ui_theme.gd` | edit | +`SKILL_OFFER_MARKER_COLOR`, `SKILL_OFFER_MARKER_RADIUS`. |
| `data/maps/sample_skill_offer.json` | new | Smoke-уровень. |

## Pool: scan + cache

```gdscript
# scripts/runtime/skill_offer_controller.gd, autoload "SkillOfferController"
extends Node

const POOLS_DIR := "res://data/skill_offer_pools/"
var _pools: Dictionary = {}    # StringName -> Dictionary

func _scan_pools() -> void:
    var dir := DirAccess.open(POOLS_DIR)
    if dir == null: return
    dir.list_dir_begin()
    var fname := dir.get_next()
    while fname != "":
        if not dir.current_is_dir() and fname.ends_with(".json") and not fname.begins_with("_"):
            _load_pool(POOLS_DIR + fname)
        fname = dir.get_next()
    dir.list_dir_end()
    GameLogger.info("SkillOfferController", "loaded %d pools" % _pools.size())

func _load_pool(path: String) -> void:
    var text := FileAccess.get_file_as_string(path)
    var parsed = JSON.parse_string(text)
    if parsed == null or not (parsed is Dictionary): return
    var id: StringName = StringName(str(parsed.get("id", "")))
    if id == &"": return
    _pools[id] = parsed
```

Reload — добавим `_reload_pools()` метод и хоткей в editor для дизайнерского workflow (out_of_scope v1, можно расширить).

## Flow

```gdscript
func _on_wave_cleared(idx: int, _unused: int) -> void:
    if _level == null: return
    var offer: Variant = _level.waves[idx].get("skill_offer", null)
    if offer == null: return

    # ── 1. Build cards ──
    var pool_id: StringName = StringName(str(offer.get("pool", "")))
    var pool: Dictionary = _pools.get(pool_id, {})
    if pool.is_empty(): return
    var cards: Array = _build_cards(pool, offer)
    if cards.is_empty(): return

    # ── 2. Wait for any in-flight dialog (039 chained `play_mode=play`) ──
    EventBus.skill_offer_about_to_open.emit(idx, cards.size(), pool_id)
    if DialogueManager.is_playing():
        await EventBus.dialogue_finished

    # ── 3. Open modal, pause game, await player decision ──
    get_tree().paused = true
    var picked: Dictionary = await _open_modal(cards, offer)
    get_tree().paused = false

    # ── 4. Apply to player skill set ──
    if picked.get("mode", &"skipped") != &"skipped":
        _apply_pick(picked)

    # ── 5. Notify, allow 039 closed-trigger to chain ──
    EventBus.skill_offer_closed.emit(idx, picked.get("skill_id", &""), picked.get("mode", &"skipped"))
```

**Pause при playing dialog.** Один awkward edge-case: `get_tree().paused = true` пока DialogueManager отыгрывает сцену из 039 trigger'а на `skill_offer_about_to_open`. Решение: **сначала ждём dialogue_finished, потом pause**. Это слегка extends gap между `wave_cleared` и `wave_about_to_start`, но семантически чище — pause фрэймит только сам выбор.

## Card building

```gdscript
func _build_cards(pool: Dictionary, offer: Dictionary) -> Array:
    var skills_in_pool: Array = pool.get("skills", []) as Array
    var weights: Dictionary = pool.get("weights", {}) as Dictionary
    var exclude_owned: bool = bool(offer.get("exclude_owned", false))
    var allow_upgrade: bool = bool(offer.get("allow_upgrade", true))
    var allow_replace: bool = bool(offer.get("allow_replace", true))
    var count: int = int(offer.get("count", 3))

    var owned: Dictionary = _player_skill_adapter().owned_skills_dict()  # {skill_id: Skill}

    # Filter step: drop missing-from-DB; conditionally drop owned.
    var candidates: Array = []
    for sid in skills_in_pool:
        var sn: StringName = StringName(str(sid))
        if not SkillDatabase.has_skill(sn):  # API: TBD
            GameLogger.warn_once("SkillOfferController", "skill '%s' missing — skip" % sn)
            continue
        if exclude_owned and owned.has(sn) and not allow_upgrade and not allow_replace:
            continue
        candidates.append({
            "id": sn,
            "weight": float(weights.get(str(sid), 1.0)),
        })
    if candidates.is_empty():
        return []

    # Sample N unique by weight.
    var picked_ids: Array = _weighted_sample_unique(candidates, count)

    # Map each picked id to (skill, mode).
    var cards: Array = []
    for pid in picked_ids:
        var card: Dictionary = _make_card_for(pid, owned, allow_upgrade, allow_replace)
        if card.is_empty():
            continue
        cards.append(card)
    return cards


func _make_card_for(id: StringName, owned: Dictionary, allow_up: bool, allow_repl: bool) -> Dictionary:
    var skill: Skill = SkillDatabase.get_skill(id)  # API: TBD
    if skill == null:
        return {}
    if not owned.has(id):
        return {"skill_id": id, "skill": skill, "mode": &"add"}
    # Owned — try upgrade first
    if allow_up and _player_skill_adapter().can_upgrade(id):
        return {"skill_id": id, "skill": skill, "mode": &"upgrade",
                "next_level": owned[id].level + 1}
    if allow_repl:
        return {"skill_id": id, "skill": skill, "mode": &"replace"}
    return {}  # owned, no path forward — drop card
```

## Apply pick

```gdscript
func _apply_pick(picked: Dictionary) -> void:
    var adapter: Node = _player_skill_adapter()
    var mode: StringName = picked.get("mode", &"add")
    var sid: StringName = picked.get("skill_id", &"")
    match mode:
        &"add":
            adapter.add_skill(sid)
        &"upgrade":
            adapter.upgrade_skill(sid)
        &"replace":
            var slot: int = int(picked.get("slot_index", -1))
            adapter.replace_slot(slot, sid)
        _:
            pass  # skipped
    # 038 — recompute mood after skill change. Editor controller already
    # does this via sync_player_skills_from_slots; just ensure it happens.
    if Engine.has_singleton("MoodTracker") or _has_autoload("MoodTracker"):
        MoodTracker.recompute_from_skills(adapter.owned_skills_array())
```

## PlayerSkillAdapter

Если в кодовой базе уже есть public API на `Player` actor / godmode_controller / другом scope — используем напрямую. Если **нет** — создаём `scripts/runtime/player_skill_adapter.gd`:

```gdscript
class_name PlayerSkillAdapter
extends Object  # not Node — instance-less helper

# Single source of truth — finds player Actor + reads/writes its skills.
# All methods static-ish via lazy-found node ref.

static func _player() -> Node:
    # Find player by group "player" (godmode/arena both register player there)
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null: return null
    var grp: Array = tree.get_nodes_in_group("player")
    return grp.front() if not grp.is_empty() else null

static func owned_skills_array() -> Array:
    var p := _player()
    if p == null or not p.has_method("get_skills"): return []
    return p.get_skills()

static func owned_skills_dict() -> Dictionary:
    var d: Dictionary = {}
    for s in owned_skills_array():
        if s != null and s.has_method("get") and "id" in s:
            d[s.id] = s
    return d

static func add_skill(id: StringName) -> void:
    var p := _player()
    if p == null or not p.has_method("set_skills"): return
    var skill: Skill = SkillDatabase.get_skill(id)
    if skill == null: return
    var current: Array = owned_skills_array()
    current.append(skill)
    p.set_skills(current)

static func can_upgrade(id: StringName) -> bool:
    var d := owned_skills_dict()
    return d.has(id) and d[id].has_method("get") and "level" in d[id]

static func upgrade_skill(id: StringName) -> void:
    var d := owned_skills_dict()
    if not d.has(id): return
    d[id].level += 1
    # Re-set via set_skills to trigger any listeners
    var p := _player()
    if p != null and p.has_method("set_skills"):
        p.set_skills(owned_skills_array())

static func replace_slot(slot: int, id: StringName) -> void:
    var p := _player()
    if p == null: return
    var current: Array = owned_skills_array()
    if slot < 0 or slot >= current.size(): return
    var skill: Skill = SkillDatabase.get_skill(id)
    if skill == null: return
    current[slot] = skill
    if p.has_method("set_skills"):
        p.set_skills(current)
```

**Verify in T002** при имплементации — реальный API игрока. Если `get_skills/set_skills` не существуют — расширяем adapter под фактическое API. Не правим core.

## Modal scene

`scenes/ui/skill_offer_modal.tscn`:

```
SkillOfferModal (Control, mouse_filter=STOP, fullscreen anchors)
├── Backdrop (ColorRect, semi-transparent, mouse_filter=STOP)
└── CenterPanel (PanelContainer, centered)
    ├── HeaderLabel ("Choose a skill")
    ├── CardsRow (HBoxContainer)
    └── FooterRow (HBoxContainer)
        └── SkipButton (visible only if allow_skip)
```

`skill_offer_modal.gd` API:

```gdscript
signal player_picked(result: Dictionary)  # {skill_id, mode, slot_index?}

func open(cards: Array, offer: Dictionary) -> void:
    # Instantiate one SkillOfferCard per cards[i], wire card_clicked,
    # show, focus first card. SkipButton.visible = offer.allow_skip.
    ...

# replace flow:
func _on_card_clicked(card_data: Dictionary) -> void:
    if card_data.mode == &"replace":
        _show_slot_picker(card_data.skill_id)  # second screen — pick slot
    else:
        player_picked.emit(card_data)
        queue_free()
```

`skill_offer_card.tscn`:

```
SkillOfferCard (PanelContainer, takes Skill + mode in bind())
├── Icon (TextureRect)
├── Name (Label, applies tr() on Skill.name loc-key)
├── ModeBadge (Label — "ADD" / "UPGRADE → LV2" / "REPLACE")
├── MoodRow (HBoxContainer of small icons)
└── Desc (RichTextLabel, BBCode, tr() on Skill.desc)
```

ButtonControl behaviour — стандартный `gui_input` + visual hover state через UiTheme.

## Editor — WavePanel section

В `scenes/dev/wave_panel.tscn` дополняем `VBox`:

```
VBox
├── HeaderRow (existing)
├── SkillOfferSection (CollapsibleVBox — реализуется как VBoxContainer
│   с toggle-button заголовком; если в проекте нет helper — пишем простой
│   VBox с  CheckButton на header'е и `vbox.visible = checked`)
│   ├── EnableCheckbox
│   ├── PoolDropdown (OptionButton)
│   ├── CountSpinbox (SpinBox)
│   ├── AllowUpgrade / AllowReplace / AllowSkip / ExcludeOwned (CheckBox-row)
│   └── PreviewBtn
└── TimelineRow (existing)
```

`wave_panel.gd` дописывается:

```gdscript
@onready var _so_enable: CheckBox = $VBox/SkillOfferSection/EnableCheckbox
@onready var _so_pool: OptionButton = $VBox/SkillOfferSection/PoolDropdown
@onready var _so_count: SpinBox = $VBox/SkillOfferSection/CountSpinbox
# ... etc

signal skill_offer_changed(wave_index: int, offer: Variant)  # offer = Dictionary | null


func _refresh_skill_offer_section() -> void:
    if _level == null: return
    var idx: int = _level.get_active_wave_index()
    var offer: Variant = _level.waves[idx].get("skill_offer", null)
    var enabled: bool = offer != null
    _so_enable.button_pressed = enabled
    _so_pool.disabled = not enabled
    # ... toggle visibility / disabled state
    if enabled:
        _so_pool.select(_pool_dropdown_index_for(StringName(str(offer.get("pool", "")))))
        _so_count.value = int(offer.get("count", 3))
        # ... etc
```

При любом change → собираем Dictionary → `skill_offer_changed.emit(idx, offer_dict)`.

В `map_editor_controller.gd`:

```gdscript
# В _wire_wave_panel():
_wave_panel.skill_offer_changed.connect(_on_skill_offer_changed)

func _on_skill_offer_changed(wave_index: int, offer: Variant) -> void:
    _history.push(_level)
    if offer == null:
        _level.waves[wave_index].erase("skill_offer")
    else:
        _level.waves[wave_index]["skill_offer"] = offer
    _refresh_timeline_skill_offer_markers()
    _mark_dirty()
```

**Целевой инкремент в editor controller ≤ 30 строк.** Pool dropdown заполнение — внутри WavePanel (`SkillOfferController._pools.keys()` через прямой autoload-lookup — это OK для редактора-only кода).

## Timeline marker

В `wave_timeline.gd` — после рендера якорей:

```gdscript
func _draw_skill_offer_markers() -> void:
    if _level == null: return
    for i in _level.waves.size():
        if not _level.waves[i].has("skill_offer"): continue
        # Position: rightmost edge of waves[i] gap area (just before waves[i+1] anchor)
        var x: float = _anchor_positions[i] + (_gap_width(i) * 0.85)
        var y: float = BAR_Y - 14.0
        var c: Color = UiThemeScript.SKILL_OFFER_MARKER_COLOR
        draw_circle(Vector2(x, y), UiThemeScript.SKILL_OFFER_MARKER_RADIUS, c)
        draw_string(_font, Vector2(x-5, y+4), "🎴", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
```

Hover/click — добавляем тестирование на маркеры в `_gui_input` (после анкер-теста). Click → emit `skill_offer_marker_clicked(wave_index)` → editor controller активирует эту волну в WavePanel + раскрывает SkillOfferSection.

## Sample pool

`data/skill_offer_pools/basic.json`:

```json
{
  "id": "basic",
  "label_key": "skill_offer.pool.basic.name",
  "skills": [
    "ball_throw",
    "berry_throw",
    "honey_cold",
    "spores",
    "summon_bee",
    "weaken",
    "nice_smell",
    "sting"
  ]
}
```

Skill ids копированы из `data/skills/*.json` (см. CSV — ball_throw, berry_throw, honey_cold, spores, summon_bee, weaken, nice_smell, sting all exist). Если какой-то id не найдётся — runtime drop, smoke логирует.

## Test plan

Smoke:

1. Open `map_editor.tscn`, новый уровень с 2 волнами. WavePanel показывает SkillOfferSection (collapsed).
2. Active wave = 0. Раскрываем секцию, EnableCheckbox = on. Pool=basic, count=3, allow_skip=on. Save as `test_offer.json`.
3. Маркер 🎴 появился в gap'е после волны 0 на таймлайне.
4. Playtest → волна 0 кларится → пауза → модалка с 3 cards → выбираем «add ball_throw» → пауза снимается → волна 1 стартует → ball_throw в слоте.
5. Возвращаемся в editor, ставим volna 1 тоже с offer (count=3, allow_replace=on). Save. Playtest → проходим обе волны → видим обе модалки.
6. Volna 0 offer + 039 trigger на `skill_offer_about_to_open` `play_mode=play` → диалог играется ДО модалки (не одновременно).
7. allow_replace=on, играем чтобы все слоты заняты → видим карточку «replace Q with X» → клик → submenu выбора слота → Q клик → X в Q после применения.

## Risk register

- **R1 (PlayerSkillSet API gap).** Самый большой риск. Mitigation: PlayerSkillAdapter (см. выше). Если adapter не находит API — режем upgrade и replace одной коммитом, оставляем только add.
- **R2 (Replace UX confusion).** Submenu выбора слота — легко промахнуться. Mitigation: highlight соответствующих slot-кнопок в HUD (через EventBus → SlotBar) + Cancel button в submenu.
- **R3 (Pause + DialogueManager).** Если диалог открыт через 039 trigger, а offer открывается одновременно — race. Mitigation: модалка ждёт `dialogue_finished` перед `paused=true` (см. flow). Тестируется AC-S15.
- **R4 (Pool < count).** count=3, в пуле 2 уникальных не-owned скилла — отдаём 2 карточки. UI должен это пережить (HBoxContainer auto-fits). Тест.
- **R5 (Save между уровнями).** В рамках одного run пик скилла удерживается в Player. Между level transitions (если они появятся в roguelike) — не наша задача.
