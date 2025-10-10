extends	CanvasLayer

@export	var	health:	int	= 5
@export	var	max_health:	int	= 5

@onready var segment_template: TextureRect = $HealthBar/SegmentTemplate

# Called when the node enters the scene	tree for the first time.
func _ready() -> void:
	pass


# Called every frame. 'delta' is the elapsed time since	the	previous frame.
func _process(delta: float)	-> void:
	pass

func take_damage(amount: int) -> void:
	health -= amount

func add_health(amount:	int) -> void:
	health += amount

	# Clone	the	segment	template and displace to correct position
	

	if health >	max_health:
		health = max_health