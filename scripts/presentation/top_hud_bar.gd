extends PanelContainer
## TopHudBar — single horizontal strip across the top of the arena/godmode HUD.
## Holds: turn counter, current wave / total, run timer, pause button.
##
## Absorbs the prior turn_counter.gd — this listener replaces it. When this
## scene is instantiated in godmode.tscn, the standalone TurnLabel node is
## demolished (see T038 integration).
##
## API (called by run-loop / arena controller):
##   set_turn(n)
##   set_wave(current, total)
##   set_run_timer(seconds)
##
## Pause button click → emits EventBus.pause_toggled(true). The PauseMenu (C23)
## listens for this AND the ESC key handled by godmode_controller.

@onready var _turn_label: Label    = $HBox/TurnLabel
@onready var _wave_label: Label    = $HBox/WaveLabel
@onready var _timer_label: Label   = $HBox/TimerLabel
@onready var _pause_button: Button = $HBox/PauseButton
@onready var _help_button: Button  = $HBox/HelpButton


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	# turn_counter behavior absorbed: same EventBus signal, same format.
	if EventBus.has_signal("world_turn_ended"):
		EventBus.world_turn_ended.connect(_on_world_turn)
	# Initial sync from TurnManager autoload (was done by old turn_counter._ready).
	if TurnManager and TurnManager.has_method("current"):
		set_turn(TurnManager.current())
	_pause_button.pressed.connect(_on_pause_pressed)
	_help_button.pressed.connect(_on_help_pressed)


func _apply_theme() -> void:
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	UiTheme.apply_label_kind(_turn_label, "header")
	UiTheme.apply_label_kind(_wave_label, "header")
	UiTheme.apply_label_kind(_timer_label, "num_large")
	UiTheme.apply_button_styling(_pause_button)
	UiTheme.apply_button_styling(_help_button)


func set_turn(n: int) -> void:
	_turn_label.text = Localization.tf("ui_top_hud_turn", [n], "Turn: %d")


func set_wave(current: int, total: int) -> void:
	if total <= 0:
		_wave_label.text = Localization.tf("ui_top_hud_wave", [current], "Wave %d")
	else:
		_wave_label.text = Localization.tf("ui_top_hud_wave_total", [current, total], "Wave %d/%d")


func set_run_timer(seconds: float) -> void:
	var s: int = int(seconds)
	var m: int = s / 60
	var sec: int = s % 60
	_timer_label.text = "%d:%02d" % [m, sec]


func _on_world_turn(turn: int) -> void:
	set_turn(turn)


func _on_pause_pressed() -> void:
	EventBus.pause_toggled.emit(true)


func _on_help_pressed() -> void:
	EventBus.help_dropdown_toggle_requested.emit()
