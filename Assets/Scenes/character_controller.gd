extends RigidBody2D


@export_group("Ground movement")
## Maximum horizontal ground speed (pixels/sec)
@export var walk_speed: float = 120.0
## Acceleration rate when pressing left/right on ground
@export var accel: float = 900.0
## Deceleration rate when no input on ground
@export var stop_accel: float = 140.0
## Reverse acceleration rate when moving opposite to facing direction on ground
@export var ground_reverse_accel: float = 1300.0

@export_group("Ground adhesion & smoothing")
## Length of RayCast2D used to detect ground
@export var snap_dist: float = 24.0
## How quickly surface normal blends between frames
@export var normal_smooth_speed: float = 18.0
## Constant downward bias to stay “stuck” to ground
@export var stick_down_force: float = 400.0
## Cancels small upward pops when crossing seams
@export var cancel_pop_threshold: float = 30.0

@export_group("Air control")
## Enable player steering while airborne
@export var air_control_enabled: bool = true
## Air speed cap = walk_speed * this fraction
@export var air_speed_fraction: float = 0.5
## Acceleration in air toward target velocity
@export var air_accel: float = 400.0
## Rapid deceleration when holding opposite input
@export var air_reverse_decel: float = 1100.0
## Dual-purpose: quick-boost cutoff & forward accel limit
@export var air_speed_threshold: float = 60.0
## Acceleration used when below air_speed_threshold
@export var air_quick_accel: float = 1200.0
## Small drag when no input (optional, for stability)
@export var air_idle_drag: float = 0.0
## Disallow air steering for this many frames after leaving ground
@export var air_lockout_frames: int = 4

@export_group("Running step lift")
## Extra acceleration along +normal while moving on ground (simulates upward push per step)
@export var step_lift_accel: float = 180.0
## If true, scales lift by |tangent speed| / walk_speed
@export var step_lift_scale_with_speed: bool = true

@export_group("Jumping")
## Jump velocity along the ground normal
@export var jump_speed: float = 260.0
## Seconds after leaving ground where a jump is still allowed ("coyote time")
@export var coyote_time: float = 0.12
## Seconds BEFORE landing to buffer a jump press (executes on landing)
@export var jump_buffer_time: float = 0.10
## Seconds to ignore ground detection immediately after a jump (prevents stuck-on-ground)
@export var takeoff_suppress_time: float = 0.08
## If velocity along +normal exceeds this, treat as airborne even if ray still collides
@export var airborne_vn_threshold: float = 20.0
const ACTION_JUMP := "jump"                        ## Input action name for jumping

@export_group("Sticky direction")
## Enable sticky direction across landings (keeps accel aligned to current velocity until input direction changes)
@export var sticky_direction_enabled: bool = true
## Minimum |speed| threshold to treat velocity sign as reliable
@export var sticky_vt_epsilon: float = 0.5

@export_group("Debug (arrows)")
## Velocity arrow length multiplier
@export var arrow_scale: float = 0.1
## Velocity arrow color
@export var arrow_color: Color = Color.RED
## Acceleration arrow length multiplier
@export var accel_arrow_scale: float = 0.02
## Acceleration arrow color
@export var accel_arrow_color: Color = Color.BLUE

## ====== Input aliases ======
const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"

## ====== Internal state ======
var current_velocity: Vector2 = Vector2.ZERO
var current_accel: Vector2 = Vector2.ZERO
var previous_velocity: Vector2 = Vector2.ZERO

var last_ground_normal: Vector2 = Vector2.UP
var last_raw_ground_normal: Vector2 = Vector2.UP

## Previous-frame grounded state (updated at end of frame)
var prev_on_ground: bool = false

var can_jump: bool = false
var frames_since_ground: int = 9999
var coyote_time_left: float = 0.0
var jump_buffer_left: float = 0.0
var takeoff_timer: float = 0.0

## Sticky direction state
var sticky_active: bool = false          ## Whether sticky direction is currently active
var sticky_input_sign: float = 0.0       ## Sign of input at takeoff (used to detect change)

@onready var initial_position: Vector2 = global_position
@onready var ground_ray: RayCast2D = get_node_or_null("GroundRay") ## Downward ray, mask to floor layer

