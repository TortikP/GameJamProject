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
const MANEKIN_SCENE := preload("res://scenes/dev/manekin.tscn")
const PLAYER_SCENE := preload("res://scenes/dev/player.tscn")
const GODMODE_TERRAIN := preload("res://scenes/dev/godmode_terrain.tres")
const PLAYER_ID: StringName = &"player"
const GRID_W := 14
const GRID_H := 9

@export var grid: HexGrid
@export var registry: ActorRegistry
@export var player: Actor
@export var slot_bar: NodePath  # path to HBoxContainer with slot_bar.gd
@export var inspector_path: NodePath
@export var overlay_path: NodePath
@export var player_status_panel_path: NodePath  # 016/F-034 — was hardcoded "../HUD/PlayerStatusPanel"

var _slot_bar_node: Node
var _inspector: Node      # ActorInspector
var _overlay: Node        # MoveRangeOverlay
var _cast_overlay: Node   # CastRangeOverlay (026 — promoted from _ready local)
var _selected: Actor      # currently inspected actor (default: player)
var _next_manekin_idx: int = 1
var _world_processing: bool = false  # true while AI takes its turn — locks player input
var _ability_picker: PopupMenu = null   # right-click slot → pick ability
var _picker_target_slot: int = 0        # which slot the picker is assigning to
var _tile_object_resolver: TileObjectResolver  # 019 — runtime tile object triggers

# 026: multi-step cast collection state. Phase-1 (per-ability target picker)
# lives here; phase-2 is Skill.cast(player, ctxs).
var _cast_in_progress: bool = false
var _cast_skill: Skill = null
var _cast_step: int = 0                  # current ability index in skill.abilities
var _cast_ctxs: Array[Dictionary] = []   # collected so far (length == _cast_step)


func _ready() -> void:
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

	if not slot_bar.is_empty():
		_slot_bar_node = get_node_or_null(slot_bar)
	if _slot_bar_node == null:
		_slot_bar_node = get_tree().root.find_child("SlotBar", true, false)
	if _slot_bar_node == null:
		GameLogger.warn("Godmode", "SlotBar not found — abilities won't be visible")

	# 2. Paint, 3. Initialize, 4. Place
	# Godmode uses its own tileset (128×112 hexes, single grass tile) — keeps
	# arena_demo's 64×56 untouched.
	#
	# 020 — if ActiveLevel.has_queued(), load that level instead of running
	# the procedural _paint_grid + _place_player path. Falls through to the
	# original flow on any load failure (logged warn, still playable).
	grid.actor_step_started.connect(_on_step_started)
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
	_tile_object_resolver = TileObjectResolver.new()
	_tile_object_resolver.name = "TileObjectResolver"
	add_child(_tile_object_resolver)
	_tile_object_resolver.setup(grid, grid.get_object_registry(), grid.get_effect_registry(), registry)

	# 5. Seed slots — DEFERRED. Sibling order in scene tree means SlotBar._ready
	#    fires AFTER GodmodeController._ready (HUD is a later sibling), so its
	#    buttons array is empty when we get here. call_deferred runs after the
	#    rest of the frame's _ready calls.
	_seed_slots.call_deferred()
	if _slot_bar_node != null and _slot_bar_node.has_signal("slot_activated"):
		_slot_bar_node.slot_activated.connect(_on_slot_activated)
	if _slot_bar_node != null and _slot_bar_node.has_signal("slot_right_clicked"):
		_slot_bar_node.slot_right_clicked.connect(_on_slot_right_clicked)
		_build_ability_picker.call_deferred()

	# Inspector + overlay — resolve
	if not inspector_path.is_empty():
		_inspector = get_node_or_null(inspector_path)
	if _inspector == null:
		_inspector = get_tree().root.find_child("ActorInspector", true, false)
	if not overlay_path.is_empty():
		_overlay = get_node_or_null(overlay_path)
	if _overlay == null:
		_overlay = grid.get_node_or_null("MoveRangeOverlay")
	if _overlay != null and _overlay.has_method("setup"):
		_overlay.setup(grid)
	# CastRangeOverlay (009-T033) — present in godmode.tscn as sibling under HexGrid.
	# 026: promoted to class member so the multi-step cast FSM can call
	# show_range_for_ability / show_self_confirm / hide_range from any handler.
	_cast_overlay = grid.get_node_or_null("CastRangeOverlay")
	if _cast_overlay != null and _cast_overlay.has_method("setup"):
		_cast_overlay.setup(grid)
	if _inspector != null and _inspector.has_signal("speed_changed"):
		_inspector.speed_changed.connect(_on_inspector_speed_changed)

	# Reset turn counter for this session
	TurnManager.reset()
	# Force HUD to show initial value — also deferred so TurnLabel has connected.
	_emit_initial_turn.call_deferred()

	# Default selection = player (deferred so player node is fully initialised)
	_select_deferred.call_deferred()

	# AI: enemies act each world turn
	EventBus.world_turn_ended.connect(_on_world_turn_ended)
	EventBus.actor_died.connect(_on_actor_died_for_selection)

	GameLogger.info("Godmode", "ready. RMB=move, LMB/QWER/1234=select, LMB=cast, F1=spawn, F2=clear")
	# 009-T038: bind PlayerStatusPanel if it's mounted in HUD. Uses get_node_or_null
	# so godmode keeps booting if the HUD layout drops the panel.
	var psp: Node = _get_player_status_panel()
	if psp != null and psp.has_method("bind_player"):
		psp.bind_player(player)


