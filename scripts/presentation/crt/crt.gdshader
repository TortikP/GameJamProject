// CRT post-process shader for canvas_item.
// Full-screen ColorRect reads hint_screen_texture, applies barrel curvature,
// scanlines, aperture mask, chromatic aberration, warm tone grade, bloom, vignette
// and bezel mask. Single pass.
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
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.35;
// Number of scanlines across the full screen height. Pinned to game viewport
// height (720) so density stays consistent regardless of window size.
uniform float scanline_count = 720.0;

// --- Aperture mask (RGB triplets) -------------------------------------------
uniform float aperture_strength : hint_range(0.0, 1.0) = 0.20;

// --- Chromatic aberration ---------------------------------------------------
// Pixel offset between R and B channels. Strongest at edges, zero at center.
uniform float chroma_strength : hint_range(0.0, 6.0) = 1.4;

// --- Warm tone grade --------------------------------------------------------
uniform float warm_strength : hint_range(0.0, 1.0) = 0.18;
uniform vec3  warm_tint : source_color = vec3(1.10, 1.00, 0.84);

// --- Bloom-ish glow ---------------------------------------------------------
uniform float bloom_strength : hint_range(0.0, 1.0) = 0.32;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.55;

// --- Vignette ---------------------------------------------------------------
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.6;

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

	// Center-aware chromatic aberration: shift R and B by ±chroma_strength px,
	// scaled by distance from center so the edges fringe more than the middle.
	vec2 from_center = cuv - 0.5;
	vec2 chroma_dir = from_center * length(from_center) * 2.0;
	vec2 chroma_offset = chroma_dir * chroma_strength * SCREEN_PIXEL_SIZE;

	float r = texture(screen_tex, cuv + chroma_offset).r;
	float g = texture(screen_tex, cuv).g;
	float b = texture(screen_tex, cuv - chroma_offset).b;
	vec3 col = vec3(r, g, b);

	// Cheap bloom: 4 neighbour samples 2 px away, average their bright part,
	// add it on top. Not gaussian — but readable on jam-pace pixel art.
	vec2 px = SCREEN_PIXEL_SIZE * 2.0;
	vec3 n  = texture(screen_tex, cuv + vec2( 0.0,  px.y)).rgb;
	vec3 s  = texture(screen_tex, cuv + vec2( 0.0, -px.y)).rgb;
	vec3 e  = texture(screen_tex, cuv + vec2( px.x, 0.0)).rgb;
	vec3 w  = texture(screen_tex, cuv + vec2(-px.x, 0.0)).rgb;
	vec3 blur = (n + s + e + w) * 0.25;
	vec3 bright = max(blur - vec3(bloom_threshold), vec3(0.0));
	col += bright * bloom_strength;

	// Scanline modulation along the curved Y. Uses cos so peaks/valleys are
	// stable across the screen.
	float scan = 0.5 + 0.5 * cos(cuv.y * scanline_count * TWO_PI);
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

	// Warm grade: nudge toward amber, slightly lift gamma for warm shadows.
	col = mix(col, col * warm_tint, warm_strength);
	col = pow(max(col, vec3(0.0)), vec3(0.96));

	// Vignette: soft radial darkening from the curved center.
	float vig = 1.0 - vignette_strength * smoothstep(0.5, 1.4, length(from_center) * 2.0);
	col *= vig;

	// Optional 50 Hz hum — slow vertical brightness roll. Off by default.
	if (hum_strength > 0.0) {
		float hum = sin((cuv.y + TIME * hum_speed) * TWO_PI) * hum_strength;
		col *= 1.0 - hum;
	}

	// Apply bezel: fade to black outside the curved region.
	col *= 1.0 - bz;

	COLOR = vec4(col, 1.0);
}
