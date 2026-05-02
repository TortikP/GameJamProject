extends Node
## GodmodeController — slim orchestrator for the godmode sandbox scene.
##
## Owns: scene-tree ref resolution, module accessors, selection facade,
## SlotBar signal pump, right-click ability picker. NO game logic — that
## lives in the 8 sibling modules under this node (see _resolve_modules
## and 032-controller-refactor/plan.md §"Architecture").
##
## Init order:
##   1. _ready: _resolve_modules() — populates module accessor properties
##   2. _ready: setup.run() — orchestrates everything else (level load,
##      player place, slot seed, signal hookups, WaveController spin-up)

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var grid: HexGrid
@export var registry: ActorRegistry
@export var player: Actor
@export var slot_bar_path: NodePath  # path to HBoxContainer with slot_bar.gd
@export var inspector_path: NodePath
@export var overlay_path: NodePath
@export var player_status_panel_path: NodePath  # 016/F-034 — was hardcoded "../HUD/PlayerStatusPanel"

# Shared scene-tree refs — public so sibling modules can read them via _ctrl.X.
# Resolved by GodmodeSetup.run() in _ready.
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

# Selection / picker private state
var _selected: Actor      # currently inspected actor (default: player)
var _ability_picker: PopupMenu = null   # right-click slot → pick ability
var _picker_target_slot: int = 0        # which slot the picker is assigning to


func _ready() -> void:
	_resolve_modules()
	if setup != null:
		setup.run()
	# 035-game-editor: notify CampaignController (and any future scene-aware
	# listener) that this scene's init is complete. Read-only signal — no
	# listener may mutate world state from here.
	EventBus.scene_ready.emit(&"godmode")


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


# 024 / T53e — proxy for WaveController.is_transitioning so input gates
# stay terse. Returns false when no wave controller is mounted (procedural
# sandbox).
func _is_wave_transitioning() -> bool:
	return wave_controller != null and wave_controller.is_transitioning()


# ── Selection / Inspector / Overlay facade ───────────────────────────────────
# Kept on controller because (a) selection is a small concern with no clear
# home among the modules, (b) inspector + overlay are presentation glue not
# gameplay rules, (c) sibling modules call into these as a stable API.

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
	# 031 phase 12+13: idle slot preview shows only the *current* ability's
	# range — abilities[0] when idle, abilities[_step] during FSM. Painting
	# the full ability list would mix every step's range/area into one
	# mash-up. cast_fsm.current_preview_ability() is the shared source of
	# truth with the zone-area preview in HoverDispatcher.update_castability.
	var ability_items: Array = []
	if cast_fsm != null:
		var preview_ability: Ability = cast_fsm.current_preview_ability()
		if preview_ability != null:
			ability_items.append(preview_ability)
	overlay.show_for(player, registry, ability_items)


# ── Signal handlers wired by GodmodeSetup ────────────────────────────────────

func _on_inspector_speed_changed(_actor: Actor) -> void:
	refresh_overlay()


func _on_actor_died_for_selection(id: StringName) -> void:
	if _selected != null and _selected.actor_id == id:
		deselect_to_player()


# 041 follow-up: generic dead-actor cleanup. Pre-existing bug: only
# F1-spawned manekins had `died.connect(ManekinSpawner._on_actor_died)`
# wired up during spawn(); wave-spawned and CreateEffect-summoned actors
# went through LevelLoader.spawn_enemy_at, which doesn't connect anything,
# so they were left dangling on the scene tree and on the grid after death.
# Centralised here via EventBus.actor_died (one global listener handles all
# enemy spawn paths). Player is filtered out — sandbox respawn (F2) and
# future death-screen flows expect the node to remain.
func _on_actor_died_for_cleanup(id: StringName) -> void:
	if id == &"" or id == &"player":
		return
	var actor: Actor = registry.get_actor(id) if registry != null else null
	if actor == null:
		return
	if actor.team == &"player" and actor == player:
		return  # safety net — never free the player node
	if grid != null:
		grid.clear_actor(id)
	if registry != null:
		registry.unregister(id)
	actor.queue_free()
	# A killed enemy's intent label should disappear with it.
	if telegraphs != null and telegraphs.has_method("refresh"):
		telegraphs.refresh()


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

## Builds a PopupMenu with all SkillDatabase IDs. Called once via call_deferred
## from GodmodeSetup.run() (deferred so SlotBar's _ready has connected its
## slot_right_clicked signal first).
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
	# 034: get-or-clone. If the player already owns a copy of this skill
	# (e.g. it's already in another slot), reuse it so its cooldown state
	# is shared between slots — same spell, one cooldown. Only mint a new
	# clone when the player doesn't yet own this id.
	var skill: Skill = _get_or_clone_player_skill(skill_id)
	if skill == null:
		return
	if slot_bar != null:
		slot_bar.set_slot(_picker_target_slot, skill)
	# 031 phase 2: rebuild player._skills so the new slot's cooldown ticks.
	sync_player_skills_from_slots()
	GameLogger.info("Godmode", "Slot %d ← %s" % [_picker_target_slot, skill_id])


# 034: returns the player's existing per-instance Skill if they already
# have one for this id, else mints a fresh clone from the DB. Keeps the
# DB-shared resource read-only at runtime.
func _get_or_clone_player_skill(skill_id: StringName) -> Skill:
	if player != null:
		var existing: Skill = player.get_skill_by_id(skill_id)
		if existing != null:
			return existing
	var src: Skill = SkillDatabase.get_skill(skill_id)
	if src == null:
		return null
	return src.clone_for_owner()


# 031 phase 2: rebuild Actor._skills from the current slot bar contents.
# Slot bar holds the canonical Skill resources for the player; this just
# mirrors them onto the Actor so the cooldown tick (driven from
# AiDriver._tick_all_skills via Actor.tick_skills) reaches the same instances
# that the player actually casts. De-duped — same skill in two slots ticks once.
# Public so GodmodeSetup can call it after _seed_slots.
# 038: also drives MoodTracker — same deduped list, single recompute per
# slot mutation. Future single-instance-per-slot model makes the dedup a noop.
func sync_player_skills_from_slots() -> void:
	if player == null or slot_bar == null:
		return
	var skills: Array = []
	for i in 4:
		var sk: Skill = slot_bar.get_slot(i) as Skill
		if sk != null and not skills.has(sk):
			skills.append(sk)
	player.set_skills(skills)
	MoodTracker.recompute_from_skills(skills)


## 016/F-034 — resolves PlayerStatusPanel via @export NodePath, with fallback
## to the historical hardcoded "../HUD/PlayerStatusPanel" so godmode still boots
## in test scene-tree variations where the @export wasn't set.
func _get_player_status_panel() -> Node:
	if player_status_panel_path != NodePath(""):
		var psp := get_node_or_null(player_status_panel_path)
		if psp != null:
			return psp
	return get_node_or_null("../HUD/PlayerStatusPanel")


# ── 007 skill dev smoke test ──────────────────────────────────────────────
# Removed in 013: standalone hotkey was redundant once godmode gained
# RMB-assign of any skill to QWER slots. test_vamp_strike still lives in
# data/skills/ — assign to a slot via RMB on the skill button to smoke-test.
