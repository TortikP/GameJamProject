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
const SkillFormatter = preload("res://scripts/presentation/skill_formatter.gd")
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
# 029 / req-6: track which enemy is currently under cursor (or &"") so we can
# show/hide the cast-intent tooltip with no flicker on idle frames.
var _hover_intent_actor_id: StringName = &""


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


# ── Input ────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_update_castability()


func _update_castability() -> void:
	if slot_bar == null or grid == null or registry == null or player == null:
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
	# Slot castability tints. 027: stunned player → all slots greyed.
	var stunned: bool = player.is_stunned()
	for i in 4:
		var skill := slot_bar.get_slot(i) as Skill
		var castable: bool = skill != null and not stunned and skill.can_apply(player, ctx)
		slot_bar.set_castable(i, castable)

	# Damage preview on enemies — only the hovered one shows red strip,
	# others get cleared. Active slot's ability is the source.
	var active_idx: int = slot_bar.get_active()
	var active_skill := slot_bar.get_slot(active_idx) as Skill
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
	if overlay != null and overlay.has_method("show_zone_preview"):
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
		overlay.show_zone_preview(zone_hexes)

	# 029 / bonus-2: hover-path preview. Show the route the player would take
	# IFF the cursor is over a reachable hex (within effective_speed) AND
	# isn't blocked. Skipped during cast FSM and stun — neither is "I'm
	# considering moving here" mode. Path is recomputed via find_path_around
	# with live actor blocks so it bends around enemies — same set the move
	# zone was computed against, so reachability and path agree.
	_refresh_hover_path(coord)

	# 029 / req-6: tooltip on enemy hover that shows their planned cast.
	# Only fires for enemies that have a non-null cast_intent — moving-only
	# turns or idle holds get no tooltip (nothing to telegraph). The hex
	# already shows the intent visually; tooltip adds the "what is this
	# spell exactly" detail.
	_refresh_intent_tooltip(target_id)


## 029 / bonus-2: hover-path computation + push to overlay. Cheap when no
## change (overlay early-returns on identical array) so calling per frame is OK.
func _refresh_hover_path(hover_coord: Vector2i) -> void:
	if overlay == null or not overlay.has_method("set_hover_path"):
		return
	if player == null or grid == null:
		overlay.set_hover_path([] as Array[Vector2i])
		return
	# Skip during cast FSM (player is targeting, not considering movement) and
	# during AI turns / stun.
	if cast_fsm.is_in_progress() or ai.is_world_processing() or player.is_stunned():
		overlay.set_hover_path([] as Array[Vector2i])
		return
	var from: Vector2i = grid.get_coord(player.actor_id)
	if from == Vector2i(-1, -1) or hover_coord == Vector2i(-1, -1) or hover_coord == from:
		overlay.set_hover_path([] as Array[Vector2i])
		return
	if not grid.is_walkable(hover_coord) or grid.get_actor_at(hover_coord) != &"":
		overlay.set_hover_path([] as Array[Vector2i])
		return
	# Build live actor-block list — same convention as _resolve_move_intent
	# and the move-zone occupied list, so paths match the boundary visually.
	var blocked: Array = []
	for actor_v in registry.all():
		if not (actor_v is Actor):
			continue
		var a: Actor = actor_v
		if a == player or not a.is_alive():
			continue
		var c: Vector2i = grid.get_coord(a.actor_id)
		if c != Vector2i(-1, -1):
			blocked.append(c)
	var path: Array = grid.find_path_around(from, hover_coord, blocked)
	if path.size() < 2:
		overlay.set_hover_path([] as Array[Vector2i])
		return
	# Cap to effective_speed — only show preview if it's actually reachable
	# THIS turn (path.size() - 1 = number of steps).
	if path.size() - 1 > player.effective_speed():
		overlay.set_hover_path([] as Array[Vector2i])
		return
	# Re-type Array → Array[Vector2i] for the typed setter.
	var typed: Array[Vector2i] = []
	for c in path:
		typed.append(c)
	overlay.set_hover_path(typed)


