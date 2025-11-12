extends Node2D

@onready var swing: AudioStreamPlayer2D = $Swing
@onready var refuel: AudioStreamPlayer2D = $Refuel


func _on_jet_blade_melee_boost(direction: Vector2) -> void:
	swing.pitch_scale = clamp(direction.length() / 150.0, 0.5, 1.0)
	swing.play()


func _on_jet_blade_refueled() -> void:
	refuel.play()
