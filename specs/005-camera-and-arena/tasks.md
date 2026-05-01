# 005-camera-and-arena — tasks

Один таск — один логический шаг. `[P]` = можно делать параллельно с предыдущим, `[depends Tnnn]` = строгая зависимость. Все P1 (фича маленькая).

- [ ] T001 [P1] `config/game_speed.cfg`: добавить в секцию `[godmode]` ключи `zoom_step=0.1`, `zoom_min=0.5`, `zoom_max=3.0`, `zoom_lerp_duration=0.12`. См. `plan.md` §4.
- [ ] T002 [P1] [P] `scripts/presentation/godmode/godmode_controller.gd`: изменить константы `GRID_W := 14`, `GRID_H := 9`. Не трогать остальную логику, `_place_player()` уже использует `GRID_W/2, GRID_H/2`.
- [ ] T003 [P1] Создать `scripts/presentation/godmode/godmode_camera.gd` (extends Camera2D) по `plan.md` §3. Реализовать `_unhandled_input` (колесо), `_apply_zoom` с clamp, lerp через Tween, zoom-к-курсору, `_center_on_player` в `_ready` через `call_deferred`.
- [ ] T004 [P1] Обновить `scenes/dev/godmode.tscn`: добавить `Camera2D` (имя `GodmodeCamera`) как child от корневого `Godmode` Node2D. `script = godmode_camera.gd`, `current = true`, `enabled = true`, `zoom = (1, 1)`, `position_smoothing_enabled = false`. (depends T003)
- [ ] T005 [P1] Smoke-test plan: ручной чеклист в `specs/005-camera-and-arena/SMOKE.md` — 6 пунктов из spec.md "Acceptance verification". Прогнать, отметить.
- [ ] T006 [P1] Push ветку `<user>/<name>`, открыть PR `→ staging`. (depends T005)

## Проверки на ревью

- Колесо НЕ скроллит игровой UI / SlotBar / какие-либо контейнеры (event handled в камере).
- Игрок не выходит за визуально видимые пределы при зум-out до min (карта 14×9 должна целиком влезать на экран).
- Никаких хардкоженных `0.1`, `0.5`, `3.0` в коде — только через `GameSpeed.get_value`.
- При смерти игрока `_center_on_player` не падает (он ищет узел "Player" — если Player умер, ноды может уже не быть; но это `_ready`, до смерти игрока далеко). Если защита нужна — `if player != null`.
