extends "res://experiments/flippers/preview_ball.gd"

var rotation_sweep: bool = true
var iterative: bool = true
var guard_enabled: bool = false
var final_response: bool = false
var shots: int = 0
var updates: int = 0
var contacts: int = 0
var native_queries: int = 0
var end_corrections: int = 0
var max_end_correction: float = 0.0
var deferred_contacts: int = 0
var cap_steps: int = 0
var extra_end_contacts: int = 0
var touched: Dictionary[String, int] = {}
var _single_response: bool = false

var _bounds: Dictionary[int, Rect2] = {}
var _poses: Dictionary[int, Transform2D] = {}


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	updates += 1
	var before := contacts
	if rotation_sweep:
		super.advance(delta, swings)
	else:
		super.advance(delta)
	if contacts - before >= MAX_CONTACTS:
		cap_steps += 1


func _advance_motion(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	if iterative:
		super._advance_motion(delta, swings)
		return
	# One response, then one final safe move. No contact-by-contact traversal
	# of the changed path; a second obstruction is deferred to the next update.
	velocity = step_velocity(velocity, delta)
	var start := global_position
	var incoming := velocity
	var motion := incoming * delta
	native_queries += 1
	var collision := move_and_collide(motion, true, CONTACT_MARGIN, true)
	var time := delta
	if collision != null:
		time = 0.0
		if motion.length_squared() > 0.000001:
			time = delta * clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0, 1)
	var hit := {}
	if not swings.is_empty():
		hit = flippers.first_contact(swings, start, incoming, radius, 0, time)
	if hit.is_empty() and collision == null:
		global_position += motion
		force_update_transform()
		return
	_single_response = true
	if not hit.is_empty() and (collision == null or hit.time < time):
		time = hit.time
		var response := hit.duplicate()
		response.time = 0.0
		_apply_swept_contact(response)
	elif collision != null:
		_resolve_contact(collision)
	_single_response = false
	velocity = velocity.limit_length(max_speed)
	var target := start + incoming * time + velocity * (delta - time)
	var temporary: Array[PinballFlipper] = []
	var restored: Array[PinballFlipper] = []
	if final_response and not (flippers as ShotGuard).is_suppressed(self):
		for swing: PinballFlipper.Swing in swings:
			remove_collision_exception_with(swing.flipper)
			restored.append(swing.flipper)
	else:
		for item: PinballFlipper in flippers.items:
			if item not in get_collision_exceptions():
				add_collision_exception_with(item)
				temporary.append(item)
	native_queries += 1
	var obstruction := move_and_collide(target - start, false, CONTACT_MARGIN, true)
	if obstruction != null:
		if final_response:
			extra_end_contacts += 1
			_resolve_at_end(obstruction)
		else:
			deferred_contacts += 1
	for item: PinballFlipper in temporary:
		remove_collision_exception_with(item)
	for item: PinballFlipper in restored:
		if item not in get_collision_exceptions():
			add_collision_exception_with(item)
	# This is explicit end-position recovery, not a hidden intermediate sweep.
	if not (flippers as ShotGuard).is_suppressed(self):
		for item: PinballFlipper in flippers.items:
			var fixed := item as FixedFlipper
			var id := fixed.get_instance_id()
			if not _bounds.has(id) or _poses[id] != fixed.global_transform \
				or not is_equal_approx(_bounds[id].end.y, fixed.fixed_bottom):
				var points := fixed.world_polygon_at(fixed.global_transform)
				var highest := minf(points[0].y, points[1].y)
				_bounds[id] = Rect2(Vector2(fixed.fixed_left, highest),
					Vector2(fixed.fixed_right - fixed.fixed_left, fixed.fixed_bottom - highest))
				_poses[id] = fixed.global_transform
			if not _bounds[id].grow(radius + SWEEP_SEPARATION).has_point(global_position):
				continue
			if fixed._contact_at(global_position, radius, fixed.global_transform, 0, 0).is_empty():
				continue
			var distance := fixed.upward_separation(global_position, radius, fixed.global_transform)
			global_position += Vector2.UP * distance
			force_update_transform()
			end_corrections += 1
			max_end_correction = maxf(max_end_correction, distance)


func _resolve_at_end(collision: KinematicCollision2D) -> void:
	var item := collision.get_collider() as PinballFlipper
	if item == null:
		_resolve_contact(collision)
		return
	var point := collision.get_position()
	var normal := collision.get_normal()
	var striking := item.is_striking(point, normal)
	var hit := {"flipper": item, "point": point, "normal": normal,
		"time": 0.0, "depth": 0.0, "pose": item.global_transform,
		"ratio": item.contact_ratio(point), "is_striking": striking,
		"surface_velocity": item.surface_velocity_at(point),
		"strike_surface_velocity": item.surface_velocity_at(point,
			flippers.power_equalization if striking else 0.0)}
	_single_response = true
	_apply_swept_contact(hit)
	_single_response = false


func _apply_swept_contact(hit: Dictionary) -> void:
	contacts += 1
	touched[hit.flipper.name] = touched.get(hit.flipper.name, 0) + 1
	super._apply_swept_contact(hit)


func _resolve_contact(collision: KinematicCollision2D) -> void:
	contacts += 1
	var collider_name: String = collision.get_collider().name
	touched[collider_name] = touched.get(collider_name, 0) + 1
	super._resolve_contact(collision)


func _start_guard(elapsed: float) -> void:
	shots += 1
	if guard_enabled:
		super._start_guard(elapsed)


func _contact_separation(hit: Dictionary) -> Vector2:
	return Vector2.ZERO if _single_response else super._contact_separation(hit)