# ── Setup ────────────────────────────────────────────────────────────────────

func _paint_grid() -> void:
	# All grass, no walls. Godmode sandbox = clean slate.
	for row in GRID_H:
		for col in GRID_W:
			grid.tile_map_layer.set_cell(Vector2i(col, row), 0, Vector2i(0, 0))


## 020 — paint + spawn from a queued LevelData. Returns true on success.
## Failure modes (level can't load, no player spawner) → return false and let
## the caller fall back to the procedural _paint_grid + _place_player path.
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
	var spawned_player: Actor = LevelLoader.apply_to(grid, registry, level, actors_node)
	if spawned_player != null:
		player = spawned_player
	else:
		# No player spawner in level → procedural fallback for player only,
		# keep loaded floor + objects + enemies. Edge case; editor's validate()
		# blocks this on Save/Playtest, but Load Custom Level files written
		# by hand may not have one.
		GameLogger.warn("Godmode", "Loaded level has no player spawner — placing default")
		_place_player()
	# Camera follow
	var camera: Node = get_node_or_null("../GodmodeCamera")
	if camera != null and camera.has_method("set_follow_target") and player != null:
		camera.set_follow_target(player)
	GameLogger.info("Godmode", "Loaded custom level '%s'" % level.name)
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
	if _slot_bar_node == null:
		return
	var debug: Skill = SkillDatabase.get_skill(&"skill_debug_punch")
	if debug != null:
		_slot_bar_node.set_slot(0, debug)
	else:
		GameLogger.warn("Godmode", "skill_debug_punch not found in SkillDatabase")
	var melee: Skill = SkillDatabase.get_skill(&"skill_melee_punch")
	if melee != null:
		_slot_bar_node.set_slot(1, melee)
	var kb: Skill = SkillDatabase.get_skill(&"skill_knockback_punch")
	if kb != null:
		_slot_bar_node.set_slot(2, kb)
	_slot_bar_node.set_active(0)
	# Sync player ability IDs for inspector/overlay display
	var ids: Array[StringName] = []
	for i in 4:
		var sk: Skill = _slot_bar_node.get_slot(i) as Skill
		if sk != null:
			ids.append_array(sk.get_ability_ids())
	player.set_abilities(ids)


func _emit_initial_turn() -> void:
	EventBus.world_turn_ended.emit(TurnManager.current())


func _select_deferred() -> void:
	_select(player)


# ── Selection / Inspector / Overlay ──────────────────────────────────────────

func _select(actor: Actor) -> void:
	_selected = actor
	if _inspector != null and _inspector.has_method("bind"):
		_inspector.bind(actor)
	# Also show hex layer for this actor's current position
	if actor != null:
		var coord: Vector2i = grid.get_coord(actor.actor_id)
		_bind_hex_at(coord)
	_refresh_overlay()


func _deselect_to_player() -> void:
	_select(player)


func _inspect_hex(coord: Vector2i) -> void:
	# Click on empty hex → inspector shows hex info, actor section hides.
	# Selection state and player's move/cast overlay are NOT touched
	# (009-ui-kit decoupling: overlay tracks player, not _selected).
	# Note: we deliberately don't change _selected — leaving it on the
	# player so subsequent overlay refreshes have a sensible source if
	# anything ever re-introduces selection-driven logic.
	if _inspector != null and _inspector.has_method("unbind"):
		_inspector.unbind()
	_bind_hex_at(coord)


func _bind_hex_at(coord: Vector2i) -> void:
	if _inspector == null or not _inspector.has_method("bind_hex"):
		return
	if coord == Vector2i(-1, -1):
		_inspector.unbind_hex()
		return
	var tile_kind: StringName = grid.get_tile_kind(coord)
	var effect_id: StringName = grid.get_effect_id(coord)
	_inspector.bind_hex(coord, tile_kind, effect_id)


func _refresh_overlay() -> void:
	# Decoupled from _selected: the move-range and cast-range overlays are
	# always for the PLAYER. Selecting an enemy/hex (LMB on actor, click on
	# tile) should not hide the player's tactical info (Pillar 1 visibility).
	# Inspector binding still follows _selected — that's the "what am I
	# looking at" panel, separate concern from "what can I do this turn".
	if _overlay == null or player == null:
		return
	# Skills (post-007) wrap multiple abilities. Pass Ability objects directly
	# rather than IDs — avoids AbilityDatabase collisions when multiple skills
	# share an ability ID (e.g. "vs_dmg").
	var ability_items: Array = []
	if _slot_bar_node != null:
		var active: int = _slot_bar_node.get_active()
		if active != -1:
			var sk := _slot_bar_node.get_slot(active) as Skill
			if sk != null:
				for ab in sk.abilities:
					ability_items.append(ab)
	_overlay.show_for(player, registry, ability_items)


