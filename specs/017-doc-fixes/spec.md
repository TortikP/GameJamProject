# 017-doc-fixes — doc-only

**Owner:** Andrey (per `specs/012-ultrareview/findings.md` §016-doc-fixes backlog).
**Implementer:** Egor (override of AC-A5 owner-implements rule, granted in chat — same pattern as 013, 015, 016).
**Status:** Active.

## Назначение

Закрытие doc-only findings из 012-ultrareview, не влезших в 016-cleanup-wave.

Слот 016 ушёл под `egor/016-cleanup-wave`. Findings.md помечает этот pack как «016-doc-fixes», но реальный номер бамплен на 017 для прослеживаемости с веткой `egor/017-doc-fixes`.

## Findings — что закрываем

| ID | Sev | Файл | Что не работает | Кластер |
|---|---|---|---|---|
| F-023 | P3 | `CLAUDE.md` §Architecture #3 | «Autoloads (GameSpeed, EventBus, **Logger**, AudioDirector, UiTheme) are accessible from anywhere» — `Logger` не autoload. Был переименован в `GameLogger` и переведён на preload-only (см. traps table в том же файле). Doc drift. | `A-doc` |

## Out of scope

- Любые code/spec edits — этот pack строго doc-only по конструкции.
- Дальнейший audit CLAUDE.md / HANDOFF.md / spec'ов — не в scope. Если найду doc drift по дороге — фиксить отдельной веткой, не пихать сюда.

## Acceptance criteria

- **AC-1 (F-023):** В `CLAUDE.md` §Hard rules / Architecture правило #3 упоминание «`Logger`» заменено. Реальная картина:
  - `GameLogger` — НЕ autoload, а preload-only utility (`const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")` у каждого consumer'а).
  - Реальные autoloads списка-примера: `GameSpeed`, `EventBus`, `AudioDirector`, `UiTheme` (4, без Logger).
  - Решение: вычеркнуть `Logger` из inline списка autoload'ов и дописать одно предложение про `GameLogger` со ссылкой на traps table.
  - Текст после правки (target):
    > 3. Autoloads (GameSpeed, EventBus, AudioDirector, UiTheme) are accessible from anywhere. Stateless logging via `GameLogger` — preload-only utility, see traps table.
- **AC-2 (никаких code touches):** `git diff staging --stat` после всех коммитов trogs только `CLAUDE.md` и `specs/017-doc-fixes/`. Ничего больше.

## Зависимости

- **Upstream:** 016 мержен в staging. ✓
- **Downstream:** —

## Risk

- **Логи `Logger.info(...)` в чьём-то WIP-стэше.** F-023 — только doc; правка не ломает ничего runtime'но. Если у кого-то ещё валяется `Logger.info` в незаезженной ветке — это сломается на parse'е независимо от нашей правки CLAUDE.md (Godot 4.6 trap про collision с native class). Не наш фикс.
