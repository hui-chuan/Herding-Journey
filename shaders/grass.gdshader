// 草丛：顶部随风摆动，颜色按实例微变。
shader_type spatial;
render_mode cull_disabled;

uniform vec3 color_base : source_color = vec3(0.55, 0.6, 0.28);
uniform vec3 color_tip : source_color = vec3(0.78, 0.75, 0.4);
uniform float wind_strength = 0.15;
uniform float wind_speed = 1.2;

varying float height_t;

void vertex() {
	height_t = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = wp.x * 0.3 + wp.z * 0.2;
	float sway = sin(TIME * wind_speed + phase) * wind_strength * height_t * height_t;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.5;
}

void fragment() {
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 c = mix(color_base, color_tip, height_t);
	c *= 0.85 + 0.3 * COLOR.r;
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
