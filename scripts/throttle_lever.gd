class_name ThrottleLever
extends MeshInstance3D

## Rest sits 1/4 of the way from back to forward, so ~3/4 of the throw is a long stride.

signal commanded_direction_changed(direction: int)

const DIR_BACK := -1
const DIR_NEUTRAL := 0
const DIR_FORWARD := 1

static var active_grab: ThrottleLever = null

@export_group("Hinge")
## Furthest back.
@export var min_angle_degrees := 102.0
## Furthest forward.
@export var max_angle_degrees := 212.0
## Where rest sits along the throw. 0.25 = short reverse, long forward (rest nearer the back stop).
@export_range(0.0, 1.0, 0.01) var rest_from_back := 0.25
## Fraction of that side's throw that still counts as neutral.
@export_range(0.0, 0.9, 0.01) var command_deadzone := 0.2

@export_group("Feel")
## Mouse pixels needed to move one degree once the lever is sliding.
@export var resistance := 10.0
@export var invert_mouse := false
## Seconds of pushing before it loosens.
@export var warmup_seconds := 0.45
## Seconds to go heavy again if you stop pushing.
@export var settle_seconds := 0.2
## How much heavier it is at rest. 1 = no extra stiction.
@export var stiction := 3.5
## Mass / coast. Higher = slower to speed up and a little slide after you ease off.
@export var inertia := 0.16

@export_group("Grab")
@export var hit_area: CollisionObject3D
@export var grab_distance := 4.0
@export_flags_3d_physics var grab_mask := 1

@export_group("Pair")
@export var paired_lever: ThrottleLever

var _angle := 0.0
var _last_direction := DIR_NEUTRAL
var _velocity := 0.0
var _grip := 0.0
var _mouse_push := 0.0
var _pair_forward_at_grab := 0.0
var _pair_back_at_grab := 0.0
var _self_forward_at_grab := 0.0
var _self_back_at_grab := 0.0
var _pair_side := 0
var _returning := false
var _return_from := 0.0
var _return_elapsed := 0.0
var _return_duration := 0.0
var _stride_lock := 0
var _ratchet_angle := 0.0
var _completing := false
var _complete_from := 0.0
var _complete_elapsed := 0.0
## While set, the hand can stay on the lever but the mouse does not move it.
var _driven := false

const COMPLETE_SECONDS := 0.45
const HOME_SECONDS := 0.4


func _ready() -> void:
	_angle = _neutral_angle()
	_apply_angle()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			if _returning or _completing:
				return
			if _is_looked_at():
				_begin_grab()
				get_viewport().set_input_as_handled()
		elif active_grab == self:
			_end_grab()
			get_viewport().set_input_as_handled()
		return

	if active_grab != self:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var raw := motion.screen_relative
		if raw == Vector2.ZERO:
			raw = motion.relative
		_mouse_push += raw.y
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _completing:
		_integrate_complete(delta)
		_mouse_push = 0.0
		return
	if _returning:
		_integrate_return(delta)
		_mouse_push = 0.0
		return
	if active_grab == self:
		_integrate_grab(delta)
		_mouse_push = 0.0
		return

	_mouse_push = 0.0
	_velocity = 0.0
	_grip = 0.0


func get_command_direction() -> int:
	var neutral := _neutral_angle()
	var offset := _angle - neutral
	if is_zero_approx(offset):
		return DIR_NEUTRAL
	var toward_forward := max_angle_degrees - neutral
	var forward := offset * toward_forward > 0.0
	var span := absf(toward_forward) if forward else absf(min_angle_degrees - neutral)
	if span <= 0.0:
		return DIR_NEUTRAL
	if absf(offset) < span * command_deadzone:
		return DIR_NEUTRAL
	if forward:
		return DIR_FORWARD
	return DIR_BACK


func get_angle_degrees() -> float:
	return _angle


func get_forward_amount() -> float:
	return _side_amount(true)


func get_back_amount() -> float:
	return _side_amount(false)


## +1 is full forward, -1 is full back, 0 is neutral. No deadzone.
func get_signed_throw() -> float:
	return _side_amount(true) - _side_amount(false)


