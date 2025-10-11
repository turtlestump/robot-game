extends	CanvasLayer


@export	var	health:	int	= 0
@export	var	max_health:	int	= 5
@export	var	base_health_segment_pos: Vector2 = Vector2(-24.0, -15.0)
@export	var	health_segment_spacing:	float =	19.0

@onready var notch_scene: PackedScene =	preload("res://Assets/Scenes/health_notch.tscn")
@onready var screw_body: TextureRect = $Root/TopBar/HBoxContainer/LeftGroup/Health/ScrewBody
@onready var screw_head: TextureRect = $Root/TopBar/HBoxContainer/LeftGroup/Health/ScrewHead

# Called when the node enters the scene	tree for the first time.
func _ready() -> void:
	add_health(max_health)


# Called every frame. 'delta' is the elapsed time since	the	previous frame.
func _process(delta: float)	-> void:
	# Set Screw Head z-index to be greater than all segments
	screw_head.z_index = screw_body.get_child_count() + 1

	# Check all segments for metadata "delete" true and remove them after animation
	for i in range(screw_body.get_child_count() - 1, -1, -1):
		var child = screw_body.get_child(i)
		if child.has_meta("delete") and child.get_meta("delete"):
			var anim_player = child.get_node("TextureRect/AnimationPlayer") as AnimationPlayer
			if not anim_player.is_playing():
				screw_body.remove_child(child)
				child.queue_free()


func remove_health(amount: int) -> void:
	health -= amount

	if health < 0:
		health = 0

	for i in range(amount):
		if screw_body.get_child_count() > 0:
			# Get next last segment where metadata "delete" is not true
			var last_segment = null
			for j in range(screw_body.get_child_count() - 1, -1, -1):
				var child = screw_body.get_child(j)
				if not child.has_meta("delete") or not child.get_meta("delete"):
					last_segment = child
					break
			if last_segment == null:
				break

			# Play fade animation backwards
			var anim_player = last_segment.get_node("TextureRect/AnimationPlayer") as AnimationPlayer
			anim_player.play("fade_out")

			# Decrease z-index of all remaining segments by 1
			for j in range(screw_body.get_child_count()):
				var child = screw_body.get_child(j)
				if child != last_segment and (not child.has_meta("delete") or not child.get_meta("delete")):
					child.z_index -= 1

			# Set metadata "delete" to true
			last_segment.set_meta("delete", true)

func add_health(amount:	int) -> void:
	var last_health = health
	health += amount

	if health >	max_health:
		health = max_health
		amount = max_health - last_health

	for	i in range(amount):
		var	new_segment	= notch_scene.instantiate()
		new_segment.position = base_health_segment_pos + Vector2(health_segment_spacing * (last_health + i), 0)
		screw_body.add_child(new_segment)
		# Increase z-index of all previous segments by 1
		for j in range(screw_body.get_child_count() - 1):
			var child = screw_body.get_child(j)
			child.z_index += 1

		# Play fade animation forwards
		var anim_player = new_segment.get_node("TextureRect/AnimationPlayer") as AnimationPlayer
		anim_player.play("fade_in")
