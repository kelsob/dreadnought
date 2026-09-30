class_name MachineMotion
extends Node

## Reads the two throttles and publishes hull motion + plant hits.
## Camera, candles, cloth should listen to this instead of the levers.

signal foot_lifted(side: int, forward: bool)
signal foot_planted(side: int, intensity: float, forward: bool)

const SIDE_NONE := 0
const SIDE_LEFT := -1
const SIDE_RIGHT := 1

const REVERSE_SCALE := 0.35
const TURN_HEAVE := 0.22
const TURN_LEAN := 0.7
const PLANT_AT := 0.9
const LIFT_AT := 0.08
const COMMIT_AT := 0.2
const STALL_SPEED := 0.18
const STALL_SECONDS := 0.1
const PLANT_FORCE := 0.88
const SLAM_SPEED := 2.4
const LIFT_HIT := 0.22
const SHAKE_DECAY := 8.5
const KNOCK_HOLD := 0.12
const KNOCK_RECOVER := 0.5
const KNOCK_CATCH := 0.045
const KNOCK_SURGE := 0.38
const KNOCK_DROP := 0.24
const KNOCK_ROLL := 45.0
const KNOCK_YAW := 25.0
const KNOCK_PITCH := 21.0
const LAND_SECONDS := 0.16

@export_group("Stride")
## How high the hull lifts at mid-stride, in meters.
@export var step_height := 0.14
## How far the hull rolls toward the planted leg, in degrees.
@export var lean := 5.5
@export var invert_lean := false
## How far the nose pitches up at mid-stride, in degrees.
@export var pitch := 8.0

@export_group("Weight")
## Seconds the legs and hull trail the levers. Higher = heavier.
@export var lag := 0.2

@export_group("Plant")
## How far the hull drops when a foot lands, in meters.
@export var drop := 0.25
## How far a plant throws your head off-center, in meters. Away from that foot.
@export var knock := 0.042
## Up-down rattle on top of the knock, in meters.
@export var shake := 0.048

@export_group("Heading")
## How long the lever must stay held after the foot lands before the machine turns.
@export var turn_hold := 0.5
## Seconds the machine takes to turn. The levers come back with it, over this same time.
@export var turn_duration := 4.4
## Flip if a forward step turns the wrong way.
@export var invert_turn := false
## How far one foot travels on a full throw.
## The hull is the midpoint, so one foot alone carries the center half this far.
@export var step_length := 1.0
## Distance between the feet, across the hull.
@export var leg_spacing := 1.0

var _height := 0.0
var _lean := 0.0
var _pitch := 0.0
var _height_punch := 0.0
var _height_punch_vel := 0.0
var _knock_pos := Vector3.ZERO
var _knock_rot := Vector3.ZERO
var _knock_pos_target := Vector3.ZERO
var _knock_rot_target := Vector3.ZERO
var _knock_hold_left := 0.0
var _rumble := 0.0
var _heave_velocity := 0.0
var _progress := 0.0
var _last_progress := 0.0
var _swing_side := SIDE_NONE
var _last_swing_side := SIDE_NONE
var _swing_forward := true
var _lifted := false
var _planted := true
var _turning := false
var _rumble_time := 0.0
var _rumble_phase := 0.0
var _impact_side := SIDE_NONE
var _clock := 0.0
var _peak_throw := 0.0
var _last_command := 0.0
var _stall_time := 0.0
var _hist_time: Array[float] = []
var _hist_progress: Array[float] = []
var _cockpit: Cockpit
var _world: World
var _left_lever: ThrottleLever
var _right_lever: ThrottleLever
var _heading := 0.0
var _world_position := Vector2.ZERO
var _left_home := Vector2.ZERO
var _right_home := Vector2.ZERO
var _left_foot := Vector2.ZERO
var _right_foot := Vector2.ZERO
var _left_lock := 0
var _right_lock := 0
var _left_latched := false
var _right_latched := false
var _left_aim := Vector2.ZERO
var _right_aim := Vector2.ZERO
var _turn_left_from := Vector2.ZERO
var _turn_right_from := Vector2.ZERO
var _turn_center := Vector2.ZERO
var _step_side := 0
var _step_forward := Vector2.ZERO
var _step_throw := 0.0
var _step_foot := Vector2.ZERO
var _heading_busy := false
var _turn_t := -1.0
var _heading_from := 0.0
var _heading_to := 0.0
var _turn_lever: ThrottleLever = null
var _step_landed := false
var _step_was_moving := false
var _turn_skipped := false
var _hold_time := 0.0
var _foot_down := false
var _settling := false
var _settle_from := 0.0
var _settle_elapsed := 0.0


