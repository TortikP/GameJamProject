# 045-intro-cutscene — plan

## Файлы

| Файл | Действие |
|---|---|
| `scripts/presentation/meta/cutscene_player.gd` | new — autoload `CutscenePlayer` |
| `scenes/meta/cutscene_player.tscn` | new — оверлей-сцена |
| `data/cutscenes/intro_awakening.json` | new — sample кутсцен |
| `project.godot` | +autoload `CutscenePlayer` (после CampaignController) |
| `config/game_speed.cfg` | +`[meta] cutscene_slide_min_skip_sec=0.5` если нужен guard |
| `HANDOFF.md` | +короткая секция 21 |

`campaign_controller.gd`, `event_bus.gd` — **не трогаем**. Сигнал и хук уже есть.

## JSON-формат кутсцена

`data/cutscenes/<id>.json`:

```json
{
  "id": "intro_awakening",
  "panels": [
    {
      "image": "res://assets/sprites/cutscenes/intro_01.png",
      "text": "Before the arena... there was silence.",
      "duration": 4.0
    },
    {
      "image": "",
      "text": "Now it calls you.",
      "duration": 3.0
    }
  ]
}
```

- `image` — путь к PNG. Пустая строка → только текст (чёрный фон).
- `text` — строка. Пустая → только картинка.
- `duration` — float, секунды до авто-перехода. `0` = ждать клик/Space/Enter.

Оба поля опциональны. Пустой `panels` → немедленный on_done().

## Архитектура CutscenePlayer

```
CutscenePlayer (autoload, Node, scripts/presentation/meta/cutscene_player.gd)
```

Owns инстанс `scenes/meta/cutscene_player.tscn` — добавляет в дерево сцены
(`get_tree().root`) как оверлей при открытии, удаляет при закрытии.
`process_mode = PROCESS_MODE_ALWAYS` чтобы таймеры работали в паузе.

### Сцена cutscene_player.tscn (Control, CanvasLayer = 30)

```
CutsceneOverlay (CanvasLayer, layer=30)
└── Root (Control, fullscreen, black background)
    ├── ImageRect (TextureRect, stretch_mode=KEEP_ASPECT_CENTERED, anchors=full)
    ├── TextBox (PanelContainer, bottom strip ~20% высоты)
    │   └── PanelText (Label, autowrap)
    └── SkipLabel (Label, top-right: "Space / Click — skip")
```

`UiTheme.apply_label_kind` на PanelText и SkipLabel. Цвет фона — `Color(0,0,0,1)`.

### Публичный API

```gdscript
# Вызывается через signal hook, не напрямую.
func _on_cutscene_requested(cutscene_id: StringName, on_done: Callable) -> void
```

Внутренний flow:
1. Загрузить `data/cutscenes/<cutscene_id>.json`. Если нет → warn + `on_done.call()` + return.
2. `get_tree().paused = true`.
3. Инстанцировать и добавить оверлей в root.
4. `_play_panels(panels, on_done)` — async loop через `await`.
5. По last panel или skip: убрать оверлей, `get_tree().paused = false`, `on_done.call()`.

### Typewriter

Для текста — `_typewriter(label, text, chars_per_sec)`:
```gdscript
var cps: float = GameSpeed.get_value("ui", "dialogue_typewriter_chars_per_sec", 60.0)
for i in range(1, text.length() + 1):
    label.text = text.substr(0, i)
    await get_tree().create_timer(1.0 / cps).timeout  # process_mode=ALWAYS
```

Skip во время typewriter → мгновенно показать весь текст, затем ждать клика (или duration).

### Input

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_accept") or event is InputEventMouseButton and event.pressed:
        _skip_or_advance()
```

`_skip_or_advance()`:
- Если typewriter ещё идёт → force-complete текущий слайд (показать весь текст).
- Если typewriter завершён и слайд с `duration > 0` → досрочно перейти к следующему.
- Если был нажат отдельный Skip-button (или Escape) → emit внутренний `_skip_all` флаг.

**Нет отдельной кнопки Escape-to-menu** — кутсцен можно только проскипать вперёд, не выйти в меню.

## Точки интеграции

- `EventBus.campaign_cutscene_requested(cutscene_id, on_done)` — существует в 035.
  `CutscenePlayer._ready()` коннектится к нему.
- `CampaignController._emit_cutscene_request` — таймаут 0.5 сек (cutscene_request_timeout_sec).
  Нужно убедиться что этот таймаут не срабатывает раньше `on_done`. Решение: `on_done`
  вызывается нами быстрее чем timeout (`process_mode=ALWAYS`, но timeout тоже ALWAYS —
  race). **Безопасно:** `_callback_fired` в CampaignController — latch, двойной вызов on_done
  игнорируется. Наш `on_done` зовётся после last slide (≤10 сек), timeout = 0.5 сек →
  **timeout выстрелит раньше нас** если кутсцен > 0.5 сек. Это ломает flow.

  **Фикс** (единственный) — увеличить `cutscene_request_timeout_sec` в game_speed.cfg до
  значения чуть больше максимального кутсцена (например 15.0). Это единственная правка
  в `config/game_speed.cfg`. `campaign_controller.gd` не трогаем — он уже читает из GameSpeed.

## game_speed.cfg — добавляемые ключи

```ini
[meta]
# existing: rewind_effect_duration=0.8, boss_intro_duration=3.0
cutscene_request_timeout_sec=15.0    # was 0.5 (implicit default) — raised for real cutscenes
cutscene_slide_min_skip_sec=0.5      # guard: skip нажат слишком рано → только force-complete typewriter
```

## Ownership / CLAUDE.md

Добавить в таблицу «Currently claimed»:
```
| 045-intro-cutscene (CutscenePlayer autoload, data/cutscenes/) | Andrey |
```
