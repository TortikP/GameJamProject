# 026-skill-system-v3 — tasks

**Spec:** [`spec.md`](./spec.md) · **Plan:** [`plan.md`](./plan.md) · **Status:** Ready for /implement

Зависимости: T01..T03 параллельны; T04 после T01-T03; T05 после T04; T06 после T01..T05;
T07 (миграция данных) после T01-T04 (схема + парсер); T08 после T07; T09 = новый тест-фикстура.

---

## T01 — Skill: +icon, новая cast-сигнатура

**Файл:** `scripts/core/skills/skill.gd`

- [ ] Добавить `@export var icon: StringName = &""` (после `desc`, до `cooldown`).
- [ ] Сменить сигнатуру `cast(caster: Actor, ctx: Dictionary) -> bool` на `cast(caster: Actor, ctxs: Array[Dictionary]) -> bool`.
- [ ] Добавить guard: `if ctxs.size() != abilities.size():` — `GameLogger.error(...)` + `return false`.
- [ ] Внутри цикла — `abilities[i].cast(caster, ctxs[i], level)` (вместо `ab.cast(caster, ctx, level)`).
- [ ] Обновить docstring: убрать упоминание single-ctx, описать ctxs[]-контракт + ссылку на 026 spec §"Per-ability target selection".

`can_apply`, `predicted_damage_to`, `is_ready`, `tick_cooldown`, `get_ability_ids` — НЕ трогаем.

**Done when:** `Skill.cast(caster, [ctx, ctx])` вызывается без crash, `Skill.cast(caster, [ctx])` для двух-ability скилла возвращает false с error-логом.

---

## T02 — Ability: rename sound → sound_start, +sound_end, +collision_effect

**Файл:** `scripts/core/abilities/ability.gd`

- [ ] Удалить `@export var sound: StringName = &""`.
- [ ] Добавить:
      ```gdscript
      @export var sound_start: StringName = &""        # 026
      @export var sound_end: StringName = &""          # 026
      @export var collision_effect: StringName = &""   # 026
      ```
- [ ] Обновить docstring блока 021 (упомянуть 026-доп: разделение sound на start/end + collision_effect).
- [ ] `cast()`, `predicted_damage_to()`, `_apply_param_modifiers()`, `_is_dead()` — НЕ трогаем.

**Done when:** Старое `ability.sound = ...` парсится с error (поле удалено). Новые три `@export`'а доступны через `inst.set("sound_start", ...)` без warn'а.

---

## T03 — AbilityDatabase: парсинг новых Ability-полей

**Файл:** `scripts/core/abilities/ability_database.gd`

В `build_ability_from_dict` после блока создания `ability`:

- [ ] Удалить строку `ability.sound = StringName(data.get("sound", ""))`.
- [ ] Удалить строку `ability.animation = ...` (она остаётся, но переписывается в новом порядке) — оставить, не трогать.
- [ ] Добавить:
      ```gdscript
      ability.sound_start      = StringName(data.get("sound_start", ""))
      ability.sound_end        = StringName(data.get("sound_end", ""))
      ability.collision_effect = StringName(data.get("collision_effect", ""))
      ```
- [ ] Обновить docstring-пример вверху файла: `"sound": "..."` → `"sound_start": "..."`, добавить `"sound_end"`, `"collision_effect"`. Упомянуть 026.

**Done when:** Новый JSON с `sound_start`/`sound_end`/`collision_effect` парсится в `Ability` инстанс с этими `StringName`-значениями.

---

## T04 — AbilityDatabase: effect fan-out + registry-order

**Файл:** `scripts/core/abilities/ability_database.gd`

- [ ] Удалить `EFFECT_KINDS` константу (kind-discriminated registry).
- [ ] Добавить:
      ```gdscript
      const EFFECT_KEY_ORDER: Array[StringName] = [&"damage", &"heal", &"status", &"move_type", &"entity_id"]

      const EFFECT_KIND_BY_KEY: Dictionary = {
          &"damage":    preload("res://scripts/core/abilities/effects/damage_effect.gd"),
          &"heal":      preload("res://scripts/core/abilities/effects/heal_effect.gd"),
          &"status":    preload("res://scripts/core/abilities/effects/status_effect.gd"),
          &"move_type": preload("res://scripts/core/abilities/effects/move_effect.gd"),
          &"entity_id": preload("res://scripts/core/abilities/effects/create_effect.gd"),
      }
      ```
