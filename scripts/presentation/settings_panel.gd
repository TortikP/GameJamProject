extends CanvasLayer
## SettingsPanel — modal with audio sliders, game-speed multiplier, and a
## read-only keybind list.
##
## Audio: writes to AudioServer.set_bus_volume_db(idx, linear_to_db(value)).
## Bus indices resolved by name lookup once at _ready (no failure if a bus
## doesn't exist — that slider becomes a no-op).
##
## Game speed: multiplies Engine.time_scale. NOT GameSpeed.cfg — that's for
## individual battle/UI timings, not global speed. Engine.time_scale is the
## right knob for "play the whole game faster". Reset to 1.0 on close — no,
## actually keep it; it's a user preference, persists across sessions
## (post-jam: serialize to user_prefs.cfg).

const UiHelpers = preload("res://scripts/presentation/ui_signal_helpers.gd")
const KeybindOverlayScript = preload("res://scripts/presentation/keybind_overlay.gd")
const MODAL_ID: StringName = &"settings_panel"
const LANGUAGE_OPTIONS: Array[Dictionary] = [
	{"locale": "en", "label_key": "ui_settings_language_english", "fallback": "English"},
	{"locale": "ru", "label_key": "ui_settings_language_russian", "fallback": "Russian"},
]

@onready var _panel: PanelContainer = $Center/Panel
@onready var _title: Label = $Center/Panel/VBox/Title
@onready var _master_slider: HSlider = $Center/Panel/VBox/MasterRow/MasterSlider
@onready var _master_value: Label = $Center/Panel/VBox/MasterRow/MasterValue
@onready var _music_slider: HSlider = $Center/Panel/VBox/MusicRow/MusicSlider
@onready var _music_value: Label = $Center/Panel/VBox/MusicRow/MusicValue
@onready var _sfx_slider: HSlider = $Center/Panel/VBox/SfxRow/SfxSlider
@onready var _sfx_value: Label = $Center/Panel/VBox/SfxRow/SfxValue
@onready var _gs_slider: HSlider = $Center/Panel/VBox/GameSpeedRow/GameSpeedSlider
@onready var _gs_value: Label = $Center/Panel/VBox/GameSpeedRow/GameSpeedValue
@onready var _language_label: Label = $Center/Panel/VBox/LanguageRow/LanguageLabel
@onready var _language_option: OptionButton = $Center/Panel/VBox/LanguageRow/LanguageOption
@onready var _keybinds_title: Label = $Center/Panel/VBox/KeybindsTitle
@onready var _keybinds_body: Label = $Center/Panel/VBox/KeybindsBody
@onready var _close_btn: Button = $Center/Panel/VBox/ButtonRow/CloseButton

