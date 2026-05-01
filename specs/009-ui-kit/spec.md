# 009-ui-kit — spec

**Owner:** Andrey (claim-on-PR)
**Status:** Draft, **blocked-after-Phase-3** on 007 (skill system) and 008 (enemy AI). Phases 0–3 can begin immediately; Phase 4 waits.

## Цель

Привести весь UI игры к единой системе: общая палитра, общая шкала размеров, общий font-набор, и набор переиспользуемых Control-нод, покрывающих все экраны и хадовые виджеты, нужные для arena + meta-loop.

Источник правды — design-bundle в [`design/`](./design/) (24 HTML-мокапа со state-таблицами и Godot-маппингом для каждого компонента, плюс канонический [`design/tokens.css`](./design/tokens.css)).

## Что мы получаем

1. **Один autoload `UiTheme`** с константами цветов и размеров. Любой UI-скрипт, который сейчас держит `Color(0.10, 0.10, 0.10, 0.85)` инлайном, переписывается на `UiTheme.BG_PANEL`. Hot-reload через F5 (как `GameSpeed.cfg`).
2. **Refit существующих виджетов** под палитру и spacing scale: HP bar, slot bar, dialogue panel, actor inspector, intent arrow, hex cursor, telegraph hex, move-range overlay. Behaviour не трогаем — меняем только `Color()`, font sizes, padding, состояния (`hover`, `active`, `disabled`).
3. **Новые виджеты** для арены и meta-loop: top HUD, player status panel, status icon strip, cast-range overlay, floating damage numbers, hex inspector subpanel, generic tooltip, choice button row, главное меню, пауза, settings, confirm modal, toast, combat log, keybind overlay, loading cover, portal/wave transition, run summary.
4. **Спека (этот файл) фиксирует**, какие компоненты блокированы на 007 и 008 и что мы делаем сейчас vs позже.

## Соответствие пилларсам

- **§1.5.1 Полная информация.** Каждый компонент в кит-каталоге обслуживает информационную видимость: HP-бар + preview-strip, telegraph-hex с числами, status icon strip, cast-range overlay, intent arrow, skill tooltip с разбивкой `base → final + modifier breakdown`. Кит — это инфраструктура для пиллара 1.
- **§1.5.2 Симметрия.** Один и тот же `HpBar` для player и enemy. Один и тот же `ActorInspector` (read-only режим для боевой сцены, edit-режим для Godmode). Telegraph-механизм одинаков для player skill preview и для enemy intent.

## Состав работы — что в скоупе, что нет

### В скоупе (24 компонента из каталога)

Группы по экранам, в порядке файла каталога ([`design/components/`](./design/components/)):

**Combat HUD** — C1 top HUD, C2 skill slot bar, C3 player status panel, C4 HP bar, C5 status icon strip, C6 telegraph hex, C7 move-range overlay, C8 cast-range overlay, C9 intent arrow, C10 hex cursor (4 modes), C11 floating damage/heal numbers.

**Inspectors** — C12 actor inspector (Play vs Godmode режимы), C13 hex inspector subpanel, C14 skill tooltip, C15 generic tooltip.

**Dialogue** — C16 NPC dialogue panel, C17 internal voice panel, C18 choice button row.

**Meta-loop** — C19 modifier-pick screen, C20 portal/wave transition, C21 run summary, C22 main menu, C23 pause menu, C24 settings, C25 generic confirm modal.

**System** — C26 toast/notification, C27 combat log, C28 keybind overlay, C29 loading cover.

### Не в скоупе

