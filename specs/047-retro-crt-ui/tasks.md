# Tasks 047 — Retro CRT UI

T01–T03 set up paperwork. T04 is the actual code change. T05–T06 are
defensive grep audits. T07 is the manual smoke test (Andrey runs it).

- [x] **T01** Create `specs/047-retro-crt-ui/spec.md`.
- [x] **T02** Create `specs/047-retro-crt-ui/plan.md`.
- [x] **T03** Create `specs/047-retro-crt-ui/tasks.md` (this file).
- [x] **T04a** Drop `assets/fonts/VT323-Regular.ttf` (sourced from
      `github.com/google/fonts/ofl/vt323`, OFL).
- [x] **T04b** Drop `assets/fonts/VT323_OFL.txt` license file.
- [x] **T05** Edit `scripts/presentation/ui_theme.gd`:
  - Replace surface, border, text, state, semantic, team, HP, wave-timeline,
    and editor-marker color values per `plan.md` palette table. Constant
    *names* unchanged.
  - Set `corner_radius_*` to 0 in `make_panel_stylebox`,
    `make_modal_stylebox`, `make_button_stylebox`, `make_pill_stylebox`.
  - Set `shadow_size = 0` in `make_panel_stylebox` (drops drop-shadow on
    every panel). `SHADOW_SOFT_COLOR` constant kept (still referenced
    elsewhere; deprecating it is out of scope).
  - Flatten `make_panel_stylebox` borders to uniform 1px (no left-spine).
  - Bump `FS_SMALL` from 11 → 12 (VT323 readability floor).
  - Add `_FONT_PATH` const and `_default_font` member.
  - Add `_ready()` that loads VT323 and assigns `ThemeDB.fallback_font` +
    `ThemeDB.fallback_font_size = FS_BODY`. Log via `GameLogger.info` on
    success; `GameLogger.warn` on missing file (don't crash — let the game
    start with the default Godot font as a fallback).
