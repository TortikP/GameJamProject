# 012-ultrareview — spec

**Owner:** Andrey (claim-on-PR; integration / UX / polish lead per CLAUDE.md)
**Status:** Draft — open for AC review

## Цель

Закончили 11 фич за ~50 часов (001-007, 009-011 — код в staging; 008 — спека). Нужен audit-pass до того как Стасян начинает balance-tuning, а команда — финальный polish-sprint в субботу.

Цель — собрать список нарушений правил `CLAUDE.md`, presentation-coupling, hardcoded content, дублирующейся логики и Godot 4.6 traps в **один документ** (`findings.md`), с severity и owner-tag, чтобы потом точечно разнести по 013+ refactor-PR'ам.

**Read-only.** Этот PR не правит ни строки кода и ни одного JSON. Все фиксы — в 013, 014, ...

Это не «pull-request review» в стиле GitHub — это сводный audit по всему staging как whole, с cross-cutting concerns которые нельзя увидеть в одном PR-ревью (например: «8 файлов в presentation/ имеют hardcoded `font_size` — все надо в `UiTheme`»).

## Зачем сейчас, а не на старте

- Большая часть проблем прорастает на стыке фич (007 ↔ 009 ↔ 011, godmode controller от 004 vs UI Kit от 009, CRT post-fx от 010 на чужие сцены).
- Visibility doctrine добавлена в `CLAUDE.md` ретроспективно (после 009/010) — нужно прогнать audit по всем уже сделанным presentation-файлам, не только новым.
- 008-impl ещё не написан Сергеем — зачищая мусор сейчас, даём ему чище базу.
- Стасян начинает balance в субботу — не должен править hardcoded modifier values если они внезапно остались в `.gd`.
- Cheaper to find dead code на 50-часовой кодбазе, чем на 70-часовой.

## Scope аудита (что покрываем)

| ID | Домен | Источник правила | Объём проверки |
|---|---|---|---|
| **D1** | Core/Presentation isolation | `CLAUDE.md` §Architecture #1-2 | Все `scripts/core/*.gd` — поиск импортов/зависимостей от `scripts/presentation/*` или `scenes/*`. Должно быть 0. |
| **D2** | EventBus discipline | `CLAUDE.md` §Architecture #4 | Все cross-module вызовы — через `EventBus.<signal>` или `EventBus.<signal>.connect`. Прямые `get_node`/`@onready` ссылки на чужой модуль = finding. |
| **D3** | UiTheme — единственный источник стилей | `CLAUDE.md` §Architecture #5 | grep по `scripts/presentation/` на `Color(`, `font_size`, `add_theme_*_override`, raw `StyleBoxFlat.new()` без `UiTheme.X` / `UiTheme.make_*_stylebox()`. Каждое — finding. |
| **D4** | GameSpeed для всех timings | `CLAUDE.md` §Timing #5-6 | grep по всему `scripts/` на `create_timer(<число>)`, `await get_tree().create_timer`, `Tween.tween_*(<число>)`, `await ... timeout` с literal-числом. Должно быть 0 без `GameSpeed.get_value(...)` или `GameSpeed.wait(...)`. |
| **D5** | Content в `data/`, не в коде | `CLAUDE.md` §Content #7-8 | grep по `scripts/core/` и `scripts/presentation/` на: stringized id скиллов/abilities/dialogues, литералы damage values, ability-arrays / modifier-arrays внутри `.gd`. |
| **D6** | Naming conventions | `CLAUDE.md` §Naming | Все новые файлы и `class_name` — соответствие правилам (`snake_case.gd`, `PascalCase` class, `_leading_underscore` private). Сигналы — past tense. |
| **D7** | Visibility doctrine | `CLAUDE.md` §Visibility doctrine | Все файлы из `scripts/presentation/` где рендерится in-world UI (HP, damage telegraph, status, floating combat numbers, overhead labels): hardcoded `font_size`, отсутствие `UiTheme.apply_world_text_outline(label)`, отсутствие `WORLD_TEXT_OUTLINE_*` в custom `_draw()`. Ретроспективная сверка. |
| **D8** | Pillar 1 — Full information visibility | `CLAUDE.md` §Design pillars | Любая логика с потенциалом «hidden damage»: enemy ability cast без telegraph, RNG в core без UI representation, статусы без icon strip, ability preview не отражает реальное поведение. |
| **D9** | Pillar 2 — Player-monster symmetry | `CLAUDE.md` §Design pillars | `Actor` поля и методы — все ли используются и enemy и player. AI — только через те же `grid.move_actor` / `ability.cast`, никаких enemy-only damage paths. Manekin / Player — на одном API. |
| **D10** | Godot 4.6 traps | `CLAUDE.md` §Godot 4.6 traps | Каждая ловушка из таблицы — grep по codebase: `func log(`, `class_name Logger`, `var x := load(`, `var x := <variant_func>`, bash-heredoc артефакты в `.gd`, `Array[CustomClass]` со cross-Variant assignments, `_ready` order risks (вызовы чужих nodes из `_ready` без `is_node_ready` guard). |
| **D11** | Spec ↔ implementation drift | per-spec AC | Для каждого 001-011: сравнить AC из `spec.md` с состоянием staging. Найти AC которые помечены `[x]` но не работают / поменяли поведение. |
| **D12** | Dead code / orphan scenes | n/a | Файлы под `scripts/` и `scenes/` без референсов из остального проекта (поиск `preload(...)`, `instantiate()`, `class_name` usage, scene root references). Кандидаты на удаление в 013+. |

