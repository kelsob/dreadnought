shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.35, 1.0, 0.55, 1.0);
uniform vec4 line_color : source_color = vec4(0.35, 1.0, 0.55, 0.52);
uniform vec4 radial_color : source_color = vec4(0.35, 1.0, 0.55, 0.52);
uniform vec4 sweep_color : source_color = vec4(0.35, 1.0, 0.55, 0.52);
uniform vec4 label_color : source_color = vec4(0.35, 1.0, 0.55, 1.0);
uniform vec4 click_color : source_color = vec4(0.35, 1.0, 0.55, 0.52);
uniform vec4 mech_line : source_color = vec4(0.35, 1.0, 0.55, 0.52);
uniform float emission_energy = 3.5;
uniform float fill_alpha = 0.06;
uniform float uv_rotation = 0.0;

uniform int ring_count = 3;
uniform float ring_width = 0.008;
uniform float outer_width = 0.016;

uniform int radial_count = 8;
uniform float radial_width = 0.006;
uniform int sub_radial_count = 8;
uniform float sub_radial_width = 0.003;

uniform float sweep_angle = 0.0;
uniform float sweep_width = 0.04;
uniform float sweep_trail = 0.55;

uniform vec2 click_uv = vec2(-1.0);
uniform float click_size = 0.018;
uniform float click_on = 0.0;

uniform float mech_size = 0.055;
uniform vec4 mech_fill : source_color = vec4(0.85, 0.08, 0.08, 1.0);
uniform float mech_outline_width = 0.012;
uniform vec2 mech_pos = vec2(0.0);
uniform float heading_mark_length = 0.09;
uniform float heading_mark_width = 0.012;
uniform float art_rotation = 0.0;
uniform float diagram_scale = 0.9;
uniform float frame_radius = 0.985;
uniform float frame_width = 0.01;
uniform sampler2D label_tex : source_color, hint_default_transparent;

uniform float crt_mix = 1.0;
uniform float scanline_count = 220.0;
uniform float scanline_strength = 0.35;
uniform float scanline_sharpness = 1.4;
uniform float grille_count = 280.0;
uniform float grille_strength = 0.18;
uniform float noise_strength = 0.08;
uniform float flicker_strength = 0.04;
uniform float flicker_speed = 22.0;
uniform float vignette_strength = 0.45;
uniform float vignette_power = 1.8;
uniform float fringe_strength = 0.04;
uniform float roll_strength = 0.06;
uniform float roll_speed = 0.12;

uniform sampler2D world_tex : filter_linear, repeat_disable, hint_default_black;
uniform vec2 world_size = vec2(1.0);
uniform vec2 world_origin = vec2(0.0);
uniform float world_range = 16.0;
uniform float world_on = 0.0;
uniform float terrain_closed = 0.72;
uniform float terrain_open = 0.16;
uniform float terrain_span = 8.0;
uniform float terrain_soft = 0.85;
uniform vec4 ground_color : source_color = vec4(0.94, 0.55, 0.36, 1.0);
uniform float ground_fill = 0.04;
uniform sampler2D echo_tex : filter_linear, repeat_disable, hint_default_black;
uniform float echo_on = 0.0;

float line(float dist, float width) {
	return 1.0 - smoothstep(0.0, width, dist);
}

vec2 rot(vec2 v, float a) {
	float ca = cos(a);
	float sa = sin(a);
	return vec2(v.x * ca - v.y * sa, v.x * sa + v.y * ca);
}

float world_open(vec2 q) {
	vec2 world = world_origin + q * world_range;
	float inside = step(0.0, world.x) * (1.0 - step(world_size.x, world.x));
	inside *= step(0.0, world.y) * (1.0 - step(world_size.y, world.y));
	vec2 uv = world / max(world_size, vec2(1.0));
	float sdf = (texture(world_tex, uv).r - 0.5) * (terrain_span * 2.0);
	float band = max(terrain_soft, 0.001);
	return smoothstep(-band, band, sdf) * inside;
}

void add_tint(inout vec3 col, inout float alpha, vec4 tint, float mask) {
	col += tint.rgb * mask * tint.a * emission_energy;
	alpha += mask * tint.a;
}

