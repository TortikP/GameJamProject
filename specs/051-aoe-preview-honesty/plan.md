# 051-aoe-preview-honesty — plan

Spec: `spec.md`. Branch: `andrey/051-aoe-preview-honesty` off staging.

## Затрагиваемые файлы

| Файл | Изменение |
|---|---|
| `data/skills/default_ranged.json` | `target.kind`: `"actor"` → `"hex"` |
| `scripts/presentation/godmode/move_range_overlay.gd` | `_draw` блок #5: добавить `draw_colored_polygon` fill перед outline loop |
| `scripts/presentation/godmode/hover_dispatcher.gd` | `update_castability`: вычислить `zone_hexes` ДО damage-preview loop, использовать его как фильтр для `set_preview_damage` |
| `scripts/presentation/health_bar.gd` | `_draw`: при `_preview_damage > 0` рендерить `"%d → %d"` вместо `"%d/%d"` |

## Детали

### `default_ranged.json`

```diff
       "target": {
-        "kind": "actor",
+        "kind": "hex",
         "range": 4
       },
```

Никаких других правок. `area`, `effects`, `cooldown`, `behaviour_tags` — всё остаётся.

### `move_range_overlay.gd::_draw` блок #5

Текущий код:
```gdscript
var aoe_line: Color = Color(_zone_preview_color.r, _zone_preview_color.g, _zone_preview_color.b, 0.80)
for c in _zone_preview:
    var cen: Vector2 = layer.map_to_local(c)
    for i in 6:
        draw_line(cen + corners[i], cen + corners[(i + 1) % 6],
                aoe_line, 2.0, true)
```

Стать:
```gdscript
# 051: filled hexes — игроку видно ВСЮ задетую зону, не только границу.
# Fill — ниже content (alpha 0.22), outline сверху (alpha 0.80) — граница
# зоны остаётся читаемой даже если несколько AoE накладываются.
var aoe_fill: Color = Color(_zone_preview_color.r, _zone_preview_color.g, _zone_preview_color.b, 0.22)
var aoe_line: Color = Color(_zone_preview_color.r, _zone_preview_color.g, _zone_preview_color.b, 0.80)
for c in _zone_preview:
    var cen: Vector2 = layer.map_to_local(c)
    var poly := PackedVector2Array()
    for i in 6:
        poly.append(cen + corners[i])
    draw_colored_polygon(poly, aoe_fill)
    for i in 6:
        draw_line(cen + corners[i], cen + corners[(i + 1) % 6],
                aoe_line, 2.0, true)
```

### `hover_dispatcher.gd::update_castability`

Сейчас (упрощённо):
```gdscript
# (1) compute hover_target preview
preview_for_hover = predicted_damage_to(hover_target) if applicable else 0
# (2) iterate enemies, set preview = preview_for_hover if a == hover_target else 0
# (3) compute zone_hexes from preview_ability.area
# (4) overlay.show_zone_preview(zone_hexes)
```

Стать:
```gdscript
# (1) compute zone_hexes FIRST — they drive both overlay and HP preview
zone_hexes = compute_zone_hexes(preview_ability, coord, caster_coord, grid)
# (2) overlay.show_zone_preview(zone_hexes)
# (3) build set: enemies whose coord ∈ zone_hexes
# (4) for each enemy:
#       if id ∈ zone_set: set_preview_damage(predicted_damage_to(player, that_enemy, ctx_for_zone))
#       else:             set_preview_damage(0)
```

Ключ: `predicted_damage_to(player, enemy, ctx)` — `ctx` тот же что и для primary cast (с `target_coord = coord`, `target_id = grid.get_actor_at(coord)`). Для AoE-spell это ОК — damage prediction независим от per-target ctx (в текущей реализации `predicted_damage_to` игнорирует `_target` и `_ctx` в `Ability.predicted_damage_to`).

Edge: skill = healable / non-damage → `predicted_damage_to` вернёт 0 → preview не показывается, работает само собой.

Edge: AoE-spell есть, но `can_apply` false (вне range) → zone_hexes пустой (через `current_preview_ability` == null OR resolve fail) → все enemy preview = 0. ОК.

Edge: skill без area (`zone_circle radius 0` / single) → `get_affected_hexes` вернёт `[anchor]` → один гекс, один enemy в preview, поведение совпадает с текущим hover-target подходом.

### `health_bar.gd::_draw`

```diff
-var text: String = "%d/%d" % [_actor.hp, _actor.max_hp]
+var text: String
+if _preview_damage > 0:
+    text = "%d → %d" % [_actor.hp, max(0, _actor.hp - _preview_damage)]
+else:
+    text = "%d/%d" % [_actor.hp, _actor.max_hp]
```

Размер шрифта (`UiTheme.BAR_FONT_SIZE_OVERHEAD`) без изменений — `→` вмещается.

## Что НЕ делаем

- Не вводим heal preview на player'е (`+15` зелёным цветом). Если потом понадобится, отдельный спек.
- Не меняем status preview в HealthBar (status icons strip — отдельная подпанель уже).
- Не оптимизируем per-frame `predicted_damage_to` лупом. Мерим в smoke; если >0.5ms на frame — добавим guard `if zone_hexes != _last_zone_hexes`.
- Не трогаем enemy-side telegraph (мобовские intents) — они через telegraph_renderer, отдельная пайплайна.

## Audit summary

`grep -l 'target.kind' data/skills/*.json` + cross-check с `area`:
- 1 production skill с actor+area: `default_ranged.json` (фиксим).
- 6 production skills с hex+area: angel_*, fire_slime_magma_spit, lavender_lion_scare, mushroom_boar_spores, paper_jam, teapot_tea_gathering, stapler_paper_jam — уже корректны.
- 5 test skills с actor+chain: оставляем (chain семантически нуждается в actor).

## Smoke

После всех изменений в godmode:
1. F1 spawn 2 манекена близко друг к другу (≤2 hex).
2. Slot R = coffee. Hover пустой гекс между ними.
3. Видно: залитые красные/control-цвет гексы зоны, оба манекена показывают `"50 → 34"` над bar'ом, красные превью-стрипы на их HP-bar.
4. Click → оба теряют 16 HP, status weak применился.
5. Hover уехал на другой край → оба показывают `"50/50"`, без preview.
