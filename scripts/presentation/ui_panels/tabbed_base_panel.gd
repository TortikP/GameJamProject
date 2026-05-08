## TabbedBasePanel — opt-in subclass of BasePanel that replaces the
## title with a tab strip and supports tear-off / reattach.
##
## Use this instead of BasePanel when you need multiple sections of
## content sharing a single panel chrome (window). For single-section
## panels — use BasePanel directly. ~80% of panels are single-section
## and don't need this overhead (Q-058-6 in spec 058).
##
## ## .tscn-driven default
##
## In the editor, add child Controls to the panel's BodyContainer. Each
## child becomes a tab. Tab title sources, in priority order:
##   1. node.get_meta("tab_title_key") — StringName, used with tr().
##   2. node.get_meta("tab_title_fallback") — String, used as-is.
##   3. node.name — fallback.
##
## ## Runtime API
##
## - add_tab(content, tab_id, title_key=&"", title_fallback="")
## - remove_tab(tab_id)
## - get_active_tab_id() -> StringName
## - set_active_tab(tab_id) — programmatic switch (no signal)
## - signal active_tab_changed(tab_id) — user click only
##
## ## Persistence
##
## Detached tabs save layout under a synthetic panel_id of the form
## "<this.panel_id>__<tab_id>__detached" via the standard BasePanel
## persistence path. See PanelTabBar for details (T-058-4=C).

class_name TabbedBasePanel
extends BasePanel

const PANEL_TAB_BAR_SCRIPT := preload("res://scripts/presentation/ui_panels/internal/panel_tab_bar.gd")

var _tab_bar: PanelTabBar

## Re-emit of PanelTabBar.active_tab_changed. Fires only for genuine
## user clicks on a tab button (see PanelTabBar comment for what is
## intentionally excluded). Subscribe here, not on _tab_bar directly —
## _tab_bar is internal and may be replaced.
signal active_tab_changed(tab_id: StringName)


func _ready() -> void:
	# CRITICAL: super._ready() FIRST. BasePanel does node resolution,
	# anchor normalization, theme application, and handler setup in this
	# order. _setup_tab_bar reaches into _header_row / _body_container
	# which only exist after _resolve_nodes runs (CLAUDE.md trap row).
	super._ready()
	_setup_tab_bar()


func _setup_tab_bar() -> void:
	# Hide the inherited title — tabs ARE the panel's identity now.
	if _title_label != null:
		_title_label.visible = false

	_tab_bar = PanelTabBar.new()
	_tab_bar.name = "TabBar"
	_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_bar.size_flags_vertical = Control.SIZE_FILL
	_header_row.add_child(_tab_bar)
	# HeaderRow children order: [TitleLabel, LockButton, CollapseButton,
	# RightSpacer]. Move TabBar to position 0 so it expands at the left.
	_header_row.move_child(_tab_bar, 0)
	_tab_bar.setup(self)
	# Re-emit user-driven tab changes as the panel's own signal so
	# consumers don't need to know about the internal tab bar.
	_tab_bar.active_tab_changed.connect(func(tab_id: StringName) -> void: active_tab_changed.emit(tab_id))


# ── Public runtime API ────────────────────────────────────────────

## Programmatic tab insertion. Sets meta on `content` so PanelTabBar
## resolves the title the same way as for .tscn-defined tabs, names
## the node from tab_id (PanelTabBar derives tab_id from node.name),
## adds it to the body, and registers it in the tab strip.
func add_tab(content: Control, tab_id: StringName, title_key: StringName = &"", title_fallback: String = "") -> void:
	if not title_key.is_empty():
		content.set_meta(PanelTabBar.META_TAB_TITLE_KEY, title_key)
	if not title_fallback.is_empty():
		content.set_meta(PanelTabBar.META_TAB_TITLE_FALLBACK, title_fallback)
	content.name = String(tab_id)
	_body_container.add_child(content)
	if _tab_bar != null:
		_tab_bar.register_tab(content)


func remove_tab(tab_id: StringName) -> void:
	if _tab_bar != null:
		_tab_bar.unregister_tab(tab_id)


func get_active_tab_id() -> StringName:
	if _tab_bar == null:
		return &""
	return _tab_bar.get_active_tab_id()


## Programmatic active-tab switch (e.g. keyboard shortcuts in
## EditorController). Does NOT emit active_tab_changed — that signal is
## reserved for genuine user clicks. Callers that drive layer state via
## both UI and keyboard should call notify_active_layer_changed (or
## equivalent) themselves.
func set_active_tab(tab_id: StringName) -> void:
	if _tab_bar != null:
		_tab_bar.set_active(tab_id, false)
