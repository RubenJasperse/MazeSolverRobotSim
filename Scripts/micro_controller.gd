extends Node2D

@export var sensors_node: Node

func _ready():
	
	# Test sensors
	print("Robot sensors initialized")
	var sensor_data = get_sensor_data()
	print("Initial sensor readings: ", sensor_data)

func _process(_delta: float) -> void:
	print(get_sensor_data())
	
# Api
func get_sensor_data() -> Dictionary:
	if sensors_node and sensors_node.has_method("get_sensor_data"):
		return sensors_node.get_sensor_data()
	else:
		push_error("Sensors node or method not found!")
		return {"front": 0.0, "left": 0.0, "right": 0.0}
