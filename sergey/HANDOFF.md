# Sergey — handoff

Личная заметка для продолжения работы в новом чате/на другом устройстве. Если ты в новом чате — открой этот файл первым после `CLAUDE.md` и `HANDOFF.md`.

---

## Активная задача: spec-008-enemy-ai

**Ветка:** `sergey/spec-008-enemy-ai`
**Last commit:** `d63a0fd` — spec(008): close Q-AI-1..6
**PR (предыдущий, merged):** #28 — первая версия спеки с открытыми вопросами
**PR (текущий, нужно открыть):** https://github.com/TortikP/GameJamProject/compare/staging...sergey/spec-008-enemy-ai?expand=1
**Статус:** spec.md закрыт по всем Q-AI-1..6, готов к /plan. Ждём review.

## Что сделано

- `specs/008-enemy-ai/spec.md` — финальная версия спеки, все 6 вопросов закрыты, выровнено под merged 007 (Skill, не Ability; tags на Skill).
- Backward-compat расписан явно: `default_melee` JSON воспроизводит текущий manekin AI бит-в-бит. Тест #1 в Acceptance scenarios.
- Migration `attack_skill_id` + `attack_intent_coord` → `cast_intent` Resource — расписано в AC-I2.
- Plan/tasks ещё **НЕ написаны** — намеренно, ждём подтверждения ехать в /plan.

## Resolved questions (для контекста)

| Q | Решение | Что значит |
|---|---|---|
| Q-AI-1 | (b) | `Skill.tags`, не Ability |
| Q-AI-2 | (b) | Один action в ход; рывок-атака = Skill с move+damage abilities внутри |
| Q-AI-3 | (a) | Tiebreak — порядок в `actor.skills` |
| Q-AI-4 | (c) | Цвет hex по `Skill.tags[0]` (orange/green/purple/blue/gold/white) |
| Q-AI-5 | (a) | Композиция условий — 1 уровень, без вложенности |
| Q-AI-6 | (b)+(I) | policy fallback; нет якоря → `hold_position` + лог |

## Next actions (по приоритету)

1. **Юзер пингает Egor** про `Skill.tags` — additive поле, breaking-prefix не нужен, но координация требуется (его модуль). Жду подтверждения от юзера прежде чем идти в /plan.
2. **Юзер открывает PR** через URL выше. Ревьюит spec.md ещё раз свежим взглядом.
3. **Когда юзер скажет «go» — пишем `plan.md`:**
   - Архитектура `scripts/core/ai/`: `EnemyAIPlanner` (autoload), `BehaviorDatabase` (autoload), `BehaviorScenario`/`TacticRule`/`TacticCondition` (Resources).
   - JSON-схема `data/ai_behaviors/<id>.json` с примером `default_melee` (бит-в-бит как текущий manekin).
   - JSON-схема `data/enemies/<id>.json`.
   - Миграция: `Skill.tags` поле + tags на 4 production skills + удаление `attack_skill_id`/`attack_intent_coord` с manekin → `cast_intent` Resource.
   - Контракт между `EnemyAIPlanner.plan()` и `godmode_controller._resolve_cast_intent()`.
   - Telegraph color mapping (одно место в коде).
4. **Затем `tasks.md`** — пронумерованный чеклист с зависимостями.
5. **Implement** — только после approve plan/tasks.

## Что НЕ делать

- Не лезть в `core/abilities/`, `core/skills/` — это чужой модуль (Egor, 007).
- Не редактировать `Skill.tags` без пинга Egor.
- Не трогать баланс — это Стасян, после движка.
- Не писать plan/tasks без явного «go» от юзера.

## Координация и ownership

- **Egor (007)** — owner Skill/Ability системы. `Skill.tags` — additive расширение, согласовать в чате до merge.
- **Stasyan** — будет наполнять `data/ai_behaviors/*.json` и `data/enemies/*.json` после того как движок собран. Я даю ему JSON-схему в plan.md, он не лезет в код.
- **Andrey** — общая интеграция, polish. Если телеграф цвета конфликтует с UI kit (009) — согласовать.

## Reset для нового чата

В новом чате:

1. Project instructions поднимут окружение и склонируют репу автоматически.
2. После клона прочитай в этом порядке:
   - `CLAUDE.md` (конвенции)
   - `HANDOFF.md` (общий проектный контекст)
   - `sergey/HANDOFF.md` ← этот файл
   - `specs/008-enemy-ai/spec.md` (финальная спека)
   - `specs/007-skill-system/architecture.md` (что я могу/не могу трогать в чужом модуле)
3. Перед действием: `git checkout sergey/spec-008-enemy-ai && git pull`. Проверь что HEAD на `d63a0fd` или новее.
4. Жди от юзера команду «go» прежде чем писать plan/tasks.

## Полезные пути

| Что | Где |
|---|---|
| Финальная спека | `specs/008-enemy-ai/spec.md` |
| Архитектура 007 (для контекста) | `specs/007-skill-system/architecture.md` |
| Текущий примитивный AI (что заменяем) | `scripts/presentation/godmode/godmode_controller.gd` строки 508-664 |
| Текущий manekin (откуда уезжает `attack_skill_id`) | `scripts/presentation/godmode/manekin_view.gd` |
| Skill API (что вызываем) | `scripts/core/skills/skill.gd` |
| SkillDatabase | `scripts/core/skills/skill_database.gd` |
| Production skills (получают tags) | `data/skills/skill_*.json` (4 файла) |
| Test skills (теги пустые) | `data/skills/test_*.json` |
| EventBus signals | `scripts/infrastructure/event_bus.gd` |
