extends Node2D
class_name RobotSensors

# ToF Sensor Configuration
@export var front_sensor_range: float = 150.0
@export var left_sensor_range: float = 150.0
@export var right_sensor_range: float = 150.0

# ToF Sensor References
@export var front_sensor: RayCast2D
@export var left_sensor: RayCast2D
@export var right_sensor: RayCast2D

# IMU Sensor Configuration
@export var gyro_noise_level: float = 0.0    # deg/s noise
@export var accel_noise_level: float = 0.0   # m/s² noise
@export var mag_noise_level: float = 0.0     # μT noise

# Calibration
var gyro_reference_angle: float = 0.0
var imu_calibrated: bool = false

func _ready():
	configure_sensors()
	calibrate_sensors()

func configure_sensors():
	# Configure ToF sensors
	if front_sensor:
		front_sensor.target_position = Vector2(front_sensor_range, 0)
		front_sensor.enabled = true
	
	if left_sensor:
		left_sensor.target_position = Vector2(left_sensor_range, 0)
		left_sensor.rotation_degrees = -90  # Point left
		left_sensor.enabled = true
	
	if right_sensor:
		right_sensor.target_position = Vector2(right_sensor_range, 0)
		right_sensor.rotation_degrees = 90   # Point right
		right_sensor.enabled = true

func calibrate_sensors():
	# Set current orientation as reference
	gyro_reference_angle = get_parent().global_rotation_degrees
	imu_calibrated = true

func reset_gyro_calibration():
	gyro_reference_angle = get_parent().global_rotation_degrees

# --------------------------------------------------------------------
# ToF SENSORS
# --------------------------------------------------------------------

func get_sensor_data() -> Dictionary:
	# Return all sensor data
	return {
		"tof": get_tof_data(),
		"imu": get_imu_data()
	}

func get_tof_data() -> Dictionary:
	# Return ToF distances
	return {
		"front": get_sensor_distance(front_sensor, front_sensor_range),
		"left": get_sensor_distance(left_sensor, left_sensor_range),
		"right": get_sensor_distance(right_sensor, right_sensor_range)
	}

func get_sensor_distance(sensor: RayCast2D, max_range: float) -> float:
	# Get distance from specific ToF sensor
	if not sensor or not sensor.enabled:
		return 0.0
	
	sensor.force_raycast_update()
	
	if sensor.is_colliding():
		return sensor.global_position.distance_to(sensor.get_collision_point())
	else:
		return max_range

# --------------------------------------------------------------------
# IMU SENSORS (2D)
# --------------------------------------------------------------------

func get_imu_data() -> Dictionary:
	# Return all IMU sensor data
	if not imu_calibrated:
		return {"gyro": {}, "accel": {}, "mag": {}}
	
	return {
		"gyro": get_gyro_data(),
		"accel": get_accelerometer_data(),
		"mag": get_magnetometer_data()
	}

func get_gyro_data() -> Dictionary:
	# Gyro: angle and angular velocity (Z-axis only)
	var robot = get_parent()
	if not robot:
		return {"angle": 0.0, "angular_velocity": 0.0}
	
	var current_angle = robot.global_rotation_degrees
	var relative_angle = wrapf(current_angle - gyro_reference_angle, -180.0, 180.0)
	
	# Add noise
	var noisy_angle = relative_angle + randf_range(-gyro_noise_level, gyro_noise_level)
	var noisy_velocity = randf_range(-gyro_noise_level, gyro_noise_level)
	
	return {
		"angle": noisy_angle,
		"angular_velocity": noisy_velocity,
		"absolute_angle": current_angle,
		"calibrated": true
	}

func get_accelerometer_data() -> Dictionary:
	# Accelerometer: 2D acceleration (X: forward/back, Y: left/right)
	var noisy_x = randf_range(-accel_noise_level, accel_noise_level)
	var noisy_y = randf_range(-accel_noise_level, accel_noise_level)
	var magnitude = sqrt(noisy_x * noisy_x + noisy_y * noisy_y)
	
	return {
		"x": noisy_x,
		"y": noisy_y,
		"magnitude": magnitude,
		"units": "m/s²"
	}

func get_magnetometer_data() -> Dictionary:
	# Magnetometer: 2D magnetic field and compass heading
	var earth_field_horizontal = 25.0  # μT
	var north_direction = 0.0  # 0° = East, 90° = North
	
	# World magnetic field vector
	var world_angle = deg_to_rad(north_direction)
	var mag_world_x = earth_field_horizontal * cos(world_angle)
	var mag_world_y = earth_field_horizontal * sin(world_angle)
	
	# Rotate to robot local coordinates
	var robot = get_parent()
	if not robot:
		return {"x": 0.0, "y": 0.0, "heading": 0.0}
	
	var robot_angle = robot.global_rotation
	var cos_t = cos(robot_angle)
	var sin_t = sin(robot_angle)
	
	var local_x = mag_world_x * cos_t + mag_world_y * sin_t
	var local_y = -mag_world_x * sin_t + mag_world_y * cos_t
	
	# Add noise
	var noisy_x = local_x + randf_range(-mag_noise_level, mag_noise_level)
	var noisy_y = local_y + randf_range(-mag_noise_level, mag_noise_level)
	
	# Calculate heading
	var heading = calculate_magnetic_heading_2d(noisy_x, noisy_y, north_direction)
	var magnitude = sqrt(noisy_x * noisy_x + noisy_y * noisy_y)
	
	return {
		"x": noisy_x,
		"y": noisy_y,
		"heading": heading,
		"magnitude": magnitude,
		"units": "μT"
	}

func calculate_magnetic_heading_2d(mag_x: float, mag_y: float, north_dir: float = 0.0) -> float:
	# Convert magnetometer readings to compass heading (0° = North)
	if abs(mag_x) < 0.001 and abs(mag_y) < 0.001:
		return 0.0
	
	var sensor_angle = rad_to_deg(atan2(mag_y, mag_x))
	return wrapf(90.0 - sensor_angle + north_dir, 0.0, 360.0)

# --------------------------------------------------------------------
# Single Sensor GETTERS
# --------------------------------------------------------------------

func get_front_distance() -> float:
	return get_sensor_distance(front_sensor, front_sensor_range)

func get_left_distance() -> float:
	return get_sensor_distance(left_sensor, left_sensor_range)

func get_right_distance() -> float:
	return get_sensor_distance(right_sensor, right_sensor_range)

func get_gyro_angle() -> float:
	var data = get_gyro_data()
	return data.get("angle", 0.0)

func get_gyro_velocity() -> float:
	var data = get_gyro_data()
	return data.get("angular_velocity", 0.0)

func get_compass_heading() -> float:
	var data = get_magnetometer_data()
	return data.get("heading", 0.0)
