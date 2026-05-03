extends PanelContainer
## HexTooltip — cursor-anchored summary of every action that targets a hex.
##
## 049 / AC-2: replaces 029's `refresh_intent_tooltip` (single-actor tooltip
## above the enemy sprite). Now hex-driven, not actor-driven: any time the
## cursor sits on a hex with at least one incoming action — player skill
## preview OR enemy intent OR both — we list them in a 3-column table:
##
##   | actor name | skill icon + name | consequence |
##   |  player    | 🔥 Curse           | Slowed (3t) |
##   |  bee_2     | 🗡 Sting           | -8 HP       |
##
## Position: glued to the cursor (`mouse + (SP_2, -size.y - SP_2)`) so the
## predicate "the tooltip explains THIS hex" is unambiguous. Clamped to
## viewport rect so it stays on-screen near the right/top edges.
##
## Driven by HoverDispatcher.refresh_hex_tooltip(coord) — that function
## builds the rows (player preview + enemy intents covering the coord) and
## calls show_for(rows, mouse_pos), or hide_tooltip() on empty/no-activity.
##
## Rows are rebuilt each show — the per-frame guard lives upstream in
## HoverDispatcher (`_last_hex_tooltip_coord`), so any incoming show is
## treated as authoritative.

const SkillIconResolver = preload("res://scripts/presentation/skill_icon_resolver.gd")

@onready var _rows_vbox: VBoxContainer = $VBox/RowsVBox

# Pool of preallocated row containers — grown on demand, shrunk via
# `visible = false` (no queue_free / re-instantiate per frame). 4 is the
# typical max (player + 3 enemies sharing a hex on a busy turn).
var _row_pool: Array[HBoxContainer] = []
var _suppressed: bool = false


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	# Same suppression contract as TooltipPanel — modals (skill_offer,
	# pause_menu, settings) hide the tooltip; closing them re-enables.
	EventBus.ui_modal_opened.connect(_on_modal_opened)
	EventBus.ui_modal_closed.connect(_on_modal_closed)
	hide()


func _apply_theme() -> void:
	# `true` → floating-tooltip variant of the panel stylebox (subtle border,
	# slightly heavier shadow). Same surface as TooltipPanel.
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox(true))


## Public API — render rows at the cursor.
##
## `rows` is Array[Dictionary] with shape:
##   {"actor_name": String, "skill": Skill, "consequence": String}
##
## Empty array hides the tooltip (caller pattern: build rows; if empty,
## hide). `mouse_pos` is the global mouse pos at refresh time — passed in
## explicitly because the tooltip is in a CanvasLayer parent, not under
## HexGrid, so its `get_global_mouse_position` returns CanvasLayer-local
## coords which don't match the dispatch site.
func show_for(rows: Array, mouse_pos: Vector2) -> void:
	if _suppressed or rows.is_empty():
		hide_tooltip()
		return
	_ensure_rows(rows.size())
	for i in rows.size():
		var data: Dictionary = rows[i]
		_populate_row(_row_pool[i], data)
		_row_pool[i].visible = true
	for j in range(rows.size(), _row_pool.size()):
		_row_pool[j].visible = false
	visible = true
	# One-frame defer so size is committed before _place_near_cursor reads
	# it — Control sizing is async after children change. Mirrors
	# TooltipPanel._place_near pattern.
	call_deferred("_place_near_cursor", mouse_pos)


func hide_tooltip() -> void:
	visible = false


# 049 / AC-2: ensure the pool has at least `n` rows; lazily grow without
# ever shrinking past max-seen (cheaper than queue_free + re-instantiate).
func _ensure_rows(n: int) -> void:
	while _row_pool.size() < n:
		var row := _build_row_skeleton()
		_rows_vbox.add_child(row)
		_row_pool.append(row)


