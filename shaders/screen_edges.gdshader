shader_type canvas_item;
render_mode unshaded;

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float low : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(0.60, 0.09, 0.06, 1.0);
uniform vec4 low_color : source_color = vec4(0.035, 0.028, 0.022, 1.0);

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p * vec2(1.22, 1.0));
	float edge = smoothstep(0.30, 0.78, d);
	float a = edge * low * 0.86;
	vec3 col = low_color.rgb;
	float fa = edge * flash * 0.92;
	if (fa > a) {
		col = flash_color.rgb;
		a = fa;
	}
	COLOR = vec4(col, clamp(a, 0.0, 0.92));
}
