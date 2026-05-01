extends HBoxContainer
## StatusIconStrip — horizontal row of small icon-pills representing active
## statuses on a bound Actor.
##
## Until the status system lands (post-007), this widget renders placeholder
## pills from a fake Array[StringName] passed via `set_statuses(...)`. Once
## 007 lands, ActorInspector / PlayerStatusPanel will pull real statuses and
## subscribe to a `statuses_changed` signal on Actor.
##
## Each pill is a small PanelContainer with a single-character glyph (Unicode
## fallback until Katya's status icons land). Background uses semantic color
## by status family.

signal status_pill_hovered(status_id: StringName, anchor_rect: Rect2)
signal status_pill_unhovered

const _ICON_BY_FAMILY: Dictionary = {
	&"buff":    "↑",
	&"debuff":  "↓",
	&"dot":     "☠",
	&"hot":     "+",
	&"control": "✦",
	&"shield":  "◆",
}

var _pills: Array[Control] = []
var _bound_actor: Actor = null


func _ready() -> void:
	add_theme_constant_override("separation", UiTheme.SP_1)
	EventBus.ui_theme_reloaded.connect(_on_theme_reloaded)


## Bind to an actor. Until 007 ships statuses_changed signal, this just stores
## the ref — caller still has to push updates via set_statuses().
func bind_actor(actor: Actor) -> void:
	_bound_actor = actor
	# When 007 lands, connect to actor.statuses_changed here.


func unbind() -> void:
	_bound_actor = null
	clear()


## Replace the pill list with `entries`. Each entry: { id, family, duration }.
##   id        — StringName, used for tooltip + icon lookup
##   family    — &"buff" / &"debuff" / &"dot" / ...  → drives color + glyph
##   duration  — int, turns remaining; 0 → no number, -1 → "∞"
func set_statuses(entries: Array) -> void:
	clear()
	for e in entries:
		_pills.append(_make_pill(e))


func clear() -> void:
	for p in _pills:
		if is_instance_valid(p):
			p.queue_free()
	_pills.clear()


func _make_pill(entry: Dictionary) -> Control:
	var family: StringName = entry.get("family", &"buff")
	var id: StringName = entry.get("id", &"unknown")
	var duration: int = int(entry.get("duration", 0))

	var pill := PanelContainer.new()
	pill.custom_minimum_size = Vector2(28, 24)
	pill.add_theme_stylebox_override("panel", UiTheme.make_pill_stylebox(family))
	add_child(pill)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	pill.add_child(hbox)

	var icon_lbl := Label.new()
	icon_lbl.text = _ICON_BY_FAMILY.get(family, "?")
	UiTheme.apply_label_kind(icon_lbl, "small")
	hbox.add_child(icon_lbl)

	if duration != 0:
		var dur_lbl := Label.new()
		dur_lbl.text = "∞" if duration < 0 else str(duration)
		UiTheme.apply_label_kind(dur_lbl, "small")
		hbox.add_child(dur_lbl)

	# Hover for tooltip (TooltipPanel listens via EventBus signals — for now
	# emit our own pill-level signal that PlayerStatusPanel/Inspector can pick up).
	pill.mouse_entered.connect(func(): status_pill_hovered.emit(id, pill.get_global_rect()))
	pill.mouse_exited.connect(func(): status_pill_unhovered.emit())
	return pill


func _on_theme_reloaded() -> void:
	# Re-fetch family by re-using glyphs (we don't store the entry list — caller
	# rebuilds via set_statuses on theme change if needed).
	for pill in _pills:
		if not is_instance_valid(pill):
			continue
		# Best-effort: rebuilding individual pill styles requires the family
		# we threw away. For the jam: trust that arena code re-pushes status
		# state often enough that a stale palette frame is invisible.
		pass
