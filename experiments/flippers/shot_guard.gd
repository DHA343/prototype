@tool
extends PinballFlippers

enum Mode {
	UNTIL_DESCENDING,
	TIME_OR_DESCENDING,
}

const DESCENT_SPEED: float = 1.0

@export var mode: Mode = Mode.UNTIL_DESCENDING
@export_range(5.0, 150.0, 5.0, "suffix:ms") var duration_ms: float = 40.0

var shot_count: int = 0
var descent_releases: int = 0
var time_releases: int = 0
var contact_elapsed: float = 0.0
var _states: Dictionary[int, ShotState] = {}
var _current_ball: PinballBall


func begin_step(ball: PinballBall, delta: float) -> void:
	_current_ball = ball
	contact_elapsed = 0.0
	var id := ball.get_instance_id()
	if not _states.has(id):
		return
	# Match the velocity used by the ball after this step's gravity update.
	if ball.step_velocity(ball.velocity, delta).y > DESCENT_SPEED:
		_states.erase(id)
		descent_releases += 1
	elif mode == Mode.TIME_OR_DESCENDING and _states[id].remaining <= 0.0:
		_states.erase(id)
		time_releases += 1


func finish_step(ball: PinballBall, delta: float) -> void:
	var id := ball.get_instance_id()
	if _states.has(id):
		_states[id].remaining -= delta
	_current_ball = null


func record_shot(ball: PinballBall, elapsed: float) -> void:
	var state := ShotState.new()
	state.remaining = duration_ms / 1000.0 + elapsed
	var id := ball.get_instance_id()
	_states[id] = state
	shot_count += 1
	var cleanup := forget_ball.bind(ball)
	if not ball.tree_exiting.is_connected(cleanup):
		ball.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)


func is_suppressed(ball: PinballBall) -> bool:
	return _states.has(ball.get_instance_id())


func remaining_ms(ball: PinballBall) -> float:
	var state := _states.get(ball.get_instance_id()) as ShotState
	return maxf(0.0, state.remaining * 1000.0) if state != null else 0.0


func forget_ball(ball: PinballBall) -> void:
	_states.erase(ball.get_instance_id())


func reset_stats() -> void:
	_states.clear()
	shot_count = 0
	descent_releases = 0
	time_releases = 0


func first_contact(
	swings: Array[PinballFlipper.Swing], center: Vector2, velocity: Vector2,
	radius: float, elapsed: float, duration: float,
) -> Dictionary:
	if _current_ball != null and is_suppressed(_current_ball):
		return {}
	var hit := super.first_contact(swings, center, velocity, radius, elapsed, duration)
	if not hit.is_empty():
		contact_elapsed = elapsed + hit.time
	return hit


class ShotState:
	var remaining: float = 0.0