- **Asset production.** Иконки статусов, портреты, спрайты, фоны меню — не задача спеки. Везде placeholder Unicode-глиф или `[ART SLOT]` лейбл, артовое наполнение — отдельным проходом Кати.
- **VFX, particles, screenshake.** Слот зарезервирован в C20 (tape-rewind), C11 (floats) — но реализация частиц / шейдеров — отдельная фича после кита.
- **Anim-полировка.** Tween на cooldown overlay, slot scale-pop, modal slide-in — minimal viable: `transition` на opacity/color через `Tween`. Полировка motion-design — после кита.
- **Localization / i18n.** Английский (плюс русский на дев-надписях, как в существующем коде) единственные языки.
- **Save/load UI.** Между ранами не сейвимся в джеме. C22 «Continue» кнопка — серая, disabled.
- **Rebind UI.** В C24 settings — keybind list только на показ, без редактирования.
- **Дев-инструменты C30 (spawn picker), C31 (tile-effect picker).** Они существуют в Godmode, но визуально не приведены к киту в этой фиче — подтянутся после Phase 3 при ревизии Godmode-сцены.
- **Контент инспектора, зависящий от 007.** Skill tooltip с разбивкой modifier-стека (`10 → 22 (+5, ×1.5)`) — формат данных приедет из 007.
- **AI intent display, зависящий от 008.** Стрелка движения и target-coord уже есть; полная семантика `cast_intent.skill_id + target_id + target_coord + tag` — приедет из 008.
- **Реализация tape-rewind анимации.** В C20 — только лейбл `[TAPE REWIND VFX HERE]`. Реализация — отдельный VFX-таск после кита.

## Зависимости

Жёсткое разделение: **что может стартовать прямо сейчас vs что ждёт 007/008**.

### Phase 0–3 — НЕ блокированы

Theme-инфраструктура + refit + новые виджеты, не требующие новых типов из 007/008.

### Phase 4 — БЛОКИРОВАНА на 007 (skill system)

| Компонент | Что блокирует |
|---|---|
| C2 — детальная отрисовка cooldown overlay | `Skill.cooldown` поле + текущее значение тика. До 007 в слоте показываем только `id` ability и castable-флаг. |
| C14 — skill tooltip rich-формат | Нужны `Skill {abilities[]}`, `Ability {target, area, effects[], modifiers[]}`, `Effect {type, duration, …}`, `ParameterModifier {field, op, value}`. До 007 рендерится primitive-tooltip только из `Ability.id`. |
| C19 — modifier-pick screen | Нужны `ParameterModifier` resources + способ их прицепить к skill при absorb. До 007 — экран не имеет смысла, его реализация откладывается. |

### Phase 4 — БЛОКИРОВАНА на 008 (enemy AI)

| Компонент | Что блокирует |
|---|---|
| C9 — intent arrow с типом действия | Нужен `cast_intent: CastIntent {skill_id, target_id, target_coord}` и его tag (`damage`/`heal`/`control`/...). До 008 показываем только move-arrow + базовый attack-target. |
| C12 (enemy mode) — строка «planned intent» | Тот же `cast_intent`. До 008 строка показывает текущий примитив (`attack at (3,4)`). |
| C6 (enemy telegraph для не-damage) — цвет hex по тегу эффекта | Нужны теги на Skill/Ability (Q-AI-1 в 008). До 008 telegraph красный только. |

### Не блокирует, но стоит координировать

- **Ownership C2 cooldown.** Финальный формат overlay (числовой / radial sweep / fill-bar) — определяется в Phase 4, после того как Egor зафиксирует `Skill.cooldown` API. Сейчас в дизайне рекомендован числовой overlay (cheapest).
- **Ownership C14 tooltip.** Координация с Sergey, если он берёт modifier-engine: формат строки `base → final + breakdown` пишется одним местом (`SkillFormatter` helper в `scripts/presentation/`), чтобы и tooltip, и inspector, и pick-screen использовали одну функцию.

## Acceptance criteria

### AC-T (theme infrastructure)

