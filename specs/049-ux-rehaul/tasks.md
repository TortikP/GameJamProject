# 049-ux-rehaul — tasks

Spec: `spec.md`. Plan: `plan.md`. Branch: `egor/049-ux-rehaul` (off staging).

Order: A → B → C → D. Phases A (formatter) and B (telegraph icon + grey-out) are independent — можно делать параллельно. Phase C (panels) зависит от B (TelegraphHex.icon_skill — общий для C2/C3). Phase D — cleanup, идёт последней.

## Phase A — Source-of-truth для описаний

- [x] **T001** — `scripts/presentation/skill_formatter.gd`: добавить `static func format_skill_human(skill) -> String`. Логика: `Localization.t(skill.tooltip, "")` с пустым fallback'ом — детектируем missing key через `result == ""` (см. `Localization.t` API; если `t()` возвращает ключ при отсутствии вместо пустоты — менять на явное `Localization.has(key)` API; до этого момента — `tf` вторым аргументом ""). Если empty → `format_skill(skill)`. Append CD-line при `cooldown > 0`. Старый `format_skill` НЕ удалять.
- [x] **T002** — `scripts/presentation/skill_formatter.gd`: добавить `static func format_consequence(skill) -> String`. Возвращает короткую (≤30 char) строку для HexTooltip 3-й колонки. Алгоритм: первый `DamageEffect` → `"-%d HP"`; первый `HealEffect` (если есть в коде) → `"+%d HP"`; первый `status_id` → `"<status_loc> (<turns>t)"` через парс `slowed(3)` синтаксиса. Default → `""`. Без модификаторов (для предсказуемости — preview берёт base). Smoke: `default_melee` → `-10 HP`, `curse` → `Slowed (3t)`, `default_heal` → `+15 HP`.
- [x] **T003** — `scripts/presentation/player_status_panel.gd`: переключить `set_active_spell` на `format_skill_human`. Добавить `set_hover_spell(skill)`, `_active_skill` / `_hover_skill` поля, `_refresh_spell_section()` helper. Hover beats active. Null hover → fall back to active. Smoke: select slot → desc меняется; hover пустой слот → ничего не происходит; hover другой слот → desc того, на ком hover.

## Phase B — Telegraph icon + valid-target highlight

- [x] **T004** — `scripts/presentation/skill_icon_resolver.gd`: новый файл, ~30 строк. Static helper `resolve(skill) -> Texture2D`. Логика — copy из `skill_offer_card._resolve_icon` (lines 149–169). Поддерживает `res://`, `icons/skills/foo.png`, `skills/foo.png`. Возвращает null если skill null / icon empty / not found.
- [x] **T005** — `scripts/presentation/ui/skill_offer_card.gd`: переключить `_resolve_icon` на `SkillIconResolver.resolve(skill)`. Удалить inline-копию.
- [x] **T006** — `scripts/presentation/telegraph_hex.gd`: добавить `var icon_skill: Skill` (with `set` → `queue_redraw`). Расширить `_draw()`: если `outline_only==false`, после polygon+outline рисуем иконку или букву (см. plan.md §`telegraph_hex.gd`). Damage label смещается из `-tile.y/2 - 6` (above hex) в `tile.y * 0.35` (below center, inside hex). Visibility doctrine: `draw_string_outline` + `draw_string` с `WORLD_TEXT_OUTLINE_*`.
- [x] **T007** — `scripts/presentation/godmode/telegraph_renderer.gd`: в `refresh()` после `hex.set("damage", entry.damage)` (line 152) добавить `hex.set("icon_skill", entry.skill)` — для этого надо хранить `skill` в `by_coord` entry: `by_coord[coord] = {"tag": tag, "damage": dmg, "skill": skill}`. Existing aggregation по damage не ломаем (skill — у first-write-wins, как и tag).
- [x] **T008** — `scripts/presentation/cast_range_overlay.gd`: AC-6 grey-out. Изменить API `setup(grid)` → `setup(grid, registry)`. Разделить `_coords` на `_coords_valid` + `_coords_invalid`. В `show_range_for_ability` итерировать `target.get_range_hexes` и классифицировать через `target.resolve(caster, per_hex_ctx) != null`. В `_draw()` две петли: valid → `SEM_DEBUFF` outline (текущий look), invalid → `Color(GREY_50, 0.30)` outline 1.5px. Self-confirm path не трогаем.
- [x] **T009** — `scripts/presentation/godmode/godmode_setup.gd`: при resolve cast_overlay вызвать `_ctrl.cast_overlay.setup(_ctrl.grid, _ctrl.registry)` вместо `setup(grid)`.

