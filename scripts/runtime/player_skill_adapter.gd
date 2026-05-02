## PlayerSkillAdapter — bridge between SkillOfferController and the live
## player's skill set.
##
## The "player skill set" is a tri-store in current architecture:
##   - SlotBar (UI, 4 slots Q/W/E/R) — canonical visual + key binding.
##   - Actor._skills (Array[Skill]) — what cooldowns tick on, what cast
##     resolves through.
##   - GodmodeController.sync_player_skills_from_slots() — the mirror
##     function that pushes SlotBar → Actor._skills + drives MoodTracker.
##
## We don't add a parallel store. We mutate via SlotBar (because that's
## what the existing godmode UI reads on every frame for castability +
## cooldown overlay) then call sync_player_skills_from_slots so cooldown
## ticking + mood recompute behave identically to the right-click
## ability-picker flow (godmode_controller._on_ability_picker_selected).
##
## All methods are static. Lookup is lazy: each call walks the scene tree
## from /root for a node named "GodmodeController". Cheap enough for
## between-wave use (handful of calls per offer).
##
## NULL-tolerance: if no GodmodeController is in the tree (e.g. running
## the offer modal from a smoke scene without godmode), all writes are
## no-ops with a warn-once log; reads return empty.
##
## Owner: Andrey / 040.

class_name PlayerSkillAdapter

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const SLOT_COUNT: int = 4

# warn-once tracking
static var _warned_no_controller: bool = false


# ── Lookup helpers ──────────────────────────────────────────────────────────

static func _controller() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	# GodmodeController lives at <root>/Godmode/GodmodeController in
	# scenes/dev/godmode.tscn. find_child(recursive=true) handles both that
	# and any future re-parenting.
	return tree.root.find_child("GodmodeController", true, false)


static func _slot_bar(ctrl: Node) -> Node:
	if ctrl == null:
		return null
	# Public field on godmode_controller.gd, populated by GodmodeSetup.
	if "slot_bar" in ctrl:
		return ctrl.slot_bar
	return null


static func _player(ctrl: Node) -> Node:
	if ctrl == null:
		return null
	if "player" in ctrl:
		return ctrl.player
	return null


# ── Read API ────────────────────────────────────────────────────────────────

## Returns Array[Skill] currently held by the player (deduplicated; same
## skill in two slots is one entry). Empty array if no controller.
static func owned_skills_array() -> Array:
	var out: Array = []
	var ctrl: Node = _controller()
	if ctrl == null:
		_warn_no_controller()
		return out
	var bar: Node = _slot_bar(ctrl)
	if bar == null or not bar.has_method("get_slot"):
		return out
	for i in SLOT_COUNT:
		var sk = bar.get_slot(i)
		if sk != null and not out.has(sk):
			out.append(sk)
	return out


## Returns Dictionary[StringName, Skill]. One entry per unique owned skill.
static func owned_skills_dict() -> Dictionary:
	var d: Dictionary = {}
	for sk in owned_skills_array():
		if sk != null and "id" in sk:
			d[sk.id] = sk
	return d


## True iff the player has at least one slot holding a Skill with this id.
static func has_skill(id: StringName) -> bool:
	return owned_skills_dict().has(id)


## True iff this skill can have its level bumped. Current rule: any owned
## skill is upgradable (level += 1 unconditionally). When 021/026 grow a
## max_level field this becomes `level < max_level`.
static func can_upgrade(id: StringName) -> bool:
	return has_skill(id)


## Returns slot indices 0..3 currently filled. Used by the replace-slot
## sub-screen to know which slots to offer.
static func filled_slot_indices() -> Array:
	var out: Array = []
	var ctrl: Node = _controller()
	if ctrl == null:
		return out
	var bar: Node = _slot_bar(ctrl)
	if bar == null or not bar.has_method("get_slot"):
		return out
	for i in SLOT_COUNT:
		if bar.get_slot(i) != null:
			out.append(i)
	return out


