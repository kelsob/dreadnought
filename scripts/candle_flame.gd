class_name CandleFlame
extends Node3D

## Wick Omni only. No cards, shaders, fill, or machine motion yet.

@export var energy := 0.42
@export var color := Color(1.0, 0.51, 0.16)
@export var omni_range := 3.2
## 0 = almost flat then dies at range. 2 = inverse square.
@export var attenuation := 1.7
@export var specular := 0.28

var _light: OmniLight3D


func _ready() -> void:
	_light = $Sway/LightPoint/OmniLight3D
	_hide_old_layers()
	_apply_light()


func _apply_light() -> void:
	_light.visible = true
	_light.light_energy = energy
	_light.light_color = color
	_light.omni_range = omni_range
	_light.omni_attenuation = attenuation
	_light.light_specular = specular
	_light.shadow_enabled = true
	_light.shadow_opacity = 0.68
	_light.shadow_blur = 2.0
	_light.shadow_bias = 0.03
	_light.light_volumetric_fog_energy = 0.8


func _hide_old_layers() -> void:
	var fill := get_node_or_null("Fill") as OmniLight3D
	if fill != null:
		fill.visible = false
	var sway := get_node_or_null("Sway")
	if sway == null:
		return
	for child in sway.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false
