extends "res://experiments/flippers/tests/matrix_ball.gd"

var internal_releases: int = 0
var shots_on_release: int = 0


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	var internal := false
	if (flippers as ShotGuard).is_suppressed(self) \
		and step_velocity(velocity, delta).y > ShotGuard.DESCENT_SPEED:
		for item: PinballFlipper in flippers.items:
			if not item._contact_at(global_position, radius, item.global_transform, 0, 0).is_empty():
				internal = true
	var before := shots
	super.advance(delta, swings)
	if internal:
		internal_releases += 1
		shots_on_release += shots - before