func _on_inspector_speed_changed(_actor: Actor) -> void:
	_refresh_overlay()


func _on_actor_died_for_selection(id: StringName) -> void:
	if _selected != null and _selected.actor_id == id:
		_deselect_to_player()


# ── Input ────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_update_castability()


func _update_castability() -> void:
	if _slot_bar_node == null or grid == null or registry == null or player == null:
		return
	var coord := grid.coord_under_mouse()
	var target_id: StringName = &""
	if coord != Vector2i(-1, -1):
		target_id = grid.get_actor_at(coord)
	var ctx: Dictionary = {
		"registry": registry,
		"grid": grid,
		"target_id": target_id,
		"target_coord": coord,
	}
	# Slot castability tints
	for i in 4:
		var skill := _slot_bar_node.get_slot(i) as Skill
		var castable: bool = skill != null and skill.can_apply(player, ctx)
		_slot_bar_node.set_castable(i, castable)

	# Damage preview on enemies — only the hovered one shows red strip,
	# others get cleared. Active slot's ability is the source.
	var active_idx: int = _slot_bar_node.get_active()
	var active_skill := _slot_bar_node.get_slot(active_idx) as Skill
	var hover_target: Actor = registry.get_actor(target_id) if target_id != &"" else null
	var preview_for_hover: int = 0
	if active_skill != null and hover_target != null and hover_target.team == &"enemy":
		if active_skill.can_apply(player, ctx):
			preview_for_hover = active_skill.predicted_damage_to(player, hover_target, ctx)
	for actor in registry.all():
		if not (actor is Actor):
			continue
		var a: Actor = actor
		if a.team != &"enemy":
			continue
		var hp_bar: Node = a.get_node_or_null("HealthBar")
		if hp_bar == null or not hp_bar.has_method("set_preview_damage"):
			continue
		hp_bar.set_preview_damage(preview_for_hover if a == hover_target else 0)

	# Zone AoE preview — repaint every frame so it follows the cursor.
	if _overlay != null and _overlay.has_method("show_zone_preview"):
		var zone_hexes: Array[Vector2i] = []
		if active_skill != null and coord != Vector2i(-1, -1):
			var caster_coord: Vector2i = grid.get_coord(player.actor_id)
			for ab_obj in active_skill.abilities:
				var ab := ab_obj as Ability
				if ab == null or ab.area == null:
					continue
				# Anchor the preview where the area will actually resolve at cast time.
				# SelfTarget pins this to caster_coord; spatial targets (Hex/Entity)
				# fall through to hover_coord. See AbilityTarget.preview_anchor_coord.
				var anchor: Vector2i = coord
				if ab.target != null:
					anchor = ab.target.preview_anchor_coord(caster_coord, coord)
				var affected: Array[Vector2i] = ab.area.get_affected_hexes(caster_coord, anchor, grid)
				for c in affected:
					if not zone_hexes.has(c):
						zone_hexes.append(c)
		_overlay.show_zone_preview(zone_hexes)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			# 026: priority 0 — cancel multi-step cast in progress.
			# Slot-toggle path below is now unreachable while cast-FSM owns input.
			if _cast_in_progress:
				_cancel_cast()
				get_viewport().set_input_as_handled()
				return
			# 009-T051 priority chain (post-026):
			#   1. active cast slot → toggle off
			#   2. selection != player → reset selection to player
			#   3. otherwise → open pause menu
			if _slot_bar_node != null and _slot_bar_node.get_active() != -1:
				_slot_bar_node.activate(_slot_bar_node.get_active())  # toggle off
				get_viewport().set_input_as_handled()
				return
			if _selected != null and _selected != player:
				_deselect_to_player()
				get_viewport().set_input_as_handled()
				return
			# No selection to clear, no active cast — open pause menu if mounted.
			var pause_menu: Node = get_node_or_null("../HUD/PauseMenu")
			if pause_menu != null and pause_menu.has_method("open"):
				pause_menu.open()
				get_viewport().set_input_as_handled()
				return
			# Last-resort fallback: original behavior (no-op deselect).
			_deselect_to_player()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("godmode_spawn_dummy"):
		_spawn_manekin()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("godmode_clear"):
		_clear_manekins()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("dev_open_editor"):
		# 020 — global hotkey: jump straight to the map editor from any battle.
		# If this run originated from the editor's Playtest (ActiveLevel marks
		# the path), queue it back so the editor reopens with the same map
		# instead of a fresh canvas.
		if ActiveLevel.can_return_to_editor():
			ActiveLevel.queue(ActiveLevel.get_playtest_origin())
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://scenes/dev/map_editor.tscn")
		return
	if event.is_action_pressed("wait_turn"):
		_wait_turn()
		get_viewport().set_input_as_handled()
		return
	for i in 4:
		if event.is_action_pressed("cast_slot_%d" % i):
			# 026: when an FSM cast is in progress, slot keys gate through it.
			if _cast_in_progress and _slot_bar_node != null:
				var active_now: int = _slot_bar_node.get_active()
				if i == active_now:
					# Same slot pressed again — alternate keyboard path.
					# On a self-step, this commits; otherwise it cancels (toggle off).
					if _is_self_step():
						var caster_coord: Vector2i = grid.get_coord(player.actor_id)
						_commit_step(caster_coord, player.actor_id)
					else:
						_cancel_cast()
						_slot_bar_node.activate(i)  # toggle off
				else:
					# Different slot — drop current cast, switch slot. New entry happens
					# only on the next LMB (matches 021 — slot key just selects, doesn't fire).
					_cancel_cast()
					_slot_bar_node.activate(i)
				get_viewport().set_input_as_handled()
				return
			# Default: activate() in SlotBar toggles selection.
			if _slot_bar_node != null:
				_slot_bar_node.activate(i)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			# 026: RMB cancels an in-progress cast instead of moving.
			if _cast_in_progress:
				_cancel_cast()
				get_viewport().set_input_as_handled()
				return
			_request_move()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# 026: LMB during cast FSM — commit step or no-op (out-of-range click).
			if _cast_in_progress:
				_handle_cast_lmb()
				get_viewport().set_input_as_handled()
				return
			_request_cast_active()
			get_viewport().set_input_as_handled()


