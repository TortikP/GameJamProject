## PanelPersistence — save/load BasePanel layout state via ConfigFile.
##
## Composition handler. Owned by BasePanel; not a public API.
##
## Storage: user://layouts.cfg, sections "<scope>::<panel_id>".
## Scope = base_panel.persistence_scope_override (if non-empty) else
## the nearest ancestor scene_file_path. See _find_ancestor_scene_path
## for the inherited-scenes subtlety.
##
## Per-section keys:
##   position    Vector2  — panel global position (top-left)
##   size        Vector2  — EXPANDED size (pre_collapse_size if collapsed
##                          at save time, so expand restores correctly)
##   locked      bool
##   collapsed   bool
##
## Meta:
##   [meta] version = 1
##
## Save is debounced (DEBOUNCE_SEC). Each panel_moved / panel_resized /
## locked_changed / collapsed_changed restarts the timer. On panel
## tree_exiting, _flush_save runs synchronously (R4 — don't lose the
## last move on scene change).
##
## Load (load_layout):
##   1. Validate version.
##   2. Apply position (with TOP_LEFT anchor preset).
##   3. Ensure expanded so size write hits the expanded form.
##   4. Apply size.
##   5. C4 clamp to viewport — if values were saved on a larger monitor
##      they get reduced. Clamp result is persisted immediately so the
##      next load doesn't re-clamp.
##   6. Re-collapse if saved as collapsed (captures just-set size as
##      _pre_collapse_size).
##   7. Apply lock state (silent — emit=false on the handler setter).
##
## Loading uses `emit=false` setters and direct property writes so the
## debounce doesn't fire from load itself. The _loading guard is a
## belt-and-suspenders against any emit path that might creep in.

class_name PanelPersistence
extends Node

const CFG_PATH := "user://layouts.cfg"
const META_SECTION := "meta"
const VERSION_KEY := "version"
const VERSION := 1

# Debounce delay (seconds) between a state change and the save write.
const DEBOUNCE_SEC := 1.0

var _base_panel: BasePanel
var _section_key: String = ""
var _debounce_timer: Timer
var _loading: bool = false


func setup(base_panel: BasePanel) -> void:
	_base_panel = base_panel
	_section_key = _compute_section_key()

	_debounce_timer = Timer.new()
	_debounce_timer.name = "_DebounceTimer"
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = DEBOUNCE_SEC
	_debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(_debounce_timer)

	# R4: flush before the panel is freed (scene change, queue_free).
	# tree_exiting fires synchronously while the node is still in tree.
	if not _base_panel.tree_exiting.is_connected(_flush_save):
		_base_panel.tree_exiting.connect(_flush_save)

	# Subscribe to state-change signals → debounced save.
	_base_panel.panel_moved.connect(_on_state_changed)
	_base_panel.panel_resized.connect(_on_state_changed)
	_base_panel.locked_changed.connect(_on_state_changed)
	_base_panel.collapsed_changed.connect(_on_state_changed)

	# Apply persisted state on top of just-applied defaults. If no
	# record exists, defaults stay; nothing is written until the user
	# touches the panel.
	load_layout()


# ── Section key resolution ────────────────────────────────────────

func _compute_section_key() -> String:
	var scope: String
	if not _base_panel.persistence_scope_override.is_empty():
		scope = String(_base_panel.persistence_scope_override)
	else:
		scope = _find_ancestor_scene_path()
	return "%s::%s" % [scope, String(_base_panel.panel_id)]


## Walk strictly up from base_panel.get_parent() until we find a node
## with a non-empty scene_file_path. We INTENTIONALLY skip the panel
## itself: with Inherited Scenes, an instance of base_panel.tscn has
## scene_file_path = "base_panel.tscn" (the inherited base), which
## would collapse all panels in all host scenes into one shared scope.
## What we want is the host scene that instantiated this panel — so we
## start from the parent.
func _find_ancestor_scene_path() -> String:
	var node: Node = _base_panel.get_parent()
	while node != null:
		if node.scene_file_path != "":
			return node.scene_file_path
		node = node.get_parent()
	push_warning("[PanelPersistence] no ancestor scene_file_path for panel '%s' — using 'unknown' scope"
		% String(_base_panel.panel_id))
	return "unknown"


# ── Load ──────────────────────────────────────────────────────────

