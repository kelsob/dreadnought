shader_type canvas_item;

// Plot memory. Copies the last scan, and rewrites only the wedge the beam just crossed.
// world_open must stay in step with radar_hologram.gdshader.

uniform sampler2D history_tex : filter_nearest, repeat_disable, hint_default_black;
uniform float sweep_prev = 0.0;
uniform float sweep_curr = 0.0;
uniform float sweep_laps = 0.0;
uniform float sweep_pad = 0.015;

uniform sampler2D world_tex : filter_linear, repeat_disable, hint_default_black;
uniform vec2 world_size = vec2(1.0);
uniform vec2 world_origin = vec2(0.0);
uniform float world_range = 16.0;
uniform float world_on = 0.0;
uniform float terrain_span = 8.0;
uniform float terrain_soft = 0.85;

float world_open(vec2 q) {
	vec2 world = world_origin + q * world_range;
	float inside = step(0.0, world.x) * (1.0 - step(world_size.x, world.x));
	inside *= step(0.0, world.y) * (1.0 - step(world_size.y, world.y));
	vec2 uv = world / max(world_size, vec2(1.0));
	float sdf = (texture(world_tex, uv).r - 0.5) * (terrain_span * 2.0);
	float band = max(terrain_soft, 0.001);
	return smoothstep(-band, band, sdf) * inside;
}

void fragment() {
	vec2 q = (UV - vec2(0.5)) * 2.0;
	float ang = atan(q.y, q.x);
	float span = mod(sweep_curr - sweep_prev + TAU, TAU);
	float from_prev = mod(ang - sweep_prev + TAU, TAU);
	float hit = sweep_laps >= 1.0 ? 1.0 : step(from_prev, span + max(sweep_pad, 0.0));

	vec4 hist = texture(history_tex, UV);
	float held_open = hist.r;
	float held_seen = hist.g;
	float fresh = world_on > 0.5 ? world_open(q) : held_open;
	float open = mix(held_open, fresh, hit);
	float seen = max(held_seen, hit);
	COLOR = vec4(open, seen, 0.0, 1.0);
}
