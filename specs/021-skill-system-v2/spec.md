# 021-skill-system-v2 — spec

**Owner:** Egor
**Status:** Ready for /implement (clarify-цикл закрыт в чате)
**Upstream:** 007-skill-system, 011-skill-tags

## Цель

Расширить схему Skill/Ability под нужды нарратива, AI-стратегий и системы прогрессии:

- Локализация (`name`, `tooltip`, `desc` — ключи) и пресентация (`sound`, `animation` — ID) зашиты в данные навыка.
- AI-фильтрация переименована из `tags` → `behaviour_tags` (имя соответствует роли поля).
- Нарративный мудскоринг: `mood: Array[StringName]` на Skill — задел под систему характера героя.
- Прогрессия: `level: int` на Skill, **каждый компонент способности (target/area/effect) сам реагирует на уровень внутри своей реализации** — не централизованный мутатор.
- Целе-таргет `entity` переименован в `actor` (соответствует именованию в коде, `class_name Actor`).
- `CreateEffect.game_object_id` → `entity_id` (терминологическое выравнивание).
- `ChainArea.radius` — явный параметр радиуса прыжка между звеньями (default 1, текущее поведение).

## Изменения схемы

### Skill (новые / переименованные поля)

```json
{
  "id": "skill_id",
  "name": "loc_key_for_name",
  "tooltip": "loc_key_for_tooltip",
  "desc": "loc_key_for_desc",
  "cooldown": 0,
  "behaviour_tags": ["melee", "damage"],   // переименовано из "tags"
  "mood": ["toxic", "apathetic"],           // новое
  "level": 0,                               // новое
  "abilities": [/* Ability[] */]
}
```

Все новые строковые поля — голые `String`/`StringName`, без валидации содержимого. Локализация резолвится отдельным сервисом (out of scope).

### Ability (новые поля)

```json
{
  "id": "ability_id",
  "sound": "sound_id_or_empty",          // новое — будущий AudioDB lookup
  "animation": "animation_id_or_empty",  // новое — будущая animation dispatch
  "target": {"kind": "actor", "range": 1},
  "area":   {"kind": "chain", "max_chain_length": 1},
  "effects": [{"kind": "damage", "duration": 0, "damage": 5}],
  "modifiers": []
}
```

`sound`/`animation` пока сохраняются на ресурсе и не диспатчатся — потребители появятся в отдельных фичах (AudioDB, Animation system).

### Targets

| kind | поля | поведение |
|---|---|---|
| `self` | — | резолвится в caster |
| `actor` | `range: int` (–1=any, 0=self, 1+=в N шагах) | переименовано из `entity` |
| `hex` | `range: int` | без изменений |
| `object` | `range: int` | stub, будет реализован после object-сущности |

### Areas

| kind | поля | поведение |
|---|---|---|
| `self` | — | резолвится в `[caster]` |
| `chain` | `max_chain_length: int`, `radius: int = 1` | BFS-цепь, каждый прыжок до `radius` гексов |
| `zone_circle` | `radius: int` | круг от primary, BFS layered |

`chain.radius` — новое явное поле. До 021 цепь хваталась только за прямых соседей (`get_walkable_neighbours`); теперь шаг между звеньями = до `radius` гексов BFS-расстояния.

`zone_cone` / `zone_arc` / `zone_line` остаются stub'ами как и в 007 — не входят в acceptance этой фичи, продолжают парситься без warn'ов.

### Effects

| kind | поля | прим. |
|---|---|---|
| `damage` | `damage: int` | без изменений |
| `heal` | `heal: int` | без изменений |
| `status` | `status: StringName` | без изменений |
| `move` | `move_type: StringName`, `move_distance: int` | без изменений |
| `create` | `entity_id: StringName` | переименовано из `game_object_id` |

Общие поля у всех (унаследованы из 007): `id`, `type`, `duration`, `requires_alive_target`.

## Уровень навыка (level scaling)

`Skill.level: int = 0` — единственное число. На каст пробрасывается в `Ability.cast(caster, ctx, level)`, далее в каждый компонент через `apply_level(level: int) -> void` на duplicate'е перед resolve/apply.

