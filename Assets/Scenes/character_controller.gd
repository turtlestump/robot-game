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
## Input action name for jumping
const ACTION_JUMP := "jump"

@export_group("Sticky direction")
## Enable sticky direction across landings (keeps accel aligned to current velocity until input direction changes)
@export var sticky_direction_enabled: bool = true
## Minimum |speed| threshold to treat velocity sign as reliable
@export var sticky_vt_epsilon: float = 0.5

@export_group("Equipped Components")
## Currently equipped weapon for attack calls
@export var weapon: Node2D = null

@export_group("Debug (arrows)")
## Velocity arrow length multiplier
@export var arrow_scale: float = 0.1
## Velocity arrow color
@export var arrow_color: Color = Color.RED
## Acceleration arrow length multiplier
@export var accel_arrow_scale: float = 0.02
## Acceleration arrow color
@export var accel_arrow_color: Color = Color.BLUE

@export_group("Jet blade boost")
## Time (seconds) to shape the decay after end signal
@export var boost_end_time: float = 0.25
## Multiplier for each successive in-air boost in a chain (0-1 for diminishing)
@export var air_boost_chain_multiplier: float = 0.7
## Max angle (deg) between contact normal and UP to count as "ground-like" & reset the air boost chain
@export var air_boost_reset_angle_deg: float = 50.0

## ====== Input aliases ======
const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"

## ====== Internal state ======
var current_velocity: Vector2 = Vector2.ZERO
var current_accel: Vector2 = Vector2.ZERO
var previous_velocity: Vector2 = Vector2.ZERO

var last_ground_normal: Vector2 = Vector2.UP
var last_raw_ground_normal: Vector2 = Vector2.UP

## Jet blade boost state
var boost_impulse: Vector2 = Vector2.ZERO      ## Original impulse vector (applied once)
var boost_pending: bool = false                ## Apply impulse next physics step
var boost_dir: Vector2 = Vector2.ZERO          ## Normalized direction of impulse
var boost_total_mag: float = 0.0               ## Full magnitude of applied boost
var boost_max_remove: float = 0.0              ## We only ever remove 25% of boost_total_mag
var boost_removed_mag: float = 0.0             ## How much of that 25% we've removed so far
var boost_end_requested: bool = false          ## Has the end signal been received?
var boost_elapsed: float = 0.0                 ## Time since decay started

## Air boost chain state
var air_boost_chain: int = 0                   ## Index of successive in-air boosts
var last_boost_was_air: bool = false           ## True if last boost was applied while airborne

## Previous-frame grounded state
var prev_on_ground: bool = false

var can_jump: bool = false
var frames_since_ground: int = 9999
var coyote_time_left: float = 0.0
var jump_buffer_left: float = 0.0
var takeoff_timer: float = 0.0

## Sticky direction state
var sticky_active: bool = false
var sticky_input_sign: float = 0.0

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

	## Reset air boost chain only when touching a "ground-like" surface (normal within angle threshold of UP)
	if _should_reset_air_boost(state):
		air_boost_chain = 0
		last_boost_was_air = false

	## Jump impulse (up the normal)
	v = _maybe_apply_jump(state, v, on_ground)

	## Jet blade boost (one-shot impulse + eased partial decay)
	v = _apply_jet_blade_boost(state, v)

	## Player input
	var input_dir := Input.get_action_strength(ACTION_RIGHT) - Input.get_action_strength(ACTION_LEFT)
	var tng := _tangent_from_normal(n)

	## Sticky: based on true just-left-ground transition
	var just_left_ground := (not on_ground) and prev_on_ground
	_update_sticky_direction_state(just_left_ground, input_dir, v)

	## Effective movement directions
	var eff_dir_ground := _effective_ground_dir(v, tng, input_dir)
	var eff_dir_air := _effective_air_dir(v, input_dir)

	## Movement
	if on_ground:
		v = _move_on_ground(state, v, n, tng, eff_dir_ground, input_dir)
	else:
		v = _move_in_air(state, v, eff_dir_air)

	## Attacks
	if weapon and weapon.has_method("attack"):
		if Input.is_action_just_pressed("attack"):
			weapon.attack()

	## Accel tracking
	current_accel = (v - previous_velocity) / maxf(dt, 1e-6)
	previous_velocity = v

	state.linear_velocity = v
	current_velocity = v
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

	# Update last raw normal while grounded
	if on_ground:
		last_raw_ground_normal = raw_n

	## If we've recently jumped, force airborne regardless of ray/contacts
	if takeoff_timer > 0.0:
		return {"on_ground": false, "normal": last_ground_normal}

	## If moving strongly away from surface, treat as airborne
	var vn_now := state.linear_velocity.dot(n)
	if on_ground and vn_now >= airborne_vn_threshold:
		on_ground = false

	return {"on_ground": on_ground, "normal": n}


