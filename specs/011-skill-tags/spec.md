# 011-skill-tags — spec

**Owner:** Egor (skill-system module owner — claim-on-PR через 007)
**Status:** Draft — готов к /plan-/tasks

## Цель

Carve-out из `008/AC-S5` (enemy AI, Сергей): отдельным маленьким PR добавить `tags: Array[StringName]` на `Skill` + парсинг + миграция 4 production JSONов. Без этого 008 не может писать data-driven правила выбора скиллов по тегу — а 008 — длинный PR с AI/CastIntent/godmode-rename, и не должен блочить мой Skill API.

После мержа этой фичи Сергей строит 008 поверх. Ровно тот «commit (1)» из split, на который я просил Сергея согласиться в обсуждении 008.

Соответствует pillarsам: §1.5.2 (симметрия) — теги одинаковы для player/enemy скиллов, AI потом фильтрует те же сущности что юзает игрок.

## Что меняется

| Слой | Сейчас | После 011 |
|---|---|---|
| `Skill` Resource | поля `id`, `cooldown`, `abilities` | + `tags: Array[StringName]` (default `[]`) |
| `SkillDatabase._build_skill` | парсит `id`, `cooldown`, `abilities` | + парсит `tags` |
| `data/skills/skill_*.json` (4 production) | без поля | `"tags": [...]` добавлен |
| `data/skills/test_*.json` | — | **не трогать** (мои внутренние тесты, AI 008 их не выбирает по AC-G11) |

## Acceptance criteria

- **AC-T1**: `Skill` — добавлено `@export var tags: Array[StringName] = []` после `abilities`. Skill API freeze: `cast`, `is_ready`, `tick_cooldown`, `predicted_damage_to`, `get_ability_ids`, `can_apply` — сигнатуры не меняются, ничего не переименовывается. Никаких геттеров/сеттеров на `tags` — голое поле, читать напрямую.
- **AC-T2**: `SkillDatabase._build_skill` читает `data.get("tags", [])`. Отсутствие ключа в JSON → пустой default (backward-compat). Если ключ есть, но не Array → `GameLogger.warn("SkillDatabase", "<id>: 'tags' must be array, got <type> — using []")` и пустой default. Каждый элемент оборачивается в `StringName(t)`.
- **AC-T3**: 4 production JSONа размечены ровно так:
  - `skill_debug_punch.json` → `"tags": ["damage"]`
  - `skill_melee_punch.json` → `"tags": ["damage"]`
  - `skill_manekin_attack.json` → `"tags": ["damage"]`
  - `skill_knockback_punch.json` → `"tags": ["damage", "knockback"]`
- **AC-T4**: `test_*.json` (4 файла: `test_area_strike`, `test_chain_lightning`, `test_target_area_strike`, `test_vamp_strike`) — поля `tags` НЕ добавляется. Пустой default → AI их не выберет, что и нужно по 008/AC-G11. Если в будущем понадобится, добавим отдельным change — не в этом PR.
- **AC-T5**: 007/plan.md schema example (`### data/skills/*.json`) — добавлено поле `tags` в пример (doc-fix), чтобы новый contributor не пропустил.
- **AC-T6**: Smoke: запуск проекта, `SkillDatabase` логирует прежнее количество skills (`loaded N skills`, N = сколько было до PR), `[Skill] manekin_attack cast by ...` работает на манекенах как до PR, Q/W/E/R (или 1/2/3/4) в godmode (debug skills) кастуются.

## Out of scope

- AI-логика выбора скилла по тегу — это 008/AC-X3.
- Telegraph color mapping по primary-тегу — это 008/AC-I4 (плюс координация с Андреем по 009 UI Kit).
- Tags на `Ability` — Сергей в 008/Q-AI-1 это явно отверг, теги живут только на `Skill`.
- Tags на `Actor` (как «класс/архетип») — out of scope, не нужны.
- Валидатор тегов / справочник допустимых значений в коде — не нужно. Строки свободного формата. Список semantic-значений зафиксирован в 008/AC-I4 (`damage`, `damage_aoe`, `knockback`, `heal`, `control`, `debuff`, `buff`, `summon`, `mobility`), но enforce'а нет — JSON может писать что угодно, AI просто не сматчит неизвестное.
- Tags на test_*.json — AC-T4.
- `data/abilities/*.json` (одиночные ability как top-level сущность из 007/plan §Data schemas) — на эту фичу не трогаются. Ability tags явно нет.

## Зависимости

- **Upstream:** 007 merged (Skill/Ability/SkillDatabase в их текущем виде).
- **Downstream:** 008 (Сергей) — после мержа 011 он пишет plan.md/tasks.md и реализует AI-планировщик. Его commit (1) исчезает — этот PR его и есть.

## Координация

- **Сергей:** ему отдельный пинг когда PR открыт — спека 008 ссылается на `Skill.tags` как на existing field после 011. Он апдейтит 008/AC-S5 в плане-/tasks-фазе.
- **Стасян:** не затронут. Его enemy/behavior JSONы появятся после движка 008.
- **Андрей (009):** не затронут. Telegraph color mapping не входит в 011.