## Phase C — Hex tooltip + enemy details panel + enemy move path

- [x] **T010** — `scripts/presentation/hex_tooltip.gd` + `scenes/ui/hex_tooltip.tscn`: новые файлы. Class extends PanelContainer. Layout: `VBox > RowsVBox`. `show_for(rows: Array, mouse_pos: Vector2)` строит rows через `_ensure_rows(rows.size())` + `_populate_row`. `hide_tooltip()` set visible=false. Position: `_place_near_cursor(mouse_pos)` — `mouse + Vector2(SP_2, -size.y - SP_2)`, clamp via viewport rect (см. `tooltip_panel._place_near` для clamp кода). Theme: `make_panel_stylebox(true)`. Подписки: `EventBus.ui_modal_opened` → `_suppressed=true` + hide; `ui_modal_closed` → `_suppressed=false`.
- [x] **T011** — Row composition в `hex_tooltip.gd`: каждая строка — HBox: `[ActorLabel(small)] [IconRect(16x16) NameLabel(body)] [ConsequenceLabel(small)]`. Spacing — `UiTheme.SP_2`. Icon: `SkillIconResolver.resolve(skill)`, fallback — буква в Label (тот же шрифт `body`). Actor name — `Localization.t(actor_id_str, actor_id_str)` (если перевода нет — id напрямую).
- [x] **T012** — `scripts/presentation/enemy_details_panel.gd` + `scenes/ui/enemy_details_panel.tscn`: новые файлы. Layout: `HBox > [Portrait(64x64), VBox{NameRow{TeamBadge, NameLabel}, HpLabel, StatusStrip}, AbilitiesRow]`. `bind(actor)` — connect `damaged` + `statuses_changed` (если signal есть; иначе только `damaged`), populate fields. `unbind()` — disconnect, hide. `_refresh_hp` / `_refresh_statuses` — на signal. Anchors top-right (см. `plan.md §scenes/dev/godmode.tscn`).
- [x] **T013** — Portrait pipeline: попытаться загрузить `assets/portraits/<actor.actor_id>.png` или `enemy_data.portrait_path`; null → hide TextureRect. Status strip — reuse `scenes/ui/status_icon_strip.tscn` instance под `VBox/StatusStrip`.
- [x] **T014** — Abilities row в `enemy_details_panel.gd`: одна "pip" на каждый skill в `actor.get_skills()`. Pip = HBox(`[IconRect(20x20) или Letter] [Label(small) — name + (CD)]`). Tooltip на hover pip — `format_skill_human(skill)`. Disabled (no LMB action).
- [x] **T015** — `scripts/presentation/enemy_move_path.gd`: новый файл, ~70 строк, extends Node2D. `setup(grid: HexGrid, path: Array[Vector2i])`. `_draw()` — polyline через `grid.tile_map_layer.map_to_local(coord)` для каждого hex, drop shadow (1px offset, `SHADOW_SOFT_COLOR`), main line `SEM_DAMAGE` alpha 0.85 width 4.0 antialiased. Arrowhead на последнем segment — copy из `intent_arrow._draw` triangle math, но dir computed из `path[-1] - path[-2]`.
- [x] **T016** — `scripts/presentation/godmode/telegraph_renderer.gd`: заменить `INTENT_ARROW_SCRIPT` на `ENEMY_MOVE_PATH_SCRIPT`. В блоке movement intent (lines 132–143) — вычислить `path` через `grid.find_path_around(enemy_coord, mv, blocked)`, спавнить `EnemyMovePath`, `path_node.setup(grid, path)`. Helper `_live_blocked_coords(registry, exclude_actor)` — copy из hover_dispatcher refresh_hover_path:130-139, либо вынести в общий util в первой итерации не надо.
- [x] **T017** — `scripts/presentation/godmode/hover_dispatcher.gd`: удалить `refresh_intent_tooltip` (lines 156–192), `_hover_intent_actor_id` field, import `SkillFormatter` оставить (для format_consequence).
- [x] **T018** — `scripts/presentation/godmode/hover_dispatcher.gd`: добавить `refresh_hex_tooltip(coord)` + `_build_hex_tooltip_rows(coord)` (см. plan.md §hover_dispatcher.gd для signature). State guard `_last_hex_tooltip_coord` — re-render только при смене coord.
- [x] **T019** — `scripts/presentation/godmode/hover_dispatcher.gd`: добавить `refresh_enemy_details(target_id)` + `_last_enemy_details_id` guard. Резолв панели через `get_node_or_null("../../HUD/EnemyDetailsPanel")`.
- [x] **T020** — `scripts/presentation/godmode/hover_dispatcher.gd`: в `_process(_delta)` после `update_castability()` добавить вызовы новых dispatch'ей. Сохранить `coord` / `target_id` локально, передавать в `refresh_hover_path`, `refresh_hex_tooltip`, `refresh_enemy_details`. (Сейчас `update_castability` делает свои `coord_under_mouse()` + `get_actor_at` calls — duplicate ОК, дешево.)

