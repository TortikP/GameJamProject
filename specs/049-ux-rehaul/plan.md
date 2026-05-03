# 049-ux-rehaul — plan

Файл-за-файлом diff. Все пути относительны корню репы. Все правки — в `scripts/presentation/` или `scenes/`. **Core не трогается.**

## Audit (зачем выпиливаем)

```
$ grep -rn "_ctrl.select\|.select(actor)\|select(target_actor)" scripts/
scripts/presentation/godmode/godmode_input.gd:218:    _ctrl.select(target_actor)
scripts/presentation/godmode/godmode_setup.gd:319:    _ctrl.select(_ctrl.player)

$ grep -rn "ActorInspector\|inspector\." scripts/presentation/godmode/
# only godmode_controller / godmode_setup own these — no external readers

$ grep -rn "HexInspectorSubpanel" scripts/ scenes/
# 0 references outside its own file — confirmed dead parallel

$ grep -rn "IntentArrow" scripts/
scripts/presentation/intent_arrow.gd:1:extends Node2D
scripts/presentation/godmode/telegraph_renderer.gd:7:const INTENT_ARROW_SCRIPT := preload(...)
# only telegraph_renderer uses it — single replace site
```

→ Безопасно удалять при условии что мы заменим callsites.

## Новые файлы

### `scripts/presentation/skill_icon_resolver.gd` (~30 строк)

Static helper, вынесен из `skill_offer_card._resolve_icon`. Используется telegraph_hex + hex_tooltip + skill_offer_card (последний переключаем на helper, чтобы не было трёх копий логики).

```gdscript
class_name SkillIconResolver
extends RefCounted
## Resolve a Skill's icon string to Texture2D, or null. Static-only.
##
## Usage:
##   const SkillIconResolver = preload("res://scripts/presentation/skill_icon_resolver.gd")
##   var tex: Texture2D = SkillIconResolver.resolve(skill)
##
## Patterns supported (matches data/skills/*.json convention):
##   "res://path/to.png"        → load directly
##   "icons/skills/foo.png"     → "res://assets/icons/skills/foo.png"
##   "skills/foo.png"           → "res://assets/skills/foo.png"
##
## Returns null if skill is null, icon empty, or no path resolves.
static func resolve(skill) -> Texture2D
```

### `scripts/presentation/hex_tooltip.gd` + `scenes/ui/hex_tooltip.tscn` (~120 строк gd)

Cursor-anchored tooltip. **Не наследует** `TooltipPanel` — другая семантика (per-row table, не title+body).

```gdscript
extends PanelContainer
## HexTooltip — cursor-anchored summary of all incoming actions on a hovered hex.
##
## Driven by HoverDispatcher (refresh_hex_tooltip(coord)). One row per
## (actor, ability) pair where coord ∈ ability's affected hexes.
##
## Suppressed during EventBus.ui_modal_opened (same as TooltipPanel).

const SkillIconResolver = preload("res://scripts/presentation/skill_icon_resolver.gd")
const SkillFormatter    = preload("res://scripts/presentation/skill_formatter.gd")

@onready var _rows_vbox: VBoxContainer = $VBox/RowsVBox

# Per-row: HBox of [actor_label, icon_rect+name_label, consequence_label].
# Reused via object pool — _ensure_rows(n) trims/grows.
var _rows: Array[HBoxContainer] = []
var _last_coord: Vector2i = Vector2i(-9999, -9999)
var _suppressed: bool = false

func show_for(rows: Array, mouse_pos: Vector2) -> void
func hide_tooltip() -> void
func _build_row(actor_name: String, skill: Skill, consequence: String) -> HBoxContainer
func _place_near_cursor(mouse_pos: Vector2) -> void  # mouse + (SP_2, -h - SP_2), clamp
```

`rows` argument shape: `Array[Dictionary]`, each `{actor_name: String, skill: Skill, consequence: String}`. HoverDispatcher собирает.

### `scripts/presentation/enemy_details_panel.gd` + `scenes/ui/enemy_details_panel.tscn` (~150 строк gd)

Top-right hover-driven panel. Горизонтальный layout.

```
┌────────────────────────────────────────────────────────┐
│ [portrait]  bee_2 [enemy]   ❤ 12/20   [🐝 sting CD0]  │
│             [slow] [poison]                            │
└────────────────────────────────────────────────────────┘
```

