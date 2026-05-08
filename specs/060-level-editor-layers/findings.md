# 060 — Findings (during implementation)

Записи неожиданностей, всплывающих по ходу реализации. Не правят спек на ходу — это лог. Когда что-то существенно меняет дизайн, выноси в отдельный спек или PR-комментарий, спроси Андрея.

---

## F-060-IMPL-1 — `_set_active` call sites: plan и код расходятся, переинтерпретирую по принципу спека

**Фаза:** Φ-1 (T-060-1).

**Что нашёл.** Plan в §Φ-1 даёт таблицу `by_user` значений для 5 call sites `_set_active` в `panel_tab_bar.gd`. По факту — 6 call sites (89, 242, 329, 387, 457, **485**), и labels плана для 329/387 не совпадают с тем, что в коде:

| Line | Контекст в коде | Plan label | Plan `by_user` |
|---|---|---|---|
| 89 | `setup()` initial active | "initial setup в `_ready`" | false |
| 242 | `_on_tab_button_gui_input` после клика | "после клика по табу" | true |
| 329 | **`_detach_tab_active_drag` — авто-switch при отрыве таба** | "после reattach detached tab" | true |
| 387 | **`_reattach` — активация реаттаченного таба** | "re-register flow" | false |
| 457 | `register_tab` — первый таб становится активным | "первый таб в `add_tab()` (programmatic)" | false |
| 485 | `unregister_tab` — авто-switch при удалении активного таба | (не в плане) | — |

Plan, видимо, перепутал labels для 329 и 387.

**Что выбрал.** Спек §Φ-1 явно говорит: «**Только** на пользовательский click (не на programmatic restore из persistence)». Применяю этот принцип буквально:

| Line | `by_user` (моё решение) | Обоснование |
|---|---|---|
| 89  | false | Initial setup, не клик |
| 242 | **true** | Единственное место реального user click |
| 329 | false | Tab оторвали → система выбрала next, юзер не выбирал next |
| 387 | false | Reattach — юзер дропнул панель, активация — побочный эффект, не выбор таба |
| 457 | false | Programmatic add_tab |
| 485 | false | Removal triggered cleanup, не user choice |

**Почему так.** Consumer'ы (LayersPanel в Φ-3) подписываются на `active_tab_changed` чтобы синхронизировать `LayersModel.active_layer`. Если detach/reattach эмитят `true` — consumer получит false-positive «юзер сменил слой» когда он на самом деле просто двигал панель. Семантика «активный таб» != семантика «юзер выбрал слой».

**Impact на 060.** Никакого — LayersPanel не использует tear-off в Spec 060 (явно out of scope, spec.md §4). Линии 329/387/485 в 060 не активируются. Решение важно только как precedent для будущих consumers.

**Impact на план.** Plan'овая таблица в §Φ-1 — incorrect. Если позднее кто-то переоткроет вопрос, отсылка сюда.

**Action для Андрея.** Подтверди трактовку. Если нужно «detach/reattach считать user-driven» — flip 329 и 387 на true, мелкое изменение.

---

## F-060-IMPL-2 — Φ-6 cap pressure: extracted into TWO new files, not EditorIO

**Фаза:** Φ-6 (T-060-43 fallback).

**Что нашёл.** Φ-6 controller, even with aggressive doc-trimming, sat at 326 lines when fully implemented per plan §Φ-6.c. T-060-43 specifies the fallback: "extract `_prompt_autosave_restore` + `_check_multi_wave_warning` в EditorIO с callback'ами." But this contradicts plan §Φ-2's explicit constraint: "EditorIO не открывает ConfirmModal сам... IO has no scene-tree opinions." Putting the prompt in IO crosses the I/O-only boundary that Φ-2 was careful to draw.

**Что сделал.** Two new sibling files instead of stuffing into IO:

1. **`level_mutations.gd`** (45 lines, RefCounted, all-static). Holds `set_or_update_floor_cell`, `remove_at_coord`, `refresh_overlay`. Pure data-mutation primitives — no I/O, no rendering, no signals. Used by all paint/erase methods + cascade.
2. **`editor_startup.gd`** (87 lines, RefCounted, all-static). One-shot startup flow: `run(io, level, meta_panel, confirm_modal, tree) -> LevelData`. Branches on ActiveLevel.has_queued / autosave-prompt-needed / blank slate. Internally calls `confirm_modal.ask` and emits the multi-wave warning toast — this WAS in controller, now it's here.

Controller drops to 269 / 300 with margin. Single `_ready` line: `_level = await EditorStartup.run(_io, _level, _meta_panel, _confirm_modal, get_tree())`.

**Trade-offs.**
- (+) Both new files are static-only — no instance state, no lifecycle quirks, easy to test/reason about.
- (+) Φ-2's "IO has no modal" boundary stays intact.
- (+) Controller reads as a thin orchestrator — _ready, mutations, slot handlers — without the autosave/handoff branching mid-file.
- (−) Two new files vs the plan's one-file-extension. Mild abstraction inflation.
- (−) `editor_startup.gd` references `EventBus` directly for toasts — same pattern as the legacy controller, but now in a third place. Deferred refactor candidate.

