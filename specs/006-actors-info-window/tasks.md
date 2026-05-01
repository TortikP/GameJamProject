# 006-actors-info-window — tasks

- [ ] T001 [P1] `actor.gd` — добавить `@export var speed: int = 1`, `@export var damage_bonus: int = 0`, `var _ability_ids: Array[StringName]`, методы `set_abilities / get_abilities`
- [ ] T002 [P1] `damage_effect.gd` — `apply`: `max(0, amount + caster.damage_bonus)` + KEEP IN SYNC комментарий
- [ ] T003 [P1] `ability.gd` — `predicted_damage_to`: та же формула + KEEP IN SYNC
- [ ] T004 [P1] `hex_grid.gd` — добавить `reachable_within(from, max_steps, occupied) -> Array[Vector2i]` (BFS)
- [ ] T005 [P1] `godmode_controller.gd` — speed-aware `_request_move` (depends T001, T013)
- [ ] T006 [P1] `move_range_overlay.gd` — новый скрипт, `setup(grid)` / `show_for(actor, registry)` / `clear()` (depends T004)
- [ ] T007 [P1] `godmode.tscn` — добавить MoveRangeOverlay как child HexGrid (depends T006)
- [ ] T008 [P1] `actor_inspector.gd` — новый скрипт: `bind(actor)` / `unbind()`, SpinBox handlers, abilities row с тултипами
- [ ] T009 [P1] `actor_inspector.tscn` — PanelContainer TR, VBox: id/team/hp/spinboxes/abilities/hint (depends T008)
- [ ] T010 [P1] `godmode.tscn` — добавить ActorInspector в HUD (depends T009)
- [ ] T011 [P1] `godmode_controller.gd` — `_selected`, `_select()`, `_deselect_to_player()`, новая LMB-логика, ESC, actor_died handler (depends T008, T006)
- [ ] T012 [P1] `manekin_view.gd` — `_ready`: `set_abilities([attack_ability_id])` (depends T001)
- [ ] T013 [P1] `player.tscn` — override `speed = 2` (depends T001)
- [ ] T014 [P1] `godmode_controller._seed_slots` — после заполнения слотов: `player.set_abilities([...])` (depends T001)
