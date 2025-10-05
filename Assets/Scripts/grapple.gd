extends Line2D

@export var head: Node2D
@export var max_length: float = 150.0
@export var extend_speed: float = 600.0
@export var retract_speed: float = 1200.0
var grapple_point: Area2D = null

var extending := false
var retracting := false
var latched := false

var from := Vector2.ZERO
var to := Vector2.ZERO
var direction := Vector2.ZERO
var length := 0.0

func _ready() -> void:
	clear_points()
	add_point(Vector2.ZERO)
	add_point(Vector2.ZERO)
	visible = false
	if head: head.visible = false

func fire(target_position: Vector2):
	extending = true
	retracting = false
	latched = false
	visible = true
	if head: head.visible = true

	from = global_position               # assuming Line2D is a child of the player
	to = target_position
	direction = (to - from).normalized()
	length = 0.0

func _process(delta: float) -> void:
	from = global_position

	if latched and grapple_point:
		# pin end to grapple point
		var end_local := to_local(grapple_point.global_position)
		set_point_position(0, Vector2.ZERO)
		set_point_position(1, end_local)
		if head: head.global_position = grapple_point.global_position
		return

	if extending:
		extend(delta)
	elif retracting:
		retract(delta)

func extend(delta: float) -> void:
	length = min(length + extend_speed * delta, max_length)
	direction = (to - from).normalized()

	set_point_position(0, Vector2.ZERO)
	set_point_position(1, direction * length)
	if head: head.global_position = from + direction * length

	# reached max → start retract
	if length >= max_length:
		extending = false
		retracting = true

func retract(delta: float) -> void:
	length = max(length - retract_speed * delta, 0.0)
	direction = (to - from).normalized()

	set_point_position(0, Vector2.ZERO)
	set_point_position(1, direction * length)
	if head: head.global_position = from + direction * length

	if length <= 0.0:
		visible = false
		if head: head.visible = false
		grapple_point = null
		latched = false

func _on_area_2d_area_entered(area: Area2D) -> void:
	if area.is_in_group("Grapple-Point"):
		extending = false
		retracting = false
		latched = true
		grapple_point = area

		# snap the line immediately to the contact point
		var end_local := to_local(area.global_position)
		set_point_position(0, Vector2.ZERO)
		set_point_position(1, end_local)
		if head: head.global_position = area.global_position

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("World"):
		# hit world: unlatch and retract
		latched = false
		grapple_point = null
		extending = false
		retracting = true