**Action для Андрея.** Confirm extraction approach. If you'd rather have a single editor_lifecycle.gd merging both helpers, or push the data-helpers back into controller and only extract startup, I can collapse — both alternatives are simple post-Φ-6 commits.

---

## F-060-IMPL-3 — AC4 / AC5 пропуск в Φ-4: иконки добавлены пост-фактум

**Фаза:** Φ-4 follow-up.

**Что нашёл.** spec.md AC4 и AC5 явно требовали иконки в палитрах: AC4 «иконка из data/enemies/<id>.json portrait», AC5 «иконка из TileObject.icon или sprite». В Φ-4 я ориентировался на plan §Φ-4 (там было «text-only buttons» как упрощение) и сделал палитры без иконок. Plan был мягче AC. AC жёстче — приоритет AC.

**Что сделал.** Follow-up commit поднимает AC4/AC5:
- `palette_helpers.gd` обзаводится `ICON_SIZE = Vector2(72, 72)` (общий размер для всех трёх палитр), `make_icon_button(group, label, texture, fallback_glyph)` и `load_texture(path)` (с res:// нормализацией). 29 → 71 строк.
- `SpawnerPalette` теперь сканирует `data/enemies/*.json:sprite`, грузит PNG'и, кладёт как `btn.icon`. Player → glyph "★" (нет ассета, матчит idiom SpawnersOverlay).
- `ObjectPalette` берёт `TileObject.sprite_path` через registry, грузит PNG, кладёт как icon.
- `HexTilePalette` поднял `custom_minimum_size` 48→72 через ту же общую константу.
- Missing-asset fallback: первая буква id монограммой.
- Bump LayersPanel size: `level_editor.tscn` 264×300 → 304×420; `layers_panel.tscn` `min_panel_size` 220×240 → 280×360. Иначе 12 врагов в 3 столбца не помещались по высоте.

**Trade-offs.**
- (+) AC закрыты честно (была дыра в скоупе 060).
- (+) Один общий ICON_SIZE — консистентно для всех трёх палитр. Поменять на 64/96 — одна правка.
- (+) Спрайты из JSON — никаких новых ассетов не пилили.
- (−) Бамп размера панели потенциально влияет на персистенс пользователя (если кто-то её ужал). Но `min_panel_size` это floor, не значение по умолчанию, так что persisted value берёт верх — должно быть мирно.
- (−) JSON parse в `_list_enemy_entries` каждый раз при открытии редактора — не cached. На 12 врагов ~1мс. Будет дороже на 100+ — тогда достанем EnemyRegistry (которого пока нет).

**Action для Андрея.** Smoke включает: иконки видны в spawner-табе (Player ★ + 12 врагов), object-табе (8 объектов), hex-табе (теперь 72px). Если ассет не находится → буква-монограмма (для тестов: переименуй временно `assets/sprites/enemies/angel.png`, кнопка должна показать "A").

---

## F-060-IMPL-4 — Detached-панель не ресайзится: best-guess фикс без репро

**Что нашёл.** Андрей сообщил, что panels detached от LayersPanel не ресайзятся (только основная панель ресайзится). Не могу воспроизвести без Godot — анализ по коду показал что инфраструктура (PanelResizeHandler, ResizeFrame, _setup_handlers) работает идентично для main и floating.

**Гипотеза.** `_spawn_detached` создавал floating-панель с `min_panel_size = Vector2(180, 120)` и `.tscn`-default size `300×200`. С Φ-4 палитрами по 72×72 (3 ряда × 4 строки = ~216×288 + chrome) контент тела может переполнить bounds → handles ResizeFrame на правом/нижнем краях перекрываются OS-овским hit-test'ом BodyPanel (PanelContainer mouse_filter STOP). User видит handles только если кликает в самый край.

**Что сделал.** В `panel_tab_bar.gd._spawn_detached`:
- `min_panel_size`: 180×120 → **280×360**.
- После `host.add_child(detached)` (где запускается persistence load_layout, тоже могущий установить размер ниже нового min) принудительно `size = max(size, min_panel_size)`.

**Почему гипотеза слабая.** Main панель (LayersPanel) тоже использует body+content overlap по идентичной схеме, и user пишет что она ресайзится. Если бы причина была в overlap'е, оба сломаны были бы.

**Альтернативные гипотезы (если фикс не помог).**
1. `_resize_handler` не создаётся для detached'a (race в _ready ordering — host.add_child запускает _ready СРАЗУ, может быть до того как BasePanel._setup_handlers завершит).
2. Persistence load_layout перетирает size после resize пользователя — тогда нужно проверить debounce в panel_persistence.
3. ResizeFrame.visible = false из-за collapse-handler interaction.

**Action для Андрея.** Smoke — детач Spawners → попробовать ресайз за все 8 краёв/углов. Если не работает — repro: дёрнуть `print(detached._resize_handler != null)` в `_spawn_detached` после `host.add_child`. Если null — гипотеза 1. Если true — лезть в ResizeFrame.visible или persistence.

---
