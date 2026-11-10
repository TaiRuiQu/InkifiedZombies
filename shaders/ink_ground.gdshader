// Ink Tide — arena floor. Painted stone slabs, ink wash, moss, brush ring.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.56, 0.53, 0.45, 1.0);
uniform vec4 ink_color : source_color = vec4(0.12, 0.115, 0.105, 1.0);
uniform vec4 moss_color : source_color = vec4(0.38, 0.42, 0.33, 1.0);
uniform vec4 dust_color : source_color = vec4(0.78, 0.73, 0.60, 1.0);
uniform float arena_radius = 27.0;

varying vec3 v_wpos;

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
	for (int i = 0; i < 5; i++) {
		v += value_noise(p) * a;
		p = p * 2.02 + vec2(11.3, 7.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_wpos.xz;
	float r = length(p);
	float ang = atan(p.y, p.x);

	vec3 col = base_color.rgb;
	float wash = fbm(p * 0.12 + vec2(3.1, 8.4));
	float wash2 = fbm(p * 0.55 - 7.3);
	col = mix(col, ink_color.rgb, smoothstep(0.54, 0.90, wash) * 0.26);
	col = mix(col, dust_color.rgb, smoothstep(0.5, 0.85, wash2) * 0.24);
	col = mix(col, col * 0.76, smoothstep(0.46, 0.86, wash2) * 0.42);

	// Long dry-brush strokes.
	float streak = fbm(vec2(p.x * 0.10, p.y * 2.2));
	col *= 0.88 + streak * 0.20;

	// Old stone slabs.
	vec2 g = p * 0.36;
	vec2 gf = abs(fract(g + vec2(value_noise(p * 0.2) * 0.05)) - 0.5);
	float edge = smoothstep(0.455, 0.497, max(gf.x, gf.y));
	float chip = value_noise(p * 10.0);
	col = mix(col, col * 0.60, edge * (0.40 + chip * 0.35));

	// Moss gathered in the seams.
	float moss = smoothstep(0.55, 0.82, fbm(p * 0.48 + vec2(13.0, 2.0)));
	col = mix(col, moss_color.rgb, moss * (0.20 + edge * 0.5));

	// Central painted spiral — broken brush strokes.
	float ring_radius = 10.6 + (fbm(vec2(ang * 1.7, 5.0)) - 0.5) * 0.5;
	float ring = exp(-pow((r - ring_radius) / 0.22, 2.0));
	float ring_break = smoothstep(0.34, 0.62, fbm(vec2(ang * 5.5, r * 0.7) + 2.0));
	col = mix(col, ink_color.rgb, ring * ring_break * 0.8);

	// Smaller inner glyph ring.
	float ring2 = exp(-pow((r - 4.1) / 0.13, 2.0));
	col = mix(col, ink_color.rgb, ring2 * smoothstep(0.4, 0.7, fbm(vec2(ang * 7.0, 3.0))) * 0.5);

	// Uneven ink pooling around the middle of the courtyard.
	float center_wash = smoothstep(0.42, 0.85, fbm(p * 0.32 + 10.0)) * smoothstep(20.0, 6.0, r);
	col = mix(col, ink_color.rgb, center_wash * 0.26);

	// Ink tide creeping in from the walls.
	float edge_dark = smoothstep(arena_radius - 7.0, arena_radius + 2.0, r);
	col = mix(col, ink_color.rgb, edge_dark * 0.70);

	// Splatter speckles.
	float sp = smoothstep(0.945, 0.99, fbm(p * 15.0 + 5.0));
	col = mix(col, ink_color.rgb, sp * 0.45);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += vec3(0.95, 0.91, 0.8) * fres * 0.04;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float s1 = smoothstep(-0.04, 0.06, ndl);
	float s2 = smoothstep(0.34, 0.44, ndl);
	float ramp = 0.50 + 0.30 * s1 + 0.20 * s2;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ramp;
}
