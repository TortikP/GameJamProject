# 017-doc-fixes — plan

## Approach

Один кластер, один commit. Pack строго doc-only — в нём ровно одно finding'овое изменение в `CLAUDE.md`. Spec/plan/tasks для трассировки с findings.md (как у 013/015/016).

## Files affected

- EDIT `CLAUDE.md` §Hard rules / Architecture — правило #3 (line 42).

## Specifics

### F-023 — точная замена

Before (line 42):
```
3. Autoloads (GameSpeed, EventBus, Logger, AudioDirector, UiTheme) are accessible from anywhere.
```

After:
```
3. Autoloads (GameSpeed, EventBus, AudioDirector, UiTheme) are accessible from anywhere. Stateless logging via `GameLogger` — preload-only utility, see traps table.
```

Rationale:
- `Logger` никогда не был autoload — был только `class_name Logger` который коллизился с native Godot class и был переименован в `GameLogger` в `andrey/rename-logger-to-gamelogger`.
- Финальная форма `GameLogger` — preload-only по trap table требованию (line 180 того же CLAUDE.md). Никаких `class_name`, никаких autoload-регистраций.
- Полный список autoload'ов в `project.godot` шире (12 штук), но правило #3 даёт representative sample, не exhaustive. Не расширяю — это вне scope F-023.
- Ссылка «see traps table» бесполезна без раздела заголовка, но он уже называется «Known Godot 4.6 traps» в том же файле; читатель найдёт через Ctrl+F.

## Smoke

Doc-only. No runtime smoke.

Sanity: `grep -n "Logger" CLAUDE.md` после правки должен вернуть только trap table (line 180) и наш новый GameLogger-абзац — никакого `Logger` в списке autoload'ов.

## HANDOFF.md links

- 012-ultrareview/findings.md F-023 row + §"Refactor PR backlog" — slicing source.