## 026: dispatch LMB while cast FSM is active.
##   - self-step: any LMB anywhere commits with caster's coord (per spec AC-C4).
##   - non-self : LMB on a hex within ability.target.range commits; otherwise
##                no-op (overlay stays, player keeps the step).
func _handle_cast_lmb() -> void:
	if not _cast_in_progress or _cast_skill == null:
		return
	if _cast_step >= _cast_skill.abilities.size():
		return
	var ab: Ability = _cast_skill.abilities[_cast_step]
	if ab.target is SelfTarget:
		var caster_coord: Vector2i = grid.get_coord(player.actor_id)
		_commit_step(caster_coord, player.actor_id)
		return
	var coord: Vector2i = grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		return  # off-grid click — stay on step
	var from_coord: Vector2i = grid.get_coord(player.actor_id)
	var valid_hexes: Array[Vector2i] = ab.target.get_range_hexes(from_coord, grid)
	if coord in valid_hexes:
		_commit_step(coord, grid.get_actor_at(coord))
	# else: invalid range click — neither commit nor cancel; stay on step


# ── Actions ──────────────────────────────────────────────────────────────────

func _wait_turn() -> void:
	if grid._moving or _world_processing:
		return
	GameLogger.info("Godmode", "player skipped turn")
	TurnManager.advance()


func _request_move() -> void:
	if grid._moving or _world_processing:
		return
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		return
	if not grid.is_walkable(coord):
		GameLogger.info("Godmode", "unreachable: %s" % str(coord))
		return
	var from: Vector2i = grid.get_coord(PLAYER_ID)
	if coord == from:
		return
	if grid.get_actor_at(coord) != &"":
		GameLogger.info("Godmode", "occupied: %s" % str(coord))
		return
	if player.speed <= 0:
		GameLogger.info("Godmode", "cannot move (speed=0)")
		return
	var path: Array = grid.find_path(from, coord)
	var dist: int = path.size() - 1
	if dist > player.speed:
		GameLogger.info("Godmode", "too far (speed=%d, distance=%d)" % [player.speed, dist])
		return
	await grid.move_actor(PLAYER_ID, coord)
	if grid.get_coord(PLAYER_ID) != from:
		TurnManager.advance()
		_refresh_overlay()


func _request_cast_active() -> void:
	if _slot_bar_node == null:
		return
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		return
	var target_id: StringName = grid.get_actor_at(coord)
	var ctx: Dictionary = {
		"registry": registry, "grid": grid,
		"target_id": target_id, "target_coord": coord,
	}
	var active_idx: int = _slot_bar_node.get_active()
	# If a spell is selected and can cast → start the FSM
	if active_idx != -1:
		var skill := _slot_bar_node.get_slot(active_idx) as Skill
		if skill != null and skill.can_apply(player, ctx):
			_cast_slot(active_idx)
			# 026 fix: the entry LMB also acts as the commit click for step 0.
			# Without this, the player would have to click twice (once to enter
			# FSM, once to commit). _handle_cast_lmb is safe to call when FSM
			# isn't active (early-returns).
			if _cast_in_progress:
				_handle_cast_lmb()
		# Skill slot active → never inspect/deselect on a failed cast.
		return
	# No active skill: inspect hovered actor or hex
	var target_actor: Actor = registry.get_actor(target_id) if target_id != &"" else null
	if target_actor != null:
		_select(target_actor)
	elif grid.is_walkable(coord):
		_inspect_hex(coord)


