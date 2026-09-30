class_name Cockpit
extends Node3D

## Scene-owned paths into the inherited GLB. Other Main systems read these.

@onready var left_throttle: ThrottleLever = $Env/ThrottleLeft/Handle
@onready var right_throttle: ThrottleLever = $Env/ThrottleRight/Handle_001
