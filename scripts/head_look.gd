class_name HeadLook
extends Camera3D

## Visible software cursor drives look. Screen center is rest. Edges are max head turn.

@export_group("Head turn")
## How far the head turns with the cursor at the left or right edge of the window.
@export var max_left_right := 18.0
## How far the head turns with the cursor at the top of the window.
@export var max_up := 8.0
## How far the head turns with the cursor at the bottom of the window.
@export var max_down := 10.0
## How quickly the head catches up to the pointer. Higher is snappier.
@export var smoothing := 14.0

@export_group("Cursor")
@export var invert_y := false
@export var look_while_grabbing := false

var _rest_rotation := Vector3.ZERO
var _rest_position := Vector3.ZERO
var _machine_motion: MachineMotion
var _yaw := 0.0
var _pitch := 0.0
var _target_yaw := 0.0
var _target_pitch := 0.0


func _ready() -> void:
	_rest_rotation = rotation
	_rest_position = position
	process_priority = 20
	make_current()
	call_deferred("_bind_machine_motion")


func _bind_machine_motion() -> void:
	var parent := get_parent()
	if parent == null:
		return
	_machine_motion = parent.get_node_or_null("MachineMotion") as MachineMotion


func _process(delta: float) -> void:
	if look_while_grabbing or not ThrottleLever.is_busy():
		_update_look_target()
	_apply_look(delta)


func _update_look_target() -> void:
	var n := _cursor_from_center()
	if invert_y:
		n.y = -n.y
	_target_yaw = -n.x * deg_to_rad(max_left_right)
	if n.y >= 0.0:
		_target_pitch = -n.y * deg_to_rad(max_down)
	else:
		_target_pitch = -n.y * deg_to_rad(max_up)


func _pointer_position() -> Vector2:
	if SoftwareCursor.has_instance():
		return SoftwareCursor.screen_point()
	return get_viewport().get_mouse_position()


func _cursor_from_center() -> Vector2:
	var viewport_size := Vector2(get_viewport().get_visible_rect().size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2.ZERO
	var n := (_pointer_position() / viewport_size) * 2.0 - Vector2.ONE
	return Vector2(clampf(n.x, -1.0, 1.0), clampf(n.y, -1.0, 1.0))


func _apply_look(delta: float) -> void:
	if smoothing <= 0.0:
		_yaw = _target_yaw
		_pitch = _target_pitch
	else:
		var weight := 1.0 - exp(-smoothing * delta)
		_yaw = lerp(_yaw, _target_yaw, weight)
		_pitch = lerp(_pitch, _target_pitch, weight)

	var body_pitch := 0.0
	var body_lean := 0.0
	var body_height := 0.0
	var knock := Vector3.ZERO
	var knock_rot := Vector3.ZERO
	var vibe := Vector3.ZERO
	var vibe_rot := Vector3.ZERO
	if _machine_motion != null:
		body_pitch = _machine_motion.get_pitch()
		body_lean = _machine_motion.get_lean()
		body_height = _machine_motion.get_height()
		knock = _machine_motion.get_knock_offset()
		knock_rot = _machine_motion.get_knock_rotation()
		vibe = _machine_motion.get_shake_offset()
		vibe_rot = _machine_motion.get_shake_rotation()

	rotation = Vector3(
		_rest_rotation.x + _pitch + body_pitch + knock_rot.x + vibe_rot.x,
		_rest_rotation.y + _yaw + knock_rot.y + vibe_rot.y,
		_rest_rotation.z + body_lean + knock_rot.z + vibe_rot.z
	)
	position = _rest_position + Vector3(
		knock.x + vibe.x,
		body_height + knock.y + vibe.y,
		knock.z + vibe.z
	)