## 029 / req-6: hover-on-enemy → cast-intent tooltip dispatch. State-tracked so
## moving the cursor between hexes doesn't spam show_tooltip every frame —
## tooltip only re-renders when the hovered actor id actually changes.
func _refresh_intent_tooltip(hovered_id: StringName) -> void:
	# Resolve to "do we have an enemy with a planned cast under cursor?"
	var new_id: StringName = &""
	if hovered_id != &"" and registry != null:
		var hov: Actor = registry.get_actor(hovered_id)
		if hov != null and hov.team == &"enemy" and hov.is_alive() and hov.cast_intent != null:
			new_id = hovered_id
	if new_id == _hover_intent_actor_id:
		return  # no transition — current tooltip state is correct
	_hover_intent_actor_id = new_id
	var tooltip: Node = get_node_or_null("../HUD/TooltipPanel")
	if tooltip == null:
		return
	if new_id == &"":
		if tooltip.has_method("hide_tooltip"):
			tooltip.hide_tooltip()
		return
	# Render: skill id headline + formatted body. SkillFormatter is the same
	# helper PSP/inspector use — single source of truth, so a buff/CD note
	# changes everywhere at once.
	var actor: Actor = registry.get_actor(new_id)
	var ci: CastIntent = actor.cast_intent as CastIntent
	if ci == null:
		return
	var skill: Skill = SkillDatabase.get_skill(ci.skill_id)
	if skill == null:
		return
	var title: String = "%s → %s" % [String(actor.actor_id), String(skill.id)]
	var body: String = SkillFormatter.format_skill(skill)
	if tooltip.has_method("show_tooltip"):
		# anchor=null → tooltip places itself near the mouse pointer (see
		# tooltip_panel.gd::_place_near).
		tooltip.show_tooltip(null, title, body)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			# 026: priority 0 — cancel multi-step cast in progress.
			# Slot-toggle path below is now unreachable while cast-FSM owns input.
			if cast_fsm.is_in_progress():
				cast_fsm.cancel()
				get_viewport().set_input_as_handled()
				return
			# 009-T051 priority chain (post-026):
			#   1. active cast slot → toggle off
			#   2. selection != player → reset selection to player
			#   3. otherwise → open pause menu
			if slot_bar != null and slot_bar.get_active() != -1:
				slot_bar.activate(slot_bar.get_active())  # toggle off
				get_viewport().set_input_as_handled()
				return
			if _selected != null and _selected != player:
				deselect_to_player()
				get_viewport().set_input_as_handled()
				return
			# No selection to clear, no active cast — open pause menu if mounted.
			var pause_menu: Node = get_node_or_null("../HUD/PauseMenu")
			if pause_menu != null and pause_menu.has_method("open"):
				pause_menu.open()
				get_viewport().set_input_as_handled()
				return
			# Last-resort fallback: original behavior (no-op deselect).
			deselect_to_player()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("godmode_spawn_dummy"):
		manekin_spawner.spawn()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("godmode_clear"):
		manekin_spawner.clear_all()
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
			# 027: stunned player can't enter cast FSM. _update_castability
			# already greys the slot visually; this guards the keyboard path.
			if player != null and player.is_stunned() and not cast_fsm.is_in_progress():
				get_viewport().set_input_as_handled()
				return
			# 026: when an FSM cast is in progress, slot keys gate through it.
			if cast_fsm.is_in_progress() and slot_bar != null:
				var active_now: int = slot_bar.get_active()
				if i == active_now:
					# Same slot pressed again — alternate keyboard path.
					# On a self-step, this commits; otherwise it cancels (toggle off).
					if cast_fsm.is_self_step():
						var caster_coord: Vector2i = grid.get_coord(player.actor_id)
						cast_fsm.commit_step(caster_coord, player.actor_id)
					else:
						cast_fsm.cancel()
						slot_bar.activate(i)  # toggle off
				else:
					# Different slot — drop current cast, switch slot. New entry happens
					# only on the next LMB (matches 021 — slot key just selects, doesn't fire).
					cast_fsm.cancel()
					slot_bar.activate(i)
				get_viewport().set_input_as_handled()
				return
			# Default: activate() in SlotBar toggles selection.
			if slot_bar != null:
				slot_bar.activate(i)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			# 026: RMB cancels an in-progress cast instead of moving.
			if cast_fsm.is_in_progress():
				cast_fsm.cancel()
				get_viewport().set_input_as_handled()
				return
			_request_move()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# 026: LMB during cast FSM — commit step or no-op (out-of-range click).
			if cast_fsm.is_in_progress():
				cast_fsm.handle_lmb()
				get_viewport().set_input_as_handled()
				return
			_request_cast_active()
			get_viewport().set_input_as_handled()


# ── Actions ──────────────────────────────────────────────────────────────────

func _wait_turn() -> void:
	if grid._moving or ai.is_world_processing() or _is_wave_transitioning():
		return
	GameLogger.info("Godmode", "player skipped turn")
	TurnManager.advance()


func _request_move() -> void:
	if grid._moving or ai.is_world_processing() or _is_wave_transitioning():
		return
	if player.is_stunned():
		# 027: pill icon over player explains why; no log spam.
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
	if player.effective_speed() <= 0:
		# 027: rooted or speed=0. Pill icon explains.
		GameLogger.info("Godmode", "cannot move (effective_speed=0)")
		return
	var path: Array = grid.find_path(from, coord)
	var dist: int = path.size() - 1
	if dist > player.effective_speed():
		GameLogger.info("Godmode", "too far (effective_speed=%d, distance=%d)" % [player.effective_speed(), dist])
		return
	await grid.move_actor(PLAYER_ID, coord)
	if grid.get_coord(PLAYER_ID) != from:
		TurnManager.advance()
		refresh_overlay()


func _request_cast_active() -> void:
	if slot_bar == null:
		return
	if player != null and player.is_stunned():
		# 027: cast slots are greyed via _update_castability; this guards the
		# direct LMB-to-cast path when an active slot is already selected.
		return
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		return
	var target_id: StringName = grid.get_actor_at(coord)
	var ctx: Dictionary = {
		"registry": registry, "grid": grid,
		"target_id": target_id, "target_coord": coord,
	}
	var active_idx: int = slot_bar.get_active()
	# If a spell is selected and can cast → start the FSM
	if active_idx != -1:
		var skill := slot_bar.get_slot(active_idx) as Skill
		if skill != null and skill.can_apply(player, ctx):
			cast_fsm.start(active_idx)
			# 026 fix: the entry LMB also acts as the commit click for step 0.
			# Without this, the player would have to click twice (once to enter
			# FSM, once to commit). _handle_cast_lmb is safe to call when FSM
			# isn't active (early-returns).
			if cast_fsm.is_in_progress():
				cast_fsm.handle_lmb()
		# Skill slot active → never inspect/deselect on a failed cast.
		return
	# No active skill: inspect hovered actor or hex
	var target_actor: Actor = registry.get_actor(target_id) if target_id != &"" else null
	if target_actor != null:
		select(target_actor)
	elif grid.is_walkable(coord):
		inspect_hex(coord)


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
