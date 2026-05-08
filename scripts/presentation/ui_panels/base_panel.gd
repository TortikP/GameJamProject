## BasePanel — universal interface window framework root.
##
## Inherited Scenes pattern: subclasses inherit from base_panel.tscn,
## enable Editable Children, place content into BodyContainer.
##
## See:
##   - docs/systems/ui-panels/design.md  (system-level decisions)
##   - specs/055-ui-panels/spec.md       (this implementation)
##
## Layout:
##   - 10 resize handles inside ResizeFrame:
##       Top corners (TopLeft, TopRight) split into _H + _V arms
##       (L-shape outside the visible frame; bottom corners stay 44×44).
##     EDGE_THICKNESS-thick strips on each edge between corners.
##   - The visible header+body frame (VBoxContainer) is inset from the
##     root by EDGE_THICKNESS on all four sides — that 6px gap is where
##     the edge resize strips live.
##   - HeaderPanel contains a single HeaderRow (HBoxContainer):
##     TitleLabel (expand) / Lock / Collapse / RightSpacer (22px, IGNORE).
##     Buttons cluster on the right, offset CORNER_SIZE/2 from the
##     panel's right edge so they don't abut the Right resize handle
##     (1px gap → 23px gap, prevents hit-test bleed). Spacer is
##     mouse-IGNORE so drag still fires on its area via PASS chain.
##     Container layout sets exact button rects; no manual offsets.
##
## Children of BasePanel root, in tscn declaration (= back-to-front):
##   1. ResizeFrame   — 10 Control handles at root corners/edges
##   2. VBoxContainer — HeaderPanel (with HeaderRow) + BodyPanel,
##                      inset 6px from root edges
##
## Mouse routing:
##   - ResizeFrame:    IGNORE (children STOP)
##   - VBoxContainer:  IGNORE
##   - HeaderPanel:    PASS (so drag handler's gui_input fires)
##   - HeaderRow:      PASS (lets clicks fall through to HeaderPanel
##                     for drag, while children Buttons STOP for clicks)
##   - LockButton/CollapseButton: STOP (default for Button)
##   - TitleLabel:     IGNORE (default for Label)
##   - BodyPanel:      PASS
##   - BasePanel root: STOP (catch-all, C5)
##
## Composition handlers (created in _ready, owned as child nodes):
##   - PanelDragHandler     — listens to HeaderPanel.gui_input
##   - PanelResizeHandler   — connects to each of the 10 ResizeFrame handles
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
var _header_row: HBoxContainer
var _title_label: Label
var _body_panel: PanelContainer
var _body_container: MarginContainer
var _resize_frame: Control
var _lock_button: Button
var _collapse_button: Button

# ── Composition handlers (created in _ready, owned as child nodes) ────
var _drag_handler: PanelDragHandler
var _resize_handler: PanelResizeHandler
var _collapse_handler: PanelCollapseHandler
var _lock_handler: PanelLockHandler
var _persistence: PanelPersistence

# Set by _apply_chrome_visibility; consumed by _apply_theme. When true,
# BodyPanel uses make_panel_stylebox() (full 4-side border) instead of
# make_panel_body_stylebox() (no top border).
var _pinned_body_style: bool = false


func _ready() -> void:
	add_to_group(&"ui_panel")
	mouse_filter = Control.MOUSE_FILTER_STOP

	_resolve_nodes()
	_normalize_anchors_to_top_left()
	_compute_effective_flags()
	_apply_chrome_visibility()
	_apply_title()
	_apply_theme()
	_setup_handlers()
	_setup_persistence()

	if not EventBus.ui_theme_reloaded.is_connected(_apply_theme):
		EventBus.ui_theme_reloaded.connect(_apply_theme)

	# C3: clamp on viewport resize. Connected for ALL panels (not only
	# persistable ones) so even ad-hoc panels can't be lost off-screen
	# when the window shrinks. Persistable panels additionally autosave
	# the clamped state via the panel_moved/panel_resized emits below.
	get_viewport().size_changed.connect(_on_viewport_size_changed)


