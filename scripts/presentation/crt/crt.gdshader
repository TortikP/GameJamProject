// CRT post-process shader for canvas_item.
// Full-screen ColorRect reads hint_screen_texture, applies barrel curvature,
// scanlines (pinned to physical pixels — no moiré), aperture mask, chromatic
// aberration, warm tone grade with phosphor glow, soft bloom, aspect-correct
// vignette and bezel mask. Single pass.
//
// Tested target: Godot 4.6.2 with renderer=gl_compatibility.
// All cosmetic knobs are uniforms — tweak in inspector, no recompile.

shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

// --- Geometry ---------------------------------------------------------------
uniform float curvature : hint_range(0.0, 0.5) = 0.08;
uniform float bezel_softness : hint_range(0.0, 0.2) = 0.04;

// --- Scanlines --------------------------------------------------------------
// Pitch in PHYSICAL pixels — locked to FRAGCOORD.y so we don't beat against
// the actual viewport resolution and produce macro-arcs. 3.0 = "every 3rd
// physical row is a dark line" → classic CRT density without going eye-stabby.
uniform float scanline_pitch_px : hint_range(1.5, 8.0) = 3.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.30;

// --- Aperture mask (RGB triplets) -------------------------------------------
uniform float aperture_strength : hint_range(0.0, 1.0) = 0.15;

// --- Chromatic aberration ---------------------------------------------------
// Pixel offset between R and B channels. Strongest at edges, zero at center.
uniform float chroma_strength : hint_range(0.0, 6.0) = 1.6;

// --- Warm tone grade --------------------------------------------------------
uniform float warm_strength : hint_range(0.0, 1.0) = 0.28;
uniform vec3  warm_tint : source_color = vec3(1.18, 1.04, 0.78);
// Phosphor never fully rests — even "black" carries faint warm glow.
uniform vec3  phosphor_glow : source_color = vec3(0.030, 0.018, 0.008);

// --- Bloom-ish glow ---------------------------------------------------------
uniform float bloom_strength : hint_range(0.0, 1.5) = 0.55;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.45;

// --- Vignette ---------------------------------------------------------------
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.42;

// --- Brightness recovery ----------------------------------------------------
// scanline × aperture × vignette × gamma combined dim the image to ~60% of
// source. This boost is applied AFTER all multiplicative dimming so the screen
// reads as warm-bright, not muddy.
uniform float boost : hint_range(0.5, 2.5) = 1.35;

// --- Optional 50 Hz hum (off by default) ------------------------------------
uniform float hum_strength : hint_range(0.0, 0.2) = 0.0;
uniform float hum_speed = 0.6;

const float TWO_PI = 6.28318530718;

// Curve UV around the screen center to fake a CRT bulge.
vec2 barrel(vec2 uv) {
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	c *= 1.0 + r2 * curvature;
	return c + 0.5;
}

// 0 inside the curved screen region, → 1 in the bezel area.
float bezel_mask(vec2 cuv) {
	vec2 d = max(vec2(0.0) - cuv, cuv - vec2(1.0));
	float outside = max(d.x, d.y);
	return smoothstep(0.0, bezel_softness, outside);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 cuv = barrel(uv);

	// Outside the curved frame → solid black bezel with soft edge.
	float bz = bezel_mask(cuv);
	float screen_mask = 1.0 - bz;

	// Center-aware chromatic aberration: shift R and B by ±chroma_strength px,
	// scaled by squared distance from center so the edges fringe more than the middle.
	vec2 from_center = cuv - 0.5;
	vec2 chroma_dir = from_center * length(from_center) * 2.0;
	vec2 chroma_offset = chroma_dir * chroma_strength * SCREEN_PIXEL_SIZE;

	float r = texture(screen_tex, cuv + chroma_offset).r;
	float g = texture(screen_tex, cuv).g;
	float b = texture(screen_tex, cuv - chroma_offset).b;
	vec3 col = vec3(r, g, b);

	// Cheap bloom: 4 neighbour samples a few pixels away, average them, then
	// add only the bright part. 4-tap is "good enough" on jam-pace pixel art.
	vec2 px = SCREEN_PIXEL_SIZE * 3.0;
	vec3 nb = texture(screen_tex, cuv + vec2( 0.0,  px.y)).rgb;
	vec3 sb = texture(screen_tex, cuv + vec2( 0.0, -px.y)).rgb;
	vec3 eb = texture(screen_tex, cuv + vec2( px.x, 0.0)).rgb;
	vec3 wb = texture(screen_tex, cuv + vec2(-px.x, 0.0)).rgb;
	vec3 blur = (nb + sb + eb + wb) * 0.25;
	vec3 bright = max(blur - vec3(bloom_threshold), vec3(0.0));
	col += bright * bloom_strength;

	// Scanlines locked to PHYSICAL pixel rows — no moiré with viewport size.
	// `cos(2π * y / pitch)`: one full bright→dim cycle every `pitch` rows.
	float scan = 0.5 + 0.5 * cos(FRAGCOORD.y * TWO_PI / scanline_pitch_px);
	col *= mix(1.0 - scanline_strength, 1.0, scan);

	// Aperture mask: per-physical-pixel RGB triplets. mod(FRAGCOORD.x, 3).
	float fx = mod(FRAGCOORD.x, 3.0);
	float dim = 1.0 - aperture_strength;
	vec3 mask;
	if (fx < 1.0) {
		mask = vec3(1.0, dim, dim);
	} else if (fx < 2.0) {
		mask = vec3(dim, 1.0, dim);
	} else {
		mask = vec3(dim, dim, 1.0);
	}
	col *= mask;

	// Warm grade: nudge toward amber, very slight gamma lift to warm shadows.
	col = mix(col, col * warm_tint, warm_strength);
	col = pow(max(col, vec3(0.0)), vec3(0.96));

	// Phosphor never rests — add tiny warm ambient inside the screen so true
	// blacks read as "tube glow", not "void".
	col += phosphor_glow * screen_mask;

	// Aspect-correct vignette. SCREEN_PIXEL_SIZE.y/x = aspect ratio (e.g. 16/9).
	// Without this, the radial gradient is squashed vertically on widescreen
	// and corners look uneven.
	vec2 vc = from_center;
	vc.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float vig = 1.0 - vignette_strength * smoothstep(0.45, 0.95, length(vc) * 1.6);
	col *= vig;

	// Recover brightness lost to the multiplicative chain above.
	col *= boost;

	// Optional 50 Hz hum — slow vertical brightness roll. Off by default.
	if (hum_strength > 0.0) {
		float hum = sin((cuv.y + TIME * hum_speed) * TWO_PI) * hum_strength;
		col *= 1.0 - hum;
	}

	// Apply bezel: fade to black outside the curved region.
	col *= screen_mask;

	COLOR = vec4(col, 1.0);
}