func _ready() -> void:
	process_priority = 10
	_apply_world_start()
	call_deferred("_bind_cockpit")


func _bind_cockpit() -> void:
	var parent := get_parent()
	if parent == null:
		push_error("MachineMotion: needs a parent scene with a Cockpit child.")
		return
	_cockpit = parent.get_node_or_null("Cockpit") as Cockpit
	if _cockpit == null:
		push_error("MachineMotion: no sibling named Cockpit with cockpit.gd attached.")
		return
	_left_lever = _cockpit.left_throttle
	_right_lever = _cockpit.right_throttle
	_bind_world()


func _bind_world() -> void:
	var parent := get_parent()
	if parent == null:
		return
	_world = parent.get_node_or_null("World") as World
	if _world == null:
		push_warning("MachineMotion: no sibling named World. The hull can walk anywhere.")
		return
	_apply_world_start()


func _apply_world_start() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var world := parent.get_node_or_null("World") as World
	if world == null:
		return
	_world = world
	_heading = world.get_start_heading_degrees()
	_world_position = world.get_start_position()
	_seat_feet(_world_position, _heading)


func _process(delta: float) -> void:
	if _left_lever == null or _right_lever == null:
		return
	var previous_height := _height
	_update_gait(delta)
	_update_heading_turn(delta)
	_update_feet(delta)
	_heave_velocity = (_height - previous_height) / maxf(delta, 0.0001)


func get_height() -> float:
	return _height + _height_punch


func get_lean() -> float:
	return _lean


func get_pitch() -> float:
	return _pitch


func get_heave_velocity() -> float:
	return _heave_velocity


func get_knock_offset() -> Vector3:
	return _knock_pos


func get_knock_rotation() -> Vector3:
	return _knock_rot


func get_shake_offset() -> Vector3:
	return _rumble_offset()


func get_shake_rotation() -> Vector3:
	var rumble := _rumble_offset()
	return Vector3(rumble.y * 1.4, rumble.x * 0.35, rumble.x * 0.25)


func get_step_progress() -> float:
	return _progress


func get_swing_side() -> int:
	return _swing_side


func is_turning() -> bool:
	return _turning


func get_heading_degrees() -> float:
	return _heading


func get_world_position() -> Vector2:
	return _world_position


func get_forward_vector() -> Vector2:
	var rad := deg_to_rad(_heading)
	return Vector2(sin(rad), cos(rad))


func get_right_vector() -> Vector2:
	var fwd := get_forward_vector()
	return Vector2(fwd.y, -fwd.x)


func _update_feet(delta: float) -> void:
	if _heading_busy:
		_place_feet_for_turn()
		_drive_levers_from_feet()
		return
	var grabbed := ThrottleLever.active_grab
	var side := SIDE_NONE
	if grabbed == _left_lever:
		side = SIDE_LEFT
	elif grabbed == _right_lever:
		side = SIDE_RIGHT
	if side == SIDE_NONE:
		if _step_side != SIDE_NONE and not _step_landed:
			_commit_step()
		_step_side = SIDE_NONE
		_hold_time = 0.0
		_world_position = (_left_foot + _right_foot) * 0.5
		return
	if side != _step_side:
		_begin_step(side, grabbed)
	if _step_landed:
		_world_position = (_left_foot + _right_foot) * 0.5
		if _turn_skipped:
			return
		_hold_time += delta
		if _hold_time >= turn_hold:
			_begin_heading_turn(grabbed)
		return
	_slide_step(side, grabbed)
	_mirror_other_lever(side, grabbed)
	_world_position = (_left_foot + _right_foot) * 0.5
	if _step_should_land(grabbed):
		_commit_step()


