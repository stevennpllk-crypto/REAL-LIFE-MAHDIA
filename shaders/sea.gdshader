shader_type spatial;
// Mediterranean sea: Gerstner swell in the vertex stage, layered ripple
// normals, depth-tinted colour, shoreline foam. Reflections and the sun
// highlight come from Godot's own GGX specular + sky radiance (low roughness).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.008, 0.10, 0.26, 1.0);
uniform vec4 mid_color : source_color = vec4(0.015, 0.21, 0.42, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.05, 0.42, 0.52, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.97, 0.98, 1.0);
uniform float swell_height = 0.16;
uniform float ripple_strength = 0.55;
uniform int ripple_octaves = 5;
uniform float shore_z = -57.3;
// Rocky headland under the fortress: xmin, zmin, xmax, zmax.
uniform vec4 headland = vec4(-52.0, -82.0, -6.0, -57.3);
uniform float foam_width = 1.6;

varying vec3 world_pos;
varying float swell_crest;

vec3 gerstner(vec2 p, vec2 dir, float steepness, float wavelength, float speed, float t) {
	float k = 6.28318 / wavelength;
	float a = steepness / k;
	float f = k * (dot(dir, p) - speed * t);
	return vec3(dir.x * a * cos(f), a * sin(f), dir.y * a * cos(f));
}

float shore_distance(vec2 xz) {
	float d_line = xz.y - shore_z;           // negative out at sea
	vec2 c = vec2((headland.x + headland.z) * 0.5, (headland.y + headland.w) * 0.5);
	vec2 h = vec2((headland.z - headland.x) * 0.5, (headland.w - headland.y) * 0.5);
	vec2 q = abs(xz - c) - h;
	float d_box = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	return min(-d_line, d_box);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float fade = clamp(shore_distance(wp.xz) / 6.0, 0.15, 1.0);
	vec3 d = vec3(0.0);
	d += gerstner(wp.xz, normalize(vec2(0.25, 1.0)), 0.10, 18.0, 2.2, t);
	d += gerstner(wp.xz, normalize(vec2(-0.6, 0.8)), 0.07, 9.0, 1.6, t);
	d += gerstner(wp.xz, normalize(vec2(0.9, 0.4)), 0.05, 5.0, 1.2, t);
	d *= swell_height / 0.16 * fade;
	VERTEX += d;
	swell_crest = d.y;
	world_pos = wp + d;
}

vec2 ripple_slope(vec2 p, float t) {
	vec2 slope = vec2(0.0);
	float amp = 1.0;
	float freq = 0.55;
	for (int i = 0; i < 8; i++) {
		if (i >= ripple_octaves) { break; }
		float ang = float(i) * 2.399;
		vec2 dir = vec2(cos(ang), sin(ang));
		float ph = dot(dir, p) * freq + t * (1.1 + float(i) * 0.37);
		slope += dir * cos(ph) * amp * freq;
		amp *= 0.62;
		freq *= 1.83;
	}
	return slope;
}

void fragment() {
	vec2 xz = world_pos.xz;
	float dist = max(distance(CAMERA_POSITION_WORLD, world_pos), 0.001);
	// Ripples fade with distance to avoid shimmering aliasing on the horizon.
	float detail_fade = clamp(1.0 - dist / 160.0, 0.12, 1.0);
	vec2 slope = ripple_slope(xz, TIME) * ripple_strength * 0.12 * detail_fade;
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	float sd = shore_distance(xz);
	float shallow = 1.0 - smoothstep(0.0, 14.0, sd);
	float far_deep = smoothstep(25.0, 140.0, sd);
	vec3 col = mix(mid_color.rgb, deep_color.rgb, far_deep);
	col = mix(col, shallow_color.rgb, shallow * 0.85);
	// Light catches the wave crests (cheap subsurface impression).
	col += vec3(0.02, 0.09, 0.08) * clamp(swell_crest * 4.0, 0.0, 1.0);

	float n = vnoise(xz * 0.9 + vec2(TIME * 0.35, -TIME * 0.2)) * 0.6 + vnoise(xz * 2.7 - TIME * 0.5) * 0.4;
	float edge = foam_width * (0.55 + 0.9 * n);
	float foam = (1.0 - smoothstep(0.0, edge, sd)) * smoothstep(0.35, 0.6, n + 0.25 * sin(TIME * 1.7 + sd * 2.0));
	foam += smoothstep(0.11, 0.17, swell_crest) * smoothstep(0.55, 0.8, n) * 0.5;
	foam = clamp(foam, 0.0, 1.0);

	ALBEDO = mix(col, foam_color.rgb, foam);
	ROUGHNESS = mix(0.035, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = mix(0.62, 0.3, foam);
}
