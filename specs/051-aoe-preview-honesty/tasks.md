# 051-aoe-preview-honesty — tasks

Spec: `spec.md`. Plan: `plan.md`. Branch: `andrey/051-aoe-preview-honesty`.

## Phase A — coffee bombs the ground

- [x] **T001** — `data/skills/default_ranged.json`: `target.kind` `"actor"` → `"hex"`. Без других правок.

## Phase B — filled AoE preview

- [x] **T002** — `scripts/presentation/godmode/move_range_overlay.gd` `_draw` блок #5 (`# 5) AoE preview`): вставить `draw_colored_polygon` fill (alpha 0.22) перед существующим outline-loop'ом. Outline сохраняем (alpha 0.80, 2.0 px).

## Phase C — per-enemy HP preview в зоне

- [x] **T003** — `scripts/presentation/godmode/hover_dispatcher.gd` `update_castability`:
  - Поднять вычисление `zone_hexes` ВЫШЕ damage-preview блока (сейчас оно в самом низу).
  - Заменить логику preview: вместо `if a == hover_target` — `if a.coord ∈ zone_hexes`.
  - При `active_skill == null` или `preview_ability == null` или `not active_skill.can_apply(player, ctx)` — все enemy preview = 0 (как сейчас).

- [x] **T004** — `scripts/presentation/health_bar.gd` `_draw`:
  - При `_preview_damage > 0` → `text = "%d → %d" % [_actor.hp, max(0, _actor.hp - _preview_damage)]`.
  - Иначе старый `"%d/%d"`.

## Phase D — smoke + commit

- [ ] **T005** — Smoke в godmode (см. `plan.md §Smoke`).
- [x] **T006** — Commit + push + PR URL для Андрея.
