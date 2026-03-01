extends RefCounted
class_name ExampleAlgorithm

var mc: MicrocontrollerAPI

enum State { START, DRIVING, TURNING }
var state: State = State.START

func initialize(microcontroller: MicrocontrollerAPI) -> void:
	mc = microcontroller
	state = State.START  # Reset state machine

func step() -> void:
	match state:
		State.START:
			mc.drive_forward(0.6)
			state = State.DRIVING

		State.DRIVING:
			if mc.is_wall_ahead():
				mc.stop_drive()
				mc.turn(-90)
				state = State.TURNING

		State.TURNING:
			if not mc.is_turning():
				mc.drive_forward(0.6)
				state = State.DRIVING
