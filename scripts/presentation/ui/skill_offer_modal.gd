extends CanvasLayer
## SkillOfferModal — between-wave skill pick UI (040).
##
## Shape: CanvasLayer (layer=25, above DialogueManager's 20) + Control
## fullscreen + semi-transparent backdrop + centered PanelContainer with
## header/cards/footer.
##
## Two screens:
##   1. card screen — N cards (one per offered skill) + optional Skip.
##   2. slot picker (replace mode only) — shows current 4-slot bar with
##      labels Q/W/E/R; click a slot → emits player_picked with slot_index.
##
## Lifecycle:
##   open(cards, offer)         — instantiates cards, shows screen 1.
##   _on_card_clicked(card_data) — for add/upgrade, emits player_picked
##                                 immediately; for replace, transitions
##                                 to screen 2 with the chosen card pinned.
##   _on_slot_picked(idx)        — emits player_picked with slot_index.
##   skip                        — emits player_picked({mode: skipped}).
##
## Process mode is ALWAYS so input survives the get_tree().paused = true
## that SkillOfferController sets on caller side.
##
## Owner: Andrey / 040.

const UiThemeScript = preload("res://scripts/presentation/ui_theme.gd")
const PlayerSkillAdapterScript = preload("res://scripts/runtime/player_skill_adapter.gd")
const SkillOfferCardScene: PackedScene = preload("res://scenes/ui/skill_offer_card.tscn")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
# 049b / T044: replace screen surfaces both the incoming gameplay text
# (top, full-strength) and the outgoing one (bottom, strikethrough red).
# Same human-formatter the cards / PSP / HexTooltip use — single source.
const SkillFormatter = preload("res://scripts/presentation/skill_formatter.gd")

const MODAL_LAYER: int = 25

signal player_picked(result: Dictionary)

# Built nodes
var _root: Control
var _backdrop: ColorRect
var _center_panel: PanelContainer
var _vbox: VBoxContainer
var _header: Label
var _cards_row: HBoxContainer
var _footer_row: HBoxContainer
var _skip_button: Button

# Slot picker (created lazily)
var _slot_picker: Control
var _slot_picker_pinned_card: Dictionary = {}

# Misc state
var _emitted: bool = false  # one-shot guard


func _init() -> void:
	layer = MODAL_LAYER


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_tree()