# ── 026: multi-step cast collection (phase 1) ──────────────────────────────────
##
## State-machine: IDLE → AWAIT_TARGET / AWAIT_SELF_CONFIRM → ... → _commit_cast
## Cancel paths reset to IDLE without firing Skill.cast.
##
## See specs/026-skill-system-v3/plan.md §"Player cast state-machine".

## Entry point — called when player presses LMB with an active slot.
## Pre-checks `skill.can_apply(player, mouse_ctx)` against abilities[0] (021
## semantics). If false, slot stays greyed and FSM does not start.
func _cast_slot(slot_index: int) -> void:
	if _slot_bar_node == null:
		return
	var skill := _slot_bar_node.get_slot(slot_index) as Skill
	if skill == null:
		GameLogger.info("Godmode", "slot %d empty" % slot_index)
		return
	if skill.abilities.is_empty():
		GameLogger.warn("Godmode", "slot %d skill '%s' has no abilities" % [slot_index, skill.id])
		return
	if grid._moving or _world_processing:
		return

	# Pre-check using mouse position. Cheap and matches 021 grey-out semantics.
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		GameLogger.info("Godmode", "no target (off-grid)")
		return
	var pre_ctx: Dictionary = {
		"registry": registry, "grid": grid,
		"target_id": grid.get_actor_at(coord), "target_coord": coord,
	}
	if not skill.can_apply(player, pre_ctx):
		return

	_cast_skill = skill
	_cast_step = 0
	_cast_ctxs = []
	_cast_in_progress = true
	# 026 fix: hide MoveRangeOverlay's slot-activation attack-range paint
	# so CastRangeOverlay's per-step paint doesn't render on top of it.
	# Restored on FSM exit via _refresh_overlay (in _commit_cast/_cancel_cast).
	if _overlay != null and _overlay.has_method("clear"):
		_overlay.clear()
	_begin_step()


func _begin_step() -> void:
	if _cast_skill == null or _cast_step >= _cast_skill.abilities.size():
		return
	var ab: Ability = _cast_skill.abilities[_cast_step]
	if _cast_overlay == null:
		return
	if ab.target is SelfTarget:
		var caster_coord: Vector2i = grid.get_coord(player.actor_id)
		if _cast_overlay.has_method("show_self_confirm"):
			_cast_overlay.show_self_confirm(caster_coord)
	else:
		if _cast_overlay.has_method("show_range_for_ability"):
			_cast_overlay.show_range_for_ability(player, ab)


func _commit_step(coord: Vector2i, target_id: StringName) -> void:
	var ctx: Dictionary = {
		"registry": registry, "grid": grid,
		"target_id": target_id, "target_coord": coord,
	}
	_cast_ctxs.append(ctx)
	_cast_step += 1
	if _cast_overlay != null and _cast_overlay.has_method("hide_range"):
		_cast_overlay.hide_range()
	if _cast_step == _cast_skill.abilities.size():
		await _commit_cast()
	else:
		_begin_step()


func _commit_cast() -> void:
	# Snapshot then reset BEFORE Skill.cast so EventBus subscribers see clean state.
	var skill: Skill = _cast_skill
	var ctxs: Array[Dictionary] = _cast_ctxs
	_reset_cast_state()
	var did_cast: bool = skill.cast(player, ctxs)
	# 026 fix: restore MoveRangeOverlay slot paint after FSM exits.
	_refresh_overlay()
	if did_cast:
		await GameSpeed.wait("godmode", "ability_cast_delay")
		TurnManager.advance()


func _cancel_cast() -> void:
	if _cast_overlay != null and _cast_overlay.has_method("hide_range"):
		_cast_overlay.hide_range()
	_reset_cast_state()
	# 026 fix: restore MoveRangeOverlay slot paint after FSM cancels.
	_refresh_overlay()
	# no cooldown, no commit, no turn advance


func _reset_cast_state() -> void:
	_cast_in_progress = false
	_cast_skill = null
	_cast_step = 0
	_cast_ctxs = []


func _is_self_step() -> bool:
	if not _cast_in_progress or _cast_skill == null:
		return false
	if _cast_step >= _cast_skill.abilities.size():
		return false
	return _cast_skill.abilities[_cast_step].target is SelfTarget


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
	_refresh_overlay()
	# 009-T044+: push active spell into PlayerStatusPanel description block.
	# -1 = deselect → pass null which collapses the spell section.
	var psp: Node = _get_player_status_panel()
	if psp != null and psp.has_method("set_active_spell"):
		var ability = null
		if _index != -1 and _slot_bar_node != null:
			ability = _slot_bar_node.get_slot(_index)
		psp.set_active_spell(ability)


