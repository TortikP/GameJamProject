# 017-doc-fixes — tasks

Один кластер, один commit (плюс spec/closeout).

## A — F-023 (CLAUDE.md autoload list)

- [ ] A1. `CLAUDE.md` §Hard rules / Architecture — правило #3 (line 42): убрать `Logger` из inline списка autoload'ов, дописать предложение про `GameLogger` (preload-only, see traps table). Точный target-текст — см. plan.md.
- [ ] A2. Sanity: `grep -n "Logger" CLAUDE.md` возвращает только trap table line + новый GameLogger-абзац. Никакого `Logger` в списке autoload'ов.
- [ ] A3. Commit: `docs(017): F-023 — drop Logger from autoload list, link GameLogger to traps table`.

## B — Closeout

- [ ] B1. Отметить все `[x]` в этом файле.
- [ ] B2. Commit: `docs(017): mark tasks [x]`.
- [ ] B3. `git push -u origin egor/017-doc-fixes`. PR-URL отдать Egor'у в чат.

## Зависимости

- A независим (single-line edit).
