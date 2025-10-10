shader_type canvas_item;

// 3+ rust palette
uniform vec4 color_rust_lo : source_color = vec4(0.62, 0.29, 0.10, 1.0);
uniform vec4 color_rust_md : source_color = vec4(0.78, 0.38, 0.12, 1.0);
uniform vec4 color_rust_hi : source_color = vec4(0.86, 0.45, 0.14, 1.0);

// Controls
uniform float uv_scale = 6.0;             // rust patch size
uniform float rust_amount = 0.55;         // how much appears
uniform float rust_contrast = 1.25;       // edge hardness
uniform float seed = 13.0;

// Optional: keep top/bottom of the bar empty (hard cut)
uniform float transparent_margin : hint_range(0.0, 0.5) = 0.0;

// --- tiny value-noise + fbm ---
float h(vec2 p){ p=fract(p*vec2(123.34,345.45)); p+=dot(p,p+34.345); return fract(p.x*p.y); }
float vnoise(vec2 p){
    vec2 i=floor(p), f=fract(p);
    float a=h(i), b=h(i+vec2(1,0)), c=h(i+vec2(0,1)), d=h(i+vec2(1,1));
    vec2 u=f*f*(3.0-2.0*f);
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}
float fbm(vec2 p){
    float a=0.5, s=0.0;
    for(int i=0;i<5;i++){ s+=a*vnoise(p); p*=2.0; a*=0.5; }
    return s;
}

void fragment(){
    // Local UV noise
    float n = fbm(UV * uv_scale + vec2(seed, seed*0.73));
    n = pow(clamp(n, 0.0, 1.0), rust_contrast);

    // Thresholds → 3 color bands
    float t0 = smoothstep(rust_amount-0.15, rust_amount+0.15, n);
    float t1 = smoothstep(rust_amount+0.05, rust_amount+0.30, n);

    float w_lo = t1;                // darkest cores
    float w_md = t0 * (1.0 - t1);   // mid ring
    float w_hi = max(0.0, t0 - w_md - w_lo);

    vec3 rust_rgb = normalize(
        color_rust_lo.rgb * w_lo +
        color_rust_md.rgb * w_md +
        color_rust_hi.rgb * w_hi + 1e-6);

    // Rust strength (0..1)
    float rust = t0;

    // Optional hard top/bottom cut for the overlay
    bool in_margin = (UV.y < transparent_margin) || (UV.y > (1.0 - transparent_margin));
    if (in_margin) rust = 0.0;

    // MULTIPLY overlay: white = no change, darker = rust tint
    vec3 out_rgb = mix(vec3(1.0), rust_rgb, rust);

    // Alpha can be 1 (Mul ignores it), or use rust as alpha if you prefer Mix
    COLOR = vec4(out_rgb, 1.0);
}
