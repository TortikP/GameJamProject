extends Node
## SkillOfferController — autoload (040-wave-skill-choice).
##
## Lifecycle:
##   _ready                 → scan data/skill_offer_pools/ into _pools.
##   level_loaded(level)    → cache LevelData ref. Director-shape hook so
##                            we have the level handy when wave_cleared fires
##                            (WaveController doesn't pass the level along).
##   wave_cleared(idx, _)   → if waves[idx].skill_offer present, build
##                            cards, await dialogue_finished if any chained
##                            039 trigger is playing, open modal, await
##                            player decision, apply pick, emit
##                            skill_offer_closed.
##   battle_ended(victory)  → null _level so a second run starts clean.
##
## Pause behaviour: get_tree().paused = true ON modal open, false on close.
## Modal scene must have process_mode=ALWAYS so its input survives the pause.
## CanvasLayer for the modal is 25 — above DialogueManager (20) so a chained
## 039 dialog can finish before the modal opens (we await dialogue_finished
## first, then pause + open).
##
## Failure modes — every branch must emit skill_offer_closed exactly once
## or WaveController will await forever (it gates _advance_wave on this
## signal when the cleared wave has skill_offer). Guard rail:
## _emit_closed_safely is the only emit site; tracks per-wave-idx fired set
## and warns on double-emit.
##
## Owner: Andrey / 040.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const PlayerSkillAdapterScript = preload("res://scripts/runtime/player_skill_adapter.gd")
const POOLS_DIR: String = "res://data/skill_offer_pools/"
const MODAL_SCENE_PATH: String = "res://scenes/ui/skill_offer_modal.tscn"
const OFFER_SOURCE_POOL: StringName = &"pool"
const OFFER_SOURCE_DEFEATED_ENEMIES: StringName = &"defeated_enemies"

# Pool cache: StringName id → Dictionary (raw parsed JSON).
var _pools: Dictionary = {}

# Most recent level from EventBus.level_loaded. Null between battles.
var _level: LevelData = null

# Active modal instance (one at a time).
var _modal: Node = null

# warn-once tracking
var _warned_missing_skills: Dictionary = {}  # StringName id -> true

# Current-wave loot source: wave index -> Dictionary[StringName skill_id, true].
var _current_wave_index: int = -1
var _defeated_skills_by_wave: Dictionary = {}


func _ready() -> void:
	_scan_pools()
	EventBus.level_loaded.connect(_on_level_loaded)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.actor_died_snapshot.connect(_on_actor_died_snapshot)
	EventBus.wave_cleared.connect(_on_wave_cleared)
	EventBus.battle_ended.connect(_on_battle_ended)


# ── Pool scan ───────────────────────────────────────────────────────────────

