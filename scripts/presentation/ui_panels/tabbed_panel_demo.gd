## tabbed_panel_demo — manual smoke harness for spec 058 acceptance.
##
## Hosts three TabbedBasePanel instances and populates them via the
## runtime add_tab API:
##
## - MainTabbed (top-left, 3 tabs) — primary AC1..AC10 target.
## - OtherTabbed (top-right, 1 tab) — AC6: foreign tab-bar rejection.
## - CenteredTabbed (anchored at center) — AC10: anchor normalization
##   on a non-default-anchored parent, plus its detached child.
##
## ## Why programmatic, not .tscn-declarative
##
## In Godot 4, adding child nodes to an instanced subtree via
## `parent="<instance_root>/<inner_path>"` in a .tscn block requires
## an `[editable path="..."]` marker on the host scene and is fragile
## across nested scene instances. Going through TabbedBasePanel.add_tab
## from _ready is the robust path and exercises the runtime half of
## T-058-1 (hybrid API) — which is what consumers would use anyway
## when their tab content is dynamic. See findings.md.

extends Control

@onready var _main_tabbed: TabbedBasePanel = $MainTabbed
@onready var _other_tabbed: TabbedBasePanel = $OtherTabbed
@onready var _centered_tabbed: TabbedBasePanel = $CenteredTabbed


func _ready() -> void:
	_populate_main()
	_populate_other()
	_populate_centered()


func _populate_main() -> void:
	_main_tabbed.add_tab(_make_label("I am tab A"), &"TabA", &"", "Tab A")

	var tab_b := VBoxContainer.new()
	tab_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var btn1 := Button.new()
	btn1.text = "Action 1"
	tab_b.add_child(btn1)
	var btn2 := Button.new()
	btn2.text = "Action 2"
	tab_b.add_child(btn2)
	_main_tabbed.add_tab(tab_b, &"TabB", &"", "Tab B")

	_main_tabbed.add_tab(_make_label("Empty tab C"), &"TabC", &"", "Tab C")


func _populate_other() -> void:
	var foo := _make_label("Other panel — drop here should be rejected")
	foo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_other_tabbed.add_tab(foo, &"Foo", &"", "Foo")


func _populate_centered() -> void:
	var bar := _make_label("Centered panel — non-default anchors\nDetach me to verify AC10")
	bar.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_centered_tabbed.add_tab(bar, &"Bar", &"", "Bar")


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl
