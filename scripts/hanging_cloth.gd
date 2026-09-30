class_name HangingCloth
extends Node3D

## Heavy drapery with a spring. Listens to MachineMotion; never reads the levers.
## Pushes sway into the cloth shader. Pin this node's origin on the hanging rail.
## Attach to a MeshInstance3D in the inherited cockpit, or to a pin Node3D with a child named Cloth.

const DEFAULT_MATERIAL := preload("res://shaders/hanging_cloth.tres")

@export_group("Motion")
## Multiplies every MachineMotion response. 1 is intended, 5 is obvious while dialing in.
@export var motion_scale := 1.0

@export_group("Sway")
## How hard the cloth tries to hang straight. Higher = snappier, less trail.
@export var stiffness := 2.0
## 1 = no wobble after a kick. Lower = it overshoots and rings.
@export_range(0.15, 1.2, 0.01) var damping := 1.2
## How far it trails away from a hull roll/pitch, as a fraction of that angle.
@export_range(0.0, 1.5, 0.01) var buoyancy := 0.0
## Extra lag from how fast the hull is rotating, in seconds of look-ahead.
@export var rate_lag := 1.0
## Hard cap on how far the hem can swing, in degrees.
@export var max_lean_degrees := 6.0
## Fore/aft swing as a fraction of side swing. Keep low so it does not punch a wall.
@export_range(0.0, 1.0, 0.01) var depth_scale := 0.0

@export_group("Heave")
## How much vertical hull acceleration bunches the hang.
@export var heave_amount := 0.04
## Extra side-velocity on a plant, at full slam.
@export var plant_kick := 5.5
## Extra traveling ripple on a plant, at full slam.
@export var plant_jostle := 0.12
## How much of a plant the lift-off is worth.
@export_range(0.0, 1.0, 0.01) var lift_kick := 0.28

@export_group("Idle")
## Rest ripple at the hem, in meters at full hang.
@export_range(0.0, 0.12, 0.001) var flutter := 0.031
## How much the vertical edges lag the middle.
@export_range(0.0, 0.2, 0.005) var fold := 0.145

@export_group("Gather")
## Vertical ridges across the hanging. 3 is a light drape, not a shower curtain.
@export_range(1.0, 8.0, 0.5) var pleat_count := 3.0
## How hard verts pull sideways into those ridges, as a fraction of half-width.
@export_range(0.0, 0.2, 0.005) var bunch := 0.045
## How far the ridges puff off the wall, as a fraction of width.
@export_range(0.0, 0.15, 0.005) var puff := 0.035
## Extra slack-side gather when the hem swings. 0 = even sheet.
@export_range(0.0, 1.0, 0.01) var sway_bunch := 0.28
## How differently each hanging drapes and idles. Physics stay the same.
@export_range(0.0, 1.0, 0.01) var variance := 0.55

@export_group("Mesh")
## Local hang length in meters. 0 = measure from the Cloth AABB.
@export var hang_length_override := 0.0

var _cloth: MeshInstance3D
var _material: ShaderMaterial
var _machine_motion: MachineMotion
var _hang_length := 1.0
var _hang_width := 1.0
var _pin_y := 0.0
var _sway_rot := Vector2.ZERO
var _sway_vel := Vector2.ZERO
var _heave := 0.0
var _heave_vel := 0.0
var _jostle := 0.0
var _jostle_vel := 0.0
var _jostle_phase := 0.0
var _last_lean := 0.0
var _last_pitch := 0.0
var _last_heave_v := 0.0
var _time := 0.0
var _seed := 0.0
var _have_motion_sample := false


func _ready() -> void:
	process_priority = 20
	_cloth = _find_cloth()
	if _cloth == null:
		push_warning("HangingCloth: needs a MeshInstance3D child named Cloth.")
	_strip_mesh_lods()
	_measure_cloth()
	_seed_from_place()
	call_deferred("_prepare_material")
	call_deferred("_bind_machine_motion")


func _seed_from_place() -> void:
	var p := global_position
	var name_salt := float(name.hash() % 997)
	_seed = fmod(
		absf(p.x * 12.9898 + p.y * 4.731 + p.z * 78.233 + name_salt * 0.19),
		TAU
	)
	_time = _seed * 1.7
	_jostle_phase = _seed * 0.85


func _find_cloth() -> MeshInstance3D:
	var named := get_node_or_null("Tapestry") as MeshInstance3D
	if named != null:
		return named
	for child in get_children():
		if child is MeshInstance3D:
			return child
	var attached: Node = self
	if attached is MeshInstance3D:
		return attached
	return null


func _strip_mesh_lods() -> void:
	if _cloth == null:
		return
	var src := _cloth.mesh as ArrayMesh
	if src == null:
		return
	var stripped := ArrayMesh.new()
	for surface in src.get_surface_count():
		stripped.add_surface_from_arrays(
			src.surface_get_primitive_type(surface),
			src.surface_get_arrays(surface),
			src.surface_get_blend_shape_arrays(surface),
			{}
		)
		var mat := src.surface_get_material(surface)
		if mat != null:
			stripped.surface_set_material(surface, mat)
	_cloth.mesh = stripped


func _exit_tree() -> void:
	if _machine_motion == null:
		return
	if _machine_motion.foot_planted.is_connected(_on_foot_planted):
		_machine_motion.foot_planted.disconnect(_on_foot_planted)
	if _machine_motion.foot_lifted.is_connected(_on_foot_lifted):
		_machine_motion.foot_lifted.disconnect(_on_foot_lifted)


func _bind_machine_motion() -> void:
	var node: Node = self
	while node != null:
		var found := node.get_node_or_null("MachineMotion") as MachineMotion
		if found != null:
			_machine_motion = found
			if not _machine_motion.foot_planted.is_connected(_on_foot_planted):
				_machine_motion.foot_planted.connect(_on_foot_planted)
			if not _machine_motion.foot_lifted.is_connected(_on_foot_lifted):
				_machine_motion.foot_lifted.connect(_on_foot_lifted)
			return
		node = node.get_parent()
	push_warning("HangingCloth: no MachineMotion found above this node.")


func _prepare_material() -> void:
	if _cloth == null:
		push_warning("HangingCloth: missing child MeshInstance3D named Cloth.")
		return
	var active := _cloth.get_active_material(0)
	var source := active as ShaderMaterial
	if source == null:
		source = DEFAULT_MATERIAL
	_material = source.duplicate() as ShaderMaterial
	_cloth.set_surface_override_material(0, _material)
	_cloth.extra_cull_margin = maxf(_cloth.extra_cull_margin, _hang_length * 0.4)
	_push_static_params()


func _measure_cloth() -> void:
	if _cloth == null or _cloth.mesh == null:
		return
	var aabb := _cloth.get_aabb()
	_hang_width = maxf(aabb.size.x, 0.05)
	_pin_y = aabb.position.y + aabb.size.y
	if hang_length_override > 0.0:
		_hang_length = hang_length_override
	else:
		_hang_length = maxf(aabb.size.y, 0.05)


func _process(delta: float) -> void:
	_time += delta
	var hull_lean := 0.0
	var hull_pitch := 0.0
	var heave_v := 0.0
	var shake_rot := Vector3.ZERO
	var gain := motion_scale
	if _machine_motion != null:
		hull_lean = _machine_motion.get_lean() * gain
		hull_pitch = _machine_motion.get_pitch() * gain
		heave_v = _machine_motion.get_heave_velocity() * gain
		shake_rot = _machine_motion.get_shake_rotation() * gain

	var lean_rate := 0.0
	var pitch_rate := 0.0
	var heave_acc := 0.0
	if _have_motion_sample and delta > 0.0:
		lean_rate = (hull_lean - _last_lean) / delta
		pitch_rate = (hull_pitch - _last_pitch) / delta
		heave_acc = clampf((heave_v - _last_heave_v) / delta, -12.0 * gain, 12.0 * gain)
	_last_lean = hull_lean
	_last_pitch = hull_pitch
	_last_heave_v = heave_v
	_have_motion_sample = true

	var target := Vector2(
		(-hull_pitch * buoyancy - pitch_rate * rate_lag) * depth_scale,
		-hull_lean * buoyancy - lean_rate * rate_lag
	)
	target += Vector2(shake_rot.x * depth_scale, shake_rot.z) * 0.4
	_step_spring(delta, target, heave_acc)
	_push_pose()


