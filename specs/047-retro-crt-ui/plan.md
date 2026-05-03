# Plan 047 — Retro CRT UI

## Architecture

Single-file change: `scripts/presentation/ui_theme.gd`. Plus one font asset.
No new files in `scripts/`, no new autoloads, no new scenes.

Why this works: per CLAUDE.md "Architecture rule 5", all UI colors and
spacing flow through `UiTheme.X` and `UiTheme.make_*_stylebox()`. As long
as we don't break the public surface (constant names, helper signatures,
`apply_*` semantics), every Control in the project re-skins automatically
on next instantiation, and on F5 the existing reload signal restyles
everything live.

## Public surface — what we MUST NOT break

These are the names callers depend on. Values change freely; names don't.

**Color constants (callers reference by name):**
`BG_SCREEN`, `BG_PANEL`, `BG_PANEL_2`, `BG_ELEVATED`, `OVERLAY`,
`BORDER`, `BORDER_STRONG`, `TEXT`, `TEXT_DIM`, `TEXT_FAINT`,
`TEXT_ON_ACCENT`, `FOCUS`, `DISABLED`, `FOCUS_ACTIVE_CASTABLE`,
`FOCUS_ACTIVE_DISABLED`, `HOVER_BRIGHTEN`, `SEM_DAMAGE`, `SEM_HEAL`,
`SEM_CONTROL`, `SEM_BUFF`, `SEM_DEBUFF`, `SEM_MOVE`, `SEM_CREATE`,
`TEAM_PLAYER`, `TEAM_ENEMY`, `TEAM_NEUTRAL`, `HP_FILL`, `HP_LOW`,
`HP_CRIT`, `HP_PREVIEW`, `HP_BG`, `WORLD_TEXT_OUTLINE_COLOR`,
`SHADOW_SOFT_COLOR`, `WAVE_BAR_BG`, `WAVE_ANCHOR_*`, `WAVE_NUMBER_COLOR`,
`WAVE_CURSOR_COLOR`, `WAVE_DIFF_FILL`, `WAVE_DIFF_OUTLINE`,
`DIALOGUE_TRIGGER_MARKER_COLOR`, `SKILL_OFFER_MARKER_COLOR`.

**Numeric constants:** `HP_LOW_THRESHOLD`, `HP_CRIT_THRESHOLD`, `SP_*`,
`FS_*`, `BAR_*_OVERHEAD`, `WORLD_TEXT_OUTLINE_SIZE`, `WAVE_*` numerics.
Don't rename. Sizes can be bumped *up* if VT323 turns out unreadable at
that size — never below the existing value.

**Static helpers:** `hp_color_for(ratio)`, `team_color(team)`,
`semantic_color(tag)`, `make_panel_stylebox(elevated)`,
`make_nested_stylebox()`, `make_modal_stylebox()`,
`make_button_stylebox(state)`, `make_pill_stylebox(family)`,
`apply_label_kind(lbl, kind)`, `apply_world_text_outline(lbl)`,
`apply_button_styling(btn)`. Signatures unchanged.

## Palette — amber CRT terminal

Reference: amber phosphor monitor (IBM 5151 monochrome) plus a touch of
CGA's secondary palette for semantic colors so damage/heal/control stay
distinguishable.