## The foot slides straight along the facing from when the lever was grabbed.
## The nose stays put until a held plant turns it.
func _begin_step(side: int, lever: ThrottleLever) -> void:
	_step_side = side
	_step_landed = false
	_step_was_moving = false
	_turn_skipped = false
	_hold_time = 0.0
	_step_forward = get_forward_vector()
	_step_throw = lever.get_signed_throw()
	_step_foot = _left_foot if side == SIDE_LEFT else _right_foot


func _step_should_land(lever: ThrottleLever) -> bool:
	if absf(lever.get_signed_throw() - _step_throw) < 0.02:
		return false
	if absf(lever.get_signed_throw()) >= 0.98:
		return true
	if lever.is_moving():
		_step_was_moving = true
		return false
	return _step_was_moving


func _commit_step() -> void:
	if _step_landed or _step_side == SIDE_NONE:
		return
	var lever := _lever_for(_step_side)
	var moved := 0.0
	if lever != null:
		moved = absf(lever.get_signed_throw() - _step_throw)
	_step_landed = true
	_hold_time = 0.0
	_world_position = (_left_foot + _right_foot) * 0.5
	if moved < 0.02:
		_turn_skipped = true
		return
	if lever != null and ThrottleLever.active_grab == lever:
		lever.set_driven(true)
	var forward := true
	if lever != null:
		forward = lever.get_signed_throw() >= _step_throw
	var intensity := _plant_force(moved, 0.0) * clampf(moved, 0.0, 1.0)
	_planted = true
	_apply_impact(_step_side, intensity, forward, true)
	foot_planted.emit(_step_side, intensity, forward)


func _mirror_other_lever(side: int, grabbed: ThrottleLever) -> void:
	var other := _right_lever if side == SIDE_LEFT else _left_lever
	if other == null:
		return
	other.set_signed_throw(-grabbed.get_signed_throw())


func _slide_step(side: int, lever: ThrottleLever) -> void:
	var delta := (lever.get_signed_throw() - _step_throw) * step_length
	var requested := _step_foot + _step_forward * delta
	var current := _left_foot if side == SIDE_LEFT else _right_foot
	_set_foot(side, _clamp_travel(current, requested))


func _facing_from_feet() -> float:
	var line := _right_foot - _left_foot
	if line.length_squared() < 0.0001:
		return _heading
	line = line.normalized()
	# Forward sits across the foot line, left foot on the left.
	var fwd := Vector2(-line.y, line.x)
	return rad_to_deg(atan2(fwd.x, fwd.y))


func _apply_heading_from_feet() -> void:
	_heading = _facing_from_feet()


func _place_feet_for_turn() -> void:
	var t := clampf(_turn_t, 0.0, 1.0)
	var abreast := _abreast(_turn_center, _heading)
	_left_foot = _turn_left_from.lerp(abreast[0], t)
	_right_foot = _turn_right_from.lerp(abreast[1], t)
	_world_position = _turn_center


func _throw_for_foot(foot: Vector2) -> float:
	var along := (foot - _world_position).dot(get_forward_vector())
	return clampf(along / maxf(step_length * 0.5, 0.001), -1.0, 1.0)


func _drive_levers_from_feet() -> void:
	if _left_lever != null:
		_left_lever.set_driven(true)
		_left_lever.set_signed_throw(_throw_for_foot(_left_foot))
	if _right_lever != null:
		_right_lever.set_driven(true)
		_right_lever.set_signed_throw(_throw_for_foot(_right_foot))


func _release_levers() -> void:
	if _left_lever != null:
		_left_lever.set_driven(false)
		_left_lever.clear_stride_lock()
	if _right_lever != null:
		_right_lever.set_driven(false)
		_right_lever.clear_stride_lock()


