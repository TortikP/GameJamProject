// Space background — rotating-rays sunburst, soft and slow. Drawn behind the
// world (CanvasLayer.layer = -10 in space_background.tscn). Replaces the flat
// gray background that sat under the hex grid.
//
// 029 / req-8.
//
// Single full-screen pass. Polar coordinates around the screen center; rays are
// `sin(angle * count + time * speed)` softened with smoothstep so the wedges
// feel like beams of light instead of pie slices. A radial fade darkens the
// center (so the hex grid sits over the darkest part) and brightens the edges
// (so the rays sweep into vignette).
//
// All knobs as uniforms — tune in the inspector via space_background.tscn's
// ShaderMaterial. Defaults aimed at "barely there" so it never competes with
// gameplay UI.

shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec3  color_base : source_color = vec3(0.020, 0.020, 0.045);
uniform vec3  color_ray  : source_color = vec3(0.055, 0.060, 0.110);
uniform float ray_count = 14.0;
uniform float rotation_speed = 0.04;     // full revolutions per second of the ray pattern
uniform float ray_softness : hint_range(0.05, 1.0) = 0.45;  // higher = softer wedge edges
uniform float center_fade_start : hint_range(0.0, 0.5) = 0.05;  // r below this: pure base
uniform float center_fade_end   : hint_range(0.05, 0.9) = 0.45; // r above this: full ray contribution
uniform float edge_lift = 0.20;          // extra brightness multiplier at radial edges (0 = none)

const float TAU = 6.28318530718;


void fragment() {
	// UV centered at (0,0). Aspect-correct so the wedges look like wedges, not
	// ellipses on widescreen. Multiplying x by viewport-width/height ratio
	// gives a polar space where 1 unit horizontal == 1 unit vertical.
	vec2 uv = SCREEN_UV - vec2(0.5);
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	float r = length(uv);
	float angle = atan(uv.y, uv.x);

	// Ray pattern: sine across angular position, drifting in TIME. Softened to
	// avoid a hard vector-art wedge look. ray ∈ [0, 1] after smoothstep.
	float wave = sin(angle * ray_count + TIME * rotation_speed * TAU);
	float ray = smoothstep(-ray_softness, ray_softness, wave);

	// Radial weighting — center stays darker so gameplay reads cleanly over
	// the calmest part of the background. Past `center_fade_end`, full ray
	// contribution kicks in. `edge_lift` then nudges the outermost rays a
	// touch brighter so the "sweep into vignette" effect lands.
	float radial = smoothstep(center_fade_start, center_fade_end, r);
	float edge_boost = 1.0 + edge_lift * smoothstep(center_fade_end, 0.9, r);

	float ray_strength = ray * radial * edge_boost;
	vec3 col = mix(color_base, color_ray, clamp(ray_strength, 0.0, 1.0));

	COLOR = vec4(col, 1.0);
}