```
Surfaces (warm near-black, no pure #000)
  BG_SCREEN     #0a0807   ← was #0c0e12
  BG_PANEL      #14100c   ← was #161a22
  BG_PANEL_2    #1c1812   ← was #1f2530
  BG_ELEVATED   #241e16   ← was #2a313e
  OVERLAY       (0,0,0,0.65)

Borders (dim/medium amber, hard lines)
  BORDER        #5a4622
  BORDER_STRONG #8a6e2e

Text (amber phosphor)
  TEXT          #f5b943   ← was #e8ecf3
  TEXT_DIM      #b58530
  TEXT_FAINT    #6a4f1c
  TEXT_ON_ACCENT #0a0807

State
  FOCUS         #ffce5e   (bright golden amber — was #f5d97a, very close)
  DISABLED      #3a2f18

Semantic (desaturated CGA-ish — distinguishable, period-feel)
  SEM_DAMAGE    #d04020
  SEM_HEAL      #88a040   (CGA green)
  SEM_CONTROL   #8060c0
  SEM_BUFF      #4080a0
  SEM_DEBUFF    #c08030
  SEM_MOVE      #a09080
  SEM_CREATE    #806040

Team
  TEAM_PLAYER   #4080c0
  TEAM_ENEMY    #c04040
  TEAM_NEUTRAL  #806e58

HP — green fill / amber low / red crit (NOT amber, see spec §"Non-goals")
  HP_FILL       #60a040
  HP_LOW        #c08030
  HP_CRIT       #c04040
  HP_PREVIEW    #c04040
  HP_BG         #14100c

Wave timeline
  WAVE_BAR_BG          #14100c
  WAVE_ANCHOR_FILL     #c8b896
  WAVE_ANCHOR_PASSED   #5a4622
  WAVE_ANCHOR_CURRENT  #ffce5e   (= FOCUS)
  WAVE_ANCHOR_OUTLINE  #0a0807   (= BG_SCREEN)
  WAVE_NUMBER_COLOR    #f5b943   (= TEXT)
  WAVE_CURSOR_COLOR    #ffce5e
  WAVE_DIFF_FILL       (0.34, 0.78, 0.55, 0.18)  (CGA green, low alpha — kept)
  WAVE_DIFF_OUTLINE    (0.34, 0.78, 0.55, 0.85)  (kept)

Editor markers (kept distinguishable from FOCUS gold and WAVE colors)
  DIALOGUE_TRIGGER_MARKER_COLOR  #b080c0   (muted violet)
  SKILL_OFFER_MARKER_COLOR       #40b8a8   (period teal)
```

## Stylebox changes

All `make_*` helpers:
- `corner_radius_*` → 0 (every corner, every stylebox)
- `shadow_size` → 0 (no soft drop shadows)
- Border widths kept (1px default, 2px on focus/modal)
- Asymmetric "spine" 2px-left in `make_panel_stylebox` → flatten to uniform
  1px on all sides. CRT panels don't have a spine; uniform border reads
  more "boxed-in by the screen frame".

## Font wiring

VT323 lives at `res://assets/fonts/VT323-Regular.ttf` (OFL license file
alongside as `VT323_OFL.txt`).

Wiring strategy: `ThemeDB.fallback_font` and `ThemeDB.fallback_font_size`
set in `UiTheme._ready()`. This is Godot 4's official way to globally
override the default font for *all* Control nodes that don't have an
explicit font override. No per-control change needed; no `Theme.tres`
file edit needed; no `project.godot` change needed.

```gdscript
const _FONT_PATH := "res://assets/fonts/VT323-Regular.ttf"
var _default_font: FontFile

func _ready() -> void:
    _default_font = load(_FONT_PATH)
    if _default_font:
        ThemeDB.fallback_font = _default_font
        ThemeDB.fallback_font_size = FS_BODY
```

`_ready()` is the right hook because `UiTheme` is an autoload (per
project.godot:24) and runs before any scene is loaded.

## VT323 readability — pillar 1 check

VT323 was designed at ~14px and reads cleanly down to 12px. Below that it
softens. Current `FS_SMALL = 11`. Per CLAUDE.md Visibility doctrine, if a
size is unreadable we bump it up — bump `FS_SMALL` to 12 in the same PR.
All other `FS_*` are ≥14 and safe.

`BAR_FONT_SIZE_OVERHEAD = 18` is fine. `FS_NUM_HUGE = 40` is fine. No
other bumps anticipated. Andrey verifies in playtest; if a screen reads
poorly, bump the number not the font.

## Hot-reload behavior

`reload()` already exists and re-fires `EventBus.ui_theme_reloaded`. Adding
font load in `_ready()` is one-shot (font doesn't reload on F5). If we
ever want to swap fonts at runtime, that's a separate spec; not needed for
the jam.

## Risk register

- **Existing per-control font overrides** (e.g. labels that called
  `add_theme_font_override`) will keep their old font, NOT VT323. Mitigation:
  T05 — grep the codebase for `add_theme_font_override` and decide
  case-by-case. Expectation: zero or near-zero hits, since the architecture
  rule routes everything through `UiTheme`.
- **TileMap labels / Sprite text inside MultiMeshInstance** — irrelevant,
  these don't use ThemeDB.
- **Inline `Color(...)` in presentation scripts** would not get the new
  palette. Architecture rule 5 forbids this; T06 grep verifies.

## Files touched

```
A  specs/047-retro-crt-ui/spec.md
A  specs/047-retro-crt-ui/plan.md
A  specs/047-retro-crt-ui/tasks.md
A  assets/fonts/VT323-Regular.ttf       (binary)
A  assets/fonts/VT323_OFL.txt           (license, required by OFL §3)
M  scripts/presentation/ui_theme.gd
```

No other file is modified by this PR.