func _drive_foot(side: int, lever: ThrottleLever) -> void:
	if lever == null:
		return
	var latched := _is_latched(side)
	if lever.is_returning():
		if not latched:
			_set_foot(side, _foot_target(side, lever))
			_latch_foot(side)
		else:
			_set_foot(side, _home_for(side))
		return
	if latched:
		_set_foot(side, _home_for(side))
		if lever.get_command_direction() == ThrottleLever.DIR_NEUTRAL and not lever.is_completing():
			_set_latched(side, false)
			_set_lock(side, 0)
			lever.clear_stride_lock()
		return
	var lock := _lock_for(side)
	if lock == 0:
		var dir := lever.get_command_direction()
		if dir == ThrottleLever.DIR_NEUTRAL:
			_set_foot(side, _home_for(side))
			return
		_set_lock(side, dir)
		_set_aim(side, get_forward_vector())
		lever.lock_stride(dir)
		lock = dir
	var amount := lever.get_forward_amount() if lock == ThrottleLever.DIR_FORWARD else lever.get_back_amount()
	var along := 1.0 if lock == ThrottleLever.DIR_FORWARD else -1.0
	_set_foot(side, _clamp_travel(_home_for(side), _home_for(side) + _aim_for(side) * along * step_length * amount))


func _foot_target(side: int, lever: ThrottleLever) -> Vector2:
	var lock := _lock_for(side)
	if lock == 0:
		return _home_for(side)
	var amount := lever.get_forward_amount() if lock == ThrottleLever.DIR_FORWARD else lever.get_back_amount()
	var along := 1.0 if lock == ThrottleLever.DIR_FORWARD else -1.0
	return _clamp_travel(_home_for(side), _home_for(side) + _aim_for(side) * along * step_length * amount)


func _latch_foot(side: int) -> void:
	if _is_latched(side):
		return
	if side == SIDE_LEFT:
		_left_home = _left_foot
		_left_latched = true
	else:
		_right_home = _right_foot
		_right_latched = true


func _seat_feet(center: Vector2, heading: float) -> void:
	var abreast := _abreast(center, heading)
	_world_position = center
	_left_home = abreast[0]
	_right_home = abreast[1]
	_left_foot = _left_home
	_right_foot = _right_home
	_apply_heading_from_feet()


func _abreast(center: Vector2, heading: float) -> Array[Vector2]:
	var rad := deg_to_rad(heading)
	var fwd := Vector2(sin(rad), cos(rad))
	var right := Vector2(fwd.y, -fwd.x) * leg_spacing * 0.5
	var pair: Array[Vector2] = [center - right, center + right]
	return pair


func _clamp_travel(from_pos: Vector2, to_pos: Vector2) -> Vector2:
	if _world == null or _world.accepts_step(from_pos, to_pos):
		return to_pos
	var lo := 0.0
	var hi := 1.0
	for _i in 8:
		var mid := (lo + hi) * 0.5
		if _world.accepts_step(from_pos, from_pos.lerp(to_pos, mid)):
			lo = mid
		else:
			hi = mid
	return from_pos.lerp(to_pos, lo)


func _home_for(side: int) -> Vector2:
	return _left_home if side == SIDE_LEFT else _right_home


func _aim_for(side: int) -> Vector2:
	return _left_aim if side == SIDE_LEFT else _right_aim


func _lock_for(side: int) -> int:
	return _left_lock if side == SIDE_LEFT else _right_lock


func _is_latched(side: int) -> bool:
	return _left_latched if side == SIDE_LEFT else _right_latched


func _set_foot(side: int, pos: Vector2) -> void:
	if side == SIDE_LEFT:
		_left_foot = pos
	else:
		_right_foot = pos


func _set_lock(side: int, lock: int) -> void:
	if side == SIDE_LEFT:
		_left_lock = lock
	else:
		_right_lock = lock


