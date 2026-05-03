shader_type canvas_item;
// 047-skill-fx-system / default_melee — sword-slash arc. The slash front
// sweeps in caster→victim direction along a parabolic arc (sin curve) so it
// reads as "blade cut through here" rather than a flat wipe. The leading
// edge is the brightest pixel; intensity falls off behind it down a tunable
// trail length, giving a motion-trail feel.
//
// Coordinate setup: UV is rotated around (0.5, 0.5) by `angle` (set per-victim
// by FxDirector when uses_direction=true) so the slash always sweeps along
// the rotated +X axis. The arc itself is in the rotated frame:
//   arc_y(x) = 0.5 + arc_height * sin(x * PI)
// peaking at x=0.5 with magnitude arc_height. Negative arc_height inverts
// the curve direction (slash bowing the other way).
//
// Editable uniforms:
//   slash_color    — band tint (RGBA, alpha modulates strength)
//   band_thickness — perpendicular thickness around the arc curve
//   arc_height     — curve amplitude. 0 = straight line. Negative = mirror.
//   trail_length   — how far the trail extends behind the leading edge

uniform float progress       : hint_range(0.0, 1.0)  = 0.0;
uniform float angle                                  = 0.0;
uniform vec4  slash_color    : source_color          = vec4(1.0, 0.85, 0.4, 1.0);
uniform float band_thickness : hint_range(0.02, 0.3) = 0.08;
uniform float arc_height     : hint_range(-0.4, 0.4) = 0.22;
uniform float trail_length   : hint_range(0.1, 0.8)  = 0.45;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    // Rotate UV around (0.5, 0.5) so the swing axis aligns with +X. We
    // rotate by -angle because we want the WORLD axis at `angle` to become
    // the SHADER axis at 0.
    vec2 centered = UV - vec2(0.5);
    float c = cos(-angle);
    float s = sin(-angle);
    vec2 rotated = vec2(
        centered.x * c - centered.y * s,
        centered.x * s + centered.y * c
    ) + vec2(0.5);

    // Leading edge of the slash sweeps left→right with overshoot on both
    // sides so the slash enters and exits the sprite cleanly.
    float x_front = mix(-0.2, 1.2, progress);

    // Parabolic arc trajectory (sin peaks at x=0.5, zero at x=0 and x=1).
    float arc_y = 0.5 + arc_height * sin(rotated.x * 3.14159);

    // Distance from this pixel (in rotated frame) to the arc curve at the
    // pixel's x position. smoothstep gives a soft band rather than a hard
    // edge so the slash reads as motion blur.
    float dist_to_curve = abs(rotated.y - arc_y);
    float band = smoothstep(band_thickness, 0.0, dist_to_curve);

    // Trail mask: pixel must be behind (lower x than) the leading edge AND
    // within trail_length of it. Brightness drops with distance from front,
    // so the leading edge is white-hot and the tail fades to nothing.
    float front_dist = x_front - rotated.x;
    float in_trail = step(0.0, front_dist) * step(front_dist, trail_length);
    float trail_intensity = 1.0 - smoothstep(0.0, trail_length, front_dist);

    float intensity = band * in_trail * trail_intensity * slash_color.a;
    COLOR = vec4(mix(tex.rgb, slash_color.rgb, intensity), tex.a);
}
