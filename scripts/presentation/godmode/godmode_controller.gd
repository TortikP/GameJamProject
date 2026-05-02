extends Node
## GodmodeController — drives the godmode sandbox scene.
##
## Wires together: HexGrid (instance), ActorRegistry (sibling), Player (Actor in
## HexGrid/Actors), SlotBar UI, TurnManager autoload. Owns input handling.
##
## Init order (matches arena_demo_controller convention):
##   1. resolve nodes
##   2. _paint_grid()   ← set_cell BEFORE grid.initialize()
##   3. grid.initialize()
##   4. _place_player()
##   5. _seed_slots()   ← populate slot 0 with debug_punch
##
## Input:
##   RMB                  → grid.move_actor(player, coord) → tick after move
##   LMB                  → cast active slot at coord-under-mouse → tick
##   cast_slot_0..3       → activate slot + cast at coord-under-mouse → tick
##   godmode_spawn_dummy  → spawn manekin (no tick)
##   godmode_clear        → remove all manekins (no tick)

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const PLAYER_SCENE := preload("res://scenes/dev/player.tscn")
const GODMODE_TERRAIN := preload("res://scenes/dev/godmode_terrain.tres")
const PLAYER_ID: StringName = &"player"
const GRID_W := 14
const GRID_H := 9

@export var grid: HexGrid
@export var registry: ActorRegistry
@export var player: Actor
@export var slot_bar_path: NodePath  # path to HBoxContainer with slot_bar.gd
@export var inspector_path: NodePath
@export var overlay_path: NodePath
@export var player_status_panel_path: NodePath  # 016/F-034 — was hardcoded "../HUD/PlayerStatusPanel"

# Shared scene-tree refs — public so sibling modules can read them via _ctrl.X.
# Resolved in _ready (Phase 1) before _resolve_modules() and setup.run().
var slot_bar: Node
var inspector: Node      # ActorInspector
var overlay: Node        # MoveRangeOverlay
var cast_overlay: Node   # CastRangeOverlay (026 — promoted from _ready local)
var tile_object_resolver: TileObjectResolver  # 019 — runtime tile object triggers
# 024-wave-editor: present iff a queued LevelData is loaded; null in
# procedural godmode sandbox.
var wave_controller: WaveController = null
# 024: held only between _try_load_queued_level success and the end of
# _ready, where WaveController is instantiated and start_level called.
var queued_level: LevelData = null

# 032: module accessors — populated by _resolve_modules() in _ready before
# setup.run() runs. Each is a Node sibling of the controller (child in the
# scene tree, accessible to other modules via _ctrl.X).
var setup: Node              # GodmodeSetup
var input: Node              # GodmodeInput
var cast_fsm: Node           # CastFsm
var ai: Node                 # AiDriver
var telegraphs: Node         # TelegraphRenderer
var hover: Node              # HoverDispatcher
var manekin_spawner: Node    # ManekinSpawner
var step_animator: Node      # StepAnimator

var _selected: Actor      # currently inspected actor (default: player)
var _ability_picker: PopupMenu = null   # right-click slot → pick ability
var _picker_target_slot: int = 0        # which slot the picker is assigning to