- **AC-T1**: Существует autoload `UiTheme` (`scripts/presentation/ui_theme.gd`). Содержит ВСЕ цветовые константы из [`design/tokens.css`](./design/tokens.css) с теми же именами в SCREAMING_SNAKE_CASE (`BG_PANEL`, `BORDER`, `SEM_DAMAGE`, `TEAM_PLAYER`, `HP_FILL`, ...).
- **AC-T2**: `UiTheme` содержит spacing-константы `SP_1=4, SP_2=8, SP_3=12, SP_4=16, SP_5=24, SP_6=32` (int, в пикселях).
- **AC-T3**: `UiTheme` содержит font-size константы `FS_DISPLAY=32, FS_HEADER=18, FS_BODY=14, FS_SMALL=11, FS_NUM_LARGE=24, FS_NUM_SMALL=12`.
- **AC-T4**: `UiTheme` поддерживает hot-reload по F5: правка значений в `config/ui_theme.cfg` (или захардкодена напрямую в скрипте — оба варианта валидны, plan.md решит) — F5 в Godmode сцене перезатягивает значения и редроит видимые виджеты. EventBus сигнал `ui_theme_reloaded`.
- **AC-T5**: Никакой UI-скрипт в `scripts/presentation/` НЕ содержит `Color(...)` инлайн — всё через `UiTheme.X`. Линтер/grep-проверка в плане. Исключения: дев-инструменты в `scenes/dev/`, цвета арены/тайлов (не UI).

### AC-R (refit existing widgets)

- **AC-R1**: `HealthBar` (`scripts/presentation/health_bar.gd`) использует `UiTheme.HP_BG`, `UiTheme.HP_FILL` (с переключением на `HP_LOW` при ≤30% и `HP_CRIT` при ≤15% — новое поведение из мокапа), `UiTheme.HP_PREVIEW`, и outline по `UiTheme.TEAM_*`. Размеры WIDTH/HEIGHT не меняются (30×4). Текст лейбла по `UiTheme.FS_NUM_SMALL` (10 in mockup → use 10 directly как existing). Все стейты из `c4-hp-bar.html` визуально воспроизведены.
- **AC-R2**: `SlotBar` (`scripts/presentation/slot_bar.gd`) использует `UiTheme.BG_PANEL`/`BG_PANEL_2` для фона слота, `UiTheme.FOCUS` для активной подсветки, `UiTheme.DISABLED` для disabled. Hover-стейт добавляется (сейчас отсутствует). Размер 72×72 не меняется. Стейт «cooling down» — placeholder в Phase 1, полная отрисовка — Phase 4.
- **AC-R3**: `ActorInspector` (`scripts/presentation/godmode/actor_inspector.gd`) — структура VBox/HBox не ломается, перекраска через UiTheme. SpinBox-ряды остаются для Godmode. Добавляется заголовочная плашка с team-badge (новое из мокапа). «Planned intent» строка — placeholder в Phase 1, полное содержимое — Phase 4.
- **AC-R4**: `DialoguePanel` (`scripts/presentation/dialogue_panel.gd`) — стайлбокс из мокапа (`bg_color = UiTheme.BG_PANEL`, без текущего инлайн `Color(0.08, 0.08, 0.12, 0.92)`). Typewriter и state-machine не трогаем.
- **AC-R5**: `IntentArrow` (`scripts/presentation/intent_arrow.gd`) — цвет из `UiTheme.SEM_DAMAGE` (default move-toward-target) или `UiTheme.SEM_MOVE` (мирное движение). Тег эффекта, если есть, — placeholder в Phase 1.
- **AC-R6**: `HexCursor` (`scripts/presentation/hex_cursor.gd`) — 4 цветовых стейта по `cast_mode` (idle / casting / inspect / disabled — соответственно `UiTheme.TEXT_DIM`, `UiTheme.SEM_*` по типу скилла, `UiTheme.FOCUS`, `UiTheme.DISABLED`). Inspect-режим (LMB на врага) рисуется как 6 hex-corner brackets — см. `c10-c11-cursor-fct.html`.
- **AC-R7**: `TelegraphHex` (`scripts/presentation/telegraph_hex.gd`) — цвет hex и числа по `UiTheme.SEM_DAMAGE` (как сейчас) + добавляется поддержка передачи semantic-тега извне (для будущих heal-интентов). Multi-source aggregation — сумма (как сейчас + breakdown в hover Phase 4 после 008).
- **AC-R8**: Существующие move-range overlay (`scripts/presentation/godmode/move_range_overlay.gd`) — цвет по `UiTheme.TEAM_*` (cyan для союзников, red для врагов).

