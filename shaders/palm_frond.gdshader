shader_type spatial;
// Palm fronds: vertex colours for leaf variation, double sided, gentle wind.
// UV.x carries the position along the frond (0 at the crown, 1 at the tip).
render_mode cull_disabled, diffuse_burley;

uniform float wind_strength = 0.10;

void vertex() {
	float phase = NODE_POSITION_WORLD.x * 0.31 + NODE_POSITION_WORLD.z * 0.17;
	float tip = UV.x * UV.x;
	VERTEX.x += sin(TIME * 1.3 + phase + VERTEX.z * 0.4) * wind_strength * tip;
	VERTEX.z += cos(TIME * 1.1 + phase * 1.3 + VERTEX.x * 0.4) * wind_strength * tip;
	VERTEX.y += sin(TIME * 2.1 + phase + UV.x * 3.0) * wind_strength * 0.5 * tip;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.62;
	SPECULAR = 0.35;
}
