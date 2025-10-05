extends CharacterBody2D


const SPEED = 250.0
const JUMP_VELOCITY = -400.0

# Prepare aiming / shooting elements
@export var reticle: Node2D
@onready var ProjectileScene: PackedScene = preload("res://Assets/Scenes/projectile.tscn")
@onready var grapple_line: Line2D = $Grapple/Line2D

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("move_left", "move_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		
	# Attack
	if Input.is_action_just_pressed("shoot"): 
		shoot()
		
	# Grapple
	if Input.is_action_just_pressed("grapple"):
		grapple()

	move_and_slide()

func shoot() -> void:
	# Create projectile
	var instance := ProjectileScene.instantiate()
	get_parent().add_child(instance)
	
	if instance is Node2D:
		instance.global_position = global_position
		instance.rotation = reticle.global_position.angle_to_point(position) + PI / 2
		
func grapple() -> void:
	grapple_line.fire(reticle.global_position)
