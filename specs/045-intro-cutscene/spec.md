# 045-intro-cutscene — spec

**Owner:** Andrey.
**Status:** Draft (rewrite — replaces slide-show plan, see git history).

## Контекст

Существующий cutscene-hook в `CampaignController` (035) эмитит
`EventBus.campaign_cutscene_requested(cutscene_id, on_done)` если у текущего
уровня в `ActiveGame` непустой `cutscene_id`. Никто не слушал, таймаут 0.5s,
flow продолжался.

Изначальный план 045 — generic JSON-слайд-шоу. Отброшен: для джемного интро
нужен конкретный кинематографичный момент, не редактор слайдов.

**Новый план (Plan A — fullscreen overlay):**

1. Жмём "Начать забег" в главном меню → камера отъезжает «через голову
   персонажа» через два концепт-арта (`cutscene_2.png` с фигурой → fade →
   `cutscene_1.png` без фигуры).
2. Поверх живого уровня `office_intro` (полноценный `data/maps/<...>.json`)
   спадает overlay — игрок видит пустую сцену офиса.
3. Проигрывается диалог.
4. Игрок (заскриптованно) шагает 1 хекс на юг — камера следит (043-camera-follow).
5. Существующий `level_transition.gdshader` рисует стандартный переход → `story_map_01`.

Во время шагов 1–4 нельзя играть: HUD скрыт, зум/пан камеры залочен,
ввод игрока заглушен. Триггер всех трёх локов — кампанийный `is_intro: true`,
который УЖЕ в схеме (`scripts/core/maps/game_data.gd`) и ныне no-op.

## Бюджет / scope

- Cutscene-art transition ≤ 3 сек.
- Диалог ≤ 12 сек (Никита решает текст; ставлю плейсхолдер).
- Move + transition shader ≤ 2 сек.
- Итого intro ≤ ~17 сек, скип всегда доступен.

## Acceptance criteria

- **AC-1 (campaign).** В `data/games/story_campaign.game.json` появился
  `office_intro` *первым* уровнем. На нём `is_intro=true`,
  `cutscene_id="intro_office"`. Со `story_map_01` снят `is_intro` и
  `cutscene_id` (теперь `false` / `""`).

- **AC-2 (level).** `data/maps/office_intro.json` существует — небольшая
  карта (≈5×5 хексов), биом «office» (slot 7 атласа), декорирована
  `object_computer` / `object_cooler` / `object_on_chair`. Player spawn —
  на хексе со стулом. Враги: 0. Волны: 0.

- **AC-3 (cutscene art).** При входе в `office_intro` `CutscenePlayer`
  получает `campaign_cutscene_requested("intro_office", on_done)`, рисует
  fullscreen-overlay:
  - Кадр 1: `cutscene_2.png` (с персонажем), scale 1.0 → 0.7 за 1.2s
    (создаёт ощущение «отлёт назад»).
  - Кросс-fade к `cutscene_1.png` (без персонажа), scale продолжает с 0.7
    до 0.6 за 0.8s.
  - Fade-out alpha → 0 за 0.6s, overlay убран, `on_done` вызван.
  - Скип (Space/click/Enter) → мгновенно завершить, `on_done`.

- **AC-4 (locks при is_intro).** Когда `ActiveGame.current_is_intro() == true`:
  - `HUD.visible = false` (CanvasLayer в godmode.tscn).
  - `GodmodeCamera` не реагирует на колесо мыши (зум) и MMB-pan.
  - `GodmodeInput` сразу `return` для всех player-actions (LMB-cast, hotkeys,
    move, wait). ESC → pause-меню остаётся доступным (для аварийного выхода).
  - При переходе на следующий уровень (где `is_intro=false`) всё восстанавливается.

- **AC-5 (диалог).** После `on_done` cutscene-art'а — `IntroDirector` зовёт
  `DialogueManager.play_dialogue("intro_office_monologue")` напрямую (не
  через `level_dialogue_director`). Awaits `EventBus.dialogue_finished`.
  Контент диалога — Никите; ставлю sample на 2–3 реплики.

- **AC-6 (scripted move + camera follow).** После `dialogue_finished`:
  `IntroDirector` зовёт `HexGrid.move_actor(player_id, south_neighbor)`.
  Awaits `EventBus.actor_moved`. Камера 043-camera-follow уже подхватит
  плавную центровку без правок.

- **AC-7 (level_completed).** После move'а `IntroDirector` эмитит
  `EventBus.level_completed.emit(0)`. `CampaignController` обрабатывает:
  стандартный transition shader → следующий уровень (`story_map_01`).

- **AC-8 (skip всё).** Скип во время cutscene-art работает (AC-3).
  Скип во время диалога — стандартный (DialogueManager сам обрабатывает
  пробел/клик). Скип во время move'а — нет (≤0.4s, не успеваешь).

- **AC-9 (нет регрессии без is_intro).** На уровнях с `is_intro=false`
  HUD виден, зум/пан работают, ввод работает. `IntroDirector._on_scene_ready`
  early-returns. CutscenePlayer — early-return если `cutscene_id == ""`
  (signal эмитится только когда непустой, но guard для надёжности).

- **AC-10 (Godmode / Load Custom — без поломок).** Запуск из главного меню
  Godmode (без ActiveGame) или Load Custom Level — `is_intro=false`
  (нет ActiveGame), `IntroDirector` молчит, всё как было.

- **AC-11 (touch budget).** Изменения по файлам см. plan.md.
  `event_bus.gd` — без изменений (все нужные сигналы есть).
  `level_data.gd` / `game_data.gd` — без изменений (`is_intro` уже в схеме).
  `campaign_controller.gd` — 1 правка: поднять `cutscene_request_timeout_sec`
  до 4.0 (cutscene-art до 3 сек, нужен запас).

## Out of scope

- Анимация спрайта персонажа во время «шага» (sit→stand sprite swap, idle frames). Используем существующий step animator из 043; визуально это просто скольжение спрайта на 1 хекс.
- Озвучка диалога (AudioDirector hooks — отдельно).
- Локализация диалога (пишем сразу на нужном языке в JSON, как принято).
- Отдельный редактор интро в Game Editor.
- Воспроизводимое intro для других уровней — `is_intro=true` тянет за собой ВЕСЬ скрипт (cutscene→dialogue→step→complete), это не generic фича. Если понадобится intro на другом уровне — копи-пейст IntroDirector с другими параметрами в новом спеке.
- Возврат камеры в исходное положение при пропуске cutscene'а — overlay рисуется поверх живой сцены, никакой реальной Camera2D-анимации нет, возвращать нечего.