func _build_tree() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = UiThemeScript.SHADOW_SOFT_COLOR
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	# CenterContainer auto-centers its single child regardless of child
	# size — the previous PRESET_CENTER on the panel anchored its top-left
	# at viewport center, growing right/down off-screen.
	var centerer := CenterContainer.new()
	centerer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centerer.mouse_filter = Control.MOUSE_FILTER_PASS  # backdrop already stops
	_root.add_child(centerer)

	_center_panel = PanelContainer.new()
	_center_panel.add_theme_stylebox_override("panel", UiThemeScript.make_panel_stylebox(true))
	# Cap horizontal size so wide pools (count=5) don't overflow at 1280.
	# Cards are 220 each; with 3 cards + paddings we want ~720 max, with
	# headroom for a 4th/5th card the cap of 1100 keeps content within
	# the standard 1280 viewport with comfortable margins.
	_center_panel.custom_minimum_size = Vector2(0, 0)
	_center_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_center_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centerer.add_child(_center_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", UiThemeScript.SP_4)
	_center_panel.add_child(_vbox)

	_header = Label.new()
	_header.text = Localization.t("skill_offer.header", "Choose a skill")
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiThemeScript.apply_label_kind(_header, "header")
	_vbox.add_child(_header)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", UiThemeScript.SP_3)
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_child(_cards_row)

	_footer_row = HBoxContainer.new()
	_footer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer_row.add_theme_constant_override("separation", UiThemeScript.SP_3)
	_vbox.add_child(_footer_row)


## Public API — called by SkillOfferController.
func open(cards: Array, offer: Dictionary) -> void:
	_emitted = false
	# Late-build guard: if open() arrives before _ready (shouldn't happen
	# with current spawn flow, but cheap safety).
	if not is_node_ready():
		ready.connect(open.bind(cards, offer), CONNECT_ONE_SHOT)
		return
	_clear_cards_row()
	for card_data in cards:
		var card: Node = SkillOfferCardScene.instantiate()
		_cards_row.add_child(card)
		if card.has_method("bind"):
			card.bind(card_data)
		if card.has_signal("card_clicked"):
			card.card_clicked.connect(_on_card_clicked)

	# Skip button — only when offer.allow_skip == true.
	for child in _footer_row.get_children():
		child.queue_free()
	var allow_skip: bool = bool(offer.get("allow_skip", false))
	if allow_skip:
		_skip_button = Button.new()
		_skip_button.text = Localization.t("skill_offer.skip", "Skip")
		UiThemeScript.apply_button_styling(_skip_button)
		_skip_button.pressed.connect(_on_skip_pressed)
		_footer_row.add_child(_skip_button)


func _clear_cards_row() -> void:
	for child in _cards_row.get_children():
		child.queue_free()


# ── Card flow ──────────────────────────────────────────────────────────────

func _on_card_clicked(card_data: Dictionary) -> void:
	if _emitted:
		return
	var mode: StringName = StringName(str(card_data.get("mode", "add")))
	if mode == &"replace":
		_show_slot_picker(card_data)
		return
	_emit(card_data)


func _on_skip_pressed() -> void:
	if _emitted:
		return
	_emit({"mode": &"skipped"})


# ── Replace-slot sub-screen ────────────────────────────────────────────────

# 049b / T044: outgoing-skill preview panel — fixed at the bottom of the
# slot picker. Filled on slot hover, cleared on hover-exit. Persistent
# reference so hover handlers can mutate it without traversing the tree.
var _replace_outgoing_panel: PanelContainer
var _replace_outgoing_label: RichTextLabel


func _show_slot_picker(card_data: Dictionary) -> void:
	_slot_picker_pinned_card = card_data
	# Hide cards row + footer, show a slot picker beneath the header.
	_cards_row.visible = false
	_footer_row.visible = false

	if _slot_picker != null and is_instance_valid(_slot_picker):
		_slot_picker.queue_free()

	var picker := VBoxContainer.new()
	picker.add_theme_constant_override("separation", UiThemeScript.SP_3)
	picker.alignment = BoxContainer.ALIGNMENT_CENTER

	var skill = card_data.get("skill", null)
	var name_key: String = String(skill.name) if skill != null and "name" in skill else ""
	var sid: String = str(card_data.get("skill_id", ""))
	var display_name: String = Localization.t(name_key, sid) if name_key != "" else sid

	var hint := Label.new()
	hint.text = Localization.tf("skill_offer.replace.prompt", [display_name],
			"Pick a slot to replace with %s")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiThemeScript.apply_label_kind(hint, "body")
	picker.add_child(hint)

	# 049b / T044: INCOMING-skill preview at the top of the picker.
	# Reminds the player exactly what they're getting in exchange — the
	# previous version showed only the localised name in `hint`, so the
	# moment you got past the card screen the actual mechanical effect
	# (damage / range / CD / etc) was off-screen and you had to cancel
	# back to re-read it.
	var incoming_panel := PanelContainer.new()
	incoming_panel.add_theme_stylebox_override("panel", UiThemeScript.make_panel_stylebox())
	var incoming_vbox := VBoxContainer.new()
	incoming_vbox.add_theme_constant_override("separation", UiThemeScript.SP_1)
	incoming_panel.add_child(incoming_vbox)

	var incoming_name := Label.new()
	incoming_name.text = display_name
	incoming_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiThemeScript.apply_label_kind(incoming_name, "header")
	# Tint by skill type — same consequence_color logic the cards / PSP /
	# HexTooltip use. Reads-at-a-glance "what kind of spell".
	if skill != null:
		incoming_name.add_theme_color_override("font_color",
				SkillFormatter.consequence_color(skill))
	incoming_vbox.add_child(incoming_name)

	var incoming_desc := RichTextLabel.new()
	incoming_desc.bbcode_enabled = true
	incoming_desc.fit_content = true
	incoming_desc.scroll_active = false
	incoming_desc.custom_minimum_size = Vector2(360, 0)
	incoming_desc.add_theme_font_size_override("normal_font_size", UiThemeScript.FS_BODY)
	incoming_desc.add_theme_color_override("default_color", UiThemeScript.TEXT)
	incoming_desc.text = SkillFormatter.format_skill_human(skill) if skill != null else ""
	incoming_vbox.add_child(incoming_desc)

	picker.add_child(incoming_panel)

	# Slot row — same Q/W/E/R buttons. With T043, all 4 slots are filled
	# whenever this screen reaches (empty-slot path goes to ADD upstream).
	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", UiThemeScript.SP_2)
	picker.add_child(slots_row)

	var labels: Array = ["Q", "W", "E", "R"]
	for i in 4:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(96, 96)
		var slot_text: String = labels[i]
		var existing = _peek_slot(i)
		if existing != null and "id" in existing:
			var ex_key: String = String(existing.name) if "name" in existing else ""
			var ex_disp: String = Localization.t(ex_key, str(existing.id)) if ex_key != "" else str(existing.id)
			slot_text += "\n%s" % ex_disp
		else:
			slot_text += "\n—"
		btn.text = slot_text
		UiThemeScript.apply_button_styling(btn)
		# T043 makes empty slots impossible here, but keep the disabled
		# branch for forward-compat against future force_replace edge cases.
		btn.disabled = (existing == null)
		btn.pressed.connect(_on_slot_picked.bind(i))
		# 049b / T044: hover wiring — fill / clear the outgoing preview.
		# bind() captures the slot index so the handler knows which slot
		# the cursor entered (mouse_entered is parameterless natively).
		btn.mouse_entered.connect(_on_replace_slot_hover.bind(i))
		btn.mouse_exited.connect(_on_replace_slot_unhover)
		slots_row.add_child(btn)

	# 049b / T044: OUTGOING-skill preview panel at the bottom — fixed
	# vertical position (bottom of the picker VBox) so the player's eye
	# doesn't have to track the cursor as it moves between slots. Red
	# border + RichTextLabel with [s]strikethrough[/s] BBCode communicates
	# "this is being thrown away."
	_replace_outgoing_panel = PanelContainer.new()
	_replace_outgoing_panel.add_theme_stylebox_override("panel",
			_make_replace_outgoing_stylebox())
	_replace_outgoing_panel.custom_minimum_size = Vector2(0, 96)
	_replace_outgoing_label = RichTextLabel.new()
	_replace_outgoing_label.bbcode_enabled = true
	_replace_outgoing_label.fit_content = true
	_replace_outgoing_label.scroll_active = false
	_replace_outgoing_label.custom_minimum_size = Vector2(360, 0)
	_replace_outgoing_label.add_theme_font_size_override("normal_font_size", UiThemeScript.FS_BODY)
	_replace_outgoing_label.add_theme_color_override("default_color", UiThemeScript.SEM_DAMAGE)
	# Default placeholder — replaced by hover handler.
	_replace_outgoing_label.text = Localization.t(
			"skill_offer.replace.hover_hint",
			"Hover a slot to preview what gets replaced.")
	_replace_outgoing_panel.add_child(_replace_outgoing_label)
	picker.add_child(_replace_outgoing_panel)

	# Cancel — back to cards row.
	var cancel_row := HBoxContainer.new()
	cancel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var cancel_btn := Button.new()
	cancel_btn.text = Localization.t("skill_offer.cancel", "Cancel")
	UiThemeScript.apply_button_styling(cancel_btn)
	cancel_btn.pressed.connect(_on_cancel_replace)
	cancel_row.add_child(cancel_btn)
	picker.add_child(cancel_row)

	_slot_picker = picker
	_vbox.add_child(picker)


# 049b / T044: red-bordered stylebox for the outgoing-preview panel.
# Same shape as make_panel_stylebox + 2px SEM_DAMAGE border (vs default
# 1px BORDER) so the "this is being lost" cue reads at a glance without
# yelling.
func _make_replace_outgoing_stylebox() -> StyleBoxFlat:
	var sb: StyleBoxFlat = UiThemeScript.make_panel_stylebox()
	sb.border_color = UiThemeScript.SEM_DAMAGE
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	return sb


# 049b / T044: slot-button hover handler — populate outgoing preview.
# Strikethrough on both the name line and the gameplay description via
# [s]…[/s] BBCode (RichTextLabel native; not supported on plain Label).
func _on_replace_slot_hover(slot_index: int) -> void:
	if _replace_outgoing_label == null:
		return
	var existing = _peek_slot(slot_index)
	if existing == null:
		_replace_outgoing_label.text = "[s]%s[/s]" % Localization.t(
				"skill_offer.replace.empty_slot", "(empty)")
		return
	var ex_key: String = String(existing.name) if "name" in existing else ""
	var ex_id: String = str(existing.id) if "id" in existing else ""
	var ex_disp: String = Localization.t(ex_key, ex_id) if ex_key != "" else ex_id
	var gameplay: String = SkillFormatter.format_skill_human(existing)
	# [b][s]NAME[/s][/b]\n[s]gameplay[/s] — bold name on top, body desc
	# below; both strikethrough. Newline isn't BBCode in RichTextLabel, it
	# just works as plain \n.
	_replace_outgoing_label.text = "[b][s]%s[/s][/b]\n[s]%s[/s]" % [ex_disp, gameplay]


# 049b / T044: hover-exit handler. Decision: keep the last-hovered preview
# pinned rather than clearing on exit. Reasoning — on mobile / slow-pad
# pointers the cursor flickers off-button between slot moves, and clearing
# would create a strobing UX. Last-hover persists until a new slot fires
# its mouse_entered. Clearing is left for the next hover.
func _on_replace_slot_unhover() -> void:
	pass


func _peek_slot(idx: int):
	return PlayerSkillAdapterScript.peek_slot(idx)


func _on_slot_picked(slot_index: int) -> void:
	if _emitted:
		return
	var result: Dictionary = _slot_picker_pinned_card.duplicate()
	result["slot_index"] = slot_index
	_emit(result)


func _on_cancel_replace() -> void:
	if _slot_picker != null and is_instance_valid(_slot_picker):
		_slot_picker.queue_free()
	_slot_picker = null
	_slot_picker_pinned_card = {}
	# 049b / T044: drop refs to children that are about to be freed with
	# the picker. Without this, _on_replace_slot_hover from a stale signal
	# could touch a freed RichTextLabel — Godot 4.6 trap (CLAUDE.md).
	_replace_outgoing_panel = null
	_replace_outgoing_label = null
	_cards_row.visible = true
	_footer_row.visible = true


# ── Emit guard ─────────────────────────────────────────────────────────────

func _emit(result: Dictionary) -> void:
	_emitted = true
	player_picked.emit(result)
