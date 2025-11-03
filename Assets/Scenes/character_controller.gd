extends RigidBody2D

@export var walk_speed: float = 120.0
@export var accel: float = 900.0
@export var stop_accel: float = 140.0

# ---- Debug arrow ----
@export var arrow_scale: float = 0.1
@export var arrow_color: Color = Color.RED

# ---- Ground handling / smoothing ----
@export var snap_dist: float = 24.0                 # GroundRay length; also used for sanity checks
@export var normal_smooth_speed: float = 18.0       # Higher = snappier normal smoothing
@export var stick_down_force: float = 400.0         # Small constant "adhesion" along -n
@export var cancel_pop_threshold: float = 30.0      # Zero-out tiny upward (along n) velocity bumps

const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"

var current_velocity: Vector2 = Vector2.ZERO
var last_ground_normal: Vector2 = Vector2.UP
@onready var initial_position: Vector2 = global_position
@onready var ground_ray: RayCast2D = get_node_or_null("GroundRay")

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if Input.is_action_just_pressed("debug_reset"):
		global_position = initial_position
		state.linear_velocity = Vector2.ZERO

	# ---------- 1) Detect ground & pick a stable normal ----------
	var on_ground := false
	var n := Vector2.UP

	# Prefer the RayCast2D to avoid seam flip-flop
	if ground_ray:
		ground_ray.target_position = Vector2(0, snap_dist)
		ground_ray.enabled = true
		if ground_ray.is_colliding():
			var rn := ground_ray.get_collision_normal().normalized()
			# Only treat as ground if it faces somewhat up; else we fall back to contacts
			if rn.dot(Vector2.UP) > -0.2: # allow ceilings/walls if you want; tweak as needed
				n = rn
				on_ground = true

	# Fallback: average contacts (use only the "most upward" one to avoid wall bias)
	if not on_ground:
		var cc := state.get_contact_count()
		if cc > 0:
			on_ground = true
			var best_dot := -1e9
			var best_n := Vector2.UP
			for i in cc:
				var cn := state.get_contact_local_normal(i).normalized()
				var d := cn.dot(Vector2.UP)
				if d > best_dot:
					best_dot = d
					best_n = cn
			n = best_n

	# ---------- 2) Smooth the ground normal to avoid seam bumps ----------
	if on_ground:
		# Exponential-ish smoothing in time: slerp/lerp by factor in [0,1]
		var t : float = clamp(normal_smooth_speed * state.step, 0.0, 1.0)
		n = (last_ground_normal.lerp(n, t)).normalized()
		last_ground_normal = n
	else:
		# When airborne, keep last_ground_normal so we don't snap weirdly on recontact
		n = last_ground_normal

	# Tangent for along-surface motion (right-hand tangent when n == UP)
	var tng := Vector2(-n.y, n.x).normalized()

	# ---------- 3) Move along tangent; stick-to-ground ----------
	var dir := Input.get_action_strength(ACTION_RIGHT) - Input.get_action_strength(ACTION_LEFT)
	var v := state.linear_velocity

	if on_ground:
		# Cancel tiny upward "pops" along the normal (smoothing out seam jiggle)
		var vn := v.dot(n)
		if vn > 0.0 and vn < cancel_pop_threshold:
			v -= n * vn

		# Small constant adhesion so we don't leave the ground over micro-gaps
		v -= n * (stick_down_force * state.step)

		# Drive speed along the tangent only, preserve orthogonal component
		var vt := v.dot(tng)
		if absf(dir) > 0.001:
			var target := dir * walk_speed
			vt = move_toward(vt, target, accel * state.step)
		else:
			vt = move_toward(vt, 0.0, stop_accel * state.step)

		var v_orth := v - tng * v.dot(tng)
		v = v_orth + tng * vt

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
