# 011-skill-tags — plan

**Spec:** [`spec.md`](./spec.md)

## Файлы

| Путь | Что меняется | Размер |
|---|---|---|
| `scripts/core/skills/skill.gd` | +1 строка: `@export var tags: Array[StringName] = []` после `abilities` | +1 |
| `scripts/core/skills/skill_database.gd` | в `_build_skill` после парсинга `cooldown` — блок парсинга `tags` (см. snippet ниже) | ~10 |
| `data/skills/skill_debug_punch.json` | +`"tags": ["damage"]` после `cooldown` | +1 |
| `data/skills/skill_melee_punch.json` | +`"tags": ["damage"]` | +1 |
| `data/skills/skill_manekin_attack.json` | +`"tags": ["damage"]` | +1 |
| `data/skills/skill_knockback_punch.json` | +`"tags": ["damage", "knockback"]` | +1 |
| `specs/007-skill-system/plan.md` | в JSON schema example добавить строку `"tags": ["damage"],` после `"cooldown": 2,` | +1 |

## Skill resource

Текущая сигнатура (`scripts/core/skills/skill.gd` строки 13-15):

```gdscript
@export var id: StringName = &""
@export var cooldown: int = 0
@export var abilities: Array[Ability] = []
```

Добавляется одна строка:

```gdscript
@export var tags: Array[StringName] = []
```

Без геттеров. Read-only по convention (никто не пишет в `tags` после загрузки JSON). Сравнение тегов на стороне consumer'а (AI планировщик в 008) — `for s in actor.skills: if &"damage" in s.tags: ...` или `s.tags.any(...)`.

## Парсер snippet (для T002)

В `_build_skill` (строки 63-83 текущего `skill_database.gd`) — после `skill.cooldown = int(data.get("cooldown", 0))` (строка 71) добавить:

```gdscript
var tags_raw: Variant = data.get("tags", [])
if typeof(tags_raw) != TYPE_ARRAY:
    GameLogger.warn("SkillDatabase", "%s: 'tags' must be array, got %s — using []" % [sid, type_string(typeof(tags_raw))])
    tags_raw = []
for t in tags_raw:
    skill.tags.append(StringName(t))
```

Замечания:
- `Array[StringName]` через `.append(StringName(...))` работает в 4.6 — StringName — built-in, не CustomClass из ловушки CLAUDE.md.
- `data.get("tags", [])` возвращает `Variant`, нужна аннотация. См. CLAUDE.md trap про `:=` + Variant.
- `type_string(typeof(...))` — для удобочитаемого warn-лога.
- Не фейлим load skill'а если tags кривые — graceful degradation, skill доступен с пустыми tags.

## JSON schema (для AC-T5 — doc fix в 007/plan.md)

Текущий пример в 007/plan.md строки 237-261 — обновить только верхние 3 строки:

```json
{
  "id": "vamp_strike",
  "cooldown": 2,
  "tags": ["damage"],
  "abilities": [
    ...
  ]
}
```

Остальное без изменений. Комментарий в plan.md — не обязательно, поле говорит само за себя.

## Тестирование

- **Юнит-тестов нет.** Skill смок-тестит сам себя через рантайм (godmode F1-F4 + manekin attacks).
- **Smoke flow** (AC-T6): F5 запуск проекта → debug overlay показывает HP players/manekin → нажать F1 (skill_debug_punch) → манекен теряет HP. Затем F2/F3/F4 — все скиллы работают как до PR. Лог `[INFO][SkillDatabase] loaded 8 skills` (или сколько было).

## Migration safety

- Тэги — additive поле с пустым default.
- Существующие saved skills (если бы были — игра не сейвится в джеме) загрузились бы с пустыми tags.
- Никто кроме 008 ещё не читает `tags` — нет риска сломать чужой код.

## Ссылки

- 007 architecture: `specs/007-skill-system/architecture.md` §1 (Skill = ordered composition of abilities).
- 008 спека: `specs/008-enemy-ai/spec.md` AC-S5 (откуда вырезано), AC-I4 (semantic значения тегов для будущего telegraph mapping).
- Godot 4.6 docs:
  - [`StringName`](https://docs.godotengine.org/en/4.6/classes/class_stringname.html) — `StringName(s)` constructor берёт `String`/`StringName`.
  - [`@export`](https://docs.godotengine.org/en/4.6/classes/class_%40gdscript.html#class-gdscript-annotation-export) — типизованные массивы экспортируются как сериализуемые в JSON .tres / inspector.
