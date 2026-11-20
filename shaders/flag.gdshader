shader_type spatial;
// Waving cloth flag. UV.x = 0 at the pole, so the free edge moves most.
render_mode cull_disabled, diffuse_burley;

uniform sampler2D flag_texture : source_color, filter_linear_mipmap;
uniform float wave_amount = 0.16;
uniform float wave_speed = 5.0;

void vertex() {
	float phase = NODE_POSITION_WORLD.x * 0.37;
	float w = sin(UV.x * 7.0 - TIME * wave_speed + phase) + 0.45 * sin(UV.x * 13.0 + UV.y * 3.0 - TIME * wave_speed * 1.6);
	VERTEX.z += w * wave_amount * UV.x;
	VERTEX.y -= UV.x * UV.x * 0.06;
}

void fragment() {
	vec4 tex = texture(flag_texture, UV);
	float fold = 0.88 + 0.12 * sin(UV.x * 7.0 - TIME * wave_speed);
	ALBEDO = tex.rgb * fold;
	ROUGHNESS = 0.75;
}
