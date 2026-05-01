# 009-ui-kit — tasks

**Owner:** Andrey · **Spec:** [`spec.md`](./spec.md) · **Plan:** [`plan.md`](./plan.md)

Status legend: `[ ]` not started · `[x]` done · `[~]` partial (note what's left) · `[!]` blocked.

Phases gate execution. Phase N+1 не стартует, пока в Phase N остались `[ ]` или `[~]`. Внутри фазы — `[P]` mark = можно делать в параллель с другими `[P]` той же фазы.

## Phase 0 — Theme infrastructure (UNBLOCKED)

Foundation. Без этого ничего из остального не имеет смысла.

- [x] **T001** [P1] Создать `scripts/presentation/ui_theme.gd` со всеми константами из plan.md §"UiTheme autoload" (цвета, spacing, font sizes, helpers)
- [x] **T002** [P1] Зарегистрировать UiTheme как autoload в `project.godot` (порядок: после Logger, до AudioDirector) (depends T001)
- [x] **T003** [P1] [P] Добавить EventBus сигналы из plan.md §"EventBus extensions": `ui_theme_reloaded`, `ui_toast_requested`, `ui_modal_opened`, `ui_modal_closed`, `main_menu_entered`, `run_started_requested`, `run_summary_shown`, `pause_toggled` (правка `scripts/infrastructure/event_bus.gd`)
- [x] **T004** [P2] Добавить `scripts/presentation/ui_signal_helpers.gd` со static-helper'ами: `attach_focus_release(line_edit, game_keys)`, `setup_modal_pause(canvas_layer, modal_id)` (depends T003)
- [x] **T005** [P2] Smoke-тест в Godmode: добавить временный Label на сцену с цветом `UiTheme.SEM_DAMAGE` — убедиться, что autoload видится. Удалить после проверки. (depends T002) — *static grep verification, runtime check on first launch*
- [x] **T006** [P3] Документировать `UiTheme` в `CLAUDE.md` секции "Architecture" (одна строка: «UI цвета — только через UiTheme.X, не Color() inline»)

**Definition of done Phase 0:** UiTheme автозагружается, EventBus имеет новые сигналы, smoke-тест проходит.

---

## Phase 1 — Refit existing widgets (UNBLOCKED, after Phase 0)

Перекраска существующих виджетов под палитру. Behaviour не трогается. Каждый рефит — отдельный коммит для лёгкого revert.

- [ ] **T010** [P1] Refit `scripts/presentation/health_bar.gd`: убрать inline `Color(...)`, использовать `UiTheme.HP_*`, `UiTheme.team_color()`, `UiTheme.hp_color_for(ratio)`. Подписаться на `EventBus.ui_theme_reloaded` → `queue_redraw()`. AC-R1.
- [ ] **T011** [P1] Refit `scripts/presentation/slot_bar.gd`: палитра через UiTheme, добавить hover-стейт (mouse_entered/exited на каждой кнопке). AC-R2.
- [ ] **T012** [P1] Refit `scripts/presentation/godmode/actor_inspector.gd`: палитра через UiTheme, добавить team-badge node, добавить `@export var dev_mode: bool = true` с swap visibility SpinBox ↔ Label. AC-R3.
- [ ] **T013** [P1] Refit `scripts/presentation/dialogue_panel.gd` + `scenes/ui/dialogue_panel.tscn`: убрать inline SubResource StyleBox, в `_ready()` повесить `UiTheme.make_panel_stylebox()`. AC-R4.
- [ ] **T014** [P1] Refit `scripts/presentation/intent_arrow.gd`: цвет через `UiTheme.SEM_*`. AC-R5.
- [ ] **T015** [P2] Refit `scripts/presentation/hex_cursor.gd`: 4 cast_mode'а с разными цветами + новый inspect-mode рисующий 6 hex-corner brackets (геометрия из `design/components/c10-c11-cursor-fct.html`). AC-R6.
- [ ] **T016** [P2] Refit `scripts/presentation/telegraph_hex.gd`: цвет через UiTheme + новый параметр `semantic_tag: StringName` (forward-compat для 007). AC-R7.
- [ ] **T017** [P2] Refit `scripts/presentation/godmode/move_range_overlay.gd`: цвета через `UiTheme.TEAM_*`. AC-R8.
- [ ] **T018** [P2] Поглотить `scripts/presentation/turn_counter.gd` в `top_hud_bar.gd` (Phase 2 T030). Когда T030 будет готов — удалить turn_counter.gd, перенаправить ноду в godmode.tscn. **Этот таск обнулить если T030 сделан без поглощения.**
- [ ] **T019** [P3] Регрессионный смоук Phase 1: запуск Godmode, выполнение acceptance scenarios из 003-dialogue-manager и 006-actors-info-window. Если что-то не работает — фикс в этой же фазе. (depends T010-T017)

**Definition of done Phase 1:** все 8 виджетов рефит-нуты, regression scenarios зелёные, F5 hot-reload меняет цвета.

---

## Phase 2 — New HUD components (UNBLOCKED, after Phase 1)

Виджеты для арены, не зависят от 007/008. Идут параллельно — каждый компонент независим.

- [ ] **T030** [P1] [P] Build C1 TopHudBar: `scripts/presentation/top_hud_bar.gd` + `scenes/ui/top_hud_bar.tscn`. Поля: turn_label, wave_label, run_timer_label, pause_button. API из plan.md §"Component public APIs". (Поглощает старый turn_counter.gd) AC-N1, AC-N3.
- [ ] **T031** [P1] [P] Build C3 PlayerStatusPanel: `scripts/presentation/player_status_panel.gd` + `scenes/ui/player_status_panel.tscn`. Bind на player Actor через `bind_player()`, реагирует на `damaged` и `statuses_changed` (последний — placeholder сигнал, эмитимый из inspector temp). AC-N1.
- [ ] **T032** [P2] [P] Build C5 StatusIconStrip: `scripts/presentation/status_icon_strip.gd` + `scenes/ui/status_icon_strip.tscn`. На вход — `Array[StringName]` статусов с длительностями. На время phase 2 — статус-системы нет, рендер заглушек по фейковым данным из inspector.
- [ ] **T033** [P2] [P] Build C8 CastRangeOverlay: `scripts/presentation/cast_range_overlay.gd` + `scenes/ui/cast_range_overlay.tscn`. Рисует подсветку валидных целевых hex'ов по выбранной abillity. Слушает `cast_mode_changed` от controller'а. AC-N1.
- [ ] **T034** [P2] [P] Build C11 FloatingNumberLayer + FloatingNumber: `scripts/presentation/floating_number{,_layer}.gd` + scenes. Spawn по EventBus.damage_dealt / heal_done (заглушки сигналов до 007). Float-up + fade-out via Tween в _ready. AC-N1.
- [ ] **T035** [P2] [P] Build C13 HexInspectorSubpanel: рефакторинг hex section из `actor_inspector.gd` в отдельную сцену + скрипт. ActorInspector instance'ит её как child. (depends T012)
- [ ] **T036** [P2] [P] Build C15 TooltipPanel: `scripts/presentation/tooltip_panel.gd` + `scenes/ui/tooltip_panel.tscn`. Авто-suppression через `EventBus.ui_modal_opened/closed`. AC-X2.
- [ ] **T037** [P2] [P] Build C18 ChoiceButtonRow: вынести из `dialogue_panel.gd._show_choices()` в отдельный компонент. DialoguePanel instance'ит его. (depends T013)
- [ ] **T038** [P3] Integrate Phase 2 в `scenes/dev/godmode.tscn`: заменить TurnLabel/HelpLabel на TopHudBar instance, добавить PlayerStatusPanel, CastRangeOverlay, ToastLayer (из Phase 3 T041 — отложить если параллелится). AC-I1. (depends T030, T031, T033)

**Definition of done Phase 2:** Godmode сцена показывает new HUD, все компоненты работают визуально, regression smoke зелёный.

---

## Phase 3 — Modals, menus, system widgets (UNBLOCKED, after Phase 2)

- [ ] **T040** [P1] [P] Build C25 ConfirmModal: `scripts/presentation/confirm_modal.gd` + scene. API: `await ask(...) -> bool`. Pause toggle. AC-X1.
- [ ] **T041** [P1] [P] Build C26 ToastLayer + ToastItem: `scripts/presentation/toast_{layer,item}.gd` + scenes. Stack 3, dedup по тексту 500ms. Слушает `EventBus.ui_toast_requested`. AC-X4.
- [ ] **T042** [P1] [P] Build C23 PauseMenu: `scripts/presentation/pause_menu.gd` + scene. Buttons: Resume / Restart Run (→ confirm) / Settings (→ open C24) / Main Menu (→ confirm) / Quit (→ confirm). Pause via `get_tree().paused = true`. (depends T040)
- [ ] **T043** [P2] [P] Build C24 SettingsPanel: scene + script. Audio sliders (привязка к существующим audio buses через `AudioServer.set_bus_volume_db`), game speed multiplier (через `GameSpeed.set_global_multiplier()` — добавить если нет), keybind list display-only.
- [ ] **T044** [P1] [P] Build C22 MainMenu: `scripts/presentation/main_menu.gd` + `scenes/main_menu.tscn`. Buttons: Start Run (emits `EventBus.run_started_requested`) / Continue (disabled) / Settings (→ open C24 in standalone mode) / Credits / Quit. AC-I2.
- [ ] **T045** [P2] [P] Build C28 KeybindOverlay: `scripts/presentation/keybind_overlay.gd` + scene. Toggle by `?` key. Plain two-column list. NOT pause-triggering.
- [ ] **T046** [P2] [P] Build C27 CombatLog: `scripts/presentation/combat_log.gd` + scene. Ring buffer 50, toggle by `L`. Слушает `damage_dealt` / `heal_done` / `status_applied` сигналы (заглушки до 007/008). AC-X5.
- [ ] **T047** [P3] [P] Build C20 PortalTransition: `scripts/presentation/portal_transition.gd` + scene. Fullscreen interstitial с wave number + flavor text slot + continue button (or auto-advance N sec).
- [ ] **T048** [P3] [P] Build C21 RunSummary: scene + script. Stacked horizontal bars per moral compass axis (Q-UI-2 → bars). Stats grid. Buttons: Restart / Main Menu.
- [ ] **T049** [P3] [P] Build C29 LoadingCover: trivial — fullscreen ColorRect + center Label. Show/hide via signals.
- [ ] **T050** [P1] Migrate main scene: `project.godot` `[application] config/run/main_scene` → `res://scenes/main_menu.tscn`. Удалить `scenes/main.tscn` + `scripts/main.gd` (Q-UI-4 → (a)). AC-I2. (depends T044)
- [ ] **T051** [P2] Add ESC handler upgrade в `godmode_controller`: priority chain (cancel cast → close top modal → reset selection → open pause menu). AC-I3, plan.md §"ESC handling". (depends T042)
- [ ] **T052** [P3] Optional: `scripts/presentation/modal_router.gd` autoload для централизованного modal stack management. Пропустить если pause/settings/confirm справляются self-managed (вероятно справятся, рассмотреть после Phase 3 интеграции).
- [ ] **T053** [P3] Финальный regression smoke: 003, 004, 005, 006 acceptance scenarios + ручной проход всего main menu → start run → godmode → pause → settings → resume → trigger toast → trigger combat log lines.

**Definition of done Phase 3:** main menu — точка входа, pause/settings/confirm работают, toast/log/keybind overlay интегрированы. Игра до Phase 4 — играбельна целиком в Godmode + меню вокруг.

---

## Phase 4 — BLOCKED on 007 (skill system)

**НЕ СТАРТОВАТЬ** до merge spec-007 в staging. Андрей подтверждает в чате с Egor.

- [!] **T060** [P1] Build C14 SkillTooltip: `scripts/presentation/skill_tooltip.gd` + scene. Renders: skill header (name + cooldown), abilities list (target/area glyph + effects breakdown с modifier-влиянием в формате `base → final`), tags chips. Использует helper `SkillFormatter` (новый, в `scripts/presentation/`). АC-N1.
- [!] **T061** [P1] Build helper `scripts/presentation/skill_formatter.gd`: pure-static функции `format_effect(effect, modifiers) -> String`, `format_modifier_breakdown(modifiers, field) -> String`. Один источник правды для skill text representation. (depends 007 ParameterModifier API)
- [!] **T062** [P1] Refit `slot_bar.gd` cooldown overlay: numeric Label centered в slot когда `Skill.cooldown_remaining > 0`. Other variants (radial, fill-bar) — заскипать, выбран числовой как cheapest (Q-UI-1 в handoff). (depends 007 Skill API)
- [!] **T063** [P2] Build C19 ModifierPickScreen: `scripts/presentation/modifier_pick_screen.gd` + scene. 3 cards с aspect (target/effect/modifier), description, моральный compass shift preview (option (b) из handoff Q-UI-1). Pick → emit signal → close. (depends 007 ParameterModifier + future absorb-system)
- [!] **T064** [P2] Подключить SkillTooltip к slot_bar (hover) и ActorInspector (skill pip hover). Удалить плейсхолдер tooltip из 006. (depends T060)

---

## Phase 4 — BLOCKED on 008 (enemy AI)

**НЕ СТАРТОВАТЬ** до merge spec-008 в staging. Координация с Sergey.

- [!] **T070** [P1] Refit `intent_arrow.gd`: показывать цвет по `cast_intent.skill.primary_tag` (если != null), иначе fallback на damage. (depends 008 cast_intent API)
- [!] **T071** [P1] Refit `actor_inspector.gd` enemy-mode: добавить «Planned intent» Label, рендерящий `cast_intent` в одну строку («Cast Fireball at (3,2): -15 dmg»). (depends 008 + T060 SkillFormatter)
- [!] **T072** [P2] Refit `telegraph_hex.gd`: цвет hex по `cast_intent.skill.primary_tag` (heal-intent → green tint, control → purple, etc.). Pillar 1 — игрок видит ЧТО случится. (depends 008 + 007 tags)

---

## Phase 5 (post-jam, optional) — Polish

Не входит в defition of done джема. Если останется время в субботу днём.

- [ ] **T080** Animations: cooldown sweep в C2 (Tween на overlay), modal slide-in (Tween на position), toast slide-in/fade-out, slot scale-pop при cast.
- [ ] **T081** SFX hooks: button hover/click, modal open/close, toast appear, dialogue advance. AudioDirector signals.
- [ ] **T082** Migration UiTheme constants → `config/ui_theme.cfg` ConfigFile, если плейтест показал что палитра балансится активно.
- [ ] **T083** Asset slots: подменить Unicode glyph placeholders на иконки от Кати по мере поступления.
- [ ] **T084** Refit `scenes/dev/` (spawn picker, tile-effect picker) под палитру UiTheme — C30, C31. Не критично, dev-only.

---

## Параллельность — рекомендованная разбивка для одного человека (Andrey)

День 1 (Phase 0 + Phase 1):
- Утро: T001-T005 (Phase 0, ~2 часа)
- День: T010, T011, T012 (refit health/slot/inspector, ~3 часа)
- Вечер: T013-T017 + T019 (refit + smoke, ~2 часа)

День 2 (Phase 2 + начало Phase 3):
- Утро: T030, T031, T038 (top HUD + player status + integration, ~3 часа)
- День: T032-T037 (status icons, cast range, floats, tooltip, choice row, hex subpanel — ~4 часа суммарно, многие тривиальные)
- Вечер: T040, T041, T042 (confirm/toast/pause — ~3 часа)

День 3 (Phase 3 закрытие):
- Утро: T043, T044, T045, T046 (settings, main menu, keybind, log)
- День: T047, T048, T049, T050, T051 (transitions, summary, loading, main scene swap, ESC handler)
- Вечер: T053 regression + полировка

Phase 4 — после того как Egor/Sergey закроют 007/008. Реалистично — последний день джема.

## Открытые вопросы — отслеживание

Закрытие в порядке:
- **Q-UI-1** (theme storage) — рекомендация (a) hardcoded const. Закрыть в момент T001 (утвердить или мигрировать).
- **Q-UI-2** (compass viz) — bars, утверждено для T048.
- **Q-UI-3** (pause granularity) — (b), утверждено в plan.md.
- **Q-UI-4** (main scene swap) — (a) полная замена, утверждено для T050.
- **Q-UI-5** (internal voice anchor) — (a) top-center, утверждено для C17 (Phase 5 если успеется, иначе не блокирует основной flow).

Если в ходе работы один из ответов не сходится — обновить spec.md в том же PR и переотметить.
