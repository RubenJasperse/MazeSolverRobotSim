extends Node2D
class_name RobotSensors

# Configuration for each sensor - easily adjustable in editor
@export var front_sensor_range: float = 150.0
@export var left_sensor_range: float = 150.0
@export var right_sensor_range: float = 150.0

# References to our RayCast2D nodes (assign in editor)
@export var front_sensor: RayCast2D
@export var left_sensor: RayCast2D
@export var right_sensor: RayCast2D

func _ready():
	# Configure each sensor with its range
	configure_sensors()
	
func configure_sensors():
	#Set up all sensors with configured ranges
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

func get_sensor_data() -> Dictionary:
	#Return raw distance of all sensors
	var data = {}
	
	# Get distance from each sensor, or 0 if sensor missing/misconfigured
	data["front"] = get_sensor_distance(front_sensor, front_sensor_range)
	data["left"] = get_sensor_distance(left_sensor, left_sensor_range)
	data["right"] = get_sensor_distance(right_sensor, right_sensor_range)
	
	return data

func get_sensor_distance(sensor: RayCast2D, max_range: float) -> float:
	#Get distance from specific sensor
	if not sensor:
		push_error("Sensor node is missing!")
		return 0.0
	
	if not sensor.enabled:
		push_warning("Sensor is disabled: " + sensor.name)
		return 0.0
	
	sensor.force_raycast_update() #Needed for highspeed due to slower physics tick
	
	if sensor.is_colliding():
		# Calculate actual distance to collision point
		return sensor.global_position.distance_to(sensor.get_collision_point())
	else:
		# No collision = max range
		return max_range

#Individual sensor getters
#func get_front_distance() -> float:
#	return get_sensor_distance(front_sensor, front_sensor_range)

#func get_left_distance() -> float:
#	return get_sensor_distance(left_sensor, left_sensor_range)

#func get_right_distance() -> float:
#	return get_sensor_distance(right_sensor, right_sensor_range)
