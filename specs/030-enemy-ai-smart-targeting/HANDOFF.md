# 030-enemy-ai-smart-targeting — HANDOFF

**Branch:** `alexey/030-smart-targeting`
**Last commit:** feat(030): all enemies wired — behaviors + scenes for full roster
**PR:** https://github.com/TortikP/GameJamProject/compare/staging...alexey/030-smart-targeting?expand=1
**Review needed from:** Egor (core/ai/ owner)

---

## Что сделано

### Новые GDScript файлы

| Файл | Класс | AC |
|---|---|---|
| `scripts/core/ai/conditions/condition_unclaimed_hex_exists_near_enemy.gd` | `ConditionUnclaimedHexExistsNearEnemy` | AC-C10 |
| `scripts/core/ai/conditions/condition_ally_count_below.gd` | `ConditionAllyCountBelow` | AC-C11 |
| `scripts/core/ai/selectors/selector_highest_hp_ally.gd` | `SelectorHighestHpAlly` | AC-T9 |
| `scripts/core/ai/selectors/selector_unclaimed_hex_near_enemy.gd` | `SelectorUnclaimedHexNearEnemy` | AC-T8 |
| `scripts/core/ai/selectors/selector_target_without_status.gd` | `SelectorTargetWithoutStatus` | AC-T10 |
| `scripts/core/ai/policies/policy_approach_nearest_enemy_unclaimed.gd` | `PolicyApproachNearestEnemyUnclaimed` | AC-MP5 |
| `scripts/core/ai/policies/policy_maintain_range.gd` | `PolicyMaintainRange` | post-playtest fix |

### Изменённые файлы

| Файл | Что |
|---|---|
| `scripts/core/ai/enemy_ai_planner.gd` | +1 строка: `want_allies or selector is SelectorHighestHpAlly` |
| `scripts/core/ai/behavior_database.gd` | +2 conditions, +3 selectors, +2 policies в switch |
| `scripts/core/maps/level_loader.gd` | +10 сцен в ENEMY_SCENES |

### Новые behavior JSONs (`data/ai_behaviors/`)

Архетипы: `melee_fighter`, `ranged_mage`, `healer`, `buffer`
Архетипы боссов (текущие враги): `bear_aggressive`, `bee_aggressive`, `bush_aggressive`,
`boar_aggressive`, `angel_aggressive`, `burning_bear_aggressive`, `fire_slime_aggressive`,
`lavender_lion_aggressive`, `monkey_aggressive`, `stapler_aggressive`, `teapot_aggressive`

Политика `maintain_range` (desired_min/max) — заменяет kite_from_nearest_enemy для ranged
чтобы не убегали вечно.

### Новые сцены (`scenes/dev/`)

bear, bee, mushroom_boar — placeholder (manekin.png + tint)
angel, burning_bear, fire_slime, lavender_lion, monkey, stapler, teapot — реальные спрайты

---

## Открытые вопросы

### 1. bee_honey_cold / bee_summon_bee не стреляют
Тег `heal`/`summon` не в `tag_priority` bee_aggressive → скиллы молчат.
Пчела только стингует. Решение:
- Добавить `"heal"` в tag_priority → honey_cold попытается лечить союзников
  (если есть раненые bee рядом). Если союзников нет — правило не срабатывает.
- summon: нужен отдельный `ally_count_below(N)` → selector_self → `[summon]` rule.
  AC-C11 готов, JSON-rule не написан. Стасян решает нужно ли.

### 2. lavender_lion_scare (hex AoE debuff) не стреляет с nearest_enemy
scare — HexTarget r3. С nearest_enemy selector — SelectorUnclaimedHexNearEnemy отфильтрует.
Сейчас lion бьёт только bite. Для scare нужен Rule с `unclaimed_hex_near_enemy`.
Добавить в lavender_lion_aggressive Rule 2:
```json
{
  "condition": {"kind": "enemy_in_range", "distance": 3},
  "target_selector": {"kind": "unclaimed_hex_near_enemy"},
  "tag_priority": ["debuff", "ranged"],
  "min_skill_count": 1
}
```
Поставить между Rule 1 (bite) и Rule 3 (fallback).

### 3. burning_bear_hellshake (self-AoE r-1) не стреляет
range=-1 — плановщик скорее всего интерпретирует как «в пределах 0» или кидает ошибку.
Проверить Egor — возможно нужен специальный `condition: always` + `target: self` + hex selector.
Либо r-1 это «любая дистанция» в интерпретации способностей.

### 4. burning_bear_summon_bear (hex r-1) аналогично
Тот же вопрос по r-1.

### 5. teapot_spill_the_t без damage тега
tags: `[ranged]` — в условии `enemy_in_range(5)` / selector `nearest_enemy` / priority `[ranged]`
→ spill_the_t подберётся. Но это HexTarget — nearest_enemy вернёт Actor →
SelectorUnclaimedHexNearEnemy нужен. Текущий teapot_aggressive Rule 1 использует unclaimed_hex → OK.
Если unclaimed_hex не найден → Rule 2 nearest_enemy → spill_the_t не выстрелит (HexTarget + ActorSelector).
Допустимо для плейтеста.

---

## Для Стасяна

Все numeric placeholder в `data/ai_behaviors/*.json` ждут баланса:
- `desired_min/max` в maintain_range (angel=2-4, stapler=2-3)
- `pct` в self_hp_below (bear=40%), healer=40/60, buffer=40/50
- `distance` в enemy_in_range правилах
- Пчела: решить нужен ли summon rule (AC-C11 condition готов)

---

## Для Egor при review

Единственный изменённый существующий файл в `scripts/core/ai/` — `enemy_ai_planner.gd`:
```gdscript
# было:
var want_allies: bool = selector is SelectorLowestHpAlly
# стало:
var want_allies: bool = selector is SelectorLowestHpAlly or selector is SelectorHighestHpAlly
```
Всё остальное — additive (новые файлы в existing папках).

`behavior_database.gd` — только новые case в switch, existing ветки не тронуты.

---

## Следующий сеанс

```bash
git fetch --all
git checkout alexey/030-smart-targeting
git pull
```
Smoke tests T061-T069 из SMOKE.md. Потом PR в staging.
