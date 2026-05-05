# 040-wave-skill-choice — spec

**Owner:** Andrey (driver, full-stack — schema, runtime modal, editor UI, sample pool).
**Coordination:**
- **Egor / Sergey** (007/021/026 skill system) — readonly read из `Skill` API: `id`, `name` (loc-key), `desc`, `level`, `mood`, `tooltip`. Также `PlayerSkillSet` (или эквивалент) для apply-выбора (add/upgrade/replace). Никаких правок их файлов; если public API не покрывает «upgrade существующего скилла» — поднимаем флаг и режем сразу до `add | replace` (см. cut list).
- **Alexey** (roguelike loop) — owner будущего meta-loop'а. SkillOfferModal — частный случай roguelike-progression UI, мы делаем localized в-уровне версию. Если roguelike-loop появится — рефакторится снаружи без правок 040.
- **Andrey** (024-wave-editor) — owner WavePanel + WaveController. Этот спек добавляет subpanel в WavePanel и точку прерывания в WaveController. Не coordinated — сам с собой.
**Status:** Draft — clarify-round пройден с Andrey (full Hades-like: pick + upgrade + replace).

## Цель

Между волнами игрок выбирает скилл из 3 (или N) карточек. Можно добавить новый, апгрейднуть существующий в слоте, или заменить занятый слот на новый. Конфигурируется per-wave в map editor; если волна без `skill_offer` — переход без модалки. Реф — Hades' boon system, упрощённый под джем.

## Scope-граница

**В скоупе:**
- Schema `LevelData.waves[i].skill_offer` (опциональная Dictionary).
- Pool definitions `data/skill_offer_pools/*.json` — список skill-id из которых сэмплируется `count`.
- Runtime `SkillOfferController` autoload — слушает `EventBus.wave_cleared`, открывает модалку, ждёт выбор, применяет к player skill set, продолжает wave-flow.
- Modal scene `scenes/ui/skill_offer_modal.tscn` — N карточек + Skip button (если `allow_skip=true`).
- Editor UI — config-сабпанель в WavePanel (per-wave) + маркер pick'а на WaveTimeline в EDIT и RUNTIME режимах.
- Новые `EventBus` сигналы: `skill_offer_about_to_open(wave_index, count, pool_id)`, `skill_offer_closed(wave_index, picked_skill_id, mode)` где `mode ∈ {&"add", &"upgrade", &"replace", &"skipped"}`.
- Sample-уровень `data/maps/sample_skill_offer.json` + sample pool `data/skill_offer_pools/basic.json`.

**Вне скоупа:** см. секцию «Out of scope» внизу. Главные исключения: meta-progression сохранение между ранами, кастомные правила выбора (rerolls, banishes, conditional offers), drag-drop reordering пула, balance-tuning weights.

## Что вводится

### 1. Расширение `LevelData.waves[i]` — поле `skill_offer`

Каждая волна получает опциональное поле:

```gdscript
{
  "index": 1,
  "is_special": false,
  "turns_to_next": 6,
  "floor": [...],
  "objects": [...],
  "spawners": [...],
  "skill_offer": {                       # optional — null/absent = no offer between this wave and next
    "pool": "basic",                      # StringName — id файла из data/skill_offer_pools/*.json (без .json)
    "count": 3,                           # int >=1 — сколько карточек показать
    "allow_upgrade": true,                # bool — можно показать «upgrade existing slot X» как один из вариантов
    "allow_replace": true,                # bool — можно показать «replace slot X» как один из вариантов
    "allow_skip": false,                  # bool — кнопка Skip (без выбора, mode=skipped)
    "exclude_owned": false,               # bool — фильтр пула: исключить скиллы, уже занимающие слоты
  },
}
```

**Семантика timing.** Offer открывается **после `wave_cleared`** старой волны и **до `wave_about_to_start`** новой. То есть последовательность:
1. Last enemy died → `actor_died` → WaveController auto-clear → `wave_cleared(idx, unused)`.
2. SkillOfferController перехватывает: если `waves[idx].skill_offer != null` → opens modal, эмитит `skill_offer_about_to_open(idx, count, pool_id)`. Player input — заблокирован для боя (модалка над всем).
3. Player picks (или Skip). Modal closes, эмитит `skill_offer_closed(idx, picked_id, mode)`.
4. WaveController продолжает: `wave_about_to_start(idx+1)` → `_apply_wave_snapshot(idx+1)` → `wave_started(idx+1, ...)`.

