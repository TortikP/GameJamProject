extends Control
## DialoguePanel — View layer for dialogue.
## Consumes DialogueLine data, emits signals for DialogueManager.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

signal line_ended
signal choice_picked(index: int)

@onready var _portrait : TextureRect    = $Panel/MarginContainer/HBoxContainer/Portrait
@onready var _name_lbl : Label          = $Panel/MarginContainer/HBoxContainer/VBoxContainer/Name
@onready var _text_lbl : RichTextLabel  = $Panel/MarginContainer/HBoxContainer/VBoxContainer/Text
@onready var _choices  : HBoxContainer  = $Panel/MarginContainer/HBoxContainer/VBoxContainer/Choices
@onready var _image    : TextureRect    = $Panel/MarginContainer/HBoxContainer/Image

var _placeholder_cache: Dictionary = {}  # speaker_id -> ImageTexture
var _full_text: String = ""
var _tween: Tween = null
var _text_complete: bool = false
var _skip_count: int = 0           # 0 = none, 1 = first skip (fill text), 2 = close
var _has_choices: bool = false
var _auto_timer: SceneTreeTimer = null


func _ready() -> void:
	_choices.hide()
	_image.hide()
	set_process_unhandled_input(false)


func show_line(line: Object, speaker_data: Dictionary) -> void:
	_full_text     = line.text
	_has_choices   = line.choices.size() > 0
	_text_complete = false
	_skip_count    = 0
	set_process_unhandled_input(true)

	if _auto_timer != null:
		# can't cancel SceneTreeTimer directly — just ignore its signal via _text_complete flag
		_auto_timer = null

	# Speaker name
	var display_name: String = speaker_data.get("display_name", str(line.speaker))
	_name_lbl.text = display_name

	# Portrait
	_portrait.texture = _resolve_portrait(line, speaker_data)

	# Image slot
	if line.image != "":
		var img_tex = _try_load_texture(line.image)
		if img_tex != null:
			_image.texture = img_tex
			_image.show()
		else:
			_image.hide()
	else:
		_image.hide()

	# Clear choices
	for child in _choices.get_children():
		child.queue_free()
	_choices.hide()

	# Typewriter
	_text_lbl.text = ""
	_text_lbl.bbcode_enabled = true
	_text_lbl.visible_characters = 0
	_text_lbl.text = line.text

	var chars_per_sec: float = GameSpeed.get_value("ui", "dialogue_typewriter_chars_per_sec", 60.0)
	var duration: float = float(line.text.length()) / max(chars_per_sec, 1.0)

	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_text_lbl, "visible_characters", line.text.length(), duration)
	await _tween.finished

	_text_complete = true
	_text_lbl.visible_characters = -1  # ensure full display

	if _has_choices:
		_show_choices(line.choices)
	else:
		var auto_delay: float = GameSpeed.get_value("ui", "dialogue_auto_advance_after_sec", 3.0)
		_auto_timer = get_tree().create_timer(auto_delay)
		var t = _auto_timer  # capture for closure check
		await t.timeout
		if _auto_timer == t:  # not cancelled by new show_line call
			line_ended.emit()


func _show_choices(choices: Array) -> void:
	for i in choices.size():
		var btn := Button.new()
		btn.text = choices[i].get("label", "...")
		var idx := i
		btn.pressed.connect(func(): _on_choice(idx))
		_choices.add_child(btn)
	_choices.show()


func _on_choice(index: int) -> void:
	set_process_unhandled_input(false)
	_choices.hide()
	choice_picked.emit(index)


func _unhandled_input(event: InputEvent) -> void:
	var is_advance := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_advance = true
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			is_advance = true

	if not is_advance:
		return

	get_viewport().set_input_as_handled()

	if _has_choices:
		return  # choices: wait for button click

	if not _text_complete:
		# First skip: fill text immediately
		if _tween != null and _tween.is_running():
			_tween.kill()
		_text_lbl.visible_characters = -1
		_text_complete = true
		_auto_timer = null  # invalidate pending auto-advance
	else:
		# Second skip: close
		set_process_unhandled_input(false)
		_auto_timer = null
		line_ended.emit()


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
	img.fill(Color(0.35, 0.35, 0.35, 1.0))

	# Draw a simple letter in the centre (no font needed — just a label overlay)
	# We return the grey square and let the Name label serve as identifier
	var tex := ImageTexture.create_from_image(img)
	_placeholder_cache[speaker_id] = tex
	return tex
