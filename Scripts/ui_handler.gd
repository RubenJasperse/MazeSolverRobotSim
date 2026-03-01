extends CanvasLayer

@export var maze_generator: MazeGenerator

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _on_import_button_pressed() -> void:
	maze_generator.load_maze("Saved_Maze")
	
func _on_export_button_pressed() -> void:
	maze_generator.save_maze("Saved_Maze")
