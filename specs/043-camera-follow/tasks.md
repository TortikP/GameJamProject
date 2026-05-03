# 043-camera-follow — tasks

## Чеклист

- [x] **T001** [P1] `godmode_camera.gd`: добавить хелпер `_is_following()` —
  `null + is_instance_valid` гард. Plan §1. AC-6.
  _Файл:_ `scripts/presentation/godmode/godmode_camera.gd`

- [x] **T002** [P1] `godmode_camera.gd`: добавить `_process(_delta)` follow-loop.
  Plan §2. AC-1.

- [x] **T003** [P1] `godmode_camera.gd`: гард в MMB-блоке `_unhandled_input` —
  ранний return при `_is_following()`. Plan §3. AC-2, AC-4.

- [x] **T004** [P1] `godmode_camera.gd`: в `_apply_zoom` параллельный
  position-tween — только если `not _is_following()`. Plan §4. AC-3.

- [x] **T005** [P1] `godmode.tscn`: атрибут `position_smoothing_enabled = true`
  на ноде GodmodeCamera. Plan §"Изменение godmode.tscn". AC-7.
  _Файл:_ `scenes/dev/godmode.tscn`

- [ ] **T006** [P2] Smoke (godmode): запустить F8 godmode-сцену → поводить
  игрока на 3-4 гекса → камера держит центр, smoothing виден; колесо мыши —
  zoom работает; MMB-drag — нет реакции. AC-1, AC-2, AC-3, AC-7.

- [ ] **T007** [P2] Smoke (map_editor): запустить F9 map_editor-сцену →
  MMB-drag двигает камеру; wheel-zoom + zoom-to-cursor работают. AC-4.

- [ ] **T008** [P3] Smoke (level-transition): load custom level через Game
  Editor → камера обновляется на нового игрока без warn'ов / crash'ей.
  AC-6.

## Зависимости

T001 → T002, T003, T004 (хелпер используется).
T005 параллелит с T001-T004.
T006-T008 после T001-T005.