func _ready() -> void:
	_resolve_modules()
	# 1. Resolve
	if grid == null:
		grid = get_node_or_null("../HexGrid") as HexGrid
	if grid == null:
		GameLogger.error("Godmode", "HexGrid not found")
		return

	if grid.tile_map_layer == null:
		grid.tile_map_layer = grid.get_node_or_null("Terrain") as TileMapLayer
	if grid.vfx_overlay == null:
		grid.vfx_overlay = grid.get_node_or_null("VFXOverlay") as TileMapLayer

	if registry == null:
		registry = get_node_or_null("../ActorRegistry") as ActorRegistry
	if registry == null:
		GameLogger.error("Godmode", "ActorRegistry not found")
		return

	if player == null:
		player = grid.get_node_or_null("Actors/Player") as Actor
	if player == null:
		# Not present in scene tree → spawn from prefab
		var actors_node: Node = grid.get_node_or_null("Actors")
		if actors_node == null:
			actors_node = grid
		player = PLAYER_SCENE.instantiate() as Actor
		actors_node.add_child(player)

	if not slot_bar_path.is_empty():
		slot_bar = get_node_or_null(slot_bar_path)
	if slot_bar == null:
		slot_bar = get_tree().root.find_child("SlotBar", true, false)
	if slot_bar == null:
		GameLogger.warn("Godmode", "SlotBar not found — abilities won't be visible")

	# 2. Paint, 3. Initialize, 4. Place
	# Godmode uses its own tileset (128×112 hexes, single grass tile) — keeps
	# arena_demo's 64×56 untouched.
	#
	# 020 — if ActiveLevel.has_queued(), load that level instead of running
	# the procedural _paint_grid + _place_player path. Falls through to the
	# original flow on any load failure (logged warn, still playable).
	grid.actor_step_started.connect(step_animator._on_step_started)
	var loaded_via_active_level: bool = false
	if ActiveLevel.has_queued():
		loaded_via_active_level = _try_load_queued_level()
	if not loaded_via_active_level:
		grid.tile_map_layer.tile_set = GODMODE_TERRAIN
		if grid.vfx_overlay != null:
			grid.vfx_overlay.tile_set = GODMODE_TERRAIN
		_paint_grid()
		grid.initialize()
		_place_player()

	# 019 — wire tile object runtime resolver. Must be after grid.initialize()
	# so registries are populated. add_child before setup so the node is in
	# the tree when EventBus signals arrive.
	tile_object_resolver = TileObjectResolver.new()
	tile_object_resolver.name = "TileObjectResolver"
	add_child(tile_object_resolver)
	tile_object_resolver.setup(grid, grid.get_object_registry(), grid.get_effect_registry(), registry)

	# 5. Seed slots — DEFERRED. Sibling order in scene tree means SlotBar._ready
	#    fires AFTER GodmodeController._ready (HUD is a later sibling), so its
	#    buttons array is empty when we get here. call_deferred runs after the
	#    rest of the frame's _ready calls.
	_seed_slots.call_deferred()
	if slot_bar != null and slot_bar.has_signal("slot_activated"):
		slot_bar.slot_activated.connect(_on_slot_activated)
	if slot_bar != null and slot_bar.has_signal("slot_right_clicked"):
		slot_bar.slot_right_clicked.connect(_on_slot_right_clicked)
		_build_ability_picker.call_deferred()

	# Inspector + overlay — resolve
	if not inspector_path.is_empty():
		inspector = get_node_or_null(inspector_path)
	if inspector == null:
		inspector = get_tree().root.find_child("ActorInspector", true, false)
	if not overlay_path.is_empty():
		overlay = get_node_or_null(overlay_path)
	if overlay == null:
		overlay = grid.get_node_or_null("MoveRangeOverlay")
	if overlay != null and overlay.has_method("setup"):
		overlay.setup(grid)
	# CastRangeOverlay (009-T033) — present in godmode.tscn as sibling under HexGrid.
	# 026: promoted to class member so the multi-step cast FSM can call
	# show_range_for_ability / show_self_confirm / hide_range from any handler.
	cast_overlay = grid.get_node_or_null("CastRangeOverlay")
	if cast_overlay != null and cast_overlay.has_method("setup"):
		cast_overlay.setup(grid)
	if inspector != null and inspector.has_signal("speed_changed"):
		inspector.speed_changed.connect(_on_inspector_speed_changed)

	# Reset turn counter for this session
	TurnManager.reset()
	# Force HUD to show initial value — also deferred so TurnLabel has connected.
	_emit_initial_turn.call_deferred()

	# Default selection = player (deferred so player node is fully initialised)
	_select_deferred.call_deferred()

	# 024: announce the start of a fresh run so RunScore resets to 0 and
	# any other run-scoped state listeners get a clean slate. Emitted
	# whether or not we're loading a queued level — godmode procedural
	# sandbox is also "a new run".
	EventBus.run_started.emit()
	# AI: enemies act each world turn
	EventBus.world_turn_ended.connect(ai._on_world_turn_ended)
	EventBus.actor_died.connect(_on_actor_died_for_selection)

	GameLogger.info("Godmode", "ready. RMB=move, LMB/QWER/1234=select, LMB=cast, F1=spawn, F2=clear")
	# 009-T038: bind PlayerStatusPanel if it's mounted in HUD. Uses get_node_or_null
	# so godmode keeps booting if the HUD layout drops the panel.
	var psp: Node = _get_player_status_panel()
	if psp != null and psp.has_method("bind_player"):
		psp.bind_player(player)

	# 024-wave-editor: spin up WaveController iff we loaded a custom level.
	# Procedural godmode sandbox (no queued level) leaves it null — runtime
	# stays single-wave-implicit and behaves as before.
	if queued_level != null:
		wave_controller = WaveController.new()
		wave_controller.name = "WaveController"
		wave_controller.grid = grid
		wave_controller.registry = registry
		add_child(wave_controller)
		# Bind the LevelData to the HUD WaveTimeline FIRST — its _do_rebuild
		# runs deferred and must populate _anchor_positions before
		# wave_started fires (the runtime cursor reads _anchor_positions).
		# call_deferred preserves call order via FIFO, so bind queued first
		# means rebuild runs first.
		var wt: Node = get_node_or_null("../HUD/WaveTimeline")
		if wt != null and wt.has_method("bind_level"):
			wt.bind_level.call_deferred(queued_level)
		# Then start the wave controller — its first emit of wave_started
		# is now safe because the timeline already has its anchors.
		wave_controller.start_level.call_deferred(queued_level)


