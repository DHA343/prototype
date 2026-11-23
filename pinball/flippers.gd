@tool
class_name PinballFlippers
extends Node2D

@export_group("Shape")
## Diameter of the round root. The wall socket remains on its upper tangent.
@export_range(12.0, 72.0, 1.5, "suffix:px") var root_width: float = 36.0:
	set(value):
		root_width = value
		_refresh_shape()
## Diameter of the round tip, capped at Root Width. The cap extends beyond Tip Socket.
@export_range(6.0, 48.0, 1.5, "suffix:px") var tip_width: float = 18.0:
	set(value):
		tip_width = value
		_refresh_shape()

@export_group("Flipper Motion")
@export_range(5.0, 80.0, 1.0, "suffix:deg") var swing_angle: float = 45.0
@export_range(90.0, 1440.0, 10.0, "suffix:deg/s") var raise_speed: float = 720.0
@export_range(90.0, 1440.0, 10.0, "suffix:deg/s") var return_speed: float = 420.0

@export_group("Shot Direction")
## Measured from world up on the left flipper; the right mirrors the angle.
@export_range(-70.0, 70.0, 1.0, "suffix:deg") var root_angle: float = -20.0
@export_range(-70.0, 70.0, 1.0, "suffix:deg") var tip_angle: float = 40.0

@export_group("Shot Power")
## Raises the effective lever arm toward the tip: 0 uses the contact point, 1 uses the tip.
@export_range(0.0, 1.0, 0.01) var power_equalization: float = 0.5

@export_group("Restitution")
@export_range(0.0, 1.0, 0.01) var restitution: float = 0.1

@export_group("Shot Recovery")
@export var pass_until_descending: bool = false

var _passing_targets: Dictionary[int, bool] = {}

@onready var items: Array[PinballFlipper] = [$LeftFlipper, $RightFlipper]


func _ready() -> void:
	_refresh_shape()


func advance(delta: float, left_pressed: bool, right_pressed: bool) -> void:
	var inputs: Array[bool] = [left_pressed, right_pressed]
	for side: int in 2:
		if items[side].visible:
			items[side].advance(delta, inputs[side], swing_angle, raise_speed, return_speed)


func plan_motion(left_pressed: bool, right_pressed: bool) -> Array[PinballFlipper.Swing]:
	var swings: Array[PinballFlipper.Swing] = []
	var pressed: Array[bool] = [left_pressed, right_pressed]
	for flipper: PinballFlipper in items:
		if not flipper.visible:
			continue
		var held := pressed[flipper.side]
		var swing := flipper.plan_motion(held, swing_angle, raise_speed if held else return_speed)
		if swing != null:
			swings.append(swing)
	return swings


func first_contact(
	swings: Array[PinballFlipper.Swing], center: Vector2, velocity: Vector2,
	radius: float, elapsed: float, duration: float,
) -> Dictionary:
	var first := {}
	var first_swing: PinballFlipper.Swing
	for swing: PinballFlipper.Swing in swings:
		var hit := swing.sweep(center, velocity, radius, elapsed, duration, power_equalization)
		if not hit.is_empty() and (first.is_empty() or hit.time < first.time):
			first = hit
			first_swing = swing
	if first_swing != null:
		first.swing = first_swing
	return first


func reset_input() -> void:
	_passing_targets.clear()
	for flipper: PinballFlipper in items:
		flipper.reset_motion()


func refresh_target(target: CharacterBody2D, next_velocity_y: float) -> void:
	if next_velocity_y > 1.0:
		release_target(target.get_instance_id())


func disable_target(target: CharacterBody2D) -> bool:
	if not pass_until_descending:
		return false
	var id := target.get_instance_id()
	_passing_targets[id] = true
	var cleanup := release_target.bind(id)
	if not target.tree_exiting.is_connected(cleanup):
		target.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)
	return true


func release_target(id: int) -> void:
	_passing_targets.erase(id)


func is_target_disabled(id: int) -> bool:
	return pass_until_descending and _passing_targets.has(id)


func motion_step_limit(ball_radius: float, left_pressed: bool, right_pressed: bool) -> float:
	var limit := INF
	var inputs: Array[bool] = [left_pressed, right_pressed]
	for side: int in 2:
		if not items[side].visible:
			continue
		var speed := raise_speed if inputs[side] else return_speed
		limit = minf(limit, items[side].step_limit(ball_radius, inputs[side], swing_angle, speed))
	return limit


func direct_shot(
	physical_velocity: Vector2, contact_ratio: float, side: int, normal: Vector2,
) -> Vector2:
	var direction := _outward_direction(contact_ratio, side, normal)
	return direction * physical_velocity.length() if direction != Vector2.ZERO else physical_velocity


## Zero means the shot uses physical reflection at the powered surface speed.
func outward_shot_direction(hit: Dictionary) -> Vector2:
	var flipper: PinballFlipper = hit.flipper
	return _outward_direction(hit.ratio, flipper.side, hit.normal)


func shot_velocity(incoming: Vector2, hit: Dictionary, direction: Vector2) -> Vector2:
	var reflected := PinballMotion.reflected_velocity(
		incoming, hit.normal, restitution, hit.strike_surface_velocity)
	return direction * reflected.length() if direction != Vector2.ZERO else reflected


func shot_direction(contact_ratio: float, side: int) -> Vector2:
	var angle := lerpf(root_angle, tip_angle, clampf(contact_ratio, 0.0, 1.0))
	return Vector2.UP.rotated(deg_to_rad(angle * (1.0 if side == 0 else -1.0)))


func _outward_direction(contact_ratio: float, side: int, normal: Vector2) -> Vector2:
	var direction := shot_direction(contact_ratio, side)
	return direction if direction.dot(normal) > 0.0 else Vector2.ZERO


func _refresh_shape() -> void:
	if not is_node_ready():
		return
	for flipper: PinballFlipper in items:
		flipper.set_widths(root_width, tip_width)