```gdscript
extends PanelContainer
## EnemyDetailsPanel — top-right hover-driven enemy info. No selection,
## no editing, no LMB. Driven by HoverDispatcher.refresh_enemy_details(actor_id).

@onready var _portrait_rect: TextureRect    = $HBox/Portrait
@onready var _name_label:    Label          = $HBox/Info/NameRow/NameLabel
@onready var _team_badge:    ColorRect      = $HBox/Info/NameRow/TeamBadge
@onready var _hp_label:      Label          = $HBox/Info/HpLabel
@onready var _status_strip:  HBoxContainer  = $HBox/Info/StatusStrip   # reuse status_icon_strip.tscn
@onready var _abilities_row: HBoxContainer  = $HBox/AbilitiesRow

var _actor: Actor = null

func bind(actor: Actor) -> void   # connects damaged + statuses_changed
func unbind() -> void             # disconnects, hides
```

Подписки на `actor.damaged` / `actor.statuses_changed` — single source of truth для обновлений (не per-frame).

### `scripts/presentation/enemy_move_path.gd` (~70 строк)

Заменяет `intent_arrow.gd`. Тот же стиль, что `move_range_overlay._draw_hover_path:294-308`, но красный.

```gdscript
extends Node2D
## EnemyMovePath — polyline through hex centers from enemy's coord to its
## planned move_intent_coord. Drawn red (SEM_DAMAGE). One per enemy with a
## planned move; spawned/destroyed by TelegraphRenderer.refresh().
##
## Path is computed via grid.find_path_around with live actor blocks — same
## set the AI uses, so the visual matches reality.

var _grid: HexGrid = null
var _path: Array[Vector2i] = []

func setup(grid: HexGrid, path: Array[Vector2i]) -> void
func _draw() -> void   # polyline + arrowhead at last segment, drop shadow
```

### `specs/049-ux-rehaul/{spec.md, plan.md, tasks.md}`

Этот пакет.

## Изменяемые файлы

### `scripts/presentation/skill_formatter.gd`

Добавить новый метод; старый сохранить как fallback и для legacy callers.

```gdscript
## Human-readable skill description. Source of truth: Localization.t(skill.tooltip).
## Falls back to format_skill (debug-style structural reconstruction) when
## tooltip key missing or unresolved.
##
## Use this for: PSP SpellDesc, HexTooltip rows, EnemyDetailsPanel ability hover.
## Use format_skill for: dev/debug-only contexts.
static func format_skill_human(skill) -> String:
    if skill == null:
        return ""
    var key: String = String(skill.tooltip)
    if key == "":
        return format_skill(skill)
    var resolved: String = Localization.t(key, "")
    # Localization.t returns the key itself when missing — sentinel via fallback="".
    if resolved == "":
        return format_skill(skill)
    # Append CD if active.
    if skill.cooldown > 0:
        var cd_remaining: int = int(skill.get("_cd_remaining"))
        if cd_remaining > 0:
            resolved += " " + Localization.tf("ui_skill_cooldown_remaining",
                    [cd_remaining, skill.cooldown], "(CD %d/%d)")
    return resolved
```

Дополнительно — `format_consequence(skill)` для HexTooltip 3-й колонки. Возвращает короткую строку: `"-N HP"`, `"+N HP"`, `"Slowed (3t)"`, etc. — на базе `skill.behaviour_tags[0]` + первый `DamageEffect.damage` / first `status_id` parsed. ≤30 символов, без markup.

### `scripts/presentation/player_status_panel.gd`

```gdscript
# AC-8: hover beats active.
var _active_skill = null   # Skill set by set_active_spell
var _hover_skill = null    # Skill set by set_hover_spell

func set_active_spell(skill_or_ability) -> void:
    _active_skill = skill_or_ability
    _refresh_spell_section()

func set_hover_spell(skill) -> void:   # NEW
    _hover_skill = skill
    _refresh_spell_section()

func _refresh_spell_section() -> void:
    var s = _hover_skill if _hover_skill != null else _active_skill
    if s == null:
        _spell_section.visible = false
        return
    _spell_name.text = Localization.t(String(s.name), String(s.id))
    _spell_desc.text = SkillFormatter.format_skill_human(s)   # AC-1
    _spell_section.visible = true
```

### `scripts/presentation/slot_bar.gd`

Добавить:
```gdscript
signal slot_hovered(idx: int)
signal slot_unhovered(idx: int)
```

В каждом `SlotButton` (или эквиваленте) — connect `mouse_entered` / `mouse_exited` → emit на bar level.

