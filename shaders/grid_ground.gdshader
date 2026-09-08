// 灰盒地面：10 m 大格 + 1 m 小格。大格与草场格（BEHAVIOR §4）同尺寸。
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.55, 0.6, 0.3);
uniform vec3 line_color : source_color = vec3(0.35, 0.4, 0.2);
// 秃地与肥草，与 grass.gdshader 用同一组颜色。
uniform vec3 color_bare : source_color = vec3(0.62, 0.55, 0.34);
uniform vec3 color_lush : source_color = vec3(0.42, 0.55, 0.22);
uniform float major = 10.0;
uniform float minor = 1.0;

// 草场网格（GRASSLAND §6）。远视角下草丛只占很少像素，
// 真正让玩家看出"哪里被吃过"的是地面本身的颜色。
uniform sampler2D grassland_tex : filter_linear, source_color, hint_default_white;
uniform float map_size = 400.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float size, float width) {
	vec2 g = abs(fract(p / size - 0.5) - 0.5) * size;
	float d = min(g.x, g.y);
	return 1.0 - smoothstep(0.0, width, d);
}

void fragment() {
	vec2 p = world_pos.xz;
	float major_l = grid(p, major, 0.12);
	float minor_l = grid(p, minor, 0.03) * 0.35;
	float l = max(major_l * 0.5, minor_l * 0.4);
	float g = texture(grassland_tex, (p + map_size * 0.5) / map_size).r;
	vec3 ground = mix(color_bare, base_color, smoothstep(0.02, 0.45, g));
	ground = mix(ground, color_lush, smoothstep(0.5, 1.0, g) * 0.55);
	ALBEDO = mix(ground, line_color, l);
	ROUGHNESS = 1.0;
}
