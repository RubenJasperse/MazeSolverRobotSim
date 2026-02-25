# microcontroller_api.gd
extends Node
class_name MicrocontrollerAPI

# Configuration
@export var sensors_node: Node  # Reference to RobotSensors node

# API Defaults
@export var wall_detection_threshold: float = 50.0

# Internal state
var last_sensor_update_time: float = 0.0
var sensor_data_cache: Dictionary = {}
var is_initialized: bool = false

# --------------------------------------------------------------------
# INITIALIZATION
# --------------------------------------------------------------------

func _ready():
	initialize()
	
func initialize():
	# Wait for sensors to be ready
	await get_tree().process_frame
	
	if sensors_node and sensors_node.has_method("get_sensor_data"):
		print("Microcontroller API initialized")
		is_initialized = true
		calibrate_sensors()
	else:
		push_error("Sensors node not found or missing get_sensor_data method")

func _process(_delta: float) -> void:
	update_sensors()
	
	#print(get_compass_heading())

# --------------------------------------------------------------------
# SENSOR POLLING
# --------------------------------------------------------------------

func update_sensors() -> bool:	
	if not is_initialized or not sensors_node:
		return false
	
	# Get fresh sensor data
	sensor_data_cache = sensors_node.get_sensor_data()
	last_sensor_update_time = Time.get_ticks_msec()
	
	return true

# --------------------------------------------------------------------
# API - RAW DATA
# --------------------------------------------------------------------

func get_sensor_data() -> Dictionary:
	# Return raw sensor data (format same as sensors.gd)
	if sensor_data_cache.is_empty():
		update_sensors()
	return sensor_data_cache.duplicate(true)  # For encapsulation

func get_tof_distances() -> Dictionary:
	# Return only ToF distances
	var data = get_sensor_data()
	return data.get("tof", {"front": 0.0, "left": 0.0, "right": 0.0})

func get_imu_data() -> Dictionary:
	# Return only IMU data
	var data = get_sensor_data()
	return data.get("imu", {"gyro": {}, "accel": {}, "mag": {}})

# --------------------------------------------------------------------
# API - PROCESSED DATA
# --------------------------------------------------------------------

func get_compass_heading() -> float:
	# Return compass heading in deg (0-360, 0 = North)
	var imu_data = get_imu_data()
	var mag_data = imu_data.get("mag", {})
	return mag_data.get("heading", 0.0)

func get_gyro_angle() -> float:
	# Return gyro angle relative to calibration
	var imu_data = get_imu_data()
	var gyro_data = imu_data.get("gyro", {})
	return gyro_data.get("angle", 0.0)

func get_angular_velocity() -> float:
	# Return gyro angular velocity in deg/s
	var imu_data = get_imu_data()
	var gyro_data = imu_data.get("gyro", {})
	return gyro_data.get("angular_velocity", 0.0)

func get_acceleration() -> Vector2:
	# Return 2D acceleration vector
	var imu_data = get_imu_data()
	var accel_data = imu_data.get("accel", {})
	return Vector2(accel_data.get("x", 0.0), accel_data.get("y", 0.0))

func get_wall_detections(threshold: float = wall_detection_threshold) -> Dictionary:
	# Return bool for each direction if wall is closer than threshold
	var tof = get_tof_distances()
	return {
		"front": tof.get("front", 0.0) < threshold,
		"left": tof.get("left", 0.0) < threshold,
		"right": tof.get("right", 0.0) < threshold
	}

func is_wall_ahead(threshold: float = 50.0) -> bool:
	return get_tof_distances().get("front", 0.0) < threshold

func is_wall_left(threshold: float = 50.0) -> bool:
	return get_tof_distances().get("left", 0.0) < threshold

func is_wall_right(threshold: float = 50.0) -> bool:
	return get_tof_distances().get("right", 0.0) < threshold

# --------------------------------------------------------------------
# API - CALIBRATION
# --------------------------------------------------------------------

func calibrate_sensors():
	# Calibrate IMU sensors (set current orientation as reference)
	if sensors_node and sensors_node.has_method("calibrate_sensors"):
		sensors_node.calibrate_sensors()
		print("Sensors calibrated")

func reset_gyro_calibration():
	# Reset gyro to current orientation
	if sensors_node and sensors_node.has_method("reset_gyro_calibration"):
		sensors_node.reset_gyro_calibration()
		print("Gyro recalibrated")

# --------------------------------------------------------------------
# API - UTILITIES
# --------------------------------------------------------------------

func get_last_sensor_update_time() -> float:
	return last_sensor_update_time

func is_sensors_ready() -> bool:
	# Use to stop Robot if sensors fail | TODO: Actively check for faulty data
	return is_initialized and not sensor_data_cache.is_empty()

# --------------------------------------------------------------------
# DEBUG/DEVICE INFO
# --------------------------------------------------------------------

func get_device_info() -> Dictionary:
	return {
		"sensor_delay": sensors_node.sensor_update_delay,
		"last_update": last_sensor_update_time,
		"initialized": is_initialized
	}
