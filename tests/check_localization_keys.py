#!/usr/bin/env python3
"""Spec 061 smoke automation — localization key presence check.

Scans .gd and .tscn for `ui_*` keys (string literals and StringName literals)
passed to Localization.t() / tr() / inline references, and verifies each key
is present in en.json AND ru.json with a non-empty value.

Scope: ui_* namespace only (UI labels). Other namespaces (item_, ability_,
character_, etc.) are content keys with their own validation rhythm — adding
them here would just make this test noisy.

Run: python3 tests/check_localization_keys.py
Exit: 0 = green, 1 = at least one missing/empty key.
"""
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
LOC_DIR = REPO / "data" / "localization"
BASELINE_PATH = pathlib.Path(__file__).resolve().parent / "localization_baseline.txt"

# Match: "ui_..." or &"ui_..." anywhere in a .gd / .tscn file.
# Trailing underscore is rejected to skip concat-prefix patterns like
# `Localization.t("ui_foo_" + variant, ...)` — those aren't real keys, just
# string-builder fragments.
KEY_RE = re.compile(r'&?"(ui_[a-z](?:[a-z0-9_]*[a-z0-9])?)"')

# Subdirectories not worth scanning.
SKIP_PARTS = {".git", ".godot", ".import", "addons"}


def load_baseline() -> set:
    """Pre-existing misses we don't want to block PRs on. See baseline file header."""
    if not BASELINE_PATH.exists():
        return set()
    keys: set = set()
    for line in BASELINE_PATH.read_text(encoding="utf-8").splitlines():
        s = line.split("#", 1)[0].strip()
        if s:
            keys.add(s)
    return keys


def find_used_keys() -> set:
    keys: set = set()
    for ext in ("*.gd", "*.tscn"):
        for f in REPO.rglob(ext):
            if any(p in SKIP_PARTS for p in f.parts):
                continue
            try:
                text = f.read_text(encoding="utf-8")
            except Exception:
                continue
            keys.update(KEY_RE.findall(text))
    return keys


def load_locale(name: str) -> dict:
    p = LOC_DIR / f"{name}.json"
    return json.loads(p.read_text(encoding="utf-8"))


def main() -> int:
    used = find_used_keys()
    en = load_locale("en")
    ru = load_locale("ru")
    baseline = load_baseline()

    print(f"[check_localization_keys] used ui_* keys: {len(used)}")
    print(f"[check_localization_keys] en.json: {len(en)} keys, ru.json: {len(ru)} keys")
    print(f"[check_localization_keys] baseline (pre-existing misses): {len(baseline)}")

    def is_missing(d: dict, key: str) -> bool:
        return key not in d or not str(d[key]).strip()

    missing_en_all = {k for k in used if is_missing(en, k)}
    missing_ru_all = {k for k in used if is_missing(ru, k)}

    # New regressions — anything missing that isn't in the baseline.
    new_en = sorted(missing_en_all - baseline)
    new_ru = sorted(missing_ru_all - baseline)

    # Stale baseline entries — keys that are no longer missing or no longer used.
    stale_baseline = sorted(
        k for k in baseline if k not in missing_en_all and k not in missing_ru_all
    )
    if stale_baseline:
        print(f"  hint: {len(stale_baseline)} stale baseline entries (no longer missing) — remove from localization_baseline.txt:")
        for k in stale_baseline:
            print(f"    - {k}")

    if not new_en and not new_ru:
        print("[check_localization_keys] OK")
        return 0

    print("[check_localization_keys] FAIL — new regressions (not in baseline):")
    if new_en:
        print(f"  missing/empty in en.json ({len(new_en)}):")
        for k in new_en:
            print(f"    - {k}")
    if new_ru:
        print(f"  missing/empty in ru.json ({len(new_ru)}):")
        for k in new_ru:
            print(f"    - {k}")
    print("  → add the translations, OR if knowingly deferred, add the key to tests/localization_baseline.txt with owner comment.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
