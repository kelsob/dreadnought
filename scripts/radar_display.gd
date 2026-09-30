class_name RadarDisplay
extends MeshInstance3D

## Shader-drawn radar on RadarFace. Tune the groups in the inspector.
## The shore is held in an offscreen plot and refreshed only under the sweep.

@export_group("Look")
@export_range(0.0, 40.0, 0.1) var emission_energy := 12.0
@export_range(0.0, 1.0, 0.01) var fill_alpha := 0.06
@export_range(-180.0, 180.0, 0.1) var uv_rotation_degrees := 0.0

@export_group("Rings")
## Range rings, the plot rim, and the outer frame.
@export var line_color := Color(0.35, 1.0, 0.55, 0.52)
@export_range(1, 12) var ring_count := 3
@export_range(0.001, 0.05, 0.001) var ring_width := 0.008
@export_range(0.001, 0.08, 0.001) var outer_width := 0.016

@export_group("Radials")
## Main radials and the thinner ones between them.
@export var radial_color := Color(0.35, 1.0, 0.55, 0.52)
@export_range(2, 24) var radial_count := 8
@export_range(0.001, 0.05, 0.001) var radial_width := 0.006
@export_range(0, 24) var sub_radial_count := 8
@export_range(0.001, 0.04, 0.001) var sub_radial_width := 0.003

@export_group("Sweep")
@export var sweep_color := Color(0.35, 1.0, 0.55, 0.52)
@export var sweep_seconds := 2.4
@export_range(0.005, 0.2, 0.001) var sweep_width := 0.04
@export_range(0.05, 1.0, 0.01) var sweep_trail := 0.55
## The shore stays as last scanned, and changes only when the beam passes over it.
@export var sweep_paints_plot := true
## Plot memory size. Read when the radar starts. Raise it if the coast looks blocky.
@export_range(128, 1024, 64) var echo_resolution := 512

@export_group("Mech")
@export_range(0.02, 0.2, 0.001) var mech_size := 0.055
@export var mech_fill := Color(0.85, 0.08, 0.08, 1.0)
## Outline and heading tick.
@export var mech_line := Color(0.35, 1.0, 0.55, 0.52)
@export_range(0.001, 0.04, 0.001) var mech_outline_width := 0.012
@export_range(0.02, 0.25, 0.001) var heading_mark_length := 0.09
@export_range(0.002, 0.04, 0.001) var heading_mark_width := 0.012
## World units from origin to the plot rim.
@export var radar_range := 16.0

@export_group("Terrain")
## Walkable ground, and the plot before the sweep has painted it.
@export var color := Color(0.35, 1.0, 0.55, 1.0)
## Closed ground on the plot.
@export var ground_color := Color(0.94, 0.55, 0.36, 1.0)
## Strength of that wash. The face emission multiplies it, so a small number is already bright.
@export_range(0.0, 0.35, 0.005) var ground_fill := 0.04
## How far closed ground drops the rings, radials, and sweep. 0 leaves them unchanged.
@export_range(0.0, 1.0, 0.01) var closed_dim := 0.72
## Extra glow on open ground.
@export_range(0.0, 1.0, 0.01) var open_lift := 0.16
## Width of the soft shore, in world units. The feet still stop on the hard cell edge.
@export_range(0.05, 3.0, 0.05) var shore_softness := 0.85

@export_group("Labels")
@export var label_color := Color(0.35, 1.0, 0.55, 1.0)
@export var angle_font: Font
@export_range(8, 72) var angle_font_size := 28
@export_range(5, 90, 1) var angle_step_degrees := 60
@export_range(0.7, 1.0, 0.01) var diagram_scale := 0.9
@export_range(0.88, 1.0, 0.005) var label_radius := 0.925
## Fixed rim outside the bearing labels. 1 is the edge of the face.
@export_range(0.9, 1.0, 0.005) var frame_radius := 0.985
@export_range(0.001, 0.04, 0.001) var frame_width := 0.01

