extends PinballMotion

const Refined = preload("res://experiments/flippers/refined_motion.gd")
const Surroundings = preload("res://experiments/flippers/tests/separation_environment.gd")

var normal_new: bool = false
var refine: bool = false
var observe: bool = true
var audit_detection: bool = true
var native_response: Callable
var events: Array[Dictionary] = []
var released_inside: Array[Dictionary] = []
var detection_checks: int = 0
var detection_differences: Array[Dictionary] = []
var references: Array[Dictionary] = []
var raw_mismatches: int = 0
var raw_queries: int = 0
var discarded_true_s: float = 0.0
var discarded_legacy_s: float = 0.0
var cap: bool = false
var shots: int = 0
var _plans: Array[PinballFlipper.Swing] = []
var _initial: Dictionary = {}
var _legacy: float = 0.0
var _physical: float = 0.0
var _duration: float = 0.0
var _previous: Vector2
var _offset: Vector2
var _kind: String
var _native_actor: PhysicsBody2D
var _new_contact: bool = false
var _opportunity_ordinal: int = 0
var _surroundings: Surroundings = Surroundings.new()


func _init(target: CharacterBody2D) -> void:
	super(target)
	separate_new_contacts = false
	native_contact = _native_contact


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	events.clear()
	released_inside.clear()
	detection_differences.clear()
	references.clear()
	detection_checks = 0
	raw_mismatches = 0
	raw_queries = 0
	shots = 0
	_legacy = 0.0
	_physical = 0.0
	_duration = delta
	_previous = body.global_position
	_initial.clear()
	_plans = Refined.plans_for(swings, 4) if refine else swings
	if normal_new or observe:
		for item: PinballFlipper in flippers.items:
			var hit := item._contact_at(body.global_position, radius, _pose(item, 0), 0, 0)
			_initial[item.get_instance_id()] = not hit.is_empty()
			if observe and not hit.is_empty() and flippers.is_target_disabled(body.get_instance_id()) \
					and step_velocity(body.velocity, delta).y > 1:
				released_inside.append({"target": str(item.name), "depth_px": hit.depth})
	super.advance(delta, _plans)
	cap = events.size() == MAX_CONTACTS
	var remaining := maxf(0.0, delta - _legacy)
	discarded_legacy_s = remaining if cap else 0.0
	var free_time := remaining if not cap and remaining >= 0.000001 else 0.0
	discarded_true_s = maxf(0.0, delta - _physical - free_time) if observe and raw_mismatches == 0 else -1.0


func advance_motion(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	if observe and audit_detection and not swings.is_empty() \
			and not flippers.is_target_disabled(body.get_instance_id()):
		_detection_probe(delta, swings)
	super.advance_motion(delta, swings)


func apply_swept_contact(hit: Dictionary) -> void:
	var item: PinballFlipper = hit.flipper
	_new_contact = not _initial.get(item.get_instance_id(), false) and item._contact_at(
		body.global_position, radius, _pose(item, _legacy), 0, 0).is_empty()
	_kind = "flipper_sweep"
	_native_actor = item
	_legacy += hit.time
	_physical += hit.time
	super.apply_swept_contact(hit)
	_previous = body.global_position


func contact_separation(hit: Dictionary) -> Vector2:
	_offset = hit.normal * (maxf(0.0, hit.depth) + SEPARATION_MARGIN) if normal_new and _new_contact \
		else super.contact_separation(hit)
	return _offset


func _respond_to_flipper(hit: Dictionary) -> void:
	var incoming := body.velocity
	var shot: bool = hit.is_striking and (incoming - hit.surface_velocity).dot(hit.normal) < 0.0
	super._respond_to_flipper(hit)
	shots += int(shot)
	_capture(hit.point, hit.normal, incoming, shot, hit.flipper)


func _native_contact(collision: KinematicCollision2D) -> void:
	var incoming := body.velocity
	var remaining := maxf(0.0, _duration - _legacy)
	var motion := incoming * remaining
	var legacy_fraction := 0.0
	if motion.length_squared() > 0.000001:
		legacy_fraction = clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0, 1)
	var physical_time := remaining * legacy_fraction
	if observe:
		var parameters := PhysicsTestMotionParameters2D.new()
		parameters.from = body.global_transform
		parameters.from.origin = _previous
		parameters.motion = motion
		parameters.margin = CONTACT_MARGIN
		parameters.recovery_as_collision = true
		var raw := PhysicsTestMotionResult2D.new()
		var found := PhysicsServer2D.body_test_motion(body.get_rid(), parameters, raw)
		raw_queries += 1
		if not found or raw.get_collider_rid() != collision.get_collider_rid():
			raw_mismatches += 1
		physical_time = remaining * raw.get_collision_safe_fraction()
	_legacy += remaining * legacy_fraction
	_physical += physical_time
	_offset = collision.get_travel() - incoming * physical_time
	_kind = "native"
	_native_actor = collision.get_collider() as PhysicsBody2D
	var health: float = _native_actor.current_health if _native_actor is Enemy else 0.0
	var count := events.size()
	native_response.call(collision)
	if events.size() == count:
		_capture(collision.get_position(), collision.get_normal(), incoming, false, _native_actor)
	if observe and _native_actor is Enemy:
		events.back()["ball_damage"] = maxf(0.0, health - _native_actor.current_health)
	_previous = body.global_position


