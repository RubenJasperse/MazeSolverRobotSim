extends Node
class_name MicrocontrollerAPI

# IMPORTANT: _<variable_name> means this variable is private and should not be used outside this script!!

# References
var rc: CharacterBody2D

# Configuration
@export var sensors_node: Node  # Reference to RobotSensors node
@export var wall_detection_threshold: float = 10.0
@export var _speed_multiplier: float = 200.0 # For simulation - will be replaced with voltages on real robot

const SENSOR_STALE_THRESHOLD_MS: float = 500.0
const TOF_MAX_RANGE: float = 150.0

# Internal state
var last_sensor_update_time: float = 0.0
var sensor_data_cache: Dictionary = {}
var is_initialized: bool = false
var error_state: bool = false
var error_message: String = ""

# Cached flat sensor values
var _tof_front: float = TOF_MAX_RANGE
var _tof_left: float = TOF_MAX_RANGE
var _tof_right: float = TOF_MAX_RANGE
var _gyro_angle: float = 0.0
var _gyro_angular_velocity: float = 0.0
var _gyro_absolute_angle: float = 0.0
var _gyro_calibrated: bool = false
var _accel_x: float = 0.0
var _accel_y: float = 0.0
var _mag_heading: float = 0.0

# Motor state
var left_motor_speed: float = 0.0
var right_motor_speed: float = 0.0

# --------------------------------------------------------------------
# DRIVE STATE
# --------------------------------------------------------------------

# Whether drive_forward/backward is active
var _driving: bool = false

var _drive_base_speed: float = 0.0

# Heading (gyro angle) to maintain while driving
var _drive_target_heading: float = 0.0

# PID state for heading correction; TODO: tune these 3 for real robot
var _pid_kp: float = 0.8   # Proportional gain
var _pid_ki: float = 0.02  # Integral gain
var _pid_kd: float = 0.1   # Derivative gain

var _pid_integral: float = 0.0
var _pid_last_error: float = 0.0

# Max correction that is added/subtracted from motor (as fraction of base speed)
# e.g. 0.25 means correction is clamped to +-25% of the base speed
const PID_CORRECTION_LIMIT: float = 0.25

# --------------------------------------------------------------------
# TURN STATE
# --------------------------------------------------------------------

# Signal so callers can await turn completing
signal turn_completed

# Blocks new turn calls
var _turning: bool = false

# Make coroutine exit silently without emitting turn_completed
var _turn_cancelled: bool = false

const TURN_ANGLE_TOLERANCE: float = 0.25 # deg

# Proportional gain for slowing down as approaching target angle during turn
const TURN_P_GAIN: float = 0.05

# Motor speed during turn proportional to base speed
var turn_speed: float = 0.5

# Min motor speed during turn so robot doesn't stallt
const TURN_MIN_SPEED: float = 0.05

# Motors cut out this many degrees before the target to let momentum carry the robot.
# 0.0 for because overshoot not simulated
# TODO: Tune when adding damping/settle logic for real robot
const TURN_BRAKE_MARGIN: float = 0.0

# --------------------------------------------------------------------
# INITIALIZATION
# --------------------------------------------------------------------

func _ready():
	initialize()

func initialize():
	await get_tree().process_frame

	rc = get_parent()

	# Validate RobotController
	if not rc or not rc.has_method("set_motor_speeds"):
		push_error("RobotController node not found or missing set_motor_speed method")
		enter_error_state("RobotController node missing during initialization")
		return

	# Validate Sensors node
	if not sensors_node or not sensors_node.has_method("get_sensor_data"):
		push_error("Sensors node not found or missing get_sensor_data method")
		enter_error_state("Sensor node missing during initialization")
		return

	print("Microcontroller API initialized")
	is_initialized = true
	calibrate_sensors()

func _process(delta: float) -> void:
	if error_state:
		return

	update_sensors()
	_process_drive_pid(delta)

# --------------------------------------------------------------------
# ERROR HANDLING
# --------------------------------------------------------------------

func enter_error_state(message: String):
	error_state = true
	error_message = message
	stop_motors()
	_driving = false
	push_error("Microcontroller ERROR: " + message)

func clear_error_state():
	error_state = false
	error_message = ""
	print("Microcontroller error cleared")

func is_in_error_state() -> bool:
	return error_state

func get_error_message() -> String:
	return error_message

# --------------------------------------------------------------------
# SENSOR POLLING
# --------------------------------------------------------------------

