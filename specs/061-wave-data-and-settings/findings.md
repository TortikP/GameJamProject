# 061 — Findings (during implementation)

Лог неожиданностей, всплывающих по ходу реализации. Не правят спек на ходу — это лог. Когда что-то существенно меняет дизайн, выноси в отдельный спек или PR-комментарий, спроси Андрея.

---

## F-061-IMPL-1 — `is_special` cast в самом `level_data.gd` пропущен в audit'е Φ-2

**Фаза:** Φ-0 recon (T-061-3).

**Что нашёл.** Grep `is_special` нашёл все ожидаемые точки из `plan.md` §Φ-2 (wave_timeline, skill_offer_smoke), плюс `wave_controller.gd:142,145` из spec §5.2. Но **в самом `level_data.gd` ещё две точки с `bool(...)` cast'ом**, которые spec/plan не выделяет отдельно:

| Файл | Строка | Текущее | Что произойдёт после Φ-1 миграции |
|---|---:|---|---|
| `scripts/core/maps/level_data.gd` | 517 | `"is_special": bool(d.get("is_special", false))` в `_wave_dict_from_arr` | На v3-файле `bool("normal") = true` → миграция-блок видит bool=true → перезаписывает в `"boss"`. **Каждый reload v3-файла превращает все "normal" волны в "boss".** |
| `scripts/core/maps/level_data.gd` | 274 | `"is_special": bool(w.get("is_special", false))` в `to_dict` | После Φ-1 in-memory is_special — String. `bool("boss") = true`, `bool("normal") = true` → JSON всегда `true`. **Save'ит всегда bool, теряет string fidelity. Roundtrip ломается.** |

Это не «аудит-точка из Φ-2» (Φ-2 — про runtime-консьюмеров), а блокер для **Φ-1 самого**. Если T-061-7 (миграция в `from_dict`) идёт без правки строк 517 и 274 — миграция работает только на первом save'е v2-файла, на втором reload'е возникает corruption.

**Что делать в Φ-1:**
- **T-061-8** (`_wave_dict_from_arr`): убрать `bool()` cast на `is_special` — читать raw value: `"is_special": d.get("is_special", DEFAULT_IS_SPECIAL)`. Migration block в `from_dict` нормализует тип после.
- **T-061-10** (`to_dict`): заменить `bool(w.get("is_special", false))` на `String(w.get("is_special", DEFAULT_IS_SPECIAL))`. После Φ-1 in-memory `is_special` гарантированно String (миграция гарантирует), но `String(...)` cast — defensive против любого пути, который может ещё положить bool в memory dict.

**Дополнительно (некритично, но в той же тематике):**
- Line 324 (legacy v1 fallback в `from_dict`): `"is_special": false` → `"is_special": DEFAULT_IS_SPECIAL` для согласованности.
- Line 361 (`make_wave_copy_no_spawners`): `"is_special": false` — покрывается T-061-6, но в нынешней формулировке task'а не очевидно что нужна замена литерала. **Уточнить в имплементации:** new value = `String(src.get("is_special", DEFAULT_IS_SPECIAL))` (наследует от source) ИЛИ `DEFAULT_IS_SPECIAL` (всегда normal). Spec/plan не уточняет — выбираю **наследование от source** (логика «копия» предполагает копировать metadata).
- Line 372-376 (`snapshot_root_as_wave`, параметр `is_special: bool = false`): **функция dead code** (zero callers). Можно либо обновить сигнатуру до `String = "normal"`, либо удалить функцию. Defer — отдельный chore-коммит, не часть 061.

**Impact на план.** Не меняет фазы/тасковую структуру. T-061-7 формулировка в `tasks.md` не меняется (миграционный блок остаётся). T-061-8 и T-061-10 — нужны ровно те же task'и, но с этим findings'ом в виду. Добавляю как риск-anchor в коммите Φ-1.

**Impact на спек.** Никакого — спек §5.2 уже упоминает `level_data.gd` как изменяемый файл с расширением сериализации. Просто конкретика реализации.

---
