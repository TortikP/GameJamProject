// Level transition shader (035-game-editor).
// Self-contained fullscreen canvas_item shader for the metamorphosis effect.
// Reads hint_screen_texture and applies, in priority order:
//   1. Wobble — high-frequency UV displacement driven by `wobble` uniform.
//   2. Distort — slow, large-amplitude wave warp driven by `distort` uniform.
//   3. Chromatic split — RGB channels offset radially, scaled by `chroma`.
//   4. Black overlay — `fade` mixes toward `vec3(0)` (Phase B/C).
// All four uniforms in [0,1]; the GD script tweens them across phases.
// No CRT-shader dependency — that one has no distort knob and modifying it
// would scope-creep 010-crt-postfx.

shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

// 0..1 — high-frequency screen-space wobble (pseudo-shake).
uniform float wobble : hint_range(0.0, 1.0) = 0.0;
// 0..1 — large-amplitude wave warp.
uniform float distort : hint_range(0.0, 1.0) = 0.0;
// 0..1 — chromatic aberration strength multiplier.
uniform float chroma : hint_range(0.0, 1.0) = 0.0;
// 0..1 — black-overlay alpha (1.0 = fully black).
uniform float fade : hint_range(0.0, 1.0) = 0.0;

const float TWO_PI = 6.28318530718;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Wobble: two sin layers at different freqs, summed and scaled by wobble.
	// Pixel-anchored via SCREEN_PIXEL_SIZE so amplitude reads consistently
	// regardless of viewport size.
	if (wobble > 0.0) {
		vec2 wob;
		wob.x = sin(uv.y * 80.0 + TIME * 60.0) * 0.5
			  + sin(uv.y * 23.0 + TIME * 14.0) * 0.5;
		wob.y = sin(uv.x * 60.0 + TIME * 47.0) * 0.5
			  + sin(uv.x * 17.0 + TIME * 9.0) * 0.5;
		uv += wob * SCREEN_PIXEL_SIZE * 18.0 * wobble;
	}

	// Distort: slow wave warp, larger amplitude. UV-space, no pixel scaling
	// so the warp visibly bends content. Two crossing waves keep it from
	// looking like a 1D scroll.
	if (distort > 0.0) {
		float w1 = sin(uv.y * 8.0 + TIME * 1.7) * 0.5;
		float w2 = sin(uv.x * 6.0 + TIME * 1.3) * 0.5;
		uv.x += w1 * 0.04 * distort;
		uv.y += w2 * 0.04 * distort;
	}

	// Chromatic split: radial offset from screen center.
	vec2 from_center = uv - vec2(0.5);
	vec2 chroma_dir = from_center * length(from_center) * 2.0;
	vec2 chroma_off = chroma_dir * 0.025 * chroma;

	// Sample. Clamp to safe inset so warped UVs outside [0,1] don't return
	// stretched edge pixels.
	vec2 inset = SCREEN_PIXEL_SIZE * 4.0;
	vec2 uv_safe = clamp(uv, inset, vec2(1.0) - inset);

	float r = texture(screen_tex, clamp(uv_safe + chroma_off, inset, vec2(1.0) - inset)).r;
	float g = texture(screen_tex, uv_safe).g;
	float b = texture(screen_tex, clamp(uv_safe - chroma_off, inset, vec2(1.0) - inset)).b;
	vec3 col = vec3(r, g, b);

	// Fade toward black.
	col = mix(col, vec3(0.0), fade);

	COLOR = vec4(col, 1.0);
}