func _set_aim(side: int, aim: Vector2) -> void:
	if side == SIDE_LEFT:
		_left_aim = aim
	else:
		_right_aim = aim


func _set_latched(side: int, latched: bool) -> void:
	if side == SIDE_LEFT:
		_left_latched = latched
	else:
		_right_latched = latched


func _lever_for(side: int) -> ThrottleLever:
	if side == SIDE_LEFT:
		return _left_lever
	if side == SIDE_RIGHT:
		return _right_lever
	return null


func _plant_force(throw: float, speed: float) -> float:
	var u := clampf((throw - COMMIT_AT) / maxf(1.0 - COMMIT_AT, 0.001), 0.0, 1.0)
	var force := lerpf(PLANT_FORCE, 1.0, u)
	force = lerpf(force, 1.0, clampf(speed / SLAM_SPEED, 0.0, 1.0) * 0.08)
	return clampf(force, PLANT_FORCE, 1.0)


func _land_foot(swing_forward: bool, intensity: float, from_progress: float) -> void:
	if _planted:
		return
	_plant_foot(swing_forward, intensity)
	_foot_down = true
	if from_progress < 0.97:
		_settling = true
		_settle_from = from_progress
		_settle_elapsed = 0.0


func _plant_foot(swing_forward: bool, intensity: float) -> void:
	_planted = true
	_apply_impact(_swing_side, intensity, swing_forward, true)
	foot_planted.emit(_swing_side, intensity, swing_forward)


func _begin_heading_turn(lever: ThrottleLever) -> void:
	if _left_lever == null or _right_lever == null:
		return
	var delta := wrapf(_facing_from_feet() - _heading, -180.0, 180.0)
	if invert_turn:
		delta = -delta
	if absf(delta) < 0.05:
		_turn_skipped = true
		return
	_turn_lever = lever
	_turn_left_from = _left_foot
	_turn_right_from = _right_foot
	_turn_center = (_left_foot + _right_foot) * 0.5
	_world_position = _turn_center
	_heading_from = _heading
	_heading_to = _heading_from + delta
	_heading_busy = true
	_turn_t = 0.0


func _turn_still_held() -> bool:
	return _turn_lever != null and ThrottleLever.active_grab == _turn_lever


func _stop_heading_turn() -> void:
	_heading_busy = false
	_turn_t = -1.0
	_turn_lever = null
	_turn_skipped = true
	_step_side = SIDE_NONE
	_world_position = (_left_foot + _right_foot) * 0.5
	_drive_levers_from_feet()
	_release_levers()


func _finish_heading_turn() -> void:
	_heading = wrapf(_heading_to, -180.0, 180.0)
	_heading_busy = false
	_turn_t = -1.0
	_turn_lever = null
	_turn_skipped = true
	_step_landed = false
	_step_side = SIDE_NONE
	_hold_time = 0.0
	_seat_feet(_turn_center, _heading)
	_left_latched = false
	_right_latched = false
	_left_lock = 0
	_right_lock = 0
	_drive_levers_from_feet()
	_release_levers()


func _update_heading_turn(delta: float) -> void:
	if not _heading_busy:
		return
	if not _turn_still_held():
		_stop_heading_turn()
		return
	_turn_t += delta / maxf(turn_duration, 0.05)
	var t := clampf(_turn_t, 0.0, 1.0)
	_heading = lerpf(_heading_from, _heading_to, t)
	if _turn_t >= 1.0:
		_finish_heading_turn()


