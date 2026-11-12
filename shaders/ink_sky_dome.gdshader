// Ink Tide — spatial sky dome (avoids cubemap seams and gives full control).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform vec4 top_color : source_color = vec4(0.34, 0.41, 0.41, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.78, 0.71, 0.58, 1.0);
uniform vec4 low_color : source_color = vec4(0.66, 0.62, 0.52, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.22, 0.25, 0.26, 1.0);
uniform vec4 sun_color : source_color = vec4(0.84, 0.26, 0.15, 1.0);
uniform vec4 ridge_far : source_color = vec4(0.47, 0.51, 0.49, 1.0);
uniform vec4 ridge_mid : source_color = vec4(0.31, 0.36, 0.33, 1.0);
uniform vec4 ridge_near : source_color = vec4(0.17, 0.21, 0.19, 1.0);
uniform float ridge_near_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 sun_dir = vec3(0.46, 0.20, -0.86);
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.85;

varying vec3 v_dir;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	for (int i = 0; i < 2; i++) {
	#else
	for (int i = 0; i < 4; i++) {
	#endif
		v += value_noise3(p) * a;
		p = p * 2.03 + vec3(4.7, 9.1, 2.3);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(v_dir);
	float up = clamp(d.y, -0.3, 1.0);
	float t = smoothstep(-0.02, 0.62, up);
	vec3 col = mix(horizon_color.rgb, top_color.rgb, pow(t, 0.8));
	col = mix(low_color.rgb, col, smoothstep(-0.15, 0.05, d.y));

	// Seamless ink clouds.
	vec3 cuv = d * 3.4;
	cuv.x += TIME * 0.006;
	float clouds = fbm3(cuv);
	float clouds2 = fbm3(cuv * 2.7 + vec3(7.0, 0.0, 3.0));
	float band = smoothstep(0.015, 0.16, d.y) * (1.0 - smoothstep(0.34, 0.72, d.y));
	float cloud_mask = smoothstep(0.46, 0.70, clouds + clouds2 * 0.25) * band * cloud_amount;
	col = mix(col, cloud_color.rgb, cloud_mask * 0.42);
	float cloud_fringe = smoothstep(0.40, 0.50, clouds + clouds2 * 0.25) * band * cloud_amount;
	col = mix(col, cloud_color.rgb * 1.3, cloud_fringe * 0.18);

	float streak = smoothstep(0.58, 0.78, fbm3(vec3(d.x * 2.0, d.y * 26.0, d.z * 2.0) + 5.0));
	col = mix(col, cloud_color.rgb * 0.9, streak * band * 0.22);

	// Cinnabar sun.
	float sd = clamp(dot(d, normalize(sun_dir)), -1.0, 1.0);
	float disc = smoothstep(0.9978, 0.9984, sd);
	float halo = pow(clamp(sd, 0.0, 1.0), 180.0);
	float broad = pow(clamp(sd, 0.0, 1.0), 14.0);
	float sun_tex = 0.82 + 0.32 * value_noise3(d * 90.0);
	float rim = smoothstep(0.9964, 0.9976, sd) * (1.0 - disc);
	col = mix(col, sun_color.rgb * 1.1, broad * 0.14);
	col = mix(col, sun_color.rgb * 1.25, halo * 0.55);
	col = mix(col, sun_color.rgb * 0.45, rim * 0.45);
	col = mix(col, sun_color.rgb * 1.6 * sun_tex, disc * 0.94);

	// Two hand-torn mountain ridges.
	float az = atan(d.z, d.x);
	float ridge_a = 0.105
		+ 0.040 * sin(az * 2.0 + 0.7)
		+ 0.018 * sin(az * 5.0 + 2.1)
		+ 0.007 * sin(az * 11.0 + 0.3);
	float ridge_b = 0.070
		+ 0.050 * sin(az * 3.0 + 1.7)
		+ 0.022 * sin(az * 7.0 + 0.4)
		+ 0.008 * sin(az * 17.0 + 1.1);
	float ridge_c = 0.038
		+ 0.058 * sin(az * 1.3 + 2.8)
		+ 0.025 * sin(az * 4.0 + 0.9)
		+ 0.010 * sin(az * 9.0 + 2.2);
	float mask_far = smoothstep(ridge_a + 0.006, ridge_a - 0.006, d.y);
	float mask_mid = smoothstep(ridge_b + 0.005, ridge_b - 0.005, d.y);
	float mask_near = smoothstep(ridge_c + 0.004, ridge_c - 0.004, d.y);
	col = mix(col, ridge_far.rgb, mask_far * 0.78);
	col = mix(col, ridge_mid.rgb, mask_mid * 0.86);
	col = mix(col, ridge_near.rgb, mask_near * 0.92 * ridge_near_strength);

	// Low-lying paper haze hugging the horizon.
	float haze = smoothstep(0.16, 0.0, d.y);
	col = mix(col, horizon_color.rgb, haze * 0.30);

	float grain = value_noise(vec2(d.x * 430.0 + d.z * 120.0, d.y * 520.0));
	col *= 1.0 - (grain - 0.5) * 0.045;

	ALBEDO = col;
}
