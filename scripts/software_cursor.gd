class_name SoftwareCursor
extends Control

## Hide the OS pointer and draw this Control instead.
## While a throttle is grabbed, this moves at grab_move_scale (0.1 = 10%).

static var instance: SoftwareCursor

## Cursor travel while holding a lever, as a fraction of mouse movement.
@export var grab_move_scale := 0.1

var _point := Vector2.ZERO


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_point = get_viewport().get_visible_rect().size * 0.5
	_snap_visual()
	_hide_os_cursor()
	call_deferred("_hide_os_cursor")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_hide_os_cursor()


func _hide_os_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var raw := motion.screen_relative
		if raw == Vector2.ZERO:
			raw = motion.relative
		var scale := grab_move_scale if ThrottleLever.is_busy() else 1.0
		_point += raw * scale
		_clamp_to_viewport()
		_snap_visual()


func _clamp_to_viewport() -> void:
	var viewport_rect := get_viewport().get_visible_rect()
	_point = Vector2(
		clampf(_point.x, viewport_rect.position.x, viewport_rect.end.x),
		clampf(_point.y, viewport_rect.position.y, viewport_rect.end.y)
	)


func _snap_visual() -> void:
	position = _point - size * 0.5


static func has_instance() -> bool:
	return instance != null and is_instance_valid(instance)


static func screen_point() -> Vector2:
	if has_instance():
		return instance._point
	return Vector2.ZERO
