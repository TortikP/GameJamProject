shader_type canvas_item;
// 047-skill-fx-system / default_debuff — vertical streaks flowing downward
// across the sprite. Mirror of stream_up — same band/segment logic but
// origin is the top of the sprite and the Y pattern advances downward
// (UV.y - progress instead of UV.y + progress).

uniform float progress       : hint_range(0.0, 1.0)  = 0.0;
uniform vec4  stream_color   : source_color          = vec4(0.7, 0.4, 0.9, 1.0);
uniform float band_count     : hint_range(2.0, 12.0) = 5.0;
uniform float segment_count  : hint_range(4.0, 24.0) = 12.0;
uniform float fade_origin    : hint_range(0.0, 1.0)  = 0.7;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float x_pattern = step(0.5, sin(UV.x * band_count * 6.2832));
    // Subtract instead of add → segments move downward over time.
    float y_pattern = step(0.5, sin((UV.y - progress) * segment_count));
    // Brighter near top of sprite (origin), fading toward bottom.
    float vertical_fade = smoothstep(0.0, fade_origin, UV.y);
    float time_envelope = smoothstep(0.0, 0.15, progress) * smoothstep(1.0, 0.85, progress);
    float intensity = x_pattern * y_pattern * vertical_fade * time_envelope;
    COLOR = vec4(mix(tex.rgb, stream_color.rgb, intensity * stream_color.a), tex.a);
}
