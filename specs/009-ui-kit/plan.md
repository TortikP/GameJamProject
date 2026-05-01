# 009-ui-kit — plan

**Owner:** Andrey
**Spec:** [`spec.md`](./spec.md) · **Status:** Draft, awaits Q-UI-1..Q-UI-5 closure → /tasks

## Архитектурный обзор

Три слоя:

```
┌─────────────────────────────────────────────────────────┐
│  Component scenes & scripts                             │
│  scenes/ui/*.tscn  +  scripts/presentation/*.gd         │
│  ─ each component a self-contained Control subtree     │
│  ─ pulls colors / sizes via UiTheme.X (no inline)      │
│  ─ exposes signals through EventBus, never direct refs │
└──────────────────────┬──────────────────────────────────┘
                       │ reads
┌──────────────────────▼──────────────────────────────────┐
│  UiTheme  (autoload, scripts/presentation/ui_theme.gd)  │
│  ─ Color constants  (BG_PANEL, SEM_DAMAGE, …)           │
│  ─ Spacing constants (SP_1..SP_6)                       │
│  ─ Font sizes        (FS_DISPLAY..FS_NUM_SMALL)         │
│  ─ Helpers           (make_*_stylebox, apply_label_*)   │
│  ─ Hot-reload        (F5 in editor → reload + signal)   │
└──────────────────────┬──────────────────────────────────┘
                       │ refs
┌──────────────────────▼──────────────────────────────────┐
│  Source of truth                                        │
│  specs/009-ui-kit/design/tokens.css                     │
│  ─ canonical CSS palette                                │
│  ─ ui_theme.gd MUST mirror this 1:1                     │
└─────────────────────────────────────────────────────────┘
```

`UiTheme` — единственная точка касания UI-кода с палитрой. Все компоненты — клиенты `UiTheme`. Никакого `Theme` resource на корне сцены — это Godot путь, который плохо работает с merge-конфликтами в `.tres`-файлах и непрозрачным наследованием. Решение принято в Q-UI-1 (рекомендация (a) — захардкоженные константы).

## File layout

### Новые файлы

```
scripts/presentation/
├── ui_theme.gd                 # autoload — color, spacing, font constants + helpers
├── ui_signal_helpers.gd        # static helpers for tooltip suppression, focus release
│
├── top_hud_bar.gd              # C1
├── player_status_panel.gd      # C3
├── status_icon_strip.gd        # C5
├── cast_range_overlay.gd       # C8
├── floating_number.gd          # C11 (single instance, queue_free after anim)
├── floating_number_layer.gd    # C11 — manager that spawns floating_number on event
├── hex_inspector_subpanel.gd   # C13 — extends/refactors actor_inspector hex section
├── tooltip_panel.gd            # C15 generic
├── skill_tooltip.gd            # C14 — Phase 4 (blocked on 007)
├── choice_button_row.gd        # C18 — refactor from dialogue_panel.gd internal
├── modifier_pick_screen.gd     # C19 — Phase 4 (blocked on 007)
├── portal_transition.gd        # C20
├── run_summary.gd              # C21
├── main_menu.gd                # C22
├── pause_menu.gd               # C23
├── settings_panel.gd           # C24
├── confirm_modal.gd            # C25
├── toast_layer.gd              # C26 — manages stack
├── toast_item.gd               # C26 — single toast instance
├── combat_log.gd               # C27
├── keybind_overlay.gd          # C28
└── loading_cover.gd            # C29

scenes/ui/
├── top_hud_bar.tscn
├── player_status_panel.tscn
├── status_icon_strip.tscn
├── tooltip_panel.tscn
├── skill_tooltip.tscn
├── choice_button_row.tscn
├── modifier_pick_screen.tscn
├── portal_transition.tscn
├── run_summary.tscn
├── pause_menu.tscn
├── settings_panel.tscn
├── confirm_modal.tscn
├── toast_layer.tscn
├── toast_item.tscn
├── combat_log.tscn
├── keybind_overlay.tscn
├── loading_cover.tscn
├── floating_number.tscn        # single number ephemera
└── floating_number_layer.tscn

scenes/
├── main_menu.tscn              # NEW — replaces main.tscn as project main_scene
└── main.tscn                   # KEPT as transition stub OR DELETED — Q-UI-4 → (a) DELETE
```

