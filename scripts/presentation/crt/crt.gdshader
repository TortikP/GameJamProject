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
// Bezel-rim soft fade width in UV. With the new bezel_mask logic this is the
// full visible darkening rim (was just the OOB-fade in v1–v6, so 0.04 looked
// thinner before). Lowered to 0.025 → ~32 px on 1280-wide viewport — about
// the same apparent rim thickness as before, just everything fully inside
// [0,1] now so no clamp-to-edge artefacts.
uniform float bezel_softness : hint_range(0.0, 0.2) = 0.025;

// --- Scanlines --------------------------------------------------------------
// Pitch in PHYSICAL pixels — locked to FRAGCOORD.y so we don't beat against
// the actual viewport resolution and produce macro-arcs. 3.0 = "every 3rd
// physical row is a dark line" → classic CRT density without going eye-stabby.
//
// 029 / req-9: dampened (0.30 → 0.15) along with the rest of the effects so
// only curvature + the (now horizontal) aperture mask remain prominent.
uniform float scanline_pitch_px : hint_range(1.5, 8.0) = 3.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.15;

// --- Aperture mask (RGB triplets) -------------------------------------------
// 029 / req-9: dampened (0.15 → 0.06). The mask is also rotated 90° in the
// fragment shader (mod(FRAGCOORD.y) instead of .x) so the RGB-tinted bands
// run HORIZONTALLY rather than vertically — Andrey's complaint was that the
// vertical ones read as artificial stripes; horizontal ones blend with the
// scanlines into "this is a CRT" rather than "this is a barcode".
uniform float aperture_strength : hint_range(0.0, 1.0) = 0.06;

// --- Chromatic aberration ---------------------------------------------------
// 029 / req-9: dampened (1.6 → 0.6). At 1.6 the channel split was visible
// even on small text mid-screen; 0.6 gives a faint edge-only fringe.
uniform float chroma_strength : hint_range(0.0, 6.0) = 0.6;

// --- Tone grade -------------------------------------------------------------
// 029 / req-9: tint flipped from warm (orange phosphor) to cool blue. Variable
// names kept (`warm_*`) to avoid touching set_param call-sites; the comments
// and defaults are what shifted. New reading: think "blue CRT tube" instead of
// "old amber terminal".
uniform float warm_strength : hint_range(0.0, 1.0) = 0.18;
uniform vec3  warm_tint : source_color = vec3(0.85, 0.95, 1.15);
// Phosphor never fully rests — even "black" carries faint blue glow.
uniform vec3  phosphor_glow : source_color = vec3(0.008, 0.018, 0.030);

// --- Bloom-ish glow ---------------------------------------------------------
// 029 / req-9: dampened (0.55 → 0.20) — bloom was washing out highlights.
uniform float bloom_strength : hint_range(0.0, 1.5) = 0.20;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.45;

// --- Vignette ---------------------------------------------------------------
// 029 / req-9: dampened (0.42 → 0.20). Curvature still implies CRT; the heavy
// vignette on top was darkening the playfield edges where wave timeline UI sits.
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.20;

// --- Brightness recovery + tone shaping -------------------------------------
// scanline × aperture × vignette × gamma combined dim the image to ~60% of
// source. `boost` is a multiplicative lift applied AFTER all dimming.
// `contrast` is a classic pivot-at-0.5 contrast curve, applied right after
// boost — pushes blacks darker and whites whiter without touching mid greys.
//
// 029 / req-9: boost 1.5 → 1.1 because the rest of the chain dims less now;
// at 1.5 the image was clipping to white in mid-bright regions. Contrast
// untouched.
uniform float boost : hint_range(0.5, 2.5) = 1.1;
uniform float contrast : hint_range(0.5, 2.0) = 1.12;