# ── Spawning ─────────────────────────────────────────────────────────────────

func _spawn_manekin() -> void:
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1) or not grid.is_walkable(coord):
		GameLogger.info("Godmode", "cannot spawn at %s" % str(coord))
		return
	if grid.get_actor_at(coord) != &"":
		GameLogger.info("Godmode", "occupied at %s" % str(coord))
		return
	var idx := _next_manekin_idx
	_next_manekin_idx += 1
	var id := StringName("dummy_%03d" % idx)
	var manekin: Actor = MANEKIN_SCENE.instantiate()
	manekin.actor_id = id
	manekin.position = grid.tile_map_layer.map_to_local(coord)
	var actors_node: Node = grid.get_node_or_null("Actors")
	if actors_node == null:
		actors_node = grid
	actors_node.add_child(manekin)
	grid.place_actor(id, coord)
	registry.register(manekin)
	manekin.died.connect(_on_actor_died)
	GameLogger.info("Godmode", "spawned %s at %s" % [id, str(coord)])
	# Plan immediately so the player sees the new manekin's intent right away,
	# without having to end their turn first. Re-plans ALL enemies because
	# adding a new one can block existing pathing.
	_replan_all_and_refresh()
	_refresh_overlay()


func _replan_all_and_refresh() -> void:
	var enemies: Array = []
	for actor in registry.all():
		if actor is Actor and (actor as Actor).team == &"enemy":
			enemies.append(actor)
	var ctx: Dictionary = _world_ctx()
	for actor in enemies:
		if actor is Actor and (actor as Actor).is_alive():
			EnemyAIPlanner.plan(actor as Actor, ctx)
	_refresh_telegraphs()


func _clear_manekins() -> void:
	var to_remove: Array = []
	for actor in registry.all():
		if actor is Actor and (actor as Actor).team == &"enemy":
			to_remove.append(actor)
	for actor in to_remove:
		var a: Actor = actor
		grid.clear_actor(a.actor_id)
		registry.unregister(a.actor_id)
		a.queue_free()
	_clear_all_telegraphs()
	# F2 doubles as a sandbox reset: revive player and refill HP. Lets the
	# tester keep playing after death without restarting the scene.
	if player != null:
		player.heal_to_full()
	_deselect_to_player()
	GameLogger.info("Godmode", "cleared %d manekins, player reset" % to_remove.size())


func _on_actor_died(id: StringName) -> void:
	var actor: Actor = registry.get_actor(id)
	if actor == null:
		return
	grid.clear_actor(id)
	registry.unregister(id)
	actor.queue_free()
	# An enemy died → its intent is gone, refresh visuals to drop its label
	_refresh_telegraphs()


# ── Movement animation (mirror of arena_demo_controller) ─────────────────────

func _on_step_started(actor_id: StringName, _from: Vector2i, to: Vector2i) -> void:
	var actor: Actor = registry.get_actor(actor_id)
	if actor == null:
		return
	var pos: Vector2 = grid.tile_map_layer.map_to_local(to)
	var duration: float = GameSpeed.get_value("arena", "step_duration", 0.18) * grid.get_move_cost(to)
	create_tween().tween_property(actor, "position", pos, duration)


# ── AI ───────────────────────────────────────────────────────────────────────
#
# Two-stage per enemy on world_turn_ended:
#   1. RESOLVE last turn's attack intent (if any). If player still on the
#      intent hex, attack lands; else attack misses (wasted turn). Clear
#      telegraph visual either way.
#   2. PLAN this turn:
#      a. If adjacent to player → don't move (preserve attacking position).
#      b. Else → step one hex toward player.
#   3. SET intent for next turn: if adjacent (now or after the step) AND
#      has attack_ability, intent = player's current coord. Show telegraph.
#
# Sequential per enemy. _world_processing locks player input during the loop.

const TELEGRAPH_HEX_SCRIPT := preload("res://scripts/presentation/telegraph_hex.gd")
const INTENT_ARROW_SCRIPT := preload("res://scripts/presentation/intent_arrow.gd")

var _telegraph_hexes: Dictionary = {}  # Vector2i coord -> TelegraphHex node
var _intent_arrows: Dictionary = {}    # StringName actor_id -> IntentArrow node


func _on_world_turn_ended(_turn: int) -> void:
	if _world_processing:
		return
	if player == null or not player.is_alive():
		return
	_world_processing = true
	await _run_enemy_turn()
	_world_processing = false
	_refresh_overlay()