### AC-N (new widgets, Phase 2-3)

- **AC-N1**: Каждый компонент C1, C3, C5, C8, C10, C11, C13, C15, C18, C20, C21, C22, C23, C24, C25, C26, C27, C28, C29 реализован как `.tscn` сцена + `.gd` скрипт в `scenes/ui/` + `scripts/presentation/`. Имена файлов snake_case по id компонента (`top_hud_bar.tscn`, `player_status_panel.tscn`, ...).
- **AC-N2**: Каждый новый компонент визуально воспроизводит ВСЕ состояния из соответствующего `.html` файла (idle, hover, active, disabled, empty/no-data, error/loading — те, что применимы). Visual check — ручной от Andrey против side-by-side `.html` мокапа.
- **AC-N3**: Каждый новый компонент использует только `UiTheme.X` для цветов и spacing. Никаких `Color(...)` инлайн.
- **AC-N4**: C17 (internal voice) — реализуется как **отдельный** компонент от C16. Решение зафиксировано: дизайн-мокап показал обе альтернативы, narrative-вес и визуальный contrast (italic+narrower+top-anchor) оправдывают отдельную сцену. Запасной вариант (mode-switch на C16) откинут.

### AC-I (integration)

- **AC-I1**: На `scenes/dev/godmode.tscn` добавлены/переподключены: C1 (top HUD), C3 (player status panel), C5 (status icon strip — пустой пока, без статус-системы), C8 (cast-range overlay), C26 (toast layer). Существующий HUD (TurnLabel, HelpLabel) демонтируется или переезжает в C1.
- **AC-I2**: Главное меню (C22) — новая сцена `scenes/main_menu.tscn`, входит в `project.godot main_scene` как фактическая точка входа (текущий `scenes/main.tscn` — заглушка-stub под bootstrap, теперь заменяется).
- **AC-I3**: Pause menu (C23) — открывается по ESC в любой arena/godmode сцене (overrides текущее `ESC = deselect`, см. UX state machine: ESC сейчас сбрасывает selection/cast_mode → дополнительная семантика «второй ESC открывает pause»).
- **AC-I4**: EventBus получает сигналы `ui_toast_requested(text, duration_sec, level)` и `ui_modal_opened(id)`/`ui_modal_closed(id)` для координации tooltip suppression и pause-on-modal.

### AC-X (edge cases & UX)