func _best_up_normal_from_contacts(state: PhysicsDirectBodyState2D) -> Vector2:
	var best_dot := -1e9
	var best_n := Vector2.UP
	var cc := state.get_contact_count()
	for i in range(cc):
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
	# Prefer instantaneous contact/ray normal at jump moment; fallback to last raw ground normal
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
	## Disable sticky when no input direction
	if sticky_active and absf(input_dir) <= 0.001:
		sticky_active = false

	## Allow activation only if not in takeoff suppression
	var can_activate_sticky := sticky_direction_enabled and (takeoff_timer <= 0.0)

	## Activate when we just left ground with input held
	if can_activate_sticky and just_left_ground and absf(input_dir) > 0.001:
		sticky_active = true
		sticky_input_sign = signf(input_dir)

	## Unstick when input reverses
	if sticky_active and absf(input_dir) > 0.001:
		if signf(input_dir) != sticky_input_sign:
			sticky_active = false


func _effective_ground_dir(v: Vector2, tng: Vector2, input_dir: float) -> float:
	if sticky_direction_enabled and sticky_active:
		var vt := v.dot(tng)
		if absf(vt) >= sticky_vt_epsilon:
			return signf(vt)
		if absf(sticky_input_sign) > 0.0:
			return sticky_input_sign
	return input_dir


func _effective_air_dir(v: Vector2, input_dir: float) -> float:
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
	if Input.is_action_just_pressed(ACTION_JUMP):
		jump_buffer_left = jump_buffer_time
	else:
		jump_buffer_left = maxf(jump_buffer_left - dt, 0.0)


func _update_takeoff_timer(dt: float) -> void:
	if takeoff_timer > 0.0:
		takeoff_timer = maxf(takeoff_timer - dt, 0.0)


func _maybe_apply_jump(state: PhysicsDirectBodyState2D, v: Vector2, on_ground: bool) -> Vector2:
	if can_jump and (on_ground or coyote_time_left > 0.0) and jump_buffer_left > 0.0:
		var jn := _get_jump_normal(state, on_ground).normalized()
		var vn := v.dot(jn)
		var desired_vn := jump_speed
		var delta_vn := desired_vn - vn
		v += jn * delta_vn

		can_jump = false
		coyote_time_left = 0.0
		jump_buffer_left = 0.0
		takeoff_timer = takeoff_suppress_time

		## Disable sticky on actual jump
		sticky_active = false
		sticky_input_sign = 0.0

	return v


