extends Node
## GodmodeSetup — orchestrates GodmodeController._ready setup chain.
##
## Owns: level loading, player placement, slot seeding, post-init signal
## hookups, WaveController spin-up. Public entry: run() — called by the
## controller after node + module resolution.


const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const TutorialDirector = preload("res://scripts/runtime/tutorial_director.gd")
const HubController = preload("res://scripts/runtime/hub_controller.gd")

const PLAYER_SCENE := preload("res://scenes/dev/player.tscn")
const HEX_TERRAIN := preload("res://scenes/arena/tilesets/hex_terrain.tres")
const PLAYER_ID: StringName = &"player"
const GRID_W := 14
const GRID_H := 9

var _ctrl: Node = null


func _ready() -> void:
	_ctrl = get_parent()


## Entry — called by GodmodeController._ready AFTER its node-resolution Phase 1.
## Mirrors the original controller._ready setup chain 1:1.
func run() -> void:
	var campaign_mode: bool = ActiveGame.has_active_game()
	var hub_mode: bool = campaign_mode and ActiveGame.is_in_hub()
	# 1. Resolve scene-tree refs the @export NodePaths didn't populate.
	if _ctrl.grid == null:
		_ctrl.grid = _ctrl.get_node_or_null("../HexGrid") as HexGrid
	if _ctrl.grid == null:
		GameLogger.error("Godmode", "HexGrid not found")
		return

	if _ctrl.grid.tile_map_layer == null:
		_ctrl.grid.tile_map_layer = _ctrl.grid.get_node_or_null("Terrain") as TileMapLayer
	if _ctrl.grid.vfx_overlay == null:
		_ctrl.grid.vfx_overlay = _ctrl.grid.get_node_or_null("VFXOverlay") as TileMapLayer

	if _ctrl.registry == null:
		_ctrl.registry = _ctrl.get_node_or_null("../ActorRegistry") as ActorRegistry
	if _ctrl.registry == null:
		GameLogger.error("Godmode", "ActorRegistry not found")
		return

	if _ctrl.player == null:
		_ctrl.player = _ctrl.grid.get_node_or_null("Actors/Player") as Actor
	if _ctrl.player == null:
		# Not present in scene tree → spawn from prefab
		var actors_node: Node = _ctrl.grid.get_node_or_null("Actors")
		if actors_node == null:
			actors_node = _ctrl.grid
		_ctrl.player = PLAYER_SCENE.instantiate() as Actor
		actors_node.add_child(_ctrl.player)

	if not _ctrl.slot_bar_path.is_empty():
		_ctrl.slot_bar = _ctrl.get_node_or_null(_ctrl.slot_bar_path)
	if _ctrl.slot_bar == null:
		_ctrl.slot_bar = _ctrl.get_tree().root.find_child("SlotBar", true, false)
	if _ctrl.slot_bar == null:
		GameLogger.warn("Godmode", "SlotBar not found — abilities won't be visible")

	# 2. Paint, 3. Initialize, 4. Place
	# Single tileset post-032 — hex_terrain.tres (HEXAGON shape, 128×80 cells).
	#
	# 020 — if ActiveLevel.has_queued(), load that level instead of running
	# the procedural _paint_grid + _place_player path. Falls through to the
	# original flow on any load failure (logged warn, still playable).
	_ctrl.grid.actor_step_started.connect(_ctrl.step_animator._on_step_started)
	var loaded_via_active_level: bool = false
	if ActiveLevel.has_queued():
		loaded_via_active_level = _try_load_queued_level()
	if not loaded_via_active_level:
		_ctrl.grid.tile_map_layer.tile_set = HEX_TERRAIN
		if _ctrl.grid.vfx_overlay != null:
			_ctrl.grid.vfx_overlay.tile_set = HEX_TERRAIN
		_paint_grid()
		_ctrl.grid.initialize()
		_place_player()

	# 019 — wire tile object runtime resolver. Must be after grid.initialize()
	# so registries are populated. add_child before setup so the node is in
	# the tree when EventBus signals arrive.
	_ctrl.tile_object_resolver = TileObjectResolver.new()
	_ctrl.tile_object_resolver.name = "TileObjectResolver"
	_ctrl.add_child(_ctrl.tile_object_resolver)
	_ctrl.tile_object_resolver.setup(_ctrl.grid, _ctrl.grid.get_object_registry(), _ctrl.grid.get_effect_registry(), _ctrl.registry)

	# 5. Seed slots — DEFERRED. Sibling order in scene tree means SlotBar._ready
	#    fires AFTER GodmodeController._ready (HUD is a later sibling), so its
	#    buttons array is empty when we get here. call_deferred runs after the
	#    rest of the frame's _ready calls.
	_seed_slots.call_deferred()
	if _ctrl.slot_bar != null and _ctrl.slot_bar.has_signal("slot_activated"):
		_ctrl.slot_bar.slot_activated.connect(_ctrl._on_slot_activated)
	if not campaign_mode and _ctrl.slot_bar != null and _ctrl.slot_bar.has_signal("slot_right_clicked"):
		_ctrl.slot_bar.slot_right_clicked.connect(_ctrl._on_slot_right_clicked)
	# 049 / AC-8: hover preview wiring. Has-signal guard handles in-flight
	# scenes that haven't reloaded slot_bar.gd post-rebase yet.
	if _ctrl.slot_bar != null and _ctrl.slot_bar.has_signal("slot_hovered"):
		_ctrl.slot_bar.slot_hovered.connect(_ctrl._on_slot_hovered)
	if _ctrl.slot_bar != null and _ctrl.slot_bar.has_signal("slot_unhovered"):
		_ctrl.slot_bar.slot_unhovered.connect(_ctrl._on_slot_unhovered)
	_ctrl._build_ability_picker.call_deferred()

	# 049 / T024 + AC-3: ActorInspector resolution removed. EnemyDetailsPanel
	# and HexTooltip are pure hover sinks — HoverDispatcher resolves them via
	# get_node_or_null on each refresh, no controller-side caching required.
	# MoveRangeOverlay + CastRangeOverlay still resolve here.
	if not _ctrl.overlay_path.is_empty():
		_ctrl.overlay = _ctrl.get_node_or_null(_ctrl.overlay_path)
	if _ctrl.overlay == null:
		_ctrl.overlay = _ctrl.grid.get_node_or_null("MoveRangeOverlay")
	if _ctrl.overlay != null and _ctrl.overlay.has_method("setup"):
		_ctrl.overlay.setup(_ctrl.grid)
	# CastRangeOverlay (009-T033) — present in godmode.tscn as sibling under HexGrid.
	# 026: promoted to controller property so the multi-step cast FSM can call
	# show_range_for_ability / show_self_confirm / hide_range from any handler.
	_ctrl.cast_overlay = _ctrl.grid.get_node_or_null("CastRangeOverlay")
	if _ctrl.cast_overlay != null and _ctrl.cast_overlay.has_method("setup"):
		# 049 / T009: registry is the second arg now — needed for AC-6
		# valid/invalid hex classification (overlay calls target.resolve which
		# reads ctx.registry). Backward-compatible: setup() default-args to
		# null on registry so older scenes won't 500.
		_ctrl.cast_overlay.setup(_ctrl.grid, _ctrl.registry)
	if campaign_mode:
		var help_label: Node = _ctrl.get_node_or_null("../HUD/HelpLabel")
		if help_label != null:
			help_label.hide()
		var combat_log: Node = _ctrl.get_node_or_null("../HUD/CombatLog")
		if combat_log != null:
			combat_log.hide()
	if hub_mode:
		var wave_timeline: Node = _ctrl.get_node_or_null("../HUD/WaveTimeline")
		if wave_timeline != null:
			wave_timeline.hide()

	# Reset turn counter for this session
	TurnManager.reset()
	# Force HUD to show initial value — also deferred so TurnLabel has connected.
	_emit_initial_turn.call_deferred()

	# 049 / T024: removed _select_deferred (selection is gone) — player
	# auto-binds in PSP via bind_player below; nothing else needed an
	# initial select(player) call.

	# 024: announce the start of a fresh run so RunScore resets to 0 and
	# any other run-scoped state listeners get a clean slate. Emitted
	# whether or not we're loading a queued level — godmode procedural
	# sandbox is also "a new run".
	EventBus.run_started.emit()
	# AI: enemies act each world turn
	EventBus.world_turn_ended.connect(_ctrl.ai._on_world_turn_ended)
	# 049 / T024: removed actor_died → _on_actor_died_for_selection wire.
	# Selection no longer exists; cleanup wire below remains.
	# 041 follow-up: generic dead-actor cleanup (frees node + clears grid +
	# unregisters). Replaces ManekinSpawner's per-spawn died.connect path.
	EventBus.actor_died.connect(_ctrl._on_actor_died_for_cleanup)

	GameLogger.info("Godmode", "ready. RMB=move, LMB/QWER/1234=cast, F1=spawn, F2=clear")
	# 009-T038: bind PlayerStatusPanel if it's mounted in HUD. Uses get_node_or_null
	# so godmode keeps booting if the HUD layout drops the panel.
	var psp: Node = _ctrl._get_player_status_panel()
	if psp != null and psp.has_method("bind_player"):
		psp.bind_player(_ctrl.player)

	# 024-wave-editor: spin up WaveController iff we loaded a custom level.
	# Procedural godmode sandbox (no queued level) leaves it null — runtime
	# stays single-wave-implicit and behaves as before.
	if _ctrl.queued_level != null and not hub_mode:
		_ctrl.wave_controller = WaveController.new()
		_ctrl.wave_controller.name = "WaveController"
		_ctrl.wave_controller.grid = _ctrl.grid
		_ctrl.wave_controller.registry = _ctrl.registry
		_ctrl.add_child(_ctrl.wave_controller)
		# Bind the LevelData to the HUD WaveTimeline FIRST — its _do_rebuild
		# runs deferred and must populate _anchor_positions before
		# wave_started fires (the runtime cursor reads _anchor_positions).
		# call_deferred preserves call order via FIFO, so bind queued first
		# means rebuild runs first.
		var wt: Node = _ctrl.get_node_or_null("../HUD/WaveTimeline")
		if wt != null and wt.has_method("bind_level"):
			wt.bind_level.call_deferred(_ctrl.queued_level)
		# Then start the wave controller — its first emit of wave_started
		# is now safe because the timeline already has its anchors.
		if _is_tutorial_level(_ctrl.queued_level):
			_install_tutorial_director(_ctrl.queued_level)
		_ctrl.wave_controller.start_level.call_deferred(_ctrl.queued_level)
	elif _ctrl.queued_level != null and hub_mode:
		_install_hub_controller(_ctrl.queued_level)

	# 045-intro-cutscene: on campaign intro levels, the HUD is invisible —
	# the player can't act, the cutscene/dialogue/scripted-step flow plays
	# uninterrupted. Restored on next-level scene reload (fresh _ready).
	if ActiveGame.has_active_game() and ActiveGame.current_is_intro():
		var hud: CanvasLayer = _ctrl.get_node_or_null("../HUD") as CanvasLayer
		if hud != null:
			hud.visible = false
			GameLogger.info("Godmode", "intro level — HUD hidden")


