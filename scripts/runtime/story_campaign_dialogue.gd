extends Node

## StoryCampaignDialogue -- small listener that turns campaign cutscene hooks
## into deterministic DialogueManager scenes for the authored story campaign.

const VICTORY_DIALOGUE_ID: StringName = &"ending_self_lavender_raf"


func _ready() -> void:
	EventBus.campaign_cutscene_requested.connect(_on_campaign_cutscene_requested)
	EventBus.scene_ready.connect(_on_scene_ready)


func _on_campaign_cutscene_requested(cutscene_id: StringName, on_done: Callable) -> void:
	if cutscene_id == &"" or not DialogueDB.has_line(cutscene_id):
		if on_done.is_valid():
			on_done.call()
		return
	DialogueManager.play(cutscene_id, true)
	await _await_dialogue_idle()
	if on_done.is_valid():
		on_done.call()


func _on_scene_ready(scene_kind: StringName) -> void:
	if scene_kind != &"campaign_end":
		return
	if not DialogueDB.has_line(VICTORY_DIALOGUE_ID):
		return
	DialogueManager.play(VICTORY_DIALOGUE_ID, true)


func _await_dialogue_idle() -> void:
	while DialogueManager.is_playing():
		await EventBus.dialogue_finished
