extends Area2D

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("Projectile") && area.is_player:
		area.collide()
