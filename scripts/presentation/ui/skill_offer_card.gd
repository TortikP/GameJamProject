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
# 049 / T005: shared icon resolution helper. Inline copy was duplicated
# across SkillOfferCard, TelegraphHex, EnemyDetailsPanel, HexTooltip — hoisted
# into a single static helper to keep behaviour identical everywhere.
const SkillIconResolver = preload("res://scripts/presentation/skill_icon_resolver.gd")
# 049b / T040: gameplay tooltip routed through the same human formatter the
# PSP and HexTooltip use — single source of truth for "what does this skill
# do" text. Lore stays on RichTextLabel (skill.desc) below it.
const SkillFormatter    = preload("res://scripts/presentation/skill_formatter.gd")

const CARD_MIN_SIZE: Vector2 = Vector2(220, 320)

signal card_clicked(card_data: Dictionary)

var _data: Dictionary = {}
var _name_label: Label
var _mode_badge: Label
# 049b / T040: split into TWO description widgets. _gameplay_label holds the
# Localization.t(skill.tooltip) string (primary read — what does it do
# mechanically). _lore_label holds Localization.t(skill.desc) (flavour, dim
# and small). Old single _desc_label was wired to skill.desc only — surfaced
# lore on the offer screen and hid the gameplay numbers entirely.
var _gameplay_label: RichTextLabel
var _lore_label: RichTextLabel
var _mood_row: HBoxContainer
var _icon_rect: TextureRect
# 049b / T040: letter-fallback Label sits next to _icon_rect inside an
# icon container. Visible iff SkillIconResolver returns null (no asset
# exists yet — Katya hasn't shipped the skill icon set). Mirrors the same
# letter-fallback the TelegraphHex and HexTooltip rows use.
var _icon_letter: Label
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
	# 049b / T048: child Controls (Labels, RichTextLabels, TextureRect, etc)
	# default to MOUSE_FILTER_STOP and intercept clicks meant for the card
	# itself — Egor saw flickering hover + dropped clicks when the cursor
	# was over text/icon child rects. The card listens via gui_input on the
	# root, so all descendants must let events pass straight through.
	# Recursive walk is one-shot (children are built once in _build_children).
	_propagate_mouse_filter_ignore(self)


# 049b / T048: walk Control descendants of `node` (excluding `node` itself
# when called with the root) and set mouse_filter to IGNORE. Containers
# default to STOP and would otherwise eat the click.
func _propagate_mouse_filter_ignore(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_propagate_mouse_filter_ignore(child)


func _build_children() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiThemeScript.SP_3)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = UiThemeScript.SP_4
	vbox.offset_top = UiThemeScript.SP_4
	vbox.offset_right = -UiThemeScript.SP_4
	vbox.offset_bottom = -UiThemeScript.SP_4
	add_child(vbox)

	# 049b / T040: icon container — TextureRect (visible when SkillIconResolver
	# resolves) + letter Label fallback (visible otherwise). Same shape as
	# the equivalent slot in HexTooltip rows / TelegraphHex draw — single
	# behaviour everywhere. Centered in the card via SHRINK_CENTER.
	var icon_box := CenterContainer.new()
	icon_box.custom_minimum_size = Vector2(72, 72)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(icon_box)
	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(64, 64)
	_icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_box.add_child(_icon_rect)
	_icon_letter = Label.new()
	# Display kind = FS_DISPLAY (32). Bigger than header so the placeholder
	# letter on a 64px icon slot reads as "this is a deliberate placeholder",
	# not "the icon failed to render".
	UiThemeScript.apply_label_kind(_icon_letter, "display")
	_icon_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_box.add_child(_icon_letter)

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

	# 049b / T040: GAMEPLAY description (primary). Sourced from
	# Localization.t(skill.tooltip) via SkillFormatter.format_skill_human —
	# same text PSP and HexTooltip surface. Body kind, full TEXT colour, no
	# fit_content cap (cards are 320px tall — let the lore fall below). On
	# overflow autowrap takes over; if a tooltip is genuinely too long for
	# 220px width it'll push the card vertically and the modal's HBox row
	# alignment naturally re-centers (skill_offer_modal sets card_min_size
	# but doesn't cap card_max_size).
	_gameplay_label = RichTextLabel.new()
	_gameplay_label.bbcode_enabled = true
	_gameplay_label.fit_content = true
	_gameplay_label.scroll_active = false
	_gameplay_label.add_theme_font_size_override("normal_font_size", UiThemeScript.FS_BODY)
	_gameplay_label.add_theme_color_override("default_color", UiThemeScript.TEXT)
	vbox.add_child(_gameplay_label)

	# 049b / T040: LORE description (secondary). Sourced from
	# Localization.t(skill.desc) — Nikita's flavour copy. Smaller font
	# (FS_SMALL), dim TEXT_DIM colour. Shrinks under gameplay to keep the
	# focus where the player actually reads. SIZE_EXPAND_FILL on the lore
	# rather than gameplay so a really long lore string scrolls/grows but
	# doesn't push the gameplay text off-screen.
	_lore_label = RichTextLabel.new()
	_lore_label.bbcode_enabled = true
	_lore_label.fit_content = true
	_lore_label.scroll_active = false
	_lore_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lore_label.add_theme_font_size_override("normal_font_size", UiThemeScript.FS_SMALL)
	_lore_label.add_theme_color_override("default_color", UiThemeScript.TEXT_DIM)
	vbox.add_child(_lore_label)


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

	# 049b / T040: gameplay description goes in the primary slot. Sourced
	# from format_skill_human (same as PSP / HexTooltip) — falls back to
	# "[ДОБАВИТЬ]" placeholder when the tooltip key is missing, which is
	# fine here too: designer-visible signal that something needs writing.
	_gameplay_label.text = SkillFormatter.format_skill_human(skill)

	# 049b / T040: lore description in the secondary slot. Localization.t
	# of skill.desc with the same key as fallback so missing-key shows the
	# raw key for designer attention. Was the only thing on the card pre-
	# 049b — now it's flavour text underneath the mechanical answer.
	var desc_key: String = String(skill.desc) if skill != null and "desc" in skill else ""
	var desc_text: String = Localization.t(desc_key, desc_key) if desc_key != "" else ""
	_lore_label.text = desc_text

	# 049b / T040: icon — texture if SkillIconResolver finds one, else show
	# the letter fallback Label (first letter of localised skill name, big).
	# Same fallback strategy as TelegraphHex._draw_icon and HexTooltip rows;
	# Katya's skill icons aren't in the repo yet, so the fallback is the
	# default visible state until they land.
	var tex: Texture2D = SkillIconResolver.resolve(skill)
	if tex != null:
		_icon_rect.texture = tex
		_icon_rect.visible = true
		_icon_letter.visible = false
	else:
		_icon_rect.texture = null
		_icon_rect.visible = false
		var letter: String = ""
		if display_name != "":
			letter = display_name.substr(0, 1).to_upper()
		_icon_letter.text = letter
		_icon_letter.visible = true


# 049 / T005: _resolve_icon body moved to SkillIconResolver.resolve(). Method
# kept as a thin shim so external callers (if any — grep finds none in repo)
# don't break. Safe to remove in a follow-up cleanup.
func _resolve_icon(skill) -> Texture2D:
	return SkillIconResolver.resolve(skill)


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
