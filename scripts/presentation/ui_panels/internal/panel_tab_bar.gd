## PanelTabBar — tab strip + tear-off / reattach for TabbedBasePanel.
##
## Composition handler. Owned by TabbedBasePanel; lives in HeaderRow at
## position 0, replacing the BasePanel TitleLabel.
##
## ## Responsibilities
##
## - Discover tab Control children of the owner's BodyContainer and
##   render a button per tab.
## - Active-tab visibility toggling (only the active tab Control is
##   visible in BodyContainer).
## - Tear-off: detect drag-beyond-threshold or drag-outside-rect during
##   tab-button press and spawn the tab's content as a standalone
##   BasePanel. Hand off the active drag gesture so the user keeps
##   dragging without an LMB release.
## - Reattach: when a previously-detached BasePanel's drag ends with the
##   cursor over THIS tab-bar (origin only — see Q-058-7 / T-058-2=A),
##   absorb it back as a tab.
## - Persistence: detached panels save layout under a synthetic
##   panel_id "<parent_id>__<tab_id>__detached" via the standard
##   BasePanel persistence path (T-058-4=C). On scene reopen, restore
##   detached state by reading the layouts.cfg directly. On reattach,
##   erase the synthetic section AFTER PanelPersistence._flush_save
##   runs (during tree_exiting), so a tree_exited callback handles it.
## - Empty state placeholder when all tabs are detached.
##
## ## Conventions
##
## - Origin tracking is via Node.set_meta (not exported fields) — keeps
##   the detached panel a plain BasePanel without a subclass for two
##   StringNames. Meta keys: META_ORIGIN_PANEL_ID / META_ORIGIN_TAB_ID.
## - Synthetic panel_id separator is "__" (double underscore). Avoid
##   "__" inside panel_ids and tab_ids to prevent section-key collisions
##   (R8 in spec 058 plan.md). In practice this is a non-issue.
##
## ## Out of scope (058)
##
## - Tab reorder via horizontal drag.
## - Cross-TabbedBasePanel re-homing (drop on a foreign tab-bar).
## - RMB context menu for detach.
## - Persistence of active-tab id (always opens on the first attached tab).

class_name PanelTabBar
extends HBoxContainer

const META_ORIGIN_PANEL_ID := "__origin_panel_id"
const META_ORIGIN_TAB_ID := "__origin_tab_id"
const META_TAB_TITLE_KEY := "tab_title_key"
const META_TAB_TITLE_FALLBACK := "tab_title_fallback"

## Vertical drag distance (pixels) past which a tab-button press is
## promoted to a tear-off gesture. Tear-off also triggers when the
## cursor leaves the tab-bar's global rect during a press.
const VERTICAL_DRAG_THRESHOLD := 30.0

const BASE_PANEL_SCENE := preload("res://scenes/ui/panels/base_panel.tscn")
const LAYOUTS_CFG_PATH := "user://layouts.cfg"

# Tab record: { tab_id: StringName, content: Control, button: Button,
#               title_key: StringName, title_fallback: String,
#               original_index: int, detached: bool }
var _tabbed_panel: TabbedBasePanel
var _tabs: Array[Dictionary] = []
var _active_tab_id: StringName = &""
var _button_group: ButtonGroup
var _placeholder_label: Label

# Active-press tracking for click vs drag disambiguation.
var _pressed_tab_id: StringName = &""
var _press_global_pos: Vector2 = Vector2.ZERO

# Currently floating BasePanel instances (detached children).
var _floating_panels: Array[BasePanel] = []


# ── Signals ───────────────────────────────────────────────────────

## Emitted when the active tab changes due to a genuine user click on a
## tab button. Programmatic / system-driven activations (initial setup,
## persistence restore, detach/reattach side-effects, unregister
## fallthrough) do NOT emit — consumers wire layer-state to user intent,
## not to side-effects of unrelated gestures (see findings F-060-IMPL-1).
##
## Re-emitted by TabbedBasePanel under the same name as a public-facing
## signal; subscribe to the panel, not directly to the tab bar.
signal active_tab_changed(tab_id: StringName)


# ── Setup ─────────────────────────────────────────────────────────

## Single entry-point. Called by TabbedBasePanel after super._ready().
## Sequencing: build placeholder, register tabs, restore any detached
## state from persistence, set initial active tab.
func setup(tabbed_panel: TabbedBasePanel) -> void:
	_tabbed_panel = tabbed_panel
	_button_group = ButtonGroup.new()
	_build_placeholder()
	_discover_and_register_tabs()
	_restore_detached_from_persistence()
	var first_id := _first_attached_tab_id()
	if not first_id.is_empty():
		_set_active(first_id)
	_refresh_placeholder_visibility()


