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
@export var magnetic_declination: float = 0.0  # Rotate magnetic north if desired (deg)

# Sim Configuration
@export var sensor_update_delay: float = 0.0  # Simulate processing delay (ms)

# Calibration
var gyro_reference_angle: float = 0.0
var imu_calibrated: bool = false

# Accelerometer tracking variables
var previous_velocity: Vector2 = Vector2.ZERO
var previous_position: Vector2 = Vector2.ZERO
var last_accel_update: float = 0.0

# Gyro tracking variables
var last_gyro_angle: float = 0.0
var last_gyro_update: float = 0.0

# --------------------------------------------------------------------

func _ready():
	configure_sensors()
	calibrate_sensors()

func configure_sensors():
	# Configure ToF sensors
	if front_sensor:
		front_sensor.target_position = Vector2(front_sensor_range, 0)
		front_sensor.rotation_degrees = -90 # Raycasts start pointing to right (from robot pov) so this rotates them to front
		front_sensor.enabled = true
	
	if left_sensor:
		left_sensor.target_position = Vector2(left_sensor_range, 0)
		left_sensor.rotation_degrees = 180
		left_sensor.enabled = true
	
	if right_sensor:
		right_sensor.target_position = Vector2(right_sensor_range, 0)
		right_sensor.rotation_degrees = 0
		right_sensor.enabled = true

func calibrate_sensors():
	# Set current orientation as reference
	gyro_reference_angle = get_parent().global_rotation_degrees
	imu_calibrated = true

# --------------------------------------------------------------------
# SENSORS
# --------------------------------------------------------------------

func get_sensor_data() -> Dictionary:
		# Simulate processing delay
	if sensor_update_delay > 0:
		await get_tree().create_timer(sensor_update_delay / 1000.0).timeout
	
	# Return all sensor data
	return {
		"tof": get_tof_data(),
		"imu": get_imu_data()
	}

# --------------------------------------------------------------------
# ToF SENSORS
# --------------------------------------------------------------------

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
	
	var current_time = Time.get_ticks_msec() / 1000.0  # Convert to seconds
	var current_angle = robot.global_rotation_degrees
	var relative_angle = wrapf(current_angle - gyro_reference_angle, -180.0, 180.0)
	
	# Calculate angular velocity based on angle change
	var angular_velocity = 0.0
	if last_gyro_update > 0:
		var delta_time = current_time - last_gyro_update
		if delta_time > 0:
			# Calculate angle change since last update
			var angle_change = current_angle - last_gyro_angle
			# Handle wrap-around (e.g., going from 359 to 1 degree)
			if angle_change > 180:
				angle_change -= 360
			elif angle_change < -180:
				angle_change += 360
			
			angular_velocity = angle_change / delta_time
	
	# Add noise to the measured values (not random values)
	var noisy_angle = relative_angle + randf_range(-gyro_noise_level * 0.01, gyro_noise_level * 0.01)
	var noisy_velocity = angular_velocity + randf_range(-gyro_noise_level, gyro_noise_level)
	
	# Store values for next update
	last_gyro_angle = current_angle
	last_gyro_update = current_time
	
	return {
		"angle": noisy_angle,
		"angular_velocity": noisy_velocity,
		"calibrated": true,
		"angle_units": "deg", # For Clarity can be Removed
		"velocity_units": "deg/s"
	}