Подписку в godmode_setup.gd:
```gdscript
_ctrl.slot_bar.slot_hovered.connect(_ctrl._on_slot_hovered)
_ctrl.slot_bar.slot_unhovered.connect(_ctrl._on_slot_unhovered)
```

В `godmode_controller.gd`:
```gdscript
func _on_slot_hovered(idx: int) -> void:
    var psp = _get_player_status_panel()
    if psp == null: return
    var sk: Skill = slot_bar.get_slot(idx) as Skill
    if psp.has_method("set_hover_spell"):
        psp.set_hover_spell(sk)

func _on_slot_unhovered(_idx: int) -> void:
    var psp = _get_player_status_panel()
    if psp != null and psp.has_method("set_hover_spell"):
        psp.set_hover_spell(null)
```

### `scripts/presentation/telegraph_hex.gd`

Расширение `_draw()`. Новое поле + skill ref.

```gdscript
const SkillIconResolver = preload("res://scripts/presentation/skill_icon_resolver.gd")

## AC-5: skill ref drives icon (texture) or letter fallback. Set by
## TelegraphRenderer alongside semantic_tag/damage. Null → no icon (legacy
## or non-skill telegraphs).
var icon_skill: Skill = null:
    set(value):
        icon_skill = value
        queue_redraw()

func _draw() -> void:
    # ... existing polygon + outline ...
    if outline_only:
        return
    _draw_icon()           # NEW — center of hex, 32×32 area
    _draw_damage_label()   # MOVED — was -tile.y/2 - 6, now bottom-center hex

func _draw_icon() -> void:
    if icon_skill == null: return
    var tex: Texture2D = SkillIconResolver.resolve(icon_skill)
    if tex != null:
        draw_texture_rect(tex, Rect2(-16, -16, 32, 32), false)
        return
    # Letter fallback — first char of localized skill name.
    var name_str: String = Localization.t(String(icon_skill.name), String(icon_skill.id))
    if name_str.is_empty(): return
    var letter: String = name_str.substr(0, 1).to_upper()
    var font: Font = ThemeDB.fallback_font
    var fs: int = UiTheme.FS_NUM_LARGE
    var sz: Vector2 = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
    var pos: Vector2 = Vector2(-sz.x * 0.5, sz.y * 0.3)   # baseline-corrected ~center
    draw_string_outline(font, pos, letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fs,
            UiTheme.WORLD_TEXT_OUTLINE_SIZE, UiTheme.WORLD_TEXT_OUTLINE_COLOR)
    draw_string(font, pos, letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, UiTheme.TEXT)

func _draw_damage_label() -> void:
    if damage <= 0: return
    # Was: pos.y = -tile_size.y * 0.5 - 6.0  (above hex)
    # Now: bottom-center inside hex, since icon owns the center.
    var pos: Vector2 = Vector2(-size.x * 0.5, tile_size.y * 0.35)
    # ... rest unchanged ...
```

### `scripts/presentation/godmode/telegraph_renderer.gd`

В `refresh()`:
1. При создании primary `TelegraphHex` (line 147–154) — `hex.set("icon_skill", skill)`.
2. Удалить `INTENT_ARROW_SCRIPT` preload + spawning block (line 132–143). Заменить на `EnemyMovePath` spawn:
```gdscript
if mv != Vector2i(-1, -1):
    var enemy_coord: Vector2i = grid.get_coord(enemy.actor_id)
    if enemy_coord != Vector2i(-1, -1) and enemy_coord != mv:
        var blocked: Array = _live_blocked_coords(registry, enemy)
        var path: Array = grid.find_path_around(enemy_coord, mv, blocked)
        if path.size() >= 2:
            var path_node: Node2D = ENEMY_MOVE_PATH_SCRIPT.new()
            path_node.position = Vector2.ZERO
            path_node.z_index = 4
            grid.add_child(path_node)
            var typed: Array[Vector2i] = []
            for c in path: typed.append(c)
            path_node.setup(grid, typed)
            _intent_arrows[enemy.actor_id] = path_node   # rename: _enemy_move_paths
```

Helper `_live_blocked_coords(registry, exclude)` — same shape as in `hover_dispatcher.refresh_hover_path:130-139`. Можно вынести в общий helper в `hover_dispatcher` (uses Array — typed Array[Vector2i] painful; Array OK).

### `scripts/presentation/godmode/hover_dispatcher.gd`

Большая ребалансировка `_process` / `update_castability`:

1. **Убрать** `refresh_intent_tooltip(target_id)` целиком (lines 156–192). Также `_hover_intent_actor_id` field.
2. **Добавить** `refresh_hex_tooltip(coord)`:
```gdscript
var _last_hex_tooltip_coord: Vector2i = Vector2i(-9999, -9999)

func refresh_hex_tooltip(coord: Vector2i) -> void:
    var tip: Node = get_node_or_null("../../HUD/HexTooltip")
    if tip == null: return
    if coord == _last_hex_tooltip_coord and tip.visible:
        return   # no-op: same hex, already showing/hiding
    _last_hex_tooltip_coord = coord
    if coord == Vector2i(-1, -1):
        tip.hide_tooltip()
        return
    var rows: Array = _build_hex_tooltip_rows(coord)
    if rows.is_empty():
        tip.hide_tooltip()
        return
    tip.show_for(rows, _ctrl.get_viewport().get_mouse_position())

func _build_hex_tooltip_rows(coord: Vector2i) -> Array:
    var rows: Array = []
    var grid: HexGrid = _ctrl.grid
    var registry: ActorRegistry = _ctrl.registry
    var player: Actor = _ctrl.player

    # Player preview — IFF active slot AND coord in valid range AND can_apply.
    var slot_bar: Node = _ctrl.slot_bar
    var active_idx: int = slot_bar.get_active() if slot_bar != null else -1
    if active_idx != -1 and player != null:
        var skill: Skill = slot_bar.get_slot(active_idx) as Skill
        if skill != null and not skill.abilities.is_empty():
            var ab: Ability = skill.abilities[0]   # 0-step preview, matches refresh_overlay
            if _hex_in_ability_effect(player, ab, coord, grid, registry):
                rows.append({
                    "actor_name": "player",
                    "skill": skill,
                    "consequence": SkillFormatter.format_consequence(skill),
                })
    # Enemy intents — every AI actor whose intent's primary or AoE area covers coord.
    for actor_v in registry.all():
        if not (actor_v is Actor): continue
        var enemy: Actor = actor_v
        if enemy == player or not enemy.is_alive(): continue
        var ci: CastIntent = enemy.cast_intent as CastIntent
        if ci == null or not ci.is_valid(): continue
        var skill: Skill = SkillDatabase.get_skill(ci.skill_id)
        if skill == null: continue
        if not _intent_covers_coord(enemy, ci, skill, coord, grid):
            continue
        rows.append({
            "actor_name": String(enemy.actor_id),
            "skill": skill,
            "consequence": SkillFormatter.format_consequence(skill),
        })
    return rows
```

Helpers — `_hex_in_ability_effect` уточняет «конкретный hex входит в affected list для cast на cursor-coord» (только для preview), `_intent_covers_coord` использует ту же `ability.area.get_affected_hexes` логику, что telegraph_renderer.refresh() уже строит (можно вытащить общий helper, но в первой итерации — дублирование ОК; см. tasks T-cleanup).

3. **Добавить** `refresh_enemy_details(target_id)`:
```gdscript
var _last_enemy_details_id: StringName = &""

func refresh_enemy_details(target_id: StringName) -> void:
    var registry: ActorRegistry = _ctrl.registry
    var panel: Node = get_node_or_null("../../HUD/EnemyDetailsPanel")
    if panel == null: return
    var new_id: StringName = &""
    if target_id != &"" and registry != null:
        var hov: Actor = registry.get_actor(target_id)
        if hov != null and hov.team == &"enemy" and hov.is_alive():
            new_id = target_id
    if new_id == _last_enemy_details_id: return
    _last_enemy_details_id = new_id
    if new_id == &"":
        if panel.has_method("unbind"): panel.unbind()
        return
    var actor: Actor = registry.get_actor(new_id)
    if panel.has_method("bind"): panel.bind(actor)
```

4. **Update** `_process(_delta)` chain:
```gdscript
func _process(_delta: float) -> void:
    update_castability()   # contains zone preview, slot tints, hp damage preview
    var coord: Vector2i = _ctrl.grid.coord_under_mouse() if _ctrl.grid != null else Vector2i(-1, -1)
    var target_id: StringName = _ctrl.grid.get_actor_at(coord) if coord != Vector2i(-1, -1) else &""
    refresh_hover_path(coord)
    refresh_hex_tooltip(coord)
    refresh_enemy_details(target_id)
```

(`update_castability` остаётся — там логика slot-castability, hp-bar damage preview, zone AoE preview. Только `refresh_intent_tooltip` оттуда выпиливается.)

