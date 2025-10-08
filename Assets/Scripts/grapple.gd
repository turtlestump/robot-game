extends Line2D

signal grappled(center_point: Vector2)

@export var head: Node2D
@export var max_length: float = 150.0
@export var extend_speed: float = 600.0
@export var retract_speed: float = 1200.0

var extending := false
var retracting := false
var latched := false

var grapple_point: Area2D = null
var from := Vector2.ZERO
var to := Vector2.ZERO
var direction := Vector2.RIGHT
var length := 0.0

func _ready() -> void:
	clear_points()
	add_point(Vector2.ZERO)  # start (local)
	add_point(Vector2.ZERO)  # end (local)
	_set_visible(false)
	if is_instance_valid(head):
		head.top_level = true  # so we can place it in world space cleanly

func fire(target_position: Vector2) -> void:
	from = global_position
	to = target_position
	direction = (to - from).normalized()
	length = 0.0
	extending = true
	retracting = false
	latched = false
	grapple_point = null
	_set_visible(true)
	_draw_unlatched_end(from + direction * length)

func begin_retract() -> void:
	if !retracting:
		retracting = true
		extending = false
		latched = false
		grapple_point = null
		# keep current direction so retract looks natural

func _process(delta: float) -> void:
	from = global_position
	if latched and is_instance_valid(grapple_point):
		# Pin end to grapple point
		var end_global := grapple_point.global_position
		_draw_latched_end(end_global)
		# keep direction/length updated so a later retract is smooth
		length = from.distance_to(end_global)
		if length > 0.0:
			direction = (end_global - from).normalized()
		return

	if extending:
		length = min(length + extend_speed * delta, max_length)
		direction = (to - from).normalized()
		var end_global := from + direction * length
		_draw_unlatched_end(end_global)
		if length >= max_length:
			# max reached without latching → start retract
			retracting = true
			extending = false

	elif retracting:
		length = max(length - retract_speed * delta, 0.0)
		var end_global := from + direction * length
		_draw_unlatched_end(end_global)
		if length <= 0.0:
			_set_visible(false)
			retracting = false  # back to idle

	# idle: nothing to draw; visibility is already handled when length hits 0

func _on_area_2d_area_entered(area: Area2D) -> void:
	if area.is_in_group("Grapple-Point") and extending:
		extending = false
		retracting = false
		latched = true
		grapple_point = area
		var end_global := area.global_position
		_draw_latched_end(end_global)
		length = from.distance_to(end_global)
		if length > 0.0:
			direction = (end_global - from).normalized()
		emit_signal("grappled", end_global)

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("World"):
		begin_retract()

# ----------------- helpers (tiny & focused) -----------------

func _set_visible(v: bool) -> void:
	visible = v
	if is_instance_valid(head):
		head.visible = v

func _draw_unlatched_end(end_global: Vector2) -> void:
	set_point_position(0, Vector2.ZERO)
	set_point_position(1, to_local(end_global))
	if is_instance_valid(head):
		head.global_position = end_global

func _draw_latched_end(end_global: Vector2) -> void:
	set_point_position(0, Vector2.ZERO)
	set_point_position(1, to_local(end_global))
	if is_instance_valid(head):
		head.global_position = end_global
