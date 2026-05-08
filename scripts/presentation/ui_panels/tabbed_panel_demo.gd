## tabbed_panel_demo — manual smoke harness for spec 058 acceptance.
##
## Hosts three TabbedBasePanel instances:
##
## - MainTabbed (top-left, 3 tabs) — primary AC1..AC10 target.
## - OtherTabbed (top-right, 1 tab) — AC6: foreign tab-bar rejection.
## - CenteredTabbed (anchored at center) — AC10: anchor normalization
##   on a non-default-anchored parent, plus its detached child.

extends Control
