extends Node2D

class_name JetBlade

## Jetblade configuration (self-contained)
@export var boost_amount: float = 200.0
@export var attack_duration: float = 0.25
@export var reticle: Node2D = null

## Fuel system
@export var max_fuel: float = 100.0
@export var fuel_per_attack: float = 25.0
@export var fuel_recharge_delay: float = 0.5
@export var pre_refuel_flash: float = 0.1  # how early to emit before refueling

@onready var fuel_indicator: GPUParticles2D = $ParticleFuelIndicator
@onready var blade_area: Area2D = $BladeArea

var is_attacking: bool = false
var current_fuel: float = 0.0
var time_since_last_attack: float = 0.0
var pre_refuel_emitted: bool = false

signal melee_boost(direction: Vector2)
signal end_boost()
signal refueled()

var blade_sprite: Sprite2D = null

func _ready() -> void:
	visible = true
	set_meta("active", false)
	current_fuel = max_fuel
	set_process(true)

	# Try to automatically find a Sprite2D child (two layers down)
	for child in get_children():
		for subchild in child.get_children():
			if subchild is Sprite2D:
				blade_sprite = subchild
				break
		if blade_sprite:
			break

	if blade_area:
		blade_area.visible = false
	if blade_sprite:
		blade_sprite.visible = false

func _process(delta: float) -> void:
	if not is_attacking:
		time_since_last_attack += delta

		# Trigger pre-refuel particle emission slightly before refuel
		if not pre_refuel_emitted \
			and time_since_last_attack >= fuel_recharge_delay - pre_refuel_flash \
			and current_fuel < max_fuel:
			if fuel_indicator:
				fuel_indicator.emitting = true
			pre_refuel_emitted = true

		# Actually refuel after the delay
		if time_since_last_attack >= fuel_recharge_delay and current_fuel < max_fuel:
			current_fuel = max_fuel
			pre_refuel_emitted = false
			refueled.emit()

	_update_blade_color()

func attack() -> void:
	if is_attacking or reticle == null:
		return

	var fuel_ratio := clampf(current_fuel / max_fuel, 0.0, 1.0)
	var effective_boost := boost_amount * fuel_ratio

	is_attacking = true
	time_since_last_attack = 0.0
	pre_refuel_emitted = false

	if fuel_per_attack > 0.0:
		current_fuel = max(current_fuel - fuel_per_attack, 0.0)

	var attack_angle: float = (reticle.global_position - global_position).angle()
	rotation = attack_angle + PI / 2.0
	set_meta("active", true)

	if blade_area:
		blade_area.visible = true
	if blade_sprite:
		blade_sprite.visible = true

	if effective_boost > 0.0:
		var dir := Vector2(cos(attack_angle), sin(attack_angle))
		melee_boost.emit(dir * effective_boost)
	else:
		melee_boost.emit(Vector2.ZERO)

	await get_tree().create_timer(attack_duration).timeout
	end_boost.emit()
	set_meta("active", false)

	if blade_area:
		blade_area.visible = false
	if blade_sprite:
		blade_sprite.visible = false

	is_attacking = false

func _update_blade_color() -> void:
	if blade_sprite == null:
		return
	var fuel_ratio := clampf(current_fuel / max_fuel, 0.0, 1.0)
	var empty_color := Color(0.4, 0.0, 0.0)  # dark red
	var full_color := Color(1.0, 1.0, 1.0)   # white
	blade_sprite.modulate = full_color.lerp(empty_color, 1.0 - fuel_ratio)