## =========================================================
## ===  Main Physics Loop  ===
## =========================================================
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	_handle_debug_reset(state)
	var dt := state.step
	var v := state.linear_velocity

	_update_takeoff_timer(dt)

	var ground_info := _detect_ground(state)
	var on_ground: bool = ground_info["on_ground"]
	var n: Vector2 = ground_info["normal"]

	n = _smooth_normal(n, dt, on_ground)
	_update_ground_frame_counter(on_ground, dt)
	_update_jump_gate(on_ground)
	_update_jump_buffer(dt)

	## Jump impulse (up the normal)
	v = _maybe_apply_jump(state, v, on_ground)

	## Player input (raw)
	var input_dir := Input.get_action_strength(ACTION_RIGHT) - Input.get_action_strength(ACTION_LEFT)
	var tng := _tangent_from_normal(n)

	## Sticky: update using a true just-left-ground transition.
	var just_left_ground := (not on_ground) and prev_on_ground
	_update_sticky_direction_state(just_left_ground, input_dir, v)

	## Effective directions
	var eff_dir_ground := _effective_ground_dir(v, tng, input_dir)
	var eff_dir_air := _effective_air_dir(v, input_dir)

	## Movement
	if on_ground:
		v = _move_on_ground(state, v, n, tng, eff_dir_ground, input_dir)
	else:
		v = _move_in_air(state, v, eff_dir_air)

	## --- Acceleration tracking ---
	current_accel = (v - previous_velocity) / maxf(dt, 1e-6)
	previous_velocity = v

	state.linear_velocity = v
	current_velocity = v

	## Update previous grounded state at the end
	prev_on_ground = on_ground

	queue_redraw()

## =========================================================
## ===  Ground detection and smoothing  ===
## =========================================================
func _detect_ground(state: PhysicsDirectBodyState2D) -> Dictionary:
	var n := Vector2.UP
	var raw_n := Vector2.UP
	var on_ground := false

	if ground_ray:
		ground_ray.target_position = Vector2(0, snap_dist)
		ground_ray.enabled = true
		if ground_ray.is_colliding():
			raw_n = ground_ray.get_collision_normal().normalized()
			n = raw_n
			on_ground = true

	if not on_ground:
		var cc := state.get_contact_count()
		if cc > 0:
			on_ground = true
			raw_n = _best_up_normal_from_contacts(state)
			n = raw_n

	# Update last raw normal when on ground
	if on_ground:
		last_raw_ground_normal = raw_n

	## If we've recently jumped, force airborne regardless of ray/contacts
	if takeoff_timer > 0.0:
		return {"on_ground": false, "normal": last_ground_normal}

	## If still moving strongly away from the surface, treat as airborne
	var vn_now := state.linear_velocity.dot(n)
	if on_ground and vn_now >= airborne_vn_threshold:
		on_ground = false

	return {"on_ground": on_ground, "normal": n}

func _best_up_normal_from_contacts(state: PhysicsDirectBodyState2D) -> Vector2:
	var best_dot := -1e9
	var best_n := Vector2.UP
	var cc := state.get_contact_count()
	for i in cc:
		var cn := state.get_contact_local_normal(i).normalized()
		var d := cn.dot(Vector2.UP)
		if d > best_dot:
			best_dot = d
			best_n = cn
	return best_n

func _smooth_normal(n: Vector2, dt: float, on_ground: bool) -> Vector2:
	if on_ground:
		var k := clampf(normal_smooth_speed * dt, 0.0, 1.0)
		n = (last_ground_normal.lerp(n, k)).normalized()
		last_ground_normal = n
	else:
		n = last_ground_normal
	return n

func _tangent_from_normal(n: Vector2) -> Vector2:
	return Vector2(-n.y, n.x).normalized()

func _get_jump_normal(state: PhysicsDirectBodyState2D, on_ground: bool) -> Vector2:
	# Prefer the instantaneous contact/ray normal at the jump moment; fallback to last raw ground normal
	if on_ground:
		if ground_ray and ground_ray.is_colliding():
			return ground_ray.get_collision_normal().normalized()
		var cc := state.get_contact_count()
		if cc > 0:
			return _best_up_normal_from_contacts(state)
	return last_raw_ground_normal

