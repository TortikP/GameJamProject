shader_type canvas_item;
// 047-skill-fx-system — single-pass flash for skill FX (anim + collision +
// AI telegraph). Multiplicative mix between sprite texture and a uniform
// flash_color, weighted by flash_amount ∈ [0, 1]. Alpha preserved from
// texture so transparent regions stay transparent.
//
// Driven by Tween on `material:shader_parameter/flash_amount`. ShaderMaterial
// instances are created per-flash by FxDirector and cleared on tween finished.

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4  flash_color  : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    COLOR = vec4(mix(tex.rgb, flash_color.rgb, flash_amount), tex.a);
}
