extends	CharacterBody2D


const SPEED	= 250.0
const JUMP_VELOCITY	= -400.0
const DAMPING = 40.0

# Prepare aiming / shooting	elements
@export	var	reticle: Node2D
@onready var ProjectileScene: PackedScene =	preload("res://Assets/Scenes/projectile.tscn")
@onready var grapple_line: Line2D =	$Grapple/Line2D

@export	var	movement_type := MovementType.WALK
var	grapple_point: Vector2 = Vector2.ZERO

enum MovementType {
	WALK,
	SWING
}

func _physics_process(delta: float)	-> void:

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
				velocity.x = direction * SPEED
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

		# Apply	tangential velocity	to the player
		velocity = tangent_vector *	tangential_velocity
		
	# Attack
	if Input.is_action_just_pressed("shoot"): 
		shoot()
		
	# Grapple
	if Input.is_action_just_pressed("grapple"):
		grapple()

	# If the grapple input is not held and the player is swinging, release the grapple.
	if !Input.is_action_pressed("grapple") and movement_type == MovementType.SWING:
		movement_type =	MovementType.WALK
		grapple_line.retract(delta)

	move_and_slide()

func shoot() -> void:
	# Create projectile
	var	instance := ProjectileScene.instantiate()
	get_parent().add_child(instance)
	
	if instance	is Node2D:
		instance.global_position = global_position
		instance.rotation =	reticle.global_position.angle_to_point(position) + PI /	2
		
func grapple() -> void:
	grapple_line.fire(reticle.global_position)


func _on_grappled(center_point:	Vector2) -> void:
	movement_type =	MovementType.SWING
	grapple_point =	center_point
