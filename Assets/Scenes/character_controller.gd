extends RigidBody2D

@export var walk_speed: float = 120.0
@export var accel: float = 900.0
@export var stop_accel: float = 140.0
@export var arrow_scale: float = 0.1
@export var arrow_color: Color = Color.RED

const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"

var current_velocity: Vector2 = Vector2.ZERO

@onready var initial_position: Vector2 = global_position

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:

	if Input.is_action_just_pressed("debug_reset"):
		global_position	= initial_position
		state.linear_velocity = Vector2.ZERO

	var contact_count := state.get_contact_count()
	var on_ground := contact_count > 0

	# Average contact normal (fallback = UP)
	var n := Vector2.UP
	if on_ground:
		var sum := Vector2.ZERO
		for i in contact_count:
			sum += state.get_contact_local_normal(i)
		if sum.length() > 0.0001:
			n = sum.normalized()

	# Tangent points "to the right" when n == UP, so right input maps to +x on flat ground.
	var t := Vector2(-n.y, n.x).normalized()

	var dir := Input.get_action_strength(ACTION_RIGHT) - Input.get_action_strength(ACTION_LEFT)
	var v := state.linear_velocity

	if on_ground:
		# Component of velocity along the tangent
		var vt := v.dot(t)

		if absf(dir) > 0.001:
			var target := dir * walk_speed
			vt = move_toward(vt, target, accel * state.step)
		else:
			vt = move_toward(vt, 0.0, stop_accel * state.step)

		# Recombine: keep the component orthogonal to the tangent unchanged
		var v_orth := v - t * v.dot(t)
		v = v_orth + t * vt

	state.linear_velocity = v
	current_velocity = v
	queue_redraw()

func _draw() -> void:
	if current_velocity.length() < 0.1:
		return
	var start := Vector2(0, -20)
	var end := start + current_velocity * arrow_scale
	draw_line(start, end, arrow_color, 2.0)
	var dir := (end - start).normalized()
	var side1 := dir.rotated(PI * 3.0 / 4.0) * 6.0
	var side2 := dir.rotated(-PI * 3.0 / 4.0) * 6.0
	draw_line(end, end + side1, arrow_color, 2.0)
	draw_line(end, end + side2, arrow_color, 2.0)