func _build_placeholder() -> void:
	_placeholder_label = Label.new()
	_placeholder_label.name = "_AllDetachedPlaceholder"
	_placeholder_label.text = tr(&"ui_tabs_all_detached_hint")
	_placeholder_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder_label.visible = false
	_placeholder_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_placeholder_label)


func _discover_and_register_tabs() -> void:
	var body := _tabbed_panel.get_body_container()
	if body == null:
		push_warning("[PanelTabBar] no body container on tabbed panel '%s'" % String(_tabbed_panel.panel_id))
		return
	var children := body.get_children()
	for i in children.size():
		var node := children[i] as Control
		if node == null:
			continue
		_register_tab_internal(node, i)


func _register_tab_internal(content: Control, original_index: int) -> void:
	var tab_id := StringName(content.name)
	if tab_id.is_empty():
		push_warning("[PanelTabBar] tab content has empty name; skipping")
		return
	var title_key := StringName(content.get_meta(META_TAB_TITLE_KEY, &""))
	var title_fallback := String(content.get_meta(META_TAB_TITLE_FALLBACK, content.name))

	var button := _make_tab_button(tab_id, title_key, title_fallback)
	add_child(button)
	# Place button before the placeholder. Placeholder lives last.
	if _placeholder_label != null:
		move_child(_placeholder_label, get_child_count() - 1)

	var record := {
		"tab_id": tab_id,
		"content": content,
		"button": button,
		"title_key": title_key,
		"title_fallback": title_fallback,
		"original_index": original_index,
		"detached": false,
	}
	_tabs.append(record)
	# Hide all by default; _set_active will reveal the active one.
	content.visible = false


func _make_tab_button(tab_id: StringName, title_key: StringName, title_fallback: String) -> Button:
	var b := Button.new()
	b.name = "Tab_" + String(tab_id)
	b.toggle_mode = true
	b.button_group = _button_group
	b.focus_mode = Control.FOCUS_NONE
	b.text = title_fallback if title_key.is_empty() else tr(title_key)
	b.gui_input.connect(_on_tab_button_gui_input.bind(tab_id))
	return b


# ── Active-tab management ─────────────────────────────────────────

func _set_active(tab_id: StringName, by_user: bool = false) -> void:
	_active_tab_id = tab_id
	# If the target is detached, the request can't be visually expressed
	# in this strip — its content lives in a floating panel, not in our
	# body. Toggling the visibility loop below would just hide whatever
	# attached tab is currently visible (and reveal nothing), leaving an
	# empty body. _active_tab_id is already updated above (logical active
	# for keyboard semantics + correct initial state on a future
	# reattach), so we can safely bail.
	for record in _tabs:
		if record["tab_id"] == tab_id and bool(record["detached"]):
			if by_user:
				active_tab_changed.emit(tab_id)
			return
	for record in _tabs:
		var is_active: bool = (record["tab_id"] == tab_id) and not record["detached"]
		var content := record["content"] as Control
		var button := record["button"] as Button
		if content != null and is_instance_valid(content) and content.get_parent() == _tabbed_panel.get_body_container():
			content.visible = is_active
		if button != null and is_instance_valid(button):
			button.button_pressed = is_active
	if by_user:
		active_tab_changed.emit(tab_id)


## Public delegate for programmatic tab activation, mainly for keyboard
## shortcuts wired through the TabbedBasePanel.set_active_tab facade.
## by_user defaults false — pass true only from genuine user gestures
## that aren't the click site (which already routes through _set_active
## directly). See active_tab_changed for the policy.
func set_active(tab_id: StringName, by_user: bool = false) -> void:
	_set_active(tab_id, by_user)


func _first_attached_tab_id() -> StringName:
	for record in _tabs:
		if not record["detached"]:
			return record["tab_id"]
	return &""


## Count of tabs whose content is currently inside this strip's body
## (not torn off into a floating panel). Used by _detach_tab_active_drag
## to refuse the last detach and by callers that want to know if the
## strip has any visible tabs at all.
func _attached_tab_count() -> int:
	var n := 0
	for record in _tabs:
		if not bool(record["detached"]):
			n += 1
	return n


