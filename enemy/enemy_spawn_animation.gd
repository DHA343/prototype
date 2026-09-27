class_name EnemySpawnAnimation
extends Node

signal scale_changed(scale_multiplier: float)
signal grow_finished

enum Phase {
	GROW,
	SETTLE,
	COMPLETE,
}

@export_range(0.01, 1.0, 0.01) var initial_scale: float = 0.1
@export_range(1.0, 3.0, 0.05) var peak_scale: float = 1.3
@export_range(0.01, 1.0, 0.01, "suffix:s") var grow_duration: float = 0.12
@export var grow_transition: Tween.TransitionType = Tween.TRANS_QUAD
@export var grow_ease: Tween.EaseType = Tween.EASE_OUT

@export_group("Spring", "spring_")
@export_range(1.0, 1000.0, 1.0) var spring_stiffness: float = 200.0
@export_range(0.0, 100.0, 0.1) var spring_damping: float = 10.0

var _phase: Phase = Phase.COMPLETE
var _grow_tween: Tween
var _spring: ScaleSpring = ScaleSpring.new()


func _process(delta: float) -> void:
	if _phase != Phase.SETTLE:
		return

	_spring.update(delta)
	if _spring.is_settled():
		_spring.settle()
		_phase = Phase.COMPLETE

	scale_changed.emit(_spring.value)


func play() -> void:
	cancel()

	_phase = Phase.GROW
	_spring.stiffness = spring_stiffness
	_spring.damping = spring_damping
	scale_changed.emit(initial_scale)

	_grow_tween = create_tween()
	_grow_tween.tween_method(
		scale_changed.emit, initial_scale, peak_scale, grow_duration
	).set_trans(grow_transition).set_ease(grow_ease)
	_grow_tween.finished.connect(_on_grow_tween_finished)


func cancel() -> void:
	if _grow_tween != null:
		_grow_tween.kill()
		_grow_tween = null

	_phase = Phase.COMPLETE


func _on_grow_tween_finished() -> void:
	_grow_tween = null
	_spring.start(peak_scale)
	_phase = Phase.SETTLE
	grow_finished.emit()
