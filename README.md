# Polyabsorb

> **YOU ARE WHAT YOU EAT** — turn-based hex tactics with story-driven roguelike loop and meta-progression. Aspect-based identity system: kill enemies, absorb their skills, become what you eat. Godot 4.6.2 + GDScript.

## Quick start

1. Install **Godot 4.6.2 stable** (patch must match across the team).
2. Clone this repo, open `project.godot` in Godot.
3. Run the project — entry is `scenes/main_menu.tscn`.
4. **F5 in-game** hot-reloads `config/game_speed.cfg` without restart.

## What you can launch from the main menu

| Button | What it does |
|---|---|
| **Start Run** | Story campaign (`data/games/story_campaign.game.json`) — intro cutscene → levels with waves and dialogues. |
| **Godmode** | Sandbox arena (`scenes/dev/godmode.tscn`) — spawn dummies, free-cast, no death. Dev/playtest. |
| **Map Editor** | Build single-level layouts (terrain, tile objects, waves, dialogue triggers, skill offers). Saves to `data/maps/*.json`. |
| **Game Editor** | Stitch maps into a campaign (`*.game.json`) — order, intros, cutscenes. Round-trips to Map Editor. |
| **Load Game** | Pick any `*.game.json` and play it. |
| **Load Custom Level** | Pick any `*.json` map and play it standalone. |

## Design pillars (override implementation convenience)

1. **Full information visibility.** Player sees everything needed to make the call *before* committing — HP, statuses, telegraphs with damage numbers, ability previews, castability. No hidden RNG. Loss feels like "I misjudged", never "the game cheated me".
2. **Player–monster symmetry.** Monsters use the same `Actor` and `Ability` (`Target × Effect × Modifier`) contracts as the player. AI is a controller picking from the same primitives — not a parallel system.

Full discussion in `THEME_PLAN.md` §1.5 and `CLAUDE.md`. PRs that violate these get re-thought before merge.

## What lives where

- `CLAUDE.md` — project conventions / constitution. **Read this first.**
- `HANDOFF.md` — full operational context, timeline, scope rules, fallbacks.
- `docs/design/` — current game concept: `VISION.md`, `PILLARS.md`, `aspects.md`, `DECISIONS.md`, `REFERENCES.md`, `OPEN-QUESTIONS.md`, `GLOSSARY.md`. Replaces the old `jam-concept-pitch.md` (deleted 2026-05-07; that was a pre-theme pitch, much of which never materialized).
- `THEME_PLAN.md` — narrative + design plan tied to jam theme.
- `PROJECT_INSTRUCTIONS.md` — template for `claude.ai → Project → Instructions` (per-user, with personal token).
- `specs/NNN-feature-name/` — `spec.md` / `plan.md` / `tasks.md` per feature. See `HANDOFF.md` §19. **54 numbered folders total: 41 real specs (features / systems / refactors), 11 minor fixes & cleanup, 2 reserved drafts (025, 029 — never implemented, subsumed by 039 / scattered polish).** Minor-fix folders: `013-refactor-wave-1`, `015-refactor-wave-2`, `016-cleanup-wave`, `017-doc-fixes`, `031-skill-system-fixes`, `036-level-builder-bugfix`, `037-player-stun-immunity`, `046-skill-bug-fix`, `051-ability-sfx-resolver`, `052-ability-sfx-fix`, `053-pck-audio-portrait-fix`.
- `scenes/` — `main_menu.tscn`, `arena/`, `dev/` (godmode, editors, smoke tests), `meta/` (transitions, end screens), `ui/` (HUD, panels, overlays), `presentation/` (CRT post-fx, space bg).
- `scripts/infrastructure/` — autoloads (GameSpeed, EventBus, AudioDirector, Localization, RunScore, ActiveLevel, ActiveGame, …).
- `scripts/core/` — game logic. **Knows nothing of presentation.** `actors/`, `arena/` (HexGrid), `abilities/`, `skills/`, `statuses/`, `turn/`, `dialogue/`, `narrative/` (mood), `ai/`, `progression/`, `maps/`.
- `scripts/runtime/` — controllers gluing core to presentation (CampaignController, WaveController, LevelDialogueDirector, SkillOfferController, IntroDirector, CorpseManager).
- `scripts/presentation/` — UI, VFX, polish. `crt/`, `meta/` (cutscene, transitions), `godmode/`, `dev/`, `runtime/`.
- `scripts/audio/music/` — MusicDirector + procedural music.
- `data/` — JSON content: `dialogues/`, `abilities/`, `skills/`, `enemies/`, `modifiers/`, `status_effects/`, `tile_effects/`, `tile_objects/`, `ai_behaviors/`, `skill_offer_pools/`, `fx/`, `localization/`, `maps/`, `games/`, `music/`.
- `config/game_speed.cfg` — all tunable timings. Hot-reload via F5 in-game.
- `assets/` — sprites, portraits, hex tiles, audio.

## Hard rules (excerpt — see `CLAUDE.md` for the full list)

- `scripts/core/` knows nothing of textures/audio/scenes.
- Cross-module communication via **EventBus signals**, not direct refs.
- All timings via **`GameSpeed.wait(...)` / `GameSpeed.get_value(...)`**. Bare `create_timer(0.5)` → rejected.
- UI colors/spacing/font sizes — only via **`UiTheme`**. No inline `Color(...)` in presentation. No hardcoded `FONT_SIZE = 9`.
- Hex polygon geometry — via `HexGeometry.flat_top_polygon(layer.tile_set.tile_size)`. Single tileset: `scenes/arena/tilesets/hex_terrain.tres`.
- Content (modifiers, enemies, spells, dialogues) — JSON in `data/`. No hardcoded content in scripts.

## Branches

| Branch | Push rights |
|---|---|
| `main` | Andrey, Egor — manually only. Stable. |
| `staging` | PR only, ≥1 approval. Integration. |
| `<user>/<task>` | Personal work branches. `<user>` ∈ {andrey, egor, nikita, sergey, alexey, stasyan}. Merged into staging via PR. |

Flow: branch off staging → work → push → open PR to staging → review → merge. `staging → main` happens periodically when staging is stable, by Andrey or Egor.

## Stack

- Godot **4.6.2 stable** (patch versions must match)
- **GDScript only** — no C#, no GDExtension, no addons without team agreement
- JSON + `.tres` for content; no databases
- Desktop builds (Win / Mac / Linux); web only if time permits

## Team

7 people, 6 in repo, +Katya (art) via file exchange.

| Role | Person |
|---|---|
| UX integration, polish, audio direction, glue | Andrey |
| Hex arena, battle loop, enemies, skill engine | Egor |
| Spell-craft / modifier engine | Sergey |
| Roguelike loop, waves, portal, meta-screens UI, DialogueManager | Alexey |
| Dialogue content, flavor texts, tone | Nikita |
| Balance, modifier content, playtest | Stasyan |
| Tiles, portraits, icons, VFX | Katya (no repo access) |

Module ownership is **claim-on-PR** — first PR for a module owns the public API. Current claims tracked in `CLAUDE.md`.

## License

See `LICENSE`.
