extends PinballLab

const Geometry = preload("res://experiments/flippers/tests/value_geometry.gd")

var inspect_respawn: bool = true
var require_clear_respawn: bool = false
var occupied_respawns: int = 0
var blocked_ticks: int = 0
var max_blocked_run: int = 0
var respawn_depth_max: float = 0.0
var _blocked_run: int = 0


func reset_ball() -> void:
	if not ball.active and (inspect_respawn or require_clear_respawn):
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = (ball.get_node("CollisionShape2D") as CollisionShape2D).shape
		query.transform = Transform2D(0.0, _spawn_position)
		query.collision_mask = ball.collision_mask
		query.margin = PinballMotion.CONTACT_MARGIN
		query.exclude = [ball.get_rid()]
		var blockers := ball.get_world_2d().direct_space_state.intersect_shape(query, 32)
		if not blockers.is_empty():
			for hit: Dictionary in blockers:
				respawn_depth_max = maxf(respawn_depth_max, Geometry.depth(hit.collider, _spawn_position, ball.radius))
			if require_clear_respawn:
				blocked_ticks += 1
				_blocked_run += 1
				max_blocked_run = maxi(max_blocked_run, _blocked_run)
				return
			occupied_respawns += 1
	_blocked_run = 0
	super.reset_ball()
