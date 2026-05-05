# 026-skill-system-v3 — spec

**Owner:** Egor
**Status:** Ready for /plan (clarify-цикл закрыт в чате 02.05)
**Upstream:** 007-skill-system, 011-skill-tags, 021-skill-system-v2

## Цель

Доработка контракта Skill/Ability под нарратив, аудио/VFX-привязку и UX
многошагового каста:

1. **Иконка скилла** в данных (`Skill.icon`) — задел под UI слотов / тултипов / уровень-up награды.
2. **Звуковая привязка способности** разделена: `sound_start` (на каст), `sound_end` (на резолв). Текущее `sound` упраздняется как недостаточное.
3. **VFX-привязка способности** через `collision_effect` — анимация попадания (damage flash, heal sparkle и т.д.). Отдельно от `animation` (поза/жест каста).
4. **Effect-схема: `kind` упраздняется**, дискриминатор — наличие ключа в объекте. Один JSON-объект эффекта может нести несколько эффект-ключей; парсер разворачивает его в N типизированных `AbilityEffect`-инстансов в **детерминированном порядке registry**.
5. **Area: префикс `area_`** в полях `chain` / `zone_circle` (`max_chain_length` → `area_max_chain_length`, `radius` → `area_radius`).
6. **Per-ability target selection** — при касте multi-ability скилла каждая ability собирает свою цель отдельно (phase 1: collect, phase 2: apply). `target.kind = self` требует явного подтверждения, не auto-skip.

## Изменения схемы

### Skill (новые / изменённые поля)

```json
{
  "id": "skill_id",
  "name": "name_loc_key",
  "tooltip": "tooltip_loc_key",
  "desc": "desc_loc_key",
  "icon": "icon_id",                 // НОВОЕ
  "cooldown": 0,
  "behaviour_tags": ["melee", "damage"],
  "mood": ["toxic", "apathetic"],
  "level": 0,
  "abilities": [/* Ability[] */]
}
```

`icon: StringName` — id из будущего IconDB. Пока хранится, не диспатчится.
Все остальные поля без изменений vs 021.

### Ability (изменённые поля)

```json
{
  "id": "ability_id",
  "sound_start":      "sound_start_id",        // НОВОЕ — было `sound` в 021
  "sound_end":        "sound_end_id",          // НОВОЕ
  "collision_effect": "collision_effect_id",   // НОВОЕ — VFX попадания
  "animation":        "animation_id",          // без изменений vs 021
  "target": {"kind": "actor", "range": 1},
  "area":   {"kind": "chain", "area_max_chain_length": 1, "area_radius": 1},
  "effects": [/* Effect[] — см. ниже */],
  "modifiers": []
}
```

- `sound` (021) **упразднён**, hard rename → `sound_start`.
- `sound_end`, `collision_effect` — новые `StringName`, default `&""`.
- `animation` — остаётся (анимация каста на caster), не путать с `collision_effect` (VFX на target).
- `id` — **остаётся** (per-step EventBus.ability_cast emit, AbilityDatabase lookup, multi-ability dispatch). 021-аргументы валидны.
- Все 4 строковых поля (`sound_start`/`sound_end`/`collision_effect`/`animation`) хранятся, не диспатчатся — потребители (AudioDB / VFXDB / IconDB) появятся отдельными фичами.

### Areas

| kind | поля | поведение |
|---|---|---|
| `self` | — | резолв в `[caster]` (без изменений) |
| `chain` | `area_max_chain_length: int = 1`, `area_radius: int = 1` | BFS-цепь, шаг между звеньями до `area_radius` гексов |
| `zone_circle` | `area_radius: int = 1` | круг от primary, BFS layered |

**Hard rename ключей** (без шима):
- `chain.max_chain_length` → `chain.area_max_chain_length`
- `chain.radius` → `chain.area_radius`
- `zone_circle.radius` → `zone_circle.area_radius`

Внутреннее имя GDScript-поля сохраняется (`max_chain_length`, `radius`) — переименовывать только JSON-ключ через переопределение `_apply_params` в `AbilityDatabase` (mapping table). См. plan §"Area key mapping". Это даёт grep-friendly префикс в JSON без массового touch'а кода.

`zone_cone` / `zone_arc` / `zone_line` — продолжают парситься как stub'ы без warn'ов.

### Effects — НОВАЯ схема

**Ключ `kind` упразднён.** Тип эффекта определяется наличием его уникальных ключей в объекте.

| effect-ключ | класс | дополнительные поля |
|---|---|---|
| `damage` | `DamageEffect` | `damage: int` |
| `heal`   | `HealEffect`   | `heal: int` |
| `status` | `StatusEffect` | `status: StringName` |
| `move_type` | `MoveEffect` | `move_type: StringName`, `move_distance: int` |
| `entity_id` | `CreateEffect` | `entity_id: StringName` |