## True when the handle is still sliding.
func is_moving() -> bool:
	return absf(_velocity) > 2.0


## The hand may stay down. Mouse motion is ignored until this is cleared.
func set_driven(on: bool) -> void:
	_driven = on


## Places the lever on the throw. Ignored while the player is holding it, unless it is driven.
func set_signed_throw(amount: float) -> void:
	if not _driven and (active_grab == self or _returning or _completing):
		return
	var t := clampf(amount, -1.0, 1.0)
	if t >= 0.0:
		_set_side_amount(true, t)
	else:
		_set_side_amount(false, -t)


func return_to_rest(duration: float) -> void:
	if active_grab == self:
		_end_grab()
	_completing = false
	_stride_lock = 0
	_returning = true
	_return_from = _angle
	_return_elapsed = 0.0
	_return_duration = maxf(duration, 0.05)
	_velocity = 0.0
	_grip = 0.0
	_mouse_push = 0.0


func is_returning() -> bool:
	return _returning


func is_completing() -> bool:
	return _completing


## Once a stride leaves neutral, the lever can only travel further that way.
func lock_stride(direction: int) -> void:
	if direction == 0 or _stride_lock != 0 or _returning or _completing:
		return
	_stride_lock = direction
	_ratchet_angle = _angle


func clear_stride_lock() -> void:
	_stride_lock = 0


static func is_busy() -> bool:
	return active_grab != null


func _integrate_return(delta: float) -> void:
	var target := _neutral_angle()
	_return_elapsed += delta
	var t := clampf(_return_elapsed / _return_duration, 0.0, 1.0)
	_angle = lerpf(_return_from, target, t)
	if t >= 1.0:
		_angle = target
		_returning = false
	_apply_angle()
	_update_direction()


func _begin_grab() -> void:
	if _returning or _completing:
		return
	if active_grab != null and active_grab != self:
		active_grab._end_grab()
	active_grab = self
	_stride_lock = 0
	_velocity = 0.0
	_grip = 0.0
	_mouse_push = 0.0
	_capture_pair_state()
	_pair_side = _active_side()


func _end_grab() -> void:
	if active_grab == self:
		active_grab = null
	_driven = false
	_stride_lock = 0
	_velocity = 0.0
	_grip = 0.0
	_mouse_push = 0.0


func _integrate_grab(delta: float) -> void:
	if _driven:
		_mouse_push = 0.0
		_velocity = 0.0
		return
	if resistance <= 0.0 or delta <= 0.0:
		return

	var push := _mouse_push
	if invert_mouse:
		push = -push

	if _stride_lock == 0 and absf(push) > 0.25:
		var toward_forward := push * _forward_sign() > 0.0
		lock_stride(DIR_FORWARD if toward_forward else DIR_BACK)

	if absf(push) > 0.25:
		_grip = minf(_grip + delta / maxf(warmup_seconds, 0.001), 1.0)
	else:
		_grip = maxf(_grip - delta / maxf(settle_seconds, 0.001), 0.0)

	var loosen := _grip * _grip
	var effective_resistance := resistance * lerpf(maxf(stiction, 1.0), 1.0, loosen)
	var impulse_rate := (push / effective_resistance) / delta

	if inertia <= 0.0:
		_velocity = impulse_rate
	else:
		var follow := 1.0 - exp(-delta / inertia)
		_velocity = lerpf(_velocity, impulse_rate, follow)

	var unclamped := _angle + _velocity * delta
	var lo := _numeric_min()
	var hi := _numeric_max()
	_angle = clampf(unclamped, lo, hi)
	if unclamped < lo or unclamped > hi:
		_velocity = 0.0
	_apply_ratchet()
	_release_lock_if_step_done()

	_apply_angle()
	_update_direction()
	_sync_paired_throw()


func _sync_paired_throw() -> void:
	pass


func _capture_pair_state() -> void:
	_self_forward_at_grab = _side_amount(true)
	_self_back_at_grab = _side_amount(false)
	if paired_lever == null:
		_pair_forward_at_grab = 0.0
		_pair_back_at_grab = 0.0
		return
	_pair_forward_at_grab = paired_lever._side_amount(true)
	_pair_back_at_grab = paired_lever._side_amount(false)


