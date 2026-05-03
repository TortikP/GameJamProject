# 049-ux-rehaul — spec

**Owner:** Egor (hex arena, battle UX, telegraphs).
**Coordination:**
- **Andrey** (029-feedback-polish predecessor) — этот спек закрывает большую часть ОТКРЫТЫХ пунктов 029 §req-6 / §Pillar 1+3 (mob-hover тултип, AoE telegraph иконки, valid-target highlight). 029 spec.md можно частично пометить как «закрыто 049» при следующей правке.
- **Nikita** (text content) — описания скиллов уже написаны в `<skill_id>_tooltip` ключах локализации. Никакой работы не требуется; этот спек просто перестаёт игнорировать поле.
- **Stasyan** (balance, content) — нет точек прерывания. Если нужно дописать недостающие `_tooltip` ключи — это уже его обычная работа над content JSON, не блокирует ветку.

**Status:** Draft.

## Цель (одно предложение)

Перейти от click-to-inspect к ITB-style **always-on hover-driven preview**: игрок видит, что произойдёт, *до* клика; источник истины описаний — авторская human-readable строка из локализации (`<skill_id>_tooltip`), а не реконструкция из структурных классов.

## Pillar mapping

- **Pillar 1 (full information visibility)** — hex-tooltip аккумулирует все intents на гексе; valid-target highlight показывает, куда вообще можно кликнуть; иконка скилла на телеграфе говорит «что прилетит», а не только «прилетит дамаг».
- **Pillar 2 (player–monster symmetry)** — enemy move отображается тем же polyline-стилем, что player hover-path (только цвет другой). Один визуальный язык для движения.

## Out of scope

- Skill icon assets — fallback на букву; реальные `assets/icons/skills/*.png` подключаются автоматически по существующему пути в JSON, когда Катя пришлёт. Не блокирует мерж.
- Перевод дебажных `Localization.tf("ui_effect_generic", …)` строк в живой текст — уже не нужны, они отрезаются через `format_skill_human` fallback (старый формат остаётся только для совсем нелокализованных скиллов в dev).
- Балансная переработка urgency cues (color/sound на «вот тебя сейчас убьют»).
- Editor-сцена UX — этот спек только про battle UX (godmode + production levels через ту же сцену).
- ActorInspector в режиме редактирования статов SpinBox'ами — фича теряется. Если кому-то нужен — отдельная dev-only панель за F-toggle, **отдельным спеком**.

## Acceptance criteria

### AC-1 — Описания скиллов человеческие
- В `PlayerStatusPanel.SpellSection` при выборе слота в `SpellDesc` отображается `Localization.t(skill.tooltip)`, а не `"Target: ActorTarget\nArea: ZoneCircleArea\nDamage: 25"`.
- Если `skill.tooltip` пуст ИЛИ ключ отсутствует в локализации → fallback на текущий `format_skill` (debug-вид сохраняется только в этом краевом случае).
- Cooldown-индикатор (`(CD 2/3)`) добавляется к header-строке, как сейчас.

### AC-2 — Hex-tooltip у курсора
- Наведение на гекс → если на гексе есть **хотя бы одна** угрожающая активность (player skill preview ИЛИ ≥1 enemy intent с `target_coord==coord` ИЛИ `coord ∈ ability.area.affected`) — показывается `HexTooltip`.
- Положение: `mouse_global + Vector2(SP_2, -tooltip.size.y - SP_2)` (правее курсора, выше курсора), clamp к viewport rect (см. `tooltip_panel._place_near` для clamp-логики).
- Содержимое — таблица из 3 колонок, по строке на каждый предполагаемый эффект:
  | Actor name | Skill name + icon | Consequences |
  |---|---|---|
  | `player` | 🔥 Curse | Slowed (3 turns) |
  | `bee_2` | 🗡 Sting | -8 HP |
- Header пустого гекса (нет активности) → tooltip скрывается, не показывается «Empty (forest)».
- Tooltip не «дрожит» при движении мыши внутри одного гекса — re-render только при смене hovered coord.

### AC-3 — ЛКМ-select-actor выпилен
- Клик ЛКМ по живому актёру **без** активного слота — ничего не делает (ни selection, ни inspector). Без активного слота ЛКМ только инспектирует пустой гекс — тоже выпиливается, см. AC-4.
- Никаких следов: `GodmodeController.{select, inspect_hex, bind_hex_at, deselect_to_player, _selected, _on_inspector_speed_changed, _on_actor_died_for_selection}` удалены. `godmode_input.gd` теряет ветку `select(target_actor)` / `inspect_hex(coord)`.
- Esc-priority chain в `godmode_input` сжимается с 3 уровней до 2 (cast-FSM cancel, pause-menu) — selection-уровень больше не существует.

### AC-4 — EnemyDetailsPanel вместо ActorInspector
- Top-right HUD панель (`scenes/ui/enemy_details_panel.tscn`), горизонтальный layout: portrait (если есть) • name + team badge • HP bar • status icons • abilities row.
- Видна **только** при hover мышью над живым enemy на гриде. `mouse_exit` / cursor над пустым гексом / cursor над player → панель скрыта.
- Никаких editable SpinBox'ов. Read-only labels.
- Старый `ActorInspector` + `actor_inspector.tscn` + `HexInspectorSubpanel` (мёртвый parallel) удалены.