## Phase D — Cleanup + scene wiring

- [x] **T021** — `scripts/presentation/godmode/godmode_controller.gd`: удалить `_selected`, `select`, `deselect_to_player`, `inspect_hex`, `bind_hex_at`, `_on_inspector_speed_changed`, `_on_actor_died_for_selection`, `var inspector`, `@export var inspector_path`. Добавить `_on_slot_hovered(idx)` / `_on_slot_unhovered(_idx)` (см. plan.md §godmode_controller.gd).
- [x] **T022** — `scripts/presentation/slot_bar.gd`: добавить signals `slot_hovered(idx)` + `slot_unhovered(idx)`. В каждом slot button (см. existing `_make_slot_button` или эквивалент в файле — TBD при impl) `mouse_entered.connect(emit_signal.bind("slot_hovered", i))` + `mouse_exited`.
- [x] **T023** — `scripts/presentation/godmode/godmode_input.gd`: AC-3 — в `_request_cast_active` (lines 215–220) удалить ветку с `_ctrl.select(target_actor)` / `_ctrl.inspect_hex(coord)`. Замена: `if active_idx == -1: return` (no active slot → no-op). В Esc-handler удалить selection-tier (lines 44–47).
- [x] **T024** — `scripts/presentation/godmode/godmode_setup.gd`: удалить `_ctrl.inspector` resolution, `speed_changed.connect`, `inspector.hide()` fallback, `_select_deferred`. Добавить connect `slot_hovered` / `slot_unhovered`. Найти HexTooltip + EnemyDetailsPanel через `find_child` (либо новые `@export NodePath` на controller — выбрать одно). Передать registry в cast_overlay.setup (T009).
- [x] **T025** — `scenes/dev/godmode.tscn`: удалить ActorInspector node + ext_resource + `inspector_path` строку. Добавить EnemyDetailsPanel + HexTooltip nodes под `HUD` (top-right anchor для EDP, no anchor для HT). Update load_steps.
- [x] **T026** — Удалить файлы:
  - `scripts/presentation/godmode/actor_inspector.gd`
  - `scenes/dev/actor_inspector.tscn`
  - `scripts/presentation/hex_inspector_subpanel.gd`
  - `scripts/presentation/intent_arrow.gd`
  Каждое удаление — `git rm`.
- [x] **T027** — `scripts/presentation/dev/tile_objects_smoke_controller.gd`: добавить `const _SMOKE_LOG_ENABLED: bool = false` в начале файла. Обернуть все `GameLogger.info(...)` calls (примерно 20 штук) в `if _SMOKE_LOG_ENABLED:`. Контроллер сам остаётся — это всё ещё валидный smoke-тест 018.

## Phase E — Smoke