## Public read-only view of currently-floating panels (one per
## detached tab). Returns a copy. Used by consumers that need to
## affect floating panels uniformly — e.g. LayersPanel's active-layer
## highlight in spec 060. Pair with the META_ORIGIN_TAB_ID metadata
## on each panel to identify which tab it hosts.
func get_floating_panels() -> Array[BasePanel]:
	return _floating_panels.duplicate()


## Returns true if the tab's content currently lives in this strip's
## body (attached). False if torn off into a floating panel, or if
## tab_id is unknown. Used by LayersPanel to decide whether the main
## or the floating panel hosts a given layer.
func is_tab_attached(tab_id: StringName) -> bool:
	for record in _tabs:
		if record["tab_id"] == tab_id:
			return not bool(record["detached"])
	return false


func _count_attached() -> int:
	var n := 0
	for record in _tabs:
		if not record["detached"]:
			n += 1
	return n


func _refresh_placeholder_visibility() -> void:
	if _placeholder_label == null:
		return
	_placeholder_label.visible = _count_attached() == 0


func _find_tab(tab_id: StringName) -> Dictionary:
	for record in _tabs:
		if record["tab_id"] == tab_id:
			return record
	return {}


# ── Press / drag tracking ─────────────────────────────────────────

## gui_input on tab button. We intercept LMB-press to start a drag-or-
## click gesture. _input (global) handles motion + release while
## _pressed_tab_id is set.
func _on_tab_button_gui_input(event: InputEvent, tab_id: StringName) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			# R5/R6: ignore tab interaction when parent is collapsed/locked.
			if _tabbed_panel.is_collapsed() or _tabbed_panel.is_locked():
				accept_event()
				return
			_pressed_tab_id = tab_id
			_press_global_pos = mb.global_position
			# Don't accept_event — let Button show its press visual.


