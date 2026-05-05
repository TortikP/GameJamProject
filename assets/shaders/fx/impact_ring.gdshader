shader_type canvas_item;
// 047-skill-fx-system / default_ranged — radial shock ring expanding outward
// from sprite center. Reads as "impact landed here" — distinct from swipe so
// the player can tell ranged hits apart from melee at a glance.
//
// progress 0→1 drives ring radius outward. Ring fades as it expands so the
// last frame is a faint after-glow rather than a hard pop.

uniform float progress    : hint_range(0.0, 1.0)  = 0.0;
uniform vec4  ring_color  : source_color          = vec4(1.0, 0.4, 0.4, 1.0);
uniform float ring_width  : hint_range(0.02, 0.3) = 0.08;
uniform float max_radius  : hint_range(0.3, 0.8)  = 0.6;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float d = distance(UV, vec2(0.5));
    float r = progress * max_radius;
    float ring = smoothstep(ring_width, 0.0, abs(d - r));
    // Fade out as the ring expands so we don't end on a bright halo.
    float fade = 1.0 - progress;
    COLOR = vec4(mix(tex.rgb, ring_color.rgb, ring * fade * ring_color.a), tex.a);
}
