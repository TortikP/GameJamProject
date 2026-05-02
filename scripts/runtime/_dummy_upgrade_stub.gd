extends Node

## _DummyUpgradeStub — placeholder listener for upgrade_choice_requested.
## Removed from project.godot as soon as Alexey lands the real upgrade-screen
## spec. Until then, on every level victory in an active game:
##   - Wait [ui]/upgrade_screen_min_display sec (default 2.0).
##   - Show a toast with placeholder text + score bonus info.
##   - Add STUB_SCORE_BONUS to RunScore (default 1 for visible feedback).
##   - Fire on_done.call() so CampaignController can proceed.
##
## STUB_SCORE_BONUS exists so a designer can quickly set it to 0 if the
## "+1 every level" reading distracts during playtests. Per spec §35, AC-G5.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const STUB_SCORE_BONUS: int = 1


func _ready() -> void:
	EventBus.upgrade_choice_requested.connect(_on_upgrade_request)


func _on_upgrade_request(level_score: int, on_done: Callable) -> void:
	GameLogger.info("UpgradeStub", "Upgrade screen requested (level_score=%d)" % level_score)
	# Immediate toast so the player sees something happen even though the
	# real screen doesn't exist yet.
	var msg: String = "Upgrade placeholder (+%d score)" % STUB_SCORE_BONUS
	EventBus.ui_toast_requested.emit(msg, 1.6, &"info")

	# Score bonus is applied immediately so wave_controller's level_completed
	# total — which we already reported — increments visibly during the wait.
	if STUB_SCORE_BONUS != 0:
		RunScore.add(STUB_SCORE_BONUS)

	# Hold the screen long enough that the player feels a beat between level
	# end and transition. Pulled from the existing [ui] key — Andrey can tune.
	await GameSpeed.wait("ui", "upgrade_screen_min_display", 2.0)

	if on_done.is_valid():
		on_done.call()