@export_group("Click")
@export var click_color := Color(0.35, 1.0, 0.55, 0.52)
@export_range(0.004, 0.08, 0.001) var click_size := 0.018
@export var pick_distance := 4.0

@export_group("CRT")
@export_range(0.0, 1.0, 0.01) var crt_mix := 1.0
@export_range(20.0, 600.0, 1.0) var scanline_count := 220.0
@export_range(0.0, 1.0, 0.01) var scanline_strength := 0.35
@export_range(0.2, 4.0, 0.05) var scanline_sharpness := 1.4
@export_range(20.0, 800.0, 1.0) var grille_count := 280.0
@export_range(0.0, 1.0, 0.01) var grille_strength := 0.18
@export_range(0.0, 0.5, 0.005) var noise_strength := 0.08
@export_range(0.0, 0.25, 0.005) var flicker_strength := 0.04
@export_range(1.0, 60.0, 0.5) var flicker_speed := 22.0
@export_range(0.0, 1.0, 0.01) var vignette_strength := 0.45
@export_range(0.4, 4.0, 0.05) var vignette_power := 1.8
@export_range(0.0, 0.2, 0.005) var fringe_strength := 0.04
@export_range(0.0, 0.4, 0.005) var roll_strength := 0.06
@export_range(0.0, 1.5, 0.01) var roll_speed := 0.12

var _material: ShaderMaterial
var _label_vp: SubViewport
var _label_layer: RadarAngleLabels
var _machine_motion: MachineMotion
var _world: World
var _sweep := 0.0
## Last finished scan. The other buffer is the one drawn this frame.
var _echo_front: SubViewport
var _echo_back: SubViewport
var _echo_front_mat: ShaderMaterial
var _echo_back_mat: ShaderMaterial
var _echo_blank: Texture2D
var _echo_drawn := 0
var _click_uv := Vector2(-1.0, -1.0)
var _verts: PackedVector3Array
var _uvs: PackedVector2Array
var _indices: PackedInt32Array


func _ready() -> void:
	call_deferred("_boot")


func _boot() -> void:
	process_priority = 15
	_cache_mesh()
	_boot_labels()
	_boot_echo()
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/radar_hologram.gdshader")
	_material.render_priority = 16
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_surface_override_material(0, _material)
	_bind_machine_motion()
	_apply_look()


func _boot_labels() -> void:
	_label_vp = SubViewport.new()
	_label_vp.size = Vector2i(1024, 1024)
	_label_vp.transparent_bg = true
	_label_vp.disable_3d = true
	_label_vp.handle_input_locally = false
	_label_vp.gui_disable_input = true
	_label_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_label_vp)
	_label_layer = RadarAngleLabels.new()
	_label_layer.size = Vector2(1024, 1024)
	_label_vp.add_child(_label_layer)


func _bind_machine_motion() -> void:
	_machine_motion = _find_ancestor("MachineMotion") as MachineMotion
	if _machine_motion == null:
		push_warning("RadarDisplay: no MachineMotion found above this node.")
	_world = _find_ancestor("World") as World
	if _world == null:
		push_warning("RadarDisplay: no World found above this node.")


func _find_ancestor(node_name: String) -> Node:
	var node: Node = self
	while node != null:
		var found := node.get_node_or_null(node_name)
		if found != null:
			return found
		node = node.get_parent()
	return null


func _plot_rotation_degrees() -> float:
	var heading := 0.0
	if _machine_motion != null:
		heading = _machine_motion.get_heading_degrees()
	return uv_rotation_degrees - heading


func _font() -> Font:
	if angle_font != null:
		return angle_font
	return load("res://assets/fonts/Missaali-Regular.otf") as Font


func _process(delta: float) -> void:
	if _material == null:
		return
	var prev := _sweep
	var advance := delta / maxf(sweep_seconds, 0.05)
	_sweep = fmod(prev + advance, 1.0)
	_apply_look()
	_material.set_shader_parameter("sweep_angle", _sweep * TAU)
	_paint_echo(prev, _sweep, advance)


