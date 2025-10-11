extends CharacterBody2D

@export var ProjectileScene: PackedScene
@export var shield: Node2D
@export var player: Node2D
@export var hover_amplitude: float
@export var hover_frequency: float
@export var attack_interval: float
var player_dir: Vector2

# Beginning point for sine wave
var rest_position: Vector2
var hover_timer: float
var attack_timer: float

func _ready() -> void:
	rest_position = global_position

func _physics_process(delta: float) -> void:
	
	player_dir = player.global_position - global_position
	
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
		
	shield.global_rotation = lerp_angle(shield.global_rotation, (player_dir).angle() + PI / 2, delta * 2)
	
func shoot() -> void:
	
	# Create projectile
	var instance: Area2D = ProjectileScene.instantiate()
	get_parent().add_child(instance)
	
	instance.global_position = global_position
	
	# Aiming
	instance.rotation = (player_dir).normalized().angle() - PI / 2
