extends Node2D

@export var robot: CharacterBody2D
@export var maze_generator: Node2D

func _ready() -> void:
	robot.global_position = maze_generator.get_start_position()
	robot.rotation = PI
