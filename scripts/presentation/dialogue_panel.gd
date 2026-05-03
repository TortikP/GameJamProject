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

# 052: mood-driven heroine portrait.
# Speaker id, по которому распознаём главгероиню. Совпадает с ключом в
# data/dialogues/_speakers.json и значением "speaker" в репликах.
const PLAYER_SPEAKER: StringName = &"heroine"

# Mood → portrait file (тематический маппинг, см. specs/052-mood-portrait).
# `neutral` / `chimera` не указаны намеренно — у них нет mood-файла,
# срабатывает fall-through на следующий шаг priority chain в _resolve_portrait.
const MOOD_PORTRAIT: Dictionary = {
	&"tranquility": "res://assets/portraits/aspect_forest.png",
	&"burnout":     "res://assets/portraits/aspect_fire.png",
	&"ascended":    "res://assets/portraits/aspect_heaven.png",
}

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

# 052: cached dominant mood from MoodTracker. Updated via
# EventBus.player_mood_changed; read inside _resolve_portrait when
# speaker == PLAYER_SPEAKER. Initial &"neutral" matches MoodTracker's
# all-zero state — falls through to default_portrait when no signal yet.
var _dominant_mood: StringName = &"neutral"


func _ready() -> void:
	_choices.hide()
	_image.hide()
	set_process_input(false)
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	# 052: track player's dominant mood for heroine portrait swap.
	EventBus.player_mood_changed.connect(_on_player_mood_changed)
	# Sync once on startup in case MoodTracker emitted before our connect
	# (autoload order is .gd-position-dependent in project.godot). Defensive
	# under get_node_or_null — scenes without MoodTracker (smoke tests, dev
	# scenes) just keep the &"neutral" default.
	var mt: Node = get_node_or_null("/root/MoodTracker")
	if mt != null and mt.has_method("get_dominant"):
		_dominant_mood = mt.get_dominant()


## Re-applies UiTheme palette to all themable nodes in this panel. Idempotent.
## Replaces the .tscn-baked SubResource StyleBoxFlat with a fresh UiTheme one;
## relabels Name/Text with header/body kinds.
##
## 047: dialogue panel uses the standard sharp-corner stylebox. Earlier
## attempts at rounded-top corners ("tray look") undermined the Win98
## sharp-edge palette — every other surface is flat-rectangular.
##
## 047 polish: dialogue uses dedicated FS_DIALOGUE_* sizes (much larger
## than FS_HEADER/FS_BODY) — story beats are the focal point during a
## dialogue, not chrome. apply_label_kind isn't used on Name because no
## generic "kind" matches dialogue speaker scale.
func _apply_theme() -> void:
	# Build a fresh stylebox each call — UiTheme rule: don't share StyleBoxFlat
	# instances between nodes (their bg_color is mutable).
	var sb := UiTheme.make_panel_stylebox()
	if _panel:
		_panel.add_theme_stylebox_override("panel", sb)
	if _name_lbl:
		_name_lbl.add_theme_font_size_override("font_size", UiTheme.FS_DIALOGUE_NAME)
		_name_lbl.add_theme_color_override("font_color", UiTheme.TEXT)
	if _text_lbl:
		_text_lbl.add_theme_font_size_override("normal_font_size", UiTheme.FS_DIALOGUE_TEXT)
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

# 052: cache dominant mood for next show_line(). Live update of an already-
# rendered portrait is intentionally skipped — would flash mid-typewriter and
# RMB-replace during an active dialogue is rare. Next line picks it up.
func _on_player_mood_changed(_counts: Dictionary, dominant: StringName) -> void:
	_dominant_mood = dominant


func _resolve_portrait(line: Object, speaker_data: Dictionary) -> Texture2D:
	# Priority chain (spec 052):
	#   1. line.portrait        — explicit per-line override
	#   2. mood-driven heroine  — only when speaker == PLAYER_SPEAKER
	#   3. speaker default      — speaker_data.default_portrait
	#   4. _make_placeholder    — global default_portrait.png / generated quad

	# 1. Explicit per-line override wins.
	if line.portrait != "":
		var line_tex: Texture2D = _try_load_texture(line.portrait)
		if line_tex != null:
			return line_tex

	# 2. Mood-driven heroine portrait.
	# line.speaker is StringName (dialogue_line.gd:12) — direct compare.
	# neutral/chimera intentionally absent from MOOD_PORTRAIT → .get() returns
	# "" → step skipped → fall through to speaker default.
	if line.speaker == PLAYER_SPEAKER:
		var mood_path: String = MOOD_PORTRAIT.get(_dominant_mood, "")
		if mood_path != "":
			var mood_tex: Texture2D = _try_load_texture(mood_path)
			if mood_tex != null:
				return mood_tex

	# 3. Speaker default.
	var default_path: String = speaker_data.get("default_portrait", "")
	if default_path != "":
		var def_tex: Texture2D = _try_load_texture(default_path)
		if def_tex != null:
			return def_tex

	# 4. Placeholder.
	return _make_placeholder(str(line.speaker))


func _try_load_texture(path: String) -> Texture2D:
	# 053: ResourceLoader.exists, not FileAccess.file_exists. The latter
	# checks raw pack contents and misses imported resources in exported
	# .pck builds (the .png source isn't packed; only the .ctex remap is).
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _make_placeholder(_speaker_id: String) -> Texture2D:
	# Spec 050: single global default for all speakers without per-speaker
	# portrait files. Cache key is "__default__" — speaker_id arg kept for
	# backward sig compatibility but unused.
	const CACHE_KEY := "__default__"
	const DEFAULT_PATH := "res://assets/portraits/default_portrait.png"
	if _placeholder_cache.has(CACHE_KEY):
		return _placeholder_cache[CACHE_KEY]
	# Prefer the on-disk default portrait (130×180, matches the slot's
	# 13:18 aspect). When Katya ships per-speaker portraits later, they
	# take priority via _resolve_portrait → speaker_data.default_portrait.
	var tex := _try_load_texture(DEFAULT_PATH)
	if tex != null:
		_placeholder_cache[CACHE_KEY] = tex
		return tex
	# Fallback: flat colored rect at slot dimensions (defensive — covers
	# the case where the asset is missing from a checkout).
	var img := Image.create(130, 180, false, Image.FORMAT_RGBA8)
	img.fill(UiTheme.BG_PANEL_2)
	var fallback := ImageTexture.create_from_image(img)
	_placeholder_cache[CACHE_KEY] = fallback
	return fallback