func _input(event: InputEvent) -> void:
	if _pressed_tab_id.is_empty():
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var dy := mm.global_position.y - _press_global_pos.y
		var outside_rect := not get_global_rect().has_point(mm.global_position)
		if dy > VERTICAL_DRAG_THRESHOLD or outside_rect:
			var tab_id := _pressed_tab_id
			_pressed_tab_id = &""
			_detach_tab_active_drag(tab_id, mm.global_position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			# Release without threshold cross. If still over the original
			# tab-button's rect → it's a click → activate. Otherwise no-op
			# (slipped off without crossing detach threshold).
			var record := _find_tab(_pressed_tab_id)
			_pressed_tab_id = &""
			if record.is_empty():
				return
			var button := record["button"] as Button
			if button != null and button.get_global_rect().has_point(mb.global_position):
				_set_active(record["tab_id"], true)


# ── Tear-off ──────────────────────────────────────────────────────

## Active-drag detach: spawn a BasePanel with the tab's content, set up
## meta+persistence, and hand off the drag gesture so it continues
## without an LMB release.
func _detach_tab_active_drag(tab_id: StringName, mouse_global: Vector2) -> void:
	# Block detach of the last attached tab — leaving the parent panel
	# empty creates 1+ floating panels with one shell, which is just
	# clutter. User can drag the tabbed panel itself instead.
	if _attached_tab_count() <= 1:
		return
	var detached := _spawn_detached(tab_id)
	if detached == null:
		return
	# Position so the cursor lands over the new header (~40px from left,
	# centered vertically on the header strip).
	detached.position = mouse_global - Vector2(40.0, BasePanel.CORNER_SIZE / 2.0)
	# Hand off the drag — begin_drag_at also snaps the panel to cursor
	# synchronously (R1 mitigation in PanelDragHandler.begin_drag_at).
	detached.start_drag_at(mouse_global)


## Silent detach: used at scene-load time when persistence has a
## synthetic section. Position/size come from PanelPersistence.load_layout
## during the spawned panel's _ready. No drag handoff.
func _detach_tab_silent(tab_id: StringName) -> void:
	_spawn_detached(tab_id)


## Common detach pipeline. Returns the spawned BasePanel, or null on
## failure (tab not found / content missing).
func _spawn_detached(tab_id: StringName) -> BasePanel:
	var record := _find_tab(tab_id)
	if record.is_empty():
		push_warning("[PanelTabBar] detach: unknown tab_id '%s'" % String(tab_id))
		return null
	if record["detached"]:
		# Already detached (e.g. restoration tried to spawn an existing one).
		return null
	var content := record["content"] as Control
	if content == null or not is_instance_valid(content):
		push_warning("[PanelTabBar] detach: missing content for tab '%s'" % String(tab_id))
		return null

	var detached := BASE_PANEL_SCENE.instantiate() as BasePanel
	detached.panel_id = _synthetic_panel_id(tab_id)
	detached.panel_title_key = record["title_key"]
	detached.panel_title_fallback = record["title_fallback"]
	# 280×360 accommodates the 72×72 icon palettes (~3 columns × 4 rows
	# of 72 + chrome). The previous 180×120 default was too small for
	# the icon-mode palettes — content overflowed past panel bounds and
	# the resize handles at the right/bottom edges were covered by body
	# content, making the floating panel feel unresizable.
	detached.min_panel_size = Vector2(280, 360)
	detached.set_meta(META_ORIGIN_PANEL_ID, _tabbed_panel.panel_id)
	detached.set_meta(META_ORIGIN_TAB_ID, tab_id)

	# Add to the tabbed panel's parent so detached panels live as siblings
	# (and share persistence scope — same ancestor scene_file_path).
	var host := _tabbed_panel.get_parent()
	if host == null:
		push_warning("[PanelTabBar] detach: tabbed panel has no parent")
		return null
	host.add_child(detached)
	# detached._ready has now run: anchors normalized, persistence loaded
	# (which may have set position/size from a saved synthetic section).
	# A persisted size from before this commit's min bump (or the tscn
	# 300×200 default if no persistence) might leave size below the new
	# min — force up so resize handles aren't covered by overflow.
	if detached.size.x < detached.min_panel_size.x:
		detached.size.x = detached.min_panel_size.x
	if detached.size.y < detached.min_panel_size.y:
		detached.size.y = detached.min_panel_size.y

	# Reparent the tab content into the detached panel's body.
	var body := _tabbed_panel.get_body_container()
	body.remove_child(content)
	detached.get_body_container().add_child(content)
	content.visible = true

	# Subscribe to drag end for reattach detection. _drag_handler is
	# always present on a default-exports BasePanel instantiated here,
	# but guard defensively in case future flags disable drag.
	if detached._drag_handler != null:
		detached._drag_handler.drag_ended.connect(_on_floating_drag_ended.bind(detached))
	else:
		push_warning("[PanelTabBar] detached panel has no drag_handler — reattach disabled for tab '%s'"
			% String(tab_id))

	# Hide the tab-button while detached; mark record.
	var button := record["button"] as Button
	if button != null:
		button.visible = false
	record["detached"] = true

	_floating_panels.append(detached)

	# Switch active to whichever tab remains attached.
	var next_active := _first_attached_tab_id()
	if not next_active.is_empty():
		_set_active(next_active)
	_refresh_placeholder_visibility()

	return detached


# ── Reattach ──────────────────────────────────────────────────────

## Wired per detached panel. Fires on LMB release at end of any drag of
## the floating panel. If release is over THIS tab-bar (origin only,
## per T-058-2=A), reattach. Foreign tab-bars get nothing — symmetric:
## they only listen to their own _floating_panels (Q-058-7 + AC6).
func _on_floating_drag_ended(release_pos: Vector2, panel: BasePanel) -> void:
	if not is_instance_valid(panel):
		return
	if get_global_rect().has_point(release_pos):
		_reattach(panel)


func _reattach(panel: BasePanel) -> void:
	var tab_id := StringName(panel.get_meta(META_ORIGIN_TAB_ID, &""))
	if tab_id.is_empty():
		push_warning("[PanelTabBar] reattach: missing __origin_tab_id meta")
		return
	var record := _find_tab(tab_id)
	if record.is_empty():
		push_warning("[PanelTabBar] reattach: unknown origin tab_id '%s'" % String(tab_id))
		return

	# Reparent content back to the tabbed panel's body before freeing
	# the detached shell (so we don't free the content along with it).
	var content := record["content"] as Control
	if content != null and is_instance_valid(content) and content.get_parent() == panel.get_body_container():
		panel.get_body_container().remove_child(content)
		var body := _tabbed_panel.get_body_container()
		body.add_child(content)
		# Restore original position in body if possible.
		var idx: int = mini(int(record["original_index"]), body.get_child_count() - 1)
		if idx >= 0:
			body.move_child(content, idx)

	# Restore the tab-button visibility.
	var button := record["button"] as Button
	if button != null and is_instance_valid(button):
		button.visible = true
	record["detached"] = false

	# CRITICAL ORDER (R4 in spec 058 plan.md, refined): PanelPersistence
	# is connected to panel.tree_exiting and will _flush_save() the
	# synthetic section synchronously when the panel leaves the tree.
	# tree_exited fires AFTER tree_exiting; erasing there guarantees we
	# remove what _flush_save just wrote.
	var section_key := _layout_section_key(panel.panel_id)
	panel.tree_exited.connect(_erase_layout_section.bind(section_key), CONNECT_ONE_SHOT)

	_floating_panels.erase(panel)
	panel.queue_free()

	_set_active(tab_id)
	_refresh_placeholder_visibility()


# ── Persistence helpers (direct ConfigFile access) ────────────────

## Mirrors PanelPersistence._compute_section_key for our synthetic ids.
## Scope = tabbed_panel.persistence_scope_override if set, else walk up
## from the tabbed panel's parent looking for a non-empty scene_file_path.
func _layout_section_key(synthetic_id: StringName) -> String:
	var scope: String
	if _tabbed_panel != null and not _tabbed_panel.persistence_scope_override.is_empty():
		scope = String(_tabbed_panel.persistence_scope_override)
	else:
		scope = _find_ancestor_scene_path()
	return "%s::%s" % [scope, String(synthetic_id)]


func _find_ancestor_scene_path() -> String:
	var node: Node = _tabbed_panel.get_parent() if _tabbed_panel != null else null
	while node != null:
		if node.scene_file_path != "":
			return node.scene_file_path
		node = node.get_parent()
	return "unknown"


func _synthetic_panel_id(tab_id: StringName) -> StringName:
	return StringName("%s__%s__detached" % [String(_tabbed_panel.panel_id), String(tab_id)])


## Read layouts.cfg directly to discover saved synthetic sections.
## For each registered tab, if a synthetic section exists, spawn a
## detached panel without drag handoff (load-time path).
func _restore_detached_from_persistence() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(LAYOUTS_CFG_PATH)
	if err != OK:
		return
	# Iterate over a copy: _detach_tab_silent mutates _tabs flags.
	var tab_ids: Array[StringName] = []
	for record in _tabs:
		tab_ids.append(record["tab_id"])
	for tab_id in tab_ids:
		var section_key := _layout_section_key(_synthetic_panel_id(tab_id))
		if cfg.has_section(section_key):
			_detach_tab_silent(tab_id)


func _erase_layout_section(section_key: String) -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(LAYOUTS_CFG_PATH)
	if err != OK:
		# Nothing to erase if the file doesn't exist.
		return
	if cfg.has_section(section_key):
		cfg.erase_section(section_key)
		var save_err: int = cfg.save(LAYOUTS_CFG_PATH)
		if save_err != OK:
			push_warning("[PanelTabBar] erase save failed (err=%d) at %s"
				% [save_err, ProjectSettings.globalize_path(LAYOUTS_CFG_PATH)])


# ── Public runtime API (called via TabbedBasePanel facade) ────────

func register_tab(content: Control) -> void:
	# Caller has already added content to body. Append at the end.
	var idx := _tabbed_panel.get_body_container().get_child_count() - 1
	_register_tab_internal(content, idx)
	if _active_tab_id.is_empty():
		_set_active(StringName(content.name))
	_refresh_placeholder_visibility()


func unregister_tab(tab_id: StringName) -> void:
	var record := _find_tab(tab_id)
	if record.is_empty():
		return
	# If currently detached, free the floating panel first.
	if record["detached"]:
		for panel in _floating_panels.duplicate():
			if StringName(panel.get_meta(META_ORIGIN_TAB_ID, &"")) == tab_id:
				var section_key := _layout_section_key(panel.panel_id)
				panel.tree_exited.connect(_erase_layout_section.bind(section_key), CONNECT_ONE_SHOT)
				_floating_panels.erase(panel)
				panel.queue_free()
				break
	# Free button + content.
	var button := record["button"] as Button
	if button != null and is_instance_valid(button):
		button.queue_free()
	var content := record["content"] as Control
	if content != null and is_instance_valid(content):
		content.queue_free()
	_tabs.erase(record)
	if _active_tab_id == tab_id:
		var next := _first_attached_tab_id()
		if not next.is_empty():
			_set_active(next)
		else:
			_active_tab_id = &""
	_refresh_placeholder_visibility()


func get_active_tab_id() -> StringName:
	return _active_tab_id