- [ ] Удалить функцию `_make_effect(data: Dictionary) -> AbilityEffect`.
- [ ] Добавить:
      ```gdscript
      func _make_effects_from_dict(data: Dictionary, ability_id: String) -> Array[AbilityEffect]:
          if data.has("kind"):
              GameLogger.warn("AbilityDatabase", "%s: legacy 'kind' key in effect dict — ignoring (026 schema)" % ability_id)
          var out: Array[AbilityEffect] = []
          for key in EFFECT_KEY_ORDER:
              if not data.has(key):
                  continue
              var script: GDScript = EFFECT_KIND_BY_KEY[key]
              var inst: AbilityEffect = script.new()
              for k in data.keys():
                  if k == "kind":
                      continue
                  inst.set(k, data[k])
              out.append(inst)
          if out.is_empty():
              GameLogger.info("AbilityDatabase", "%s: effect dict has no recognised keys — skipping" % ability_id)
          return out
      ```
- [ ] В `build_ability_from_dict` заменить блок:
      ```gdscript
      # 021:
      for eff_data in data.get("effects", []):
          var e := _make_effect(eff_data)
          if e != null:
              effects.append(e)
      ```
      на:
      ```gdscript
      # 026:
      for eff_data in data.get("effects", []):
          for e in _make_effects_from_dict(eff_data, id):
              effects.append(e)
      ```
- [ ] Обновить docstring-пример вверху файла: убрать `"kind": "damage"` и т.п. из примеров, заменить на 026-схему.

**Done when:**
- JSON `{"duration": 0, "damage": 10, "move_type": "push", "move_distance": 2}` парсится в `[DamageEffect, MoveEffect]` именно в этом порядке.
- JSON `{"duration": 0, "kind": "damage", "damage": 10}` парсится в `[DamageEffect]` + warn про legacy kind.
- JSON `{"duration": 0}` без эффект-ключей — не падает, info-лог, `effects = []`.

---

## T05 — AbilityDatabase: area key remap (area_max_chain_length / area_radius)

**Файл:** `scripts/core/abilities/ability_database.gd`

- [ ] Добавить:
      ```gdscript
      const AREA_KEY_REMAP: Dictionary = {
          "chain": {
              "area_max_chain_length": "max_chain_length",
              "area_radius":            "radius",
          },
          "zone_circle": {
              "area_radius": "radius",
          },
      }
      ```
- [ ] Переписать `_make_area`:
      ```gdscript
      func _make_area(data: Dictionary) -> AbilityArea:
          var kind: String = data.get("kind", "")
          var script: Variant = AREA_KINDS.get(kind)
          if script == null:
              GameLogger.warn("AbilityDatabase", "unknown area kind: '%s'" % kind)
              return null
          var inst: Object = script.new()
          var remap: Dictionary = AREA_KEY_REMAP.get(kind, {})
          for key in data.keys():
              if key == "kind":
                  continue
              var script_key: String = remap.get(key, key)
              inst.set(script_key, data[key])
          return inst as AbilityArea
      ```
- [ ] `_apply_params` — оставить как есть; используется для targets/modifiers (без remap).
- [ ] `_make_target`, `_make_modifier` — НЕ трогаем.

**Done when:** JSON `{"kind": "chain", "area_max_chain_length": 3, "area_radius": 2}` → `ChainArea(max_chain_length=3, radius=2)`. Старый ключ `max_chain_length` в JSON — без remap, проставит `inst.set("max_chain_length", ...)` напрямую (бесшовный fallback на 021-данные ДО миграции T07).

---

## T06 — SkillDatabase: парсинг icon

**Файл:** `scripts/core/skills/skill_database.gd`

В `_build_skill` после блока с `desc`:

- [ ] Добавить:
      ```gdscript
      # 026: icon — id для будущего IconDB (хранение, не диспатч).
      skill.icon = StringName(data.get("icon", ""))
      ```

**Done when:** JSON `{"id": "x", "icon": "ic_x", ...}` → `skill.icon == &"ic_x"`.

---

## T07 — Миграция data/skills/*.json

**Цель:** убрать `kind` из effects, переименовать area-ключи, переименовать `sound` → `sound_start`.

Скрипт миграции (run руками, не комитим):

