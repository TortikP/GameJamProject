## BasePanel — universal interface window framework root.
##
## Inherited Scenes pattern: subclasses inherit from base_panel.tscn,
## enable Editable Children, place content into BodyContainer.
##
## See:
##   - docs/systems/ui-panels/design.md  (system-level decisions)
##   - specs/055-ui-panels/spec.md       (this implementation)
##
## Layout (from spec 055 mockup):
##   - 4 corner resize zones (CORNER_SIZE square, FDIAG/BDIAG cursors)
##     anchored to the panel ROOT corners.
##   - 4 edge resize strips between corners (EDGE_THICKNESS thick),
##     anchored to the panel ROOT edges.
##   - The visible header+body frame (VBoxContainer) is inset from the
##     root by EDGE_THICKNESS on all four sides. This is what makes the
##     corner zones visibly stick out past the frame on the two outward-
##     facing sides of each corner, while overlapping the frame on the
##     two inward-facing sides (where lock/collapse buttons sit on top).
##     The 6px gap on each side is exactly where the edge strips live.
##   - Header drag zone fills the top of the header, between corners.
##   - Lock / Collapse buttons sit ON TOP of the corners (own layer in
##     z-order so they always capture their clicks)
##
## Children of BasePanel root, in tscn declaration (= back-to-front):
##   1. ResizeFrame      — 8 Control handles at root corners/edges, drawn
##                         FIRST so VBoxContainer covers the inner overlap
##                         and only the outer parts (sticking past VBox)
##                         remain visible. Click hit area follows visibility:
##                         resize via the L-shape outside the panel + the
##                         6px edge strips.
##   2. VBoxContainer    — HeaderPanel (drag bg) + BodyPanel (body bg),
##                         inset by EDGE_THICKNESS from root edges. Drawn
##                         on top of ResizeFrame, hides handler overlap.
##   3. DragDebug        — yellow rect flush with HeaderPanel rect; gets
##                         T-shape visibility after HeaderButtons cover it.
##   4. HeaderButtons    — LockButton + CollapseButton, each CORNER_SIZE
##                         square, pinned to top-left and top-right of root.
##
## Mouse routing:
##   - HeaderButtons: IGNORE (children STOP)
##   - ResizeFrame:   IGNORE (children STOP)
##   - VBoxContainer: IGNORE (HeaderPanel PASS for drag, BodyPanel PASS)
##   - BasePanel root: STOP (catch-all, C5)
##
## Composition handlers (created in _ready, owned as child nodes):
##   - PanelDragHandler     — listens to HeaderPanel.gui_input
##   - PanelResizeHandler   — connects to each of the 8 ResizeFrame handles
##   - PanelCollapseHandler — toggle CollapseButton; hides BodyPanel and
##                            ResizeFrame; shrinks panel to header-only height
##   - PanelLockHandler     — toggle LockButton; gates drag and resize at
##                            their input handlers via is_locked() checks

class_name BasePanel
extends Control

# ── Geometry constants (mirrored in base_panel.tscn anchors/offsets) ──
const CORNER_SIZE: int    = 44   # corner resize zone size = header height = lock/collapse button size
const EDGE_THICKNESS: int = 6    # edge resize zone thickness = VBox inset from root

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

# ── Constraints. With CORNER_SIZE=44, the panel needs at least 88×88
##    just to fit non-overlapping corners. Default bumped from spec's
##    suggested 120×32 to reflect real layout requirements. ─────────
@export var min_panel_size: Vector2 = Vector2(120, 88)

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
var _header_panel: PanelContainer
var _title_label: Label
var _body_panel: PanelContainer
var _body_container: MarginContainer
var _resize_frame: Control
var _header_buttons: Control
var _lock_button: Button
var _collapse_button: Button

# ── Composition handlers (created in _ready, owned as child nodes) ────
var _drag_handler: PanelDragHandler
var _resize_handler: PanelResizeHandler
var _collapse_handler: PanelCollapseHandler
var _lock_handler: PanelLockHandler


func _ready() -> void:
	add_to_group(&"ui_panel")
	mouse_filter = Control.MOUSE_FILTER_STOP

	_resolve_nodes()
	_compute_effective_flags()
	_apply_title()
	_apply_theme()
	_setup_handlers()

	if not EventBus.ui_theme_reloaded.is_connected(_apply_theme):
		EventBus.ui_theme_reloaded.connect(_apply_theme)