- [ ] **T028** — Smoke в Godmode: загрузить `scenes/dev/godmode.tscn`, F1 → spawn 2 манекена. Каждый получает cast_intent через `ai_driver` (или вручную через RMB? — TBD). Для каждого AC проверить:
  - **AC-1**: select slot Q → PSP SpellDesc показывает Localization tooltip, не структуру. (Если key missing — debug fallback ОК.)
  - **AC-2**: hover на гексе под player preview / enemy intent → HexTooltip у курсора, 1+ строк. На пустом гексе → скрыт.
  - **AC-3**: LMB на enemy без активного slot → ничего. ActorInspector нет.
  - **AC-4**: hover на enemy → EnemyDetailsPanel в верхнем правом углу. Hover off → скрыт.
  - **AC-5**: TelegraphHex на manekin'е под intent — иконка-буква в центре, damage снизу.
  - **AC-6**: Q (default_melee, range 1) → adjacent hex'ы валидны (red outline), дальние — серые. Click на серый — no-op.
  - **AC-7**: manekin с `move_intent` → красный path через hex'ы от его coord до intent_coord.
  - **AC-8**: hover на slot R (curse) без выбора → PSP показывает curse description; mouse exit → возвращается на active.
  - **AC-9**: лог тихий, нет 018-smoke spam.
- [ ] **T029** — Smoke на sample-уровне (level из editor): загрузить уровень с 2 волнами по 2 моба. Wave 1 → пройти, Wave 2 → прицельно проверить hex tooltip когда у нескольких мобов intents на один hex (multi-row tooltip).
- [ ] **T030** — Edge: cursor на player'e → enemy_details скрыт (player не enemy). Edge: cursor на гексе с двумя AOE-целями (player skill + enemy intent) → tooltip показывает обе строки. Edge: cursor двигается между гексами — tooltip перерисовывается без flicker.
- [x] **T031** — Localization audit: `grep -c "_tooltip" data/localization/en.json` vs `ls data/skills/*.json | wc -l`. Если разница > 30% — заэскалировать Никите перед merge (R1 в spec.md).

## Phase F — Docs + PR

- [x] **T032** — `HANDOFF.md`: добавить секцию `## 23. 049-ux-rehaul — точки интеграции`. Ссылки на 029 (что закрыто), 040 (SkillIconResolver helper), 048 (no overlap).
- [x] **T033** — `CLAUDE.md` ownership table: добавить строку `049-ux-rehaul (HexTooltip, EnemyDetailsPanel, EnemyMovePath, SkillFormatter human, TelegraphHex icon, CastRangeOverlay grey-out) | Egor`.
- [x] **T034** — Self-review diff: убедиться что (a) core/ не тронут, (b) UiTheme только расширен (не правлен), (c) удалённые файлы — все 4 из T026, ничего лишнего, (d) PSP SpellSection НЕ потерял CD indicator.

## Cut list

См. `plan.md §"Что не делаем"`. В порядке агрессивного отрезания: AC-2 hex-tooltip → AC-6 grey-out → AC-8 hover-PSP → AC-7 enemy-paths → portrait в EDP → consequence column в hex-tooltip. Минимум shippable: AC-1 + AC-3 + AC-4 + AC-5 (буква) + AC-9.

## После мержа

- 029-feedback-polish/spec.md — отметить req-6 как «закрыто 049» (можно при следующей правке Andrey'я).
- Иконки скиллов от Кати, когда придут, — drop в `assets/icons/skills/<id>.png`, JSON уже указывает путь, SkillIconResolver сам подхватит.

## Phase G — 049b follow-ups (Egor feedback after first pass)

Three issues surfaced on first review of the merged 049 work; tracked as
follow-up tasks rather than amending the original AC list.

### Issue 1 — Description fonts too small / no colour cue

Spell description in PSP and the consequence column in HexTooltip read
as the dimmest things on screen. Player has to lean toward the monitor
to parse them — violates the visibility doctrine in CLAUDE.md.

- [x] **T035** — `scripts/presentation/skill_formatter.gd`: добавить
  `static func consequence_color(skill) -> Color`. Effect-priority order
  matches `format_consequence`: damage→SEM_DAMAGE, heal→SEM_HEAL,
  status→SEM_DEBUFF, move→SEM_MOVE, create→SEM_BUFF, default→TEXT.
  `scripts/presentation/hex_tooltip.gd`: bump label kinds — actor/skill
  body/header (was small/body), consequence body (was small). Apply
  `consequence_color(skill)` as `font_color` override per row.
  `scripts/presentation/player_status_panel.gd`: `_spell_desc` kind
  small→body + `autowrap_mode = WORD_SMART`. Tint `_spell_name` and
  `_spell_desc` with `consequence_color(skill)` for read-at-a-glance
  type cue. Bare-Ability path stays neutral TEXT.

### Issue 2 — Tooltip stale on invalid target / after slot toggle off

Two related symptoms:
  a) Hovering a hex inside the active ability's range circle but where
     the cast wouldn't actually land (no actor of right team / blocked /
     out-of-LOS) still surfaced a player-preview row.
  b) Pressing the active slot key again to deselect didn't clear the
     tooltip's player-preview row until the cursor moved to a new hex.

