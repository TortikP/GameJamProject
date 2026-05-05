shader_type canvas_item;
// 047-skill-fx-system / default_buff — vertical streaks flowing upward across
// the sprite. Reads as "energy rising into the actor". X-axis sin pattern
// creates 4-6 distinct columns; Y-axis sin pattern creates moving segments
// inside each column (UV.y + progress shifts the pattern upward over time).
//
// fade_in / fade_out windows soften the start and end so the effect doesn't
// snap on/off.

uniform float progress       : hint_range(0.0, 1.0)  = 0.0;
uniform vec4  stream_color   : source_color          = vec4(1.0, 0.95, 0.4, 1.0);
uniform float band_count     : hint_range(2.0, 12.0) = 5.0;
uniform float segment_count  : hint_range(4.0, 24.0) = 12.0;
uniform float fade_origin    : hint_range(0.0, 1.0)  = 0.7;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    // Vertical bands across X — only positions where sin > threshold are lit.
    float x_pattern = step(0.5, sin(UV.x * band_count * 6.2832));
    // Y pattern shifts upward over time → at UV.y=fixed, brightness pulses
    // in sync with the wave moving past it.
    float y_pattern = step(0.5, sin((UV.y + progress) * segment_count));
    // Brighter near bottom of sprite (origin of energy), fading toward top.
    float vertical_fade = smoothstep(0.0, fade_origin, 1.0 - UV.y);
    // Soft envelope on time so it doesn't pop on/off.
    float time_envelope = smoothstep(0.0, 0.15, progress) * smoothstep(1.0, 0.85, progress);
    float intensity = x_pattern * y_pattern * vertical_fade * time_envelope;
    COLOR = vec4(mix(tex.rgb, stream_color.rgb, intensity * stream_color.a), tex.a);
}