### Изменяемые файлы (refit)

```
scripts/presentation/
├── health_bar.gd               # AC-R1 — Color() inline → UiTheme.HP_*  + low/crit thresholds
├── slot_bar.gd                 # AC-R2 — Color() → UiTheme + hover state
├── intent_arrow.gd             # AC-R5 — color → UiTheme.SEM_*
├── hex_cursor.gd               # AC-R6 — 4 modes by cast_mode, inspect-mode hex brackets
├── telegraph_hex.gd            # AC-R7 — color via UiTheme.SEM_*, semantic-tag input
├── turn_counter.gd             # absorbed into top_hud_bar.gd (kept as Label child node)
├── dialogue_panel.gd           # AC-R4 — stylebox via UiTheme + extract choice row to C18
└── godmode/
    ├── actor_inspector.gd      # AC-R3 — UiTheme palette + team badge + dev_mode toggle
    └── move_range_overlay.gd   # AC-R8 — color via UiTheme.TEAM_*

scenes/ui/
├── dialogue_panel.tscn         # stylebox via SubResource → load from UiTheme.make_panel_stylebox()
                                # in _ready, not as inline SubResource

scenes/dev/
└── godmode.tscn                # AC-I1 — replace TurnLabel/HelpLabel with TopHudBar instance
                                # add PlayerStatusPanel, StatusIconStrip, CastRangeOverlay, ToastLayer

project.godot                   # add UiTheme autoload + change main_scene to main_menu.tscn
                                # add ESC pause input action if not already
```

## API contracts

### UiTheme autoload