// --- Optional 50 Hz hum (slow vertical brightness roll, on by default now) --
// hum_bands = how many sinusoidal bands are visible across screen height at
// any instant. 2.0 reads more "real CRT mains hum" than a single full cycle.
//
// 029 / req-9: dampened (0.04 → 0.015) — roll was visible even with the rest
// of the effects toned down.
uniform float hum_strength : hint_range(0.0, 0.2) = 0.015;
uniform float hum_speed = 0.30;
uniform float hum_bands = 2.0;

const float TWO_PI = 6.28318530718;

// Curve UV around the screen center to fake a CRT bulge.
//
// Pre-shrinks the input by `1 + curvature * 0.5` BEFORE applying the
// quadratic expansion, so that even at the corners (where r² = 0.5 and the
// expansion is at maximum) the output stays inside [0, 1]. Without the
// pre-shrink, corners overshoot to ~1.02 and the texture sampler hits
// clamp-to-edge there → leftmost/rightmost column gets replicated as a
// visible rim stripe. This kills the artifact at the source instead of
// trying to mask it out further down the pipeline.
//
// Trade-off: visible image is shrunk by ~2% on each axis. Imperceptible
// against the curved bezel; cheaper than a SubViewport rebuild.
vec2 barrel(vec2 uv) {
	vec2 c = (uv - 0.5) / (1.0 + curvature * 0.5);
	float r2 = dot(c, c);
	c *= 1.0 + r2 * curvature;
	return c + 0.5;
}