**Реакция на уровень — внутри каждой реализации компонента** (не централизованный мутатор в `Ability.cast`). Базовый класс — no-op, подклассы overrid'ят по необходимости.

Базовые паттерны (Egor):

| Параметр | Формула |
|---|---|
| `damage` | `damage * (1 + 0.2 * level)` → floor |
| `heal`   | `heal * (1 + 0.1 * level)` → floor |
| `range`  | `if range > 1: range += level` |
| `area` (radius / max_chain_length) | `if X > 1: X += level / 2` (целочисл. деление) |
| `duration` | `if duration > 1: duration += level` |

Применение на конкретные классы:

| Класс | Реакция |
|---|---|
| `DamageEffect` | `damage` по формуле |
| `HealEffect` | `heal` по формуле |
| `StatusEffect` | `duration` по формуле |
| `MoveEffect` | `duration` по формуле; `move_distance` НЕ скейлится (не указан в спеке) |
| `CreateEffect` | no-op |
| `ActorTarget` (был `EntityTarget`) | `range` по формуле |
| `HexTarget` | `range` по формуле |
| `ObjectTarget` | `range` по формуле |
| `SelfTarget` | no-op |
| `ChainArea` | `max_chain_length` по формуле; `radius` НЕ скейлится |
| `ZoneCircleArea` | `radius` по формуле |
| `SelfArea` | no-op |

## ability_id — keep

Вопрос Egor'а из исходного запроса: можно ли убрать `ability_id` за счёт `skill_id`. **Нельзя.**

- `EventBus.ability_cast.emit(caster, ability_id, targets)` — per-step UI-хук. Вампирик-навык эмитит 2 события (damage + heal) с разными ability_id; коллапс в skill_id ломает per-step VFX/звук/лог.
- `AbilityDatabase.get_ability(id)` — потребители: `actor_inspector` (тултипы), `cast_range_overlay`, `move_range_overlay`, `manekin_view`. Все нужают per-ability lookup.
- `skill_id` не дизамбигуирует N abilities одного навыка.
- Стоимость хранения: ~30 char/JSON. Стоимость удаления: переписать EventBus + 6 потребителей + потерять per-step dispatch.

Решение: `ability.id` остаётся обязательным.

## Acceptance criteria

### Структурные
- **AC-S1**: `Skill` имеет поля `id`, `name`, `tooltip`, `desc`, `cooldown`, `behaviour_tags`, `mood`, `level`, `abilities`. Поле `tags` удалено (rename, не coexist).
- **AC-S2**: `Ability` имеет поля `id`, `sound`, `animation`, `target`, `area`, `effects`, `modifiers`. `sound`/`animation` — `StringName`, default `&""`.
- **AC-S3**: `class_name EntityTarget` переименован в `ActorTarget`, файл `entity_target.gd` → `actor_target.gd`. JSON kind `"entity"` → `"actor"`.
- **AC-S4**: `CreateEffect.game_object_id` → `entity_id`. JSON-ключ — соответственно.
- **AC-S5**: `ChainArea` имеет `@export var radius: int = 1`. При `radius=1` поведение идентично pre-021.

### Уровень
- **AC-L1**: `AbilityTarget`, `AbilityArea`, `AbilityEffect` имеют метод `apply_level(level: int) -> void`, default no-op.
- **AC-L2**: Каждый non-stub подкласс (см. таблицу выше) реализует `apply_level` согласно формуле.
- **AC-L3**: `Ability.cast(caster, ctx, level: int = 0)` — level пробрасывается. На duplicate'ах вызывается `apply_level(level)`. Базовый ресурс не мутируется.
- **AC-L4**: `Skill.cast(caster, ctx)` читает `self.level` и пробрасывает в `Ability.cast(..., level)`.
- **AC-L5**: `Ability.predicted_damage_to(caster, target, ctx, level)` учитывает level (UI hover preview корректен). Skill.predicted_damage_to передаёт свой level.
- **AC-L6**: При `level = 0` итоговые числа идентичны pre-021 (нулевой регрессионный delta).

