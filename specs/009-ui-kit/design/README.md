# UI Kit — Design Reference

This folder contains the **as-shipped design bundle** from a Claude Design project (claude.ai/design) — HTML/CSS prototypes for every UI component in the game.

**This is reference material, not code to copy.** Implementation lives in Godot (`scripts/presentation/`) and is driven by the parent spec.

## What to read

| File | Purpose |
|---|---|
| `../spec.md` | What's being built, acceptance criteria, dependencies on 007/008. **Read first.** |
| `../plan.md` | How: file layout, theme architecture, migration table for existing widgets. |
| `../tasks.md` | Phased checklist. Phases 0-3 are unblocked; Phase 4 waits on 007/008. |
| `tokens.css` | **Canonical color & spacing palette.** Every value here maps 1:1 to a `Color()` constant in `scripts/presentation/ui_theme.gd`. |
| `index.html` | Component catalog, links to every component page. |
| `components/c*.html` | One file per component. Each contains: state mockups, spec block (`<details class="spec">`), Godot mapping block. **Open the `<details>` block — the Godot Control tree is in there.** |
| `source-chat.md` | Original conversation transcript with the design assistant. Useful for "why did this end up this way" questions. |

## Component naming

`cN-…html` where N is the component ID from `spec.md` §6 (catalog). Examples: `c4-hp-bar.html` is the world-space HP bar (existing in code, refit per Phase 1); `c14-skill-tooltip.html` is blocked on 007.

## How to use a component file when implementing

1. Find the `<details class="spec">` block at the bottom of the HTML — it has Purpose, Anchor & sizing, Inputs, Outputs, Edge cases, and a **Godot mapping** with the exact Control tree.
2. The visible HTML above it shows every state side-by-side (idle / hover / active / disabled / empty / error). These are the visual targets.
3. Inline CSS uses tokens from `../tokens.css`. When porting, reference `UiTheme.X` instead of hardcoded colors — `UiTheme` is the autoload that mirrors tokens.css 1:1 (see `plan.md` §2).
4. Don't open these files in a browser to "match pixels" — the HTML *is* the spec. Read it.

## What this folder is NOT

- Not the production UI (that's `scripts/presentation/` + `scenes/ui/`).
- Not maintained — the design pass is done. Updates to UI happen in the Godot scripts; mockups are frozen reference.
- Not authoritative when in conflict with shipped code: if a mockup doesn't match what's in `scripts/presentation/`, the spec.md says which side wins (usually mockup for visual, code for behavior).
