extends Node
## UiTheme — color, spacing, font-size constants for all UI Control nodes.
## Mirrors specs/009-ui-kit/design/tokens.css 1:1.
##
## Hot-reload: F5 in editor reloads constants and emits EventBus.ui_theme_reloaded.
## All consumers should connect to that signal and queue_redraw / restyle on emit.
##
## Usage:
##   modulate = UiTheme.SEM_DAMAGE
##   panel.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
##   UiTheme.apply_label_kind(label, "header")
##
## Don't reach for Color() inline anywhere in scripts/presentation/ — palette comes
## through this single file. PRs with inline Color() in UI code get bounced.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

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
const TEXT           := Color("e8ecf3")
const TEXT_DIM       := Color("9aa3b2")
const TEXT_FAINT     := Color("5e6776")
const TEXT_ON_ACCENT := Color("0c0e12")

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
# `num_huge` is for in-world combat text crits — has to read from across the
# screen at a glance. See `Visibility doctrine` in CLAUDE.md.
const FS_NUM_HUGE   := 40

# ── Overhead actor UI (HP bar above sprite) ──────────────────
# Visibility doctrine: world UI must read at default zoom without leaning in.
# These are bigger than the original 30×4×9px bar — that was readable on a
# screenshot but invisible during actual play.
const BAR_WIDTH_OVERHEAD     := 64.0
const BAR_HEIGHT_OVERHEAD    := 10.0
const BAR_FONT_SIZE_OVERHEAD := 18

# ── Outline / shadow for in-world text ───────────────────────
# Combat text and HP digits sit on top of arbitrary backgrounds (grass, fire,
# blood, UI panels). Without a strong outline they vanish on busy frames.
const WORLD_TEXT_OUTLINE_SIZE  := 4
const WORLD_TEXT_OUTLINE_COLOR := Color(0, 0, 0, 0.95)

# ── Soft drop shadow ─────────────────────────────────────────
# Lighter than the world-text outline (alpha 0.55 vs 0.95). For arrow shadows,
# panel elevations, intent telegraphs — anywhere a shadow should sit behind
# the foreground without competing with it.
const SHADOW_SOFT_COLOR := Color(0, 0, 0, 0.55)

# ── Lookups ──────────────────────────────────────────────────

## Returns hp fill color by ratio (0..1).
static func hp_color_for(ratio: float) -> Color:
	if ratio <= HP_CRIT_THRESHOLD:
		return HP_CRIT
	if ratio <= HP_LOW_THRESHOLD:
		return HP_LOW
	return HP_FILL


## Returns team accent by team id.
static func team_color(team: StringName) -> Color:
	if team == &"player":
		return TEAM_PLAYER
	if team == &"enemy":
		return TEAM_ENEMY
	return TEAM_NEUTRAL


## Returns semantic color by effect-type tag (forward-compat with 007).
## Unknown tag → neutral text color.
static func semantic_color(tag: StringName) -> Color:
	match tag:
		&"damage":
			return SEM_DAMAGE
		&"heal":
			return SEM_HEAL
		&"control":
			return SEM_CONTROL
		&"buff":
			return SEM_BUFF
		&"debuff":
			return SEM_DEBUFF
		&"move":
			return SEM_MOVE
		&"create":
			return SEM_CREATE
	return TEXT

# ── Helpers ──────────────────────────────────────────────────

## Builds a fresh StyleBoxFlat for a panel surface.
## Each call returns a NEW instance — do not share between nodes
## (their bg_color is mutable and sharing leaks state).
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
	sb.content_margin_left   = SP_3
	sb.content_margin_right  = SP_3
	sb.content_margin_top    = SP_2
	sb.content_margin_bottom = SP_2
	return sb


## Builds an inset (nested) panel stylebox — slightly lighter background,
## same border / corner / margin.
static func make_nested_stylebox() -> StyleBoxFlat:
	var sb := make_panel_stylebox()
	sb.bg_color = BG_PANEL_2
	return sb


