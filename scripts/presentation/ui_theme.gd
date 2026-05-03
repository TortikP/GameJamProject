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
##
## --- Spec 047 (retro CRT) ---
## Palette is amber phosphor on near-black; semantic colors stay distinguishable
## but desaturated to a CGA-ish range. All `make_*_stylebox` corners are 0,
## panel drop-shadows removed (CRTs don't drop-shadow). Default font for every
## Control is VT323 — wired via ThemeDB.fallback_font in _ready().

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# ── Default font (047) ───────────────────────────────────────
# Wired into ThemeDB.fallback_font in _ready() so every Control without an
# explicit font override picks up VT323 automatically.
const _FONT_PATH := "res://assets/fonts/VT323-Regular.ttf"
# Typed as base Font (rather than FontFile) so the assignment survives if Godot
# ever returns a different concrete subclass for an imported .ttf.
var _default_font: Font

# ── Surfaces — warm near-black, no pure #000 ─────────────────
const BG_SCREEN    := Color("0a0807")
const BG_PANEL     := Color("14100c")
const BG_PANEL_2   := Color("1c1812")
const BG_ELEVATED  := Color("241e16")
const OVERLAY      := Color(0, 0, 0, 0.65)

# ── Borders — dim/medium amber, hard 1–2px lines ─────────────
const BORDER        := Color("5a4622")
const BORDER_STRONG := Color("8a6e2e")

# ── Text — amber phosphor ────────────────────────────────────
const TEXT           := Color("f5b943")
const TEXT_DIM       := Color("b58530")
const TEXT_FAINT     := Color("6a4f1c")
const TEXT_ON_ACCENT := Color("0a0807")

# ── State ────────────────────────────────────────────────────
const FOCUS    := Color("ffce5e")
const DISABLED := Color("3a2f18")

# Slot focus / hover modulation (009/T044+ slot_bar). Pre-baked from FOCUS so
# slot_bar doesn't recompute Color(focus.r * 1.3, ...) per state change.
# Active slot when castable: FOCUS amber brightened ×1.3, blue knocked to ×0.5
# (hue shift toward gold).
const FOCUS_ACTIVE_CASTABLE := Color(FOCUS.r * 1.3, FOCUS.g * 1.3, FOCUS.b * 0.5, 1.0)
# Active slot when not castable (out of range / cooldown): FOCUS desaturated.
const FOCUS_ACTIVE_DISABLED := Color(FOCUS.r,       FOCUS.g,       FOCUS.b * 0.7, 1.0)
# Hover brighten for filled-castable slots and similar interactive elements.
const HOVER_BRIGHTEN        := Color(1.10, 1.10, 1.10)

# ── Semantic (effect types) ──────────────────────────────────
# Desaturated CGA-ish palette — keeps pillar 1 distinguishability without
# fighting the amber UI surround.
const SEM_DAMAGE  := Color("d04020")
const SEM_HEAL    := Color("88a040")
const SEM_CONTROL := Color("8060c0")
const SEM_BUFF    := Color("4080a0")
const SEM_DEBUFF  := Color("c08030")
const SEM_MOVE    := Color("a09080")
const SEM_CREATE  := Color("806040")

# ── Team ─────────────────────────────────────────────────────
const TEAM_PLAYER  := Color("4080c0")
const TEAM_ENEMY   := Color("c04040")
const TEAM_NEUTRAL := Color("806e58")

# ── HP bar ───────────────────────────────────────────────────
# Stays green/amber/red instead of mono-amber: amber HP at low values
# would camouflage into the ambient amber UI and break pillar 1.
const HP_FILL    := Color("60a040")
const HP_LOW     := Color("c08030")
const HP_CRIT    := Color("c04040")
const HP_PREVIEW := Color("c04040")
const HP_BG      := Color("14100c")
const HP_LOW_THRESHOLD  := 0.30
const HP_CRIT_THRESHOLD := 0.15

# 039-dialogue-triggers: WaveTimeline marker for dialogue trigger anchors (EDIT mode).
# Muted violet — distinct from amber UI, FOCUS gold, and skill-offer teal.
const DIALOGUE_TRIGGER_MARKER_COLOR  := Color("b080c0")
const DIALOGUE_TRIGGER_MARKER_RADIUS := 5.0

# 040-wave-skill-choice: WaveTimeline marker for skill offer anchors (EDIT + RUNTIME).
# Visible in both modes — players plan around offers, designers see them while editing.
# Period teal — readable on amber-tinted dark, distinct from violet/yellow.
const SKILL_OFFER_MARKER_COLOR  := Color("40b8a8")
const SKILL_OFFER_MARKER_RADIUS := 6.0
const SKILL_OFFER_MARKER_GLYPH  := "★"                     # rendered next to the disc

# ── Spacing scale (px) ───────────────────────────────────────
const SP_1 := 4
const SP_2 := 8
const SP_3 := 12
const SP_4 := 16
const SP_5 := 24
const SP_6 := 32

