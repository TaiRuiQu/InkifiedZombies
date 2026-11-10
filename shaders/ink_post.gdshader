// Ink Tide — full-screen paper grade. Subtle boiling jitter, grain, ink
// vignette and the damage haemorrhage. Applied on a CanvasLayer ColorRect.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.055;
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.5;
uniform float wash_amount : hint_range(0.0, 1.0) = 0.20;
uniform float boil_amount : hint_range(0.0, 4.0) = 0.8;
uniform float posterize_amount : hint_range(0.0, 1.0) = 0.26;
uniform vec4 paper_tint : source_color = vec4(0.98, 0.95, 0.86, 1.0);
uniform vec4 ink_tint : source_color = vec4(0.10, 0.10, 0.10, 1.0);
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform vec4 damage_color : source_color = vec4(0.52, 0.09, 0.07, 1.0);
uniform float low_health : hint_range(0.0, 1.0) = 0.0;

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
		p = p * 2.03 + vec2(5.1, 9.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Hand-drawn "boil": the whole frame shivers a fraction.
	float t = floor(TIME * 7.0);
	vec2 wob = vec2(
		value_noise(uv * vec2(9.0, 7.0) + vec2(t * 1.7, 0.0)),
		value_noise(uv * vec2(8.0, 10.0) + vec2(31.0, t * 2.3))
	) - 0.5;
	vec3 col = texture(screen_texture, uv + wob * 0.0011 * boil_amount).rgb;

	// Slightly desaturated painted palette.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, 0.88);

	// Paper lift.
	col = mix(col, col * paper_tint.rgb, 0.07);

	// Screen-printed paper grain (kept low-frequency so it never moirés).
	float g = value_noise(SCREEN_UV * vec2(150.0, 92.0));
	g = g * 0.62 + value_noise(SCREEN_UV * vec2(330.0, 200.0) + 13.0) * 0.38;
	col *= 1.0 - (g - 0.5) * grain_amount * 1.2;

	// Large ink wash blooming in from the corners.
	vec2 c = SCREEN_UV - 0.5;
	float wash = fbm(SCREEN_UV * 2.7 + vec2(4.0, 9.0));
	float wash_v = smoothstep(0.52, 0.86, wash + length(c) * 0.35);
	col *= 1.0 - wash_v * wash_amount * 0.16;

	// Ragged paper vignette.
	float dist = length(c * vec2(1.18, 1.0));
	float vig = smoothstep(0.40, 0.86, dist + (wash - 0.5) * 0.10);
	col = mix(col, col * ink_tint.rgb * 1.9, vig * vignette_amount);

	// Gentle colour banding for a painted, non-digital surface.
	col = mix(col, floor(col * 22.0) / 22.0, posterize_amount);

	// Low health: cold ink creeps in at the edges.
	if (low_health > 0.001) {
		float pulse = 0.75 + 0.25 * sin(TIME * 3.2);
		col = mix(col, ink_tint.rgb, vig * low_health * 0.55 * pulse);
	}

	// Fresh damage splash.
	if (damage > 0.001) {
		float splash = smoothstep(0.18, 0.78, dist + (wash - 0.5) * 0.35);
		col = mix(col, damage_color.rgb, splash * damage * 0.85);
	}

	COLOR = vec4(col, 1.0);
}
