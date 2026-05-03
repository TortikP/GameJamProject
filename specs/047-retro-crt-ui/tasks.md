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