**Last wave.** `skill_offer` на последней волне — допустимо, открывается перед `level_completed`. Для финальных «выбор как награда за уровень» сценариев. Дизайнер сам решает, нужно или нет.

### 2. Pool format `data/skill_offer_pools/*.json`

```json
{
  "id": "basic",
  "label_key": "skill_offer.pool.basic.name",
  "skills": [
    "ball_throw",
    "berry_throw",
    "honey_cold",
    "spores",
    "summon_bee",
    "weaken"
  ],
  "weights": {                              // optional — default 1.0 each
    "summon_bee": 0.5
  },
  "min_player_level": 0,                    // optional — gate against future progression
  "tags": ["starter"]                        // optional metadata, не используется в v1
}
```

`skills` — массив skill-id (`StringName`); каждый id должен резолвиться через `SkillDatabase` (или эквивалент — найти при имплементации). Если id не найден — runtime drop'ает его из эффективного пула, warn-once.

`weights` — relative; не нормализуем явно, выборка через `randf() * total_weight`. Default = 1.0 для не указанных.

### 3. Runtime — `SkillOfferController` (autoload)

```gdscript
# scripts/runtime/skill_offer_controller.gd, autoload "SkillOfferController"
extends Node

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const POOLS_DIR := "res://data/skill_offer_pools/"

var _pools: Dictionary = {}                  # StringName -> Dictionary
var _level: LevelData = null                 # set on EventBus.level_loaded
var _modal: Node = null                      # spawned on demand


func _ready() -> void:
    _scan_pools()
    EventBus.level_loaded.connect(_on_level_loaded)
    EventBus.wave_cleared.connect(_on_wave_cleared)
    EventBus.battle_ended.connect(_on_battle_ended)


func _on_wave_cleared(idx: int, _unused: int) -> void:
    if _level == null: return
    if idx < 0 or idx >= _level.waves.size(): return
    var offer: Variant = _level.waves[idx].get("skill_offer", null)
    if offer == null: return

    var pool_id: StringName = StringName(str(offer.get("pool", "")))
    var pool: Dictionary = _pools.get(pool_id, {})
    if pool.is_empty():
        GameLogger.warn("SkillOfferController", "pool '%s' not found — skipping offer" % pool_id)
        return

    var count: int = int(offer.get("count", 3))
    var cards: Array = _build_cards(pool, count, offer)
    if cards.is_empty():
        GameLogger.warn("SkillOfferController", "pool '%s' produced no cards — skipping" % pool_id)
        return

    EventBus.skill_offer_about_to_open.emit(idx, count, pool_id)
    var picked: Dictionary = await _open_modal(cards, offer)  # awaits player click or skip
    _apply_pick(picked)
    EventBus.skill_offer_closed.emit(idx, picked.get("skill_id", &""), picked.get("mode", &"skipped"))
```

**`_build_cards`** генерирует список вариантов:
- Сэмплируем `count` уникальных скиллов из пула (с учётом weights).
- Для каждого выбранного skill_id определяем доступный `mode`:
  - Если игрок ещё **не имеет** этот скилл → вариант `add`.
  - Если игрок имеет → если `allow_upgrade` и skill_system поддерживает upgrade на следующий level → вариант `upgrade`. Иначе если `allow_replace` → `replace` (требует выбор слота — открывается под-меню). Иначе skip из выборки и пробуем заменить новым.
- Если `exclude_owned=true` — фильтруем все already-owned скиллы из пула перед сэмплированием.
- Если pool < count после фильтров — отдаём сколько есть (UI показывает 1-2 карточки).

**`_open_modal`** — instantiate `scenes/ui/skill_offer_modal.tscn`, передаём cards, `await modal.player_picked` сигнал. Возврат `{skill_id, mode, slot_index}` (slot_index только для `upgrade`/`replace`).

**`_apply_pick`** — вызывает `PlayerSkillSet.add_skill(...)` / `upgrade_slot(...)` / `replace_slot(...)`. Конкретные API имена — уточнить при имплементации (см. risk register).

### 4. Modal UI — `scenes/ui/skill_offer_modal.tscn`

`Control` на `CanvasLayer = 25` (выше DialogueManager на 20 — иначе диалог от 039 перекроет offer). По умолчанию blocks input через `mouse_filter = STOP`.

Раскладка:
```
SkillOfferModal (Control, fullscreen, semi-transparent backdrop)
└── CenterPanel (PanelContainer)
    ├── HeaderLabel: "Choose a skill"  (loc key)
    ├── CardsRow: HBox  [Card1][Card2][Card3]
    └── FooterRow: HBox  [Skip (optional)]
```