# ── Setup helpers ────────────────────────────────────────────────────────────

func _paint_grid() -> void:
	# Procedural godmode sandbox: all grass, no walls. Source 0 atlas (0,0)
	# in hex_terrain.tres is Katya's hand-drawn grass tile (godmode_atlas,
	# 128×80, walkable=true, move_cost=1).
	for row in GRID_H:
		for col in GRID_W:
			_ctrl.grid.tile_map_layer.set_cell(Vector2i(col, row), 0, Vector2i(0, 0))


## 020 — paint + spawn from a queued LevelData. Returns true on success.
## Failure modes (level can't load, no player spawner) → return false and let
## the caller fall back to the procedural _paint_grid + _place_player path.
##
## 024 — on success, also caches the loaded LevelData in _ctrl.queued_level so
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
	_ctrl.grid.tile_map_layer.tile_set = ts
	if _ctrl.grid.vfx_overlay != null:
		_ctrl.grid.vfx_overlay.tile_set = ts
	# Paint floor from level data
	_ctrl.grid.tile_map_layer.clear()
	for cell in level.floor_cells:
		_ctrl.grid.tile_map_layer.set_cell(cell.coord, cell.source_id, cell.atlas_coord)
	# Init grid (reads custom_data, builds HexTile dict + pathfinder)
	_ctrl.grid.initialize()
	# Apply objects + spawners (LevelLoader handles registry + place_actor)
	var actors_node: Node = _ctrl.grid.get_node_or_null("Actors")
	if actors_node == null:
		actors_node = _ctrl.grid
	var spawned_player: Actor = LevelLoader.apply_to(_ctrl.grid, _ctrl.registry, level, actors_node, true)
	if spawned_player != null:
		_ctrl.player = spawned_player
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
	if _ctrl.player != null:
		_ctrl.grid.registry_lookup[_ctrl.player.actor_id] = _ctrl.player
	# Render tile-object visuals. LevelLoader writes object_id to HexTile
	# (logic / pathfinder / resolver), but doesn't paint sprites — that's the
	# editor's job in editor scenes, godmode's here.
	var objects_overlay: Node = _ctrl.grid.get_node_or_null("ObjectsOverlay")
	if objects_overlay != null:
		if objects_overlay.has_method("bind_registry"):
			objects_overlay.bind_registry(_ctrl.grid.get_object_registry())
		if objects_overlay.has_method("clear_all"):
			objects_overlay.clear_all()
		if objects_overlay.has_method("set_object"):
			for entry in level.objects:
				var coord: Vector2i = entry.get("coord", Vector2i(-1, -1))
				var obj_id: StringName = entry.get("object_id", &"")
				if coord != Vector2i(-1, -1) and obj_id != &"":
					objects_overlay.set_object(coord, obj_id)
	# Camera follow
	var camera: Node = _ctrl.get_node_or_null("../GodmodeCamera")
	if camera != null and camera.has_method("set_follow_target") and _ctrl.player != null:
		camera.set_follow_target(_ctrl.player)
	GameLogger.info("Godmode", "Loaded custom level '%s'" % level.name)
	_ctrl.queued_level = level
	# 039: signal the loaded level so LevelDialogueDirector can cache it
	# before battle_started fires (which comes from WaveController.start_level
	# on the next deferred frame).
	EventBus.level_loaded.emit(level)
	return true


