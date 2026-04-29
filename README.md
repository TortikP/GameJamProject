# GameJamProject

72-hour game jam project. Godot 4.6.2 + GDScript. Default concept: turn-based magical arena with spell-crafting via modifiers, hex grid, roguelike loop. Theme announced Thursday 19:00 (one of 15 candidates).

## Quick start

1. Install Godot 4.6.2 (patch version must match across the team).
2. Clone this repo, open `project.godot` in Godot.
3. Run the project — the entry scene `scenes/main.tscn` should print `[INFO][Main] run_started signalled` and show "Jam Project Ready".
4. Press **F5 in-game** to hot-reload `config/game_speed.cfg` without restarting.

## What lives where

- `CLAUDE.md` — project conventions / constitution. **Read this first.**
- `HANDOFF.md` — full operational context, timeline, scope rules, fallbacks.
- `PROJECT_INSTRUCTIONS.md` — template for the `Project Settings → Instructions` field in claude.ai (per-user, with personal token).
- `specs/NNN-feature-name/` — `spec.md` / `plan.md` / `tasks.md` per feature. See `HANDOFF.md` §19.
- `scripts/infrastructure/` — autoloads (GameSpeed, EventBus, Logger, AudioDirector).
- `scripts/core/` — game logic (battle, spells, progression, dialogue).
- `scripts/presentation/` — UI, VFX, polish.
- `data/` — JSON content (modifiers, enemies, spells, dialogues).
- `config/game_speed.cfg` — all tunable timings.
- `<name>/` (`andrey/`, `egor/`, `nikita/`, `sergey/`, `alexey/`, `stasyan/`) — personal scratch / drafts / per-dev notes. Each Claude reads its user's folder at session start.

## Branches

| Branch | Push rights |
|---|---|
| `main` | Andrey, Egor — manually only. Stable. |
| `staging` | PR only, ≥1 approval. Integration. |
| `<user>/<task>` | Personal work branches. Merged into staging via PR. |

## Stack

- Godot 4.6.2 stable
- GDScript only (no C#, no GDExtension)
- JSON + `.tres` for content; no databases
- Desktop builds (Win/Mac/Linux); web only if time permits Saturday