func _run_enemy_turn() -> void:
	var enemies: Array = []
	for actor in registry.all():
		if actor is Actor and (actor as Actor).team == &"enemy":
			enemies.append(actor)
	_clear_all_telegraphs()

	# Phase 1: RESOLVE — execute everyone's planned move, then planned cast.
	# Movement first so casts happen from the post-move position.
	for actor in enemies:
		if not (actor is Actor):
			continue
		var enemy: Actor = actor
		if not enemy.is_alive() or registry.get_actor(enemy.actor_id) == null:
			continue
		await _resolve_move_intent(enemy)
		if not enemy.is_alive():
			continue
		await _resolve_cast_intent(enemy)

	# Phase 2: PLAN — pick next move and next cast (writes cast_intent /
	# move_intent_coord on each enemy). Visuals rebuilt at the end of this loop.
	var ctx: Dictionary = _world_ctx()
	for actor in enemies:
		if not (actor is Actor):
			continue
		var enemy: Actor = actor
		if not enemy.is_alive() or registry.get_actor(enemy.actor_id) == null:
			continue
		EnemyAIPlanner.plan(enemy, ctx)

	_refresh_telegraphs()


# ── Resolve helpers ──────────────────────────────────────────────────────────

func _resolve_move_intent(enemy: Actor) -> void:
	var intent: Vector2i = enemy.move_intent_coord
	enemy.move_intent_coord = Vector2i(-1, -1)
	if intent == Vector2i(-1, -1):
		return
	var enemy_coord: Vector2i = grid.get_coord(enemy.actor_id)
	if enemy_coord == intent:
		return  # already there (somehow)
	# Check destination is still walkable + unoccupied at execute-time
	# (another enemy may have ended up there during this Phase 1)
	if grid.get_actor_at(intent) != &"":
		GameLogger.info("AI", "%s: move blocked at %s" % [enemy.actor_id, intent])
		return
	# move_actor handles validation; await ensures sequential animation
	await grid.move_actor(enemy.actor_id, intent)


## Resolves a previously-planned cast on `enemy`. Reads enemy.cast_intent (set
## by EnemyAIPlanner during Phase 2 of the previous turn). Generic over Skill —
## works for any target type / area / effect chain. AC-X5 re-validates target
## state at resolve time (target alive, in range, skill still ready).
func _resolve_cast_intent(enemy: Actor) -> void:
	var intent_v: Variant = enemy.cast_intent
	enemy.cast_intent = null
	if intent_v == null:
		return
	var intent: CastIntent = intent_v as CastIntent
	if intent == null or not intent.is_valid():
		return
	var skill: Skill = SkillDatabase.get_skill(intent.skill_id)
	if skill == null or not skill.is_ready():
		return

	# Re-validate target — entity may have died/moved between plan and resolve.
	var target_id: StringName = intent.target_id
	var target_coord: Vector2i = intent.target_coord
	if target_id != &"":
		var target_actor: Actor = registry.get_actor(target_id)
		if target_actor == null or not target_actor.is_alive():
			GameLogger.info("AI", "%s: cast cancelled (target gone)" % enemy.actor_id)
			return
		var live_coord: Vector2i = grid.get_coord(target_id)
		if live_coord == Vector2i(-1, -1):
			GameLogger.info("AI", "%s: cast cancelled (target off-grid)" % enemy.actor_id)
			return
		# Target moved? Old planned coord is stale — use current.
		target_coord = live_coord

	var ctx: Dictionary = {
		"registry": registry, "grid": grid,
		"target_id": target_id, "target_coord": target_coord,
	}
	# 026: AI broadcasts a single ctx to all abilities. Per-ability AI targeting
	# is out of scope — see specs/026-skill-system-v3/spec.md §"Out of scope".
	# can_apply re-validates range / castability at the moment of cast.
	var ctxs: Array[Dictionary] = []
	for _i in skill.abilities.size():
		ctxs.append(ctx)
	skill.cast(enemy, ctxs)
	await GameSpeed.wait("godmode", "ability_cast_delay")


# ── World context for AI planner ─────────────────────────────────────────────

func _world_ctx() -> Dictionary:
	return {
		"registry": registry,
		"grid": grid,
		"all_actors": registry.all(),
		"turn": TurnManager.current(),
	}


# ── Telegraph tag mapping (AC-I4) ────────────────────────────────────────────

## Maps a Skill's primary tag to TelegraphHex.semantic_tag (which UiTheme then
## resolves via semantic_color). Aggregation in _refresh_telegraphs already
## handles per-coord summing — this is one-shot per cast.
func _telegraph_tag_for_skill(skill: Skill) -> StringName:
	if skill == null or skill.behaviour_tags.is_empty():
		return &""  # → SEM_DAMAGE default (legacy / unknown)
	match skill.behaviour_tags[0]:
		&"damage", &"damage_aoe", &"knockback":
			return &"damage"
		&"heal":
			return &"heal"
		&"control":
			return &"control"
		&"debuff":
			return &"debuff"
		&"buff":
			return &"buff"
		&"summon":
			return &"create"
		&"mobility":
			return &"move"
	return &""


# ── Plan helpers ─────────────────────────────────────────────────────────────

# ── Telegraph visuals ────────────────────────────────────────────────────────

