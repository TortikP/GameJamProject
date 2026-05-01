extends Label
## FloatingNumber — single floating combat-text ephemeral. Auto-frees after
## its rise+fade tween completes.
##
## Created and configured by FloatingNumberLayer.spawn(...). Don't instance
## directly — go through the layer so positioning is consistent.
##
## kind ∈ &"damage" / &"heal" / &"miss" / &"buff" / &"debuff" / &"crit"

const RISE_PIXELS: float = 24.0
const DURATION_MS: int = 700
const CRIT_DURATION_MS: int = 1100
const FADE_IN_PORTION: float = 0.20  # 0→1 alpha over first 20%
const HOLD_PORTION: float = 0.45     # held at full alpha
# remainder fades out


func setup(world_pos: Vector2, amount: int, kind: StringName) -> void:
	# Configure text + color before adding to scene.
	var prefix: String = ""
	var color: Color = UiTheme.TEXT
	var size_kind: String = "num_large"
	match kind:
		&"damage":
			prefix = "−"
			color = UiTheme.SEM_DAMAGE
		&"heal":
			prefix = "+"
			color = UiTheme.SEM_HEAL
		&"miss":
			prefix = ""
			color = UiTheme.TEXT_DIM
			size_kind = "small"
		&"buff":
			prefix = "↑ "
			color = UiTheme.SEM_BUFF
			size_kind = "body"
		&"debuff":
			prefix = "↓ "
			color = UiTheme.SEM_DEBUFF
			size_kind = "body"
		&"crit":
			prefix = "CRIT "
			color = UiTheme.SEM_DAMAGE
			# Crits land hard — biggest in-world text size we have.
			size_kind = "num_huge"
	if kind == &"miss":
		text = "miss"
	else:
		text = "%s%d" % [prefix, abs(amount)]
	UiTheme.apply_label_kind(self, size_kind)
	add_theme_color_override("font_color", color)
	# All in-world combat text gets the strong dark outline so it reads against
	# any background — visibility doctrine in CLAUDE.md.
	UiTheme.apply_world_text_outline(self)
	position = world_pos
	# Center horizontally on the spawn point — Label's text aligns to its rect
	# left edge by default; we want the rect centered on world_pos.
	pivot_offset = size * 0.5


func _ready() -> void:
	# Center the rect on its spawn point now that size is known.
	position -= size * 0.5
	# Slight horizontal jitter for stacked-numbers case (per design C11).
	position.x += randf_range(-10.0, 10.0)

	var dur_ms: int = CRIT_DURATION_MS if text.begins_with("CRIT") else DURATION_MS
	var dur_s: float = dur_ms / 1000.0

	# Rise + fade via Tween. Modulate.a animated through tween_method for the
	# segmented fade (in / hold / out) — simpler than chaining 3 tweeners.
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:y", position.y - RISE_PIXELS, dur_s)
	tw.tween_method(_set_alpha, 0.0, 1.0, dur_s)
	tw.chain().tween_callback(queue_free)


func _set_alpha(t: float) -> void:
	# t ∈ [0, 1] mapped to fade-in / hold / fade-out segments.
	var a: float
	if t < FADE_IN_PORTION:
		a = t / FADE_IN_PORTION
	elif t < FADE_IN_PORTION + HOLD_PORTION:
		a = 1.0
	else:
		var rem: float = 1.0 - FADE_IN_PORTION - HOLD_PORTION
		a = 1.0 - (t - FADE_IN_PORTION - HOLD_PORTION) / max(rem, 0.001)
	modulate.a = clampf(a, 0.0, 1.0)
