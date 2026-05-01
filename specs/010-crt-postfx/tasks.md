# 010-crt-postfx — tasks

P0 = ship-blocker. P1 = polish-after-P0. P2 = nice-to-have.

## P0 — minimum shippable CRT

- [x] T001 [P0] Создать `scenes/presentation/` (новая папка, `.gdignore` не нужен).
- [x] T002 [P0] Написать `scripts/presentation/crt/crt.gdshader` — минимальная версия:
      barrel curvature + scanlines + bezel mask + vignette. Без bloom, aperture, chroma, warm.
      Все uniform-ы с дефолтами по plan.md.
      ⚠ По факту реализован сразу полный шейдер (T002+T010..T013) одним файлом —
      разбивка на коммиты в одном маленьком .gdshader даёт нулевую пользу.
- [x] T003 [P0] Написать `scripts/presentation/crt/crt_post_fx.gd` — autoload-скрипт,
      `_unhandled_input` ловит `KEY_F6` → `toggle()`. Использует `GameLogger`
      (не `Logger` — см. CLAUDE.md trap). Без `class_name` (не затмеваем имя
      autoload-синглтона, паттерн от `EventBus`/`GameSpeed`).
- [x] T004 [P0] Сцена `scenes/presentation/crt_post_fx.tscn`: CanvasLayer (layer=128) +
      ColorRect (anchors_preset=15, mouse_filter=2 IGNORE, material=ShaderMaterial→crt.gdshader).
- [x] T005 [P0] Прописать autoload в `project.godot` после `SkillDatabase`.
- [ ] T006 [P0] **(требует Godot)** Прогнать в Godot: открыть проект, запустить main_menu, убедиться что:
      - картинка изогнута,
      - сканлайны видны,
      - F6 переключает,
      - кнопки меню кликаются.
      Этот шаг делает Андрей локально — я в контейнере без Godot.
- [ ] T007 [P0] Зафиксировать в коммит: `feat(crt): minimal CRT post-fx (curvature + scanlines)`.
      Сделано как один коммит с полным шейдером, см. T015.

## P0 — добивка эффектов

- [x] T010 [P0] Шейдер: добавить chromatic aberration через 3-tap по R/G/B со смещением
      `chroma_strength * SCREEN_PIXEL_SIZE * uv_centered`. Чем дальше от центра — тем
      сильнее (домножаем на `length(uv_centered)`).
- [x] T011 [P0] Шейдер: добавить aperture mask. Триплеты RGB по горизонтали, период 3
      физических пикселя окна. Использовать `FRAGCOORD.x` или `SCREEN_UV.x / SCREEN_PIXEL_SIZE.x`.
- [x] T012 [P0] Шейдер: добавить тёплый tone grade — `mix(c, c * warm_tint, warm_strength)`,
      затем лёгкое `pow(c, vec3(0.95))` для тёплых теней.
- [x] T013 [P0] Шейдер: bloom-ish — 4-tap box blur по соседям ±2 пикселя, добавить
      от bright pixels (luma > 0.6) с весом `bloom_strength`.
- [ ] T014 [P0] **(требует Godot)** Прогнать в editor: подкрутить дефолты так чтоб «было красиво» по
      ощущению. Закоммитить дефолты обратно в шейдер. Этот шаг делает Андрей.
- [x] T015 [P0] Коммит: `feat(crt): full effect chain (chroma + aperture + warm + bloom)`.

## P0 — push + PR

- [x] T020 [P0] `git push -u origin andrey/crt-postfx`, забрать URL для PR из stderr.
- [x] T021 [P0] Дать URL Андрею в чате, чтобы он открыл PR в браузере.

## Также добавлено в этой PR (вне исходного P0)

- [x] +bonus: keybind_overlay.gd — добавлена строка F6 → "Toggle CRT effect"
      (T032 из P1 — однострочная правка, не вижу смысла откладывать).

## v2 — итерация по скриншоту

После первого прогона на реальном экране Андрей прислал скрин с двумя проблемами.
Поправлено вторым коммитом в той же ветке:

- [x] T050 [P0] **Макро-арки сверху/снизу.** Был муар: `scanline_count=720` × cos(uv.y·720·2π)
      против фактической высоты окна ~738 → бит с разностью ~18 → видимые тёмные
      широкие полосы. Привязал сканлайны к `FRAGCOORD.y` через `scanline_pitch_px`
      (физические пиксели окна, дефолт 3.0). Теперь паттерн строго на пиксельной
      решётке, муара нет вообще.
- [x] T051 [P0] **Виньетка эллипсом.** Считал `length(from_center)` в UV, где X и Y
      нормированы к [0,1] на 16:9-экране → радиальный градиент сплющен. Поправил:
      x-компонента from_center множится на aspect ratio через
      `SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x`. Теперь круглая.
- [x] T052 [P0] **«Мутно, не лампово».** Стек × вниз (scan × aperture × vignette × pow)
      ронял яркость до ~60% от исходной. Добавил `boost` uniform (дефолт 1.35),
      применяется ПОСЛЕ затемняющих операций. Картинка читается ярко-тёплой.
- [x] T053 [P0] **Чёрный — настоящий чёрный.** ЭЛТ так не делает: фосфор всегда
      слегка светится. Добавил `phosphor_glow` (vec3, янтарный, амплитуда ~0.03)
      внутри маски экрана. Теперь тени дышат тёплым.
- [x] T054 [P0] **Усиление amber-grade.** warm_tint сместил в (1.18, 1.04, 0.78),
      warm_strength 0.18 → 0.28. Bloom: threshold 0.55 → 0.45, strength 0.32 → 0.55,
      радиус 2 → 3 px. Vignette: 0.6 → 0.42 (углы дышат).
- [x] T055 [P0] Обновил соответствующие куски plan.md.

## P1 — после P0

- [ ] T030 [P1] Settings-panel: чекбокс «CRT effect» рядом с volume-слайдерами.
      `settings_panel.gd` дёргает `CrtPostFx.enabled = ...`. Состояние сохраняется
      туда же, где volume (надо посмотреть, через ConfigFile или просто in-memory).
- [ ] T031 [P1] Слайдер «CRT intensity» (0.0–1.0), мультиплицирует все strength-ы
      сразу. По умолчанию 1.0.
- [ ] T032 [P1] Обновить `keybind_overlay.gd` — добавить строку `["F6", "Toggle CRT"]`.

## P2 — если останется время

- [ ] T040 [P2] Опциональный 50 Hz hum: медленный roll яркости через `TIME * hum_speed`.
      Uniform `hum_strength` дефолт 0.0. Для скриншотов выключено.
- [ ] T041 [P2] CRT power-on/off анимация (белая точка → expand). Отдельный uniform
      `power_progress` 0..1, контроллер тваенит при `enabled` change.
- [ ] T042 [P2] Звук электростатического гула + щелчка при F6 (через AudioDirector).

## Зависимости задач

- T002 нужен для T004 (сцена ссылается на шейдер).
- T003 нужен для T004 (сцена ссылается на скрипт).
- T004+T005 нужны для T006 (тест в Godot).
- T010..T013 идут друг за другом по слоям, но ломают шейдер только локально —
  если один эффект сглючит, откатываем тот коммит.