## =========================================================
## ===  Jet blade boost logic  ===
## =========================================================
func _apply_jet_blade_boost(state: PhysicsDirectBodyState2D, v: Vector2) -> Vector2:
	var dt := state.step

	# 1) Apply pending impulse once
	if boost_pending and boost_impulse != Vector2.ZERO:
		v += boost_impulse
		boost_pending = false

		boost_dir = boost_impulse.normalized()
		boost_total_mag = boost_impulse.length()
		boost_max_remove = boost_total_mag * 0.25      # Only ever remove 25% of this boost
		boost_removed_mag = 0.0
		# Decay begins once end is requested

	# 2) Eased decay after end signal, capped at 25%
	if boost_end_requested and boost_dir != Vector2.ZERO and boost_max_remove > 0.0 and boost_end_time > 0.0:
		boost_elapsed += dt
		var t : float = clamp(boost_elapsed / boost_end_time, 0.0, 1.0)

		# Ease-out cubic (fast then slow)
		var eased := 1.0 - pow(1.0 - t, 3.0)

		# Desired total removed so far (0 → boost_max_remove)
		var target_removed := boost_max_remove * eased
		var to_remove := maxf(target_removed - boost_removed_mag, 0.0)

		if to_remove > 0.0:
			var v_along := v.dot(boost_dir)
			# Don't remove more along boost_dir than we currently have, and don't exceed our cap
			var allowed := minf(to_remove, maxf(v_along, 0.0))
			if allowed > 0.0:
				var old_v := v
				var new_v := v - boost_dir * allowed

				# Clamp to prevent sign flip on x
				if old_v.x != 0.0 and signf(old_v.x) != signf(new_v.x):
					new_v.x = 0.0
				# Clamp to prevent sign flip on y
				if old_v.y != 0.0 and signf(old_v.y) != signf(new_v.y):
					new_v.y = 0.0

				v = new_v
				boost_removed_mag += allowed

		# Stop when we've removed our allowed 25% or shaped over full time
		if t >= 1.0 or boost_removed_mag >= boost_max_remove - 0.0001:
			boost_end_requested = false
			boost_elapsed = 0.0

			# Remaining 75% stays baked into velocity; clear decay state
			boost_impulse = Vector2.ZERO
			boost_dir = Vector2.ZERO
			boost_total_mag = 0.0
			boost_max_remove = 0.0
			boost_removed_mag = 0.0

	return v


## =========================================================
## ===  Air boost reset helper  ===
## =========================================================
func _should_reset_air_boost(state: PhysicsDirectBodyState2D) -> bool:
	var cos_threshold := cos(deg_to_rad(air_boost_reset_angle_deg))
	var cc := state.get_contact_count()

	# Check physical contacts
	for i in range(cc):
		var n := state.get_contact_local_normal(i).normalized()
		if n.dot(Vector2.UP) >= cos_threshold:
			return true

	# Optionally also consider ground ray as "ground-like"
	if ground_ray and ground_ray.is_colliding():
		var rn := ground_ray.get_collision_normal().normalized()
		if rn.dot(Vector2.UP) >= cos_threshold:
			return true

	return false


## =========================================================
## ===  Movement logic  ===
## =========================================================
func _move_on_ground(state: PhysicsDirectBodyState2D, v: Vector2, n: Vector2, tng: Vector2, eff_dir: float, input_dir: float) -> Vector2:
	var vn := v.dot(n)

	## Cancel tiny upward pops only when no input
	if absf(input_dir) <= 0.001 and vn > 0.0 and vn < cancel_pop_threshold:
		v -= n * vn

	## Adhesion bias
	v -= n * (stick_down_force * state.step)

	var vt := v.dot(tng)
	if absf(eff_dir) > 0.001:
		var target := eff_dir * walk_speed
		var rate := accel
		## Stronger accel if reversing direction
		if signf(vt) != 0.0 and signf(eff_dir) != signf(vt):
			rate = ground_reverse_accel
		vt = move_toward(vt, target, rate * state.step)
	else:
		vt = move_toward(vt, 0.0, stop_accel * state.step)

	var v_orth := v - tng * v.dot(tng)
	var new_v := v_orth + tng * vt

	## Step lift only when actively pressing input
	if absf(input_dir) > 0.001:
		var lift_scale := 1.0
		if step_lift_scale_with_speed:
			lift_scale = clampf(absf(vt) / maxf(walk_speed, 0.001), 0.0, 1.0)
		new_v += n * (step_lift_accel * lift_scale * state.step)

	return new_v


