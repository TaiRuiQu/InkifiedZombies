// Ink Tide — inverted-hull outline.
// Constant-ish screen-space width, with optional hand-drawn thickness wobble.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(0.055, 0.050, 0.045, 1.0);
uniform float width : hint_range(0.0, 0.02) = 0.0070;
uniform float thickness_variation : hint_range(0.0, 1.0) = 0.45;
uniform float wobble_amp : hint_range(0.0, 0.08) = 0.0;
uniform float wobble_freq : hint_range(0.1, 8.0) = 2.0;
uniform float wobble_speed : hint_range(1.0, 24.0) = 8.0;
uniform float time_offset = 0.0;

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

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (wobble_amp > 0.0001) {
		float t = floor(TIME * wobble_speed + time_offset) + time_offset * 13.0;
		float n = value_noise(wp.xz * wobble_freq + wp.y * 0.7 + vec2(t * 3.71, t * 1.37)) - 0.5;
		float n2 = value_noise(wp.zy * wobble_freq * 1.3 + vec2(t * 2.13, t * 4.77)) - 0.5;
		VERTEX += NORMAL * (n + n2 * 0.5) * wobble_amp;
	}

	vec4 view_pos = VIEW_MATRIX * MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize(mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * NORMAL);
	float dist = max(-view_pos.z, 0.05);

	// Hand-pressed brush pressure varies along the contour.
	float tnow = floor(TIME * 6.0);
	float press = value_noise(wp.xz * 2.7 + wp.y * 1.9 + vec2(tnow * 0.37, tnow * 0.71));
	float thickness = width * (1.0 + (press - 0.5) * 2.0 * thickness_variation);

	view_pos.xyz += view_normal * thickness * clamp(dist, 0.4, 40.0);
	POSITION = PROJECTION_MATRIX * view_pos;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
