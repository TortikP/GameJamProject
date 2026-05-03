extends Control
## DialoguePanel — state-machine view. No await inside — all state transitions
## are explicit. DialogueManager awaits line_ended / choice_picked signals.
##
## Palette: applied via UiTheme in _ready (overrides .tscn-set inline stylebox).
## Subscribes to ui_theme_reloaded so F5 restyles without restart.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

signal line_ended
signal choice_picked(index: int)

enum State { IDLE, TYPING, WAITING, CHOICES }

@onready var _panel    : Panel         = $Panel
@onready var _portrait : TextureRect   = $Panel/MarginContainer/HBoxContainer/Portrait
@onready var _name_lbl : Label         = $Panel/MarginContainer/HBoxContainer/VBoxContainer/Name
@onready var _text_lbl : RichTextLabel = $Panel/MarginContainer/HBoxContainer/VBoxContainer/Text
@onready var _choices  : HBoxContainer = $Panel/MarginContainer/HBoxContainer/VBoxContainer/Choices
@onready var _image    : TextureRect   = $Panel/MarginContainer/HBoxContainer/Image

var _placeholder_cache: Dictionary = {}
var _tween: Tween = null
var _state: int = State.IDLE
var _current_line: Object = null


func _ready() -> void:
	_choices.hide()
	_image.hide()
	set_process_input(false)
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)


## Re-applies UiTheme palette to all themable nodes in this panel. Idempotent.
## Replaces the .tscn-baked SubResource StyleBoxFlat with a fresh UiTheme one;
## relabels Name/Text with header/body kinds.
func _apply_theme() -> void:
	# Build a fresh stylebox each call — UiTheme rule: don't share StyleBoxFlat
	# instances between nodes (their bg_color is mutable).
	var sb := UiTheme.make_panel_stylebox()
	# Dialogue panel sits at the bottom of the screen — round only top corners
	# for a "tray" look. Keep horizontal borders for clean delimitation.
	sb.corner_radius_top_left     = 6
	sb.corner_radius_top_right    = 6
	sb.corner_radius_bottom_left  = 0
	sb.corner_radius_bottom_right = 0
	if _panel:
		_panel.add_theme_stylebox_override("panel", sb)
	if _name_lbl:
		UiTheme.apply_label_kind(_name_lbl, "header")
	if _text_lbl:
		_text_lbl.add_theme_font_size_override("normal_font_size", UiTheme.FS_BODY)
		_text_lbl.add_theme_color_override("default_color", UiTheme.TEXT)


func show_line(line: Object, speaker_data: Dictionary) -> void:
	_current_line = line
	_state = State.IDLE   # reset before setup

	var speaker_fallback := String(speaker_data.get("display_name", str(line.speaker)))
	_name_lbl.text = Localization.t("dialogues_speakers_%s_display_name" % str(line.speaker), speaker_fallback)
	_portrait.texture = _resolve_portrait(line, speaker_data)

	if line.image != "":
		var img_tex = _try_load_texture(line.image)
		if img_tex != null:
			_image.texture = img_tex
			_image.show()
		else:
			_image.hide()
	else:
		_image.hide()

	for child in _choices.get_children():
		child.queue_free()
	_choices.hide()

	_text_lbl.bbcode_enabled = true
	_text_lbl.text = Localization.t("dialogues_%s_text" % str(line.id), Localization.t(line.text, line.text))
	# visible_ratio (0..1) handles bbcode correctly — tags are not counted.
	# visible_characters tweening would also need visible_characters_behavior tuning;
	# ratio sidesteps that entirely.
	_text_lbl.visible_ratio = 0.0

	var chars_per_sec: float = GameSpeed.get_value("ui", "dialogue_typewriter_chars_per_sec", 60.0)
	# get_total_character_count() returns visible chars (excludes bbcode tags),
	# so a [b]bold[/b] line gets the right duration regardless of tag overhead.
	var visible_chars: int = _text_lbl.get_total_character_count()
	if visible_chars <= 0:
		visible_chars = _text_lbl.text.length()  # fallback for empty / pre-layout cases
	var duration: float = float(visible_chars) / max(chars_per_sec, 1.0)

	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_text_lbl, "visible_ratio", 1.0, duration)
	_tween.finished.connect(_on_typewriter_done, CONNECT_ONE_SHOT)

	_state = State.TYPING
	set_process_input(true)


func _on_typewriter_done() -> void:
	_text_lbl.visible_ratio = 1.0
	if _current_line.choices.size() > 0:
		_show_choices(_current_line.choices)
		_state = State.CHOICES
	else:
		_state = State.WAITING


func _show_choices(choices: Array) -> void:
	for i in choices.size():
		var btn := Button.new()
		var label := String(choices[i].get("label", "..."))
		var label_key := "dialogues_%s_choices_%d_label" % [str(_current_line.id), i]
		btn.text = Localization.t(label_key, label)
		UiTheme.apply_button_styling(btn)
		var idx := i
		btn.pressed.connect(func(): _on_choice(idx))
		_choices.add_child(btn)
	_choices.show()


func _on_choice(index: int) -> void:
	_state = State.IDLE
	set_process_input(false)
	_choices.hide()
	choice_picked.emit(index)


func _close() -> void:
	_state = State.IDLE
	set_process_input(false)
	line_ended.emit()


func _input(event: InputEvent) -> void:
	var is_advance := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_advance = true
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			is_advance = true

	if not is_advance:
		return

	match _state:
		State.TYPING:
			get_viewport().set_input_as_handled()
			if _tween != null:
				_tween.kill()
			_tween = null
			_on_typewriter_done()
		State.WAITING:
			get_viewport().set_input_as_handled()
			_close()
		State.CHOICES:
			pass  # buttons handle their own clicks
		State.IDLE:
			pass  # absorbs click bleed between lines


# ── Helpers ───────────────────────────────────────────────────────────────────

func _resolve_portrait(line: Object, speaker_data: Dictionary) -> Texture2D:
	var path: String = line.portrait
	if path == "":
		path = speaker_data.get("default_portrait", "")
	if path != "":
		var tex = _try_load_texture(path)
		if tex != null:
			return tex
	return _make_placeholder(str(line.speaker))


func _try_load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	return load(path)


func _make_placeholder(speaker_id: String) -> ImageTexture:
	if _placeholder_cache.has(speaker_id):
		return _placeholder_cache[speaker_id]
	var img := Image.create(160, 160, false, Image.FORMAT_RGBA8)
	img.fill(UiTheme.BG_PANEL_2)
	var tex := ImageTexture.create_from_image(img)
	_placeholder_cache[speaker_id] = tex
	return tex
