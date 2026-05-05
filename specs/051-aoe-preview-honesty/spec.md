# 051-aoe-preview-honesty — spec

**Owner:** Andrey.
**Status:** Draft → in progress.
**Coordination:** none — touches presentation only and one production skill JSON. No public API renamed.

## Цель

Closeloop AoE-кастов: (1) можно бросать в землю, не только в актёра; (2) визуально честно — все задетые гексы залиты, не точечный outline; (3) числовой preview HP («сейчас → после») на каждом враге в зоне, а не только на курсоре.

## Pillar mapping

- **Pillar 1 (full information visibility).** Залитая зона + per-enemy «X → Y» = игрок видит весь исход клика *до* клика. Сейчас он видит только точку курсора и догадывается «а попадёт ли в соседа».
- **Pillar 2 (player–monster symmetry).** Меняется только player-side preview; враги уже используют ту же telegraph-инфраструктуру. Контракт `Ability.predicted_damage_to` симметричен.

## Требования

### R1 — coffee может бить в землю

`data/skills/default_ranged.json` → `target.kind` с `"actor"` на `"hex"`. Аудит остальных скиллов (`bash` через все JSON-ы): только default_ranged имел смесь actor+zone — все прочие production AoE уже на hex/self. `chain` area оставляем на actor (chain семантически нуждается в первичном актёре).

Acceptance: в godmode F1 манекен, выбран R/E/W (coffee), курсор на пустой гекс на расстоянии 1 от манекена → preview зоны включает гекс манекена → клик по пустому гексу → манекен теряет 16 HP.

### R2 — AoE preview залитыми гексами

`scripts/presentation/godmode/move_range_overlay.gd` `_draw` блок #5 (`# 5) AoE preview`):
- Сейчас: 6 thin outlines per hex, alpha 0.80, ширина 2.0.
- Стало: залитый polygon per hex (`draw_colored_polygon`), alpha 0.22 (ниже tile content, выше fill, не overwhelm). Поверх — тот же outline (alpha 0.80, 2.0), чтобы граница зоны читалась.
- Цвет — без изменений (`UiTheme.SEM_CONTROL`, выставляется в `show_zone_preview`).

Это покрывает ВСЕ AoE-скиллы (player и враги используют одну overlay), не только coffee.

Acceptance: hover любого AoE-скилла → залитые гексы в зоне видны на дефолтной грин-плитке, не сливаются с tile, граница читается.

### R3 — HP preview на всех целях зоны

`scripts/presentation/godmode/hover_dispatcher.gd` `update_castability`:
- Сейчас: `preview_for_hover = predicted_damage_to(player, hover_target, ctx)` — считается ОДИН раз, ставится только на `hover_target`. Враги не под курсором всегда получают `set_preview_damage(0)`.
- Стало: после расчёта `zone_hexes` собрать `Set<StringName>` ID врагов, чьи координаты входят в `zone_hexes`. Для каждого такого врага вычислить `predicted_damage_to(player, that_enemy, ctx_for_that_hex)` и проставить через `set_preview_damage`. Для всех остальных — 0.

`scripts/presentation/health_bar.gd` `_draw`:
- Сейчас: всегда `"%d/%d" % [hp, max_hp]`.
- Стало: при `_preview_damage > 0` → `"%d → %d" % [hp, max(0, hp - _preview_damage)]`. Иначе старый формат.
- Размер шрифта без изменений (`UiTheme.BAR_FONT_SIZE_OVERHEAD`), цвет без изменений (`UiTheme.TEXT`), outline без изменений.

Acceptance:
- Hover на гекс с двумя манекенами в зоне coffee (radius 1) → у обоих manekins показано `"50 → 34"`.
- Hover ушёл с зоны → у всех манекенов вернулось `"50/50"`.
- Manekin, не входящий в зону → всегда `"50/50"`, без preview.
- Skill, не наносящий урона (heal, buff) → manekin показывает `"50/50"`, не `"50 → 50"`.

## Out of scope

- Heal preview на player'е (`+15` зелёным) — отдельная фича, не в этом спеке.
- Status preview («Slowed (3t)») в HealthBar — это в hex tooltip уже есть после 049 (AC-2).
- Изменения в telegraph-renderer (враждебные intents) — они уже честные, не трогаем.
- Перебалансировка `default_ranged` (radius/damage/range) — это к Стасяну в content tuning, не сюда.

## Зависимости

- Постмерж 049-ux-rehaul (PR #97 — есть в staging) — `cast_range_overlay.show_range_for_ability` с registry-параметром, `_zone_preview` в move_range_overlay уже на месте.
- Постмерж 091 (campaign-skill-choose, Никита) — никаких пересечений по файлам.

## Риски

- **R1**: переход actor→hex для default_ranged означает, что `target.resolve` теперь не вернёт actor (вернёт coord). `Ability.cast` и AoE-effect уже работают через `area.get_affected_hexes(caster, anchor, grid)` — actor под анкором попадает в зону через registry-сканирование. Smoke покрывает.
- **R2**: filled AoE может перекрыть HP-bar / damage label, если те рисуются ниже по z_index. `move_range_overlay` сидит на z=2, HealthBar на actor (Node2D children, типично z=0+) — но HealthBar's `y_offset = -28` рисует НАД tile center, выше z=2 overlay не критично. Проверим в smoke.
- **R3**: per-enemy `predicted_damage_to` цикл по всем actors — N×K вызовов на frame (N=enemies, K=abilities в скилле). Для джем-сценариев (≤8 enemies, 1-2 abilities) это <50 calls/frame, нет beзопасности. Если позже всплывёт — кэш по hover_coord.
