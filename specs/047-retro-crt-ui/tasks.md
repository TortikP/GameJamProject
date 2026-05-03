# Tasks 047 — Retro CRT UI

T01–T03 set up paperwork. T04 is the actual code change. T05–T06 are
defensive grep audits. T07 is the manual smoke test (Andrey runs it).

- [x] **T01** Create `specs/047-retro-crt-ui/spec.md`.
- [x] **T02** Create `specs/047-retro-crt-ui/plan.md`.
- [x] **T03** Create `specs/047-retro-crt-ui/tasks.md` (this file).
- [x] **T04a** Drop `assets/fonts/VT323-Regular.ttf` (sourced from
      `github.com/google/fonts/ofl/vt323`, OFL).
- [x] **T04b** Drop `assets/fonts/VT323_OFL.txt` license file.
- [ ] **T05** Edit `scripts/presentation/ui_theme.gd`:
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
- [ ] **T06** Defensive grep — verify nothing in `scripts/presentation/`
      uses inline `Color(...)` literals that would dodge the new palette.
      `grep -RnE 'Color\(' scripts/presentation/ | grep -v ui_theme.gd | grep -v '#'`.
      Any hit → file an issue, do not fix in this PR (architecture
      violation tracked separately).
- [ ] **T07** Defensive grep — find existing per-control font overrides
      that would NOT pick up VT323 via `ThemeDB.fallback_font`.
      `grep -RnE 'add_theme_font_override|theme_override_fonts/font' scripts scenes`.
      Expectation: zero or near-zero hits. If hits exist, list them in PR
      description; Andrey decides case-by-case (some may be intentional —
      e.g. a logo font).
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
