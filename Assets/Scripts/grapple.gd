extends Line2D

# Update points according to position
# Max length
# Check collision with trigger
# Retract grapple line

@export var head: Sprite2D
@export var max_length: float = 150.0
@export var extend_speed: float = 100.0
@export var retract_speed: float = 1200.0

var extending: bool = false
var retracting: bool = false
var from: Vector2
var to: Vector2
var direction: Vector2
var length: float = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	clear_points()
	add_point(Vector2.ZERO)
	add_point(Vector2.ZERO)
	visible = false
	head.visible = false
	
func fire(target_position: Vector2):
	extending = true
	retracting = false
	visible = true
	head.visible = true
	
	from = global_position
	to = target_position
	direction = (to - from).normalized()
	length = 0.0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if extending:
		extend(delta)
	elif retracting:
		retract(delta)
		
	from = global_position
		
func extend(delta: float) -> void:
	length += extend_speed * delta
	to = from + direction * length
	
	set_point_position(0, Vector2.ZERO)
	set_point_position(1, direction * length)
	head.global_position = to
	
	# Check length
	if length >= max_length:
		length = max_length
		extending = false
		retracting = true

func retract(delta:float) -> void:
	length -= retract_speed * delta
	length = max(length, 0.0)
	to = from + direction * length
	
	# set_point_position(0, Vector2.ZERO)
	set_point_position(1, direction * length)
	head.global_position = to
	
	if length <= 0.0:
		visible = false
		head.visible = false