- [x] **T06** Defensive grep — inline `Color(...)` in `scripts/presentation/`.
      Findings: 30 hits, but ~25 are `Color(UiTheme.X.r, .g, .b, alpha)` —
      legal pattern (alpha-modulating a UiTheme color, not bypassing the
      palette). Real palette-bypassing literals (won't update with new theme):
      - `runtime/spawner_placeholder.gd:80` — pure white at 45% (editor placeholder)
      - `ui/skill_offer_modal.gd:70` — should be `UiTheme.OVERLAY`
      - `dev/spawners_overlay.gd:47,57` — should be `UiTheme.WORLD_TEXT_OUTLINE_COLOR`
      - `dev/objects_overlay.gd:155,159,161` — three hardcoded hexes (`#4a7d4a`
        forest green, `#9aa3b2` silvery, `#8a6d3b` warm brown) for object kind
        glyphs — visible only in dev/object overlay
      All pre-existing tech debt, not introduced by this PR. Filed as
      follow-up — out of scope here per spec §"Out of scope".
- [x] **T07** Defensive grep — per-control font overrides.
      `add_theme_font_override` / `theme_override_fonts/font` /
      `font = ExtResource` / `theme = ExtResource` across `scripts/` and
      `scenes/`: **0 hits**. ThemeDB.fallback_font will catch every Control
      cleanly. No per-scene fixes needed.
- [ ] **T08** Smoke test (Andrey runs locally):
  1. `Godot 4.6.2` opens the project, no errors in Output panel.
  2. Main menu renders in amber-on-black with sharp corners.
  3. Open Game Editor → start Playtest → close back to editor. No
     theme-related errors.
  4. F5 in-game: `EventBus.ui_theme_reloaded` fires, no errors.

## Dependencies

- T05 depends on T04a/T04b (the font file must exist for the load to
  succeed).
- T06 / T07 are independent grep audits, can run in any order.
- T08 depends on everything else.

## Post-merge revisions

### Font swap: VT323 → Pixellari Cyrillic

VT323 lacks Cyrillic glyphs entirely — Russian text rendered as `□□□`
squares or fell back to OpenSans. Replaced with **Pixellari Cyrillic**
(YuRaNnNzZZ, OFL-1.1, derived from Pixellari by Zaccary Dempsey-Plante,
2017). Source: https://github.com/YuRaNnNzZZ/PixellariCyrillic.

Coverage: full Latin + Latin Extended + Russian (Ё, А-Я, а-я, ё). Ukrainian
diacritics not included (acceptable for jam scope).

Changes:
- Removed `assets/fonts/VT323-Regular.ttf` + `assets/fonts/VT323_OFL.txt`.
- Added `assets/fonts/Pixellari.ttf`, `assets/fonts/Pixellari_OFL.txt`,
  `assets/fonts/Pixellari_README.md` (last one carries the OFL-required
  attribution to original + Cyrillic editor).
- `_FONT_PATH` constant updated.
- `_ready()` now also forces pixel-perfect render settings on the FontFile:
  `antialiasing = NONE`, `hinting = NONE`, `subpixel_positioning = DISABLED`.
  Without this Godot's default TTF anti-aliasing turns the bitmap glyphs
  into mush. Done in code (not in `.import`) so the look survives reimport
  or Godot version bumps.
- `FS_BODY` bumped 14 → 16. Pixellari's bitmap source is 16px-tall —
  multiples of 16 render crispest; 14 was an awkward in-between size.
- Header doc-comment + overhead-bar size comment refreshed to mention
  Pixellari instead of VT323.

### Global font wiring fix

`ThemeDB.fallback_font` only triggers when no theme in the cascade
provides a font. Godot's built-in default theme always provides OpenSans,
so the fallback never fired for normal Controls — only for code paths
that read `ThemeDB.fallback_font` directly (e.g. `health_bar.gd:71`).
Result: VT323 was visible on overhead HP labels but nowhere else.

Fix: also assign `ThemeDB.get_default_theme().default_font`. Both knobs
set; covers both cascade and direct-read paths.

### Overhead HP size

`BAR_FONT_SIZE_OVERHEAD` bumped 18 → 22. Pixel fonts have thinner strokes
than OpenSans on the same px size; on busy backgrounds (grass, fire) the
original 18 washed out. Per Visibility doctrine — bump size, never font.

### Palette: amber CRT → Win98-teal

User direction: "цвет как в старой винде 98", with explicit "читаемость
очень важна — найди компромисс". Pure Win98 teal `#008080` everywhere
would camouflage SEM_HEAL green / TEAM_PLAYER blue / HP_FILL green into
the UI surround → pillar-1 violation. Compromise:

- **Surfaces** tinted dark teal instead of warm near-black: `BG_SCREEN
  #001a1d`, `BG_PANEL #002830`, `BG_PANEL_2 #003a44`, `BG_ELEVATED
  #004d59`. Still dark enough that semantic colors pop.
- **Borders** use the iconic Win98 desktop teal `#008080` and a brighter
  `#00c8c8` for modals. This is where the "Win98 vibe" most lives.
- **Text** swaps from amber `#f5b943` to cool off-white `#d8f0f0`.
  TEXT_DIM/FAINT recoloured to teal-greys.
- **FOCUS** moves from amber gold `#ffce5e` to bright cyan `#00ffff` —
  Win98-selection energy. `FOCUS_ACTIVE_CASTABLE` formula adapted: was
  "amber → gold via ×1.3/×0.5", now "cyan → white-cyan via +0.3 on r"
  (preserves intent: brighten the active state without hue-shifting).
  `FOCUS_ACTIVE_DISABLED` is just FOCUS dimmed ×0.6 (cyan has nowhere
  to desaturate without going gray).
- **Semantic** colors retuned for distinguishability against teal:
  damage/heal/buff/debuff stay clearly red/green/blue/orange. SEM_HEAL
  pushed to `#60c080` (greener, less yellow) to separate from teal hue
  family. SEM_BUFF pushed to `#6090f0` (more blue, less cyan) for the
  same reason.
- **Team** colors: TEAM_PLAYER blue `#6090f0` is clearly more saturated
  than UI teal — player vs neutral teal panel reads unambiguously.
- **HP bar** stays green/orange/red. Teal HP would camouflage; pillar 1.
- **WaveTimeline**: anchors retinted (`WAVE_ANCHOR_FILL` cool white-cyan,
  `WAVE_ANCHOR_PASSED` Win98 teal, `WAVE_ANCHOR_CURRENT` bright cyan).
- **SKILL_OFFER_MARKER** was teal `#40b8a8` — would now camouflage into
  UI teal. Switched to magenta-pink `#e060c0`. Distinct from violet
  trigger markers, distinct from FOCUS cyan, distinct from teal panels.

What was deliberately NOT done in the palette swap:
- No Win98 bevel borders (white-top-left + dark-bottom-right). StyleBoxFlat
  has uniform border_color only; per-side coloring needs custom `_draw()`
  or 4 StyleBoxLines. Out of scope.
- No grey panels (Win98-control-grey on Win98-desktop-teal). Light UI on
  dark game world would be visually dominant — reads as "Office app
  loaded over a game" not "stylish retro". Dark-teal-tinted UI keeps
  the world primary.

### Score corner: top-right → bottom-right

`scenes/ui/score_corner.tscn`: anchors_preset 1 → 3 (top-right →
bottom-right) plus offset_top/offset_bottom flipped to negatives so the
164×64 score box now lives in the bottom-right corner. Reason: it was
overlapping with the actor inspector panel (also anchored top-right) at
godmode-arena scenes — caller couldn't read either.

Trade-off: when the dialogue panel (280px tall, full width, anchored
bottom) is visible, the score box is now hidden behind it. Acceptable
for now — the score isn't load-bearing during a dialogue beat. If it
matters later, add an auto-hide on `EventBus.dialogue_started` /
auto-show on `EventBus.dialogue_ended`, or move it to bottom-right
above the dialogue area (offset_bottom = -290).

### Font bump: small text → readable

User feedback: small text in the actor inspector (HP/dmg/speed labels,
position coord, hint, terrain tag) was unreadable. Two-front fix:

1. **`UiTheme` constants**:
   - `FS_SMALL` 12 → 14
   - `FS_NUM_SMALL` 12 → 14 (kept matching FS_SMALL so numeric/textual
     "small" stay at the same line-height)
   These propagate to all `apply_label_kind(_, "small")` callers:
   keybind_overlay hint, tool_panel hint, dialogue_trigger_panel count,
   hex_inspector_subpanel effect, skill_offer_card mode_badge, and
   actor_inspector hex_effect (script-side override).

2. **`scenes/dev/actor_inspector.tscn` hardcoded sizes**: this scene
   pre-dates the visibility doctrine and had 11 inline
   `theme_override_font_sizes/font_size` literals at sizes 10/11/12/16
   that bypass `UiTheme.FS_*` entirely. Bumping `FS_SMALL` alone wouldn't
   reach them. Mapped into the new scale:
   - 10 → 14 (HintLabel, LabelHexCoord)
   - 11 → 14 (LabelTeam, LabelAbilities, LabelHexEffect)
   - 12 → 16 (LabelMaxHp, LabelDamage, LabelSpeed, LabelHexKind)
   - 16 → 18 (LabelId — actor name reads as a header)

Container audit: `ActorInspector` is a `PanelContainer` with
`grow_vertical = 1` (auto-grows downward), 240 px wide, all labels
sit in `VBoxContainer` / `HBoxContainer` parents with `size_flags_horizontal = 3`
or default. Bumped sizes don't trigger any clipping.
`top_hud_bar` (44 px fixed height) was checked — its labels use
`FS_HEADER = 18` (unchanged) and `FS_NUM_LARGE = 24` (unchanged), no
risk. No other fixed-height containers in `scenes/ui/`.

Pre-existing tech debt NOT fixed in this PR (out of scope, filed for
later): `actor_inspector.tscn` also has inline `theme_override_colors`
that bypass `UiTheme` palette (lines 37, 100, 110, 124, 135). Same
violation pattern as the inline-`Color()` literals from the T06 audit.
Non-blocking; the colors render OK against the new teal palette.

### Dialogue text legibility

User feedback: dialogue name + line text were too small in the new
Pixellari + Win98-teal layout — the dialogue is the focal point of a
story beat, not chrome. Two new constants in `UiTheme` so future
callers don't reach for inline numbers:

- `FS_DIALOGUE_NAME = 48` — speaker name. Just above user's "×2 of
  FS_HEADER minimum"; equals `FS_BODY × 3 = 16 × 3`, so it lands on a
  clean Pixellari bitmap-grid multiple.
- `FS_DIALOGUE_TEXT = 40` — line text. Exactly user's "×2.5 of FS_BODY"
  (`16 × 2.5`). Not a clean integer multiple of 16 → mild aliasing
  accepted because the readability win is decisive.

Wired in `dialogue_panel.gd::_apply_theme()`. The Name label now uses
`FS_DIALOGUE_NAME` directly instead of `apply_label_kind(_, "header")`
because no generic "kind" matches dialogue scale, and adding a "dialogue"
kind would be a single-consumer abstraction.

Panel height stays at 280 px (256 content area). Worst case fits:
name 48 + text 3 × 40 + choices ~32 + separations ~16 = ~216 px, with
~40 px buffer. Dialogue beats in this game are written for ≤3 lines, so
this margin is enough; if a future longer line needs the room, bump
`offset_top` in `dialogue_panel.tscn` then.

Dead `theme_override_font_sizes/font_size = 18` removed from Name label
in the .tscn — was overridden every `_apply_theme()`, pure stale config.