Card scene `scenes/ui/skill_offer_card.tscn`:
```
SkillOfferCard (PanelContainer, Button-styled)
├── Icon: TextureRect
├── Name: Label (Skill.name, loc-resolved)
├── ModeBadge: Label  ("ADD" / "UPGRADE LV2" / "REPLACE Q")
├── Mood: HBox of mood-icons (читает Skill.mood)
├── Desc: RichTextLabel (Skill.desc, loc-resolved, BBCode enabled)
└── HoverFX: dim/highlight
```

Click на карточке → emit `card_picked(card_data)`. Skip → emit `card_picked({mode: &"skipped"})`. Modal — `await player_picked` (один сигнал, фасад).

Для `replace` mode — после клика открывается под-выбор слотов (Q/W/E/R), player кликает в слот → возвращается `{skill_id, mode: &"replace", slot_index: 2}`.

**Pause behaviour.** Модалка ставит `get_tree().paused = true` на open, `false` на close. Это пауза рантайма — все timer'ы боя стопятся, диалоги (если открыты) — остаются на месте, но 003 атомарность сцены гарантирует что offer и dialogue не пересекаются (DialogueManager drop'ит на playing).

### 5. Editor UI — config-сабпанель в WavePanel

В `wave_panel.gd` — добавить сворачиваемую секцию «Skill offer for this wave» под существующим header'ом:

```
WavePanel
├── HeaderRow (existing): StatusLabel + Copy/Special/Delete
├── SkillOfferSection (new, collapsible):
│   ├── EnableCheckbox: "Show skill offer after this wave"
│   ├── PoolDropdown: OptionButton (pool ids)
│   ├── CountSpinbox: 1..5
│   ├── AllowUpgradeToggle / AllowReplaceToggle / AllowSkipToggle / ExcludeOwnedToggle
│   └── PreviewBtn: "Preview offer" (открывает модалку с этим pool/config — dev only)
└── TimelineRow (existing)
```

Включение/выключение чекбокса — сетит/удаляет `skill_offer` Dictionary в `waves[active].skill_offer`. Все правки `_mark_dirty()`.

**Маркер на WaveTimeline.** В обоих режимах (EDIT и RUNTIME — игроку видно, чтобы планировать) — иконка-карточка 🎴 (или цвет-точка из `UiTheme.SKILL_OFFER_MARKER`) **в gap'е** между якорем волны i и якорем волны i+1, прижатая к якорю i+1 (т.е. показываем «после волны i будет offer»). На последней волне с offer — справа от якоря.

### 6. Sample content

`data/maps/sample_skill_offer.json`:
- 3 волны.
- Wave 0: turns_to_next=4, no offer.
- Wave 1: turns_to_next=5, `skill_offer={pool: "basic", count: 3, allow_upgrade: true, allow_replace: true, allow_skip: true}`.
- Wave 2: final, no offer.

`data/skill_offer_pools/basic.json` — 6-8 скиллов из существующего `data/skills/`. (Sergey/Egor/Стасян пишут реальный balance pool позже.)

## Acceptance criteria

### Schema & data

- **AC-S1 (LevelData schema).** `waves[i].skill_offer` — optional Dictionary. Per §1 schema. `LevelSerializer` пишет/читает. Default — поле отсутствует (null).
- **AC-S2 (legacy migration).** Старые JSON без `skill_offer` грузятся как «нет offer'а». `sample_waves.json` (024) загружается без правок.
- **AC-S3 (validate).** `LevelData.validate()` проверяет:
  - Если `skill_offer` присутствует и не Dictionary → ERR.
  - `pool` непустая StringName → ERR.
  - `count >= 1` → ERR.
  - boolean поля — bool → WARN.
  - `pool` существует в `data/skill_offer_pools/` → WARN (контент может быть в работе).
- **AC-S4 (pool schema).** `data/skill_offer_pools/basic.json` парсится. `SkillOfferController._scan_pools` логирует loaded count. Битые JSON → warn, не краш.

### Runtime — Controller