func _apply_look() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("color", color)
	_material.set_shader_parameter("line_color", line_color)
	_material.set_shader_parameter("radial_color", radial_color)
	_material.set_shader_parameter("sweep_color", sweep_color)
	_material.set_shader_parameter("label_color", label_color)
	_material.set_shader_parameter("click_color", click_color)
	_material.set_shader_parameter("mech_line", mech_line)
	_material.set_shader_parameter("emission_energy", emission_energy)
	_material.set_shader_parameter("fill_alpha", fill_alpha)
	_material.set_shader_parameter("uv_rotation", deg_to_rad(_plot_rotation_degrees()))
	_material.set_shader_parameter("ring_count", ring_count)
	_material.set_shader_parameter("ring_width", ring_width)
	_material.set_shader_parameter("outer_width", outer_width)
	_material.set_shader_parameter("radial_count", radial_count)
	_material.set_shader_parameter("radial_width", radial_width)
	_material.set_shader_parameter("sub_radial_count", sub_radial_count)
	_material.set_shader_parameter("sub_radial_width", sub_radial_width)
	_material.set_shader_parameter("sweep_width", sweep_width)
	_material.set_shader_parameter("sweep_trail", sweep_trail)
	_material.set_shader_parameter("click_uv", _click_uv)
	_material.set_shader_parameter("click_size", click_size)
	_material.set_shader_parameter("click_on", 1.0 if _click_uv.x >= 0.0 else 0.0)
	_material.set_shader_parameter("mech_size", mech_size)
	_material.set_shader_parameter("mech_fill", mech_fill)
	_material.set_shader_parameter("mech_outline_width", mech_outline_width)
	_material.set_shader_parameter("heading_mark_length", heading_mark_length)
	_material.set_shader_parameter("heading_mark_width", heading_mark_width)
	_material.set_shader_parameter("art_rotation", deg_to_rad(uv_rotation_degrees))
	_material.set_shader_parameter("mech_pos", Vector2.ZERO)
	_material.set_shader_parameter("diagram_scale", diagram_scale)
	_material.set_shader_parameter("frame_radius", frame_radius)
	_material.set_shader_parameter("frame_width", frame_width)
	_material.set_shader_parameter("crt_mix", crt_mix)
	_material.set_shader_parameter("scanline_count", scanline_count)
	_material.set_shader_parameter("scanline_strength", scanline_strength)
	_material.set_shader_parameter("scanline_sharpness", scanline_sharpness)
	_material.set_shader_parameter("grille_count", grille_count)
	_material.set_shader_parameter("grille_strength", grille_strength)
	_material.set_shader_parameter("noise_strength", noise_strength)
	_material.set_shader_parameter("flicker_strength", flicker_strength)
	_material.set_shader_parameter("flicker_speed", flicker_speed)
	_material.set_shader_parameter("vignette_strength", vignette_strength)
	_material.set_shader_parameter("vignette_power", vignette_power)
	_material.set_shader_parameter("fringe_strength", fringe_strength)
	_material.set_shader_parameter("roll_strength", roll_strength)
	_material.set_shader_parameter("roll_speed", roll_speed)
	_apply_terrain()
	if _label_vp != null:
		_material.set_shader_parameter("label_tex", _label_vp.get_texture())
	if _label_layer != null:
		_label_layer.font = _font()
		_label_layer.font_size = angle_font_size
		_label_layer.step_degrees = maxi(angle_step_degrees, 1)
		_label_layer.label_radius = label_radius
		_label_layer.uv_rotation = deg_to_rad(_plot_rotation_degrees())
		_label_layer.queue_redraw()


