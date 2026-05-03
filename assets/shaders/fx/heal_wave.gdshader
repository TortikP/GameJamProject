shader_type canvas_item;
// 047-skill-fx-system / default_heal — horizontal wave sweeping bottom→top
// across the sprite. Reads as "rising restoration"; the soft falloff on
// either side of the wave Y position gives a gradient bloom rather than a
// hard line, which suits healing's gentle visual register.

uniform float progress         : hint_range(0.0, 1.0)  = 0.0;
uniform vec4  wave_color       : source_color          = vec4(0.4, 1.0, 0.5, 1.0);
uniform float wave_thickness   : hint_range(0.05, 0.4) = 0.15;
uniform float trail_strength   : hint_range(0.0, 0.6)  = 0.2;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    // Wave Y position: progress 0 → bottom (UV.y=1), progress 1 → top (UV.y=0).
    float wave_y = 1.0 - progress;
    float dist = abs(UV.y - wave_y);
    float front = smoothstep(wave_thickness, 0.0, dist);
    // Below-wave trail (already-traversed area gets a soft afterglow).
    float trail = step(UV.y, wave_y + wave_thickness) * trail_strength
                  * (1.0 - smoothstep(0.0, 0.5, wave_y - UV.y));
    float intensity = max(front, trail);
    COLOR = vec4(mix(tex.rgb, wave_color.rgb, intensity * wave_color.a), tex.a);
}