func _refresh_telegraphs() -> void:
	# Clear all current visuals.
	for poly in _telegraph_hexes.values():
		if is_instance_valid(poly):
			poly.queue_free()
	_telegraph_hexes.clear()
	for arr in _intent_arrows.values():
		if is_instance_valid(arr):
			arr.queue_free()
	_intent_arrows.clear()

	# Aggregate per-coord telegraph state across all enemies' intents.
	# Each hex tracks (tag, damage). Damage only sums when both intents are damage-class.
	var by_coord: Dictionary = {}   # Vector2i -> {tag: StringName, damage: int}
	for actor in registry.all():
		if not (actor is Actor):
			continue
		var enemy: Actor = actor
		if enemy.team != &"enemy" or not enemy.is_alive():
			continue

		# Cast telegraph: hex + color from primary tag, damage number for damage-class only.
		var intent: Variant = enemy.cast_intent
		if intent == null:
			pass
		else:
			var ci: CastIntent = intent as CastIntent
			if ci != null and ci.is_valid():
				var coord: Vector2i = ci.target_coord
				if ci.target_id != &"":
					var live: Vector2i = grid.get_coord(ci.target_id)
					if live != Vector2i(-1, -1):
						coord = live
				if coord != Vector2i(-1, -1):
					var skill: Skill = SkillDatabase.get_skill(ci.skill_id)
					var tag: StringName = _telegraph_tag_for_skill(skill)
					var dmg: int = 0
					if tag == &"damage" or tag == &"":
						# Predict only for damage-class. tag=="" → legacy fallback (treat as damage).
						var target_actor: Actor = null
						if ci.target_id != &"":
							target_actor = registry.get_actor(ci.target_id)
						if target_actor != null and skill != null:
							dmg = skill.predicted_damage_to(enemy, target_actor, {})
					if by_coord.has(coord):
						var prev: Dictionary = by_coord[coord]
						# Sum damage only when both are damage-class with same tag; else keep first.
						if prev.tag == tag and (tag == &"damage" or tag == &""):
							prev.damage += dmg
					else:
						by_coord[coord] = {"tag": tag, "damage": dmg}

		# Movement arrow — one per enemy with a planned move.
		var mv: Vector2i = enemy.move_intent_coord
		if mv != Vector2i(-1, -1):
			var enemy_coord: Vector2i = grid.get_coord(enemy.actor_id)
			if enemy_coord != Vector2i(-1, -1):
				var arrow: Node2D = INTENT_ARROW_SCRIPT.new()
				arrow.position = Vector2.ZERO
				arrow.z_index = 4  # above telegraph hex, below actors
				grid.add_child(arrow)
				arrow.set("origin", grid.tile_map_layer.map_to_local(enemy_coord))
				arrow.set("target", grid.tile_map_layer.map_to_local(mv))
				_intent_arrows[enemy.actor_id] = arrow

	# Render one telegraph hex per threatened coord.
	for coord in by_coord.keys():
		var hex: Node2D = TELEGRAPH_HEX_SCRIPT.new()
		hex.position = grid.tile_map_layer.map_to_local(coord)
		hex.z_index = 3
		var entry: Dictionary = by_coord[coord]
		hex.set("semantic_tag", entry.tag)
		hex.set("damage", entry.damage)   # 0 = no number drawn (heal/buff/etc.)
		grid.add_child(hex)
		_telegraph_hexes[coord] = hex


func _clear_all_telegraphs() -> void:
	for poly in _telegraph_hexes.values():
		if is_instance_valid(poly):
			poly.queue_free()
	_telegraph_hexes.clear()
	for arr in _intent_arrows.values():
		if is_instance_valid(arr):
			arr.queue_free()
	_intent_arrows.clear()


## Best-effort damage forecast for an enemy's pending cast against the player.
## Kept as a thin shim for any external caller (ActorInspector, etc.) that wants
## a quick "what will hit me next turn" number — telegraph rendering itself
## inlines the same lookup in _refresh_telegraphs.
func _enemy_attack_damage(enemy: Actor) -> int:
	var intent_v: Variant = enemy.cast_intent
	if intent_v == null:
		return 0
	var ci: CastIntent = intent_v as CastIntent
	if ci == null or not ci.is_valid():
		return 0
	var skill: Skill = SkillDatabase.get_skill(ci.skill_id)
	if skill == null:
		return 0
	var tag: StringName = _telegraph_tag_for_skill(skill)
	if tag != &"damage" and tag != &"":
		return 0
	return skill.predicted_damage_to(enemy, player, {})


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
	if _slot_bar_node != null:
		_slot_bar_node.set_slot(_picker_target_slot, skill)
	GameLogger.info("Godmode", "Slot %d ← %s" % [_picker_target_slot, skill_id])


# ── 007 skill dev smoke test ──────────────────────────────────────────────
# Removed in 013: standalone hotkey was redundant once godmode gained
# RMB-assign of any skill to QWER slots. test_vamp_strike still lives in
# data/skills/ — assign to a slot via RMB on the skill button to smoke-test.