## =========================================================
## ===  Sticky direction helpers  ===
## =========================================================
func _update_sticky_direction_state(just_left_ground: bool, input_dir: float, v: Vector2) -> void:
	## KILL sticky when there's no input direction (requested behavior)
	if sticky_active and absf(input_dir) <= 0.001:
		sticky_active = false

	## PREVENT re-activation right after a jump:
	## while takeoff_timer > 0, do not allow sticky to activate on "just left ground".
	var can_activate_sticky := sticky_direction_enabled and (takeoff_timer <= 0.0)

	## Activate sticky when we JUST left the ground while holding a direction (and not in takeoff suppression)
	if can_activate_sticky and just_left_ground and absf(input_dir) > 0.001:
		sticky_active = true
		sticky_input_sign = signf(input_dir)

	## Unstick when the player actively changes input direction (presses nonzero opposite sign)
	if sticky_active and absf(input_dir) > 0.001:
		if signf(input_dir) != sticky_input_sign:
			sticky_active = false

func _effective_ground_dir(v: Vector2, tng: Vector2, input_dir: float) -> float:
	## When sticky is active, drive along the **current tangent velocity** direction.
	if sticky_direction_enabled and sticky_active:
		var vt := v.dot(tng)
		if absf(vt) >= sticky_vt_epsilon:
			return signf(vt)
		## Near-zero tangent speed: fall back to stored sticky sign
		if absf(sticky_input_sign) > 0.0:
			return sticky_input_sign
	return input_dir

func _effective_air_dir(v: Vector2, input_dir: float) -> float:
	## Air uses world-X; reflect sticky by following current horizontal velocity sign
	## (or the stored sticky sign if speed is tiny).
	if sticky_direction_enabled and sticky_active:
		var vx := v.x
		if absf(vx) >= sticky_vt_epsilon:
			return signf(vx)
		if absf(sticky_input_sign) > 0.0:
			return sticky_input_sign
	return input_dir

## =========================================================
## ===  Jumping & ground-state tracking  ===
## =========================================================
func _update_jump_gate(on_ground: bool) -> void:
	## Open jump gate when we just landed
	if on_ground and not prev_on_ground:
		can_jump = true

func _update_ground_frame_counter(on_ground: bool, dt: float) -> void:
	if on_ground:
		frames_since_ground = 0
		coyote_time_left = coyote_time
	else:
		frames_since_ground += 1
		coyote_time_left = maxf(coyote_time_left - dt, 0.0)

func _update_jump_buffer(dt: float) -> void:
	## When the player presses jump at any time, start/refresh the buffer timer.
	if Input.is_action_just_pressed(ACTION_JUMP):
		jump_buffer_left = jump_buffer_time
	else:
		jump_buffer_left = maxf(jump_buffer_left - dt, 0.0)

func _update_takeoff_timer(dt: float) -> void:
	if takeoff_timer > 0.0:
		takeoff_timer = maxf(takeoff_timer - dt, 0.0)

func _maybe_apply_jump(state: PhysicsDirectBodyState2D, v: Vector2, on_ground: bool) -> Vector2:
	## Consume buffered jump if available and jumping is permitted (grounded or within coyote time)
	if can_jump and (on_ground or coyote_time_left > 0.0) and jump_buffer_left > 0.0:
		var jn := _get_jump_normal(state, on_ground) # use unsmoothed, instantaneous surface normal
		jn = jn.normalized()
		var vn := v.dot(jn)
		var desired_vn := jump_speed      ## Launch strictly along +normal
		var delta_vn := desired_vn - vn
		v += jn * delta_vn
		can_jump = false
		coyote_time_left = 0.0
		jump_buffer_left = 0.0
		## Start a brief takeoff suppression so rays/contacts don't keep us "grounded"
		takeoff_timer = takeoff_suppress_time

		## Disable sticky on actual jump (requested)
		sticky_active = false
		sticky_input_sign = 0.0
	return v