func update_sensors() -> bool:
	if not is_initialized or not sensors_node:
		enter_error_state("Sensors not initialized")
		return false

	if error_state:
		return false

	var new_data = sensors_node.get_sensor_data()

	if not validate_sensor_data(new_data):
		enter_error_state("Invalid sensor data detected")
		return false

	sensor_data_cache = new_data
	last_sensor_update_time = Time.get_ticks_msec()

	# Update flat cache to avoid deep copies on EVERY read
	var tof = new_data["tof"]
	_tof_front = tof["front"]
	_tof_left  = tof["left"]
	_tof_right = tof["right"]

	var gyro = new_data["imu"]["gyro"]
	_gyro_angle = gyro.get("angle", 0.0)
	_gyro_angular_velocity = gyro.get("angular_velocity", 0.0)
	_gyro_absolute_angle = gyro.get("absolute_angle", 0.0)
	_gyro_calibrated = gyro.get("calibrated", false)

	var accel = new_data["imu"]["accel"]
	_accel_x = accel.get("x", 0.0)
	_accel_y = accel.get("y", 0.0)

	var mag = new_data["imu"]["mag"]
	_mag_heading = mag.get("heading", 0.0)

	return true

func validate_sensor_data(data: Dictionary) -> bool:
	if not data.has("tof") or not data.has("imu"):
		return false

	var tof = data["tof"]
	for key in ["front", "left", "right"]:
		var value = tof.get(key, -1.0)
		if value < 0.0 or value > TOF_MAX_RANGE:
			return false

	var imu = data["imu"]
	if not imu.has("gyro") or not imu.has("accel") or not imu.has("mag"):
		return false

	var gyro = imu["gyro"]
	if not gyro.has("angle") or not gyro.has("angular_velocity"):
		return false

	return true

func is_sensor_data_stale() -> bool: # In Sim this does nothing, important for realworld
	if last_sensor_update_time == 0.0:
		return true
	return (Time.get_ticks_msec() - last_sensor_update_time) > SENSOR_STALE_THRESHOLD_MS

# --------------------------------------------------------------------
# API - RAW DATA
# --------------------------------------------------------------------

func get_sensor_data() -> Dictionary:
	if error_state:
		return _get_error_sensor_data()

	if sensor_data_cache.is_empty():
		update_sensors()

	return sensor_data_cache.duplicate(true)

func _get_error_sensor_data() -> Dictionary:
	return {
		"tof": {"front": 0.0, "left": 0.0, "right": 0.0},
		"imu": {
			"gyro": {"angle": 0.0, "angular_velocity": 0.0, "absolute_angle": 0.0, "calibrated": false},
			"accel": {"x": 0.0, "y": 0.0, "magnitude": 0.0, "units": "m/s²"},
			"mag": {"x": 0.0, "y": 0.0, "heading": 0.0, "magnitude": 0.0, "units": "μT"}
		}
	}

func get_tof_distances() -> Dictionary:
	return {"front": _tof_front, "left": _tof_left, "right": _tof_right}

func get_imu_data() -> Dictionary:
	var data = get_sensor_data()
	return data.get("imu", {"gyro": {}, "accel": {}, "mag": {}})

# --------------------------------------------------------------------
# API - PROCESSED DATA
# --------------------------------------------------------------------

func get_compass_heading() -> float:
	# Return compass heading in deg (0-360, 0 = North)
	return _mag_heading

func get_gyro_angle() -> float:
	# Return gyro angle relative to calibration
	return _gyro_angle

func get_angular_velocity() -> float:
	# Return gyro angular velocity in deg/s
	return _gyro_angular_velocity

func get_acceleration() -> Vector2:
	# Return 2D acceleration vector
	return Vector2(_accel_x, _accel_y)

func get_wall_detections(threshold: float = wall_detection_threshold) -> Dictionary:
	return {
		"front": _tof_front < threshold,
		"left": _tof_left  < threshold,
		"right": _tof_right < threshold
	}

func is_wall_ahead(threshold: float = wall_detection_threshold) -> bool:
	return _tof_front < threshold

func is_wall_left(threshold: float = wall_detection_threshold) -> bool:
	return _tof_left < threshold

func is_wall_right(threshold: float = wall_detection_threshold) -> bool:
	return _tof_right < threshold

func get_cardinal_direction() -> String:
	var heading = get_compass_heading()

	if heading >= 315.0 or heading < 45.0:
		return "N"
	elif heading < 135.0:
		return "E"
	elif heading < 225.0:
		return "S"
	else:
		return "W"

# --------------------------------------------------------------------
# API - MOTOR CONTROL - Raw
# --------------------------------------------------------------------