## Returns the first empty slot index, or -1 if all 4 are filled.
static func first_empty_slot() -> int:
	var ctrl: Node = _controller()
	if ctrl == null:
		return -1
	var bar: Node = _slot_bar(ctrl)
	if bar == null or not bar.has_method("get_slot"):
		return -1
	for i in SLOT_COUNT:
		if bar.get_slot(i) == null:
			return i
	return -1


# ── Write API ───────────────────────────────────────────────────────────────

## Add a fresh clone of `id` into the first empty slot. Returns true on
## success. If all slots are full, returns false (caller should have
## fallen back to replace mode at card-build time).
static func add_skill(id: StringName) -> bool:
	var ctrl: Node = _controller()
	if ctrl == null:
		_warn_no_controller()
		return false
	var bar: Node = _slot_bar(ctrl)
	if bar == null or not bar.has_method("set_slot"):
		return false
	var slot: int = first_empty_slot()
	if slot < 0:
		GameLogger.warn("PlayerSkillAdapter", "add_skill('%s') — no empty slot" % id)
		return false
	var skill: Skill = SkillDatabase.get_skill(id)
	if skill == null:
		GameLogger.warn("PlayerSkillAdapter", "add_skill('%s') — not in SkillDatabase" % id)
		return false
	bar.set_slot(slot, skill.clone_for_owner())
	_sync(ctrl)
	GameLogger.info("PlayerSkillAdapter", "add_skill('%s') -> slot %d" % [id, slot])
	return true


## Bump level on the player's existing copy of `id`. No-op + false if not
## owned. Increments level by 1 (per OQ-2; future max_level cap goes here).
static func upgrade_skill(id: StringName) -> bool:
	var ctrl: Node = _controller()
	if ctrl == null:
		_warn_no_controller()
		return false
	var d: Dictionary = owned_skills_dict()
	if not d.has(id):
		return false
	var sk = d[id]
	if not ("level" in sk):
		return false
	sk.level += 1
	# 031/034 — Skill is a Resource and slot_bar holds it by reference; the
	# level bump is visible on next cast. Re-sync so MoodTracker recomputes
	# (mood derives from skill.mood which can vary by level in future).
	_sync(ctrl)
	GameLogger.info("PlayerSkillAdapter", "upgrade_skill('%s') -> level=%d" % [id, sk.level])
	return true


## Replace the skill in `slot` with a fresh clone of `id`. Returns true on
## success. slot must be 0..3.
static func replace_slot(slot: int, id: StringName) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	var ctrl: Node = _controller()
	if ctrl == null:
		_warn_no_controller()
		return false
	var bar: Node = _slot_bar(ctrl)
	if bar == null or not bar.has_method("set_slot"):
		return false
	var skill: Skill = SkillDatabase.get_skill(id)
	if skill == null:
		GameLogger.warn("PlayerSkillAdapter", "replace_slot(%d, '%s') — not in SkillDatabase" % [slot, id])
		return false
	bar.set_slot(slot, skill.clone_for_owner())
	_sync(ctrl)
	GameLogger.info("PlayerSkillAdapter", "replace_slot(%d, '%s')" % [slot, id])
	return true


# ── Internal ────────────────────────────────────────────────────────────────

static func _sync(ctrl: Node) -> void:
	# Mirror SlotBar -> Actor._skills + drive MoodTracker. This is the
	# canonical post-mutation step from godmode_controller's own slot
	# changes (_on_ability_picker_selected) so we use it verbatim.
	if ctrl != null and ctrl.has_method("sync_player_skills_from_slots"):
		ctrl.sync_player_skills_from_slots()


static func _warn_no_controller() -> void:
	if _warned_no_controller:
		return
	_warned_no_controller = true
	GameLogger.warn("PlayerSkillAdapter",
		"GodmodeController not in tree — skill mutations will be no-ops " +
		"(this is expected in smoke scenes / dialogue preview / map editor)")
