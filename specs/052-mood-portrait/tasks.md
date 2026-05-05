# 052 — Tasks

Все правки в одном файле — `scripts/presentation/dialogue_panel.gd`.

- [x] **T001** — Добавить `const PLAYER_SPEAKER`, `const MOOD_PORTRAIT`, `var _dominant_mood: StringName = &"neutral"` после блока `enum State { ... }` / `@onready` deklarations. См. plan.md §"Implementation sketch".

- [x] **T002** — В `_ready()` добавить:
  - `EventBus.player_mood_changed.connect(_on_player_mood_changed)`
  - Initial sync через `get_node_or_null("/root/MoodTracker")` под if-guard'ом (defensive против сцен без MoodTracker).

- [x] **T003** — Добавить handler `_on_player_mood_changed(_counts: Dictionary, dominant: StringName) -> void` — простой ассайн `_dominant_mood = dominant`.

- [x] **T004** — Переписать `_resolve_portrait(line, speaker_data)` в 4-шаговую priority-chain:
  1. line.portrait
  2. mood-маппинг (только если `line.speaker == PLAYER_SPEAKER`)
  3. speaker_data.default_portrait
  4. _make_placeholder
  
  `line.speaker` уже `StringName` — сравниваем напрямую с `PLAYER_SPEAKER` без `String(...)`.

- [ ] **T005** — Smoke-test (Egor, в editor'е):
  1. Запустить godmode → fresh start (4 default-скилла) → проверить лог MoodTracker (`info | dominant=…`).
  2. Открыть/триггернуть реплику с `speaker: "heroine"` (например, `data/dialogues/intro_office_monologue.json`).
  3. Глазом сверить портрет с маппингом (`tranquility → forest`, `burnout → fire`, `ascended → heaven`, `neutral`/`chimera` → default).
  4. Сменить скилл RMB → лог `MoodTracker.warn DOMINANT … → …` → следующая реплика обновляет портрет.
  5. Триггернуть narrator/rival реплику → портрет не зависит от mood (placeholder/default).

- [ ] **T006** — Если smoke прошёл — push branch, запостить PR-URL Егору.