func _scan_pools() -> void:
	_pools.clear()
	var dir: DirAccess = DirAccess.open(POOLS_DIR)
	if dir == null:
		GameLogger.info("SkillOfferController", "no pools dir at %s — feature inert" % POOLS_DIR)
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() \
				and fname.ends_with(".json") \
				and not fname.begins_with("_"):
			_load_pool(POOLS_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	GameLogger.info("SkillOfferController", "loaded %d pool(s)" % _pools.size())


func _load_pool(path: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		GameLogger.warn("SkillOfferController", "cannot open %s" % path)
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		GameLogger.warn("SkillOfferController", "bad JSON: %s" % path)
		return
	var d: Dictionary = parsed
	var id_str: String = str(d.get("id", ""))
	if id_str == "":
		GameLogger.warn("SkillOfferController", "%s: missing 'id' — skip" % path)
		return
	var id: StringName = StringName(id_str)
	if _pools.has(id):
		GameLogger.warn("SkillOfferController", "duplicate pool id '%s' (last loaded wins)" % id)
	_pools[id] = d


## Returns sorted list of pool ids for editor dropdowns.
func get_pool_ids() -> Array:
	var ids: Array = _pools.keys()
	ids.sort()
	return ids


func has_pool(id: StringName) -> bool:
	return _pools.has(id)


## Editor-side helper — look up a pool's localised label or fall back to id.
func get_pool_label(id: StringName) -> String:
	var d: Dictionary = _pools.get(id, {})
	var key: String = str(d.get("label_key", ""))
	if key != "":
		var resolved: String = Localization.t(key, str(id))
		return resolved
	return str(id)


# ── Public query — used by WaveController to decide whether to await ────────

## True iff the cleared wave has a non-null `skill_offer` field. Cheap
## (one Dictionary.get + null-check); WaveController calls this before
## awaiting EventBus.skill_offer_closed.
func has_offer_for_wave(wave_index: int) -> bool:
	if _level == null:
		return false
	if wave_index < 0 or wave_index >= _level.waves.size():
		return false
	var w: Dictionary = _level.waves[wave_index]
	var so: Variant = w.get("skill_offer", null)
	return so != null and so is Dictionary


# ── Event handlers ──────────────────────────────────────────────────────────

func _on_level_loaded(level: LevelData) -> void:
	_level = level
	_current_wave_index = -1
	_defeated_skills_by_wave.clear()


func _on_battle_ended(_victory: bool) -> void:
	# Don't drop _level — rerun of same level reuses it. But close any
	# stale modal + drop warn-once state so a new battle has a clean slate.
	_close_modal_if_any()
	_warned_missing_skills.clear()
	_current_wave_index = -1
	_defeated_skills_by_wave.clear()


func _on_wave_started(index: int, _is_special: bool) -> void:
	_current_wave_index = index
	_defeated_skills_by_wave[index] = {}


func _on_actor_died_snapshot(_id: StringName, team: StringName, skill_ids: Array) -> void:
	if team != &"enemy":
		return
	if _current_wave_index < 0:
		return
	if not _defeated_skills_by_wave.has(_current_wave_index):
		_defeated_skills_by_wave[_current_wave_index] = {}
	var wave_skills: Dictionary = _defeated_skills_by_wave[_current_wave_index]
	for sid_raw in skill_ids:
		var sid: StringName = StringName(str(sid_raw))
		if sid == &"":
			continue
		wave_skills[sid] = true
	_defeated_skills_by_wave[_current_wave_index] = wave_skills


func _on_wave_cleared(idx: int, _unused: int) -> void:
	if not has_offer_for_wave(idx):
		return
	var w: Dictionary = _level.waves[idx]
	var offer: Dictionary = w["skill_offer"]
	var pool_id: StringName = StringName(str(offer.get("pool", "")))
	var pool: Dictionary = _pools.get(pool_id, {})
	if pool.is_empty():
		GameLogger.warn("SkillOfferController",
			"wave %d: pool '%s' not found — skipping offer" % [idx, pool_id])
		_emit_closed_safely(idx, &"", &"skipped")
		return

	var effective_pool: Dictionary = _effective_pool_for_offer(idx, pool, offer)
	var cards: Array = _build_cards(effective_pool, offer)
	if cards.is_empty():
		GameLogger.warn("SkillOfferController",
			"wave %d: pool '%s' produced no cards — skipping offer" % [idx, pool_id])
		_emit_closed_safely(idx, &"", &"skipped")
		return

	# Announce intent (lets 039 triggers fire chained dialogue first).
	EventBus.skill_offer_about_to_open.emit(idx, cards.size(), pool_id)

	# T019 — wait for any chained dialogue to finish before pausing the
	# scene. Pausing while DialogueManager is mid-scene would freeze its
	# auto-advance timers and the dialogue would hang forever.
	while DialogueManager.is_playing():
		await EventBus.dialogue_finished

	# Open modal + pause + await pick.
	get_tree().paused = true
	var picked: Dictionary = await _open_modal(cards, offer)
	get_tree().paused = false

	var mode: StringName = StringName(str(picked.get("mode", "skipped")))
	var sid: StringName = StringName(str(picked.get("skill_id", "")))
	if mode != &"skipped":
		_apply_pick(picked)

	_emit_closed_safely(idx, sid, mode)


# ── Card building ───────────────────────────────────────────────────────────

func _effective_pool_for_offer(wave_index: int, pool: Dictionary, offer: Dictionary) -> Dictionary:
	var source: StringName = StringName(str(offer.get("source", OFFER_SOURCE_POOL)))
	if source != OFFER_SOURCE_DEFEATED_ENEMIES:
		return pool

	var defeated: Dictionary = _defeated_skills_by_wave.get(wave_index, {})
	if defeated.is_empty():
		var empty_pool: Dictionary = pool.duplicate(true)
		empty_pool["skills"] = []
		return empty_pool

	var whitelist: Array = pool.get("skills", []) as Array
	var allowed: Array = []
	var seen: Dictionary = {}
	for sid_raw in whitelist:
		var sid: StringName = StringName(str(sid_raw))
		if sid == &"" or seen.has(sid):
			continue
		if not defeated.has(sid):
			continue
		seen[sid] = true
		allowed.append(String(sid))

	var effective: Dictionary = pool.duplicate(true)
	effective["skills"] = allowed
	GameLogger.info("SkillOfferController",
		"wave %d: defeated_enemies source yielded %d whitelist skill(s)" % [wave_index, allowed.size()])
	return effective


func _build_cards(pool: Dictionary, offer: Dictionary) -> Array:
	var skills_in_pool: Array = pool.get("skills", []) as Array
	var weights: Dictionary = pool.get("weights", {}) as Dictionary
	var exclude_owned: bool = bool(offer.get("exclude_owned", false))
	var allow_upgrade: bool = bool(offer.get("allow_upgrade", true))
	var allow_replace: bool = bool(offer.get("allow_replace", true))
	var force_replace: bool = bool(offer.get("force_replace", false))
	var count: int = int(offer.get("count", 3)) + PlayerSkillAdapterScript.offer_count_bonus()

	var owned: Dictionary = PlayerSkillAdapterScript.owned_skills_dict()

	# Filter step: drop unknowns; conditionally drop owned.
	var candidates: Array = []
	for sid_raw in skills_in_pool:
		var sn: StringName = StringName(str(sid_raw))
		if not SkillDatabase.has_skill(sn):
			if not _warned_missing_skills.has(sn):
				_warned_missing_skills[sn] = true
				GameLogger.warn("SkillOfferController", "skill '%s' missing in DB — drop from pool" % sn)
			continue
		if exclude_owned and owned.has(sn):
			continue
		var w: float = float(weights.get(str(sid_raw), 1.0))
		if w <= 0.0:
			continue
		candidates.append({"id": sn, "weight": w})
	if candidates.is_empty():
		return []

	# Sample `count` unique by weight without replacement.
	var picked_ids: Array = _weighted_sample_unique(candidates, count)

	# Resolve each picked id to a card with mode.
	var cards: Array = []
	for pid in picked_ids:
		var card: Dictionary = _make_card_for(pid, owned, allow_upgrade, allow_replace, force_replace)
		if not card.is_empty():
			cards.append(card)
	return cards


func _make_card_for(id: StringName, owned: Dictionary,
		allow_up: bool, allow_repl: bool, force_replace: bool = false) -> Dictionary:
	var skill: Skill = SkillDatabase.get_skill(id)
	if skill == null:
		return {}
	if not owned.has(id):
		var slot_kind: StringName = PlayerSkillAdapterScript.slot_kind_for_skill_id(id)
		# 049b / T043: empty-slot check wins over force_replace. Story maps
		# (story_map_0[1-4].json) set force_replace=true on every wave to
		# encourage build evolution, but the prior order also forced REPLACE
		# even when the player still had an unfilled slot — confusing UX
		# (the screen demanded "swap something out" while a slot sat empty).
		# New rule: if any slot is empty, the new skill is always ADD,
		# regardless of force_replace. force_replace only kicks in once the
		# bar is fully populated.
		if PlayerSkillAdapterScript.first_empty_slot(slot_kind) >= 0:
			return {"skill_id": id, "skill": skill, "mode": &"add", "slot_kind": slot_kind}
		# Bar full — replace path. force_replace just guarantees we don't
		# silently drop the card when allow_repl is also true.
		if allow_repl:
			return {"skill_id": id, "skill": skill, "mode": &"replace", "slot_kind": slot_kind}
		return {}
	# Owned — try upgrade first.
	if allow_up and PlayerSkillAdapterScript.can_upgrade(id):
		var owned_skill = owned[id]
		var next_level: int = (int(owned_skill.level) if "level" in owned_skill else 0) + 1
		return {"skill_id": id, "skill": skill, "mode": &"upgrade", "next_level": next_level,
				"slot_kind": PlayerSkillAdapterScript.slot_kind_for_skill_id(id)}
	if allow_repl:
		return {"skill_id": id, "skill": skill, "mode": &"replace",
				"slot_kind": PlayerSkillAdapterScript.slot_kind_for_skill_id(id)}
	return {}


func _weighted_sample_unique(candidates: Array, count: int) -> Array:
	# Plain weighted reservoir without replacement. Acceptable O(N²) for
	# pool sizes <= 20 (jam-realistic). For larger pools rewrite with the
	# Efraimidis-Spirakis A-Res algorithm.
	var pool: Array = candidates.duplicate()  # shallow copy of dicts
	var picked: Array = []
	while not pool.is_empty() and picked.size() < count:
		var total: float = 0.0
		for c in pool:
			total += float(c.weight)
		if total <= 0.0:
			break
		var r: float = randf() * total
		var acc: float = 0.0
		var chosen_idx: int = pool.size() - 1
		for i in pool.size():
			acc += float(pool[i].weight)
			if r <= acc:
				chosen_idx = i
				break
		picked.append(pool[chosen_idx].id)
		pool.remove_at(chosen_idx)
	return picked


# ── Apply pick ──────────────────────────────────────────────────────────────

func _apply_pick(picked: Dictionary) -> void:
	var mode: StringName = StringName(str(picked.get("mode", "skipped")))
	var sid: StringName = StringName(str(picked.get("skill_id", "")))
	if sid == &"":
		return
	match mode:
		&"add":
			PlayerSkillAdapterScript.add_skill(sid)
		&"upgrade":
			PlayerSkillAdapterScript.upgrade_skill(sid)
		&"replace":
			var slot: int = int(picked.get("slot_index", -1))
			if slot < 0:
				GameLogger.warn("SkillOfferController",
					"_apply_pick replace mode but slot_index=%d — drop" % slot)
				return
			var kind: StringName = StringName(str(picked.get("slot_kind",
					PlayerSkillAdapterScript.slot_kind_for_skill_id(sid))))
			PlayerSkillAdapterScript.replace_slot(slot, sid, kind)


# ── Modal lifecycle ─────────────────────────────────────────────────────────

func _open_modal(cards: Array, offer: Dictionary) -> Dictionary:
	# Phase 3 stub — real modal lands in T015-T018. Until the scene file
	# exists, instantiation falls back to "auto-pick first card" so the
	# wave_cleared → wave_about_to_start flow can be smoke-tested
	# end-to-end. Once skill_offer_modal.tscn ships, the resource_exists
	# branch takes over.
	var scene: PackedScene = null
	if ResourceLoader.exists(MODAL_SCENE_PATH):
		scene = load(MODAL_SCENE_PATH) as PackedScene
	if scene == null:
		GameLogger.warn("SkillOfferController",
			"modal scene not yet available — auto-pick first card as smoke")
		if cards.is_empty():
			return {"mode": &"skipped"}
		return cards[0]

	_modal = scene.instantiate()
	# Modal MUST be process_mode=ALWAYS so its input survives the pause we
	# enable on caller-side. The .tscn root sets this; we double-set here
	# for safety in case someone strips it during a refactor.
	_modal.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_modal)
	if _modal.has_method("open"):
		_modal.open(cards, offer)
	if not _modal.has_signal("player_picked"):
		GameLogger.warn("SkillOfferController",
			"modal scene missing 'player_picked' signal — skipping")
		_close_modal_if_any()
		return {"mode": &"skipped"}
	var result: Variant = await _modal.player_picked
	_close_modal_if_any()
	if result is Dictionary:
		return result
	return {"mode": &"skipped"}


func _close_modal_if_any() -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null


# ── Emit guard ──────────────────────────────────────────────────────────────

func _emit_closed_safely(wave_index: int, picked_id: StringName, mode: StringName) -> void:
	# WaveController awaits exactly one emit per cleared wave with offer.
	# Centralising here lets us defensively avoid double-emit on weird
	# code paths (modal frees during teardown, etc.).
	call_deferred("_emit_closed_deferred", wave_index, picked_id, mode)


func _emit_closed_deferred(wave_index: int, picked_id: StringName, mode: StringName) -> void:
	EventBus.skill_offer_closed.emit(wave_index, picked_id, mode)
	GameLogger.info("SkillOfferController",
		"closed wave=%d picked='%s' mode=%s" % [wave_index, picked_id, mode])