float dist_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.00001), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 s = (UV - vec2(0.5)) * 2.0;
	if (length(s) > 1.0) {
		discard;
	}

	vec2 q = rot(s, uv_rotation) / max(diagram_scale, 0.05);
	float r = length(q);
	float ang = atan(q.y, q.x);
	float in_plot = 1.0 - step(1.001, r);

	float fill = fill_alpha * (1.0 - r);
	float rings = line(abs(r - 1.0), outer_width);

	for (int i = 1; i <= 12; i++) {
		if (i > ring_count) {
			break;
		}
		float target = float(i) / float(ring_count + 1);
		rings += line(abs(r - target), ring_width) * 0.75;
	}

	float rr = max(r, 0.001);
	float main_n = float(max(radial_count, 1));
	float main_period = TAU / main_n;
	float main_ang = ang - main_period * 0.5;
	float main_t = min(fract(main_ang / main_period), 1.0 - fract(main_ang / main_period));
	float main_dist = main_t * main_period * rr;
	float main_line = line(main_dist, radial_width) * step(0.02, r);
	float radials = main_line * 0.55;

	if (sub_radial_count > 0) {
		float sub_n = float(sub_radial_count);
		float sub_period = TAU / sub_n;
		float sub_t = min(fract(ang / sub_period), 1.0 - fract(ang / sub_period));
		float sub_dist = sub_t * sub_period * rr;
		float sub_line = line(sub_dist, sub_radial_width) * step(0.02, r);
		sub_line *= step(main_period * 0.25, main_t * main_period);
		radials += sub_line * 0.28;
	}

	float delta = sweep_angle - ang;
	delta = mod(delta + TAU, TAU);
	float trail = 1.0 - smoothstep(0.0, max(sweep_trail, 0.001), delta / TAU);
	float arm = 1.0 - smoothstep(0.0, sweep_width, abs(delta));
	float beam = max(arm, trail * 0.35) * step(r, 1.0);
	fill *= in_plot;
	rings *= in_plot;
	radials *= in_plot;
	beam *= in_plot;

	float open = 1.0;
	float seen = 0.0;
	if (world_on > 0.5) {
		seen = 1.0;
		open = world_open(q);
		if (echo_on > 0.5) {
			vec4 echo = texture(echo_tex, q * 0.5 + vec2(0.5));
			open = echo.r;
			seen = echo.g;
		}
		float dim = mix(1.0, mix(1.0 - terrain_closed, 1.0, open), seen);
		rings *= dim;
		radials *= dim;
		beam *= dim;
	}
	float land = (1.0 - open) * seen * in_plot;
	float open_field = fill * (1.0 - land) + terrain_open * open * seen * in_plot;
	float frame = line(abs(length(s) - frame_radius), frame_width);
	float click = 0.0;

	if (click_on > 0.5 && click_uv.x >= 0.0) {
		vec2 cp = rot((click_uv - vec2(0.5)) * 2.0, uv_rotation) / max(diagram_scale, 0.05);
		click = line(length(q - cp), click_size) * 2.0 * in_plot;
	}

	vec2 m = rot(s, art_rotation) / max(diagram_scale, 0.05);
	vec2 d = m - mech_pos;
	float mech_r = length(d);
	float self_fill = 1.0 - smoothstep(mech_size - 0.004, mech_size, mech_r);
	float self_ring = line(abs(mech_r - mech_size), mech_outline_width);
	vec2 fwd = rot(vec2(0.0, -1.0), art_rotation);
	float mark = line(dist_segment(d, fwd * mech_size, fwd * (mech_size + heading_mark_length)), heading_mark_width);
	float clear = 1.0 - self_fill;
	rings *= clear;
	radials *= clear;
	beam *= clear;
	click *= clear;
	open_field *= clear;
	land *= clear;

	vec3 col = vec3(0.0);
	float alpha = 0.0;
	add_tint(col, alpha, color, open_field);
	float wash = ground_fill * (1.0 - 0.35 * clamp(r, 0.0, 1.0)) * land;
	add_tint(col, alpha, ground_color, wash);
	add_tint(col, alpha, line_color, rings + frame);
	add_tint(col, alpha, radial_color, radials);
	add_tint(col, alpha, sweep_color, beam);
	add_tint(col, alpha, click_color, click);
	add_tint(col, alpha, mech_line, self_ring + mark);
	col += mech_fill.rgb * self_fill * mech_fill.a * emission_energy;
	alpha += self_fill * mech_fill.a;
	vec4 lab = texture(label_tex, UV);
	col += label_color.rgb * lab.a * label_color.a * emission_energy;
	alpha += lab.a * label_color.a;

	float scan = abs(sin(UV.y * scanline_count * TAU));
	scan = pow(scan, max(scanline_sharpness, 0.2));
	scan = mix(1.0, scan, scanline_strength);
	float gx = fract(UV.x * grille_count);
	vec3 grille = vec3(
		smoothstep(0.0, 0.12, gx) * smoothstep(0.33, 0.21, gx),
		smoothstep(0.33, 0.45, gx) * smoothstep(0.66, 0.54, gx),
		smoothstep(0.66, 0.78, gx) * smoothstep(1.0, 0.88, gx)
	);
	grille = mix(vec3(1.0), grille * 3.0, grille_strength);
	float vig = 1.0 - vignette_strength * pow(clamp(length(s), 0.0, 1.0), max(vignette_power, 0.2));
	float n = fract(sin(dot(UV * 87.1 + vec2(TIME * 9.3, TIME * 5.1), vec2(12.9898, 78.233))) * 43758.5453);
	float flick = 1.0 + sin(TIME * flicker_speed) * flicker_strength + (n - 0.5) * noise_strength;
	float roll = 1.0 + roll_strength * (1.0 - smoothstep(0.0, 0.08, abs(fract(UV.y - TIME * roll_speed) - 0.62)));
	vec3 fringe = vec3(1.0 + fringe_strength * s.x, 1.0, 1.0 - fringe_strength * s.x);
	vec3 crt = col * scan * grille * vig * flick * roll * fringe;
	col = mix(col, crt, clamp(crt_mix, 0.0, 1.0));
	alpha *= mix(1.0, scan * vig * flick, clamp(crt_mix, 0.0, 1.0) * 0.65);

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
	EMISSION = col;
}