func _apply_terrain() -> void:
	var on := _world != null and _world.has_map()
	_material.set_shader_parameter("world_on", 1.0 if on else 0.0)
	_material.set_shader_parameter("world_range", radar_range)
	_material.set_shader_parameter("ground_color", ground_color)
	_material.set_shader_parameter("ground_fill", ground_fill)
	_material.set_shader_parameter("terrain_closed", closed_dim)
	_material.set_shader_parameter("terrain_open", open_lift)
	_material.set_shader_parameter("terrain_soft", shore_softness)
	_material.set_shader_parameter("terrain_span", World.SHORE_SPAN)
	if not on:
		return
	var origin := Vector2.ZERO
	if _machine_motion != null:
		origin = _machine_motion.get_world_position()
	_material.set_shader_parameter("world_tex", _world.get_mask_texture())
	_material.set_shader_parameter("world_size", Vector2(_world.get_pixel_size()))
	_material.set_shader_parameter("world_origin", origin)


func _boot_echo() -> void:
	var shader: Shader = load("res://shaders/radar_echo.gdshader")
	var side := clampi(echo_resolution, 32, 2048)
	_echo_front = _make_echo_viewport("RadarEchoA", side, shader)
	_echo_back = _make_echo_viewport("RadarEchoB", side, shader)
	_echo_front_mat = (_echo_front.get_child(0) as ColorRect).material as ShaderMaterial
	_echo_back_mat = (_echo_back.get_child(0) as ColorRect).material as ShaderMaterial
	var blank := Image.create(side, side, false, Image.FORMAT_RGBAH)
	blank.fill(Color(0.0, 0.0, 0.0, 1.0))
	_echo_blank = ImageTexture.create_from_image(blank)