- **AC-S5 (autoload registered).** `SkillOfferController` в `project.godot` после `SkillDatabase` (или эквивалент) и `EventBus`.
- **AC-S6 (no-offer pass-through).** Wave с `skill_offer=null` → `wave_cleared` → сразу `wave_about_to_start`. Никаких эмитов offer-сигналов, модалка не открывается.
- **AC-S7 (offer flow).** Wave с `skill_offer` → `wave_cleared` → emit `skill_offer_about_to_open(idx, count, pool_id)` → модалка открывается → пауза → выбор → модалка закрывается → emit `skill_offer_closed(idx, picked, mode)` → пауза снимается → `wave_about_to_start(idx+1)`.
- **AC-S8 (sample pool).** `pool="basic"` сэмплирует `count` скиллов из пула. Все cards имеют валидный `mode` ∈ {add, upgrade, replace}.
- **AC-S9 (no-duplicate sampling).** В одном offer не показываем тот же skill_id дважды.
- **AC-S10 (weights).** Если у `summon_bee` weight=0.5, остальные default=1.0 — за 100 sampling runs `summon_bee` появляется ~33% от ожидаемого base. Не точная стат-проверка, sanity smoke.
- **AC-S11 (apply add).** Игрок без скилла X выбирает «add X» → `PlayerSkillSet.add_skill(X)` (точное API — TBD в имплементации) → следующая волна стартует, X в слотах.
- **AC-S12 (apply upgrade).** Игрок с X.level=0, allow_upgrade=true, выбирает «upgrade X» → X.level=1 после применения. Если skill_system не поддерживает upgrade — fallback в add (или предупреждение в редакторе уже на этапе валидации).
- **AC-S13 (apply replace).** Игрок с X в слоте Q, выбирает «replace Q with Y» → submenu выбора слота → `PlayerSkillSet.replace_slot(Q, Y)` → Y в слоте Q.
- **AC-S14 (skip).** allow_skip=true, кнопка Skip → emit `skill_offer_closed(idx, &"", &"skipped")`. Никаких изменений в skill set.
- **AC-S15 (chained dialog interplay).** Если 039 trigger на `skill_offer_about_to_open` имеет `play_mode=play` → диалог играется **до** открытия модалки. Modal ждёт `dialogue_finished` перед открытием. Аналогично — `skill_offer_closed`-trigger играется после закрытия. Реализуется через `await EventBus.dialogue_finished` в Controller'е если `DialogueManager.is_playing()`.

### Editor UI

- **AC-S16 (wave panel section).** WavePanel показывает «Skill offer» секцию. Per-wave config работает: enable → пул/count/toggles → save → JSON содержит правильную структуру.
- **AC-S17 (pool dropdown live).** Dropdown собран из `_pools.keys()` SkillOfferController'а. При запуске редактора — все pools из `data/skill_offer_pools/*.json` доступны.
- **AC-S18 (preview button).** Preview Btn открывает модалку с текущей конфигурацией (без применения выбора — dev-режим). Полезно для дизайнера-проверки.
- **AC-S19 (timeline marker EDIT).** Маркер 🎴 в gap'е после волны с `skill_offer != null`. Hover-tooltip: «Offer 3 from basic pool».
- **AC-S20 (timeline marker RUNTIME).** Маркер виден в `Mode.RUNTIME` тоже — игрок планирует. Hide-toggle — out_of_scope.
- **AC-S21 (autosave/dirty).** Любая правка `skill_offer` → `_mark_dirty` → autosave. Без правок к существующему `_mark_dirty` пути.
- **AC-S22 (editor controller delta).** Правки `map_editor_controller.gd` ≤ 30 строк (skill offer section живёт **внутри** WavePanel, не нужен новый sibling-resolve).

### Sample smoke

- **AC-S23 (full run).** `sample_skill_offer.json` загружается через Load Custom Level → wave 0 кларится → нет offer → wave 1 → кларится → модалка открывается → выбираем add → wave 2 стартует с новым скиллом в слоте.

## Open questions

- **OQ-1 (PlayerSkillSet API).** Точные методы для add/upgrade/replace — найдутся в имплементации. Если 026/021 не предоставляют — пишем тонкий adapter в `runtime/`, не лезем в core. **Худший случай** — режем upgrade и replace из 040 v1.
- **OQ-2 (Skill upgrade semantics).** Что значит «upgrade» — `level += 1` и компоненты сами реагируют (per 021 §«Прогрессия»)? Или это full swap скилла? Default — `level += 1`. Уточнить с Egor если понадобится.
- **OQ-3 (Skip vs no-skip default).** Дизайнер по умолчанию хочет давать Skip или нет? Default — `allow_skip: false` в JSON (player вынужден выбрать). Если в плейтесте окажется болезненно — стасян/андрей переключают per-wave.
- **OQ-4 (Pool weights в editor).** В v1 редактор не умеет править weights (это редкая задача, делается в JSON руками). Если плейтест покажет частую необходимость — добавим editor.
- **OQ-5 (Offer на финальной волне).** `level_completed` идёт после offer'а финальной волны. Это OK или хотим отдельный «end-of-level reward» режим? Default — обычный offer работает, финальный.