## =========================================================
## ===  Movement logic  ===
## =========================================================
func _move_on_ground(state: PhysicsDirectBodyState2D, v: Vector2, n: Vector2, tng: Vector2, eff_dir: float, input_dir: float) -> Vector2:
	var vn := v.dot(n)
	## Only cancel tiny upward pops when there's no active input;
	## when the player is pushing forward we allow some upward component for "step lift".
	if absf(input_dir) <= 0.001 and vn > 0.0 and vn < cancel_pop_threshold:
		v -= n * vn
	## adhesion (minor downward bias)
	v -= n * (stick_down_force * state.step)

	## drive along tangent
	var vt := v.dot(tng)
	if absf(eff_dir) > 0.001:
		var target := eff_dir * walk_speed
		var rate := accel
		# If effective dir opposes current tangent velocity, use stronger reverse accel
		if signf(vt) != 0.0 and signf(eff_dir) != signf(vt):
			rate = ground_reverse_accel
		vt = move_toward(vt, target, rate * state.step)
	else:
		vt = move_toward(vt, 0.0, stop_accel * state.step)

	## recompose velocity from tangent & orthogonal components
	var v_orth := v - tng * v.dot(tng)
	var new_v := v_orth + tng * vt

	## Step lift only when actually holding input (not just sticky)
	if absf(input_dir) > 0.001:
		var lift_scale := 1.0
		if step_lift_scale_with_speed:
			lift_scale = clampf(absf(vt) / maxf(walk_speed, 0.001), 0.0, 1.0)
		new_v += n * (step_lift_accel * lift_scale * state.step)

	return new_v

func _move_in_air(state: PhysicsDirectBodyState2D, v: Vector2, dir: float) -> Vector2:
	if not air_control_enabled:
		return v
	## 1) Skip air control for N frames after leaving ground
	if frames_since_ground <= air_lockout_frames:
		return v

	var vx := v.x
	var air_max := walk_speed * air_speed_fraction

	if absf(dir) > 0.001:
		## Reverse input: allow braking always
		if signf(vx) != 0.0 and signf(dir) != signf(vx):
			vx = move_toward(vx, 0.0, air_reverse_decel * state.step)
		else:
			## Quick-boost below threshold; no forward accel above threshold
			if absf(vx) < air_speed_threshold:
				var quick_target := dir * minf(air_speed_threshold, air_max)
				vx = move_toward(vx, quick_target, air_quick_accel * state.step)
			elif signf(dir) != signf(vx):
				## Allow braking in opposite direction
				vx = move_toward(vx, 0.0, air_reverse_decel * state.step)
			## else: already above threshold in forward direction → do nothing
	elif air_idle_drag > 0.0:
		vx = move_toward(vx, 0.0, air_idle_drag * state.step)

	vx = clampf(vx, -air_max, air_max)
	v.x = vx
	return v

## =========================================================
## ===  Debug / utilities  ===
## =========================================================
func _handle_debug_reset(state: PhysicsDirectBodyState2D) -> void:
	if Input.is_action_just_pressed("debug_reset"):
		global_position = initial_position
		state.linear_velocity = Vector2.ZERO
		previous_velocity = Vector2.ZERO
		current_accel = Vector2.ZERO
		## Clear sticky on hard reset
		sticky_active = false
		sticky_input_sign = 0.0
		prev_on_ground = false

func _draw() -> void:
	## Base anchor for debug drawing just above the body
	var base := Vector2(0, -20)

	## Draw velocity (red)
	if current_velocity.length() >= 0.1:
		var start := base
		var end := start + current_velocity * arrow_scale
		draw_line(start, end, arrow_color, 2.0)
		var d := (end - start).normalized()
		var side1 := d.rotated(PI * 3.0 / 4.0) * 6.0
		var side2 := d.rotated(-PI * 3.0 / 4.0) * 6.0
		draw_line(end, end + side1, arrow_color, 2.0)
		draw_line(end, end + side2, arrow_color, 2.0)

	## Draw acceleration (blue)
	if current_accel.length() >= 0.1:
		var a_start := base
		var a_end := a_start + current_accel * accel_arrow_scale
		draw_line(a_start, a_end, accel_arrow_color, 2.0)
		var ad := (a_end - a_start).normalized()
		var aside1 := ad.rotated(PI * 3.0 / 4.0) * 6.0
		var aside2 := ad.rotated(-PI * 3.0 / 4.0) * 6.0
		draw_line(a_end, a_end + aside1, accel_arrow_color, 2.0)

	## GREEN DOT: shows when sticky is active
	if sticky_direction_enabled and sticky_active:
		var dot_pos := base + Vector2(0, -12)
		draw_circle(dot_pos, 3.0, Color(0, 1, 0))