- [x] **T036** — `scripts/presentation/godmode/hover_dispatcher.gd`:
  `_coord_in_ability_effect` now adds a step-2 validity gate via
  `ability.target.resolve(caster, per_hex_ctx)` (same shape as
  CastRangeOverlay's AC-6 grey-out). Step 1 is range_hexes membership;
  step 3 is area expansion (only when `ability.area != null`).
- [x] **T037** — `scripts/presentation/godmode/hover_dispatcher.gd`:
  `refresh_hex_tooltip` ditches the `_last_hex_tooltip_coord` guard.
  Rebuild rows every frame — guard was a mistake because slot toggle
  off (and other intent changes) don't shift the hovered coord. Cost
  is trivial (~10 actors × O(1)). Field removed.

### Issue 3 — Enemy telegraph colour-coded by skill type, not threat

Telegraph hex was tinted by `behaviour_tags[0]` (heal-cast = green hex,
control = purple hex, etc.). Goal of the telegraph is "this hex is a
threat from an enemy" — a uniform red read better. Skill-type info now
lives in the icon (049 AC-5) and the hex-tooltip consequence colour
(049b T035), so dropping it from the hex itself is no information loss.
Also: secondary AoE hexes were too easy to miss against busy biome
tiles — outline-only with α0.55, 1.5px.

- [x] **T038** — `scripts/presentation/godmode/telegraph_renderer.gd`:
  primary + secondary `TelegraphHex.semantic_tag = &"damage"` regardless
  of underlying skill. Original `tag` is still tracked in `by_coord` for
  the damage-aggregation sum upstream.
- [x] **T039** — `scripts/presentation/telegraph_hex.gd`: `outline_only`
  mode now draws a faint α0.18 fill in addition to the boundary, and
  outline weight bumped 1.5px α0.55 → 2.0px α0.85. Primary/secondary
  distinction now lives in fill density (0.42 vs 0.18) instead of in
  outline weight where it disappeared on busy frames.

### Issue 4 — Skill offer card surfaces lore, hides gameplay; no icon

The between-wave skill offer modal (040 territory) was wired to
`skill.desc` (lore) only and never showed `skill.tooltip` (gameplay).
`_resolve_icon` was called but the icon rect drew nothing when the
texture didn't resolve — Katya's skill icon set isn't in the repo yet,
so cards rendered with a blank 64×64 hole at the top. Egor screenshot.

- [x] **T040** — `scripts/presentation/ui/skill_offer_card.gd`:
  - Two RichTextLabels: `_gameplay_label` (FS_BODY, TEXT) sourced from
    `SkillFormatter.format_skill_human(skill)` — same string PSP and
    HexTooltip use.
  - `_lore_label` (FS_SMALL, TEXT_DIM) sourced from
    `Localization.t(skill.desc)` — was the only desc pre-T040, now
    flavour text underneath the mechanical answer.
  - Icon: `CenterContainer` with `_icon_rect` + `_icon_letter` Label
    (FS_DISPLAY); show whichever the resolver picks. Mirrors
    TelegraphHex / HexTooltip letter fallback.
  - `CARD_MIN_SIZE` 200×280 → 220×320 for the second description.

### Issue 5 — EnemyDetailsPanel overlaps TopHudBar; fonts too small

Top-right anchor with `offset_top=16` collided with TopHudBar (anchors
preset 10, y=0..52, full-width) and HelpLabel (y=56..84). Hover-driven
panel rendered behind/over the existing top strip. Fonts (`hp_label`
and abilities-row pip names) were `small` (14px) — illegible next to
the `header` (20px) name on the same panel.

- [x] **T041** —
  - `scenes/dev/godmode.tscn`: EDP `offset_top` 16 → 92 (clears
    TopHudBar 0..52 + HelpLabel 56..84 with padding); width 560 → 640
    (more room for 3+ ability pips); height bumped to 100px.
  - `scenes/ui/enemy_details_panel.tscn`: `custom_minimum_size` width
    360 → 480; `AbilitiesRow.separation` 8 → 16 so pips stop bleeding
    into each other.
  - `scripts/presentation/enemy_details_panel.gd`: `_apply_theme` —
    `_hp_label` kind small → body. `_make_pip` — name label small →
    body, icon size 20→24px, separation SP_1 → SP_2.

### Issue 6 (round-2) — three more on the same modal flow

After T040/T041 landed Egor surfaced three further issues on the offer
flow + telegraph rendering. Tracked as T042-T044.

#### Issue 6a — ranged-AoE telegraph lying

For `target=actor(range=N) area=zone_circle(radius=R)` skills, the AI
re-resolves `target_coord = live_coord` of the player at apply-time
(see `ai_driver._resolve_cast_intent` line 246). Player walks one hex
"away from" the visualised AoE and gets clipped because the AoE re-
anchors on the new player position. Visual was painting the AoE around
the live coord at refresh-time only — it lied about future apply.

- [x] **T042** — `scripts/presentation/godmode/telegraph_renderer.gd`:
  in the AoE-collection block, build `anchor_set` per-ability:
    - live target coord (existing behaviour),
    - PLUS for `ActorTarget` skills tracking `target_id == &"player"`,
      every hex in `grid.reachable_within(p_coord, p.effective_speed(), [])`
      that's also in `ability.target.get_range_hexes(caster_coord, grid)`.
  Paint AoE around every plausible anchor. Truthful threat zone — the
  player can now read "anywhere I move within this paint, the AI's AoE
  catches me." Cost: ~10 anchors × ~7 affected hexes = ~70 entries
  per intent, dedup'd by area_coords dict.

#### Issue 6b — empty slot beats force_replace

Story-map JSONs (`story_map_0[1-4].json`) all set `force_replace=true`
per wave. With T040 surfacing card mode badges prominently, players
saw "ЗАМЕНИТЬ" on every card while their R slot still sat empty. UX
contradiction: "swap something out" + "your R is open."

- [x] **T043** — `scripts/runtime/skill_offer_controller.gd`:
  `_make_card_for` empty-slot check is FIRST. If
  `PlayerSkillAdapterScript.first_empty_slot() >= 0`, return mode=add
  regardless of `force_replace`. force_replace only kicks in when the
  bar is full. Side effect: T044's slot picker now sees all 4 slots
  always populated (the empty-slot path went to ADD upstream).

#### Issue 6c — replace screen UX rebuild

Replace screen showed only the localised name of the incoming skill in
the hint Label. Slot buttons listed `Q\nUdar` etc. — fine for "what's
in there" but no way to compare what you're losing vs gaining. Egor:
"hover на слотах должен показывать tooltip снизу в одном месте, с
красной рамкой и зачёркнутым текстом. Сверху — описание того, что ты
берёшь, чтобы не забыть."

- [x] **T044** — `scripts/presentation/ui/skill_offer_modal.gd`
  `_show_slot_picker`:
    - INCOMING-skill panel at the top: PanelContainer with name (header,
      tinted by SkillFormatter.consequence_color) + RichTextLabel with
      `format_skill_human(skill)` body. Always visible.
    - Slot row gets `mouse_entered.connect(_on_replace_slot_hover.bind(i))`
      and `mouse_exited.connect(_on_replace_slot_unhover)`.
    - OUTGOING-skill preview panel at the bottom — fixed vertical
      position. Custom red-bordered stylebox via
      `_make_replace_outgoing_stylebox` (2px SEM_DAMAGE border vs default
      1px BORDER). RichTextLabel with `[b][s]NAME[/s][/b]\n[s]gameplay[/s]`
      BBCode for strikethrough on both lines, painted SEM_DAMAGE.
    - `_on_replace_slot_unhover` is a no-op — keeps last-hover pinned so
      cursor flicker between slot buttons doesn't strobe the preview.
    - Empty-slot guard `btn.disabled = (existing == null)` retained for
      forward-compat (T043 makes it unreachable today).
    - `_on_cancel_replace` clears outgoing-panel refs to avoid stale-node
      access from delayed signals (Godot 4.6 trap).
  Localization: `skill_offer.replace.hover_hint` + `.empty_slot` added
  to en + ru.
