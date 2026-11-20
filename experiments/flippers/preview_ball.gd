extends PinballBall

const FixedFlipper = preload("res://experiments/flippers/fixed_flipper.gd")
const ShotGuard = preload("res://experiments/flippers/shot_guard.gd")

var max_separation: float = 0.0
var contact_count: int = 0
var _guard_exceptions: Array[PinballFlipper] = []


func reset_at(point: Vector2, initial_velocity: Vector2 = Vector2.ZERO) -> void:
	if flippers is ShotGuard:
		(flippers as ShotGuard).forget_ball(self)
	super.reset_at(point, initial_velocity)
	max_separation = 0.0
	contact_count = 0


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	var guard := flippers as ShotGuard
	if guard == null or not active:
		super.advance(delta, swings)
		return
	guard.begin_step(self, delta)
	# Leave moving bodies to the base sweep path. Excluding them before super.advance
	# would also remove their Swing from the base ball's active list.
	if guard.is_suppressed(self):
		var moving: Array[PinballFlipper] = []
		for swing: PinballFlipper.Swing in swings:
			moving.append(swing.flipper)
		for flipper: PinballFlipper in guard.items:
			if flipper not in moving:
				_exclude_flipper(flipper)
	super.advance(delta, swings)
	for flipper: PinballFlipper in _guard_exceptions:
		remove_collision_exception_with(flipper)
	_guard_exceptions.clear()
	guard.finish_step(self, delta)


func _apply_swept_contact(hit: Dictionary) -> void:
	var shots_before := _struck_flippers.size()
	super._apply_swept_contact(hit)
	if _struck_flippers.size() > shots_before and flippers is ShotGuard:
		_start_guard((flippers as ShotGuard).contact_elapsed)


func _resolve_contact(collision: KinematicCollision2D) -> void:
	var flipper := collision.get_collider() as PinballFlipper
	var shot := false
	if flipper != null:
		var point := collision.get_position()
		var normal := collision.get_normal()
		shot = flipper.is_striking(point, normal) \
			and (velocity - flipper.surface_velocity_at(point)).dot(normal) < 0.0
	super._resolve_contact(collision)
	if shot and flippers is ShotGuard:
		_start_guard(0.0)


func _start_guard(elapsed: float) -> void:
	var guard := flippers as ShotGuard
	guard.record_shot(self, elapsed)
	# Apply immediately: a stationary opposite flipper can be reached in the
	# remainder of the very step in which the shot was made.
	for flipper: PinballFlipper in guard.items:
		_exclude_flipper(flipper)


func _exclude_flipper(flipper: PinballFlipper) -> void:
	if flipper not in get_collision_exceptions():
		add_collision_exception_with(flipper)
		_guard_exceptions.append(flipper)


func _contact_separation(hit: Dictionary) -> Vector2:
	var flipper := hit.flipper as FixedFlipper
	var center: Vector2 = global_position + velocity * hit.time
	var distance := flipper.upward_separation(center, radius, hit.pose)
	max_separation = maxf(max_separation, distance)
	contact_count += 1
	return Vector2.UP * distance
