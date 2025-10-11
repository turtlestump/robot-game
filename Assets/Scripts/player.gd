extends	CharacterBody2D

# Player statistics
const SPEED	= 250.0
const JUMP_VELOCITY	= -400.0
const DAMPING =	40.0
const AIR_ACCELERATION = 20.0
const GRAPPLE_BOOST	= 200.0

@export var hud: CanvasLayer 

@export var max_health = 6.0

# Prepare aiming / shooting	elements
@onready var ProjectileScene: PackedScene =	preload("res://Assets/Scenes/projectile.tscn")
@onready var grapple_line: Line2D =	$Grapple/Line2D
@export	var	reticle: Node2D

# Prepare grappling elements
@export	var	movement_type := MovementType.WALK
var	grapple_point: Vector2 = Vector2.ZERO
var	initial_position: Vector2

enum MovementType {
	WALK,
	SWING
}

func _ready() -> void:
	initial_position = global_position

func _physics_process(delta: float)	-> void:
	if Input.is_action_just_pressed("debug_reset"):
		global_position	= initial_position
		velocity = Vector2.ZERO
		movement_type =	MovementType.WALK
		grapple_line.begin_retract()
		print("Player reset	to initial position.")

	# Test damage and heal
	if Input.is_action_just_pressed("debug_damage"):
		_take_damage(1)
	if Input.is_action_just_pressed("heal"):
		_heal(1)

	if movement_type == MovementType.WALK:
		# Add the gravity.
		if not is_on_floor():
			velocity += get_gravity() *	delta

		# Handle jump.
		if Input.is_action_just_pressed("jump")	and	is_on_floor():
			velocity.y = JUMP_VELOCITY

		# Get the input	direction and handle the movement/deceleration.
		# As good practice,	you	should replace UI actions with custom gameplay actions.
		var	direction := Input.get_axis("move_left", "move_right")
		if direction:
			if abs(velocity.x) < abs(direction * SPEED)	|| sign(velocity.x)	!= sign(direction):
				if is_on_floor():
					velocity.x = direction * SPEED
				else:
					velocity.x = move_toward(velocity.x, direction * SPEED,	AIR_ACCELERATION)
		else:
			velocity.x = move_toward(velocity.x, 0, DAMPING)

	elif movement_type == MovementType.SWING:
		# Get tangential vector	from the current position to the grapple point
		var	arc_vector := (grapple_point - global_position).normalized()
		var	tangent_vector := Vector2(-arc_vector.y, arc_vector.x)

		# Project current velocity onto	the	tangent	vector
		var	tangential_velocity	:= velocity.dot(tangent_vector)
		# Apply	gravity	to the tangential velocity
		tangential_velocity	+= get_gravity().dot(tangent_vector) * delta
		# Apply	grapple	boost	if the player is holding left/right
		var	input_direction	:= Input.get_axis("move_left", "move_right")
		tangential_velocity	+= input_direction * GRAPPLE_BOOST * delta

		# Apply	tangential velocity	to the player
		velocity = tangent_vector *	tangential_velocity
		
	# Attack
	if Input.is_action_just_pressed("shoot"):
		shoot()
		
	# Grapple
	if Input.is_action_just_pressed("grapple"):
		grapple_line.fire(reticle.global_position)

	if Input.is_action_just_released("grapple"):
		grapple_line.begin_retract()

	# If the grapple input is not held and the player is swinging, release the grapple.
	if !Input.is_action_pressed("grapple") and movement_type == MovementType.SWING:
		movement_type =	MovementType.WALK
		grapple_line.begin_retract()
		# Add a	small boost	in the direction of the	current	velocity
		velocity += velocity.normalized() *	GRAPPLE_BOOST *	0.2

	if movement_type == MovementType.SWING && is_on_floor():
		# If the player	is swinging	and	touches	the	ground,	switch to WALK mode.
		print("Landed while	swinging, switching	to WALK	mode.")
		movement_type =	MovementType.WALK
		grapple_line.begin_retract()

	move_and_slide()

func shoot() -> void:
	# Create projectile
	var	instance := ProjectileScene.instantiate()
	get_parent().add_child(instance)
	
	if instance	is Node2D:
		instance.global_position = global_position
		instance.rotation =	reticle.global_position.angle_to_point(position) + PI /	2


func _on_grappled(center_point:	Vector2) -> void:
	if is_on_floor():
		# Don’t	allow a	latched	state on ground; retract right away
		grapple_line.begin_retract()
		return
	movement_type =	MovementType.SWING
	grapple_point =	center_point

func _take_damage(amount: int) -> void:
	hud.remove_health(amount)

func _heal(amount: int) -> void:
	hud.add_health(amount)