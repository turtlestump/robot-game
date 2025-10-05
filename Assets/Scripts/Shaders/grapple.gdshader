shader_type canvas_item;

uniform vec4 neon_cyan    : source_color = vec4(0.0, 1.0, 1.0, 1.0);
uniform vec4 inner_color  : source_color = vec4(0.8, 1.0, 1.0, 1.0);
uniform float pulse_speed = 20.0;
uniform float edge_thickness = 0.8;

// 0=no linger (plain sine), 1=strong linger at peaks/troughs
uniform float linger_amount : hint_range(0.0, 1.0) = 0.7;

float smootherstep01(float x) {
    // maps [0,1] -> [0,1] with zero slope at both ends (lingers near 0 & 1)
    return x*x*x*(x*(x*6.0 - 15.0) + 10.0);
}

void fragment() {
    // Base oscillation in [0,1]
    float raw = 0.5 + 0.5 * sin(TIME * pulse_speed);

    // Linger curve: blend between raw and eased version
    float t = mix(raw, smootherstep01(raw), linger_amount);

    // Use t for the pulse color
    vec4 pulse_color = mix(neon_cyan, inner_color, t);

    // Distance from centerline (0.5 is middle), 0 at center, 1 at edges
    float dist_from_center = abs(UV.y - 0.5) / 0.5;

    // Edge mask
    float edge_mask = smoothstep(1.0 - edge_thickness, 1.0, dist_from_center);

    // Final color: center inner_color, edges pulse
    vec4 final_color = mix(inner_color, pulse_color, edge_mask);

    COLOR = final_color;
}