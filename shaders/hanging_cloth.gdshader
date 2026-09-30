shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(0.45, 0.18, 0.14, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.88;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

/// Pendulum angles in radians. x = fore/aft (around X), y = side (around Z).
uniform vec2 sway = vec2(0.0);
uniform float heave = 0.0;
uniform float jostle = 0.0;
uniform float jostle_phase = 0.0;
uniform float hang_length = 1.0;
uniform float hang_width = 1.0;
uniform float pin_y = 0.0;
uniform float flutter = 0.018;
uniform float fold = 0.05;
uniform float pleat_count = 3.0;
uniform float bunch = 0.045;
uniform float puff = 0.035;
uniform float sway_bunch = 0.28;
uniform float cloth_time = 0.0;
uniform float cloth_seed = 0.0;

void vertex() {
	float len = max(hang_length, 0.001);
	vec3 p = VERTEX;
	p.y -= pin_y;
	float hang = clamp(-p.y / len, 0.0, 1.0);
	float t = hang * hang;
	float belly = mix(t, sin(hang * 3.14159265) * hang, 0.35);
	float half_w = max(hang_width * 0.5, 0.001);
	float across = p.x / half_w;
	float edge = across * across;
	float rest_x = p.x;
	float rest_z = p.z;

	p.y *= 1.0 + heave * hang;

	float gather = t;
	float pleat_phase = cloth_seed;
	float k = 3.14159265 * max(pleat_count, 0.001);
	float s = sin(across * k + pleat_phase);
	float c = cos(across * k + pleat_phase);
	p.x -= s * bunch * gather * half_w;
	p.z += c * puff * gather * hang_width;

	vec3 n = NORMAL;
	n.x += s * bunch * gather * 2.2;
	n.z -= s * puff * gather * 3.4;
	n = normalize(n);

	float rate = 1.0 + sin(cloth_seed) * 0.14;
	float n1 = sin(cloth_time * 1.7 * rate + across * 2.4 + cloth_seed);
	float n2 = sin(cloth_time * 2.3 * rate + hang * 5.1 + cloth_seed * 1.8);
	float n3 = sin(cloth_time * 0.85 * rate + across * 1.3 + hang * 2.0 + cloth_seed * 0.6);
	float flutter_x = (n1 * 0.55 + n3 * 0.45) * flutter * t;
	float flutter_z = (n2 * 0.6 + n1 * 0.4) * flutter * 0.7 * t;
	float wave = sin(hang * 8.0 - jostle_phase + across * 1.4) * jostle * belly;

	float ax = sway.x * belly + flutter_z * 0.35;
	float az = sway.y * belly + flutter_x * 0.45 + wave;

	vec3 from_pin = vec3(p.x - rest_x, p.y, p.z - rest_z);
	float cz = cos(az);
	float sz = sin(az);
	float cx = cos(ax);
	float sx = sin(ax);
	vec3 q = vec3(
		from_pin.x * cz - from_pin.y * sz,
		from_pin.x * sz + from_pin.y * cz,
		from_pin.z
	);
	from_pin = vec3(
		q.x,
		q.y * cx - q.z * sx,
		q.y * sx + q.z * cx
	);
	p = vec3(rest_x + from_pin.x, from_pin.y, rest_z + from_pin.z);

	float slack = max(-across * sign(sz + 0.0001), 0.0);
	float pack = slack * abs(sz) * sway_bunch * belly;
	p.x -= (s * pack + across * pack * 0.4) * half_w;
	p.z += abs(c) * pack * hang_width;
	p.z += edge * belly * fold * az * hang_length * 0.35;
	p.x += (1.0 - edge) * wave * hang_length * 0.12;
	p.y += pin_y;

	mat3 rot_x = mat3(
		vec3(1.0, 0.0, 0.0),
		vec3(0.0, cx, -sx),
		vec3(0.0, sx, cx)
	);
	mat3 rot_z = mat3(
		vec3(cz, -sz, 0.0),
		vec3(sz, cz, 0.0),
		vec3(0.0, 0.0, 1.0)
	);
	VERTEX = p;
	NORMAL = normalize(rot_x * rot_z * n);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = albedo_color.rgb * tex.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