```gdscript
# scripts/presentation/ui_theme.gd
extends Node
## UiTheme — color/size constants for all UI Control nodes.
## Mirrors specs/009-ui-kit/design/tokens.css 1:1.
##
## Hot-reload: F5 in editor reloads constants and emits theme_reloaded.
## All consumers should connect to EventBus.ui_theme_reloaded and queue_redraw / restyle.

# ── Surfaces ─────────────────────────────────────────────────
const BG_SCREEN    := Color("0c0e12")
const BG_PANEL     := Color("161a22")
const BG_PANEL_2   := Color("1f2530")
const BG_ELEVATED  := Color("2a313e")
const OVERLAY      := Color(0, 0, 0, 0.55)

# ── Borders ──────────────────────────────────────────────────
const BORDER        := Color("2c3340")
const BORDER_STRONG := Color("465062")

# ── Text ─────────────────────────────────────────────────────
const TEXT          := Color("e8ecf3")
const TEXT_DIM      := Color("9aa3b2")
const TEXT_FAINT    := Color("5e6776")
const TEXT_ON_ACCENT:= Color("0c0e12")

# ── State ────────────────────────────────────────────────────
const FOCUS    := Color("f5d97a")
const DISABLED := Color("3a414e")

# ── Semantic (effect types) ──────────────────────────────────
const SEM_DAMAGE  := Color("d94b4b")
const SEM_HEAL    := Color("4cc987")
const SEM_CONTROL := Color("9b6bd1")
const SEM_BUFF    := Color("5aa9e6")
const SEM_DEBUFF  := Color("e09b3a")
const SEM_MOVE    := Color("cfd3da")
const SEM_CREATE  := Color("b6936a")

# ── Team ─────────────────────────────────────────────────────
const TEAM_PLAYER  := Color("5fb6f5")
const TEAM_ENEMY   := Color("d94b4b")
const TEAM_NEUTRAL := Color("9aa3b2")

# ── HP bar ───────────────────────────────────────────────────
const HP_FILL    := Color("62c970")
const HP_LOW     := Color("e09b3a")
const HP_CRIT    := Color("d94b4b")
const HP_PREVIEW := Color("d94b4b")
const HP_BG      := Color("1a1d24")
const HP_LOW_THRESHOLD  := 0.30
const HP_CRIT_THRESHOLD := 0.15

# ── Spacing scale (px) ───────────────────────────────────────
const SP_1 := 4
const SP_2 := 8
const SP_3 := 12
const SP_4 := 16
const SP_5 := 24
const SP_6 := 32

# ── Font sizes (px) ──────────────────────────────────────────
const FS_DISPLAY    := 32
const FS_HEADER     := 18
const FS_BODY       := 14
const FS_SMALL      := 11
const FS_NUM_LARGE  := 24
const FS_NUM_SMALL  := 12

# ── Lookups ──────────────────────────────────────────────────

## Returns hp fill color by ratio (0..1).
static func hp_color_for(ratio: float) -> Color:
    if ratio <= HP_CRIT_THRESHOLD: return HP_CRIT
    if ratio <= HP_LOW_THRESHOLD:  return HP_LOW
    return HP_FILL

## Returns team accent by team id.
static func team_color(team: StringName) -> Color:
    if team == &"player": return TEAM_PLAYER
    if team == &"enemy":  return TEAM_ENEMY
    return TEAM_NEUTRAL

## Returns semantic color by effect type tag (after 007).
static func semantic_color(tag: StringName) -> Color:
    match tag:
        &"damage":  return SEM_DAMAGE
        &"heal":    return SEM_HEAL
        &"control": return SEM_CONTROL
        &"buff":    return SEM_BUFF
        &"debuff":  return SEM_DEBUFF
        &"move":    return SEM_MOVE
        &"create":  return SEM_CREATE
    return TEXT  # unknown tag — neutral

# ── Helpers ──────────────────────────────────────────────────

## Builds a fresh StyleBoxFlat for a panel surface.
## Each call returns a NEW instance — do not share between nodes.
static func make_panel_stylebox(elevated: bool = false) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = BG_ELEVATED if elevated else BG_PANEL
    sb.border_color = BORDER
    sb.border_width_left   = 1
    sb.border_width_right  = 1
    sb.border_width_top    = 1
    sb.border_width_bottom = 1
    sb.corner_radius_top_left     = 4
    sb.corner_radius_top_right    = 4
    sb.corner_radius_bottom_left  = 4
    sb.corner_radius_bottom_right = 4
    return sb

## Builds an inset (nested) panel stylebox.
static func make_nested_stylebox() -> StyleBoxFlat:
    var sb := make_panel_stylebox()
    sb.bg_color = BG_PANEL_2
    return sb

## Apply standardized font size + color to a Label by kind.
## kind ∈ "display" / "header" / "body" / "small" / "num_large" / "num_small"
static func apply_label_kind(lbl: Label, kind: String) -> void:
    var fs: int = FS_BODY
    var col: Color = TEXT
    match kind:
        "display":   fs = FS_DISPLAY;   col = TEXT
        "header":    fs = FS_HEADER;    col = TEXT
        "body":      fs = FS_BODY;      col = TEXT
        "small":     fs = FS_SMALL;     col = TEXT_DIM
        "num_large": fs = FS_NUM_LARGE; col = TEXT
        "num_small": fs = FS_NUM_SMALL; col = TEXT
    lbl.add_theme_font_size_override("font_size", fs)
    lbl.add_theme_color_override("font_color", col)

## Hot-reload trigger. Call from F5 input handler in dev sceens.
func reload() -> void:
    # Static consts can't be live-mutated; "reload" semantics here =
    # re-emit the signal so consumers re-pull and queue_redraw / restyle.
    EventBus.ui_theme_reloaded.emit()
    GameLogger.info("UiTheme", "theme reloaded")
```

