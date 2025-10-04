extends RigidBody2D

# Define projectile speed
@export var speed: float = 800.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.d

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var forward := global_transform.y.normalized()
	global_position += forward * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("World"):
		body.queue_free()
