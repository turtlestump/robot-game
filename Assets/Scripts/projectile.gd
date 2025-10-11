extends Area2D

# Reference to collision masks
const GROUND_MASK: int = 1

# Define projectile speed
@export var speed: float = 600.0
var velocity := Vector2.ZERO

var is_player: bool

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	
	velocity = Vector2.UP.rotated(rotation - PI) * speed
	
	# Perform raycasting
	var from := global_position
	var to := from + velocity * delta
	
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.exclude = [self]
	q.collision_mask = GROUND_MASK
	q.collide_with_areas = true
	q.collide_with_bodies = true
	
	var hit := space.intersect_ray(q)
	if hit:
		# Snap to impact point with a tiny offset and delete
		global_position = hit.position - hit.normal * 0.5
		queue_free()
	
	global_position = to;

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("World"):
		queue_free()

func collide() -> void:
	queue_free()