### EventBus extensions

```gdscript
# scripts/infrastructure/event_bus.gd — additions

# UI infrastructure
signal ui_theme_reloaded
signal ui_toast_requested(text: String, duration_sec: float, level: StringName)  # level ∈ info/success/warn/error
signal ui_modal_opened(id: StringName)
signal ui_modal_closed(id: StringName)

# Game flow (used by main menu, run summary)
signal main_menu_entered
signal run_started_requested  # from C22 Start Run button
signal run_summary_shown(summary: Dictionary)
signal pause_toggled(paused: bool)
```

### Component public APIs (terse — full signatures in tasks)

```gdscript
# C1 — TopHudBar
func set_turn(n: int) -> void
func set_wave(current: int, total: int) -> void
func set_run_timer(seconds: float) -> void
# emits via EventBus.pause_toggled when pause button clicked

# C3 — PlayerStatusPanel
func bind_player(actor: Actor) -> void
# auto-listens to actor.damaged + actor.statuses_changed

# C5 — StatusIconStrip (separate widget, also used inside C12)
func bind_actor(actor: Actor) -> void
func unbind() -> void

# C8 — CastRangeOverlay
func show_range(caster: Actor, ability_id: StringName) -> void
func hide_range() -> void
# subscribes to controller's cast_mode_changed signal

# C11 — FloatingNumberLayer
func spawn(world_pos: Vector2, amount: int, kind: StringName) -> void  # kind: damage/heal/miss

# C15 — TooltipPanel
func show_tooltip(anchor: Control, title: String, body: String = "") -> void
func hide_tooltip() -> void
# global suppression: listens to ui_modal_opened/closed

# C18 — ChoiceButtonRow
func set_choices(labels: Array[String]) -> void
signal choice_picked(index: int)

# C22 — MainMenu
# autonomous; emits run_started_requested on click

# C23 — PauseMenu
func open() -> void
func close() -> void
# triggered by ESC handler in arena/godmode controllers

# C24 — SettingsPanel
# reads/writes to GameSpeed.cfg or new user_prefs.cfg (see Q-UI-1 follow-up)

# C25 — ConfirmModal
func ask(title: String, body: String, confirm_label: String = "OK",
         cancel_label: String = "Cancel", danger: bool = false) -> bool
# awaitable: returns true on confirm, false on cancel

# C26 — ToastLayer (autoload? or per-scene?)
# Decision: per-scene, owned by HUD CanvasLayer. Listens to EventBus.ui_toast_requested.
# Stack max 3 visible; queue overflow.

# C27 — CombatLog
func append(turn: int, actor_id: StringName, verb: StringName, target_id: StringName,
            amount: int, semantic: StringName) -> void
# auto-listens to EventBus.damage_dealt / heal_done / status_applied (after 007/008 add these)

# C28 — KeybindOverlay
func toggle() -> void  # bound to ? key

# C29 — LoadingCover
func show_with_text(text: String) -> void
func hide() -> void
```

## Theme hot-reload mechanism

Phase 0 решение (Q-UI-1 → (a)):

- Константы захардкожены в `ui_theme.gd` (см. выше).
- F5 в Godot editor пересохраняет скрипт → editor live-reload подтягивает значения. Для runtime-смены палитры в плейтест-сессии: либо перезапуск сцены, либо (опционально, Phase 0 task) — `EditorScript`/`@tool` режим с `EventBus.ui_theme_reloaded.emit()`.
- В сценах: каждый Control, который рисует через `_draw()` (HpBar, TelegraphHex, MoveRangeOverlay) — подписывается на `EventBus.ui_theme_reloaded` в `_ready()` и вызывает `queue_redraw()`. Нодные styleboxes — пересобираются в `_on_theme_reloaded()` хэндлере.

Если в Phase 1 плейтесте окажется, что цвета крутятся часто — мигрируем на `config/ui_theme.cfg` (как `game_speed.cfg`). Миграция — 1 час: ConfigFile reader + replace `const X := Color(...)` на `var X: Color`. Откладываем.

