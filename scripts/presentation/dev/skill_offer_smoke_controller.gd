extends Node
## SkillOfferSmokeController — interactive dev harness for 040 (no Godot
## Editor playtest, no real battle scene). Press buttons → scenario sets
## up slot/level state → emits EventBus.wave_cleared → SkillOfferController
## runs the modal flow → status panel dumps result.
##
## Lives at root and is named "GodmodeController" because PlayerSkillAdapter
## finds the controller via `find_child("GodmodeController", true, false)`.
## The duck-typed surface (slot_bar / player / sync_player_skills_from_slots)
## mirrors the real godmode_controller exactly.
##
## To run: F5 / F6 on `scenes/dev/skill_offer_smoke.tscn`.
##
## Owner: Andrey / 040.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const UiThemeScript = preload("res://scripts/presentation/ui_theme.gd")
const ActorScript = preload("res://scripts/core/actors/actor.gd")

# Duck-typed surface for PlayerSkillAdapter — public field names must match
# real godmode_controller exactly.
var slot_bar: Node = null
var player: Actor = null

# Status panel + log buffer
var _status_label: Label = null
var _log_lines: Array[String] = []

# Button refs (built in _ready, connected to scenario handlers)
var _buttons_box: VBoxContainer = null


func _ready() -> void:
	# 1. Build a real Actor (no scene tree position needed for smoke).
	player = ActorScript.new()
	player.actor_id = &"player"
	player.team = &"player"
	player.max_hp = 100
	player.hp = 100
	add_child(player)

	# 2. Resolve scene-tree refs (built in the .tscn).
	slot_bar = $HUD/SlotBarContainer/SlotBar
	_status_label = $HUD/StatusPanel/StatusScroll/StatusLabel
	_buttons_box = $HUD/ButtonRow

	# 3. Build buttons.
	_make_btn("1. ADD flow (empty slots)", _on_btn_add)
	_make_btn("2. UPGRADE flow (slot 0 = ball_throw)", _on_btn_upgrade)
	_make_btn("3. REPLACE flow (all 4 slots full)", _on_btn_replace)
	_make_btn("4. SKIP flow (allow_skip=true)", _on_btn_skip)
	_make_btn("5. NO-OFFER pass-through", _on_btn_no_offer)
	_make_btn("6. POOL < count (count=10, pool=8)", _on_btn_pool_under)
	_make_btn("7. MISSING pool (auto-skip)", _on_btn_missing_pool)
	_make_btn("8. VALIDATION errors", _on_btn_validation)
	_make_btn("— Reset slots —", _on_btn_reset)
	_make_btn("← Main menu", _on_btn_return)

	# 4. Subscribe to 040 signals so we can render the result.
	EventBus.skill_offer_about_to_open.connect(_on_about_to_open)
	EventBus.skill_offer_closed.connect(_on_closed)

	_log("ready — F5/F6 launched. Click a button.")
	_refresh_status()


# ── Duck-typed surface for PlayerSkillAdapter ──────────────────────────────

func sync_player_skills_from_slots() -> void:
	if player == null or slot_bar == null:
		return
	var skills: Array = []
	for i in 4:
		var sk: Skill = slot_bar.get_slot(i) as Skill
		if sk != null and not skills.has(sk):
			skills.append(sk)
	player.set_skills(skills)
	if _has_autoload("MoodTracker"):
		MoodTracker.recompute_from_skills(skills)


func _has_autoload(node_name: String) -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree != null and tree.root.has_node(node_name)


# ── Button factory ─────────────────────────────────────────────────────────

func _make_btn(text: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320, 32)
	UiThemeScript.apply_button_styling(btn)
	btn.pressed.connect(handler)
	_buttons_box.add_child(btn)


# ── Scenario handlers ──────────────────────────────────────────────────────

func _on_btn_add() -> void:
	_clear_all_slots()
	_setup_offer({
		"pool": "basic", "count": 3,
		"allow_upgrade": true, "allow_replace": true,
		"allow_skip": false, "exclude_owned": false,
	})
	_log("scenario 1: add — empty slots, pick any card → goes to first empty slot")
	_emit_wave_cleared(0)


func _on_btn_upgrade() -> void:
	_clear_all_slots()
	_seed_slot(0, &"ball_throw")
	_setup_offer({
		"pool": "basic", "count": 3,
		"allow_upgrade": true, "allow_replace": false,
		"allow_skip": false, "exclude_owned": false,
	})
	_log("scenario 2: upgrade — slot 0 has ball_throw lv1; if ball_throw appears as UPGRADE card, click it → lv2")
	_emit_wave_cleared(0)


func _on_btn_replace() -> void:
	_clear_all_slots()
	_seed_slot(0, &"ball_throw")
	_seed_slot(1, &"berry_throw")
	_seed_slot(2, &"weaken")
	_seed_slot(3, &"sting")
	_setup_offer({
		"pool": "basic", "count": 3,
		"allow_upgrade": false, "allow_replace": true,
		"allow_skip": false, "exclude_owned": true,
	})
	_log("scenario 3: replace — all 4 slots full + exclude_owned. Pick card → submenu Q/W/E/R → swap")
	_emit_wave_cleared(0)


