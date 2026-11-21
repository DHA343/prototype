extends PinballMotion

const Contact = preload("res://experiments/flippers/contact.gd")


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	super.advance(delta, Contact.complete_motion(body, flippers.items, swings))