func _move_in_air(state: PhysicsDirectBodyState2D, v: Vector2, dir: float) -> Vector2:
	if not air_control_enabled:
		return v

	## Air control lockout just after leaving ground
	if frames_since_ground <= air_lockout_frames:
		return v

	var vx := v.x
	var air_max := walk_speed * air_speed_fraction

	if absf(dir) > 0.001:
		## If reversing, strong brake
		if signf(vx) != 0.0 and signf(dir) != signf(vx):
			vx = move_toward(vx, 0.0, air_reverse_decel * state.step)
		else:
			## Quick accel below threshold
			if absf(vx) < air_speed_threshold:
				var quick_target := dir * minf(air_speed_threshold, air_max)
				vx = move_toward(vx, quick_target, air_quick_accel * state.step)
			elif signf(dir) != signf(vx):
				## Allow braking if input opposes velocity
				vx = move_toward(vx, 0.0, air_reverse_decel * state.step)
	elif air_idle_drag > 0.0:
		## Gentle drag when no input
		vx = move_toward(vx, 0.0, air_idle_drag * state.step)

	vx = clampf(vx, -air_max, air_max)
	v.x = vx
	return v


## =========================================================
## === Tool / weapon usage ===
## =========================================================
func _attack() -> void:
	pass


## =========================================================
## === Signals ===
## =========================================================
func _on_jet_blade_melee_boost(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return

	# Consider it an "air" boost if we were not grounded in the previous step
	var is_air := not prev_on_ground

	if is_air:
		if last_boost_was_air:
			air_boost_chain += 1
		else:
			air_boost_chain = 0
		last_boost_was_air = true
	else:
		air_boost_chain = 0
		last_boost_was_air = false

	# Scale successive in-air boosts by multiplier^chain_index
	var scale := 1.0
	if is_air:
		scale = pow(air_boost_chain_multiplier, float(air_boost_chain))

	var scaled_impulse := direction * scale

	boost_impulse = scaled_impulse
	boost_pending = true

	# Reset decay state; magnitudes are set when applied
	boost_end_requested = false
	boost_elapsed = 0.0
	boost_total_mag = 0.0
	boost_max_remove = 0.0
	boost_removed_mag = 0.0


func _on_jet_blade_end_boost() -> void:
	## Start easing out up to 25% of the applied boost
	if boost_total_mag > 0.0 and not boost_end_requested:
		boost_end_requested = true
		boost_elapsed = 0.0


## =========================================================
## ===  Debug / utilities  ===
## =========================================================
func _handle_debug_reset(state: PhysicsDirectBodyState2D) -> void:
	if Input.is_action_just_pressed("debug_reset"):
		global_position = initial_position
		state.linear_velocity = Vector2.ZERO
		previous_velocity = Vector2.ZERO
		current_accel = Vector2.ZERO

		sticky_active = false
		sticky_input_sign = 0.0
		prev_on_ground = false

		boost_impulse = Vector2.ZERO
		boost_pending = false
		boost_dir = Vector2.ZERO
		boost_total_mag = 0.0
		boost_max_remove = 0.0
		boost_removed_mag = 0.0
		boost_end_requested = false
		boost_elapsed = 0.0

		air_boost_chain = 0
		last_boost_was_air = false


func _draw() -> void:
	var base := Vector2(0, -20)

	## Velocity (red)
	if current_velocity.length() >= 0.1:
		var start := base
		var end := start + current_velocity * arrow_scale
		draw_line(start, end, arrow_color, 2.0)
		var d := (end - start).normalized()
		var side1 := d.rotated(PI * 3.0 / 4.0) * 6.0
		var side2 := d.rotated(-PI * 3.0 / 4.0) * 6.0
		draw_line(end, end + side1, arrow_color, 2.0)
		draw_line(end, end + side2, arrow_color, 2.0)

	## Acceleration (blue)
	if current_accel.length() >= 0.1:
		var a_start := base
		var a_end := a_start + current_accel * accel_arrow_scale
		draw_line(a_start, a_end, accel_arrow_color, 2.0)
		var ad := (a_end - a_start).normalized()
		var aside1 := ad.rotated(PI * 3.0 / 4.0) * 6.0
		var aside2 := ad.rotated(-PI * 3.0 / 4.0) * 6.0
		draw_line(a_end, a_end + aside1, accel_arrow_color, 2.0)
		draw_line(a_end, a_end + aside2, accel_arrow_color, 2.0)

	## GREEN DOT: shows when sticky is active
	if sticky_direction_enabled and sticky_active:
		var dot_pos := base + Vector2(0, -12)
		draw_circle(dot_pos, 3.0, Color(0, 1, 0))