func _capture(point: Vector2, normal: Vector2, incoming: Vector2, shot: bool, actor: PhysicsBody2D) -> void:
	if not observe:
		# Needed for the same eight-contact accounting in paired observer-off checks.
		events.append({})
		return
	var event := {"kind": _kind, "target": str(actor.name), "point": _vec(point),
		"normal": _vec(normal), "position": _vec(body.global_position), "incoming": _vec(incoming),
		"velocity": _vec(body.velocity.limit_length(max_speed)), "shot": shot,
		"offset": _vec(_offset), "correction_px": _offset.length(),
		"legacy_ms": _legacy * 1000.0, "physical_path_ms": _physical * 1000.0,
		"new_contact": _new_contact if _kind == "flipper_sweep" else false}
	if _offset.length() > CONTACT_MARGIN:
		event["environment"] = _surroundings.observe(body, radius, actor,
			body.global_position - _offset, _offset, flippers, _plans, _legacy)
	events.append(event)


func _detection_probe(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	var velocity := step_velocity(body.velocity, delta)
	var near := false
	for plan: PinballFlipper.Swing in swings:
		var point := Geometry2D.get_closest_point_to_segment(plan.origin, body.global_position,
			body.global_position + velocity * delta)
		near = near or point.distance_to(plan.origin) <= plan.reach + radius
	if not near:
		return
	detection_checks += 1
	_opportunity_ordinal += 1
	var native := body.move_and_collide(velocity * delta, true, CONTACT_MARGIN, true)
	var limit := delta
	if native != null and velocity.length_squared() > 0.0:
		limit *= clampf(native.get_travel().dot(velocity * delta) / (velocity * delta).length_squared(), 0, 1)
	var coarse: Array[PinballFlipper.Swing] = []
	for source: PinballFlipper.Swing in swings:
		var plan := PinballFlipper.Swing.new()
		for property: String in ["flipper", "start_angle", "speed", "stop_time", "parent_pose", "origin", "reach"]:
			plan.set(property, source.get(property))
		coarse.append(plan)
	var refined := Refined.plans_for(coarse, 4)
	var first := flippers.first_contact(coarse, body.global_position, velocity, radius, 0, limit)
	var other := flippers.first_contact(refined, body.global_position, velocity, radius, 0, limit)
	var shot_first: bool = not first.is_empty() and first.is_striking \
		and (velocity - first.surface_velocity).dot(first.normal) < 0
	var shot_other: bool = not other.is_empty() and other.is_striking \
		and (velocity - other.surface_velocity).dot(other.normal) < 0
	if first.is_empty() != other.is_empty() or shot_first != shot_other:
		detection_differences.append({"position": _vec(body.global_position), "velocity": _vec(velocity),
			"duration": limit, "first_found": not first.is_empty(), "refined_found": not other.is_empty(),
			"first_shot": shot_first, "refined_shot": shot_other})
	if not detection_differences.is_empty() or _opportunity_ordinal % 32 == 0:
		var reference := _reference(coarse, velocity, limit, 4096)
		var check := _reference(coarse, velocity, limit, 2048)
		reference["stable"] = reference.found == check.found and (
			not reference.found or absf(reference.time - check.time) < 0.00001)
		reference["coarse_shot"] = shot_first
		reference["refined_shot"] = shot_other
		references.append(reference)


func _reference(plans: Array[PinballFlipper.Swing], velocity: Vector2, limit: float, density: int) -> Dictionary:
	# Diagnostic candidate only: it shares the production inside predicate. Confirm errors
	# with value_reference.gd before treating them as independent ground truth.
	var result := {"found": false, "shot": false, "time": limit}
	for plan: PinballFlipper.Swing in plans:
		for index: int in density + 1:
			var time := limit * float(index) / density
			var pose := plan.parent_pose * Transform2D(
				plan.start_angle + plan.speed * minf(time, plan.stop_time), plan.flipper.position)
			var omega := plan.speed if time < plan.stop_time else 0.0
			var hit := plan.flipper._contact_at(body.global_position + velocity * time,
				radius, pose, omega, flippers.power_equalization)
			if hit.is_empty(): continue
			var low := limit * maxi(0, index - 1) / density
			var high := time
			for iteration: int in 22:
				var middle := (low + high) * .5
				pose = plan.parent_pose * Transform2D(
					plan.start_angle + plan.speed * minf(middle, plan.stop_time), plan.flipper.position)
				if plan.flipper._contact_at(body.global_position + velocity * middle,
						radius, pose, 0.0, 0.0).is_empty(): low = middle
				else: high = middle
			pose = plan.parent_pose * Transform2D(
				plan.start_angle + plan.speed * minf(high, plan.stop_time), plan.flipper.position)
			hit = plan.flipper._contact_at(body.global_position + velocity * high, radius + .0005,
				pose, plan.speed if high < plan.stop_time else 0.0, flippers.power_equalization)
			if not hit.is_empty() and (not result.found or high < result.time):
				result = {"found": true, "time": high, "shot": hit.is_striking and
					(velocity - hit.surface_velocity).dot(hit.normal) < 0.0}
			break
	return result


func _pose(item: PinballFlipper, time: float) -> Transform2D:
	for plan: PinballFlipper.Swing in _plans:
		if plan.flipper == item:
			return plan.parent_pose * Transform2D(
				plan.start_angle + plan.speed * minf(time, plan.stop_time), item.position)
	return item.global_transform


static func _vec(value: Vector2) -> Array[float]:
	return [value.x, value.y]
