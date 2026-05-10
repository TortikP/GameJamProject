# 058 — Findings (impl-time)

Surfacing only what's relevant for ревью + наследников по фреймворку.

## F-058-IMPL-1 — `.tscn`-declarative tabs не работают без `[editable path="..."]`

**Контекст:** T-058-1=C декларирует hybrid API: «.tscn-driven дефолт (children of BodyContainer = tabs) + runtime add_tab/remove_tab». В первой итерации демо-сцены табы декларировались через `[node name="TabA" parent="MainTabbed/VBoxContainer/BodyPanel/BodyContainer"]` в `tabbed_panel_demo.tscn`.

**Что выявил smoke:** Все 3 TabbedBasePanel'а в демо рендерили placeholder «(All tabs detached…)» и ноль кнопок. PanelTabBar`._discover_and_register_tabs` находил 0 детей в BodyContainer.

**Корневая причина:** В Godot 4 при instance'е сцены А внутри сцены Б, добавление дочерних нод во внутреннее дерево А через `parent="A_root/inner/path"` в Б требует флага `[editable path="A_root"]` на уровне Б. Без него `[node]` блоки тихо отбрасываются (или применяются к чему-то не тому). У нас был **двойной nesting**: tabbed_base_panel.tscn instance'ит base_panel.tscn → tabbed_panel_demo.tscn instance'ит tabbed_base_panel.tscn → попытка добавить TabA внутрь base_panel.tscn'ского BodyContainer'а через двухуровневый path. Без editable_path — failure mode.

**Что сделано:** Демо переключено на runtime add_tab() в `tabbed_panel_demo.gd._ready`. PanelTabBar остался с поддержкой обоих путей (discovery в setup() работает, register_tab() runtime API работает) — этот фикс не трогал сам PanelTabBar.

**Что не сделано (для ревью / следующей итерации):**
- `.tscn`-declarative half of T-058-1 не верифицирован smoke'ом. Возможны два пути:
  - **(a) Документировать convention:** «Если хочешь .tscn-driven табы, добавь `[editable path="<your_tabbed_panel_name>"]` в свою сцену». Дёшево, но неинтуитивно для авторов.
  - **(b) Spec 058.1 / chore:** переделать `tabbed_base_panel.tscn` как Inherited Scene (а не композицию через instance+script) — Inherited Scenes по дизайну позволяют добавлять детей в субдерево без `editable_path`. Был отвергнут в плане под R7 (Inherited Scene quirks). Возможно стоит вернуться к этому варианту с явным smoke.
  - **(c) Опубликовать только runtime API:** обрезать T-058-1 до runtime-only, отозвать .tscn-driven обещание. Чище но менее удобно для статичных табов.

**Рекомендация:** до старта Spec 059 (`level-editor` consumer'ы TabbedBasePanel) — выбрать путь. Sergey/Egor (hex/skill core потребители) будут авторами .tscn'ов с TabbedBasePanel'ами; их UX страдает в варианте (a).

## F-058-IMPL-2 — R4 mitigation: tree_exited вместо «erase до queue_free»

Уже отражено в commit'е `de1d923` (T004+T005). План говорил «erase synthetic section ДО `queue_free`». PanelPersistence подключён к `tree_exiting`, который fires СИНХРОННО на queue_free и ПЕРЕЗАПИСЫВАЕТ erased section. Fix: `panel.tree_exited.connect(_erase_layout_section.bind(section_key), CONNECT_ONE_SHOT)` — `tree_exited` гарантированно после `tree_exiting` → flush уже отработал → erase удаляет именно то что записал flush.

Acceptance AC8 в смоук-листе должен пройти с этой реализацией одинаково.