func _update_gait(delta: float) -> void:
	var left_forward := _left_lever.get_forward_amount()
	var left_back := _left_lever.get_back_amount()
	var right_forward := _right_lever.get_forward_amount()
	var right_back := _right_lever.get_back_amount()
	var left_mag := maxf(left_forward, left_back)
	var right_mag := maxf(right_forward, right_back)

	# Opposite throws are a stride now: one foot ahead, the other behind center.
	_turning = false

	_swing_side = _pick_swing_side(left_mag, right_mag)
	if _swing_side != _last_swing_side:
		_peak_throw = 0.0
		_stall_time = 0.0
		_last_command = 0.0
	var swing_forward := true
	var command_progress := 0.0
	if _swing_side == SIDE_LEFT:
		swing_forward = left_forward >= left_back
		command_progress = left_mag
	elif _swing_side == SIDE_RIGHT:
		swing_forward = right_forward >= right_back
		command_progress = right_mag

	_clock += delta
	_peak_throw = maxf(_peak_throw, command_progress)
	if command_progress < LIFT_AT * 0.5:
		_peak_throw = command_progress

	var command_speed := (command_progress - _last_command) / maxf(delta, 0.0001)
	if _lifted and not _planted and command_progress >= COMMIT_AT and command_speed <= STALL_SPEED:
		_stall_time += delta
	else:
		_stall_time = 0.0
	_last_command = command_progress

	var stride := 1.0 if swing_forward else REVERSE_SCALE
	if _turning:
		stride *= TURN_HEAVE

	var progress := _push_and_sample_progress(command_progress, lag)
	var pose := progress
	if _settling:
		_settle_elapsed += delta
		var u := clampf(_settle_elapsed / LAND_SECONDS, 0.0, 1.0)
		pose = lerpf(_settle_from, 1.0, u)
		if u >= 1.0:
			_settling = false
	elif _foot_down:
		pose = 1.0
	_progress = pose
	_swing_forward = swing_forward

	var cycle := sin(pose * PI)
	var height_target := cycle * step_height * stride
	var lean_sign := float(-_swing_side) if _swing_side != SIDE_NONE else 0.0
	if invert_lean:
		lean_sign = -lean_sign
	var lean_target := deg_to_rad(lean) * cycle * lean_sign * stride
	if _turning:
		lean_target *= TURN_LEAN
	var pitch_target := deg_to_rad(pitch) * cycle * stride

	var hull_follow := 1.0
	if lag > 0.0:
		hull_follow = 1.0 - exp(-delta / lag)
	_height = lerpf(_height, height_target, hull_follow)
	_lean = lerpf(_lean, lean_target, hull_follow)
	_pitch = lerpf(_pitch, pitch_target, hull_follow)

	_step_impact(delta)
	_emit_step_events(progress, swing_forward, delta)
	_last_progress = progress
	_last_swing_side = _swing_side


func _pick_swing_side(left_mag: float, right_mag: float) -> int:
	var grabbed := ThrottleLever.active_grab
	if grabbed == _left_lever:
		return SIDE_LEFT
	if grabbed == _right_lever:
		return SIDE_RIGHT
	if left_mag > right_mag + 0.02:
		return SIDE_LEFT
	if right_mag > left_mag + 0.02:
		return SIDE_RIGHT
	if left_mag < LIFT_AT and right_mag < LIFT_AT:
		return SIDE_NONE
	return _last_swing_side


func _emit_step_events(progress: float, swing_forward: bool, _delta: float) -> void:
	if _swing_side == SIDE_NONE:
		_lifted = false
		_planted = true
		return

	if not _lifted and progress >= LIFT_AT and not _step_landed:
		_lifted = true
		_planted = false
		var lift_intensity := clampf(_peak_throw, 0.2, 1.0) * LIFT_HIT
		_apply_impact(_swing_side, lift_intensity, swing_forward, false)
		foot_lifted.emit(_swing_side, swing_forward)

	if progress < LIFT_AT * 0.5 and not _step_landed:
		_lifted = false
		_planted = true
		_foot_down = false
		_settling = false
		_stall_time = 0.0


