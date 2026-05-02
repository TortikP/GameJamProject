# 038 — Mood counter

**Owner:** Egor
**Status:** Ready for /implement
**Upstream:** 021-skill-system-v2 (`Skill.mood`), 026-skill-system-v3
**Type:** Feature (narrative tracker) + content rename

## Цель

Считать «характер» игрока по тому, какие навыки он сейчас держит на QWER-панели. Канонический mood (`get_dominant()`) потом будет читать выбор реплик в DialogueManager (отдельная задача Никиты, out-of-scope здесь).

Никакого UI и никакого consumer'а в этом спеке — только трекер + сигнал.

## Mood-словарь (канонический)

5 значений. **4 прикрепляются к навыкам, 1 — мета-tie-breaker.**

| mood | на скилле? | смысл |
|---|---|---|
| `neutral` | да | дефолт-характер, all-zero состояние |
| `tranquility` | да | спокойствие/созидание |
| `burnout` | да | разрушение/износ |
| `ascended` | да | отстранённость/вознесение |
| `chimera` | **нет** | ничья между не-нулевыми лидерами |

Канон живёт как `const` на `MoodTracker` — `MOODS_SKILL = [neutral, tranquility, burnout, ascended]`, `MOOD_CHIMERA = chimera`.

## Миграция данных (rename 1:1)

Текущие значения в `data/skills/*.json` (52 файла) → новые:

| было | стало |
|---|---|
| `friendly` (13) | `tranquility` |
| `toxic` (16) | `burnout` |
| `apathetic` (17) | `ascended` |
| `neutral` (1) | `neutral` |

Mass replace по строковому литералу в ключе `"mood"`. Скрипт-однострочник в tasks.md, диф проверяется грепом.

`SkillDatabase` при загрузке делает warn (не reject) на любой mood вне канона — ловим опечатки и забытые скиллы Никиты/Стасяна.

## Контракт `MoodTracker` (autoload)

```gdscript
# scripts/core/narrative/mood_tracker.gd, autoload "MoodTracker"

const MOODS_SKILL: Array[StringName] = [&"neutral", &"tranquility", &"burnout", &"ascended"]
const MOOD_CHIMERA: StringName = &"chimera"

func recompute_from_skills(skills: Array) -> void
func get_counts() -> Dictionary           # копия {StringName: int}, все 4 ключа всегда есть
func get_dominant() -> StringName         # один из 5
```

Эмитится сигнал на EventBus после каждого `recompute_from_skills`:

```gdscript
signal player_mood_changed(counts: Dictionary, dominant: StringName)
```

Сигнал летит **всегда** при recompute, даже если counts не изменились (KISS — пусть consumer фильтрует, если ему надо).

## Правила подсчёта

1. Вход `recompute_from_skills(skills)` — массив `Skill` (не `slot_bar`). Контроллер уже зовёт его deduped через `sync_player_skills_from_slots` — **дубликаты одного и того же Skill instance считаются один раз**. Если Никита захочет per-slot подсчёт — это 2 строчки в контроллере (передавать non-deduped массив), не блокер.
2. Skill с `mood: ["tranquility", "burnout"]` → `+1` к каждому из двух (без 1/N).
3. Mood вне канона на скилле → skip + warn-once.
4. Skill без `mood` (пустой массив) → не вкладывает в счётчик ничего (его «mood-вклад» = 0). Не считается за `neutral`.

## `get_dominant()` — алгоритм

```
max_v = max(counts.values())
if max_v == 0:                # все 4 канона = 0 (нет скиллов / все без mood)
    return neutral
winners = [m for m in MOODS_SKILL if counts[m] == max_v]
if winners.size() > 1:
    return chimera
return winners[0]
```

`neutral` в этом правиле — обычный mood-канал. Если только `neutral=2` и остальные `0` → возвращает `neutral`. Если `neutral=2` и `tranquility=2` → `chimera`. Это симметрично и предсказуемо.

## Точка пересчёта

Один и единственный call-site:

```gdscript
# godmode_controller.gd → sync_player_skills_from_slots(), после player.set_skills(skills):
MoodTracker.recompute_from_skills(skills)
```

Это уже дёргается:
- из `GodmodeSetup` после seed'а слотов на старте,
- из `_on_ability_picker_selected` после смены слота через RMB.

Никаких listener'ов на `EventBus.run_started` / `battle_started` — recompute при пустых слотах сам приведёт к all-zero → `neutral`. State trivially derived from input.

## Acceptance Criteria

- **AC-1**: `MoodTracker` зарегистрирован как autoload в `project.godot` под именем `MoodTracker`. Доступен как `MoodTracker.get_counts()` из любого скрипта.
- **AC-2**: 52 файла `data/skills/*.json` переведены на новый словарь. `grep -r '"friendly"\|"toxic"\|"apathetic"' data/skills/` пусто. Скиллы продолжают грузиться без ошибок.
- **AC-3**: `SkillDatabase` логает warn на каждый mood вне `MOODS_SKILL ∪ {chimera}` (на текущих файлах после миграции — 0 ворнингов).
- **AC-4**: На фреш-старте godmode (4 default-скилла в слотах) `MoodTracker.get_counts()` отдаёт корректную сумму mood-меток этих 4 скиллов; `get_dominant()` соответствует правилу.
- **AC-5**: RMB-замена скилла в слоте триггерит `EventBus.player_mood_changed` ровно один раз с обновлёнными counts.
- **AC-6**: Все слоты пустые → `get_counts() = {neutral:0, tranquility:0, burnout:0, ascended:0}`, `get_dominant() == &"neutral"`.
- **AC-7**: Tie между двумя не-нулевыми → `get_dominant() == &"chimera"`. Один лидер с положительным count → этот лидер.
- **AC-8**: Один и тот же `Skill` instance в двух слотах считается один раз (deduped contract).

## Out of scope

- Consumer в DialogueManager (выбор реплик по mood) — задача Никиты, отдельный спек.
- UI-индикатор текущего mood (debug-overlay, портрет-смена) — не нужен пока никто не попросит.
- Per-enemy mood tracker — у врагов нет панели, не применимо.
- Шкалы/веса/история (затухание во времени, разные веса для skill vs ability) — не запрошено.
- Persistence между ранами — счётчик derived from current slots, восстанавливается тривиально, persist'ить нечего.
- Балансовые правила «какой mood даёт какие реплики» — контент Никиты.