func set_motors(left: float, right: float):
	if error_state:
		push_warning("Cannot set motors - microcontroller in error state")
		return

	left_motor_speed = left * _speed_multiplier
	right_motor_speed = right * _speed_multiplier

	# Send to RobotController
	rc.set_motor_speeds(left_motor_speed, right_motor_speed)

# Stops motors immediately but does NOT affect _driving state.
# Use when you want to cut power temporarily, e.g. during a turn.
# To cleanly end a drive session use stop_drive() instead.
func stop_motors():
	set_motors(0.0, 0.0)

func get_motor_speeds() -> Dictionary:
	return {
		"left": left_motor_speed,
		"right": right_motor_speed
	}

# --------------------------------------------------------------------
# API - MOVEMENT - DRIVE
# --------------------------------------------------------------------
#
# For both driving functions: PID trims left/right motor
# power each frame to counteract any drift detected by the gyro.
#
# Both drive indefinitely; call stop_drive() to stop.
#
# Parameters:
#   speed - base motor voltage/speed (please keep between 0.0 - 1.0 and use the speed multiplier in the Robotcontroller for greater speed)
#
# Example:
#   mc.drive_forward(0.6)
#   await get_tree().create_timer(2.0).timeout
#   mc.stop_drive()
#

func drive_forward(speed: float):
	_start_drive(abs(speed))  # abs() ensures forward even if caller passes negative

func drive_backward(speed: float):
	_start_drive(-abs(speed))  # abs() ensures backward even if caller passes positive

func _start_drive(speed: float):
	if error_state:
		push_warning("Cannot drive - microcontroller in error state")
		return

	_drive_base_speed = speed
	_drive_target_heading = _gyro_angle  # Lock onto current heading as goal

	# Reset PID state so accumulated integral from previous run doesn't carry over
	_pid_integral = 0.0
	_pid_last_error = 0.0

	_driving = true
	set_motors(speed, speed)

# Stop driving and clear _driving state.
# Use this to cleanly end a drive session; also stops the motors.
# To cut motor power temporarily without ending the session use stop_motors() instead.
func stop_drive():
	_driving = false
	stop_motors()

# Computes a PID correction from the heading error and nudges motor speeds.
func _process_drive_pid(delta: float):
	if not _driving:
		return

	# Heading error (signed, shortest path)
	var error = _gyro_angle - _drive_target_heading
	error = fposmod(error + 180.0, 360.0) - 180.0  # Wrap to [-180, 180]

	# PID terms
	_pid_integral += error * delta
	var derivative = (error - _pid_last_error) / delta if delta > 0.0 else 0.0
	_pid_last_error = error

	var correction = (_pid_kp * error) + (_pid_ki * _pid_integral) + (_pid_kd * derivative)

	# Clamp correction so it can't flip motor direction (would break the speed controller back emf)
	var max_correction = abs(_drive_base_speed) * PID_CORRECTION_LIMIT
	correction = clamp(correction, -max_correction, max_correction)

	# Positive error = drifted clockwise → speed up left, slow right (and vice-versa)
	var signed_correction = correction * sign(_drive_base_speed)
	set_motors(
		_drive_base_speed + signed_correction,
		_drive_base_speed - signed_correction
	)

func is_driving() -> bool:
	return _driving

# Allows updating PID gains at runtime without restarting.
# Useful for tuning via a display on the real robot in the future.
func set_drive_pid_gains(kp: float, ki: float, kd: float):
	_pid_kp = kp
	_pid_ki = ki
	_pid_kd = kd
	print("Drive PID gains set - Kp:%.3f  Ki:%.3f  Kd:%.3f" % [kp, ki, kd])

# --------------------------------------------------------------------
# API - MOVEMENT - TURN
# --------------------------------------------------------------------
#
# Rotate robot by x deg (positive = clockwise, negative = counter-clockwise).
# Emits turn_completed when done so callers can use await.
#
# Parameters:
#   degrees - how many deg to turn (signed)
#   arc_turn - false (default): spin in place (motors opposite directions)
#               true: arc turn (inner motor stops, outer motor drives)
#
# Usage examples:
#
#   # Fire-and-forget (IMPORTANT: avoid in algorithms unless you know what you are doing!)
#   mc.turn(90.0)
#
#   # Await completion before continuing
#   await mc.turn(90.0)
#
#   # Arc turn
#   await mc.turn(-45.0, true)
#