## Migration table — refit existing widgets

| File | Current state | After 009 | Risk |
|---|---|---|---|
| `scripts/presentation/health_bar.gd` | 4 inline `Color(...)` constants, no low/crit thresholds, fixed sizes 30×4. Tested via 006. | All colors → `UiTheme.HP_*`. Add `_get_fill_color()` using `UiTheme.hp_color_for(ratio)`. Outline color → `UiTheme.team_color(actor.team)`. Sizes unchanged. Subscribe to `ui_theme_reloaded` → queue_redraw. | Low. Visual test: spawn actors, deal damage to thresholds, F5 reload colors. |
| `scripts/presentation/slot_bar.gd` | Direct `btn.modulate = Color(...)`. No hover state. | `_refresh_visual()` uses `UiTheme.FOCUS`/`DISABLED`. Add `mouse_entered`/`mouse_exited` per button → light hover overlay. | Low. State machine in `_refresh_visual` already exists; just swap palette + add hover branch. |
| `scripts/presentation/godmode/actor_inspector.gd` | Inline label colors, no team badge, no dev_mode toggle (always edit-mode). | Add team badge node in `_ready()` (small colored rect + team label). Add `@export var dev_mode: bool = true` — when false, SpinBox replaced by Label. UiTheme palette throughout. | Medium. Risk: dev_mode toggle changes node tree → must instance proxy Label instead of nullify SpinBox. Approach: keep both nodes in scene, swap visibility. |
| `scripts/presentation/dialogue_panel.gd` | `SubResource("1_style") = StyleBoxFlat { bg_color = Color(0.08,...) }` inline in .tscn. | Replace SubResource binding in `_ready()` with `panel.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())`. | Low. State machine, typewriter, signals — untouched. |
| `scripts/presentation/intent_arrow.gd` | Single hardcoded color. | `UiTheme.SEM_DAMAGE` default; param input for tag-based override (used in Phase 4 after 008). | Low. |
| `scripts/presentation/hex_cursor.gd` | Single semi-transparent color. | 4 cast_mode-driven colors via param from controller. New inspect-mode geometry (6 hex-corner brackets, see `design/components/c10-c11-cursor-fct.html`). | Medium. Inspect-mode geometry is new code; cursor mesh switches polygon shape based on mode. |
| `scripts/presentation/telegraph_hex.gd` | Red color hardcoded for damage. | `UiTheme.SEM_DAMAGE` default; new param `semantic_tag: StringName` accepted; consumer (controller) passes tag from skill data once 007 lands. | Low. |
| `scripts/presentation/godmode/move_range_overlay.gd` | Cyan/red hardcoded. | `UiTheme.TEAM_PLAYER`/`TEAM_ENEMY`. | Low. |
| `scripts/presentation/turn_counter.gd` | Standalone Label connected to EventBus.world_turn_ended. | **Absorbed into TopHudBar** as a child Label. Existing script deleted; logic merged into `top_hud_bar.gd`. | Low. Single signal listener; trivial port. |

## Migration plan — main scene swap (Q-UI-4 → (a))

1. Build C22 main_menu.tscn + main_menu.gd.
2. Add EventBus.run_started_requested listener in (future) `RunController` — for now in `scripts/main.gd` until run-loop экзоскелет приедет в отдельной фиче.
3. Change `project.godot` `[application] config/run/main_scene` → `res://scenes/main_menu.tscn`.
4. Delete `scenes/main.tscn` and `scripts/main.gd` once new entry point is verified.

## Pause coordination (Q-UI-3 → (b))

```
get_tree().paused = true triggers ON:    C19 modifier_pick, C23 pause_menu,
                                         C24 settings (when opened from pause),
                                         C25 confirm_modal
                          NOT ON:        C16/C17 dialogue, C26 toast,
                                         C28 keybind overlay, C29 loading cover
                                         (last is a transient cover, not a modal)
```