## When header_visible == false, hide every chrome layer (HeaderPanel
## with its row of lock/title/collapse and the entire ResizeFrame).
## A "pinned" panel is just body — no header bar, no resize handles,
## no drag affordance. Cascade in _compute_effective_flags then ensures
## no handlers are created in _setup_handlers either.
##
## Body stylebox: pinned panels swap from make_panel_body_stylebox()
## (no top border — assumes HeaderPanel sits above) to make_panel_stylebox()
## (full 4-side border) so the body has a visible top edge.
func _apply_chrome_visibility() -> void:
	if header_visible:
		return
	if _header_panel != null:
		_header_panel.visible = false
	if _resize_frame != null:
		_resize_frame.visible = false
	# Mark the panel so _apply_theme uses the full-border stylebox on
	# (re)apply. _apply_theme runs after this.
	_pinned_body_style = true
	print("[BasePanel] header_visible=false on '%s' — chrome hidden, all interactions disabled" % String(panel_id))


func _resolve_nodes() -> void:
	_header_panel    = $VBoxContainer/HeaderPanel as PanelContainer
	_header_row      = $VBoxContainer/HeaderPanel/HeaderRow as HBoxContainer
	_title_label     = $VBoxContainer/HeaderPanel/HeaderRow/TitleLabel as Label
	_body_panel      = $VBoxContainer/BodyPanel as PanelContainer
	_body_container  = $VBoxContainer/BodyPanel/BodyContainer as MarginContainer
	_resize_frame    = $ResizeFrame as Control
	_lock_button     = $VBoxContainer/HeaderPanel/HeaderRow/LockButton as Button
	_collapse_button = $VBoxContainer/HeaderPanel/HeaderRow/CollapseButton as Button


## Normalize root anchors to TOP_LEFT with default grow_direction so all
## subsequent position writes (drag, resize, persistence-load, viewport
## clamp) operate in absolute viewport coords.
##
## Why this exists: BasePanel.tscn defaults to PRESET_TOP_LEFT, but
## consuming scenes (map_editor.tscn etc.) routinely override anchors_preset
## to 1/7/11 with non-default `grow_horizontal/vertical` to position panels
## by edge/corner. With those overrides, set_anchors_preset(TOP_LEFT, true)
## inside drag/resize/persistence handlers — even with keep_offsets=true —
## doesn't reliably preserve the visual rect when grow_direction != END
## (Godot 4.6 quirk surfaced in spec 057).
##
## Single source of truth: do the conversion ONCE here, capture-and-restore
## the absolute rect explicitly, set grow_direction back to defaults. After
## this method returns the panel is in the same visual position but with
## TOP_LEFT anchors and END/END grow — so subsequent `position = X` writes
## go where you'd expect.
##
## See spec 057 finding F-057-IMPL-4 for the bug history.
func _normalize_anchors_to_top_left() -> void:
	# Snapshot absolute rect BEFORE touching anchors. global_position is
	# valid here — we're inside _ready() so the node is in the tree.
	var abs_pos: Vector2 = global_position
	var abs_size: Vector2 = size
	# Set anchors WITHOUT keep_offsets — we're about to write everything
	# explicitly, no need for Godot to recompute offsets.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Default grow_direction in case the scene set non-default values.
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END
	# Restore absolute rect.
	global_position = abs_pos
	size = abs_size


