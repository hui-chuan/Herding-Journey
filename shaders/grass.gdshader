// 草丛：顶部随风摆动，高度与颜色随草场网格变化（GRASSLAND §6）。
shader_type spatial;
render_mode cull_disabled;

uniform vec3 color_base : source_color = vec3(0.55, 0.6, 0.28);
uniform vec3 color_tip : source_color = vec3(0.78, 0.75, 0.4);
// 吃秃的地是干草色，不是焦黑——高原的秃地是干的，不是死的。
// 也避免让玩家觉得自己在破坏环境（PRD：不说教）。
uniform vec3 color_bare : source_color = vec3(0.62, 0.55, 0.34);
// 肥草偏深偏绿。有它草量的高段才有区分，否则 0.55 以上全是一个颜色。
uniform vec3 color_lush : source_color = vec3(0.42, 0.55, 0.22);
uniform float wind_strength = 0.15;
uniform float wind_speed = 1.2;

// 草场网格：R = 草量，G = 退化。由 Grassland 每日更新。
uniform sampler2D grassland_tex : filter_linear, source_color, hint_default_white;
uniform float map_size = 400.0;
// 秃地的草矮到这个比例。高度比颜色更能读出"这里被吃过"——
// 远景俯视下高度差依然可见，颜色差会被距离和雾冲淡。
uniform float bare_height = 0.25;

varying float height_t;
varying float grass_amount;

void vertex() {
	height_t = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (wp.xz + map_size * 0.5) / map_size;
	grass_amount = texture(grassland_tex, uv).r;

	VERTEX.y *= mix(bare_height, 1.0, grass_amount);
	float phase = wp.x * 0.3 + wp.z * 0.2;
	float sway = sin(TIME * wind_speed + phase) * wind_strength * height_t * height_t;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.5;
}

void fragment() {
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 c = mix(color_base, color_tip, height_t);
	// 秃 → 常态 → 肥，整个 0–1 区间都有可见变化。
	// 原来只在 0–0.55 之间过渡，而地图大部分格子在 0.55 以上，于是全图一个色。
	c = mix(color_bare, c, smoothstep(0.02, 0.45, grass_amount));
	c = mix(c, color_lush, smoothstep(0.5, 1.0, grass_amount) * 0.55);
	c *= 0.85 + 0.3 * COLOR.r;
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