# Skeleton: HBox of [ActorLabel, IconRect, SkillLabel, ConsequenceLabel].
# Children built once and reused — _populate_row writes text/textures.
func _build_row_skeleton() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UiTheme.SP_2)
	# Actor name — small caps style, keeps width predictable.
	var actor_label := Label.new()
	UiTheme.apply_label_kind(actor_label, "small")
	actor_label.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(actor_label)
	# Icon rect — 16×16, fixed size so rows align even when fallback letter
	# is used in another row. Letter fallback piggybacks on the same slot:
	# hidden TextureRect, visible Label sibling.
	var icon_box := CenterContainer.new()
	icon_box.custom_minimum_size = Vector2(16, 16)
	var icon_rect := TextureRect.new()
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.custom_minimum_size = Vector2(16, 16)
	var icon_letter := Label.new()
	UiTheme.apply_label_kind(icon_letter, "body")
	icon_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_box.add_child(icon_rect)
	icon_box.add_child(icon_letter)
	hbox.add_child(icon_box)
	# Skill name — body kind, expandable so it pushes the consequence to the
	# right edge.
	var skill_label := Label.new()
	UiTheme.apply_label_kind(skill_label, "body")
	skill_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(skill_label)
	# Consequence — small kind, right-aligned.
	var conseq_label := Label.new()
	UiTheme.apply_label_kind(conseq_label, "small")
	conseq_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(conseq_label)
	return hbox


# Populate a row's labels + icon from a single row dict. Indices are
# fixed by _build_row_skeleton's add_child order; brittle to layout
# changes but cheap and the layout is local to this file.
func _populate_row(hbox: HBoxContainer, data: Dictionary) -> void:
	var skill = data.get("skill")
	var actor_label: Label = hbox.get_child(0)
	var icon_box: CenterContainer = hbox.get_child(1)
	var icon_rect: TextureRect = icon_box.get_child(0)
	var icon_letter: Label = icon_box.get_child(1)
	var skill_label: Label = hbox.get_child(2)
	var conseq_label: Label = hbox.get_child(3)
	# Actor name — try localising as-is; falls back to the raw id for dev.
	var actor_name: String = String(data.get("actor_name", ""))
	actor_label.text = Localization.t(actor_name, actor_name)
	# Icon — texture if SkillIconResolver finds one, else first letter.
	var tex: Texture2D = SkillIconResolver.resolve(skill)
	if tex != null:
		icon_rect.texture = tex
		icon_rect.visible = true
		icon_letter.visible = false
	else:
		icon_rect.texture = null
		icon_rect.visible = false
		var first_letter: String = ""
		if skill != null:
			var nm: String = Localization.t(String(skill.name), String(skill.id))
			if not nm.is_empty():
				first_letter = nm.substr(0, 1).to_upper()
		icon_letter.text = first_letter
		icon_letter.visible = true
	# Skill name + consequence text.
	if skill != null:
		skill_label.text = Localization.t(String(skill.name), String(skill.id))
	else:
		skill_label.text = ""
	conseq_label.text = String(data.get("consequence", ""))


# Place the tooltip glued to the cursor. Above-right of the pointer is the
# convention — the cursor doesn't visually overlap, and the tooltip's
# top-left corner is the most predictable anchor when reading.
# Clamp keeps it on-screen near the right/top edges.
func _place_near_cursor(mouse_pos: Vector2) -> void:
	if not visible:
		return
	var screen_size: Vector2 = get_viewport_rect().size
	var pad: float = float(UiTheme.SP_2)
	var pos: Vector2 = mouse_pos + Vector2(pad, -size.y - pad)
	pos.x = clampf(pos.x, pad, screen_size.x - size.x - pad)
	pos.y = clampf(pos.y, pad, screen_size.y - size.y - pad)
	global_position = pos


func _on_modal_opened(_id: StringName) -> void:
	_suppressed = true
	hide_tooltip()


func _on_modal_closed(_id: StringName) -> void:
	_suppressed = false
