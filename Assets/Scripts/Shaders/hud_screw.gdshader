shader_type canvas_item;

uniform vec4 color_line : source_color = vec4(0.0, 1.0, 1.0, 1.0);
uniform vec4 color_bg   : source_color = vec4(0.06, 0.06, 0.08, 1.0);

uniform float angle_deg        : hint_range(-90.0, 90.0) = 30.0;
uniform float stripe_period_px : hint_range(2.0, 256.0) = 24.0;
uniform float stripe_offset    : hint_range(0.0, 1.0) = 0.0; // << new: manual phase shift
uniform float thickness        : hint_range(0.0, 1.0) = 0.35;
uniform float edge_softness    : hint_range(0.0, 1.0) = 0.25;
uniform float scroll_speed     : hint_range(-10.0, 10.0) = 0.0;
uniform float transparent_margin : hint_range(0.0, 0.5) = 0.15;

varying vec2 v_local_px;

void vertex() {
    // Pass local pixel coordinates from the vertex shader to fragment shader
    v_local_px = VERTEX;
}

void fragment() {
    // Compute rotation
    float a  = radians(angle_deg);
    float ca = cos(a);
    float sa = sin(a);

    // Axis along the slanted screw direction (in local pixels)
    float axis_px = v_local_px.x * ca + v_local_px.y * sa;

    // Screw pattern phase with scroll + offset
    float phase = fract(axis_px / stripe_period_px + TIME * scroll_speed + stripe_offset);

    // Stripe mask
    float dist_edge = min(phase, 1.0 - phase);
    float aa = fwidth(phase) * mix(0.0, 3.0, edge_softness);
    float half_w = clamp(thickness, 0.0, 1.0) * 0.5;
    float mask = 1.0 - smoothstep(half_w - aa, half_w + aa, dist_edge);

    // Thread color mix
    vec4 screw_color = mix(color_bg, color_line, mask);

    // Hard top/bottom transparency cut — background only
    bool in_margin = (UV.y < transparent_margin) || (UV.y > (1.0 - transparent_margin));
    float bg_factor = 1.0 - mask;
    float alpha = in_margin ? (1.0 - bg_factor) : 1.0;

    COLOR = vec4(screw_color.rgb, screw_color.a * alpha);
}
