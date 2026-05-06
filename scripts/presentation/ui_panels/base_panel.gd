## BasePanel — universal interface window framework root.
##
## Inherited Scenes pattern: subclasses inherit from base_panel.tscn,
## enable Editable Children, and place content into the Body
## (MarginContainer) node. The HeaderBar and ResizeHandles structures
## are part of BasePanel's contract and must not be modified by heirs.
##
## See:
##   - docs/systems/ui-panels/design.md  (system-level decisions)
##   - specs/055-ui-panels/spec.md       (this implementation)
##
## Behaviors are split across composition handlers in internal/.
## BasePanel itself only owns:
##   - Identity exports (panel_id, title, description)
##   - Feature toggles (draggable, resizable, ...)
##   - Defaults (default_locked, default_collapsed)
##   - Effective-flag computation (header_visible cascade)
##   - Group membership (&"ui_panel" for discoverability)
##   - Theme application
##
## All actual drag/resize/collapse/lock/persistence logic lives in
## internal/ handlers, instantiated and wired in _ready().

class_name BasePanel
extends PanelContainer

# ── Icons (16×16 monochrome pixel art, UiTheme.TEXT color) ────────
const ICON_LOCK_UNLOCKED  := preload("res://assets/icons/ui/lock_unlocked.png")
const ICON_LOCK_LOCKED    := preload("res://assets/icons/ui/lock_locked.png")
const ICON_COLLAPSE_MINUS := preload("res://assets/icons/ui/collapse_minus.png")
const ICON_EXPAND_PLUS    := preload("res://assets/icons/ui/expand_plus.png")

# ── Identity ───────────────────────────────────────────────────────
@export var panel_id: StringName = &""
@export var panel_title_key: StringName = &""
@export var panel_title_fallback: String = ""
@export_multiline var panel_description: String = ""

# ── Feature toggles ────────────────────────────────────────────────
@export var header_visible: bool = true
@export var draggable: bool = true
@export var resizable: bool = true
@export var collapsible: bool = true
@export var lockable: bool = true
@export var persistable: bool = true

# ── Defaults (applied when no record in user://layouts.cfg) ────────
@export var default_locked: bool = false
@export var default_collapsed: bool = false

# ── Persistence scope override (otherwise auto-detected) ───────────
@export var persistence_scope_override: StringName = &""

# ── Constraints ────────────────────────────────────────────────────
@export var min_panel_size: Vector2 = Vector2(120, 32)

# ── Signals ────────────────────────────────────────────────────────
signal locked_changed(is_locked: bool)
signal collapsed_changed(is_collapsed: bool)
signal panel_moved(new_position: Vector2)
signal panel_resized(new_size: Vector2)

# ── Effective flags (computed from exports + header_visible cascade) ──
var _effective_draggable: bool = true
var _effective_resizable: bool = true
var _effective_collapsible: bool = true
var _effective_lockable: bool = true

# ── Node references (resolved in _ready) ────────────────────────────
var _header_bar: PanelContainer
var _title_label: Label
var _lock_button: Button
var _collapse_button: Button
var _body_panel: PanelContainer
var _body_container: MarginContainer
var _resize_handles: Control


func _ready() -> void:
	add_to_group(&"ui_panel")
	# C5 — never let a heir or a tweak silently make the panel
	# non-interactive. STOP enforced; a follow-up notification check
	# will be added if cases of override-by-mistake appear.
	mouse_filter = Control.MOUSE_FILTER_STOP

	_resolve_nodes()
	_compute_effective_flags()
	_apply_title()
	_apply_theme()

	if EventBus.ui_theme_reloaded.is_connected(_apply_theme):
		return
	EventBus.ui_theme_reloaded.connect(_apply_theme)


func _resolve_nodes() -> void:
	_header_bar      = $VBoxContainer/HeaderBar      as PanelContainer
	_title_label     = $VBoxContainer/HeaderBar/HBox/TitleLabel  as Label
	_lock_button     = $VBoxContainer/HeaderBar/HBox/LockButton  as Button
	_collapse_button = $VBoxContainer/HeaderBar/HBox/CollapseButton as Button
	_body_panel      = $VBoxContainer/BodyPanel      as PanelContainer
	_body_container  = $VBoxContainer/BodyPanel/BodyContainer  as MarginContainer
	_resize_handles  = $ResizeHandles                as Control


func _compute_effective_flags() -> void:
	# Phase 1: header_visible cascade not yet enforced — heirs see plain
	# export values until Phase 5 wires the cascade. Stub kept here so
	# handler creation in _ready() can reference it now.
	_effective_draggable   = draggable
	_effective_resizable   = resizable
	_effective_collapsible = collapsible
	_effective_lockable    = lockable


func _apply_title() -> void:
	if _title_label == null:
		return
	if not panel_title_key.is_empty():
		_title_label.text = Localization.t(String(panel_title_key), panel_title_fallback)
	else:
		_title_label.text = panel_title_fallback


func _apply_theme() -> void:
	# Outer PanelContainer is intentionally TRANSPARENT — it acts as a
	# layout host only. The window frame is composed from two visible
	# regions, each drawn by its own child PanelContainer:
	#   - HeaderBar: top edge + left/right edges of header strip + 2px
	#     bottom border serving as the header→body separator
	#   - BodyPanel: bottom edge + left/right edges of body region
	# This avoids the nested-bordered-PanelContainers margin gymnastics
	# of earlier attempts. Each region's stylebox draws at its own
	# control rect — no expand_margin, no content_margin tweaks.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	if _header_bar != null:
		_header_bar.add_theme_stylebox_override("panel", UiTheme.make_header_stylebox())
	if _body_panel != null:
		_body_panel.add_theme_stylebox_override("panel", UiTheme.make_panel_body_stylebox())
	if _title_label != null:
		UiTheme.apply_label_kind(_title_label, "header")
		# Title sits a tick larger than the standard "header" label kind
		# so the panel name reads clearly above the +2-px-thick separator.
		_title_label.add_theme_font_size_override("font_size", UiTheme.FS_HEADER + 2)
	if _lock_button != null:
		UiTheme.apply_button_styling(_lock_button)
		# Default icon — handlers in Phase 4 swap to ICON_LOCK_LOCKED on toggle.
		_lock_button.icon = ICON_LOCK_UNLOCKED
		_lock_button.text = ""
	if _collapse_button != null:
		UiTheme.apply_button_styling(_collapse_button)
		# Default icon — handlers in Phase 4 swap to ICON_EXPAND_PLUS on collapse.
		_collapse_button.icon = ICON_COLLAPSE_MINUS
		_collapse_button.text = ""


# ── Public API stubs (implemented in later phases) ─────────────────

func get_body_container() -> MarginContainer:
	return _body_container


func is_draggable() -> bool:
	return _effective_draggable


func is_resizable() -> bool:
	return _effective_resizable


func is_collapsible() -> bool:
	return _effective_collapsible


func is_lockable() -> bool:
	return _effective_lockable


func toggle_lock() -> void:
	# Phase 4 — implemented when PanelLockHandler is wired.
	pass


func toggle_collapse() -> void:
	# Phase 4 — implemented when PanelCollapseHandler is wired.
	pass


func reset_to_defaults() -> void:
	# Phase 6 — restores position/size from .tscn defaults, then applies
	# default_locked / default_collapsed. Used by future UI Catalog preview.
	pass