## Builds a modal-surface stylebox (elevated bg, stronger border, larger margins).
static func make_modal_stylebox() -> StyleBoxFlat:
	var sb := make_panel_stylebox(true)
	sb.border_color = BORDER_STRONG
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.border_width_top    = 2
	sb.border_width_bottom = 2
	sb.content_margin_left   = SP_4
	sb.content_margin_right  = SP_4
	sb.content_margin_top    = SP_4
	sb.content_margin_bottom = SP_4
	return sb


## Builds a button stylebox for the given state.
## state ∈ "normal" / "hover" / "pressed" / "disabled" / "focus"
static func make_button_stylebox(state: String = "normal") -> StyleBoxFlat:
	var sb := make_panel_stylebox()
	sb.content_margin_left   = SP_3
	sb.content_margin_right  = SP_3
	sb.content_margin_top    = SP_2
	sb.content_margin_bottom = SP_2
	match state:
		"normal":
			sb.bg_color = BG_PANEL_2
		"hover":
			sb.bg_color = BG_ELEVATED
			sb.border_color = BORDER_STRONG
		"pressed":
			sb.bg_color = BG_PANEL
			sb.border_color = BORDER_STRONG
		"disabled":
			sb.bg_color = BG_PANEL
			sb.border_color = BORDER
		"focus":
			sb.bg_color = BG_ELEVATED
			sb.border_color = FOCUS
			sb.border_width_left   = 2
			sb.border_width_right  = 2
			sb.border_width_top    = 2
			sb.border_width_bottom = 2
	return sb


## Apply standardized font size + color to a Label by kind.
## kind ∈ "display" / "header" / "body" / "small" / "num_large" / "num_huge" / "num_small"
static func apply_label_kind(lbl: Label, kind: String) -> void:
	var fs: int = FS_BODY
	var col: Color = TEXT
	match kind:
		"display":
			fs = FS_DISPLAY
			col = TEXT
		"header":
			fs = FS_HEADER
			col = TEXT
		"body":
			fs = FS_BODY
			col = TEXT
		"small":
			fs = FS_SMALL
			col = TEXT_DIM
		"num_large":
			fs = FS_NUM_LARGE
			col = TEXT
		"num_huge":
			fs = FS_NUM_HUGE
			col = TEXT
		"num_small":
			fs = FS_NUM_SMALL
			col = TEXT
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.add_theme_color_override("font_color", col)


## Apply a strong dark outline to a Label so it reads against any background.
## Use for ALL in-world text (combat numbers, overhead bars, status icons).
## Idempotent — call again after theme reload.
static func apply_world_text_outline(lbl: Label) -> void:
	lbl.add_theme_constant_override("outline_size", WORLD_TEXT_OUTLINE_SIZE)
	lbl.add_theme_color_override("font_outline_color", WORLD_TEXT_OUTLINE_COLOR)


## Apply the full button-state stylebox set to a Button.
## Idempotent — call again after theme reload.
static func apply_button_styling(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal",   make_button_stylebox("normal"))
	btn.add_theme_stylebox_override("hover",    make_button_stylebox("hover"))
	btn.add_theme_stylebox_override("pressed",  make_button_stylebox("pressed"))
	btn.add_theme_stylebox_override("disabled", make_button_stylebox("disabled"))
	btn.add_theme_stylebox_override("focus",    make_button_stylebox("focus"))
	btn.add_theme_color_override("font_color",          TEXT)
	btn.add_theme_color_override("font_hover_color",    TEXT)
	btn.add_theme_color_override("font_pressed_color",  TEXT)
	btn.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	btn.add_theme_color_override("font_focus_color",    TEXT)
	btn.add_theme_font_size_override("font_size", FS_BODY)


## Hot-reload trigger. Bound to F5 via _unhandled_input below.
## Constants can't be live-mutated; "reload" semantics here = re-emit the signal so
## consumers re-pull derived styleboxes and queue_redraw / restyle. To actually edit
## palette values, change ui_theme.gd, save (script live-reload picks them up), then
## hit F5 in the running game to re-broadcast.
func reload() -> void:
	EventBus.ui_theme_reloaded.emit()
	GameLogger.info("UiTheme", "theme reloaded — listeners notified")


func _unhandled_input(event: InputEvent) -> void:
	# F5 already used by GameSpeed for cfg reload; piggyback on the same key —
	# both reloads in one keypress is the intended workflow.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		reload()