func _on_foot_planted(side: int, intensity: float, _forward: bool) -> void:
	var gain := motion_scale
	_sway_vel.y += float(side) * intensity * plant_kick * gain
	_jostle_vel += intensity * plant_jostle * gain


func _on_foot_lifted(side: int, _forward: bool) -> void:
	var gain := motion_scale
	_sway_vel.y -= float(side) * lift_kick * plant_kick * gain
	_jostle_vel += lift_kick * plant_jostle * gain


func _step_spring(delta: float, target: Vector2, heave_acc: float) -> void:
	var omega := maxf(stiffness, 0.01)
	var zeta := damping
	var sway_acc := (
		-omega * omega * (_sway_rot - target)
		- 2.0 * zeta * omega * _sway_vel
	)
	_sway_vel += sway_acc * delta
	_sway_rot += _sway_vel * delta
	var cap := maxf(motion_scale, 0.0)
	var max_lean := deg_to_rad(max_lean_degrees) * cap
	var lean_len := _sway_rot.length()
	if lean_len > max_lean and lean_len > 0.0:
		_sway_rot *= max_lean / lean_len
		_sway_vel *= 0.45

	var heave_target := clampf(-heave_acc * heave_amount, -0.22 * cap, 0.22 * cap)
	var heave_acc_spring := (
		-omega * omega * (_heave - heave_target)
		- 2.0 * zeta * omega * _heave_vel
	)
	_heave_vel += heave_acc_spring * delta
	_heave = clampf(_heave + _heave_vel * delta, -0.28 * cap, 0.28 * cap)

	var jostle_acc := (
		-omega * omega * 0.55 * _jostle
		- 2.0 * 0.35 * omega * _jostle_vel
	)
	_jostle_vel += jostle_acc * delta
	_jostle = clampf(_jostle + _jostle_vel * delta, 0.0, 0.55 * cap)
	_jostle_phase += (2.8 + _jostle * 6.0) * delta


func _hash01(salt: float) -> float:
	var x := sin(_seed * 12.9898 + salt) * 43758.5453
	return x - floor(x)


func _vary(base: float, salt: float, amount: float) -> float:
	return base * (1.0 + (_hash01(salt) - 0.5) * 2.0 * amount * variance)


func _push_drape_params() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("flutter", _vary(flutter, 1.7, 0.18))
	_material.set_shader_parameter("fold", _vary(fold, 3.2, 0.22))
	_material.set_shader_parameter("pleat_count", pleat_count + (_hash01(4.8) - 0.5) * 0.9 * variance)
	_material.set_shader_parameter("bunch", _vary(bunch, 6.1, 0.28))
	_material.set_shader_parameter("puff", _vary(puff, 8.4, 0.28))
	_material.set_shader_parameter("sway_bunch", _vary(sway_bunch, 9.9, 0.2))


func _push_static_params() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("hang_length", _hang_length)
	_material.set_shader_parameter("hang_width", _hang_width)
	_material.set_shader_parameter("pin_y", _pin_y)
	_material.set_shader_parameter("cloth_seed", _seed)
	_push_drape_params()


func _push_pose() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("sway", _sway_rot)
	_material.set_shader_parameter("heave", _heave)
	_material.set_shader_parameter("jostle", _jostle)
	_material.set_shader_parameter("jostle_phase", _jostle_phase)
	_material.set_shader_parameter("cloth_time", _time)
	_push_drape_params()
