# Реестр фич

Что в игре есть, в каком оно состоянии, где спека, где код, как проверить.

## Зачем существует

Чтобы за минуту отвечать на три вопроса по любой фиче:

1. Есть ли описанная спецификация?
2. Всё ли работает так как написано?
3. Где посмотреть?

`specs/` — это исторический лог решений (что мы планировали в момент X). `docs/design/` — концептуальная память (почему так). А этот файл — **текущее фактическое состояние**: что из заявленного реально работает прямо сейчас.

## Политика заполнения: lazy backfill

**Реестр пустой и заполняется по мере того как трогаем фичи.** Не тратим день на ретроактивный аудит — много фич будем переписывать, дешевле фиксировать состояние когда руки и так в коде.

Когда добавлять/обновлять запись:
- При мерже спека в staging — заводится новый блок или обновляется существующий.
- При имплементации фичи без спека — заводится блок.
- При баге, который меняет статус ("работало → сломалось") — обновляется поле **Статус** и **Заметки**.
- При обнаружении расхождения "спека сказала / код делает" — обновляется **Заметки**.

Кто обновляет: `@design-keeper` по запросу, или человек руками в том же PR где трогает фичу. Без полиции — если запись отстала, отстала. Главное чтобы она была честной когда обновляется.

## Формат записи

Один блок на фичу. Заголовок — slug (`game-editor`, не `Game Editor`), чтобы был стабильный якорь для ссылок.

```markdown
## <slug>

- **Название:** Человеческое название фичи.
- **Статус:** planned / design / partial / working / stable / broken / deprecated
- **Спек(и):** [`NNN-name`](../specs/NNN-name/) — короткое пояснение если их несколько.
- **Код:** 1-3 главных файла или папки, точка входа в систему.
- **Как проверить:** Воспроизводимые шаги или сценарий. Если есть автотест — ссылка.
- **Дизайн:** Ссылки на `docs/design/...`, `THEME_PLAN.md` секции, `CLAUDE.md` секции.
- **Заметки:** Текущие ограничения, известные баги, расхождения "спека / код", TODO.
```

### Значения статуса

- **planned** — есть спек или идея, кода нет.
- **design** — спек в процессе написания / ревью.
- **partial** — частично работает, не вся спека реализована.
- **working** — основная функциональность работает; могут быть полиш-задачи и мелкие баги.
- **stable** — работает давно, регрессий нет, можно строить поверх.
- **broken** — сломано, нужно чинить (часто после рефакторинга соседей).
- **deprecated** — заменено другой фичей или решено выкинуть; код может ещё жить временно.

Статус — субъективный. "Working" одного человека = "partial" другого. Это нормально, главное чтобы было обновлено.

---

## Реестр

## wave-settings-panel

- **Название:** Wave Settings (правая панель в level editor).
- **Статус:** working
- **Спек(и):** [`061-wave-data-and-settings`](../specs/061-wave-data-and-settings/) — переключатель волн, поля is_special/turns_to_next/respawn_player/advance_mode/music_config, секция спавнеров, skill_offer (порт 040), мirror dialogue triggers этой волны.
- **Код:**
  - `scripts/presentation/dev/wave_settings_panel.gd` — UI;
  - `scripts/presentation/dev/editor/wave_editor_ops.gd` — мутации (статические методы);
  - `scenes/dev/wave_settings_panel.tscn` — сцена (instance of base_panel).
- **Как проверить:** Открыть level editor (Ctrl+E), правая панель «Wave Settings» — вверху список волн с +/Copy/Delete, ниже секции Level / Wave / Spawners / Skill Offer / Dialogue Triggers (this wave). Smoke по T-061-74..77 (spec/061/tasks.md).
- **Дизайн:** [`specs/061-wave-data-and-settings/spec.md`](../specs/061-wave-data-and-settings/spec.md) §3, [`specs/061-wave-data-and-settings/plan.md`](../specs/061-wave-data-and-settings/plan.md) §Φ-4..Φ-8.
- **Заметки:** Файл панели ~1380 LOC (vs soft cap 600) — F-061-IMPL-2, extract отложен до второго consumer'а. Spawner-форма amount/delay полей помечена `(schema-only)` — runtime их игнорит до соответствующей фичи.

## dialogue-triggers-editor

- **Название:** Dialogue Triggers — CRUD внутри Wave Settings.
- **Статус:** working
- **Спек(и):** [`039-dialogue-triggers`](../specs/039-dialogue-triggers/) — оригинал; [`061-wave-data-and-settings`](../specs/061-wave-data-and-settings/) — миграция в WaveSettingsPanel.
- **Код:** `scripts/presentation/dev/wave_settings_panel.gd` (секция Level → Dialogue Triggers + wave-mirror); ops в `wave_editor_ops.gd`.
- **Как проверить:** В level editor открыть Wave Settings → секция «Level → Dialogue Triggers». Add → форма с id / event / dialogue_id / play_mode / conditions. Save → запись появляется в списке. Validate: пустой id → красная ошибка под формой, дубль id → тоже.
- **Дизайн:** [`docs/systems/level-editor/dialogue-triggers.md`](systems/level-editor/dialogue-triggers.md) — designer-facing reference.
- **Заметки:** CURATED_EVENTS — фиксированный список из 8 EventBus сигналов + Custom... для всего остального. Conditions: wave_index/absolute_turn/cleared_in_turns_lt/chance/mood/once_per_run.

## wave-advance-mode

- **Название:** advance_mode runtime gate — timer/clear/timer_and_clear.
- **Статус:** working
- **Спек(и):** [`061-wave-data-and-settings`](../specs/061-wave-data-and-settings/) §3.G.
- **Код:** `scripts/runtime/wave_controller.gd` (`_on_world_turn_ended` match), `scripts/infrastructure/event_bus.gd` (signal `wave_advance_blocked`), `scripts/presentation/ui/wave_timeline.gd` («waiting for clear» label).
- **Как проверить:** Сделать в редакторе волну с advance_mode=clear, без enemy spawner'а — validate WARN. С enemy: запустить playtest, не убивать врага → волна не двигается. Убить → переход. timer_and_clear: дождаться истечения timer → виден label «(waiting for clear)» → убить врага → переход.
- **Дизайн:** [`specs/061-wave-data-and-settings/design.md`](../specs/061-wave-data-and-settings/design.md) §G.
- **Заметки:** Pillar 1 visual cue — outlined string под cursor'ом. Локализация `ui_wave_waiting_for_clear`.

<!--
Шаблон для копирования:

## <slug>

- **Название:**
- **Статус:**
- **Спек(и):**
- **Код:**
- **Как проверить:**
- **Дизайн:**
- **Заметки:**
-->
