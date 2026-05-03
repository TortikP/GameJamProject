# 050-sprite-fit-tile-width — tasks

Линейные, выполняются в указанном порядке. Параллелить нечего — фича маленькая.

## Phase A — Sprite fit

- [x] **T001** — `scripts/infrastructure/sprite_fit.gd`: создать static utility со `fit_to_tile_width(sprite, tile_width=128, base_scale=1.0)`. Guards на null sprite / null texture / zero width. Лог через `GameLogger.warn`. Без `class_name`. Проверка: файл компилируется в Godot (через визуальную проверку / parse).
- [x] **T002** — `scripts/presentation/godmode/player_view.gd`: создать subclass `extends Actor`. `_ready()` — find Body, fitter call, `super._ready()`. Проверка: file syntax-ok.
- [x] **T003** — `scenes/dev/player.tscn`: swap root script ext_resource с `actor.gd` на `player_view.gd`. Удалить `scale = Vector2(1.5, 1.5)` у Body. `position = Vector2(0, -5)` сохранить.
- [x] **T004** — `scripts/presentation/godmode/enemy_view.gd`: добавить preload `SpriteFit`, вызвать `SpriteFit.fit_to_tile_width(body)` после `body.texture = tex` (один if-блок).
- [x] **T005** — `scenes/dev/enemy.tscn`: удалить `scale = Vector2(1, 1)` у Body (явное дублирование дефолта, fitter перезапишет).
- [x] **T006** — `scripts/presentation/dev/objects_overlay.gd`: добавить preload `SpriteFit`, helper `_tile_width()` (читает из grid если возможно, иначе 128), вызвать fitter после `sprite.texture = tex` с `sprite_scale` как base_scale.
- [x] **T007** — `scripts/presentation/runtime/spawner_placeholder.gd`: добавить preload `SpriteFit`, вызвать `SpriteFit.fit_to_tile_width(_sprite)` в конце `_apply_visuals()`.
- [x] **T008** — `scenes/runtime/spawner_placeholder.tscn`: удалить `scale = Vector2(0.09, 0.09)` у Sprite.

## Phase B — Dialogue portrait

- [x] **T009** — Скопировать `acpest.png` (uploaded) в `assets/portraits/default_portrait.png` (через `cp`).
- [x] **T010** — Создать `assets/portraits/default_portrait.png.import` по шаблону `assets/sprites/bush.png.import`. Свежий uid, корректный source_file, placeholder hash в `path`/`dest_files` (Godot регенерит).
- [x] **T011** — `scenes/ui/dialogue_panel.tscn`: Portrait `custom_minimum_size = Vector2(130, 180)`.
- [x] **T012** — `scripts/presentation/dialogue_panel.gd._make_placeholder()`: rewrite — пробует загрузить `res://assets/portraits/default_portrait.png` через `_try_load_texture`, кэширует под key `__default__`, fallback flat rect 130×180. Аргумент `speaker_id` сохранить для совместимости (no-op).

## Phase C — Push

- [x] **T013** — Git: `add -A`, commit `feat(050): sprite-fit-tile-width — actors/objects scale to hex width 128, dialogue Portrait 13:18 with default placeholder`. Push to origin. Захватить PR-creation URL из stderr → отдать Андрею для merge в browser.

## Phase E — Revision 1 (post-review)

- [x] **T014** — `scripts/presentation/godmode/enemy_view.gd`: удалить SpriteFit preload и вызов `fit_to_tile_width(body)`.
- [x] **T015** — `scripts/presentation/runtime/spawner_placeholder.gd`: удалить SpriteFit preload и вызов в `_apply_visuals`.
- [x] **T016** — `scenes/runtime/spawner_placeholder.tscn`: восстановить `scale = Vector2(0.09, 0.09)` у Sprite.
- [x] **T017** — `scenes/dev/player.tscn`: вернуть root script на `actor.gd`, восстановить `scale = Vector2(1.5, 1.5)` у Body.
- [x] **T018** — Удалить `scripts/presentation/godmode/player_view.gd` (больше не используется).
- [x] **T019** — `scenes/ui/dialogue_panel.tscn` Portrait: per скриншот ревью — `expand_mode=0` (Keep Size), `stretch_mode=2` (Keep), `size_flags_vertical=4` (Shrink Center), `clip_contents=true`.
- [x] **T020** — Импортировать партию ассетов от Кати (14 файлов из `assets_1639.zip`) с маппингом: `aspect_*` → `assets/portraits/`, `enemy_*` → `assets/sprites/enemies/` (drop prefix), `object_*`/`tile_*` → `assets/tiles/`. Сгенерировать `.png.import` sidecar для новых файлов; для overwritten (teapot.png, object_lava.png) — сохранить существующие .import (Godot re-импортирует на следующем открытии).
- [ ] **T021** — Git commit + push fix-коммита поверх T013.

## Phase D — Smoke (manual, after merge)

Не блокирует push, но критично перед закрытием PR. Андрей делает в Godot editor:

- [ ] **S1** — F2 reset godmode → player Body ≈ 128px wide.
- [ ] **S2** — F1 spawn manekin, bear, angel — все ≈ 128px wide.
- [ ] **S3** — Map editor → paint tree / mountain / crystal — все ≈ 128px wide.
- [ ] **S4** — Запустить wave с manekin spawner за 3+ хода — placeholder ≈ 128px wide, label читается над ним.
- [ ] **S5** — Запустить intro_office_monologue → слот Portrait 130×180, видна acpest-картинка (silhouette).
- [ ] **S6** — Если есть speaker с реальным `default_portrait` файлом (положить тестовый narrator_neutral.png 130×180 в assets/portraits/, запустить narrator dialogue) → подхватился он, не дефолт.

Если что-то ломается — детали в issue, не блокирует merge остального (feature независима от боя/AI).
