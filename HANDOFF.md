# HANDOFF — Spec 061

**Branch:** `andrey/061-wave-data-and-settings`, +31 коммитов на staging.
**Статус:** ждёт смоков от Andrey, потом обновить PR.md и открыть PR.

**Известный баг (не блокер, в `docs/tech-debt.md` как F-061-2):** ресайз LevelMetaPanel не работает. Состояние BasePanel идентично рабочим панелям. Не копать без точечной инструментации `panel_resize_handler.gd`.

**Подводные камни этой сессии (не наступать):** питон-replace по multi-line — проверять каждое место, не только count; в .tscn чужих рабочих панелей не лезть; `PanelDragHandler` — Node, не Control.