var _master_idx: int = -1
var _music_idx: int = -1
var _sfx_idx: int = -1
var _refreshing_language_options: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	_resolve_bus_indices()
	_master_slider.value_changed.connect(_on_master_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_gs_slider.value_changed.connect(_on_game_speed_changed)
	_language_option.item_selected.connect(_on_language_selected)
	Localization.locale_changed.connect(_on_locale_changed)
	_refresh_language_options()
	_refresh_localized_texts()
	_close_btn.pressed.connect(close)
	# 052: HSlider.value_changed doesn't fire from .tscn defaults — apply
	# slider values to buses on startup so e.g. Music=0.6 in the .tscn is
	# the actual volume from frame 0, not just a label under the bar.
	_apply_initial_volumes()


func _apply_initial_volumes() -> void:
	# Reuses the change handlers so labels and buses stay in sync via the
	# same path as live slider changes. Safe when a bus is missing
	# (_apply_bus_volume early-returns on idx < 0).
	_on_master_changed(_master_slider.value)
	_on_music_changed(_music_slider.value)
	_on_sfx_changed(_sfx_slider.value)


func _apply_theme() -> void:
	if _panel:
		_panel.add_theme_stylebox_override("panel", UiTheme.make_modal_stylebox())
	UiTheme.apply_label_kind(_title, "header")
	UiTheme.apply_label_kind(_keybinds_title, "header")
	UiTheme.apply_label_kind(_keybinds_body, "small")
	for r in [
		[$Center/Panel/VBox/MasterRow/MasterLabel, "body"],
		[_master_value, "num_small"],
		[$Center/Panel/VBox/MusicRow/MusicLabel, "body"],
		[_music_value, "num_small"],
		[$Center/Panel/VBox/SfxRow/SfxLabel, "body"],
		[_sfx_value, "num_small"],
		[$Center/Panel/VBox/GameSpeedRow/GameSpeedLabel, "body"],
		[_gs_value, "num_small"],
		[_language_label, "body"],
	]:
		UiTheme.apply_label_kind(r[0], r[1])
	UiTheme.apply_button_styling(_language_option)
	UiTheme.apply_button_styling(_close_btn)


func _resolve_bus_indices() -> void:
	# Look up bus indices once. If a bus doesn't exist, slider becomes a no-op.
	for i in AudioServer.bus_count:
		var n: String = AudioServer.get_bus_name(i)
		match n.to_lower():
			"master": _master_idx = i
			"music":  _music_idx = i
			"sfx":    _sfx_idx = i


func open() -> void:
	if visible:
		return
	visible = true
	UiHelpers.emit_modal_opened(MODAL_ID, true)
	_close_btn.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	UiHelpers.emit_modal_closed(MODAL_ID, true)


func _on_master_changed(v: float) -> void:
	_master_value.text = Localization.tf("ui_settings_percent_value", [int(round(v * 100.0))], "%d%%")
	_apply_bus_volume(_master_idx, v)


func _on_music_changed(v: float) -> void:
	_music_value.text = Localization.tf("ui_settings_percent_value", [int(round(v * 100.0))], "%d%%")
	_apply_bus_volume(_music_idx, v)


func _on_sfx_changed(v: float) -> void:
	_sfx_value.text = Localization.tf("ui_settings_percent_value", [int(round(v * 100.0))], "%d%%")
	_apply_bus_volume(_sfx_idx, v)


func _on_game_speed_changed(v: float) -> void:
	_gs_value.text = Localization.tf("ui_settings_speed_value", [v], "%.2fx")
	# Engine.time_scale globally affects Tween, Timer, _physics_process delta.
	Engine.time_scale = v


func _refresh_language_options() -> void:
	if _language_option == null:
		return
	_refreshing_language_options = true
	var current := Localization.current_locale()
	_language_option.clear()
	for i in LANGUAGE_OPTIONS.size():
		var option := LANGUAGE_OPTIONS[i]
		var label_key := String(option["label_key"])
		var fallback := String(option["fallback"])
		var locale := String(option["locale"])
		_language_option.add_item(Localization.t(label_key, fallback), i)
		_language_option.set_item_metadata(i, locale)
		if locale == current:
			_language_option.select(i)
	_refreshing_language_options = false


func _on_language_selected(index: int) -> void:
	if _refreshing_language_options:
		return
	var locale := String(_language_option.get_item_metadata(index))
	Localization.set_locale(locale)


func _on_locale_changed(_locale: String) -> void:
	_refresh_language_options()
	_refresh_localized_texts()


func _refresh_localized_texts() -> void:
	if _keybinds_body:
		_keybinds_body.text = KeybindOverlayScript.localized_keybinds_body()
	if _master_value:
		_master_value.text = Localization.tf("ui_settings_percent_value", [int(round(_master_slider.value * 100.0))], "%d%%")
	if _music_value:
		_music_value.text = Localization.tf("ui_settings_percent_value", [int(round(_music_slider.value * 100.0))], "%d%%")
	if _sfx_value:
		_sfx_value.text = Localization.tf("ui_settings_percent_value", [int(round(_sfx_slider.value * 100.0))], "%d%%")
	if _gs_value:
		_gs_value.text = Localization.tf("ui_settings_speed_value", [_gs_slider.value], "%.2fx")


func _apply_bus_volume(bus_idx: int, linear_value: float) -> void:
	if bus_idx < 0:
		return
	if linear_value <= 0.0001:
		AudioServer.set_bus_mute(bus_idx, true)
	else:
		AudioServer.set_bus_mute(bus_idx, false)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(linear_value))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