```python
# python3 — выполнить из корня репы
import json, os, glob
for path in sorted(glob.glob("data/skills/*.json")):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    for ab in data.get("abilities", []):
        # rename sound → sound_start
        if "sound" in ab:
            ab["sound_start"] = ab.pop("sound")
        # area key remap
        area = ab.get("area", {})
        if area.get("kind") == "chain":
            if "max_chain_length" in area:
                area["area_max_chain_length"] = area.pop("max_chain_length")
            if "radius" in area:
                area["area_radius"] = area.pop("radius")
        elif area.get("kind") == "zone_circle":
            if "radius" in area:
                area["area_radius"] = area.pop("radius")
        # drop "kind" from each effect dict
        for eff in ab.get("effects", []):
            eff.pop("kind", None)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
print("done")
```

- [ ] Запустить скрипт.
- [ ] `git diff data/skills/` — глазами проверить: `kind` нигде в effects, area-ключи переименованы, `sound` нигде.
- [ ] Поправить вручную если что-то всплыло (особо смотреть на test_combo_*.json — там самые свежие схемы).
- [ ] `git add data/skills/*.json`.

**Done when:** `grep -E '"kind"\s*:\s*"(damage|heal|status|move|create)"' data/skills/*.json` — пусто. `grep '"sound"' data/skills/*.json` — пусто. `grep '"max_chain_length"\|"radius"' data/skills/*.json` — пусто (только `area_*` варианты).

---

## T08 — Player cast state-machine в godmode_controller

**Файл:** `scripts/presentation/godmode/godmode_controller.gd`

- [ ] Добавить state-vars (после блока `_slot_bar_node` и компании):
      ```gdscript
      # 026: multi-step cast collection state.
      var _cast_in_progress: bool = false
      var _cast_skill: Skill = null
      var _cast_step: int = 0
      var _cast_ctxs: Array[Dictionary] = []
      ```
- [ ] Переписать `_request_cast_active`: вместо немедленного `_cast_slot(active_idx)` — стартовать state-machine (если skill multi-ability) ИЛИ остаться single-shot для skill с одной ability (см. ниже про unified path).
- [ ] Переписать `_cast_slot`: всегда запускает state-machine, даже для single-ability (uniform path; UX не меняется визуально для single — один step).
      ```gdscript
      func _cast_slot(slot_index: int) -> void:
          var skill := _slot_bar_node.get_slot(slot_index) as Skill
          if skill == null or skill.abilities.is_empty(): return
          if grid._moving or _world_processing: return
          # Pre-check: at least the first ability must be castable from current cursor.
          var coord := grid.coord_under_mouse()
          var pre_ctx := {"registry": registry, "grid": grid, "target_id": grid.get_actor_at(coord), "target_coord": coord}
          if not skill.can_apply(player, pre_ctx): return

          _cast_skill = skill
          _cast_step = 0
          _cast_ctxs = []
          _cast_in_progress = true
          _begin_step()
      ```
- [ ] Добавить `_begin_step()`:
      ```gdscript
      func _begin_step() -> void:
          var ab := _cast_skill.abilities[_cast_step]
          if ab.target is SelfTarget:
              var caster_coord := grid.get_coord(player.actor_id)
              _cast_overlay.show_self_confirm(caster_coord)
          else:
              _cast_overlay.show_range_for_ability(player, ab)
      ```
- [ ] Добавить `_commit_step(coord, target_id)`:
      ```gdscript
      func _commit_step(coord: Vector2i, target_id: StringName) -> void:
          var ctx := {"registry": registry, "grid": grid, "target_id": target_id, "target_coord": coord}
          _cast_ctxs.append(ctx)
          _cast_step += 1
          _cast_overlay.hide_range()
          if _cast_step == _cast_skill.abilities.size():
              await _commit_cast()
          else:
              _begin_step()
      ```
- [ ] Добавить `_commit_cast()`:
      ```gdscript
      func _commit_cast() -> void:
          var skill: Skill = _cast_skill
          var ctxs: Array[Dictionary] = _cast_ctxs
          _reset_cast_state()    # reset BEFORE cast — EventBus subscribers see clean state
          var did_cast: bool = skill.cast(player, ctxs)
          if did_cast:
              await GameSpeed.wait("godmode", "ability_cast_delay")
              TurnManager.advance()
      ```