## Acceptance criteria

- **AC-A1**: `specs/012-ultrareview/findings.md` создан, формат — единая таблица + поясняющие секции:
  ```
  | ID | Severity | Domain | File:Line | Описание | Proposed fix | Owner | Refactor PR target |
  ```
  Severity:
  - `P1` — баг / нарушение pillar / hidden damage / падение в рантайме / breaks a CLAUDE.md hard rule.
  - `P2` — нарушение CLAUDE.md правила, не падает, но архитектурный долг.
  - `P3` — косметика, naming, comments, dead code без вреда.
- **AC-A2**: Каждый домен D1-D12 имеет explicit секцию в `findings.md`, даже если нарушений нет (тогда — `Clean. N files checked.`). Доказательство покрытия — что не пропустили домен.
- **AC-A3**: Per-owner summary в начале `findings.md`:
  ```
  | Owner | P1 | P2 | P3 | Total |
  ```
  Owner определяется по prefix'у ветки/спеки feature, в которой родился код. Andrey — bootstrap/ui-kit/dialogue/godmode/crt/actors-info; Egor — hex/skill/abilities; Sergey — pending (008 impl ещё не существует, ничего не аудим); Alexey — n/a (ничего не мерджил); Stasyan — JSON content (data/skills, data/modifiers); Nikita — dialogue content (если уже есть JSON).
- **AC-A4**: Per-spec drift (D11) — секция в `findings.md` для каждого 001-011 с одним из:
  - `Spec ↔ impl: aligned` (AC выполнены, поведение совпадает),
  - `Spec ↔ impl: drift, см. F-NN, F-NN` (со списком нарушений),
  - `Spec ↔ impl: not applicable (docs/spec-only)`.
- **AC-A5**: Refactor PR backlog в конце `findings.md`:
  ```
  ### 013-refactor-wave-1: P1 fixes (must-merge before Saturday polish)
  - F-001 (Egor)
  - F-007 (Andrey)
  ...
  ### 014-refactor-wave-2: P2 architecture cleanup (Saturday morning)
  ...
  ### 015-content-migration: hardcoded → data/ (если найдено)
  ...
  ```
  Правила нарезки:
  - **Один owner на PR.** Не смешиваем.
  - **Один concern на PR.** «UI hardcodes» отдельно от «GameSpeed misses» отдельно от «dead code cleanup».
  - **P1 идёт первым,** в 013. P3 — последним, в самом конце или вовсе после джема.
