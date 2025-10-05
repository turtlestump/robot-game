extends Line2D

@export var head: Node2D
@export var max_length: float = 150.0
@export var extend_speed: float = 600.0
@export var retract_speed: float = 1200.0
var grapple_point: Area2D = null

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
	if grapple_point != null:
		head.global_position = grapple_point.global_position
		
	from = global_position
		
func extend(delta: float) -> void:
	length += extend_speed * delta
	length = min(length, max_length)
	
	# update direction to pivot toward the fixed hook point
	direction = (to - from).normalized()
	
	set_point_position(0, Vector2.ZERO)
	set_point_position(1, direction * length)
	head.global_position = from + direction * length
	
	# Check length
	if length >= max_length:
		length = max_length
		extending = false
		retracting = true

func retract(delta:float) -> void:
	length -= retract_speed * delta
	length = max(length, 0.0)
	
	# update direction to pivot toward the fixed hook point
	direction = (to - from).normalized()
	
	set_point_position(0, Vector2.ZERO)
	set_point_position(1, direction * length)
	head.global_position = from + direction * length
	
	if length <= 0.0:
		visible = false
		head.visible = false

func _on_area_2d_area_entered(area: Area2D) -> void:
	if area.is_in_group("Grapple-Point"):
		extending = false
		retracting = false
		head.global_position = area.global_position
		
		grapple_point = area

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("World"):
		extending = false
		retracting = true