- [ ] Добавить `_cancel_cast()`:
      ```gdscript
      func _cancel_cast() -> void:
          _cast_overlay.hide_range()
          _reset_cast_state()
      ```
- [ ] Добавить `_reset_cast_state()`:
      ```gdscript
      func _reset_cast_state() -> void:
          _cast_in_progress = false
          _cast_skill = null
          _cast_step = 0
          _cast_ctxs = []
      ```
- [ ] В `_unhandled_input` ESC-ветка: добавить prioritет 0 (выше slot-toggle):
      ```gdscript
      if _cast_in_progress:
          _cancel_cast()
          get_viewport().set_input_as_handled()
          return
      ```
- [ ] В `_unhandled_input` right-click ветка: если `_cast_in_progress` → `_cancel_cast()` вместо `_request_move()`.
- [ ] В `_unhandled_input` slot-key (`cast_slot_<i>`): если `_cast_in_progress`:
      ```gdscript
      var active: int = _slot_bar_node.get_active()
      if i == active:
          # Same slot pressed again
          if _is_self_step():
              _commit_step(grid.get_coord(player.actor_id), player.actor_id)
          else:
              _cancel_cast()
              _slot_bar_node.activate(i)   # toggle off
      else:
          # Different slot — cancel and switch
          _cancel_cast()
          _slot_bar_node.activate(i)       # may re-enter via _request_cast_active
      get_viewport().set_input_as_handled()
      return
      ```
- [ ] В `_unhandled_input` left-click: если `_cast_in_progress` — обработать как commit step:
      ```gdscript
      var ab: Ability = _cast_skill.abilities[_cast_step]
      if ab.target is SelfTarget:
          # Self: ANY LMB confirms (grid / UI / off-grid). target_coord = caster's coord.
          var caster_coord: Vector2i = grid.get_coord(player.actor_id)
          _commit_step(caster_coord, player.actor_id)
      else:
          # Non-self: must click on a hex within target.range. Off-grid or out-of-range = no-op.
          var coord: Vector2i = grid.coord_under_mouse()
          if coord == Vector2i(-1, -1):
              return  # off-grid — stay on step
          var caster_coord: Vector2i = grid.get_coord(player.actor_id)
          var valid_hexes: Array[Vector2i] = ab.target.get_range_hexes(caster_coord, grid)
          if coord in valid_hexes:
              _commit_step(coord, grid.get_actor_at(coord))
          # else: invalid range click — neither commit nor cancel; stay on step
      get_viewport().set_input_as_handled()
      return
      ```
- [ ] Helper `_is_self_step()` рядом с state-vars:
      ```gdscript
      func _is_self_step() -> bool:
          if not _cast_in_progress or _cast_skill == null:
              return false
          if _cast_step >= _cast_skill.abilities.size():
              return false
          return _cast_skill.abilities[_cast_step].target is SelfTarget
      ```
- [ ] В `_resolve_cast_intent` (AI path): заменить `skill.cast(enemy, ctx)` на:
      ```gdscript
      # 026: AI broadcasts single ctx to all abilities (per-ability AI is OOS).
      var ctxs: Array[Dictionary] = []
      for _i in skill.abilities.size():
          ctxs.append(ctx)
      skill.cast(enemy, ctxs)
      ```

**Done when:**
- Single-ability skill (`debug_punch`): ЛКМ по врагу → каст применяется, как в 021.
- Multi-ability skill (`vamp_strike`): ЛКМ по врагу → vs_dmg-step commit → self-overlay появляется → повторный Q или ЛКМ по caster → vs_heal commit → cast применяется.
- ESC во время phase 1: ничего не применяется, slot остаётся active или сбрасывается (по существующей логике).

---

## T09 — CastRangeOverlay: per-ability + self-confirm

**Файл:** `scripts/presentation/cast_range_overlay.gd`

- [ ] Добавить метод `show_range_for_ability(caster: Actor, ability: Ability) -> void`:
      ```gdscript
      func show_range_for_ability(caster: Actor, ability: Ability) -> void:
          hide_range()
          if _grid == null or caster == null or ability == null or ability.target == null:
              return
          var caster_coord: Vector2i = _grid.get_coord(caster.actor_id)
          if caster_coord == Vector2i(-1, -1):
              return
          var hexes: Array[Vector2i] = ability.target.get_range_hexes(caster_coord, _grid)
          var base: Color = UiTheme.SEM_DEBUFF
          var fill := Color(base.r, base.g, base.b, 0.32)
          var outline := Color(base.r, base.g, base.b, 0.78)
          for c in hexes:
              _add_hex(c, fill, outline)
      ```
