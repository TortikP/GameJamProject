# tests/

Auto-tests for the GameJamProject. Currently scoped to data-integrity and
localization-coverage smokes — UI behaviour stays manual (see
`docs/testing.md` once that exists, or per-spec PR.md smoke checklists).

## Convention

- One file per concern. Name with the spec number that introduced it:
  `test_NNN_<what>.gd` for Godot scripts, `check_<what>.py` for pure Python.
- Each test exits 0 on green, 1 on failure. No GUT, no third-party runner —
  keep the bar low so anyone can add a test without per-PR addon approval.
- If a test catches pre-existing issues that aren't this PR's responsibility,
  use a `*_baseline.txt` next to the test rather than failing all PRs on
  legacy debt. Document the cleanup in `docs/tech-debt.md`.

## What's here

### `test_061_migration.gd`

Spec 061 — covers the data-integrity portion of T-061-74/75/76 (Φ-12 backward-
compat smoke). For every map in `data/maps/*.json` (excluding scratch files):

- migrates v1/v2 → v3 via `LevelData.from_dict()`
- asserts schema version, per-wave field types, advance_mode enum
- runs `LevelData.validate()` and asserts no non-WARN errors (skipped for
  files in `maps_validate_baseline.txt` — see that file's header)
- mirrors the editor save→reload path (`to_dict → JSON.stringify →
  JSON.parse_string → from_dict → to_dict`) and asserts the dict is
  idempotent — F-061-IMPL-1 catch.

Does **not** cover: editor UI behaviour, switcher rendering, autosave debounce,
playtest-time advance_mode logic, panel visibility. Those stay manual in
`specs/061-wave-data-and-settings/PR.md`.

```sh
# Linux/macOS, godot in PATH:
godot --headless --script tests/test_061_migration.gd

# Windows PowerShell — full path or alias if godot.exe is not in PATH:
& "C:\Games\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64.exe" --headless --script tests/test_061_migration.gd
```

Filename filter — these are skipped automatically: `__*.json` (autosave/playtest
scratch), `Untitled*.json`, `untitled.json`, `maps_*_name.json` (spec-040 test
detritus). If you author a real map starting with one of those prefixes, rename it.

### `check_localization_keys.py`

Verifies every `ui_*` translation key referenced in `*.gd` / `*.tscn` is
present and non-empty in both `data/localization/en.json` and `ru.json`.

Pre-existing misses are listed in `localization_baseline.txt` so this test
fails only on **new** regressions — see that file's header for the policy.

```sh
python3 tests/check_localization_keys.py
```

## Running everything

No wrapper yet — invoke each test directly. Add one when there are >5 tests
and a wrapper saves more time than it costs.
