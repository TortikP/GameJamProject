# 060 — Findings (during implementation)

Записи неожиданностей, всплывающих по ходу реализации. Не правят спек на ходу — это лог. Когда что-то существенно меняет дизайн, выноси в отдельный спек или PR-комментарий, спроси Андрея.

---

## F-060-IMPL-1 — `_set_active` call sites: plan и код расходятся, переинтерпретирую по принципу спека

**Фаза:** Φ-1 (T-060-1).

**Что нашёл.** Plan в §Φ-1 даёт таблицу `by_user` значений для 5 call sites `_set_active` в `panel_tab_bar.gd`. По факту — 6 call sites (89, 242, 329, 387, 457, **485**), и labels плана для 329/387 не совпадают с тем, что в коде:

| Line | Контекст в коде | Plan label | Plan `by_user` |
|---|---|---|---|
| 89 | `setup()` initial active | "initial setup в `_ready`" | false |
| 242 | `_on_tab_button_gui_input` после клика | "после клика по табу" | true |
| 329 | **`_detach_tab_active_drag` — авто-switch при отрыве таба** | "после reattach detached tab" | true |
| 387 | **`_reattach` — активация реаттаченного таба** | "re-register flow" | false |
| 457 | `register_tab` — первый таб становится активным | "первый таб в `add_tab()` (programmatic)" | false |
| 485 | `unregister_tab` — авто-switch при удалении активного таба | (не в плане) | — |

Plan, видимо, перепутал labels для 329 и 387.

**Что выбрал.** Спек §Φ-1 явно говорит: «**Только** на пользовательский click (не на programmatic restore из persistence)». Применяю этот принцип буквально:

| Line | `by_user` (моё решение) | Обоснование |
|---|---|---|
| 89  | false | Initial setup, не клик |
| 242 | **true** | Единственное место реального user click |
| 329 | false | Tab оторвали → система выбрала next, юзер не выбирал next |
| 387 | false | Reattach — юзер дропнул панель, активация — побочный эффект, не выбор таба |
| 457 | false | Programmatic add_tab |
| 485 | false | Removal triggered cleanup, не user choice |

**Почему так.** Consumer'ы (LayersPanel в Φ-3) подписываются на `active_tab_changed` чтобы синхронизировать `LayersModel.active_layer`. Если detach/reattach эмитят `true` — consumer получит false-positive «юзер сменил слой» когда он на самом деле просто двигал панель. Семантика «активный таб» != семантика «юзер выбрал слой».

**Impact на 060.** Никакого — LayersPanel не использует tear-off в Spec 060 (явно out of scope, spec.md §4). Линии 329/387/485 в 060 не активируются. Решение важно только как precedent для будущих consumers.

**Impact на план.** Plan'овая таблица в §Φ-1 — incorrect. Если позднее кто-то переоткроет вопрос, отсылка сюда.

**Action для Андрея.** Подтверди трактовку. Если нужно «detach/reattach считать user-driven» — flip 329 и 387 на true, мелкое изменение.

---