**Один эффект-объект может содержать несколько эффект-ключей.** Парсер разворачивает в N типизированных инстансов:

```json
{"duration": 0, "damage": 10, "move_type": "push", "move_distance": 2}
```
→ `[DamageEffect(damage=10, duration=0), MoveEffect(move_type=push, move_distance=2, duration=0)]`

**Порядок применения внутри одного объекта — фиксированный registry-order:**

```
damage → heal → status → move → create
```

Этот порядок *детерминирован* и *документирован* — не зависит от порядка ключей в JSON. Решение временное; после плейтеста с геймдизайнером может смениться (per-effect priority field, или JSON key-order, или конфиг). См. §"Open after playtest".

**Общие поля** (`duration`, `requires_alive_target`) копируются в каждый разнесённый инстанс. Минимальный валидный объект — `{"duration": 0}` (но без эффект-ключей он бесполезен; парсер логирует info и не создаёт инстансов).

**Discriminator collisions:** ключи `damage` / `heal` / `status` / `move_type` / `entity_id` уникальны — пересечений нет, разворачивание однозначное.

### Targets — без изменений

| kind | поля |
|---|---|
| `self` | — |
| `actor` | `range: int` |
| `hex` | `range: int` |
| `object` | `range: int` |

JSON-ключи `range` без префикса `target_` — у `target` блока префикс был бы избыточен (другая семантика чем у area). Оставляем как 021.

## Per-ability target selection (cast flow)

**Изменение:** `Skill.cast(caster, ctx: Dictionary)` → `Skill.cast(caster, ctxs: Array[Dictionary])`. Один Dictionary на ability в порядке `abilities[]`.

### Phase 1 — collection (на стороне caller'а)

Caller (godmode_controller для игрока, AI для врагов) собирает Array[Dictionary] длины `abilities.size()`. Каждый i-й Dictionary — ctx для `abilities[i]`:

```gdscript
{
    "registry": <ActorRegistry>,
    "grid": <HexGrid>,
    "target_id": <StringName>,
    "target_coord": <Vector2i>,
}
```

**Player flow** (godmode_controller, state-machine с тремя состояниями):

```
IDLE → AWAIT_TARGET   (для non-self abilities[i])
IDLE → AWAIT_SELF_CONFIRM (для self abilities[i])
AWAIT_*  → IDLE (на cancel)
AWAIT_*  → AWAIT_*  (на commit step → следующая ability)
AWAIT_*  → IDLE + skill.cast(player, ctxs) (на commit последней ability)
```

1. Игрок жмёт Q/W/E/R → entry pre-check: `skill.can_apply(player, mouse_ctx) == true`. Если false — slot greyed, нет entry.
2. Для `abilities[i]`:
   - `target` — `SelfTarget` → AWAIT_SELF_CONFIRM. Overlay подсвечивает caster-hex (`show_self_confirm`). Любой ЛКМ на экране (грид, UI, вне грида) — commit step с `{target_id: caster, target_coord: caster_coord}`. Повторное нажатие активного слота — тоже commit (keyboard path).
   - Иначе → AWAIT_TARGET. Overlay подсвечивает `target.get_range_hexes(caster_coord, grid)`. ЛКМ по валидному hex'у — commit с `{target_id: actor_at(coord), target_coord: coord}`. ЛКМ вне range — no-op (остаёмся, overlay сохраняется — защита от misclick'а).
3. Если `i == abilities.size() - 1` после commit'а — вызвать `Skill.cast(player, ctxs)`, reset state, `TurnManager.advance()`.
4. **Cancel** в любом AWAIT_*-состоянии (ESC / RMB / переключение на другой слот / повторное нажатие активного слота на non-self шаге) → drop ctxs, hide overlay, no cast, no cooldown, no turn advance.

**AI flow** (godmode_controller `_resolve_cast_intent`):

AI пока живёт в одной ctx (CastIntent). На границе вызова — fan-out: `var ctxs = []; for _i in skill.abilities.size(): ctxs.append(ctx)`. Per-ability AI-таргетинг — out of scope (см. §"Out of scope").

### Phase 2 — application (внутри Skill.cast)

```
Skill.cast(caster, ctxs):
    if ctxs.size() != abilities.size(): error → false
    for i in abilities.size():
        abilities[i].cast(caster, ctxs[i], self.level)
```

Без изменений: каждая Ability получает СВОЙ ctx, дальше lifecycle 021 (target.duplicate→apply_level→resolve, area.duplicate→apply_level+modifiers→resolve, effects.duplicate→apply_level+modifiers→apply).

### Cancel-семантика

Отмена в phase 1 — атомарна: либо все цели собраны и скилл применяется целиком, либо ни одна цель не использована. Промежуточные `ctxs[i]` для уже-собранных abilities выбрасываются.