// Bezel mask. 1 = bezel (fully opaque black covering), 0 = visible screen.
//
// Inverted vs. the previous version: now the fade goes FROM the boundary
// inward over `bezel_softness` UV. Critical effect: ANY cuv outside [0,1]
// (which barrel curvature does at the corners and edges) returns 1 — full
// bezel. This is what kills clamp-to-edge sample stripes once and for all:
// even if `cuv_safe` succeeds in sampling valid content, screen_mask = 0 in
// that region zeroes the contribution out.
//
// Cost: the visible "screen" loses a bezel_softness-wide soft rim where
// content fades to black. With default 0.04 that's ~50 px on each edge —
// reads as actual CRT bezel glass, not a bug.
float bezel_mask(vec2 cuv) {
	vec2 d = max(-cuv, cuv - vec2(1.0));
	float oob = max(d.x, d.y);              // negative inside, ≥ 0 OOB
	float dist_inside = max(-oob, 0.0);     // distance from nearest edge, 0 if OOB
	return 1.0 - smoothstep(0.0, bezel_softness, dist_inside);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 cuv = barrel(uv);

	float bz = bezel_mask(cuv);
	float screen_mask = 1.0 - bz;

	// Center-aware chromatic aberration. Edges fringe more than the middle.
	// Two samples instead of three: G channel is the average of the two
	// shifted reads — visually indistinguishable from a separate centre sample,
	// −1 texture read per fragment. Multiplied by `screen_mask` so the offset
	// fades to zero right at the bezel — kills clamp-to-edge "streaks" on the
	// outermost ring of the screen.
	vec2 from_center = cuv - 0.5;
	vec2 chroma_dir = from_center * length(from_center) * 2.0;
	vec2 chroma_offset = chroma_dir * chroma_strength * SCREEN_PIXEL_SIZE * screen_mask;

	// All texture sampling uses `cuv_safe` — clamped a few pixels inside the
	// texture edge. Without this, when barrel pushes cuv slightly outside [0,1]
	// (typical at left/right rim), texture clamp-to-edge replicates the edge
	// column → visible vertical stripe of repeated pixel data. Sampling from
	// the inset gives real game content instead, then bezel mask fades it to
	// black smoothly.
	vec2 sample_margin = SCREEN_PIXEL_SIZE * 4.0;
	vec2 cuv_safe = clamp(cuv, sample_margin, vec2(1.0) - sample_margin);

	vec3 sa = texture(screen_tex, cuv_safe + chroma_offset).rgb;
	vec3 sb = texture(screen_tex, cuv_safe - chroma_offset).rgb;
	vec3 col = vec3(sa.r, (sa.g + sb.g) * 0.5, sb.b);

	// Bloom: two diagonal samples (down from four cardinal). Gated by strength
	// so setting `bloom_strength = 0` in the inspector skips the work entirely
	// instead of multiplying it out at the end. Radius also fades by screen_mask
	// so the diagonal samples don't reach beyond the bezel either.
	if (bloom_strength > 0.0) {
		vec2 px = SCREEN_PIXEL_SIZE * 2.0 * screen_mask;
		vec3 d1 = texture(screen_tex, cuv_safe + vec2( px.x,  px.y)).rgb;
		vec3 d2 = texture(screen_tex, cuv_safe + vec2(-px.x, -px.y)).rgb;
		vec3 blur = (d1 + d2) * 0.5;
		vec3 bright = max(blur - vec3(bloom_threshold), vec3(0.0));
		col += bright * bloom_strength;
	}

	// Scanlines locked to PHYSICAL pixel rows — no moiré with viewport size.
	// `cos(2π * y / pitch)`: one full bright→dim cycle every `pitch` rows.
	float scan = 0.5 + 0.5 * cos(FRAGCOORD.y * TWO_PI / scanline_pitch_px);
	col *= mix(1.0 - scanline_strength, 1.0, scan);

	// Aperture mask: per-physical-pixel RGB triplets.
	// 029 / req-9: indexed off FRAGCOORD.y (was .x) so the RGB-tinted bands
	// run HORIZONTALLY across the screen — Andrey's complaint was that the
	// vertical bands read as a deliberate stripe pattern (barcode-like) and
	// fought with the gameplay grid. Horizontal bands sit cleanly with the
	// scanlines (which are also horizontal) and read as one cohesive CRT
	// texture instead of two competing patterns.
	float fy = mod(FRAGCOORD.y, 3.0);
	float dim = 1.0 - aperture_strength;
	vec3 mask;
	if (fy < 1.0) {
		mask = vec3(1.0, dim, dim);
	} else if (fy < 2.0) {
		mask = vec3(dim, 1.0, dim);
	} else {
		mask = vec3(dim, dim, 1.0);
	}
	col *= mask;

	// Tone grade — nudge toward the cool tint, very slight gamma lift to lift
	// shadows. (029: tint default flipped warm→cool; uniform names retained.)
	col = mix(col, col * warm_tint, warm_strength);
	col = pow(max(col, vec3(0.0)), vec3(0.96));

	// Phosphor never rests — add tiny ambient inside the screen so true
	// blacks read as "tube glow", not "void". (029: blue tilt now.)
	col += phosphor_glow * screen_mask;

	// Vignette in UV space — `length(from_center)` directly. On a 16:9 screen
	// the equipotential is a UV-circle, which RENDERS as a horizontal ellipse
	// matching the resolution aspect (640 px hor vs 360 px vert from center
	// at length=0.5). This is the natural "TV bright spot" shape — fades
	// faster vertically than horizontally on widescreen, exactly what we want.
	// Earlier aspect-correction made it a physical-pixel circle (vertical
	// oval), which felt squashed.
	float vig = 1.0 - vignette_strength * smoothstep(0.25, 0.85, length(from_center));
	col *= vig;

	// Recover brightness lost to the multiplicative chain above.
	col *= boost;

	// Contrast around mid-grey. Subtle by default — darks slightly darker,
	// lights slightly lighter, mids untouched.
	col = (col - vec3(0.5)) * contrast + vec3(0.5);

	// 50 Hz mains hum — slow vertical sinusoidal brightness roll. `hum_bands`
	// controls how many bands are visible at once; a single full cycle reads
	// too uniform, two bands look more like real CRT mains interference.
	if (hum_strength > 0.0) {
		float hum = sin((cuv.y * hum_bands + TIME * hum_speed) * TWO_PI) * hum_strength;
		col *= 1.0 - hum;
	}

	// Apply bezel: fade to black outside the curved region.
	col *= screen_mask;

	COLOR = vec4(col, 1.0);
}