# ── Setup ────────────────────────────────────────────────────────────────────

func _paint_grid() -> void:
	# All grass, no walls. Godmode sandbox = clean slate.
	for row in GRID_H:
		for col in GRID_W:
			grid.tile_map_layer.set_cell(Vector2i(col, row), 0, Vector2i(0, 0))


# 032 — populate module accessors. Children exist in the scene tree (added in
# .tscn under GodmodeController) and have already run their own _ready, but
# they don't reach into _ctrl until setup.run() — so the order here just
# matters for the controller, not for the children's own _ready.
func _resolve_modules() -> void:
	setup = get_node_or_null("GodmodeSetup")
	input = get_node_or_null("GodmodeInput")
	cast_fsm = get_node_or_null("CastFsm")
	ai = get_node_or_null("AiDriver")
	telegraphs = get_node_or_null("TelegraphRenderer")
	hover = get_node_or_null("HoverDispatcher")
	manekin_spawner = get_node_or_null("ManekinSpawner")
	step_animator = get_node_or_null("StepAnimator")
	if setup == null or input == null or cast_fsm == null or ai == null \
			or telegraphs == null or hover == null or manekin_spawner == null \
			or step_animator == null:
		GameLogger.warn("Godmode", "_resolve_modules: one or more sibling modules missing — check godmode.tscn child order")


## 020 — paint + spawn from a queued LevelData. Returns true on success.
## Failure modes (level can't load, no player spawner) → return false and let
## the caller fall back to the procedural _paint_grid + _place_player path.
##
## 024 — on success, also caches the loaded LevelData in queued_level so
## the post-init WaveController setup can pick it up.
func _try_load_queued_level() -> bool:
	var queued_path: String = ActiveLevel.consume()
	var level: LevelData = LevelSerializer.load_from(queued_path)
	if level == null:
		GameLogger.warn("Godmode", "Failed to load queued level %s — fallback" % queued_path)
		return false
	# Tile set first — paint depends on it.
	var ts: TileSet = load(level.tileset_path) as TileSet
	if ts == null:
		GameLogger.warn("Godmode", "Tileset not found: %s — fallback" % level.tileset_path)
		return false
	grid.tile_map_layer.tile_set = ts
	if grid.vfx_overlay != null:
		grid.vfx_overlay.tile_set = ts
	# Paint floor from level data
	grid.tile_map_layer.clear()
	for cell in level.floor_cells:
		grid.tile_map_layer.set_cell(cell.coord, cell.source_id, cell.atlas_coord)
	# Init grid (reads custom_data, builds HexTile dict + pathfinder)
	grid.initialize()
	# Apply objects + spawners (LevelLoader handles registry + place_actor)
	var actors_node: Node = grid.get_node_or_null("Actors")
	if actors_node == null:
		actors_node = grid
	var spawned_player: Actor = LevelLoader.apply_to(grid, registry, level, actors_node, true)
	if spawned_player != null:
		player = spawned_player
	else:
		# No player spawner in level → procedural fallback for player only,
		# keep loaded floor + objects + enemies. Edge case; editor's validate()
		# blocks this on Save/Playtest, but Load Custom Level files written
		# by hand may not have one.
		GameLogger.warn("Godmode", "Loaded level has no player spawner — placing default")
		_place_player()
	# 024: track player in the grid's id→actor lookup so push-out chain
	# logic (HexGrid.displace_actor recursive case) can resolve occupants
	# without scene-tree walks.
	if player != null:
		grid.registry_lookup[player.actor_id] = player
	# Render tile-object visuals. LevelLoader writes object_id to HexTile
	# (logic / pathfinder / resolver), but doesn't paint sprites — that's the
	# editor's job in editor scenes, godmode's here.
	var objects_overlay: Node = grid.get_node_or_null("ObjectsOverlay")
	if objects_overlay != null:
		if objects_overlay.has_method("bind_registry"):
			objects_overlay.bind_registry(grid.get_object_registry())
		if objects_overlay.has_method("clear_all"):
			objects_overlay.clear_all()
		if objects_overlay.has_method("set_object"):
			for entry in level.objects:
				var coord: Vector2i = entry.get("coord", Vector2i(-1, -1))
				var obj_id: StringName = entry.get("object_id", &"")
				if coord != Vector2i(-1, -1) and obj_id != &"":
					objects_overlay.set_object(coord, obj_id)
	# Camera follow
	var camera: Node = get_node_or_null("../GodmodeCamera")
	if camera != null and camera.has_method("set_follow_target") and player != null:
		camera.set_follow_target(player)
	GameLogger.info("Godmode", "Loaded custom level '%s'" % level.name)
	queued_level = level
	return true