func _apply_impact(side: int, intensity: float, forward: bool, is_plant: bool) -> void:
	if side == SIDE_NONE or intensity <= 0.0:
		return

	_impact_side = side
	var side_sign := float(side)
	if invert_lean:
		side_sign = -side_sign
	var stride_sign := 1.0 if forward else -1.0
	var yaw_scale := 1.55 if _turning else 1.0
	var shove := knock * intensity

	if is_plant:
		_knock_pos_target = Vector3(
			-side_sign * shove,
			-shove * KNOCK_DROP,
			-stride_sign * shove * KNOCK_SURGE
		)
		_knock_rot_target = Vector3(
			-stride_sign * deg_to_rad(KNOCK_PITCH * shove),
			side_sign * deg_to_rad(KNOCK_YAW * shove) * yaw_scale,
			-side_sign * deg_to_rad(KNOCK_ROLL * shove)
		)
		_knock_hold_left = KNOCK_HOLD
		_height_punch -= drop * intensity * 0.4
		_height_punch_vel -= drop * intensity * 5.5
		_rumble = shake * intensity
		_rumble_time = 0.0
		_rumble_phase = 0.0 if side == SIDE_LEFT else 0.73
	else:
		_knock_pos_target = Vector3(
			side_sign * shove * 0.45,
			shove * KNOCK_DROP * 0.6,
			0.0
		)
		_knock_rot_target = Vector3(
			0.0,
			0.0,
			side_sign * deg_to_rad(KNOCK_ROLL * shove)
		)
		_knock_hold_left = KNOCK_HOLD * 0.45
		_height_punch_vel += drop * intensity * 2.4
		_rumble = shake * intensity * 0.35
		_rumble_time = 0.0
		_rumble_phase = 0.4 if side == SIDE_LEFT else 1.1


func _step_impact(delta: float) -> void:
	if _knock_hold_left > 0.0:
		_knock_hold_left = maxf(_knock_hold_left - delta, 0.0)
	else:
		var recover := 1.0 - exp(-delta / KNOCK_RECOVER)
		_knock_pos_target = _knock_pos_target.lerp(Vector3.ZERO, recover)
		_knock_rot_target = _knock_rot_target.lerp(Vector3.ZERO, recover)

	var catch := 1.0 - exp(-delta / KNOCK_CATCH)
	_knock_pos = _knock_pos.lerp(_knock_pos_target, catch)
	_knock_rot = _knock_rot.lerp(_knock_rot_target, catch)

	var punch_omega := 16.5
	var punch_zeta := 0.58
	var punch_acc := (
		-punch_omega * punch_omega * _height_punch
		- 2.0 * punch_zeta * punch_omega * _height_punch_vel
	)
	_height_punch_vel += punch_acc * delta
	_height_punch += _height_punch_vel * delta

	_rumble = move_toward(_rumble, 0.0, SHAKE_DECAY * delta * maxf(_rumble, 0.008))
	_rumble_time += delta


func _rumble_offset() -> Vector3:
	if _rumble <= 0.001:
		return Vector3.ZERO
	var left := _impact_side == SIDE_LEFT
	var fy := 7.2 if left else 8.1
	var fx := 11.4 if left else 10.2
	var fz := 9.3 if left else 10.6
	var t := _rumble_time
	var phase := _rumble_phase
	return Vector3(
		sin(t * fx + phase) * _rumble * 0.16,
		sin(t * fy + phase * 1.3) * _rumble,
		sin(t * fz + phase * 0.5) * _rumble * 0.12
	)


func _push_and_sample_progress(command_progress: float, delay: float) -> float:
	_hist_time.append(_clock)
	_hist_progress.append(command_progress)
	var keep_after := _clock - delay - 0.25
	while _hist_time.size() > 1 and _hist_time[0] < keep_after:
		_hist_time.remove_at(0)
		_hist_progress.remove_at(0)
	if delay <= 0.0 or _hist_time.is_empty():
		return command_progress
	var target_time := _clock - delay
	if target_time <= _hist_time[0]:
		return _hist_progress[0]
	for i in range(1, _hist_time.size()):
		if _hist_time[i] >= target_time:
			var span := _hist_time[i] - _hist_time[i - 1]
			if span <= 0.0:
				return _hist_progress[i]
			var t := (target_time - _hist_time[i - 1]) / span
			return lerpf(_hist_progress[i - 1], _hist_progress[i], t)
	return _hist_progress[_hist_progress.size() - 1]
