shader_type canvas_item;
// 047-skill-fx-system / default_summon — pulsing concentric circle painted
// over a hex tile (NOT over a victim sprite). Renders on a MeshInstance2D
// quad placed at the spawn coord by FxDirector. Reads as "something is
// being conjured here, get ready".
//
// The shader paints directly without sampling TEXTURE — works on a bare
// QuadMesh with no texture binding. Outside the unit-circle area the
// fragment is fully transparent so the quad's bounding box doesn't show.
//
// progress 0→1 over the full effect duration. ring_count controls how many
// pulses happen during that duration.

uniform float progress     : hint_range(0.0, 1.0)  = 0.0;
uniform vec4  ring_color   : source_color          = vec4(0.85, 0.5, 1.0, 1.0);
uniform float ring_count   : hint_range(1.0, 6.0)  = 3.0;
uniform float outer_radius : hint_range(0.3, 0.5)  = 0.48;
uniform float ring_width   : hint_range(0.02, 0.1) = 0.05;

void fragment() {
    float d = distance(UV, vec2(0.5));
    if (d > outer_radius) {
        // Outside the circle — fully transparent, quad bbox stays invisible.
        COLOR = vec4(0.0);
    } else {
        // Outline ring at the outer edge.
        float outline = smoothstep(outer_radius - ring_width, outer_radius, d)
                      * (1.0 - smoothstep(outer_radius, outer_radius + 0.01, d));
        // Inner radial fill that pulses with the ring count.
        float pulse = 0.5 + 0.5 * sin(progress * ring_count * 6.2832);
        float fill = (1.0 - smoothstep(0.0, outer_radius, d)) * pulse * 0.4;
        // Global fade-out so the last frame leaves a clean tile.
        float life = 1.0 - smoothstep(0.75, 1.0, progress);
        float alpha = max(outline, fill) * life;
        COLOR = vec4(ring_color.rgb, alpha * ring_color.a);
    }
}
