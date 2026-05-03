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
## --- Spec 047 (retro CRT, Win98-teal palette) ---
## Palette is Win98-teal: dark teal-tinted surfaces, iconic teal borders
## (#008080), bright cyan accents. Semantic colors (damage red, heal green,
## buff blue) stay distinguishable — pillar 1 trumps stylistic monochromy.
## All `make_*_stylebox` corners are 0, panel drop-shadows removed (Win98
## panels were sharp). Default font for every Control is Pixellari (pixel
## bitmap, full Cyrillic) — wired into the default theme + fallback_font in
## _ready() with anti-aliasing forced off.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# ── Default font (047) ───────────────────────────────────────
# Pixellari (Cyrillic edition by YuRaNnNzZZ, OFL-1.1, derived from Pixellari
# by Zaccary Dempsey-Plante 2017). Bitmap-derived TTF — see _ready() below
# for the pixel-perfect render settings that keep its glyphs crisp instead
# of fuzzy-FreeType-default.
const _FONT_PATH := "res://assets/fonts/Pixellari.ttf"
# Typed as base Font (rather than FontFile) so the assignment survives if Godot
# ever returns a different concrete subclass for an imported .ttf.
var _default_font: Font

# ── Surfaces — dark teal-tinted (Win98 desktop nostalgia) ────
const BG_SCREEN    := Color("001a1d")
const BG_PANEL     := Color("002830")
const BG_PANEL_2   := Color("003a44")
const BG_ELEVATED  := Color("004d59")
const OVERLAY      := Color(0, 0, 0, 0.65)

# ── Borders — iconic Win98 teal hierarchy ────────────────────
const BORDER        := Color("008080")  # the actual Win98 desktop teal
const BORDER_STRONG := Color("00c8c8")  # brighter teal for modals/strong frames

# ── Text — cool whites/cyans (high contrast on dark teal) ────
const TEXT           := Color("d8f0f0")
const TEXT_DIM       := Color("88b0b0")
const TEXT_FAINT     := Color("4a7070")
const TEXT_ON_ACCENT := Color("001a1d")

# ── State ────────────────────────────────────────────────────
const FOCUS    := Color("00ffff")  # bright cyan — pops against dark teal
const DISABLED := Color("2a3a40")

# Slot focus / hover modulation (009/T044+ slot_bar). Pre-baked from FOCUS so
# slot_bar doesn't recompute per state change. Adapted for cyan FOCUS:
# - CASTABLE: cyan brightened toward white-cyan (was: amber → gold)
# - DISABLED: cyan darkened (was: amber desaturated)
const FOCUS_ACTIVE_CASTABLE := Color(FOCUS.r + 0.3, FOCUS.g, FOCUS.b, 1.0)
const FOCUS_ACTIVE_DISABLED := Color(FOCUS.r * 0.6, FOCUS.g * 0.6, FOCUS.b * 0.6, 1.0)
# Hover brighten for filled-castable slots and similar interactive elements.
const HOVER_BRIGHTEN        := Color(1.10, 1.10, 1.10)

# ── Semantic (effect types) ──────────────────────────────────
# Distinguishability is non-negotiable (pillar 1). Hues kept clearly
# separable on dark-teal panels: red/green/blue/orange/purple. Saturation
# pulled slightly so they sit in the same era as the teal surrounding,
# but never dimmed enough to merge into the bg.
const SEM_DAMAGE  := Color("d04040")
const SEM_HEAL    := Color("60c080")
const SEM_CONTROL := Color("a070d0")
const SEM_BUFF    := Color("6090f0")
const SEM_DEBUFF  := Color("f0a040")
const SEM_MOVE    := Color("b0c0c8")
const SEM_CREATE  := Color("b08060")

# ── Team ─────────────────────────────────────────────────────
# Player blue pushed away from the teal bg (more saturated blue channel)
# so player vs neutral teal-tinted UI is unambiguous.
const TEAM_PLAYER  := Color("6090f0")
const TEAM_ENEMY   := Color("e04040")
const TEAM_NEUTRAL := Color("809090")

