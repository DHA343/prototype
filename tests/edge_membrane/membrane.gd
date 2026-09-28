extends ColorRect

const SAMPLE_COUNT: int = 32
const EDGE_COUNT: int = 4

@export var target: Node2D
@export_range(0.0, 100.0, 1.0, "suffix:px") var strength: float = 50.0
@export_range(40.0, 400.0, 5.0, "suffix:px") var spread: float = 180.0
@export_range(40.0, 240.0, 5.0, "suffix:px") var depth: float = 110.0
@export_range(40.0, 320.0, 5.0, "suffix:px") var approach: float = 100.0
@export_range(40.0, 160.0, 5.0, "suffix:px") var wavelength: float = 75.0
@export_range(0.5, 5.0, 0.1, "suffix:Hz") var frequency: float = 2.2
@export_range(0.1, 0.9, 0.05) var damping: float = 0.2
@export_range(1.0, 100.0, 1.0, "suffix:px") var orb_radius: float = 32.0
@export_range(400.0, 4000.0, 100.0, "suffix:px/s") var reference_speed: float = 1500.0
@export_range(1.0, 3.0, 0.1) var max_multiplier: float = 2.0
@export_range(0.0, 1.0, 0.05) var directional_flow: float = 0.35

var _offsets: PackedFloat32Array = PackedFloat32Array()
var _velocities: PackedFloat32Array = PackedFloat32Array()
var _accelerations: PackedFloat32Array = PackedFloat32Array()
var _amplitudes: PackedFloat32Array = PackedFloat32Array()
var _flows: PackedFloat32Array = PackedFloat32Array()
var _previous_position: Vector2
var _wave_time: float = 0.0

@onready var _shader_material: ShaderMaterial = material as ShaderMaterial


func _ready() -> void:
	_offsets.resize(SAMPLE_COUNT * EDGE_COUNT)
	_velocities.resize(SAMPLE_COUNT * EDGE_COUNT)
	_accelerations.resize(SAMPLE_COUNT * EDGE_COUNT)
	_amplitudes.resize(SAMPLE_COUNT * EDGE_COUNT)
	_flows.resize(SAMPLE_COUNT * EDGE_COUNT)
	reset()


func _process(delta: float) -> void:
	var current_position := target.get_global_transform_with_canvas().origin
	var viewport_size := get_viewport_rect().size
	var elapsed := minf(delta, 0.1)
	var steps := maxi(1, ceili(elapsed / (1.0 / 240.0)))
	var step := elapsed / float(steps)
	var motion := current_position - _previous_position
	var screen_velocity := motion / maxf(delta, 0.000001)
	var outward_speed := Vector4(-screen_velocity.x, screen_velocity.x,
		-screen_velocity.y, screen_velocity.y)
	var omega := TAU * frequency
	_wave_time += elapsed
	for substep in range(steps):
		_advect(step, viewport_size)
		# Swept sampling keeps a fast crossing from skipping the approach zone.
		var point := _previous_position.lerp(current_position, float(substep + 1) / steps)
		var distances := Vector4(point.x, viewport_size.x - point.x,
			point.y, viewport_size.y - point.y)
		for edge in range(EDGE_COUNT):
			var distance: float = distances[edge]
			var pressure := 0.0
			var normal_speed := maxf(outward_speed[edge], 0.0)
			if normal_speed > 0.0:
				pressure = 1.0 - smoothstep(0.0, approach + orb_radius, distance)
				pressure *= smoothstep(-orb_radius, 0.0, distance)
			var along: float = point.y if edge < 2 else point.x
			var tangent_speed: float = screen_velocity.y if edge < 2 else screen_velocity.x
			var flow := clampf(tangent_speed * directional_flow, -600.0, 600.0)
			var speed_gain := minf(normal_speed / reference_speed, max_multiplier)
			# Normalize by distance travelled through the pressure profile, not time spent in it.
			var impulse_rate := normal_speed * pressure / (approach * 0.5 + orb_radius)
			var edge_length: float = viewport_size.y if edge < 2 else viewport_size.x
			var spacing := edge_length / float(SAMPLE_COUNT - 1)
			var coupling := pow(minf(240.0 / spacing, 100.0), 2.0)
			for sample_index in range(SAMPLE_COUNT):
				var index := edge * SAMPLE_COUNT + sample_index
				var sample_position := edge_length * sample_index / float(SAMPLE_COUNT - 1)
				var falloff := exp(-2.0 * pow((sample_position - along) / spread, 2.0))
				var acceleration := strength * omega * speed_gain * impulse_rate * falloff
				acceleration -= omega * omega * _offsets[index]
				var flow_weight := 1.0 - exp(-impulse_rate * falloff * step * 4.0)
				_flows[index] = lerpf(_flows[index], flow, flow_weight)
				acceleration -= 2.0 * damping * omega * _velocities[index]
				var left := edge * SAMPLE_COUNT + maxi(sample_index - 1, 0)
				var right := edge * SAMPLE_COUNT + mini(sample_index + 1, SAMPLE_COUNT - 1)
				acceleration += coupling * (_offsets[left] + _offsets[right] - 2.0 * _offsets[index])
				_accelerations[index] = acceleration
		for index in range(_offsets.size()):
			_velocities[index] += _accelerations[index] * step
			_offsets[index] += _velocities[index] * step
			var amplitude := Vector2(_offsets[index], _velocities[index] / omega).length()
			var limit := strength * max_multiplier
			if amplitude > limit:
				_offsets[index] *= limit / amplitude
				_velocities[index] *= limit / amplitude

	_previous_position = current_position
	for index in range(_offsets.size()):
		# Oscillation energy controls ripples without translating the entire floor outward.
		_amplitudes[index] = Vector2(_offsets[index], _velocities[index] / omega).length()
	_shader_material.set_shader_parameter(&"edge_amplitudes", _amplitudes)
	_shader_material.set_shader_parameter(&"depth", depth)
	_shader_material.set_shader_parameter(&"wavelength", wavelength)
	_shader_material.set_shader_parameter(&"wave_phase", _wave_time * omega)


func reset() -> void:
	_offsets.fill(0.0)
	_velocities.fill(0.0)
	_amplitudes.fill(0.0)
	_flows.fill(0.0)
	_wave_time = 0.0
	_previous_position = target.get_global_transform_with_canvas().origin
	_shader_material.set_shader_parameter(&"edge_amplitudes", _amplitudes)


func _advect(delta: float, viewport_size: Vector2) -> void:
	var old_offsets := _offsets.duplicate()
	var old_velocities := _velocities.duplicate()
	var old_flows := _flows.duplicate()
	for edge in range(EDGE_COUNT):
		var edge_length: float = viewport_size.y if edge < 2 else viewport_size.x
		var spacing := edge_length / float(SAMPLE_COUNT - 1)
		for sample_index in range(SAMPLE_COUNT):
			var index := edge * SAMPLE_COUNT + sample_index
			var source := sample_index - old_flows[index] * delta / spacing
			if source < 0.0 or source > SAMPLE_COUNT - 1:
				_offsets[index] = 0.0
				_velocities[index] = 0.0
				_flows[index] = 0.0
				continue
			var lower := edge * SAMPLE_COUNT + int(source)
			var upper := edge * SAMPLE_COUNT + mini(int(source) + 1, SAMPLE_COUNT - 1)
			var weight := source - floorf(source)
			_offsets[index] = lerpf(old_offsets[lower], old_offsets[upper], weight)
			_velocities[index] = lerpf(old_velocities[lower], old_velocities[upper], weight)
			_flows[index] = lerpf(old_flows[lower], old_flows[upper], weight) * exp(-delta)
