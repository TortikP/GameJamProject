# 045-intro-cutscene — spec

**Owner:** Andrey.
**Status:** Draft.

## Контекст

`CampaignController` (035) уже эмитит `EventBus.campaign_cutscene_requested(cutscene_id, on_done)`
когда уровень в ActiveGame несёт непустой `cutscene_id`. Никто не слушает — сигнал падает в никуда,
таймаут 0.5 сек, игра молча продолжается. Этот спек добавляет реального слушателя:
`CutscenePlayer` — оверлей, который играет слайд-шоу из JSON и вызывает `on_done` по окончании.

**Бюджет по HANDOFF §14:** «Интро-катсцены длиннее 10 секунд — не делаем.»
Значит: короткое слайд-шоу, максимум 3–4 панели, суммарно ≤ 10 сек. Анимации нет, видео нет.

## Цель

Показать 1–N слайдов (картинка + текст) поверх только-загруженного уровня.
Пауза игры на время показа. Завершение по последнему слайду **или** по нажатию Skip.
После завершения вызвать `on_done` — CampaignController продолжает обычный flow.

## Acceptance criteria

- **AC-1 (интеграция).** `CutscenePlayer` подписан на `campaign_cutscene_requested`.
  При получении — overlay открыт, `get_tree().paused = true`. После last slide или Skip —
  `get_tree().paused = false`, вызван `on_done()`.
- **AC-2 (data-driven).** Каждый кутсцен — `data/cutscenes/<id>.json`. Структура — см. plan.md.
  Если файл не найден → warn-once, немедленный `on_done()` (скип без краша).
- **AC-3 (слайды).** Каждый слайд: опциональная картинка + текст typewriter (скорость из GameSpeed).
  Авто-переход через `duration` сек (если `duration > 0`), иначе — по клику/Space/Enter.
- **AC-4 (skip всегда).** Кнопка/клавиша Skip доступна с первого слайда.
  Skip → немедленный `on_done()` без показа оставшихся слайдов.
- **AC-5 (без активной игры — без кутсцена).** Godmode / Load Custom Level (без ActiveGame)
  не трогает CutscenePlayer. Signal эмитится только CampaignController при `has_active_game()`.
- **AC-6 (sample).** `data/cutscenes/intro_awakening.json` — 2 слайда, суммарно ≤ 8 сек.
  `data/games/sample.game.json` уже несёт `cutscene_id: "intro_awakening"` на первом уровне —
  Load Game → Start → кутсцен проигрывается.
- **AC-7 (GameSpeed).** Typewriter-скорость — `GameSpeed.get_value("ui", "dialogue_typewriter_chars_per_sec")`.
  Duration слайда уважает `process_mode = PROCESS_MODE_ALWAYS` (дерево паузировано).
- **AC-8 (touch budget).** Вне `scripts/presentation/meta/cutscene_player.gd` +
  `scenes/meta/cutscene_player.tscn` + `data/cutscenes/` — правки только:
  `project.godot` (+1 autoload), `config/game_speed.cfg` (+1 ключ если нужен),
  `HANDOFF.md` (+секция). `campaign_controller.gd` — 0 правок.

## Out of scope

- Анимации переходов между слайдами (fade, wipe). Простая смена панели.
- Видео / GIF.
- Несколько кутсцен на один уровень.
- Кутсцены в середине уровня (только до старта волн — через existing `scene_ready` hook).
- Редактор кутсцен в Game Editor.
- Озвучка (AudioDirector dispatch — отдельный PR если появится аудио).
- Локализация текстов (пишем напрямую в JSON на нужном языке, как dialogue content).