- **AC-X1**: Pause menu (C23) и любой modal (C19, C25, C28) ставит игру на паузу через `get_tree().paused = true`. Узлы UI (CanvasLayer'ы) ставятся в `process_mode = PROCESS_MODE_ALWAYS` чтобы продолжали реагировать.
- **AC-X2**: Tooltip suppression: пока открыт modal или dialogue panel — `Control.tooltip_text` подавляется (через `mouse_filter = MOUSE_FILTER_IGNORE` на overlay'ях или централизованно через `UiTheme.set_tooltips_enabled(false)`).
- **AC-X3**: Focus stealing trap (CLAUDE.md §traps + handoff §7): SpinBox в C12 продолжает release_focus на game-key (Q/W/E/R/SPACE/F-keys) как сейчас. Все новые компоненты с `LineEdit`/`SpinBox` (например в C24 settings) — то же поведение, обёрнуто в helper `UiTheme.attach_focus_release(line_edit, [game_keys])`.
- **AC-X4**: Toast (C26) стэкуется максимум 3 видимых одновременно — четвёртый ждёт. Auto-dismiss 2.5s default, override через signal payload.
- **AC-X5**: Combat log (C27) — кольцевой буфер 50 строк. По `L` toggle. Disabled by default в проде, enabled в Godmode.

### Acceptance scenarios (тесты — ручной плейтест после Phase 3)

1. **Theme hot-reload.** Запускаем Godmode, открываем `config/ui_theme.cfg` (или прямую правку константы в `ui_theme.gd`), меняем `BG_PANEL` на `Color(0.5, 0, 0)`, F5 в окне Godot — все панели мгновенно становятся бордовыми. Перезапуск не требуется.
2. **Pillar 2 — symmetry HP bar.** Игрок и manekin рисуются с одной и той же `HpBar`-сценой; смена `team` меняет outline, остальное идентично. Подтверждено визуально.
3. **Pause через ESC из боя.** В Godmode при `cast_mode=idle, selection=player` нажимаем ESC → открывается C23 pause menu, игра на паузе. Resume → продолжается.
4. **Tooltip suppress в модалке.** Открываем pause menu (C23), наводим на slot bar — тултип НЕ появляется. Закрываем модалку — тултип возвращается через 400ms hover.
5. **Toast стэк.** Эмитим 5 toast'ов подряд через EventBus — видим первые 3, четвёртый и пятый появляются по мере дисмисса.
6. **Combat log toggle.** В Godmode `L` → видна combat-log панель в bottom-right; ещё `L` → скрыта.
7. **Refit — slot bar hover.** Наводим мышь на пустой слот — лёгкая подсветка (новое); на занятый кастабельный — bright hover; на disabled — без реакции.
8. **Inspector godmode toggle.** В Godmode-сцене инспектор показывает SpinBox'ы; в (будущей) production-сцене — те же поля как `Label` (read-only). Один компонент, два режима через export-флаг `dev_mode: bool`.

## Связь с предыдущими спеками

- **006-actors-info-window** — реализовала `ActorInspector` (текущий C12). 009 рефит-ит его палитру и добавляет team-badge + tooltip-suppress координацию. Не ломает 006 acceptance.
- **005-camera-and-arena** — добавила Godmode camera. Не пересекается, но C1 (top HUD) и C3 (player status) встают над её viewport, нужно проверить anchor-presets.
- **004-godmode-base** — определила Godmode-контроллер. C1, C3, C5, C8 цепляются к `GodmodeController` через node-paths, аналогично уже подключённым `SlotBar`/`ActorInspector`.
- **003-dialogue-manager** — `DialoguePanel` рефит-ится в Phase 1 (AC-R4). Engine не трогается.
- **002-hex-grid** — `HexGrid` API не трогаем; `MoveRangeOverlay`, `TelegraphHex`, `HexCursor` — refit (AC-R6, AC-R7, AC-R8).

## Открытые вопросы (закрыть до /plan)

- **Q-UI-1 (Theme storage).** Где хранить значения констант `UiTheme`?
  - (a) Захардкожены в `ui_theme.gd` — простейшее, hot-reload через F5 даёт `EditorPlugin` редактирование, но не runtime-edit.
  - (b) `config/ui_theme.cfg` ConfigFile — параллель `game_speed.cfg`. Runtime-editable, но дублирует файлы.
  - (c) Godot `Theme` resource (`.tres`) — нативный путь, theme inheritance работает, но binding к колонкам палитры менее очевиден чем (a)/(b).
  - **Рекомендация (моя):** (a) для джема. Палитра не балансится в плейтесте; F5-перезатяг кода через `EditorScript` или просто перезапуск сцены. Если в плейтесте окажется, что цвета крутят активно — миграция на (b) тривиальна.

- **Q-UI-2 (Compass viz в C21 run summary).** Радар/spider chart (геометрически сложный custom `_draw()`) или горизонтальные стэк-бары (просто, расширяемо)? В мокапе обе альтернативы.
  - **Рекомендация:** stacked bars. Радар требует больше дев-времени и хуже масштабируется при добавлении новой оси (раса). Stacked bars ≤ 1 час работы.

- **Q-UI-3 (Pause при модалке — granularity).** Все ли модалки ставят `get_tree().paused = true`?
  - (a) Все (включая C19 modifier pick — он сам по себе пауза-моментa).
  - (b) Только pause/settings/confirm; toast/dialogue panel НЕ ставят паузу (но они и не блокируют ввод критично).
  - **Рекомендация:** (b). Pause только когда expect "freeze the world" семантика. Dialogue и toast живут поверх работающей игры (диалоги в арене теоретически могут произойти под телеграфом следующего хода — мы хотим их прочитать без зависания таймера, если он будет).

- **Q-UI-4 (Existing scenes/main.tscn → main_menu.tscn миграция).** Текущий `main.tscn` — пустая сцена-заглушка из 001-bootstrap, эмитит `EventBus.run_started`. Заменить на полноценный main menu или оставить рядом?
  - (a) Заменить полностью, эмит `run_started` переезжает в "Start Run" кнопку C22.
  - (b) Оставить main.tscn как scene-loader, main_menu.tscn — отдельная сцена которую он мгновенно загружает.
  - **Рекомендация:** (a). Лишний indirection не нужен, main.tscn никем больше не используется.

- **Q-UI-5 (C17 internal voice — anchor).** Сверху или сбоку?
  - (a) Сверху-центру — visually distinct от C16 (внизу).
  - (b) Слева-сверху — оставляет центр под арену.
  - **Рекомендация:** (a). Top-center даёт чёткую делимитацию "in-head vs out-of-head"; нарративный вес internal voice оправдывает захват внимания.

## Заметки реализации (для будущей plan.md)

- **Не autoload Theme resource целиком.** `UiTheme` — autoload с константами и хелперами (`make_panel_stylebox()`, `apply_label_style(label, kind)`). Не пытаться использовать Godot `Theme` для всего — он плохо ложится на jam-цикл (`.tres` файлы конфликтуют в merge, hot-reload неочевиден).
- **`StyleBoxFlat` через хелперы.** Для каждого паттерна (panel, modal, button, slot) — функция `UiTheme.make_*_stylebox()` возвращает свежий `StyleBoxFlat`. Не разделять stylebox между нодами (их `bg_color` мутабелен → утечка состояния).
- **Custom `_draw()` vs ProgressBar.** HealthBar уже на `_draw()` — оставляем. Cooldown overlay в C2 — также `_draw()` (radial — арки, числовой — Label). Не пытаться использовать `TextureProgressBar` — не покрывает все 3 варианта одной нодой.
- **Component file naming.** `scenes/ui/{component_id}.tscn` + `scripts/presentation/{component_id}.gd`. Например `scenes/ui/top_hud_bar.tscn` → `scripts/presentation/top_hud_bar.gd`. Никакого `scenes/hud/` или `scripts/ui/` — следуем существующему layout (см. CLAUDE.md §file structure).
- **Регрессии.** После Phase 1 refit'а — прогоняем acceptance scenarios из 006 (info window) и 003 (dialogue) чтобы убедиться, что behaviour не сломался при перекраске.
- **Migration файлов.** Удаляемых файлов нет — только правки + добавления. Текущие компоненты (HealthBar, SlotBar, ActorInspector, DialoguePanel, ...) сохраняют пути и публичный API.

## Контракт владения (claim-on-PR)

- **Andrey** клеймит UiTheme infra (Phase 0), refit (Phase 1), HUD/inspector intgration (часть Phase 2), modals/menus (Phase 3).
- **Координация перед merge:** Phase 4 cooldown overlay (C2) — с Egor (007 owner). Phase 4 skill tooltip (C14) и modifier-pick (C19) — с Egor + Sergey. Phase 4 intent display (C9, C12 enemy mode) — с Sergey (008 owner).
- **Stasyan** не задействован (контент-балансом UI не занимается, кроме тюнинга цветовых констант если визуально не зайдёт — это редкий кейс).
- **Никита** даёт narrative-копирайт для C20 (flavor text per wave) и C17 (internal voice lines). Без этого Phase 3 шипает с placeholder'ами.
- **Катя** — ассеты для портретов (C16/C17), иконок статусов (C5), illustrations для main menu (C22) — приходят отдельным проходом, до них всё работает на placeholder Unicode-глифах.
