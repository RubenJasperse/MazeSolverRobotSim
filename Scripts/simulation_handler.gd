extends Node2D
class_name SimulationHandler

@export var robot: CharacterBody2D
@export var maze_generator: MazeGenerator
@export var microcontroller: MicrocontrollerAPI
@export var algorithm_script: Script  # INFO DRAG ALGORITHM SCRIPT TO THIS SLOT IN THE EDITOR

# Simulation state
var algorithm_instance: RefCounted
var is_running: bool = false

func _ready() -> void:
	reset_robot_position()
	
	# Connect microcontroller to sensors
	if microcontroller and robot.has_node("Sensors"):
		microcontroller.sensors_node = robot.get_node("Sensors")
		print("Microcontroller connected to sensors")
	else:
		push_error("Failed to connect microcontroller to sensors")
		return
	
	initialize_algorithm()
	
	start_simulation()

func reset_robot_position():
	robot.global_position = maze_generator.get_start_position()
	robot.rotation = PI  # Robot facing down (South)
	
	if robot.has_method("reset"):
		robot.reset()

func initialize_algorithm():
	# Create algorithm instance from script
	if algorithm_script:
		algorithm_instance = algorithm_script.new()
		if algorithm_instance.has_method("initialize"):
			algorithm_instance.initialize(microcontroller) # Pass down reference to microcontroller for API usage
			print("Algorithm initialized: ", algorithm_script.resource_path)
		else:
			push_error("Algorithm script missing initialize() method")
	else:
		push_warning("No algorithm script assigned")

func _physics_process(_delta: float) -> void:
	if not is_running:
		return
	
	# Run algorithm step
	if algorithm_instance and algorithm_instance.has_method("step"):
		algorithm_instance.step()
	
	check_goal_reached()

func start_simulation():
	if microcontroller and microcontroller.is_in_error_state():
		print("Cannot start simulation - microcontroller in error state")
		return
		
	is_running = true
	print("Simulation started")

func pause_simulation():
	is_running = false
	print("Simulation paused")

# WARNING: This function causes weird behavior when resetting mid run for some reason
func reset_simulation():
	pause_simulation()
	
	reset_robot_position()
	
	# Clear microcontroller error state if any
	if microcontroller and microcontroller.is_in_error_state():
		microcontroller.clear_error_state()
	
	# Recalibrate sensors
	if microcontroller and microcontroller.has_method("calibrate_sensors"):
		microcontroller.calibrate_sensors()
	
	print("Simulation reset")
	
	start_simulation()

func check_goal_reached():
	var goal_pos = maze_generator.get_goal_position()
	var distance = robot.global_position.distance_to(goal_pos)
	
	# Check if robot is close enough to goal (within half a cell)
	if distance < maze_generator.cell_size * 0.5:
		print("Goal reached!")
		pause_simulation()

func get_simulation_status() -> Dictionary:
	var status = {
		"is_running": is_running,
		"robot_position": robot.global_position,
		"robot_cell": maze_generator.get_cell_at_position(robot.global_position),
		"goal_cell": maze_generator.goal_cell,
		"distance_to_goal": robot.global_position.distance_to(maze_generator.get_goal_position())
	}
	
	if microcontroller:
		status["microcontroller"] = {
			"initialized": microcontroller.is_initialized,
			"error_state": microcontroller.is_in_error_state(),
			"error_message": microcontroller.get_error_message(),
			"motor_speeds": microcontroller.get_motor_speeds()
		}
	
	return status

# Keyboard controls for testing
func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_accept"):  # Space bar
		if is_running:
			pause_simulation()
		else:
			start_simulation()
	
	if event.is_action_pressed("ui_cancel"):  # Escape
		reset_simulation()
	
	if event.is_action_pressed("ui_copy"):  # Ctr + C
		print(get_simulation_status())