Cooldown ставится только при `any_resolved == true` в phase 2 (как 021). Если все abilities вернули false — cooldown не ставится.

### Self-target confirmation UI

`target.kind == "self"` требует явного действия (не auto-skip), чтобы:
- multi-ability flow читался как «собрал → собрал → собрал → применил» (uniform UX);
- player мог отменить весь скилл уже внутри self-step'а (ESC / RMB);
- self-цель визуально подтверждалась (подсветка caster-hex'а).

**Confirm trigger:** ЛКМ в любой точке экрана (грид / UI / off-grid) ИЛИ повторное нажатие активного слота.
**Cancel trigger:** ESC, RMB, переключение слота.

Это намеренная асимметрия с non-self шагом (где ЛКМ вне target.range — no-op). Self-шаг не имеет «вне range» области — цель всегда caster — поэтому ЛКМ безусловно интерпретируется как commit, а отмена идёт только через явные cancel-keys.

**Single-ability self-skill** (например `test_combo_self_self_heal`) проходит через этот же путь — нажатие слота → AWAIT_SELF_CONFIRM → ЛКМ → cast. Намеренно uniform; fast-path «instant cast» НЕ реализуется в 026 (см. §"Out of scope").

## Уровень навыка (level scaling)

Без изменений vs 021. Новые поля (`icon`, `sound_start`, `sound_end`, `collision_effect`) — не скейлятся, оставляют base `apply_level` no-op в Ability (Ability сам не override'ит, скейл живёт на target/area/effect).

## Acceptance criteria

### Структурные
- **AC-S1**: `Skill` имеет поле `icon: StringName = &""`. Парсер `SkillDatabase` читает `icon` из JSON.
- **AC-S2**: `Ability` имеет поля `sound_start`, `sound_end`, `collision_effect`, `animation` (все `StringName`, default `&""`). Поле `sound` удалено (rename, не coexist).
- **AC-S3**: `Ability.id` сохраняется (021-keep решение).
- **AC-S4**: JSON-ключи `area.max_chain_length` / `area.radius` (на chain) и `area.radius` (на zone_circle) **переименованы в `area_max_chain_length` / `area_radius`** в данных. GDScript-поля сохраняют старые имена.

### Effect schema
- **AC-E1**: JSON-ключ `effect.kind` упразднён, парсер игнорирует если присутствует (warn один раз, не падает).
- **AC-E2**: Парсер разворачивает один JSON-объект эффекта в N `AbilityEffect`-инстансов по наличию эффект-ключей (`damage`/`heal`/`status`/`move_type`/`entity_id`).
- **AC-E3**: Порядок инстансов в `abilities[i].effects` — registry-order: damage → heal → status → move → create. Покрыт unit-тестом / debug-cast'ом.
- **AC-E4**: Общие поля (`duration`, `requires_alive_target`) копируются в каждый разнесённый инстанс.
- **AC-E5**: Минимальный объект `{"duration": 0}` без эффект-ключей — парсится без crash, не создаёт инстансов, логирует `GameLogger.info`.

### Cast flow
- **AC-C1**: Сигнатура `Skill.cast(caster, ctxs: Array[Dictionary]) -> bool`. Размерность `ctxs.size() == abilities.size()` проверяется, ошибка → log error + return false.
- **AC-C2**: `abilities[i].cast(caster, ctxs[i], level)` — каждая ability получает свой ctx.
- **AC-C3**: godmode_controller player path — multi-step state-machine: для multi-ability скилла собирает targets по очереди в phase 1, применяет в phase 2.
- **AC-C4**: `target.kind == "self"` — UI показывает подсветку caster-hex (`show_self_confirm`); коммит step'а — **любой ЛКМ на экране** (грид, UI, off-grid) ИЛИ повторное нажатие активного слота. Не auto-skip.
- **AC-C5**: ESC, RMB, переключение слота, или повторное нажатие активного слота на non-self шаге — отмена всего каста (no cooldown, no commit, no turn advance). ЛКМ по hex'у вне `target.get_range_hexes` на non-self шаге — **no-op** (остаёмся в текущем шаге, overlay не сбрасывается).
- **AC-C6**: AI path — `_resolve_cast_intent` строит `ctxs = [ctx] * skill.abilities.size()`, вызов `skill.cast(enemy, ctxs)` — поведенческий no-regression vs 021.
- **AC-C7**: Single-ability скилл (`abilities.size() == 1`) — phase 1 collection в один шаг (текущий UX 021 сохраняется визуально).

### Миграция
- **AC-M1**: Все production+test JSON в `data/skills/` мигрированы — старые ключи (`sound`, `kind` в effects, `max_chain_length`, `radius` на area-блоках) отсутствуют.
- **AC-M2**: `Skill.cast(caster, ctx: Dictionary)` со старой сигнатурой удалён, не coexist. Все 2 caller'а в репозитории (`_cast_slot`, `_resolve_cast_intent`) обновлены.
- **AC-M3**: Backward-compat шим не делается (как 021).

### Smoke / scenarios
- **AC-X1**: Запуск проекта → `SkillDatabase` грузит все skills без warn'ов; effect-разворот работает без unknown-kind warn'ов.
- **AC-X2**: Godmode-сцена — `vamp_strike` (multi-ability damage+heal) кастится в 2 step'а: ЛКМ по врагу (vs_dmg) → повторный Q (vs_heal self-confirm) → применение. Damage 100, heal 50 (level 0).
- **AC-X3**: `test_combo_actor_chain_move` — один эффект-объект с `damage` + `move_type`, парсится в 2 инстанса, на касте порядок: damage перед move (registry-order). Лог через `GameLogger.info("SkillTest", ...)`.
- **AC-X4**: ESC во время phase 1 (после первого step'а из 2) — каст отменяется, скилл остаётся ready (cooldown не ставится).
- **AC-X5**: Все production-абилки (`debug_punch`, `melee_punch`, `manekin_attack`, `knockback_punch`) — single-ability — в один шаг, поведение idempotent vs 021.
- **AC-X6**: AI планировщик манекена — атака применяется через ctxs-fan-out, никаких regression'ов в `manekin_attack` поведении.

## Test fixtures

Изменяются in-place:
- Все 14 файлов в `data/skills/` — миграция effect-схемы (`kind` ключ убирается, поля остаются), area-ключи (где есть). Новые поля Skill (`icon`) и Ability (`sound_end`, `collision_effect`) — НЕ добавляем в production JSON (default'ы безопасны), кроме одного нового тест-файла.

Новый файл:
- `data/skills/test_combo_multikey_effect.json` — single ability с object `{"duration": 1, "damage": 8, "status": "burning"}` (damage + status в одном объекте, проверяет AC-E2/E3).

## Out of scope

- AudioDB / VFXDB / IconDB lookup для `sound_start`/`sound_end`/`collision_effect`/`icon`/`animation` — отдельные фичи. На 026 значения хранятся, не диспатчатся.
- Per-ability AI-таргетинг — AI шарит ctx между abilities (broadcast). Когда AI поумнеет — отдельная фича в 008-enemy-ai.
- Object-сущность для `target.kind = object` — остаётся stub.
- `Enter` как self-confirm trigger — на след. итерацию (в 026 — повторное нажатие слота / ЛКМ).
- Fast-path «instant cast» для single-ability self-target скиллов — НЕТ. Все скиллы идут через state-machine для uniform-UX. Если плейтест покажет что лишний клик раздражает — добавляем отдельной фичей.
- Hint-label «ЛКМ — подтвердить, ESC — отмена» в нижнем краю экрана — nice-to-have, не блокирует 026.
- Локализация loc-keys — отдельный сервис.
- Mood-система — поле сохраняется, потребитель отсутствует.
- Backward-compat layer — НЕТ (hard rename, как 021).
- Скейлинг новых полей (`icon`/`sound_*`/`collision_effect`) от level — нет (они не numeric).
- Кастомизируемый порядок effect-разворота (priority field, JSON key-order, config) — НЕТ. Решение по итогам плейтеста (см. §"Open after playtest").

## Open after playtest

Эти решения зафиксированы как timed-out на этап плейтеста; ревизия после смотра геймдизайнера, не блокирует 026-merge:

1. **Effect dispatch order** — registry-order (damage→heal→status→move→create) сейчас. Если плейтест покажет, что нужен другой порядок (например, move перед damage для «бросок об стену» юзкейса) — рефакторим в priority-field или JSON key-order.
2. **Self-confirm UX** — ЛКМ-везде + повторный слот как commit, ESC/RMB/смена слота как cancel. Если игроки спотыкаются — добавляем кнопку «Confirm» в HUD / Enter-биндинг / fast-path для single-ability self-skills.
3. **Cancel UX** — ESC + right-click оба отменяют. Если right-click нужен под move (как сейчас) — оставляем только ESC и переключение слота.

## Зависимости

- **Upstream:** 007 (контракт), 011 (skill.tags), 021 (loc-keys, level, behaviour_tags, sound/animation slots).
- **Downstream:** 008 (enemy AI — broadcast adapter ctxs-fan-out), 009 (UI-kit — slot icon support), будущий audio/VFX dispatch.
- **Координация:** Sergey (008) — fan-out adapter в `_resolve_cast_intent` затрагивает его планировщик-границу. Andrey (009) — slot icon потребитель появится позже.