func _on_btn_skip() -> void:
	_setup_offer({
		"pool": "basic", "count": 3,
		"allow_upgrade": true, "allow_replace": true,
		"allow_skip": true, "exclude_owned": false,
	})
	_log("scenario 4: skip — Skip button visible at the bottom; click → mode=skipped, no slot changes")
	_emit_wave_cleared(0)


func _on_btn_no_offer() -> void:
	# Build a level WITHOUT skill_offer on wave 0.
	var lvl: LevelData = LevelData.new()
	lvl.waves = [{
		"index": 0,
		"is_special": false,
		"turns_to_next": 0,
		"floor": [],
		"objects": [],
		"spawners": [],
	}]
	EventBus.level_loaded.emit(lvl)
	_log("scenario 5: no offer — wave_cleared on a wave WITHOUT skill_offer. Modal must NOT open.")
	EventBus.wave_cleared.emit(0, 0)


func _on_btn_pool_under() -> void:
	_clear_all_slots()
	_setup_offer({
		"pool": "basic", "count": 10,
		"allow_upgrade": true, "allow_replace": true,
		"allow_skip": true, "exclude_owned": false,
	})
	_log("scenario 6: pool < count — pool=8, count=10 → expect ≤8 cards (no crash, modal sizes naturally)")
	_emit_wave_cleared(0)


func _on_btn_missing_pool() -> void:
	_setup_offer({
		"pool": "ghost_pool_does_not_exist", "count": 3,
		"allow_skip": false,
	})
	_log("scenario 7: missing pool — controller warns + auto-emits skipped without modal. Watch CLOSED log.")
	_emit_wave_cleared(0)


func _on_btn_validation() -> void:
	# Build a level with an intentionally bad skill_offer on wave 0.
	var lvl: LevelData = LevelData.new()
	lvl.waves = [{
		"index": 0,
		"is_special": false,
		"turns_to_next": 0,
		"floor": [{ "coord": Vector2i(0, 0), "source_id": 0, "atlas_coord": Vector2i.ZERO }],
		"objects": [],
		"spawners": [{ "coord": Vector2i(0, 0), "kind": &"player", "ref": &"", "timer": 1 }],
		"skill_offer": {
			"pool": "",          # ERR
			"count": 0,          # ERR
			"allow_upgrade": "yes",  # WARN (not bool)
		},
	}]
	var errs: Array[String] = lvl.validate()
	_log("scenario 8: validation — got %d errors:" % errs.size())
	for e in errs:
		_log("  · " + e)


func _on_btn_reset() -> void:
	_clear_all_slots()
	_log("reset — all slots cleared")


func _on_btn_return() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ── Helpers ────────────────────────────────────────────────────────────────

func _clear_all_slots() -> void:
	if slot_bar == null:
		return
	for i in 4:
		slot_bar.set_slot(i, null)
	sync_player_skills_from_slots()


func _seed_slot(idx: int, skill_id: StringName) -> void:
	var src: Skill = SkillDatabase.get_skill(skill_id)
	if src == null:
		_log("WARN seed_slot: skill '%s' not in DB" % skill_id)
		return
	slot_bar.set_slot(idx, src.clone_for_owner())
	sync_player_skills_from_slots()


func _setup_offer(offer: Dictionary) -> void:
	# Build a single-wave LevelData with the offer attached. Skip floor /
	# spawners — SkillOfferController only reads waves[idx].skill_offer.
	var lvl: LevelData = LevelData.new()
	lvl.waves = [{
		"index": 0,
		"is_special": false,
		"turns_to_next": 0,
		"floor": [],
		"objects": [],
		"spawners": [],
		"skill_offer": offer,
	}]
	EventBus.level_loaded.emit(lvl)


func _emit_wave_cleared(wave_index: int) -> void:
	EventBus.wave_cleared.emit(wave_index, 0)


# ── Event listeners ─────────────────────────────────────────────────────────

func _on_about_to_open(idx: int, count: int, pool: StringName) -> void:
	_log("→ ABOUT_TO_OPEN  wave=%d count=%d pool=%s" % [idx, count, pool])


func _on_closed(idx: int, picked: StringName, mode: StringName) -> void:
	_log("← CLOSED         wave=%d picked='%s' mode=%s" % [idx, picked, mode])


# ── Status panel ───────────────────────────────────────────────────────────

func _log(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > 24:
		_log_lines.pop_front()
	GameLogger.info("SkillOfferSmoke", line)
	_refresh_status()


func _refresh_status() -> void:
	if _status_label == null:
		return
	var parts: Array[String] = []
	parts.append("=== SLOTS ===")
	if slot_bar == null:
		parts.append("  <slot_bar not ready>")
	else:
		for i in 4:
			var sk: Skill = slot_bar.get_slot(i) as Skill
			var label: String = ["Q", "W", "E", "R"][i]
			if sk == null:
				parts.append("  %s: <empty>" % label)
			else:
				parts.append("  %s: %s  lv=%d  cd=%d/%d" % [
					label,
					sk.id,
					sk.level,
					sk._cd_remaining,
					sk.cooldown,
				])
	parts.append("")
	parts.append("=== EVENTS (newest at bottom) ===")
	for ln in _log_lines:
		parts.append(ln)
	_status_label.text = "\n".join(parts)