### Миграция / совместимость
- **AC-M1**: Все 8 production+test JSON-ов в `data/skills/` мигрированы под новую схему. Старые ключи (`tags`, `entity`, `game_object_id`) отсутствуют.
- **AC-M2**: Потребители `Skill.tags` (`enemy_ai_planner.gd`, `godmode_controller._telegraph_tag_for_skill`) обновлены на `.behaviour_tags`.
- **AC-M3**: Backward-compat шим не делается — рывковый rename, миграция в одном PR.

### Smoke / acceptance scenarios
- **AC-X1**: Запуск проекта → `SkillDatabase` загружает все skills без warn'ов; `AbilityDatabase` без warn'ов про unknown kinds.
- **AC-X2**: Godmode-сцена: 4 production-абилки (`debug_punch`, `melee_punch`, `manekin_attack`, `knockback_punch`) работают как до 021.
- **AC-X3**: AI-планировщик манекена выбирает `manekin_attack` через `behaviour_tags ∋ "damage"` (AI rule `default_melee.tag_priority = ["damage"]`).
- **AC-X4**: `test_vamp_strike` с `level: 2` — урон `100 * 1.4 = 140` (floor), heal `50 * 1.2 = 60` (floor). Лог через `GameLogger.info("SkillTest", ...)`.
- **AC-X5**: 5 новых test-combo JSON'ов (см. ниже) — каст из godmode debug-кнопки или через `SkillDatabase.get_skill(...).cast(...)` не падает.

## Test fixtures (combo coverage)

Создаются в `data/skills/`:

| Файл | target | area | effects | покрывает |
|---|---|---|---|---|
| `test_combo_actor_chain_damage.json` | `actor` r=–1 | `chain(2, radius=1)` | `damage(10)` | actor + chain multi-link |
| `test_combo_hex_circle_damage_status.json` | `hex` r=4 | `zone_circle(2)` | `damage(8)`, `status(burning, dur=2)` | hex + AoE + multi-effect |
| `test_combo_self_self_heal.json` | `self` | `self` | `heal(20)` | self-cast |
| `test_combo_actor_chain_move.json` | `actor` r=1 | `chain(1)` | `damage(4)`, `move(push, 2)` | move-эффект (knockback-like) |
| `test_combo_hex_circle_create.json` | `hex` r=3 | `zone_circle(1)` | `create(swarm)` | create-эффект |
| `test_level_scaling.json` | копия `vamp_strike` | | | `level: 2` для AC-X4 |

**Несовместимые комбо (не генерируются):**
- `target: self + area: chain` — caster-rooted chain бессмысленна как тестовая фикстура.
- `area: self + target: actor/object` — area_self игнорирует target, выбор не-self target — мусор.

Это runtime-валидные конфигурации (не валится), но как тестовые фикстуры не показательны.

## Out of scope

- Локализация: `name`/`tooltip`/`desc` хранятся как ключи, не резолвятся. Локализационный сервис — отдельная фича.
- Mood-система: поле сохраняется, потребитель отсутствует. Будущая система характера.
- AudioDB lookup для `Ability.sound` — отдельная фича. На 021 значение хранится, не диспатчится.
- Animation dispatch для `Ability.animation` — то же.
- Object-сущность для `target.kind = object` — остаётся stub.
- Level-up reward UI — engine читает `level`, источник проставления — отдельная фича.
- Backward-compat layer для старых ключей (`tags`, `entity`, `game_object_id`) — НЕТ.
- Триггерные / реактивные модификаторы — out of 007, тем более 021.
- Скейлинг `move_distance` и `chain.radius` от level — намеренно не входят (не указаны в формулах).

## Зависимости

- **Upstream:** 007 (Skill/Ability контракт), 011 (Skill.tags парсинг).
- **Downstream:** 008 (enemy AI — `Skill.tags` → `Skill.behaviour_tags` в одном файле, fix в этом PR), будущий audio/animation dispatch.
- **Координация:** Sergey (008) и Andrey (009) — рассказать после мержа, изменения в их потребителях минимальны (1-2 строки на файл).