### AC-5 — Telegraph hex с иконкой
- На каждом primary telegraph hex (где `outline_only==false`) рисуется иконка скилла:
  - Если `skill.icon` resolveится через `SkillIconResolver.resolve(skill)` → `Texture2D` отрисован 32×32 в центре hex.
  - Иначе → первая буква `Localization.t(skill.name)` крупным шрифтом (`UiTheme.FS_NUM_LARGE`), та же позиция.
- Damage-число продолжает отображаться, но смещается ниже иконки (был center → теперь bottom-center hex).
- Outline-only вторичные AoE-хексы остаются без иконки — конкуренция за внимание с primary hex недопустима.

### AC-6 — Valid-target highlight в CastRangeOverlay
- При активном слоте / cast FSM шаге ability `range` хексов окрашиваются в одну из двух категорий:
  - **valid** — `ability.target.resolve(caster, per_hex_ctx) != null` → `SEM_DEBUFF` outline (текущий вид).
  - **invalid** — иначе → `Color(GREY_50, 0.30)` outline (тоньше или то же, но dim).
- LMB на invalid hex — no-op (как сейчас); просто визуально понятно почему.
- AoE-zone preview под курсором (`show_zone_preview`) показывается **только** если cursor на valid hex. На invalid — preview прячется.

### AC-7 — Enemy move arrows красные, hex-path стилем
- Каждый enemy с `move_intent_coord != (-1,-1)` рисует polyline через центры hex'ов на пути от его текущей позиции до `move_intent_coord` (тот же путь, что моб реально пройдёт через `grid.find_path_around` с occupied-list, как у player'а в `move_range_overlay._draw_hover_path`).
- Цвет: `UiTheme.SEM_DAMAGE` (red), alpha 0.85, шторм 4px со shadow.
- Старый `IntentArrow` (straight line node) удалён.

### AC-8 — PSP показывает hover-описание скилла
- Hover на slot button (без активного выбора) → `PlayerStatusPanel.SpellSection` показывает `format_skill_human(slot.skill)`. Hover off → возвращается к active skill description (или пустой, если active нет).
- Hover описание имеет приоритет над active.
- `slot_bar.gd` эмитит `slot_hovered(int)` / `slot_unhovered(int)`. Existing `slot_activated` не трогаем.

### AC-9 — Чистка legacy
- `tile_objects_smoke_controller.gd` (`scripts/presentation/dev/`) — лог-spam через `GameLogger.info("018-smoke", …)` × 20 заглушается за F-toggle (`KEY_F12` или `dev_smoke_logging`). Default off. Контроллер сам остаётся — он instantiated в dev-сцене для smoke-теста.
- `HexInspectorSubpanel` удалён (мёртвый parallel).
- `IntentArrow` удалён (заменён на EnemyMovePath).
- Никаких `print(…)` / `print_debug(…)` в новом коде; весь логгинг через `GameLogger.{info,warn}` с категорией `"049"`.

### AC-10 — UiTheme единый стиль
- Все новые тултипы / панели используют `UiTheme.make_panel_stylebox()` (или `make_panel_stylebox(true)` для floating tooltip).
- Все label'ы — через `UiTheme.apply_label_kind(lbl, kind)`. Никаких `add_theme_color_override` напрямую вне UiTheme/CLAUDE.md visibility-doctrine исключений.
- Иконка-буква на telegraph — `draw_string_outline` + `draw_string` с `WORLD_TEXT_OUTLINE_*` (visibility doctrine — это in-world text).

## Open questions

- **OQ-1:** иконки скиллов под рукой нет (`assets/icons/` пустая) → буквенный fallback единственный путь до Кати. **Resolved (Egor):** ОК, добавим потом, fallback ОК.
- **OQ-2:** EnemyDetailsPanel position. **Resolved (Egor):** top-right.
- **OQ-3:** HexTooltip на пустом гексе. **Resolved (Egor):** не показывать, less noise.

## Размер

Средний. ~12–15 файлов, presentation-only. Без правок core. Smoke-набор в Godmode (F1 manekin spawn + sample level) полностью покрывает acceptance.

## Зависимости

- 029-feedback-polish (Andrey, merged) — базовая инфраструктура (TelegraphHex semantic_color, hover_dispatcher, paint_preview style for cast range).
- 047-skill-fx-system (Egor, merged) — FxDirector cycles на cast intent; не трогаем.
- 048-corpse-absorption (Egor, in progress on `egor/048-corpse-absorption`) — параллельно. Нет пересечений по файлам.

## Риски

- **R1:** многие `<skill_id>_tooltip` ключи могут оказаться неавторскими (отсутствует или копия `_desc`). Фолбэк на структурный formatter работает, но визуально неровно. Mitigation: грепнуть `_sources.json`, если ≥30% missing — заэскалировать Никите перед мержем.
- **R2:** EnemyDetailsPanel занимает место `ScoreCorner`. Сдвинуть один из них; логичнее — EnemyDetailsPanel в самом верхнем правом, ScoreCorner ниже. Без перекрытия.
- **R3:** HexTooltip + EnemyDetailsPanel могут одновременно показываться при hover'е на enemy (на хексе с угрозой). По дизайну — нормально (разная информация: hex = «что сюда прилетит», enemy = «кто такой моб»). Cursor-anchored vs corner-anchored — не пересекаются геометрически.
- **R4:** удаление `select()` ломает любое внешнее, что подписано на нынешнюю selection-семантику. Аудит: внутри godmode_input + godmode_setup + godmode_controller — единственные callers. Никто из других модулей в `_ctrl.select` не лезет (см. grep в plan.md §Audit).
