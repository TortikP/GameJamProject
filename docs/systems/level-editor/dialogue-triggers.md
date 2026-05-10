# Dialogue Triggers — Designer Reference

Where to author level-scoped event→dialogue bindings. The system itself
ships in Spec 003 (DialogueManager), with the in-engine editor delivered
by Spec 039 (DialogueTriggerPanel) and re-housed inside the unified
WaveSettingsPanel as part of Spec 061.

## Concept

A **dialogue trigger** is a Dictionary inside `LevelData.dialogue_triggers[]`.
Each entry says: "when **event** fires and the optional **conditions** all
match, queue **dialogue_id** with the chosen **play_mode**". Triggers live
on the level (not the wave). Per-wave scoping happens by adding a
`wave_index` condition.

The runtime owner is `LevelDialogueDirector` (Spec 003 / 039). Editor code
never reads triggers at runtime; it only writes the schema fields.

## Where to find it

Open the level editor (Ctrl+E from the main menu, or via Game Editor's
playtest button). The right-edge **Wave Settings** panel has two trigger
sections:

- **Level → Dialogue Triggers** — full CRUD: add / edit / dupe / delete.
  Edits **all** triggers regardless of which wave they apply to.
- **Dialogue Triggers (this wave)** — read-only mirror filtered by
  `conditions.wave_index == active_wave`. Click a row to jump back to the
  Level section's edit form.

## Schema

```json
{
  "id": "intro_warning",
  "event": "wave_started",
  "dialogue_id": "lvl3_pre_boss",
  "play_mode": "request",
  "conditions": {
    "wave_index": 2,
    "once_per_run": true
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique within the level. Used in logs and once-tracking. **Not** the dialogue. Validation rejects empty / duplicate. |
| `event` | yes | One of the curated events below, or any signal name (Custom...). |
| `dialogue_id` | yes | Picked from `DialogueDB` — what plays when fired. **Distinct from `id`**. |
| `play_mode` | yes | `"request"` (queue if nothing is playing) or `"play"` (interrupt). Default: `request`. |
| `conditions` | optional | Filter dictionary. All listed conditions must match for the trigger to fire. |

## Curated events

```
level_started
wave_about_to_start
wave_started
wave_cleared
world_turn_ended
skill_offer_about_to_open
skill_offer_closed
level_completed
```

These are the EventBus signals `LevelDialogueDirector` listens to. The
"Custom..." option in the dropdown lets you bind to any other signal
name; spelling errors silently never fire (no compile-time check).

## Conditions cookbook

All keys are optional. When present, all must match.

- `wave_index` (int) — fire only when `_current_wave_index == this`.
  Also used by the Wave Settings panel's wave-mirror filter.
- `absolute_turn` (int) — fire only on this exact `world_turn_ended` count
  since `level_started`.
- `cleared_in_turns_lt` (int) — for `wave_cleared`: fire only if the
  wave was cleared with fewer than this many turns into the wave.
  Designer carrot for "speed-clear bonus dialogue".
- `chance` (float, 0..1) — pass a uniform-random gate. Default 1.0.
- `mood` (string) — match `RunMood.current`. Useful for branching by
  the run's emotional state (Spec 050+).
- `once_per_run` (bool) — fire at most once per run regardless of how
  many times the conditions match.

## `id` vs `dialogue_id`

The most common authoring mistake. Mnemonic:

- **`id`** — the trigger's name. Designer-only. Shows up in `GameLogger`.
  "intro_warning_a", "boss_taunt_v2", whatever helps you tell triggers
  apart in the list.
- **`dialogue_id`** — picked from a dropdown sourced from `DialogueDB`.
  This is what the player actually hears/reads.

Both can be the same string, but the panel always shows them as
separate rows.

## Cross-references

- Spec 003 — DialogueManager (the runtime system).
- Spec 039 — DialogueTriggerPanel (original editor, deprecated by 061).
- Spec 061 — WaveSettingsPanel (current home).
- `data/maps/_schema.md` §dialogue_triggers — JSON-side documentation.
- `scripts/runtime/level_dialogue_director.gd` — runtime evaluation code.