# ── HP bar ───────────────────────────────────────────────────
# Stays green/orange/red rather than monochrome teal: teal HP at low
# values would camouflage into the ambient teal UI and break pillar 1.
# Greens/oranges/reds also pop the loudest against teal — best possible
# attention-grabber for an HP-low warning.
const HP_FILL    := Color("60c080")
const HP_LOW     := Color("f0a040")
const HP_CRIT    := Color("e04040")
const HP_PREVIEW := Color("e04040")
const HP_BG      := Color("002830")
const HP_LOW_THRESHOLD  := 0.30
const HP_CRIT_THRESHOLD := 0.15

# 039-dialogue-triggers: WaveTimeline marker for dialogue trigger anchors (EDIT mode).
# Muted violet — distinct from teal UI, FOCUS cyan, and skill-offer pink.
const DIALOGUE_TRIGGER_MARKER_COLOR  := Color("b080c0")
const DIALOGUE_TRIGGER_MARKER_RADIUS := 5.0

# 040-wave-skill-choice: WaveTimeline marker for skill offer anchors (EDIT + RUNTIME).
# Was teal in amber-palette era — now camouflaged into the new teal UI, so
# moved to magenta-pink. Distinct from violet trigger markers, distinct from
# FOCUS bright cyan, distinct from teal panels.
const SKILL_OFFER_MARKER_COLOR  := Color("e060c0")
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
# 047: FS_SMALL 11 → 12 → 14 (pixel-font readability floor, then user
# feedback bump); FS_BODY 14 → 16 because Pixellari's bitmap source is
# 16px-tall and renders crispest at multiples of 16. FS_HEADER 18 → 20
# in a follow-up bump (top_hud_bar's offset_bottom widened 44 → 52 in
# the same PR to absorb the taller line-height). FS_NUM_SMALL kept
# matching FS_SMALL so numeric and textual "small" sit at the same
# height. Per Visibility doctrine in CLAUDE.md, when a font is illegible
# at a size, the size goes up — never the font down.
const FS_DISPLAY    := 32
const FS_HEADER     := 20
const FS_BODY       := 16
const FS_SMALL      := 14
const FS_NUM_LARGE  := 24
const FS_NUM_SMALL  := 14
# `num_huge` is for in-world combat text crits — has to read from across the
# screen at a glance. See `Visibility doctrine` in CLAUDE.md.
const FS_NUM_HUGE   := 40

# ── Dialogue-specific (047 polish) ───────────────────────────
# Dialogue text/name need to be much larger than UI body — they are the
# focal point during a story beat, not chrome. User direction: speaker
# name ≥ ×2 of FS_HEADER, line text ×2.5 of FS_BODY. Picked exact
# multiples of Pixellari's 16px bitmap source for crispness:
#   FS_DIALOGUE_NAME = 48 = FS_BODY × 3  (just above the ×2 minimum,
#                                          gives clear hierarchy over text)
#   FS_DIALOGUE_TEXT = 40 = FS_BODY × 2.5
const FS_DIALOGUE_NAME := 48
const FS_DIALOGUE_TEXT := 40

# ── Overhead actor UI (HP bar above sprite) ──────────────────
# Visibility doctrine: world UI must read at default zoom without leaning in.
# These are bigger than the original 30×4×9px bar — that was readable on a
# screenshot but invisible during actual play.
# 047: BAR_FONT_SIZE_OVERHEAD bumped 18→22. Pixel fonts have thinner strokes
# than OpenSans, and HP digits sit on top of grass/fire/blood — extra pixels
# per glyph win the contrast fight (Visibility doctrine: bump size, never
# the font).
const BAR_WIDTH_OVERHEAD     := 64.0
const BAR_HEIGHT_OVERHEAD    := 10.0
const BAR_FONT_SIZE_OVERHEAD := 22

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
const WAVE_BAR_BG                   := Color("002830")  # bar trough (= BG_PANEL)
const WAVE_BAR_HEIGHT               := 6.0              # px (drawn line thickness)
const WAVE_ANCHOR_FILL              := Color("c0e0e8")  # cool white-cyan, default anchor
const WAVE_ANCHOR_PASSED            := Color("008080")  # waves before current (= BORDER teal)
const WAVE_ANCHOR_CURRENT           := Color("00ffff")  # active wave (= FOCUS bright cyan)
const WAVE_ANCHOR_OUTLINE           := Color("001a1d")  # 1px ring around every disc (= BG_SCREEN)
const WAVE_ANCHOR_RADIUS            := 10.0             # px radius for normal anchor
const WAVE_ANCHOR_SPECIAL_RADIUS_MULT := 1.6            # special wave is bigger
const WAVE_NUMBER_FONT_SIZE         := 18
const WAVE_NUMBER_COLOR             := Color("d8f0f0")  # turns_to_next digit (= TEXT)
const WAVE_CURSOR_COLOR             := Color("00ffff")  # runtime "now" pointer (= FOCUS)
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