### `scripts/presentation/cast_range_overlay.gd`

Добавить grey-out invalid hexes. Текущий `_coords` — все range-hexes; делим на два списка.

```gdscript
var _coords_valid:   Array[Vector2i] = []
var _coords_invalid: Array[Vector2i] = []

func show_range_for_ability(caster: Actor, ability: Ability) -> void:
    hide_range()
    if _grid == null or caster == null or ability == null or ability.target == null:
        return
    var caster_coord: Vector2i = _grid.get_coord(caster.actor_id)
    if caster_coord == Vector2i(-1, -1): return
    var registry: Node = caster.get_node_or_null("../..")  # find via grid? See note
    var range_hexes: Array[Vector2i] = ability.target.get_range_hexes(caster_coord, _grid)
    for c in range_hexes:
        var ctx: Dictionary = {
            "registry": _resolve_registry(),
            "grid": _grid,
            "target_id": _grid.get_actor_at(c),
            "target_coord": c,
            # actors_node + resolver only matter for CreateEffect — skip for validity check
        }
        if ability.target.resolve(caster, ctx) != null:
            _coords_valid.append(c)
        else:
            _coords_invalid.append(c)
    _color = UiTheme.SEM_DEBUFF
    queue_redraw()

func _draw() -> void:
    # ... existing valid loop ...
    var invalid_color: Color = Color(UiTheme.GREY_50.r, UiTheme.GREY_50.g, UiTheme.GREY_50.b, 0.30)
    for c in _coords_invalid:
        # same outline draw, dim color
```

`_resolve_registry()` — overlay живёт под HexGrid, registry — sibling под Godmode root. Резолвим через `get_tree().root.find_child("ActorRegistry", true, false)` cached, или (cleaner) — добавить `setup(grid, registry)` extension. **Пойдём по второму пути**: API становится `setup(grid, registry)`, godmode_setup передаёт оба ref'а.

### `scripts/presentation/godmode/godmode_controller.gd`

Удалить:
- `var _selected: Actor` поле
- `func select(actor)` (lines 97–105)
- `func deselect_to_player()` (lines 108–109)
- `func inspect_hex(coord)` (lines 112–121)
- `func bind_hex_at(coord)` (lines 124–132)
- `func _on_inspector_speed_changed(_actor)` (lines 158–159)
- `func _on_actor_died_for_selection(id)` (lines 162–164)
- `var inspector` поле + `@export var inspector_path` (line 20, 27)
- `_get_player_status_panel`'s body НЕ трогаем — нужен ещё для AC-8 PSP hover.

Добавить:
- `func _on_slot_hovered(idx)` / `func _on_slot_unhovered(idx)` (см. выше).

### `scripts/presentation/godmode/godmode_input.gd`

В `_request_cast_active` (lines 215–220), удалить `else`-ветку с `_ctrl.select(target_actor)` / `inspect_hex`:

```gdscript
# No active skill: nothing to do. (049: removed select-on-actor / inspect-hex).
if active_idx == -1:
    return
```

В Esc-handler (line 28–57): убрать selection-tier (lines 44–47). Финальный chain:
1. cast-FSM cancel
2. slot toggle off
3. pause menu

### `scripts/presentation/godmode/godmode_setup.gd`

- Удалить:
  - `_ctrl.inspector = ...` resolution (lines 101–104)
  - `_ctrl.inspector.speed_changed.connect(...)` (lines 117–118)
  - `_ctrl.inspector.hide()` fallback (line 124)
  - `_select_deferred()` (lines 318–319) и его call_deferred вызов выше

- Добавить:
  - resolve `EnemyDetailsPanel` + `HexTooltip` через `find_child` (или новые `@export NodePath` на controller — proжe)
  - `_ctrl.slot_bar.slot_hovered.connect(_ctrl._on_slot_hovered)` (после существующего `slot_activated.connect`)

### `scenes/dev/godmode.tscn`

- Удалить `[node name="ActorInspector" parent="HUD" instance=ExtResource("9_inspector")]` + соответствующий ext_resource.
- Удалить `inspector_path = NodePath("../HUD/ActorInspector")` строку.
- Добавить:
  - `[node name="EnemyDetailsPanel" parent="HUD" instance=ExtResource(N_eds)]` — top-right anchor (`anchor_left=1, anchor_right=1, offset_left=-560, offset_right=-16, offset_top=16, offset_bottom=72`).
  - `[node name="HexTooltip" parent="HUD" instance=ExtResource(N_ht)]` — без anchors (positioning runtime).