func _resolve_nodes() -> void:
	_header_panel    = $VBoxContainer/HeaderPanel as PanelContainer
	_title_label     = $VBoxContainer/HeaderPanel/TitleLabel as Label
	_body_panel      = $VBoxContainer/BodyPanel as PanelContainer
	_body_container  = $VBoxContainer/BodyPanel/BodyContainer as MarginContainer
	_resize_frame    = $ResizeFrame as Control
	_header_buttons  = $HeaderButtons as Control
	_lock_button     = $HeaderButtons/LockButton as Button
	_collapse_button = $HeaderButtons/CollapseButton as Button


func _compute_effective_flags() -> void:
	# Static effective flags from exports. The header_visible cascade
	# is folded in by Phase 5. Lock state is intentionally NOT folded
	# in here — it's runtime-dynamic, checked separately via
	# is_locked() at handler input gates (see panel_drag_handler,
	# panel_resize_handler). Recomputing on every lock toggle would
	# add complexity for no behavioural gain.
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
	if _header_panel != null:
		_header_panel.add_theme_stylebox_override("panel", UiTheme.make_header_stylebox())
	if _body_panel != null:
		_body_panel.add_theme_stylebox_override("panel", UiTheme.make_panel_body_stylebox())
	if _title_label != null:
		UiTheme.apply_label_kind(_title_label, "header")
		_title_label.add_theme_font_size_override("font_size", UiTheme.FS_HEADER + 2)
	if _lock_button != null:
		UiTheme.apply_button_styling(_lock_button)
		_lock_button.icon = ICON_LOCK_UNLOCKED
		_lock_button.text = ""
	if _collapse_button != null:
		UiTheme.apply_button_styling(_collapse_button)
		_collapse_button.icon = ICON_COLLAPSE_MINUS
		_collapse_button.text = ""


func _setup_handlers() -> void:
	if _effective_draggable and _header_panel != null:
		_drag_handler = PanelDragHandler.new()
		_drag_handler.name = "_DragHandler"
		add_child(_drag_handler)
		_drag_handler.setup(self, _header_panel)

	# Always create resize handler — its setup chooses what to do based
	# on is_resizable() (hides handles when disabled).
	_resize_handler = PanelResizeHandler.new()
	_resize_handler.name = "_ResizeHandler"
	add_child(_resize_handler)
	_resize_handler.setup(self)

	if _effective_collapsible and _collapse_button != null:
		_collapse_handler = PanelCollapseHandler.new()
		_collapse_handler.name = "_CollapseHandler"
		add_child(_collapse_handler)
		_collapse_handler.setup(self, _collapse_button, _body_panel, _resize_frame)
	elif _collapse_button != null:
		_collapse_button.visible = false

	if _effective_lockable and _lock_button != null:
		_lock_handler = PanelLockHandler.new()
		_lock_handler.name = "_LockHandler"
		add_child(_lock_handler)
		_lock_handler.setup(self, _lock_button)
	elif _lock_button != null:
		_lock_button.visible = false

	# Apply defaults. Signals are emitted so visual side-effects (e.g.
	# resize_handler hides ResizeFrame on locked_changed(true)) happen.
	# Persistence in Phase 6 will subscribe AFTER defaults are applied,
	# so these emits won't trigger spurious autosaves.
	if default_locked and _lock_handler != null:
		_lock_handler.set_locked(true)
	if default_collapsed and _collapse_handler != null:
		_collapse_handler.set_collapsed(true)


# ── Public API ─────────────────────────────────────────────────────

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


func is_locked() -> bool:
	return _lock_handler != null and _lock_handler.is_locked()


func is_collapsed() -> bool:
	return _collapse_handler != null and _collapse_handler.is_collapsed()


func toggle_lock() -> void:
	if _lock_handler != null:
		_lock_handler.toggle()


func toggle_collapse() -> void:
	if _collapse_handler != null:
		_collapse_handler.toggle()


func reset_to_defaults() -> void:
	# Phase 6 — restores position/size from .tscn defaults, then applies
	# default_locked / default_collapsed. Used by future UI Catalog preview.
	pass
