extends Node2D
class_name SimulationHandler

@export var robot: CharacterBody2D
@export var maze_generator: MazeGenerator
@export var microcontroller: MicrocontrollerAPI
@export var algorithm_script: Script  # INFO: Drag algorithm script to this slot in the editor

# Simulation state
var algorithm_instance: RefCounted
var is_running: bool = false

# --------------------------------------------------------------------
# INITIALIZATION
# --------------------------------------------------------------------

func _ready() -> void:
	await get_tree().process_frame

	# Position robot at start
	reset_robot_position()

	# Connect microcontroller to sensors
	if microcontroller and robot.has_node("Sensors"):
		microcontroller.sensors_node = robot.get_node("Sensors")
		print("Microcontroller connected to sensors")
	else:
		push_error("Failed to connect microcontroller to sensors")
		return

	# Initialize algorithm and start automatically
	await initialize_algorithm()
	start_simulation()

func reset_robot_position():
	robot.global_position = maze_generator.get_start_position()
	robot.rotation = PI  # Robot facing down (South)

	if robot.has_method("reset"):
		robot.reset()

func initialize_algorithm():
	await get_tree().process_frame

	if not algorithm_script:
		push_warning("No algorithm script assigned")
		return

	algorithm_instance = algorithm_script.new()

	if algorithm_instance.has_method("initialize"):
		algorithm_instance.initialize(microcontroller)  # Pass microcontroller reference for API usage
		print("Algorithm initialized: ", algorithm_script.resource_path)
	else:
		push_error("Algorithm script missing initialize() method")

# --------------------------------------------------------------------
# SIMULATION LOOP
# --------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not is_running:
		return

	if algorithm_instance and algorithm_instance.has_method("step"):
		algorithm_instance.step()

	check_goal_reached()

func start_simulation():
	if microcontroller and microcontroller.is_in_error_state():
		print("Cannot start - microcontroller in error state")
		return

	is_running = true
	microcontroller.drive_forward(1)
	
	print("Simulation started")

func pause_simulation():
	is_running = false
	microcontroller.stop_drive()
	print("Simulation paused")

func check_goal_reached():
	var goal_pos = maze_generator.get_goal_position()
	var distance = robot.global_position.distance_to(goal_pos)

	if distance < maze_generator.cell_size * 0.5:
		print("Goal reached!")
		pause_simulation()

# --------------------------------------------------------------------
# DEBUG
# --------------------------------------------------------------------

func get_simulation_status() -> Dictionary:
	var status = {
		"is_running":      is_running,
		"robot_position":  robot.global_position,
		"robot_cell":      maze_generator.get_cell_at_position(robot.global_position),
		"goal_cell":       maze_generator.goal_cell,
		"distance_to_goal": robot.global_position.distance_to(maze_generator.get_goal_position())
	}

	if microcontroller:
		status["microcontroller"] = {
			"initialized":  microcontroller.is_initialized,
			"error_state":  microcontroller.is_in_error_state(),
			"error_message": microcontroller.get_error_message(),
			"motor_speeds": microcontroller.get_motor_speeds()
		}

	return status

# --------------------------------------------------------------------
# KEYBOARD CONTROLS
# --------------------------------------------------------------------

func _unhandled_input(event: InputEvent):
	# Space — toggle pause/resume
	if event.is_action_pressed("ui_accept"):
		if is_running:
			pause_simulation()
		else:
			start_simulation()

	# Ctrl + C — print simulation status
	if event.is_action_pressed("ui_copy"):
		print(get_simulation_status())
