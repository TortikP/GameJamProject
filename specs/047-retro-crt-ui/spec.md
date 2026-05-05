# Spec 047 — Retro CRT UI

**Owner:** Andrey
**Status:** in progress

## What

Restyle the entire UI to feel like a DOS/CRT amber terminal:
- Amber phosphor on near-black background
- Sharp corners (`corner_radius = 0` everywhere)
- No soft drop shadows
- Hard 1–2 px borders
- Monospaced pixel font (VT323) as the project default

Mood reference: Wizardry / classic DOS RPG menus / amber CRT monitor.

## Why

Visual identity. The current dark-blue + rounded-corner look is generic
"modern dark UI" — it could belong to any indie game on Steam. A CRT-amber
look in 5 minutes makes the game *immediately* distinctive in screenshots
and trailers, which matters more than any single mechanic for jam visibility.

## Acceptance criteria

1. The whole game (menus, in-arena HUD, modals, editors) renders in the new
   palette **without per-control changes** — purely by editing `UiTheme`
   constants and helper return values.
2. Every Control node uses VT323 by default (no per-label font override
   needed). Existing labels continue to work with their existing
   `apply_label_kind()` calls.
3. No Control has rounded corners. `corner_radius_*` is 0 in every stylebox
   produced by `UiTheme.make_*`.
4. Pillar 1 (Full information visibility) is preserved — HP digits, damage
   telegraphs, status icons remain readable at default zoom in 0.3 s. If
   VT323 is illegible at any current `FS_*` constant, that constant gets
   bumped *up* (per Visibility doctrine in CLAUDE.md), not the font replaced.
5. Pillar 2 (Player–monster symmetry) is unaffected — pure presentation change.
6. F5 hot-reload still works: `EventBus.ui_theme_reloaded` re-fires, listeners
   restyle.
7. Game launches and a smoke test (Game Editor → Playtest a level → return)
   completes without errors thrown by the theme code.

## Out of scope

- Custom shaders for scanlines / phosphor glow / barrel distortion. Those go
  in a separate spec if Andrey wants them later.
- Changing icon assets (checkboxes, scrollbar arrows, etc.) — Godot defaults
  stay. Repainting them is a separate art task.
- Sound design (no Sound Blaster bleeps yet).
- Per-screen redesigns (layouts unchanged — purely re-skin).
- Replacing `WORLD_TEXT_OUTLINE_COLOR` semantics — overhead combat text keeps
  its dark outline because pillar 1 trumps stylistic purity.

## Non-goals / accepted compromises

- Semantic colors (`SEM_DAMAGE`, `SEM_HEAL`, etc.) get desaturated to fit the
  CGA-ish palette but are NOT collapsed to mono-amber. Distinguishability of
  damage vs heal vs control is required by pillar 1.
- HP bar fill stays green-ish (CGA green), not amber, for the same reason —
  amber HP at low values would camouflage into the ambient amber UI.
- Soft drop shadows on panels are removed (CRTs don't drop-shadow), but the
  in-world `WORLD_TEXT_OUTLINE_*` constants stay because they exist for
  readability over arbitrary backgrounds, not for stylistic shadowing.