func get_accelerometer_data() -> Dictionary:
	# Accelerometer: 2D acceleration in robot's local frame
	# X: forward/back, Y: left/right
	var robot = get_parent()
	if not robot:
		return {"x": 0.0, "y": 0.0, "magnitude": 0.0, "units": "m/s²"}
	
	var current_time = Time.get_ticks_msec() / 1000.0  # Convert to seconds
	var current_position = robot.global_position
	
	# Calculate velocity based on position change
	var current_velocity = Vector2.ZERO
	if last_accel_update > 0:
		var delta_time = current_time - last_accel_update
		if delta_time > 0:
			current_velocity = (current_position - previous_position) / delta_time
	
	# Calculate acceleration (change in velocity)
	var acceleration_world = Vector2.ZERO
	if previous_velocity != Vector2.ZERO:
		var delta_time = current_time - last_accel_update
		if delta_time > 0:
			acceleration_world = (current_velocity - previous_velocity) / delta_time
	
	# Gravity vector in world space (pointing down in Y axis)
	var gravity_world = Vector2(0, 9.81)  # 9.81 m/s² downward
	
	# Combine linear acceleration with gravity
	var total_accel_world = acceleration_world + gravity_world
	
	# Convert to robot's local frame
	var robot_rotation = robot.global_rotation
	var acceleration_local = Vector2(
		total_accel_world.rotated(-robot_rotation).x,  # Forward/back
		-total_accel_world.rotated(-robot_rotation).y   # Left/right (inverted because Y is down in world)
	)
	
	# Add noise
	var noisy_x = acceleration_local.x + randf_range(-accel_noise_level, accel_noise_level)
	var noisy_y = acceleration_local.y + randf_range(-accel_noise_level, accel_noise_level)
	var magnitude = sqrt(noisy_x * noisy_x + noisy_y * noisy_y)
	
	# Store values for next update
	previous_position = current_position
	previous_velocity = current_velocity
	last_accel_update = current_time
	
	return {
		"x": noisy_x,
		"y": noisy_y,
		"magnitude": magnitude,
		"accel_units": "m/s²"
	}

func get_magnetometer_data() -> Dictionary:
	var earth_field_strength = 50.0  # μT
	
	# Earth magnetic field in world frame
	var world_angle = deg_to_rad(magnetic_declination)
	var mag_world = Vector2(
		earth_field_strength * cos(world_angle),
		earth_field_strength * sin(world_angle)
	)
	
	var robot = get_parent()
	if not robot:
		return {"x": 0.0, "y": 0.0, "heading": 0.0}
	
	# Convert world field to robot local frame
	var local_field = mag_world.rotated(-robot.global_rotation)
	
	# Add noise
	var noisy_x = local_field.x + randf_range(-mag_noise_level, mag_noise_level)
	var noisy_y = local_field.y + randf_range(-mag_noise_level, mag_noise_level)
	
	var heading = calculate_magnetic_heading_2d(noisy_x, noisy_y)
	
	return {
		"x": noisy_x,
		"y": noisy_y,
		"heading": heading,
		"magnitude": sqrt(noisy_x * noisy_x + noisy_y * noisy_y),
		"field_units": "μT",
		"heading_units": "deg"
	}

func calculate_magnetic_heading_2d(mag_x: float, mag_y: float) -> float:
	if abs(mag_x) < 0.001 and abs(mag_y) < 0.001:
		return 0.0
	
	var angle = rad_to_deg(atan2(mag_y, mag_x))
	
	return wrapf(angle, 0.0, 360.0)

# --------------------------------------------------------------------
# Single Sensor GETTERS
# --------------------------------------------------------------------

# ToF Sensor Getters
func get_front_distance() -> float:
	return get_sensor_distance(front_sensor, front_sensor_range)

func get_left_distance() -> float:
	return get_sensor_distance(left_sensor, left_sensor_range)

func get_right_distance() -> float:
	return get_sensor_distance(right_sensor, right_sensor_range)

# Gyroscope Getters
func get_gyro_angle() -> float:
	var data = get_gyro_data()
	return data.get("angle", 0.0)

func get_gyro_velocity() -> float:
	var data = get_gyro_data()
	return data.get("angular_velocity", 0.0)

# Accelerometer Getters
func get_acceleration_x() -> float:
	var data = get_accelerometer_data()
	return data.get("x", 0.0)

func get_acceleration_y() -> float:
	var data = get_accelerometer_data()
	return data.get("y", 0.0)

func get_acceleration_magnitude() -> float:
	var data = get_accelerometer_data()
	return data.get("magnitude", 0.0)

func get_acceleration_vector() -> Vector2:
	var data = get_accelerometer_data()
	return Vector2(data.get("x", 0.0), data.get("y", 0.0))

# Magnetometer Getters
func get_compass_heading() -> float:
	var data = get_magnetometer_data()
	return data.get("heading", 0.0)

func get_magnetometer_x() -> float:
	var data = get_magnetometer_data()
	return data.get("x", 0.0)

func get_magnetometer_y() -> float:
	var data = get_magnetometer_data()
	return data.get("y", 0.0)

func get_magnetometer_magnitude() -> float:
	var data = get_magnetometer_data()
	return data.get("magnitude", 0.0)

func get_magnetometer_vector() -> Vector2:
	var data = get_magnetometer_data()
	return Vector2(data.get("x", 0.0), data.get("y", 0.0))
