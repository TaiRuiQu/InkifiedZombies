// Ink Tide — base surface shader.
// Flat painted colour, toon banding, dry-brush hatching, paper grain and a
// subtle "boiling" vertex wobble so silhouettes feel hand-drawn.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.78, 0.75, 0.66, 1.0);
uniform vec4 shade_tint : source_color = vec4(0.42, 0.45, 0.47, 1.0);
uniform float wash_strength : hint_range(0.0, 1.0) = 0.22;
uniform float wash_scale : hint_range(0.01, 4.0) = 0.42;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.16;
uniform float hatch_strength : hint_range(0.0, 1.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.12;
uniform vec4 rim_color : source_color = vec4(0.98, 0.94, 0.82, 1.0);
uniform float pool_strength : hint_range(0.0, 1.0) = 0.22;
uniform float wobble_amp : hint_range(0.0, 0.08) = 0.0;
uniform float wobble_freq : hint_range(0.1, 8.0) = 2.0;
uniform float wobble_speed : hint_range(1.0, 24.0) = 8.0;
uniform float time_offset = 0.0;

// Per-instance hit flash (used by enemies). Does not affect shared materials.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
uniform float hit_flash = 0.0;
#else
instance uniform float hit_flash;
#endif

varying vec3 v_wpos;
varying vec3 v_wnorm;
varying float v_local_y;
varying float v_seed;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	for (int i = 0; i < 2; i++) {
	#else
	for (int i = 0; i < 4; i++) {
	#endif
		v += value_noise(p) * a;
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_local_y = VERTEX.y;
	v_seed = hash21(wp.xz * 0.37 + wp.y);
	if (wobble_amp > 0.0001) {
		float t = floor(TIME * wobble_speed + time_offset) + time_offset * 13.0;
		float n = value_noise(wp.xz * wobble_freq + wp.y * 0.7 + vec2(t * 3.71, t * 1.37)) - 0.5;
		float n2 = value_noise(wp.zy * wobble_freq * 1.3 + vec2(t * 2.13, t * 4.77)) - 0.5;
		VERTEX += NORMAL * (n + n2 * 0.5) * wobble_amp;
	}
	v_wpos = wp;
	v_wnorm = wn;
}

void fragment() {
	// Triplanar paper wash so props never show stretched UVs.
	vec3 blend = pow(abs(normalize(v_wnorm)), vec3(4.0));
	blend /= (blend.x + blend.y + blend.z + 0.0001);
	vec2 p = v_wpos.xz * wash_scale + vec2(v_wpos.y * 0.31, -v_wpos.y * 0.23);
	float wash_a = fbm(p);
	float wash_b = fbm(p * 2.7 + 4.3);
	float wash = mix(wash_a, wash_b, 0.35);
	float grain = value_noise(v_wpos.xz * 26.0 + vec2(v_wpos.y * 21.0));

	vec3 col = base_color.rgb;
	// Large uneven ink washes.
	col *= 1.0 - (wash - 0.5) * wash_strength * 2.0;
	// Dry-brush flecks.
	col *= 1.0 - (grain - 0.5) * grain_strength * 1.6;
	// Ink pools at the feet of objects.
	float pool = exp(-max(v_local_y, 0.0) * 2.6);
	col = mix(col, col * 0.62, pool * pool_strength);
	// Slight warm/cool variation keeps the palette from feeling digital.
	col = mix(col, shade_tint.rgb, (1.0 - wash_a) * 0.10);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	if (hit_flash > 0.001) {
		ALBEDO = mix(ALBEDO, vec3(0.96, 0.93, 0.84), clamp(hit_flash, 0.0, 1.0) * 0.82);
		EMISSION = vec3(0.9, 0.85, 0.7) * clamp(hit_flash, 0.0, 1.0) * 0.35;
	}

	// Rim light to separate silhouettes from the paper sky.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += rim_color.rgb * fres * rim_strength;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));

	// Three hard toon bands with a hand-cut terminator.
	float s1 = smoothstep(-0.01, 0.06, ndl);
	float s2 = smoothstep(0.42, 0.50, ndl);
	float s3 = smoothstep(0.78, 0.86, ndl);
	float ramp = 0.28 + 0.36 * s1 + 0.21 * s2 + 0.15 * s3;

	// Dry-brush hatching that only bites in the shadow bands.
	vec3 hp = v_wpos;
	float hatch_a = sin(hp.x * 42.0 + hp.y * 29.0 + hp.z * 11.0) * 0.5 + 0.5;
	float hatch_b = sin(hp.x * -23.0 + hp.y * 37.0 + hp.z * 31.0) * 0.5 + 0.5;
	float hatch = smoothstep(0.28, 0.72, mix(hatch_a, hatch_b, 0.45));
	float shadow_mask = 1.0 - smoothstep(0.0, 0.45, ndl);
	ramp *= 1.0 - hatch * shadow_mask * hatch_strength * 0.55;

	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ramp;
}