- **AC-A6**: NO code or content files modified. `git diff staging --stat` после 012 показывает только файлы под `specs/012-ultrareview/` и `specs/013-refactor-wave-1/spec.md` (stub). Если в процессе аудита хочется поправить очевидную опечатку в комменте — **записать как finding, не править здесь.** Дисциплина дороже скорости.
- **AC-A7**: Не выдумывать findings ради количества. Если домен чистый — это валидный результат, написать `Clean. N files checked.` и идти дальше. Лучше короткий честный аудит, чем bloated шум.
- **AC-A8**: Findings — actionable, с конкретными `file:line`. Не «UI вообще не очень», а:
  ```
  presentation/health_bar.gd:42 — hardcoded FONT_SIZE = 9, должен быть UiTheme.BAR_FONT_SIZE_OVERHEAD
  ```
  Если file:line невозможен (концептуальное нарушение pillar'а) — указать минимум 2-3 file paths где симптом виден.

## Out of scope

- **Любые правки кода или JSON** — это 013, 014, ... См. AC-A6.
- **008-impl review** — Сергей ещё не писал, нечего ревьюить. Спеку 008 (как документ) тоже не ревьюим — это работа Сергея/Егора в его PR.
- **Performance profiling** — отдельный concern, не в этом PR. Если что-то страшно лагает — finding в P1, но без бенчмарков, просто факт.
- **Visual polish / art critique** — Катя; обсуждение тонов/палитр — в чате, не в findings.
- **Spec sentence-level редактура** — мы аудитим код против спек, не сами спеки. Опечатки в spec-доках — отдельная нудная работа после джема.
- **CLAUDE.md правила сами по себе** — если правило кажется кривым, это discussion в чате/PR-комментах, не findings. Findings — только нарушения существующих правил.
- **Тесты / unit-test coverage** — у нас их нет и не вводим в этом аудите.
- **Refactor sequencing** — финальный порядок 013/014/...: AC-A5 даёт черновик, но решение «что мерджим первым в субботу утром» — Andrey + Egor перед открытием PR'ов, не в 012.
- **Спек-кит ритуалы** (constitution, prompts, и т.д.) — у нас урезанный adapt'нутый workflow, не строимся в полный spec-kit.

## Зависимости

- **Upstream:**
  - `origin/sergey/spec-008-enemy-ai` смержен в staging (закрытие Q-AI-1..6 + `sergey/HANDOFF.md`). До тех пор аудит не стартует — спека 008 в staging устаревшая, и часть D11-проверок завязана на финальный текст 008.
  - Если Сергей затягивает — Andrey принимает решение: либо ждём, либо аудитим без 008-update со ссылкой `[blocked: open PR]` в D11/008 секции.
- **Downstream:**
  - **013-refactor-wave-1** — берётся из AC-A5 backlog (P1 cluster). Открывается после approval 012.
  - **014, 015, ...** — последующие волны, scope и owner определяются также из AC-A5.
- **Параллельно безопасно:** любая активная feature-branch (008-impl, etc.) не блочится. 012 — только чтение staging.

## Координация

- **Andrey:** owner аудита. Делает проход D1-D12, открывает PR, тэгит каждого owner'a в комментарии PR с фильтром findings по их модулю (или просит Клода это сгенерировать).
- **Egor:** primary reviewer по D1, D2 (архитектура), D9 (symmetry), D10 (traps). Его findings — самые критичные, идут в 013. Если он считает finding не-issue, обсуждаем перед мержем 012.
- **Sergey:** не ревьюер 012 (его кода ещё нет в staging). Будет ревьюером 013+ в части AI/skill, когда 008-impl созреет.
- **Alexey:** ревьюер по D5/D11 в части data/dialogue если DialogueManager engine-side findings всплывут.
- **Nikita:** не ревьюер кода. Возможно фигурирует в findings по dialogue content (грамматика, тон) — отдельной секцией, low priority.
- **Stasyan:** не ревьюер 012. Получает резюме findings по `data/modifiers/`, `data/skills/` отдельным сообщением — backlog для balance-PR.

## Процесс работы (шаги для self / Клода если возьмёт implement)

1. **Снимок staging:** `git pull staging` после мержа 008-update. Зафиксировать SHA — `findings.md` валиден против этого среза.
2. **Систематический проход:** D1 → D12 в порядке, каждый домен — отдельная секция в `findings.md`. Не прыгать между доменами.
3. **Findings — на лету:** не накапливать в голове, фиксировать сразу. ID — `F-001`, `F-002`, ..., no skipping numbers.
4. **Per-owner / per-spec rollup** в конце.
5. **Refactor backlog (AC-A5)** — последняя секция `findings.md`.
6. Коммит, push, тэгнуть owners в PR-комментариях.
7. Каждый owner read-only ревьюит свою часть. Approve или коррекции через PR-комменты.
8. После approval — 012 в staging, 013 стартует от него.

## Что после 012

- **013-refactor-wave-1** — slot уже зарезервирован (`specs/013-refactor-wave-1/spec.md` — stub). Заполняется из AC-A5 backlog после мержа 012.
- Если P1-findings = 0 (повезло, всё чисто) — 013 закрывается без PR, slot remains as «numbered slot consumed», следующая фича — 014.
- Если P1-findings много (тоже вероятно — мы 50 часов писали) — 013 содержит топовые, остальное в 014/015.

---

## TL;DR для команды

> «12 — это аудит, не правки. После него Андрей открывает 013-N с конкретными фиксами, разбитыми по модулям. До тех пор код-base не трогаем — параллельные feature-branch не блочатся.»