# 048-corpse-absorption — palette for absorption ritual.
# ABSORPTION_PARTICLE_COLOR — neutral fallback for GPUParticles2D modulate
# (used when no biome dominates / arena is empty). Soft teal-tinted white.
const ABSORPTION_PARTICLE_COLOR := Color(0.85, 0.95, 1.0, 0.9)

# Per-biome aspect tint, keyed by tile_kind StringName. Used to recolor
# heroine flash and absorption particles toward the dominant biome of the
# arena. Unknown / empty kind → WHITE (neutral). Pure colours — final
# applied tint is lerped against neutral via per-channel mix ratios in
# GameSpeed [fx] so designers can tune saturation without patching this dict.
const BIOME_TINTS: Dictionary = {
	&"forest": Color(0.55, 0.85, 0.45),
	&"heaven": Color(0.85, 0.92, 1.00),
	&"lava":   Color(1.00, 0.45, 0.20),
	&"ice":    Color(0.55, 0.80, 1.00),
}


## Returns biome tint by tile_kind. Unknown / empty → WHITE.
static func biome_tint_for(kind: StringName) -> Color:
	return BIOME_TINTS.get(kind, Color.WHITE)


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


## 047: load Pixellari once at autoload init and wire it as the global
## default font.
##
## Why this needs both knobs:
##  - `ThemeDB.fallback_font` is the absolute-last-resort font, used only
##    when no theme in the cascade provides one. Godot's built-in default
##    theme always provides OpenSans, so fallback_font on its own NEVER
##    fires for normal Controls.
##  - `ThemeDB.get_default_theme().default_font` is the font the built-in
##    default theme actually serves. Replacing it swaps the global font
##    for every Control that doesn't have an explicit override.
##  - Some scripts (e.g. health_bar.gd) read `ThemeDB.fallback_font`
##    directly when calling `draw_string()`. Setting both keeps those
##    paths consistent with the global theme.
##
## Pixel-perfect rendering: Pixellari is a bitmap-derived TTF, so we force
## antialiasing/hinting/subpixel-positioning OFF at runtime. Godot's
## defaults antialias every TTF — fine for OpenSans, fuzzy garbage for a
## pixel font. Setting these in code (rather than depending on a checked-in
## `.import` file) makes the look survive a re-import or a Godot version
## bump that changes the default `.import` template.
##
## Failure mode: if the font file is missing or fails to load, log a warning
## and let the game start with Godot's built-in OpenSans. Better to ship
## with the wrong font than crash on boot.
func _ready() -> void:
	var f := load(_FONT_PATH)
	if f is Font:
		_default_font = f
		# Force pixel-perfect rendering on the FontFile (TTF-from-bitmap
		# source — anti-aliasing destroys it).
		if _default_font is FontFile:
			var ff: FontFile = _default_font
			ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			ff.hinting = TextServer.HINTING_NONE
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			ff.force_autohinter = false
		# (a) Replace the default theme's font — affects every Control globally.
		var dt: Theme = ThemeDB.get_default_theme()
		if dt != null:
			dt.default_font = _default_font
			dt.default_font_size = FS_BODY
		# (b) Also set the absolute fallback — covers code paths that read
		# `ThemeDB.fallback_font` directly (HP bar overhead labels etc.).
		ThemeDB.fallback_font = _default_font
		ThemeDB.fallback_font_size = FS_BODY
		GameLogger.info("UiTheme", "Pixellari loaded as global default font (size %d, pixel-perfect)" % FS_BODY)
	else:
		GameLogger.warn("UiTheme", "Pixellari font missing at %s — using Godot default" % _FONT_PATH)


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
