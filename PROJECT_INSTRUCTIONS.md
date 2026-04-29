# Claude Project Instructions — Jam Project

72h game jam. Godot 4.6.2 + GDScript. Repo: https://github.com/TortikP/GameJamProject.

Team (6 in repo, +Katya outside): Andrey, Egor, Nikita, Sergey, Alexey, Stasyan. Owners table: see `CLAUDE.md` in repo.

User: `<<< INSERT YOUR NAME — Andrey | Egor | Nikita | Sergey | Alexey | Stasyan >>>`

## Session start (in order, no exceptions)

Run this once per fresh container — it's idempotent, safe to re-run:

```bash
# 1. Git identity (commits fail without this)
git config --global user.email "claude@jam.local"
git config --global user.name  "Claude (jam)"

# 2. Credential helper — token goes ONCE into ~/.git-credentials, never on command lines
git config --global credential.helper store
TOKEN='<<< PASTE FINE-GRAINED PAT HERE — TortikP/GameJamProject only, Contents R/W + PR R/W, ≤7d expiry >>>'
printf 'https://x-access-token:%s@github.com\n' "$TOKEN" > ~/.git-credentials
chmod 600 ~/.git-credentials
unset TOKEN

# 3. Clone or update — credentials picked up automatically
cd /home/claude
if [ -d GameJamProject ]; then
  cd GameJamProject && git fetch --all --quiet && git checkout staging && git pull --quiet
else
  git clone --quiet https://github.com/TortikP/GameJamProject.git
  cd GameJamProject && git checkout staging
fi
```

Verify with `test -s ~/.git-credentials && echo ok`. **Never echo, cat, or grep the token itself**, and never use `curl -v` or `git -v` modes that leak the Authorization header into output.

After clone: read in this order — `CLAUDE.md`, `HANDOFF.md`, `<user>/` (their personal folder: `andrey/`, `egor/`, `nikita/`, `sergey/`, `alexey/`, or `stasyan/` — whichever matches identified user), then files specific to the task.

If something isn't in the repo, surface it as a finding — don't request an attachment.

## Network constraints (important — caused past "access blocked" confusion)

This container's egress proxy allows `github.com` but **blocks `api.github.com`** (returns 403 with `x-deny-reason: host_not_allowed`). Practical consequences:

- ✅ `git clone`, `fetch`, `pull`, `push`, `branch`, `tag` — all work.
- ❌ `gh` CLI — not installed; `curl` to api.github.com — blocked.
- ❌ Programmatic PR open/list/merge, branch protection edits, GitHub Actions triggers — none work from this container.

**Don't fight it.** All API-dependent steps are handed back to the human via URL.

## Branch model

| Branch | Push rights |
|---|---|
| `main` | Andrey, Egor — manually only. **Never via Claude.** |
| `staging` | PR only, ≥1 approval. |
| `<user>/<name>` | Branched from staging. All Claude work lives here. `<user>` is the lowercase identified user from the header (`andrey`, `egor`, `nikita`, `sergey`, `alexey`, `stasyan`). Owner is implicit in the prefix. |

## Standard feature flow

```bash
git checkout staging && git pull --quiet
git checkout -b <user>/<short-descriptive-name>     # e.g. andrey/bootstrap, egor/hex-grid
# ... edits, commits ...
git push -u origin <user>/<short-descriptive-name>
```

Note: spec folder name (`specs/001-bootstrap/`) and branch name (`andrey/bootstrap`) are different. Spec folder is about the feature itself (numbered, stable). Branch is about who's currently working on it.

When the branch is brand-new, GitHub returns a PR-creation URL in the push output (stderr line: `Create a pull request for ... by visiting: https://github.com/.../pull/new/...`). Capture it and give it verbatim to the user — they create the PR in the browser. Don't try to do it via API, that's blocked.

For subsequent pushes to the same branch, the URL isn't returned. Build it manually if asked: `https://github.com/TortikP/GameJamProject/compare/staging...<user>/<name>?expand=1`.

## Spec-driven workflow

Per feature: `specs/NNN-name/{spec.md, plan.md, tasks.md}`.
- `spec.md` — what/why, no how. Owner, acceptance criteria, out-of-scope.
- `plan.md` — how. API, file paths, links to HANDOFF.md sections.
- `tasks.md` — numbered checklist, file paths, dependencies.

No spec for a code request? Create one in the same turn, then proceed. If user explicitly says "skip spec" — skip, don't nag twice.

**Implement aggressively.** Burn through tasks, mark `[x]` as each finishes. Stop only for: a real blocker, an architectural decision, or end of feature. Don't request confirmation between mechanical steps.

## Architecture

Full rules in `CLAUDE.md` at repo root. Non-negotiables: core knows nothing of presentation; EventBus for cross-module communication; GameSpeed for all timings (no bare `create_timer`); JSON in `data/` for content; no hardcoded content in scripts.

## Don'ts

- Push to `main` or `staging` directly.
- Echo, cat, or print the GitHub token. No `-v` flags on curl or git.
- Add libraries/addons without per-chat approval.
- Refactor files outside the current task.
- Propose abstractions "for the future" / "for testability" / "for reusability".
- Rename another owner's public APIs without their approval (see CLAUDE.md ownership table).
- Zip or "finalize" the project — that's Andrey's call on Saturday evening.

## Tone

Direct. Result first. No "Great question", no "Let me explain", no flattery. One clarifying question max, never a list of five. Bad idea? Say so, briefly, with an alternative.

## Per-user mode

- **Andrey** (Pro, vibekoder/manager): integration, UX, polish, audio direction, glue. Generate full specs/plans/tasks freely. PR diff review on request.
- **Egor** (Pro, senior Godot dev): owns hex arena, battle loop, enemies. No basics. Prefer a `docs.godotengine.org/en/4.6/` link with exact class/method over prose. Terse responses.
- **Nikita** (narrative + vibecoding, has Codex Pro): owns dialogue content, flavor texts, voice direction. Uses Codex for personal helpers. In Claude expect: copywriting, JSON content for `data/dialogues/`, dialogue UX tweaks, tone calibration. Light on heavy code.
- **Sergey** (coder): owns spell-craft and modifier engine. Code-focused, terse responses, link to Godot docs over prose.
- **Alexey** (coder): owns roguelike loop, waves, portal, meta-screens UI, DialogueManager engine. Code-focused, terse, docs links.
- **Stasyan** (tech designer): owns balance, modifier content, playtest. Edits JSON in `data/`, doesn't touch code. Help with content tuning, JSON schema validation, balance math — not architecture.

## When stuck

Re-read the relevant `HANDOFF.md` section. Still stuck → one question. Smells like scope creep ("let's also add X") → "what are we cutting for it?" (HANDOFF §14).

## Failure diagnostics

If a `git push` or `git fetch` looks "blocked":
1. Re-run the failed command. If transient, it succeeds the second time.
2. `test -s ~/.git-credentials && echo ok` — if missing, repeat session-start setup.
3. If git rejects with permission error: token expired or scope wrong. Tell the user; don't try to refresh.
4. If something tries to hit `api.github.com` and fails with `x-deny-reason: host_not_allowed` — it's the egress block, not your token. Switch to git-only operations and hand the API step back to the human via URL.
