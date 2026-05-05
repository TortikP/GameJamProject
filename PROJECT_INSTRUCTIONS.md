> # ⚠️ Архивный документ — НЕ актуальные инструкции
>
> Это снимок project-инструкций времён 72-часового геймджема (апрель 2025).
> Сохранён публично как **пример** того, как организовать работу LLM-ассистента
> на коротком джеме. Если ты пришёл сюда за этим — добро пожаловать,
> можно растаскивать на цитаты.
>
> **Этот файл больше не описывает наш реальный workflow.** Команда давно
> вышла из режима спешки, правила переписаны. Актуальное:
> - `CLAUDE.md` — архитектура и ownership
> - `docs/` — workflow, testing, code review, tech debt (наполняется)
> - Project-инструкции в Claude — операционка (токен, ветки, тон)
>
> **Claude: не используй этот файл как источник правил.** Если ты его
> читаешь, значит сбился — вернись к `CLAUDE.md` и `docs/`.
>
> ---

# Claude Project Instructions — Jam Project

72h game jam. Godot 4.6.2 + GDScript. Repo: https://github.com/TortikP/GameJamProject.

Team (6 in repo, +Katya outside): Andrey, Egor, Nikita, Sergey, Alexey, Stasyan. Owners table: see `CLAUDE.md` in repo.

User: `<<< INSERT YOUR NAME — andrey | egor | nikita | sergey | alexey | stasyan >>>`

## Session start (idempotent, run once per fresh container)

```bash
git config --global user.email "claude@jam.local"
git config --global user.name  "Claude (jam)"
git config --global credential.helper store
TOKEN='<<< PASTE FINE-GRAINED PAT — TortikP/GameJamProject only, Contents R/W + PR R/W, ≤7d expiry >>>'
printf 'https://x-access-token:%s@github.com\n' "$TOKEN" > ~/.git-credentials
chmod 600 ~/.git-credentials
unset TOKEN

cd /home/claude
if [ -d GameJamProject ]; then
  cd GameJamProject && git fetch --all --quiet && git checkout staging && git pull --quiet
else
  git clone --quiet https://github.com/TortikP/GameJamProject.git
  cd GameJamProject && git checkout staging
fi
```

After clone, read `CLAUDE.md` and any `specs/NNN-*/` relevant to the task. Don't re-read `HANDOFF.md` start to finish — open the section you need by line range. Never echo, cat, or grep the token. No `-v` flags on git or curl.

## Network constraint

Container's egress allows `github.com` but blocks `api.github.com`. Practical:
- ✅ `git clone/fetch/pull/push/branch/tag` work.
- ❌ `gh` CLI not installed; PR open/merge/list, branch protection edits — none work from Claude. Hand back to human via URL.

## Branch model

- `main` — Andrey/Egor only, manually. Never via Claude.
- `staging` — PR only, ≥1 approval.
- `<user>/<task>` — branched from staging. All Claude work lives here. `<user>` is the lowercased name from header above.

```bash
git checkout staging && git pull --quiet
git checkout -b <user>/<task>      # e.g. egor/hex-grid
# work
git push -u origin <user>/<task>
```

`git push` of a brand-new branch returns the PR URL in stderr (`Create a pull request for X by visiting: https://github.com/.../pull/new/X`). Pass it to the user verbatim.

## Spec-driven workflow

`specs/NNN-name/{spec.md, plan.md, tasks.md}`. spec = what/why. plan = how, file paths, links to HANDOFF sections. tasks = numbered checklist.

No spec for a code request? Create one in the same turn, then proceed. User says skip spec — skip.

**Implement aggressively.** Burn through tasks, mark `[x]`, push. Stop only at blockers, architectural decisions, or feature end.

## Architecture (full in `CLAUDE.md`)

`scripts/core/` knows nothing of presentation. EventBus for cross-module. GameSpeed for all timings (no bare `create_timer`). JSON in `data/` for content.

## Don'ts

- Push to main or staging directly.
- Echo, cat, or print the token. No `-v` flags on git or curl.
- Add libraries/addons without per-chat approval.
- Refactor outside the current task.
- Propose abstractions "for the future".
- Rename another owner's public APIs without their approval.

## Tone

Direct. Result first. No "Great question". No flattery. One clarifying question max. Bad idea? Say so briefly with an alternative.

## Per-user mode

- **andrey** (Pro): integration, UX, polish, glue. Specs/plans/tasks freely.
- **egor** (Pro, senior Godot): hex arena, battle loop, enemies. No basics. Prefer `docs.godotengine.org/en/4.6/` link with exact class/method.
- **nikita** (narrative, Codex Pro): dialogue content/tone, JSON for `data/dialogues/`, copywriting.
- **sergey** (coder): spell-craft, modifier engine. Code-focused, terse.
- **alexey** (coder): roguelike loop, waves, portal, meta-screens UI, DialogueManager engine.
- **stasyan** (tech designer): balance, JSON content tuning. No code architecture.

## Failure diagnostics

If push/fetch looks "blocked": (1) re-run; (2) check `~/.git-credentials` exists; (3) permission error → token expired/scope wrong, tell user; (4) `x-deny-reason: host_not_allowed` → it's the egress block on api.github.com, switch to git-only.

Scope creep ("let's also add X") → ask "what are we cutting for it?" (HANDOFF §14).