func _active_side() -> int:
	if _side_amount(true) > 0.001:
		return 1
	if _side_amount(false) > 0.001:
		return -1
	return 0


func _side_amount(forward: bool) -> float:
	var neutral := _neutral_angle()
	var end := max_angle_degrees if forward else min_angle_degrees
	var span := end - neutral
	if is_zero_approx(span):
		return 0.0
	return clampf((_angle - neutral) / span, 0.0, 1.0)


func _set_side_amount(forward: bool, amount: float) -> void:
	var neutral := _neutral_angle()
	var end := max_angle_degrees if forward else min_angle_degrees
	_angle = lerpf(neutral, end, clampf(amount, 0.0, 1.0))
	_apply_angle()
	_update_direction()


func _update_direction() -> void:
	var dir := get_command_direction()
	if dir == _last_direction:
		return
	_last_direction = dir
	commanded_direction_changed.emit(dir)


func _begin_complete() -> void:
	if _completing or _returning or _stride_lock == 0:
		return
	if active_grab == self:
		_end_grab()
	var target := max_angle_degrees if _stride_lock == DIR_FORWARD else min_angle_degrees
	if absf(_angle - target) < 1.5:
		return_to_rest(HOME_SECONDS)
		return
	_completing = true
	_complete_from = _angle
	_complete_elapsed = 0.0
	_velocity = 0.0
	_grip = 0.0
	_mouse_push = 0.0


func _integrate_complete(delta: float) -> void:
	var target := max_angle_degrees if _stride_lock == DIR_FORWARD else min_angle_degrees
	_complete_elapsed += delta
	var t := clampf(_complete_elapsed / COMPLETE_SECONDS, 0.0, 1.0)
	var s := t * t * (3.0 - 2.0 * t)
	_angle = lerpf(_complete_from, target, s)
	if t >= 1.0:
		_angle = target
		_apply_angle()
		_update_direction()
		return_to_rest(HOME_SECONDS)
		return
	_apply_angle()
	_update_direction()


func _apply_ratchet() -> void:
	if _stride_lock == 0:
		return
	var sign := _forward_sign()
	var delta := (_angle - _ratchet_angle) * sign
	if _stride_lock == DIR_FORWARD:
		if delta < 0.0:
			_angle = _ratchet_angle
			_velocity = 0.0
		else:
			_ratchet_angle = _angle
	elif delta > 0.0:
		_angle = _ratchet_angle
		_velocity = 0.0
	else:
		_ratchet_angle = _angle


func _release_lock_if_step_done() -> void:
	if _stride_lock == DIR_FORWARD and absf(_angle - max_angle_degrees) <= 0.05:
		clear_stride_lock()
	elif _stride_lock == DIR_BACK and absf(_angle - min_angle_degrees) <= 0.05:
		clear_stride_lock()


func _forward_sign() -> float:
	return signf(max_angle_degrees - _neutral_angle())


func _neutral_angle() -> float:
	return lerpf(min_angle_degrees, max_angle_degrees, 1.0 - rest_from_back)


func _numeric_min() -> float:
	return minf(min_angle_degrees, max_angle_degrees)


func _numeric_max() -> float:
	return maxf(min_angle_degrees, max_angle_degrees)


func _apply_angle() -> void:
	rotation_degrees = Vector3(0.0, _angle, 0.0)


func _is_looked_at() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false

	var from := camera.global_position
	var to := from + _pick_direction(camera) * grab_distance
	var query := PhysicsRayQueryParameters3D.create(from, to, grab_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit.get("collider") as Node
	if collider == null:
		return false
	if hit_area != null:
		return collider == hit_area or hit_area.is_ancestor_of(collider)
	return collider == self or is_ancestor_of(collider)


func _pick_direction(camera: Camera3D) -> Vector3:
	return camera.project_ray_normal(_pointer_position())


func _pointer_position() -> Vector2:
	if SoftwareCursor.has_instance():
		return SoftwareCursor.screen_point()
	return get_viewport().get_mouse_position()
