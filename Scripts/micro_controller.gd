extends Node
class_name MicrocontrollerAPI

# Configuration
@export var sensors_node: Node  # Reference to RobotSensors node
@export var wall_detection_threshold: float = 50.0

# Sensor staleness threshold in milliseconds
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

# Motor state (will be expanded later)
var left_motor_speed: float = 0.0
var right_motor_speed: float = 0.0

# --------------------------------------------------------------------
# INITIALIZATION
# --------------------------------------------------------------------

func _ready():
	initialize()

func initialize():
	await get_tree().process_frame

	if sensors_node and sensors_node.has_method("get_sensor_data"):
		print("Microcontroller API initialized")
		is_initialized = true
		calibrate_sensors()
	else:
		push_error("Sensors node not found or missing get_sensor_data method")
		enter_error_state("Sensor node missing during initialization")

func _process(_delta: float) -> void:
	if error_state:
		return

	update_sensors()

# --------------------------------------------------------------------
# ERROR HANDLING
# --------------------------------------------------------------------

func enter_error_state(message: String):
	error_state = true
	error_message = message
	stop_motors()
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

	# Update flat cache to avoid deep copies on every read
	var tof = new_data["tof"]
	_tof_front = tof["front"]
	_tof_left  = tof["left"]
	_tof_right = tof["right"]

	var gyro = new_data["imu"]["gyro"]
	_gyro_angle            = gyro.get("angle", 0.0)
	_gyro_angular_velocity = gyro.get("angular_velocity", 0.0)
	_gyro_absolute_angle   = gyro.get("absolute_angle", 0.0)
	_gyro_calibrated       = gyro.get("calibrated", false)

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

func is_sensor_data_stale() -> bool: # In Sim this does basically nothing, important for realworld
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
	# Return invalid/safe values
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
	# Return bool for each direction if wall is closer than threshold
	return {
		"front": _tof_front < threshold,
		"left":  _tof_left  < threshold,
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
# MOTOR CONTROL (Unfinished)
# --------------------------------------------------------------------

func set_motors(left: float, right: float):
	if error_state:
		push_warning("Cannot set motors - microcontroller in error state")
		return

	left_motor_speed = left
	right_motor_speed = right
	# TODO: Send to motor driver

func stop_motors():
	left_motor_speed = 0.0
	right_motor_speed = 0.0
	# TODO: Send stop command to motor driver

func get_motor_speeds() -> Dictionary:
	return {
		"left": left_motor_speed,
		"right": right_motor_speed
	}

# --------------------------------------------------------------------
# API - CALIBRATION
# --------------------------------------------------------------------

func calibrate_sensors():
	# Calibrate IMU sensors (set current orientation as reference)
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
		print("Calibration completed while in error state — consider calling clear_error_state() if the issue is resolved")

# --------------------------------------------------------------------
# API - UTILITIES
# --------------------------------------------------------------------

func get_last_sensor_update_time() -> float:
	return last_sensor_update_time

func is_sensors_ready() -> bool:
	return is_initialized and not sensor_data_cache.is_empty() and not is_sensor_data_stale()

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
		"motor_speeds": {"left": left_motor_speed, "right": right_motor_speed}
	}