All pause-triggering modals: their root `CanvasLayer` set `process_mode = PROCESS_MODE_ALWAYS`. They emit `EventBus.ui_modal_opened(id)` on open and `_closed(id)` on close. Other UI widgets (tooltips, hover previews) listen to these signals and gate their behavior:

```gdscript
# in TooltipPanel
func _ready():
    EventBus.ui_modal_opened.connect(func(_id): hide_tooltip())
```

Multiple modals can stack (e.g., pause → settings → confirm). Each push to a `_open_modals` set; pause unsets only when set is empty.

## ESC handling (AC-I3)

Current behavior in `godmode_controller`:
- `cast_mode != idle` → cancel cast (priority 1)
- `selection != player` → reset to player (priority 2)
- nothing → no-op

After 009:
- `cast_mode != idle` → cancel cast (priority 1) [unchanged]
- modal stack non-empty → close top modal (priority 2)
- `selection != player` → reset to player (priority 3)
- nothing → open pause menu (priority 4) [NEW]

Implementation: `godmode_controller._unhandled_input(event)` checks priorities 1, 3, 4. Priority 2 handled by modal-router (each modal listens to ESC and self-closes if it's the top one). Modal-router lives in `scripts/presentation/modal_router.gd` (new helper, optional autoload).

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Refit-Phase 1 ломает существующие сцены, особенно `actor_inspector` (dev_mode=true ↔ false). | Регрессионный смоук: после Phase 1 — все acceptance scenarios из 006 прогоняются вручную в Godmode. Если ломается — катаем исправление в той же фазе, не идём дальше. |
| 007 пересматривает `Skill`/`Ability` API во время того, как Phase 4 в работе → C14 переписывается. | Phase 4 стартует ТОЛЬКО после merge 007 в staging. Sergey + Egor подтверждают closure в чате. |
| `UiTheme` constants как `static`/`const` не позволяют live-edit без перезапуска сцены. | Если станет проблемой в плейтесте — миграция на ConfigFile (см. выше). Время миграции ≤ 1 час. |
| Theme `StyleBoxFlat` shared between nodes → mutation утечка. | `make_*_stylebox()` ВСЕГДА возвращает новый instance. Линтер: grep на `theme.*stylebox.*=.*UiTheme\.` в момент ревью PR. |
| Toast spam во время быстрых действий → визуальный шум. | Cap 3 видимых, deduplication по тексту в 500ms окне (если 2 toast'а с тем же текстом — второй не добавляется). |

## Definition of done — на момент начала Phase 4

После Phases 0-3:
- [ ] UiTheme autoload в `project.godot`, F5 reload работает
- [ ] HealthBar, SlotBar, ActorInspector, DialoguePanel, IntentArrow, HexCursor, TelegraphHex, MoveRangeOverlay рефит-нуты, regression smoke зелёный
- [ ] C1, C3, C5, C8, C10 (full), C11, C13, C15, C18 в проекте, тестируются в Godmode сцене
- [ ] C20, C21, C22, C23, C24, C25, C26, C27, C28, C29 в проекте, доступны через входные точки (main menu / ESC / L / ? / EventBus emit)
- [ ] `scenes/main.tscn` заменена на `scenes/main_menu.tscn`
- [ ] Регрессионный smoke 003, 004, 005, 006 — зелёные

После 007/008 merge → Phase 4:
- [ ] C2 cooldown overlay (number variant)
- [ ] C14 skill tooltip с modifier breakdown (через SkillFormatter helper)
- [ ] C19 modifier-pick screen (нужны ParameterModifier resources из 007)
- [ ] C9 intent arrow с тегом эффекта (cast_intent.skill.tags из 008)
- [ ] C12 (enemy mode) planned-intent line (cast_intent rendered)
- [ ] C6 telegraph hex с цветом по тегу (semantic_tag forwarding)