func _compute_effective_flags() -> void:
	# Static effective flags from exports + header_visible cascade.
	# When header_visible == false the panel is "pinned" — no chrome,
	# no drag handle, no resize geometry, no collapse/lock buttons —
	# so all 4 interactive features cascade to false regardless of
	# their individual export values (spec 055 §5.4).
	#
	# Lock state is intentionally NOT folded in here — it's runtime-
	# dynamic, checked separately via is_locked() at handler input
	# gates (see panel_drag_handler, panel_resize_handler).
	_effective_draggable   = draggable   and header_visible
	_effective_resizable   = resizable   and header_visible
	_effective_collapsible = collapsible and header_visible
	_effective_lockable    = lockable    and header_visible


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
		# Pinned (no header) → full 4-side border so the body isn't open
		# at the top. Otherwise the standard body stylebox (no top border)
		# is correct because HeaderPanel provides the top edge above it.
		var body_sb: StyleBoxFlat
		if _pinned_body_style:
			body_sb = UiTheme.make_panel_stylebox()
		else:
			body_sb = UiTheme.make_panel_body_stylebox()
		_body_panel.add_theme_stylebox_override("panel", body_sb)
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
	# Defensive: when resize is disabled (export flag OR header_visible
	# cascade), hide the entire ResizeFrame so cursor doesn't change on
	# hover. The resize handler won't be created below to enforce its
	# own visibility — this is where it's done.
	if not _effective_resizable and _resize_frame != null:
		_resize_frame.visible = false

	if _effective_draggable and _header_panel != null:
		_drag_handler = PanelDragHandler.new()
		_drag_handler.name = "_DragHandler"
		add_child(_drag_handler)
		_drag_handler.setup(self, _header_panel)

	if _effective_resizable:
		_resize_handler = PanelResizeHandler.new()
		_resize_handler.name = "_ResizeHandler"
		add_child(_resize_handler)
		_resize_handler.setup(self)

	if _effective_collapsible and _collapse_button != null:
		_collapse_handler = PanelCollapseHandler.new()
		_collapse_handler.name = "_CollapseHandler"
		add_child(_collapse_handler)
		_collapse_handler.setup(self, _collapse_button, _body_panel, _resize_frame)
	elif _collapse_button != null and header_visible:
		# Header still visible (just collapsible disabled by export) →
		# explicitly hide the collapse button. When header_visible=false
		# the whole HeaderPanel is already hidden by
		# _apply_chrome_visibility, so this branch isn't reached.
		_collapse_button.visible = false

	if _effective_lockable and _lock_button != null:
		_lock_handler = PanelLockHandler.new()
		_lock_handler.name = "_LockHandler"
		add_child(_lock_handler)
		_lock_handler.setup(self, _lock_button)
	elif _lock_button != null and header_visible:
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


# ── Phase 6: Persistence + viewport clamps ────────────────────────

## Create the persistence handler and load any saved state for this
## panel_id. Runs after _setup_handlers, so default_locked /
## default_collapsed have already been applied. If layouts.cfg has a
## record, it silently overrides those defaults (emit=false on the
## handler setters → no autosave loop). If not, defaults stay and
## nothing is written until the user touches the panel.
##
## Skipped when persistable=false or panel_id is empty (without a
## stable id we have no key to save under).
func _setup_persistence() -> void:
	if not persistable or panel_id.is_empty():
		return
	_persistence = PanelPersistence.new()
	_persistence.name = "_Persistence"
	add_child(_persistence)
	_persistence.setup(self)


## C3: clamp the panel into the new viewport on window resize.
##
## await process_frame lets Godot settle after a resize batch (Viewport
## can fire size_changed multiple times during a single drag of the
## window edge). Direct property writes plus explicit emits — the
## emits drive the persistence debounce so the clamped state is saved.
##
## Collapsed panels: clamp position only. Their size is the header strip
## (set by PanelCollapseHandler), not user-driven, so we leave it alone.
## The pre_collapse_size is left as-is too — when the user expands, the
## standard expand path runs and that may itself land off-screen, but
## that's a different problem (panel was unusable already at that size).
func _on_viewport_size_changed() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return  # Panel was freed during the await window.
	var vp := get_viewport_rect()
	var header_h: float = float(CORNER_SIZE)

	if is_collapsed():
		var new_pos: Vector2 = PanelClamps.clamp_position_to_viewport(
			position, size, header_h, vp.size)
		if new_pos != position:
			position = new_pos
			panel_moved.emit(new_pos)
		return

	var clamped: Dictionary = PanelClamps.clamp_rect_to_viewport(
		position, size, header_h, min_panel_size, vp.size)
	var new_pos2: Vector2 = clamped["position"]
	var new_size: Vector2 = clamped["size"]
	if new_pos2 != position:
		position = new_pos2
		panel_moved.emit(new_pos2)
	if new_size != size:
		size = new_size
		panel_resized.emit(new_size)