func _place_player() -> void:
	var start := Vector2i(GRID_W / 2, GRID_H / 2)
	grid.place_actor(PLAYER_ID, start)
	player.actor_id = PLAYER_ID
	player.team = &"player"
	player.position = grid.tile_map_layer.map_to_local(start)
	registry.register(player)
	# 015 / F-013: hand the camera a direct ref to Player so it doesn't
	# walk the scene tree by name. has_method check keeps controller usable
	# in test scenes that omit the camera node.
	var camera: Node = get_node_or_null("../GodmodeCamera")
	if camera != null and camera.has_method("set_follow_target"):
		camera.set_follow_target(player)
	GameLogger.info("Godmode", "Player at %s" % str(start))


func _seed_slots() -> void:
	if slot_bar == null:
		return
	var debug: Skill = SkillDatabase.get_skill(&"skill_debug_punch")
	if debug != null:
		slot_bar.set_slot(0, debug)
	else:
		GameLogger.warn("Godmode", "skill_debug_punch not found in SkillDatabase")
	var melee: Skill = SkillDatabase.get_skill(&"skill_melee_punch")
	if melee != null:
		slot_bar.set_slot(1, melee)
	var kb: Skill = SkillDatabase.get_skill(&"skill_knockback_punch")
	if kb != null:
		slot_bar.set_slot(2, kb)
	# 029 / req-1: do NOT pre-select an ability. Player must consciously pick
	# Q/W/E/R (or click a slot) before LMB casts. Avoids accidental opening cast.
	slot_bar.set_active(-1)
	# Sync player ability IDs for inspector/overlay display
	var ids: Array[StringName] = []
	for i in 4:
		var sk: Skill = slot_bar.get_slot(i) as Skill
		if sk != null:
			ids.append_array(sk.get_ability_ids())
	player.set_abilities(ids)


func _emit_initial_turn() -> void:
	EventBus.world_turn_ended.emit(TurnManager.current())


# 024 / T53e — proxy for WaveController.is_transitioning so input gates
# stay terse. Returns false when no wave controller is mounted (procedural
# sandbox).
func _is_wave_transitioning() -> bool:
	return wave_controller != null and wave_controller.is_transitioning()


func _select_deferred() -> void:
	select(player)


# ── Selection / Inspector / Overlay ──────────────────────────────────────────

func select(actor: Actor) -> void:
	_selected = actor
	if inspector != null and inspector.has_method("bind"):
		inspector.bind(actor)
	# Also show hex layer for this actor's current position
	if actor != null:
		var coord: Vector2i = grid.get_coord(actor.actor_id)
		bind_hex_at(coord)
	refresh_overlay()


func deselect_to_player() -> void:
	select(player)