func _place_player() -> void:
	var start := Vector2i(GRID_W / 2, GRID_H / 2)
	_ctrl.grid.place_actor(PLAYER_ID, start)
	_ctrl.player.actor_id = PLAYER_ID
	_ctrl.player.team = &"player"
	_ctrl.player.position = _ctrl.grid.tile_map_layer.map_to_local(start)
	_ctrl.registry.register(_ctrl.player)
	# 015 / F-013: hand the camera a direct ref to Player so it doesn't
	# walk the scene tree by name. has_method check keeps controller usable
	# in test scenes that omit the camera node.
	var camera: Node = _ctrl.get_node_or_null("../GodmodeCamera")
	if camera != null and camera.has_method("set_follow_target"):
		camera.set_follow_target(_ctrl.player)
	GameLogger.info("Godmode", "Player at %s" % str(start))


func _seed_slots() -> void:
	if _ctrl.slot_bar == null:
		return
	if ActiveGame.has_active_game():
		CampaignController.apply_campaign_skill_loadout()
		return
	# 034: clone_for_owner so player's cooldowns are isolated from any other
	# owner of the same skill (DB-shared instance never receives cd state).
	var debug: Skill = SkillDatabase.get_skill(&"skill_debug_punch")
	if debug != null:
		_ctrl.slot_bar.set_slot(0, debug.clone_for_owner())
	else:
		GameLogger.warn("Godmode", "skill_debug_punch not found in SkillDatabase")
	var melee: Skill = SkillDatabase.get_skill(&"skill_melee_punch")
	if melee != null:
		_ctrl.slot_bar.set_slot(1, melee.clone_for_owner())
	var kb: Skill = SkillDatabase.get_skill(&"skill_knockback_punch")
	if kb != null:
		_ctrl.slot_bar.set_slot(2, kb.clone_for_owner())
	# 029 / req-1: do NOT pre-select an ability. Player must consciously pick
	# Q/W/E/R (or click a slot) before LMB casts. Avoids accidental opening cast.
	_ctrl.slot_bar.set_active(-1)
	# Sync player ability IDs for inspector/overlay display
	var ids: Array[StringName] = []
	for i in 4:
		var sk: Skill = _ctrl.slot_bar.get_slot(i) as Skill
		if sk != null:
			ids.append_array(sk.get_ability_ids())
	_ctrl.player.set_abilities(ids)
	# 031 phase 2: also push the actual Skill resources onto Actor._skills so
	# AiDriver._tick_all_skills can decrement their cooldowns. Without this,
	# slot-bound skills cast fine but never come off cooldown for the player
	# (enemies work because enemy_data_loader sets _skills directly).
	_ctrl.sync_player_skills_from_slots()


func _emit_initial_turn() -> void:
	EventBus.world_turn_ended.emit(TurnManager.current())


func _is_tutorial_level(level: LevelData) -> bool:
	if level == null:
		return false
	return String(level.name) == "maps_tutorial_training_name" \
		or ActiveGame.current_map_path().ends_with("/tutorial_training.json")


func _install_tutorial_director(level: LevelData) -> void:
	var director := TutorialDirector.new()
	director.name = "TutorialDirector"
	_ctrl.add_child(director)
	director.setup(_ctrl, level)


func _install_hub_controller(level: LevelData) -> void:
	var hub := HubController.new()
	hub.name = "HubController"
	_ctrl.add_child(hub)
	_ctrl.hub_controller = hub
	hub.setup(_ctrl, level)
