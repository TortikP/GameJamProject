extends Node

## Single-slot campaign continue save.

const SAVE_PATH: String = "user://continue_slot.json"
const TUTORIAL_GAME_PATH: String = "res://data/games/tutorial.game.json"
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var _suspend_writes: bool = false


func has_continue_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func is_save_enabled_for_current_game() -> bool:
	return ActiveGame.has_active_game() and ActiveGame.game_path() != TUTORIAL_GAME_PATH


func clear_continue_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var err: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		GameLogger.warn("GameSave", "Failed to remove continue slot: %s" % str(err))


func save_campaign_state(reason: String = "") -> bool:
	if _suspend_writes:
		return false
	if not is_save_enabled_for_current_game():
		return false
	var data: Dictionary = {
		"version": 1,
		"game_path": ActiveGame.game_path(),
		"current_index": ActiveGame.current_index,
		"uses_hub": ActiveGame.uses_hub(),
		"hub_map_path": ActiveGame.hub_map_path(),
		"in_hub": ActiveGame.is_in_hub(),
		"skill_loadout": CampaignController.get_campaign_skill_loadout(),
		"hub_entry_context": CampaignController.pending_hub_entry_context(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		GameLogger.error("GameSave", "Cannot write %s: error %d" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	GameLogger.info("GameSave", "Saved continue slot (%s)" % reason)
	return true


func continue_from_save() -> bool:
	var data := _read_save()
	if data.is_empty():
		return false
	_suspend_writes = true
	var restored: bool = ActiveGame.restore_from_save(data)
	if restored:
		CampaignController.restore_hub_entry_context(data.get("hub_entry_context", ""))
		ActiveGame.emit_current_level_started()
		CampaignController.restore_campaign_skill_loadout(data.get("skill_loadout", []))
	_suspend_writes = false
	if restored:
		save_campaign_state("continue restore")
	return restored


func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		GameLogger.error("GameSave", "Cannot read %s: error %d" % [SAVE_PATH, FileAccess.get_open_error()])
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		GameLogger.error("GameSave", "JSON parse error in continue slot: %s" % json.get_error_message())
		return {}
	var raw: Variant = json.get_data()
	if not (raw is Dictionary):
		GameLogger.error("GameSave", "Continue slot is not a dictionary")
		return {}
	return raw