func _make_echo_viewport(node_name: String, side: int, shader: Shader) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = node_name
	vp.size = Vector2i(side, side)
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.use_hdr_2d = true
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.name = "Plot"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(0.0, 0.0, 0.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	add_child(vp)
	vp.add_child(rect)
	rect.position = Vector2.ZERO
	rect.size = Vector2(side, side)
	return vp


## Front is the last finished scan and is what the face shows. Back copies it, writes the new wedge, then they swap.
func _paint_echo(prev: float, curr: float, advance: float) -> void:
	var painting := sweep_paints_plot and _echo_front != null and _world != null and _world.has_map()
	_material.set_shader_parameter("echo_on", 1.0 if painting else 0.0)
	if _echo_front == null:
		return
	if not painting:
		_echo_front.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_echo_back.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_push_echo(_echo_back_mat, prev, curr, advance)
	var shown: Texture2D = _echo_blank if _echo_drawn < 1 else _echo_front.get_texture()
	_echo_back_mat.set_shader_parameter("history_tex", shown)
	_echo_front.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_echo_back.render_target_update_mode = SubViewport.UPDATE_ONCE
	_material.set_shader_parameter("echo_tex", shown)
	_echo_drawn += 1
	var vp := _echo_front
	_echo_front = _echo_back
	_echo_back = vp
	var mat := _echo_front_mat
	_echo_front_mat = _echo_back_mat
	_echo_back_mat = mat


func _push_echo(mat: ShaderMaterial, prev: float, curr: float, advance: float) -> void:
	mat.set_shader_parameter("sweep_prev", prev * TAU)
	mat.set_shader_parameter("sweep_curr", curr * TAU)
	mat.set_shader_parameter("sweep_laps", advance)
	mat.set_shader_parameter("sweep_pad", 0.015)
	mat.set_shader_parameter("world_range", radar_range)
	mat.set_shader_parameter("terrain_span", World.SHORE_SPAN)
	mat.set_shader_parameter("terrain_soft", shore_softness)
	var on := _world != null and _world.has_map()
	mat.set_shader_parameter("world_on", 1.0 if on else 0.0)
	if not on:
		return
	var origin := Vector2.ZERO
	if _machine_motion != null:
		origin = _machine_motion.get_world_position()
	mat.set_shader_parameter("world_tex", _world.get_mask_texture())
	mat.set_shader_parameter("world_size", Vector2(_world.get_pixel_size()))
	mat.set_shader_parameter("world_origin", origin)


func _input(event: InputEvent) -> void:
	if _material == null or ThrottleLever.is_busy():
		return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	var uv := _pick_uv()
	if uv.x < 0.0:
		return
	_click_uv = uv
	get_viewport().set_input_as_handled()


func _cache_mesh() -> void:
	if mesh == null:
		return
	var arrays := mesh.surface_get_arrays(0)
	_verts = arrays[Mesh.ARRAY_VERTEX]
	_uvs = arrays[Mesh.ARRAY_TEX_UV]
	_indices = arrays[Mesh.ARRAY_INDEX]


func _pick_uv() -> Vector2:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _verts.is_empty() or _uvs.is_empty():
		return Vector2(-1.0, -1.0)

	var from_local := to_local(camera.global_position)
	var far_local := to_local(camera.global_position + camera.project_ray_normal(_pointer()) * pick_distance)
	var dir_local := far_local - from_local
	var max_d := dir_local.length()
	if max_d <= 0.0001:
		return Vector2(-1.0, -1.0)
	dir_local /= max_d

	var best_d := max_d
	var best_uv := Vector2(-1.0, -1.0)
	if _indices.is_empty():
		var tri_count := int(_verts.size() / 3)
		for t in tri_count:
			var i0 := t * 3
			var hit := _intersect_tri(from_local, dir_local, i0, i0 + 1, i0 + 2)
			if hit.d >= 0.0 and hit.d < best_d:
				best_d = hit.d
				best_uv = hit.uv
	else:
		var tri_count := int(_indices.size() / 3)
		for t in tri_count:
			var i := t * 3
			var hit := _intersect_tri(from_local, dir_local, _indices[i], _indices[i + 1], _indices[i + 2])
			if hit.d >= 0.0 and hit.d < best_d:
				best_d = hit.d
				best_uv = hit.uv
	return best_uv


func _intersect_tri(from_local: Vector3, dir_local: Vector3, i0: int, i1: int, i2: int) -> Dictionary:
	var a := _verts[i0]
	var b := _verts[i1]
	var c := _verts[i2]
	var point: Variant = Geometry3D.ray_intersects_triangle(from_local, dir_local, a, b, c)
	if point == null:
		return {"d": -1.0, "uv": Vector2(-1.0, -1.0)}
	var p := point as Vector3
	var d := from_local.distance_to(p)
	return {"d": d, "uv": _barycentric_uv(p, a, b, c, _uvs[i0], _uvs[i1], _uvs[i2])}


func _barycentric_uv(p: Vector3, a: Vector3, b: Vector3, c: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> Vector2:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denom := d00 * d11 - d01 * d01
	if absf(denom) < 0.0000001:
		return uv_a
	var v := (d11 * d20 - d01 * d21) / denom
	var w := (d00 * d21 - d01 * d20) / denom
	var u := 1.0 - v - w
	return uv_a * u + uv_b * v + uv_c * w


func _pointer() -> Vector2:
	if SoftwareCursor.has_instance():
		return SoftwareCursor.screen_point()
	return get_viewport().get_mouse_position()


class RadarAngleLabels extends Control:
	var font: Font
	var font_size := 28
	var step_degrees := 30
	var label_radius := 0.925
	var uv_rotation := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if font == null or size.x <= 0.0:
			return
		var step := maxi(step_degrees, 1)
		var deg := 0
		while deg < 360:
			var compass := deg_to_rad(float(deg))
			var p := Vector2(sin(compass), -cos(compass)).rotated(uv_rotation) * label_radius
			var uv := p * 0.5 + Vector2(0.5, 0.5)
			var text := Roman.to_roman(deg)
			if text.is_empty():
				text = "n"
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var ascent := font.get_ascent(font_size)
			var center := uv * size
			var spin := compass + uv_rotation
			draw_set_transform(center, spin)
			var pos := Vector2(-text_size.x * 0.5, ascent * 0.5)
			font.draw_string(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
			deg += step
		draw_set_transform(Vector2.ZERO, 0.0)

