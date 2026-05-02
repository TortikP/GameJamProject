extends PanelContainer
## SkillOfferCard — one card in the between-wave skill offer modal (040).
##
## Built by SkillOfferModal — receives a card_data Dictionary via bind():
##   {
##     "skill_id": StringName,
##     "skill": Skill,
##     "mode": StringName,           # &"add" | &"upgrade" | &"replace"
##     "next_level": int (optional)  # only for upgrade
##   }
##
## Single Button-style click target. Emits card_clicked(card_data) on press;
## modal handles flow (replace mode opens slot picker; others emit player_picked).
##
## Children built programmatically in _ready (matching slot_bar.gd pattern;
## avoids .tscn churn during rapid spec iteration).
##
## Owner: Andrey / 040.

const UiThemeScript = preload("res://scripts/presentation/ui_theme.gd")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const CARD_MIN_SIZE: Vector2 = Vector2(200, 280)

signal card_clicked(card_data: Dictionary)

var _data: Dictionary = {}
var _name_label: Label
var _mode_badge: Label
var _desc_label: RichTextLabel
var _mood_row: HBoxContainer
var _icon_rect: TextureRect
var _hovered: bool = false


func _ready() -> void:
	custom_minimum_size = CARD_MIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiThemeScript.make_panel_stylebox(true))
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	_build_children()
	_apply_data_to_children()


func _build_children() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiThemeScript.SP_3)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = UiThemeScript.SP_4
	vbox.offset_top = UiThemeScript.SP_4
	vbox.offset_right = -UiThemeScript.SP_4
	vbox.offset_bottom = -UiThemeScript.SP_4
	add_child(vbox)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(64, 64)
	_icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_icon_rect)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiThemeScript.apply_label_kind(_name_label, "header")
	vbox.add_child(_name_label)

	_mode_badge = Label.new()
	_mode_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiThemeScript.apply_label_kind(_mode_badge, "small")
	vbox.add_child(_mode_badge)

	_mood_row = HBoxContainer.new()
	_mood_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_mood_row.add_theme_constant_override("separation", UiThemeScript.SP_1)
	vbox.add_child(_mood_row)

	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.fit_content = true
	_desc_label.scroll_active = false
	_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_label.add_theme_font_size_override("normal_font_size", UiThemeScript.FS_BODY)
	_desc_label.add_theme_color_override("default_color", UiThemeScript.TEXT)
	vbox.add_child(_desc_label)


## Bind a card_data Dictionary. Safe to call before or after _ready.
func bind(card_data: Dictionary) -> void:
	_data = card_data
	if is_node_ready():
		_apply_data_to_children()


func get_card_data() -> Dictionary:
	return _data


func _apply_data_to_children() -> void:
	if _name_label == null:
		return
	var skill = _data.get("skill", null)
	var mode: StringName = StringName(str(_data.get("mode", "add")))
	# Name — Skill.name is a localization key per 021. Try Localization.t,
	# fallback to id.
	var name_key: String = String(skill.name) if skill != null and "name" in skill else ""
	var sid: String = str(_data.get("skill_id", ""))
	var display_name: String = Localization.t(name_key, sid) if name_key != "" else sid
	_name_label.text = display_name

	# Mode badge — short tag designer reads at a glance.
	match mode:
		&"add":
			_mode_badge.text = Localization.t("skill_offer.mode.add", "ADD")
			_mode_badge.add_theme_color_override("font_color", UiThemeScript.SEM_BUFF)
		&"upgrade":
			var lv: int = int(_data.get("next_level", 1))
			_mode_badge.text = Localization.tf("skill_offer.mode.upgrade", [lv], "UPGRADE → LV%d")
			_mode_badge.add_theme_color_override("font_color", UiThemeScript.FOCUS)
		&"replace":
			_mode_badge.text = Localization.t("skill_offer.mode.replace", "REPLACE")
			_mode_badge.add_theme_color_override("font_color", UiThemeScript.SEM_DEBUFF)
		_:
			_mode_badge.text = str(mode).to_upper()

	# Mood — small dim glyphs (no icon db yet).
	for child in _mood_row.get_children():
		child.queue_free()
	if skill != null and "mood" in skill:
		for m in skill.mood:
			var lbl := Label.new()
			lbl.text = "·" + str(m)
			UiThemeScript.apply_label_kind(lbl, "small")
			_mood_row.add_child(lbl)

	# Desc — Skill.desc is a loc key per 021.
	var desc_key: String = String(skill.desc) if skill != null and "desc" in skill else ""
	var desc_text: String = Localization.t(desc_key, desc_key) if desc_key != "" else ""
	_desc_label.text = desc_text

	# Icon — Skill.icon is a StringName id; treat as path hint when it
	# starts with "icons/" or "res:". No real IconDB yet; placeholder when
	# we can't resolve. Don't crash on missing.
	_icon_rect.texture = _resolve_icon(skill)


func _resolve_icon(skill) -> Texture2D:
	if skill == null or not "icon" in skill:
		return null
	var icon_str: String = String(skill.icon)
	if icon_str == "":
		return null
	# Common patterns from data/skills/*.json: "icons/skills/foo.png"
	# (relative) or full res:// path. Try both.
	var candidates: Array[String] = [
		icon_str if icon_str.begins_with("res://") else "",
		"res://assets/" + icon_str,
		"res://" + icon_str,
	]
	for path in candidates:
		if path == "":
			continue
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex is Texture2D:
				return tex
	return null


# ── Hover / click feedback ─────────────────────────────────────────────────

func _on_mouse_entered() -> void:
	_hovered = true
	modulate = UiThemeScript.HOVER_BRIGHTEN


func _on_mouse_exited() -> void:
	_hovered = false
	modulate = Color.WHITE


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			card_clicked.emit(_data)
