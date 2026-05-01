extends CanvasLayer
## PortalTransition — fullscreen interstitial shown between waves.
## Displays wave number, optional flavor text from Nikita, and a continue button.
##
## Auto-advances after `auto_advance_sec` if > 0; otherwise waits for click.
## VFX slot is a placeholder — real tape-rewind shader is post-jam VFX work.

signal continued

@onready var _wave_title: Label = $Center/VBox/WaveTitle
@onready var _vfx_slot: Label = $Center/VBox/VfxSlot
@onready var _flavor_label: Label = $Center/VBox/FlavorLabel
@onready var _continue_btn: Button = $Center/VBox/ContinueButton

var _auto_timer: SceneTreeTimer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	_continue_btn.pressed.connect(_on_continue)


func _apply_theme() -> void:
	UiTheme.apply_label_kind(_wave_title, "display")
	UiTheme.apply_label_kind(_vfx_slot, "small")
	UiTheme.apply_label_kind(_flavor_label, "body")
	UiTheme.apply_button_styling(_continue_btn)


## Show the transition. flavor text optional. auto_advance_sec ≤ 0 → manual.
func show_for_wave(wave_index: int, total: int, flavor: String = "",
		auto_advance_sec: float = 0.0) -> void:
	if total > 0:
		_wave_title.text = "Wave %d / %d" % [wave_index, total]
	else:
		_wave_title.text = "Wave %d" % wave_index
	_flavor_label.text = flavor
	_flavor_label.visible = not flavor.is_empty()
	visible = true
	_continue_btn.grab_focus()
	if auto_advance_sec > 0.0:
		_auto_timer = get_tree().create_timer(auto_advance_sec, true, false, true)
		_auto_timer.timeout.connect(_on_continue, CONNECT_ONE_SHOT)


func _on_continue() -> void:
	_auto_timer = null
	visible = false
	continued.emit()
