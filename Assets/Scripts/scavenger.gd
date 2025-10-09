extends CharacterBody2D

@export var ProjectileScene: PackedScene
@export var player: Node2D
@export var hover_amplitude: float
@export var hover_frequency: float
@export var attack_interval: float

# Beginning point for sine wave
var rest_position: Vector2
var hover_timer: float
var attack_timer: float

func _ready() -> void:
	rest_position = global_position

func _physics_process(delta: float) -> void:
	
	# Increase timers
	hover_timer += delta
	attack_timer += delta
	
	# Hover (sine wave)
	var offset_y := hover_amplitude * sin(hover_frequency * hover_timer)
	global_position.y = rest_position.y + offset_y
	
	# Fire intermittently
	if attack_timer >= attack_interval:
		attack_timer = 0.0
		shoot()
	
func shoot() -> void:
	
	# Create projectile
	var instance: Area2D = ProjectileScene.instantiate()
	get_parent().add_child(instance)
	
	instance.global_position = global_position
	
	# Aiming
	instance.rotation = (player.global_position - instance.global_position).normalized().angle() - PI / 2