- [ ] Добавить метод `show_self_confirm(coord: Vector2i) -> void`:
      ```gdscript
      func show_self_confirm(coord: Vector2i) -> void:
          hide_range()
          if _grid == null:
              return
          var base: Color = UiTheme.SEM_BUFF if "SEM_BUFF" in UiTheme else UiTheme.SEM_DEBUFF
          var fill := Color(base.r, base.g, base.b, 0.45)
          var outline := Color(base.r, base.g, base.b, 0.85)
          _add_hex(coord, fill, outline)
      ```
- [ ] Старый `show_range(caster, skill_or_id)` НЕ удалять — он используется для slot-hover preview (показывает all-of-skill range до начала каста). Оставить.

**Done when:** Step с non-self ability подсвечивает только её target hexes; step с self-target подсвечивает caster-гекс контрастно (тёплый цвет).

---

## T10 — Тест-фикстура: multi-key effect

**Файл:** `data/skills/test_combo_multikey_effect.json` (новый)

```json
{
  "id": "test_combo_multikey_effect",
  "name": "skill.test_combo_multikey_effect.name",
  "tooltip": "skill.test_combo_multikey_effect.tooltip",
  "desc": "skill.test_combo_multikey_effect.desc",
  "icon": "",
  "cooldown": 0,
  "behaviour_tags": ["damage", "debuff"],
  "mood": [],
  "level": 0,
  "abilities": [
    {
      "id": "tcme_strike",
      "sound_start": "",
      "sound_end": "",
      "collision_effect": "",
      "animation": "",
      "target": {"kind": "actor", "range": 1},
      "area":   {"kind": "chain", "area_max_chain_length": 1, "area_radius": 1},
      "effects": [
        {"duration": 1, "damage": 8, "status": "burning"}
      ],
      "modifiers": []
    }
  ]
}
```

**Done when:**
- Файл загружается `SkillDatabase` без warn'ов.
- Cast на врага: damage применяется ДО status (registry-order), оба эффекта получают `duration=1`.

---

## T11 — Smoke checklist

Запустить `scenes/dev/godmode.tscn` (F5) и пройти ручные сценарии:

- [ ] `SkillDatabase` грузит 15 файлов, 0 warn в консоли.
- [ ] **AC-X2** vamp_strike: ЛКМ по врагу → vs_dmg-step commit → self-overlay появляется → ЛКМ в любой точке (или повторный Q) → vs_heal commit → cast применяется. Damage 100, heal 50.
- [ ] **AC-X3** test_combo_multikey_effect: cast → лог damage до status (порядок в `GameLogger`-выводе).
- [ ] **AC-X4** ESC mid-phase-1: слот не уходит на cooldown, повторный каст работает.
- [ ] **AC-X5** debug_punch / melee_punch / manekin_attack / knockback_punch — single-step cast как в 021.
- [ ] **AC-X6** Manekin AI кастит атаку без crash, target_id корректен в EventBus.skill_cast.

**Done when:** все пункты ✅, скриншот / лог в PR-комментарии.

---

## Зависимости задач

```
T01, T02, T03 — параллельно (разные файлы / контракты)
T04 после T01-T03 (effect-парсер использует базовый AbilityEffect)
T05 параллельно T04
T06 параллельно (SkillDatabase отдельный файл)
T07 после T01..T05 (миграция данных под новые контракты)
T08 после T01-T07 (state-machine использует новые сигнатуры)
T09 параллельно T08 (overlay)
T10 после T07 (новая фикстура в финальном формате)
T11 — финал, после всех
```

## Не делаем в этом PR

- Никаких изменений в `enemy_ai_planner.gd` / `CastIntent` / `ai_behaviors/*.json`.
- Никаких новых effect-классов.
- Никакого AudioDB / VFXDB / IconDB engine — только хранение полей.
- Никакого `Skill.cast(caster, ctx)` shim для бэкап-совместимости.
- Никаких изменений в `chain_area.gd` / `zone_circle_area.gd` — GDScript-имена полей сохраняются.
- `predicted_damage_to` сигнатура — без изменений (одиночный target hover, не multi-step).
