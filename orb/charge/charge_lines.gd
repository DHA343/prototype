class_name ChargeLines
extends GPUParticles2D

const LINE_TEXTURE := preload("res://orb/charge/charge_line.svg")

@export_range(0, 64, 1) var start_line_count: int = 6
@export_range(1, 64, 1) var end_line_count: int = 24
@export_range(32.0, 200.0, 1.0, "suffix:px") var inner_radius: float = 50.0
@export_range(64.0, 400.0, 1.0, "suffix:px") var outer_radius: float = 137.0
@export_range(0.0, 100.0, 1.0, "suffix:px") var spawn_radius_variation: float = 24.0
@export_range(50.0, 500.0, 10.0, "suffix:px/s") var min_inward_speed: float = 170.0
@export_range(50.0, 500.0, 10.0, "suffix:px/s") var max_inward_speed: float = 260.0
@export_range(0.1, 2.0, 0.05, "suffix:s") var particle_lifetime: float = 0.5
@export_range(0.1, 2.0, 0.05) var min_length_scale: float = 0.65
@export_range(0.1, 2.0, 0.05) var max_length_scale: float = 1.25
@export var color: Color = Color(0.75, 0.95, 1.0, 0.85)

var _charge: OrbCharge


func _ready() -> void:
	_configure_particles()
	emitting = false
	visible = false


func setup(charge: OrbCharge) -> void:
	assert(charge != null, "charge must not be null.")
	assert(_charge == null, "ChargeLines must not be setup more than once.")

	_charge = charge
	_charge.started.connect(_on_charge_started)
	_charge.level_changed.connect(_on_charge_level_changed)
	_charge.released.connect(_on_charge_released)


func _on_charge_started() -> void:
	visible = true
	emitting = true
	restart()


func _on_charge_level_changed(level: float) -> void:
	var strength := lerpf(0.25, 1.0, level)
	amount_ratio = lerpf(float(start_line_count) / float(end_line_count), 1.0, level)
	self_modulate = Color(1.0, 1.0, 1.0, strength)


func _on_charge_released(_level: float) -> void:
	emitting = false
	visible = false


func _configure_particles() -> void:
	assert(inner_radius < outer_radius, "inner_radius must be less than outer_radius.")
	assert(start_line_count <= end_line_count, "start_line_count must not exceed end_line_count.")
	assert(min_inward_speed <= max_inward_speed, "min_inward_speed must not exceed max_inward_speed.")
	assert(min_length_scale <= max_length_scale, "min_length_scale must not exceed max_length_scale.")

	amount = end_line_count
	amount_ratio = float(start_line_count) / float(end_line_count)
	lifetime = particle_lifetime
	preprocess = particle_lifetime
	randomness = 0.6
	local_coords = true
	interpolate = true
	visibility_rect = Rect2(Vector2.ONE * -outer_radius, Vector2.ONE * outer_radius * 2.0)
	texture = LINE_TEXTURE

	var particle_material := ParticleProcessMaterial.new()
	particle_material.particle_flag_disable_z = true
	particle_material.particle_flag_align_y = true
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	particle_material.emission_ring_axis = Vector3.FORWARD
	particle_material.emission_ring_radius = outer_radius
	particle_material.emission_ring_inner_radius = maxf(outer_radius - spawn_radius_variation, inner_radius)
	particle_material.radial_velocity_min = -max_inward_speed
	particle_material.radial_velocity_max = -min_inward_speed
	particle_material.gravity = Vector3.ZERO
	particle_material.scale_min = min_length_scale
	particle_material.scale_max = max_length_scale
	particle_material.lifetime_randomness = 0.2
	particle_material.color = color
	particle_material.alpha_curve = _create_alpha_curve()
	process_material = particle_material


func _create_alpha_curve() -> CurveTexture:
	var alpha_curve := Curve.new()
	alpha_curve.add_point(Vector2(0.0, 0.0))
	alpha_curve.add_point(Vector2(0.12, 1.0))
	alpha_curve.add_point(Vector2(0.72, 1.0))
	alpha_curve.add_point(Vector2(1.0, 0.0))

	var alpha_texture := CurveTexture.new()
	alpha_texture.curve = alpha_curve
	return alpha_texture
