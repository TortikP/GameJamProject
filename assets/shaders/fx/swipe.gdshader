shader_type canvas_item;
// 047-skill-fx-system / default_melee — diagonal swipe band moving across the
// sprite at runtime-configurable angle (caster→victim direction). progress is
// driven 0→1 by Tween; internally remapped to [-0.3, 1.3] so the band starts
// fully off-frame on the entry side and ends fully off-frame on the exit side.
//
// Uniforms editable via data/fx/collision_effects.json:
//   stripe_color  — band tint
//   stripe_width  — band thickness in normalized UV space
//   angle         — set by FxDirector when uses_direction=true (radians)

uniform float progress      : hint_range(0.0, 1.0)  = 0.0;
uniform float angle                                  = 0.0;
uniform vec4  stripe_color  : source_color           = vec4(1.0, 0.85, 0.4, 1.0);
uniform float stripe_width  : hint_range(0.05, 0.5) = 0.25;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    // Project UV (re-centered to [-0.5, 0.5]) onto the swipe axis, then bring
    // back into [0, 1]-ish space so progress comparisons are meaningful.
    vec2 centered = UV - vec2(0.5);
    float proj = centered.x * cos(angle) + centered.y * sin(angle) + 0.5;
    // Remap progress 0..1 → -0.3..1.3 so band travels fully past the sprite.
    float p = mix(-0.3, 1.3, progress);
    float band = smoothstep(stripe_width, 0.0, abs(proj - p));
    COLOR = vec4(mix(tex.rgb, stripe_color.rgb, band * stripe_color.a), tex.a);
}