### `scripts/presentation/dev/tile_objects_smoke_controller.gd`

Один guard:
```gdscript
const _SMOKE_LOG_ENABLED: bool = false   # 049: silenced; flip to debug 018.
```

Все `GodmodeLogger.info(...)` оборачиваются в `if _SMOKE_LOG_ENABLED:`. Сами вызовы оставляются (это функционал smoke-теста, не мусор), просто молчат. F-toggle на keypress (если 018 нужно потестить — в другой ветке).

## Удаляемые файлы

```
scripts/presentation/godmode/actor_inspector.gd          # AC-3, AC-4
scripts/presentation/hex_inspector_subpanel.gd           # AC-9 (dead parallel)
scripts/presentation/intent_arrow.gd                     # AC-7 (replaced)
scenes/dev/actor_inspector.tscn                          # AC-3, AC-4
```

## Точки интеграции

### 029-feedback-polish (Andrey, merged)

- `req-6` (mob-hover tooltip + AoE telegraph shape): mob-hover tooltip заменяется на hex-tooltip + enemy-details. AoE shape outlines (secondary `outline_only` telegraph hexes) **сохраняются** — они покрывают «что захватит aoe» на гексах БЕЗ актёров; новый icon рисуется только на primary (где актёр или target_coord).
- `bonus-2` (hover-path для player): не трогаем.
- `req-3 / req-4` (move/cast range outlines): cast range расширяется AC-6 grey-out, иной поведенческой логики не меняем.

### 047-skill-fx-system (Egor, merged)

`FxDirector.sync_telegraph_loops` — без изменений. Loop фильтр в TelegraphRenderer.refresh:175-185 продолжает работать как есть. Иконка на TelegraphHex рисуется поверх sprite-flash, ничего не ломает.

### 048-corpse-absorption (Egor, parallel branch)

Нет пересечений по файлам (048 — `corpse_manager.gd`, `corpse.gd`, `wave_controller.gd`, `godmode_camera.gd`). Branch'и можно мерджить независимо. Merge order — alphabetic, не критично.

### 040-wave-skill-choice (Andrey, merged)

`SkillOfferCard._resolve_icon` переносится в `SkillIconResolver.resolve(skill)`. SkillOfferCard теперь зовёт helper. Behavior identical.

## Performance

- HoverDispatcher уже бегает per-frame. Добавляем 2 операции:
  - hex_tooltip rebuild: O(N enemies) на смену hovered coord — не каждый кадр благодаря `_last_hex_tooltip_coord` guard. Раз в 0.x секунд при движении мыши.
  - enemy_details rebuild: O(1) на смену hovered actor — guard'итс `_last_enemy_details_id`.
- TelegraphHex._draw добавляет 1 texture draw + 0..1 string draw. ≤6 telegraph hexes на сцене типично; pessimist 20. Нечего оптимизировать.
- EnemyMovePath._draw: ≤N path segments × draw_line. Меньше, чем у player hover-path сейчас. ОК.

## Что не делаем (cut-list)

В порядке агрессивного отрезания, если время поджимает:

1. **HexTooltip 3-я колонка `consequence`** — оставить только `actor — skill name`. Игрок и так видит damage number на телеграфе.
2. **EnemyDetailsPanel portrait** — слот в layout есть, но `_portrait_rect.texture = null` всегда. Заглушка.
3. **AC-6 grey-out invalid** — оставить только valid range; UX чуть хуже, но cast click уже отлично работает (NoOp на invalid).
4. **AC-8 hover description в PSP** — отрезать; описание показывается только при выборе слота.
5. **Skill icon resolver helper** — оставить inline дубль в TelegraphHex + SkillOfferCard, не объединяя.
6. **Smoke log silencer** — забить, лог-spam терпимо, в production не виден.

Минимум shippable: AC-1 (human descriptions), AC-3 (kill select), AC-4 (corner panel хотя бы заглушка), AC-5 (icon на телеграфе с letter fallback), AC-7 (red enemy paths), AC-9 (cleanup). AC-2 (hex tooltip) — желательно, можно cut если совсем плохо.

## Touch budget

- Удалено: ~600 строк (actor_inspector + actor_inspector.tscn + hex_inspector_subpanel + intent_arrow + dead branches).
- Добавлено: ~400 строк (3 новых компонента + spec docs).
- Изменено: ~150 строк (formatter, telegraph_hex, hover_dispatcher, controller/setup/input slim).

Net: репа становится **меньше**.