func turn(degrees: float, arc_turn: bool = false) -> Signal:
	if error_state:
		push_warning("Cannot turn - microcontroller in error state")
		emit_signal("turn_completed")
		return turn_completed

	if _turning:
		push_warning("Turn already in progress - ignoring new turn request")
		return turn_completed # TODO: Make this safe

	# Prevent PID fighting the turn
	_driving = false
	_turning = true
	_turn_cancelled = false
	_turn_coroutine(degrees, arc_turn)
	return turn_completed

# Internal coroutine that drives the turn frame-by-frame.
func _turn_coroutine(degrees: float, arc_turn: bool):
	# Track accumulated rotation instead of comparing absolute angles,
	# so gyro wrapping never causes issues
	var last_angle  = _gyro_angle
	var accumulated = 0.0

	while true:
		if _turn_cancelled:
			_turn_cancelled = false
			_turning = false
			emit_signal("turn_completed")
			return

		# Measure rotation delta this frame, accounting for wrap-around
		var delta_angle = _gyro_angle - last_angle
		delta_angle = fposmod(delta_angle + 180.0, 360.0) - 180.0  # Shortest path delta
		accumulated += delta_angle
		last_angle = _gyro_angle

		var remaining = degrees - accumulated
		if abs(remaining) <= TURN_ANGLE_TOLERANCE:
			stop_motors()
			break

		# Beyond TURN_BRAKE_MARGIN use TURN_MIN_SPEED floor to avoid stalling.
		# Within TURN_BRAKE_MARGIN let speed taper to zero so no overshoot.
		var speed: float
		if abs(remaining) > TURN_BRAKE_MARGIN:
			speed = clamp(abs(remaining) * TURN_P_GAIN, TURN_MIN_SPEED, turn_speed)
		else:
			speed = clamp(abs(remaining) * TURN_P_GAIN, 0.0, turn_speed)

		var direction = sign(remaining)

		if arc_turn:
			if direction > 0:
				set_motors(0.0, speed)   # Turn clockwise
			else:
				set_motors(speed, 0.0)   # Turn counter-clockwise
		else:
			if direction > 0:
				set_motors(-speed, speed)   # Clockwise
			else:
				set_motors(speed, -speed)   # Counter-clockwise

		await get_tree().process_frame

	# TODO: Add damping/settle logic here when moving to real robot

	_turning = false
	emit_signal("turn_completed")

# Cancels an in-progress turn immediately - motors stop and the coroutine exits and emits early
func cancel_turn():
	if not _turning:
		push_warning("No turn in progress to cancel")
		return
	_turn_cancelled = true
	stop_motors()
	print("Turn cancelled at %.1f°" % _gyro_angle)

func is_turning() -> bool:
	return _turning

# --------------------------------------------------------------------
# API - CALIBRATION
# --------------------------------------------------------------------

func calibrate_sensors():
	if not sensors_node:
		push_error("Cannot calibrate: sensors_node is null")
		enter_error_state("Calibration failed: no sensor node")
		return

	if not sensors_node.has_method("calibrate_sensors"):
		push_error("Cannot calibrate: sensors_node missing calibrate_sensors method")
		enter_error_state("Calibration failed: method not found")
		return

	sensors_node.calibrate_sensors()
	print("Sensors calibrated")

	if error_state:
		print("Calibration completed while in error state - consider calling clear_error_state() if resolved")

# --------------------------------------------------------------------
# API - UTILITIES
# --------------------------------------------------------------------

func get_last_sensor_update_time() -> float:
	return last_sensor_update_time

func is_sensors_ready() -> bool:
	return is_initialized and not sensor_data_cache.is_empty() and not is_sensor_data_stale()

func reset():
	_driving = false
	_turning = false
	_turn_cancelled = false
	_pid_integral = 0.0
	_pid_last_error = 0.0
	_drive_base_speed = 0.0
	_drive_target_heading = 0.0
	clear_error_state()
	stop_motors()
	calibrate_sensors()
	print("Microcontroller reset")

# --------------------------------------------------------------------
# DEBUG
# --------------------------------------------------------------------

func get_device_info() -> Dictionary:
	return {
		"last_update": last_sensor_update_time,
		"sensor_stale": is_sensor_data_stale(),
		"initialized": is_initialized,
		"error_state": error_state,
		"error_message": error_message,
		"motor_speeds": {"left": left_motor_speed, "right": right_motor_speed},
		"driving": _driving,
		"turning": _turning,
		"drive_target_heading": _drive_target_heading,
		"pid_gains": {"kp": _pid_kp, "ki": _pid_ki, "kd": _pid_kd}
	}