func load_layout() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(CFG_PATH)
	if err != OK:
		# Missing file is normal on first run; quiet. Other errors get a warn.
		if err != ERR_FILE_NOT_FOUND:
			push_warning("[PanelPersistence] load failed (err=%d) at %s — defaults will apply"
				% [err, ProjectSettings.globalize_path(CFG_PATH)])
		return

	var version: int = int(cfg.get_value(META_SECTION, VERSION_KEY, 0))
	if version != VERSION:
		push_warning("[PanelPersistence] version mismatch (file=%d, expected=%d) — ignoring stored layout"
			% [version, VERSION])
		return

	if not cfg.has_section(_section_key):
		# No record yet; defaults already applied in BasePanel._setup_handlers.
		return

	_loading = true

	var collapse_handler := _base_panel.get_node_or_null("_CollapseHandler") as PanelCollapseHandler
	var lock_handler := _base_panel.get_node_or_null("_LockHandler") as PanelLockHandler

	# 1. Position. TOP_LEFT preset detaches from any layout container
	#    so position writes are absolute (mirrors drag handler's begin).
	if cfg.has_section_key(_section_key, "position"):
		_base_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_base_panel.position = cfg.get_value(_section_key, "position") as Vector2

	# 2. Size on expanded form. If currently collapsed (e.g. default_collapsed
	#    was just applied), expand silently first so the size write hits the
	#    expanded form. We re-collapse below in step 6 if saved as collapsed.
	if collapse_handler != null and collapse_handler.is_collapsed():
		collapse_handler.set_collapsed(false, false)

	if cfg.has_section_key(_section_key, "size"):
		_base_panel.size = cfg.get_value(_section_key, "size") as Vector2

	# 3. C4 clamp. If saved on a larger monitor, position/size may not
	#    fit the current viewport — clamp before re-collapsing so the
	#    captured _pre_collapse_size is the clamped value.
	var clamp_changed: bool = _clamp_to_viewport()

	# 4. Re-collapse if saved as collapsed. _collapse() captures the
	#    just-set base_panel.size as _pre_collapse_size, so expand
	#    restores to the persisted size.
	var saved_collapsed: bool = bool(cfg.get_value(_section_key, "collapsed", false))
	if saved_collapsed and collapse_handler != null and not collapse_handler.is_collapsed():
		collapse_handler.set_collapsed(true, false)

	# 5. Lock state.
	if cfg.has_section_key(_section_key, "locked"):
		var saved_locked: bool = bool(cfg.get_value(_section_key, "locked"))
		if lock_handler != null and lock_handler.is_locked() != saved_locked:
			lock_handler.set_locked(saved_locked, false)

	_loading = false

	# If clamping altered the rect, persist the corrected state now —
	# without this, next load would re-clamp identical values.
	if clamp_changed:
		_flush_save()


# Returns true if clamp altered position or size.
func _clamp_to_viewport() -> bool:
	var vp := _base_panel.get_viewport_rect()
	var min_size: Vector2 = _base_panel.min_panel_size
	var header_h: float = float(BasePanel.CORNER_SIZE)
	var clamped: Dictionary = PanelClamps.clamp_rect_to_viewport(
		_base_panel.position,
		_base_panel.size,
		header_h,
		min_size,
		vp.size)
	var new_pos: Vector2 = clamped["position"]
	var new_size: Vector2 = clamped["size"]
	var changed: bool = (new_pos != _base_panel.position) or (new_size != _base_panel.size)
	if changed:
		_base_panel.position = new_pos
		_base_panel.size = new_size
	return changed


# ── Save ──────────────────────────────────────────────────────────

# Single slot for all 4 state-change signals. Type-anonymous because
# the signals carry different payload types (Vector2 vs bool) — we
# don't care about the value, just that something changed.
func _on_state_changed(_payload: Variant) -> void:
	if _loading:
		return
	_debounce_timer.stop()
	_debounce_timer.start(DEBOUNCE_SEC)


func _on_debounce_timeout() -> void:
	save_layout()


func save_layout() -> void:
	var cfg := ConfigFile.new()
	# Best-effort load preserves other panels' sections. On first save
	# the load fails silently and we write a fresh file.
	cfg.load(CFG_PATH)

	cfg.set_value(META_SECTION, VERSION_KEY, VERSION)

	cfg.set_value(_section_key, "position", _base_panel.position)
	cfg.set_value(_section_key, "size", _expanded_size())
	cfg.set_value(_section_key, "locked", _base_panel.is_locked())
	cfg.set_value(_section_key, "collapsed", _base_panel.is_collapsed())

	var err: int = cfg.save(CFG_PATH)
	if err != OK:
		push_warning("[PanelPersistence] save failed (err=%d) at %s"
			% [err, ProjectSettings.globalize_path(CFG_PATH)])


## When collapsed, base_panel.size is just the header strip — not the
## value we want to persist. The collapse handler holds the pre-collapse
## size; ask it. When expanded, base_panel.size IS the expanded size.
func _expanded_size() -> Vector2:
	if _base_panel.is_collapsed():
		var ch := _base_panel.get_node_or_null("_CollapseHandler") as PanelCollapseHandler
		if ch != null:
			return ch.get_pre_collapse_size()
	return _base_panel.size


func _flush_save() -> void:
	# Synchronous save — used on tree_exiting and after load-time clamp.
	if _debounce_timer != null:
		_debounce_timer.stop()
	save_layout()
