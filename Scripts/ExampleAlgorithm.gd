extends RefCounted
class_name WallFollower

var mc: MicrocontrollerAPI

@export var follow_left: bool = true
@export var corner_steps: int = 30
@export var wall_threshold: float = 30.0
@export var open_side_delay_steps: int = 17
@export var stuck_threshold_steps: int = 120  # Force a turn if driving this long uninterrupted

enum State { START, DRIVING, TURNING, CORNER_DRIVE, OPEN_SIDE_DELAY }
var state: State = State.START
var _corner_steps_remaining: int = 0
var _delay_steps_remaining: int = 0
var _steps_since_last_turn: int = 0

func initialize(microcontroller: MicrocontrollerAPI) -> void:
	mc = microcontroller
	state = State.START

func step() -> void:
	match state:
		State.START:
			mc.drive_forward(0.6)
			state = State.DRIVING

		State.DRIVING:
			_steps_since_last_turn += 1
			var wall_ahead   = mc.is_wall_ahead(wall_threshold)
			var wall_on_side = mc.is_wall_left(wall_threshold) if follow_left else mc.is_wall_right(wall_threshold)

			if wall_ahead:
				mc.stop_drive()
				mc.turn(90.0 if follow_left else -90.0)
				_corner_steps_remaining = 0
				_steps_since_last_turn = 0
				state = State.TURNING
			elif not wall_on_side:
				_delay_steps_remaining = open_side_delay_steps
				state = State.OPEN_SIDE_DELAY
			elif _steps_since_last_turn >= stuck_threshold_steps:
				# Driving too long with wall on side and nothing ahead — force corner turn
				mc.stop_drive()
				mc.turn(-90.0 if follow_left else 90.0)
				_corner_steps_remaining = corner_steps
				_steps_since_last_turn = 0
				state = State.TURNING

		State.OPEN_SIDE_DELAY:
			var wall_on_side = mc.is_wall_left(wall_threshold) if follow_left else mc.is_wall_right(wall_threshold)
			if wall_on_side:
				state = State.DRIVING
			elif mc.is_wall_ahead(wall_threshold):
				mc.stop_drive()
				mc.turn(-90.0 if follow_left else 90.0)
				_corner_steps_remaining = 0
				_steps_since_last_turn = 0
				state = State.TURNING
			else:
				_delay_steps_remaining -= 1
				if _delay_steps_remaining <= 0:
					mc.stop_drive()
					mc.turn(-90.0 if follow_left else 90.0)
					_corner_steps_remaining = corner_steps
					_steps_since_last_turn = 0
					state = State.TURNING

		State.TURNING:
			if not mc.is_turning():
				mc.drive_forward(0.6)
				state = State.CORNER_DRIVE if _corner_steps_remaining > 0 else State.DRIVING

		State.CORNER_DRIVE:
			_corner_steps_remaining -= 1
			if _corner_steps_remaining <= 0:
				state = State.DRIVING
