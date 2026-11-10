// Ink Tide — masonry wall/pillar surface: painted stone courses, moss,
// water stains and dry-brush wear.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.46, 0.44, 0.38, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.13, 0.12, 0.10, 1.0);
uniform vec4 moss_color : source_color = vec4(0.30, 0.36, 0.28, 1.0);
uniform vec4 dust_color : source_color = vec4(0.63, 0.59, 0.49, 1.0);
uniform float block_w = 1.15;
uniform float block_h = 0.56;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.55;
uniform float wobble_amp : hint_range(0.0, 0.06) = 0.002;
uniform float hatch_strength : hint_range(0.0, 1.0) = 0.45;
uniform float pool_strength : hint_range(0.0, 1.0) = 0.3;
uniform float time_offset = 0.0;

instance uniform float hit_flash;

varying vec3 v_wpos;
varying vec3 v_wnorm;
varying float v_local_y;

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
	for (int i = 0; i < 4; i++) {
		v += value_noise(p) * a;
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local_y = VERTEX.y;
	vec3 wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	if (wobble_amp > 0.0001) {
		float t = floor(TIME * 7.0 + time_offset) + time_offset * 13.0;
		float n = value_noise(wp.xz * 2.2 + wp.y * 0.7 + vec2(t * 3.71, t * 1.37)) - 0.5;
		VERTEX += NORMAL * n * wobble_amp;
	}
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = wn;
}

void fragment() {
	vec3 n = normalize(v_wnorm);
	float vertical = 1.0 - smoothstep(0.3, 0.7, abs(n.y));

	// Tangent along the wall face so courses line up with each wall segment.
	vec2 tangent = normalize(vec2(-n.z, n.x) + vec2(0.0001, 0.0));
	float along = dot(v_wpos.xz, tangent);
	vec2 p = vec2(along, v_wpos.y);

	// Running bond courses.
	float row = floor(p.y / block_h);
	float offset = fract(row * 0.5) * block_w;
	vec2 bp = vec2((p.x + offset) / block_w, p.y / block_h);
	vec2 cell = floor(bp);
	vec2 bf = abs(fract(bp) - 0.5);

	float mortar_h = smoothstep(0.455, 0.497, bf.y);
	float mortar_v = smoothstep(0.465, 0.497, bf.x);
	float mortar = max(mortar_h, mortar_v) * vertical;
	mortar *= 0.55 + 0.45 * value_noise(p * 6.0);

	vec3 col = base_color.rgb;
	// Per-block tone shifts.
	float tint = hash21(cell + 4.0);
	col *= 0.82 + tint * 0.30;
	// Large ink wash and paper dust.
	float wash = fbm(p * 0.55 + 2.0);
	col = mix(col, dust_color.rgb, smoothstep(0.55, 0.84, wash) * 0.26);
	col *= 0.9 + 0.2 * fbm(p * 5.0);
	// Mortar.
	col = mix(col, mortar_color.rgb, mortar * 0.88);

	// Cracks.
	float crack = smoothstep(0.78, 0.88, fbm(vec2(p.x * 3.0, p.y * 1.0) + 13.0));
	col = mix(col, mortar_color.rgb, crack * vertical * 0.45);

	// Moss in the seams and along the base.
	float moss_patch = smoothstep(0.50, 0.78, fbm(p * 1.4 + 7.0));
	float base_moss = smoothstep(0.9, 0.0, p.y);
	col = mix(col, moss_color.rgb, moss_patch * moss_amount * (0.22 + mortar * 0.7 + base_moss * 0.35));

	// Old water stains bleeding down from the cap.
	float stain_noise = fbm(vec2(p.x * 0.9, 6.0));
	float stain = smoothstep(0.54, 0.78, stain_noise) * smoothstep(0.2, 2.8, p.y);
	col = mix(col, mortar_color.rgb, stain * vertical * 0.18);

	// Dry-brush speckle.
	float speck = value_noise(p * 34.0);
	col *= 0.95 + (speck - 0.5) * 0.12;

	// Dark ink pooling at the foot.
	float pool = exp(-max(v_local_y, 0.0) * 2.8);
	col = mix(col, col * 0.58, pool * pool_strength);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	if (hit_flash > 0.001) {
		ALBEDO = mix(ALBEDO, vec3(0.96, 0.93, 0.84), clamp(hit_flash, 0.0, 1.0) * 0.82);
		EMISSION = vec3(0.9, 0.85, 0.7) * clamp(hit_flash, 0.0, 1.0) * 0.35;
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += vec3(0.95, 0.91, 0.8) * fres * 0.07;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float s1 = smoothstep(-0.01, 0.06, ndl);
	float s2 = smoothstep(0.42, 0.50, ndl);
	float s3 = smoothstep(0.78, 0.86, ndl);
	float ramp = 0.28 + 0.36 * s1 + 0.21 * s2 + 0.15 * s3;

	vec3 hp = v_wpos;
	float hatch_a = sin(hp.x * 42.0 + hp.y * 29.0 + hp.z * 11.0) * 0.5 + 0.5;
	float hatch_b = sin(hp.x * -23.0 + hp.y * 37.0 + hp.z * 31.0) * 0.5 + 0.5;
	float hatch = smoothstep(0.28, 0.72, mix(hatch_a, hatch_b, 0.45));
	float shadow_mask = 1.0 - smoothstep(0.0, 0.45, ndl);
	ramp *= 1.0 - hatch * shadow_mask * hatch_strength * 0.55;

	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ramp;
}
