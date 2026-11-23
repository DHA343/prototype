extends Enemy

const Geometry = preload("res://experiments/flippers/tests/value_geometry.gd")

@export var inspect_collisions: bool = true

var step_count: int = 0
var probe_count: int = 0
var overlap_count: int = 0
var max_depth: float = 0.0


func advance(delta: float) -> void:
	if not inspect_collisions:
		super.advance(delta)
		return
	var before := global_position
	var requested := (_movement_velocity + knockback_velocity()) * delta + crowd_motion
	super.advance(delta)
	step_count += 1
	if global_position.distance_to(before + requested) <= 0.03:
		return
	probe_count += 1
	var circle := CircleShape2D.new()
	circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = global_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	var deepest := 0.0
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 32):
		deepest = maxf(deepest, Geometry.depth(hit.collider, global_position, radius))
	overlap_count += int(deepest > 0.0)
	max_depth = maxf(max_depth, deepest)