# ── Font sizes (px) ──────────────────────────────────────────
# 047: FS_SMALL bumped 11 → 12 (VT323 readability floor; per Visibility
# doctrine in CLAUDE.md, when a font is illegible at a size, the size
# goes up — never the font down).
const FS_DISPLAY    := 32
const FS_HEADER     := 18
const FS_BODY       := 14
const FS_SMALL      := 12
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
# Kept for pillar 1 (visibility) — overrides stylistic CRT purity.
const WORLD_TEXT_OUTLINE_SIZE  := 4
const WORLD_TEXT_OUTLINE_COLOR := Color(0, 0, 0, 0.95)

# ── Soft drop shadow ─────────────────────────────────────────
# Lighter than the world-text outline (alpha 0.55 vs 0.95). For arrow shadows,
# panel elevations, intent telegraphs — anywhere a shadow should sit behind
# the foreground without competing with it.
# 047: panel styleboxes no longer use this (CRT panels don't drop-shadow),
# but the constant stays — other consumers (e.g. arrow shadows) still reference it.
const SHADOW_SOFT_COLOR := Color(0, 0, 0, 0.55)

# ── 024-wave-editor — wave timeline visuals ──────────────────
# Used by scenes/ui/wave_timeline.tscn in both EDIT and RUNTIME modes.
const WAVE_BAR_BG                   := Color("14100c")  # bar trough (= BG_PANEL)
const WAVE_BAR_HEIGHT               := 6.0              # px (drawn line thickness)
const WAVE_ANCHOR_FILL              := Color("c8b896")  # warm parchment, not bright white
const WAVE_ANCHOR_PASSED            := Color("5a4622")  # waves before current (= BORDER)
const WAVE_ANCHOR_CURRENT           := Color("ffce5e")  # active wave (= FOCUS)
const WAVE_ANCHOR_OUTLINE           := Color("0a0807")  # 1px ring around every disc (= BG_SCREEN)
const WAVE_ANCHOR_RADIUS            := 10.0             # px radius for normal anchor
const WAVE_ANCHOR_SPECIAL_RADIUS_MULT := 1.6            # special wave is bigger
const WAVE_NUMBER_FONT_SIZE         := 18
const WAVE_NUMBER_COLOR             := Color("f5b943")  # turns_to_next digit (= TEXT)
const WAVE_CURSOR_COLOR             := Color("ffce5e")  # runtime "now" pointer (= FOCUS)
const WAVE_CURSOR_HEIGHT            := 22.0             # px tall

# 024 / T83 — wave-diff highlight (new-this-wave overlay in editor).
# Subtle — designer should be able to ignore it during normal editing.
# Applied to floor cells / objects / spawners that exist in waves[active]
# but not in waves[active-1] at the same coord. Wave 0 → highlight off.
# Kept as CGA green (rather than amber) so it stays semantically "additive/positive".
const WAVE_DIFF_FILL                := Color(0.34, 0.78, 0.55, 0.18)  # green-ish fill
const WAVE_DIFF_OUTLINE             := Color(0.34, 0.78, 0.55, 0.85)  # ring

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
##
## 047: corner_radius=0 (CRT panels are rectangular), no soft drop-shadow,
## uniform 1px border (no left-spine accent — feels more "boxed by the screen").
static func make_panel_stylebox(elevated: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_ELEVATED if elevated else BG_PANEL
	sb.border_color = BORDER
	sb.border_width_left   = 1
	sb.border_width_right  = 1
	sb.border_width_top    = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left     = 0
	sb.corner_radius_top_right    = 0
	sb.corner_radius_bottom_left  = 0
	sb.corner_radius_bottom_right = 0
	# No drop shadow on CRT panels.
	sb.shadow_size = 0
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


## Builds a pill stylebox for status-icon strips and similar tag-colored chips.
## family is one of the semantic tags accepted by `semantic_color` (damage/heal/...).
## Each call returns a NEW StyleBoxFlat — do not share across pills.
##
## 047: corners squared off; pills become small flat rectangles.
static func make_pill_stylebox(family: StringName) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var col: Color = semantic_color(family)
	# Pill has a low-alpha bg with the family color and a 1px border of same.
	sb.bg_color = Color(col.r, col.g, col.b, 0.20)
	sb.border_color = Color(col.r, col.g, col.b, 0.65)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = SP_1
	sb.content_margin_right = SP_1
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
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


## 047: load VT323 once at autoload init and wire it as the global default
## font. Every Control without an explicit font override picks it up via
## ThemeDB.fallback_font. No per-control change required.
##
## Failure mode: if the font file is missing or fails to load, log a warning
## and let the game start with Godot's built-in default (OpenSans). Better to
## ship with the wrong font than crash on boot.
func _ready() -> void:
	var f := load(_FONT_PATH)
	if f is Font:
		_default_font = f
		ThemeDB.fallback_font = _default_font
		ThemeDB.fallback_font_size = FS_BODY
		GameLogger.info("UiTheme", "VT323 loaded as fallback font (size %d)" % FS_BODY)
	else:
		GameLogger.warn("UiTheme", "VT323 font missing at %s — using Godot default" % _FONT_PATH)


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
