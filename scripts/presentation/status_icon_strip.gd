extends HBoxContainer
## StatusIconStrip — horizontal row of small icon-pills representing active
## statuses on a bound Actor.
##
## 027: bind_actor connects to actor.statuses_changed and rebuilds the pill
## list whenever statuses mutate. Each pill renders an icon (TextureRect from
## StatusRegistry.icon_of, if configured) or a unicode glyph fallback by family.
##
## Self-centering: when used over an actor on the world, set center_anchor in
## the .tscn — the strip recomputes its own position.x = anchor.x - width/2
## after every rebuild so the row stays horizontally centered above the actor
## regardless of pill count.

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

# Pill geometry — must match _make_pill / _ready overrides for the
# centering math to be accurate (we don't await a layout pass).
const _PILL_WIDTH: float = 28.0
const _PILL_SEPARATION: float = 4.0   # = UiTheme.SP_1

## World-space anchor (parent-relative) where the strip should be horizontally
## centered. position.y stays = anchor.y; position.x is recomputed to
## anchor.x - width/2 after every rebuild. Default Vector2.ZERO matches
## legacy behaviour (top-left at parent origin).
@export var center_anchor: Vector2 = Vector2.ZERO

var _pills: Array[Control] = []
var _bound_actor: Actor = null


func _ready() -> void:
	add_theme_constant_override("separation", int(_PILL_SEPARATION))
	EventBus.ui_theme_reloaded.connect(_on_theme_reloaded)
	_recenter()


## Bind to an actor. 027: connects to actor.statuses_changed and rebuilds
## the pill list whenever statuses mutate. Idempotent — re-binding the same
## actor is a no-op; binding a different actor disconnects the old signal.
func bind_actor(actor: Actor) -> void:
	if _bound_actor == actor:
		return
	if _bound_actor != null and _bound_actor.statuses_changed.is_connected(_on_statuses_changed):
		_bound_actor.statuses_changed.disconnect(_on_statuses_changed)
	_bound_actor = actor
	if actor != null:
		actor.statuses_changed.connect(_on_statuses_changed)
		_rebuild()


func unbind() -> void:
	if _bound_actor != null and _bound_actor.statuses_changed.is_connected(_on_statuses_changed):
		_bound_actor.statuses_changed.disconnect(_on_statuses_changed)
	_bound_actor = null
	clear()


func _on_statuses_changed(_actor_id: StringName) -> void:
	_rebuild()


# 027: pull current StatusInstance list from actor, map via StatusRegistry.family_of/icon_of,
# pass to the pre-existing set_statuses(entries) renderer.
func _rebuild() -> void:
	if _bound_actor == null:
		clear()
		return
	var entries: Array = []
	for inst_v in _bound_actor.get_statuses():
		var inst := inst_v as StatusInstance
		if inst == null:
			continue
		entries.append({
			"id":       inst.status_id,
			"family":   StatusRegistry.family_of(inst.status_id),
			"icon":     StatusRegistry.icon_of(inst.status_id),
			"duration": inst.duration,
		})
	set_statuses(entries)


## Replace the pill list with `entries`. Each entry: { id, family, icon, duration }.
##   id        — StringName, used for tooltip + icon lookup
##   family    — &"buff" / &"debuff" / &"dot" / ...  → drives color + glyph fallback
##   icon      — String resource path (or "") → TextureRect when present
##   duration  — int, turns remaining; 0 → no number, -1 → "∞"
func set_statuses(entries: Array) -> void:
	clear()
	for e in entries:
		_pills.append(_make_pill(e))
	_recenter()


func clear() -> void:
	for p in _pills:
		if is_instance_valid(p):
			p.queue_free()
	_pills.clear()
	_recenter()


# 027: horizontally centre the strip above center_anchor. Computed from
# pill count + known geometry — no layout-pass await needed.
func _recenter() -> void:
	var n: int = _pills.size()
	var width: float = 0.0
	if n > 0:
		width = n * _PILL_WIDTH + (n - 1) * _PILL_SEPARATION
	position = Vector2(center_anchor.x - width / 2.0, center_anchor.y)


func _make_pill(entry: Dictionary) -> Control:
	var family: StringName = entry.get("family", &"buff")
	var id: StringName = entry.get("id", &"unknown")
	var duration: int = int(entry.get("duration", 0))
	var icon_path: String = String(entry.get("icon", ""))

	var pill := PanelContainer.new()
	pill.custom_minimum_size = Vector2(28, 24)
	pill.add_theme_stylebox_override("panel", UiTheme.make_pill_stylebox(family))
	add_child(pill)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	pill.add_child(hbox)

	# 027: icon if metadata supplies a valid Texture2D path, else fall back to
	# family-glyph Label. ResourceLoader.exists check keeps a misconfigured
	# JSON path from crashing the strip — soft-fall to glyph.
	var used_texture: bool = false
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex: Texture2D = load(icon_path) as Texture2D
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(20, 20)
			hbox.add_child(tr)
			used_texture = true
	if not used_texture:
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
