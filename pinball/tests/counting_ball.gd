extends PinballBall

var updates: int = 0
var last_delta: float = 0.0


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	updates += 1
	last_delta = delta
	super.advance(delta, swings)
