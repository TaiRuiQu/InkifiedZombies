// Ink Tide — first-person viewmodel surface. Flat painted colours with a
// fixed hand-lit ramp, independent of the world lighting.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, fog_disabled, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.20, 0.18, 0.15, 1.0);
uniform vec4 rim_color : source_color = vec4(0.95, 0.90, 0.80, 1.0);
uniform float grain : hint_range(0.0, 0.5) = 0.10;
uniform float rim : hint_range(0.0, 0.5) = 0.07;

varying vec3 v_local;

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
	v_local = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL); // view space
	float ndl = dot(n, normalize(vec3(-0.42, 0.78, 0.55)));
	float band = ndl > 0.25 ? 1.0 : (ndl > -0.3 ? 0.74 : 0.55);
	float g = value_noise(v_local.xz * 44.0 + v_local.y * 29.0);
	vec3 col = base_color.rgb * (0.58 + band * 0.42);
	col *= 0.94 + (g - 0.5) * grain * 1.6;
	float fres = pow(1.0 - abs(dot(n, VIEW)), 3.0);
	col += rim_color.rgb * fres * rim;
	ALBEDO = col;
}
