extends Node

## RunScore — current run's accumulated score (autoload).
##
## 024-wave-editor: WaveController calls add(unused_turns) on auto-clear of
## each wave; HUD score_corner widget subscribes to score_changed to repaint
## with a punch tween. Resets on EventBus.run_started so a new playthrough
## starts at zero without explicit caller code.
##
## Stateless / process-mode independent: this is a pure counter, no nodes
## under it. Lives at /root/RunScore.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# Total score for the current run. Read directly or via the signal.
var total: int = 0

signal score_changed(total: int, delta: int)


func _ready() -> void:
	# Reset at the start of each run. EventBus.run_started exists in the
	# autoload list (signal in event_bus.gd) but we guard with has_signal in
	# case the bus is ever re-shaped.
	if EventBus.has_signal("run_started"):
		EventBus.run_started.connect(reset)


func add(delta: int) -> void:
	if delta == 0:
		return
	total += delta
	GameLogger.info("RunScore", "+%d → %d" % [delta, total])
	score_changed.emit(total, delta)


func reset() -> void:
	if total == 0:
		# Still emit so listeners can re-render (e.g. score corner remounted
		# in a new scene needs to draw "0").
		score_changed.emit(0, 0)
		return
	total = 0
	GameLogger.info("RunScore", "reset → 0")
	score_changed.emit(total, 0)
