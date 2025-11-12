extends Node2D

# Represents cursor position
var camera
var world_mouse_pos

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	camera = get_viewport().get_camera_2d()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	visible = true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	world_mouse_pos = camera.get_global_mouse_position()
	global_position = world_mouse_pos