## Out of scope

- **Meta-progression / persistence.** Pick'и не сохраняются между ранами. Если roguelike-loop появится — он будет вызывать другой UI или extender этого.
- **Rerolls / banishes / locked cards.** Один tap = один выбор. Hades-light, не Hades-prime.
- **Conditional offers** (показать определённые скиллы только если у игрока есть Y). v1 — тупо random из пула. Conditions могут идти через `tags` фильтр позже.
- **Dynamic difficulty.** Pool не зависит от score / уровня. Все статично.
- **Localization редактора weights/pools.** UI текст pool dropdown — это just StringName id или `label_key` если задан. Никакой авторской работы в Godot.
- **Drag-drop reorder pool / Edit pool в редакторе.** JSON pool — ручная работа дизайнера/программиста. Editor — только select.
- **Custom card art per skill.** Используем `Skill.icon` (021/026 поле). Если нет — placeholder.
- **Offer animations / VFX.** Простые tween'ы — fade-in/scale, без particles. Polish — отдельно (029).
- **Sound design для offer'а.** AudioDirector dispatch — позже, когда AudioDB ready.
- **PlayerSkillSet itself.** Если такого класса нет в кодовой базе — пишем минимальный wrapper в `runtime/` поверх существующих player slots; НЕ переписываем skill system.

## Зависимости

**Upstream (must merge first):**
- 024-wave-editor — `LevelData.waves[]`, `WaveController`, `WavePanel`. Уже шипнут.
- 020-map-editor — autosave, ConfirmModal. Уже шипнут.
- 007/021/026 skill-system — Skill class, SkillDatabase, player slots. Шипнуты в той или иной форме; точные API ищем при имплементации.

**Soft (degrade gracefully):**
- 039-dialogue-triggers — emits через `skill_offer_about_to_open`/`_closed`. Если 039 не смержен — события эмитятся, никто не слушает, всё ОК.
- 038-mood-counter — recompute на `_apply_pick` после mутации skills (через существующий `sync_player_skills_from_slots` call-site). 038 сам эмитит `player_mood_changed`.

**Coordination:**
- Egor / Sergey — нужен write-API в PlayerSkillSet (или его эквиваленте). Если отсутствует — мы пишем adapter, не правим core. Если adapter упрётся в private fields — короткий разговор, добавляют public method.
- Andrey — wave_about_to_start signal от 039 (уже добавлен в 039 spec). Использовать оттуда.

## Размер

Большая. Riskpoints:
- **PlayerSkillSet API** — может потребовать ad-hoc adapter, ест время.
- **Modal interaction с DialogueManager** — `await dialogue_finished` для chained 039 triggers тестируется только integration-smoke.
- **Replace-slot submenu UX** — добавляет шаг в карточном flow, нужно аккуратно с input pause / unpause.
- **Pool sampling без duplicates на маленьких пулах** (count=3 в pool из 4 скиллов) — corner case, проверить.

Если режется — см. Cut list ниже.

## Cut list

В порядке агрессивности:

1. **Cut allow_replace** — оставить только add + upgrade. Снимает submenu, упрощает modal flow на ~30%.
2. **Cut allow_upgrade** — оставить только add. v1 = pure Hades-light: новый скилл в свободный слот, либо если все слоты заняты — заменяет один на выбор. Снимает зависимость на skill upgrade API.
3. **Cut weights** — все skills в пуле равновероятны. Дизайнер фильтрует руками через состав пула.
4. **Cut Preview button** — designer playtest'ит через Load Custom Level → playtest. Снимает modal-instantiate-from-editor edge case.
5. **Cut RUNTIME timeline marker** — игрок не видит маркеры pick'а на HUD (узнаёт когда модалка открылась). Радикально упрощает таймлайн.

Default ship — без cut'ов. Cut'ы применяются по мере прорисовки времени в имплементации.

## История правок

- 2026-05-03 v1 — Andrey clarify: full Hades-like (pick + upgrade + replace). Schema per-wave в LevelData. Editor — секция в WavePanel + маркер на таймлайне. Localization — text-fields через loc-keys (Sheets-pipeline).