func inspect_hex(coord: Vector2i) -> void:
	# Click on empty hex → inspector shows hex info, actor section hides.
	# Selection state and player's move/cast overlay are NOT touched
	# (009-ui-kit decoupling: overlay tracks player, not _selected).
	# Note: we deliberately don't change _selected — leaving it on the
	# player so subsequent overlay refreshes have a sensible source if
	# anything ever re-introduces selection-driven logic.
	if inspector != null and inspector.has_method("unbind"):
		inspector.unbind()
	bind_hex_at(coord)


func bind_hex_at(coord: Vector2i) -> void:
	if inspector == null or not inspector.has_method("bind_hex"):
		return
	if coord == Vector2i(-1, -1):
		inspector.unbind_hex()
		return
	var tile_kind: StringName = grid.get_tile_kind(coord)
	var effect_id: StringName = grid.get_effect_id(coord)
	inspector.bind_hex(coord, tile_kind, effect_id)


func refresh_overlay() -> void:
	# Decoupled from _selected: the move-range and cast-range overlays are
	# always for the PLAYER. Selecting an enemy/hex (LMB on actor, click on
	# tile) should not hide the player's tactical info (Pillar 1 visibility).
	# Inspector binding still follows _selected — that's the "what am I
	# looking at" panel, separate concern from "what can I do this turn".
	if overlay == null or player == null:
		return
	# Skills (post-007) wrap multiple abilities. Pass Ability objects directly
	# rather than IDs — avoids AbilityDatabase collisions when multiple skills
	# share an ability ID (e.g. "vs_dmg").
	var ability_items: Array = []
	if slot_bar != null:
		var active: int = slot_bar.get_active()
		if active != -1:
			var sk := slot_bar.get_slot(active) as Skill
			if sk != null:
				for ab in sk.abilities:
					ability_items.append(ab)
	overlay.show_for(player, registry, ability_items)


func _on_inspector_speed_changed(_actor: Actor) -> void:
	refresh_overlay()


func _on_actor_died_for_selection(id: StringName) -> void:
	if _selected != null and _selected.actor_id == id:
		deselect_to_player()



## 016/F-034 — resolves PlayerStatusPanel via @export NodePath, with fallback
## to the historical hardcoded "../HUD/PlayerStatusPanel" so godmode still boots
## in test scene-tree variations where the @export wasn't set.
func _get_player_status_panel() -> Node:
	if player_status_panel_path != NodePath(""):
		var psp := get_node_or_null(player_status_panel_path)
		if psp != null:
			return psp
	return get_node_or_null("../HUD/PlayerStatusPanel")


func _on_slot_activated(_index: int) -> void:
	refresh_overlay()
	# 009-T044+: push active spell into PlayerStatusPanel description block.
	# -1 = deselect → pass null which collapses the spell section.
	var psp: Node = _get_player_status_panel()
	if psp != null and psp.has_method("set_active_spell"):
		var ability = null
		if _index != -1 and slot_bar != null:
			ability = slot_bar.get_slot(_index)
		psp.set_active_spell(ability)



# ── Ability picker (RMB on slot) ───────────────────────────────────────────

## Builds a PopupMenu with all SkillDatabase IDs. Called once in _ready().
func _build_ability_picker() -> void:
	_ability_picker = PopupMenu.new()
	_ability_picker.name = "SkillPicker"
	add_child(_ability_picker)
	var ids: Array = SkillDatabase.all_ids()
	ids.sort()
	for i in ids.size():
		_ability_picker.add_item(str(ids[i]), i)
	_ability_picker.id_pressed.connect(_on_ability_picker_selected.bind(ids))


func _on_slot_right_clicked(slot_index: int) -> void:
	if _ability_picker == null:
		return
	_picker_target_slot = slot_index
	_ability_picker.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_ability_picker_selected(item_id: int, ids: Array) -> void:
	if item_id < 0 or item_id >= ids.size():
		return
	var skill_id: StringName = StringName(ids[item_id])
	var skill: Skill = SkillDatabase.get_skill(skill_id)
	if skill == null:
		return
	if slot_bar != null:
		slot_bar.set_slot(_picker_target_slot, skill)
	GameLogger.info("Godmode", "Slot %d ← %s" % [_picker_target_slot, skill_id])


# ── 007 skill dev smoke test ──────────────────────────────────────────────
# Removed in 013: standalone hotkey was redundant once godmode gained
# RMB-assign of any skill to QWER slots. test_vamp_strike still lives in
# data/skills/ — assign to a slot via RMB on the skill button to smoke-test.
