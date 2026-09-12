class_name Hitbox
extends Area2D

signal hurtbox_detected(hurtbox: Hurtbox)


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	var hurtbox := area as Hurtbox
	if hurtbox == null:
		return

	hurtbox_detected.emit(hurtbox)
