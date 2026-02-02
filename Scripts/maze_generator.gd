extends Node2D
class_name MazeGenerator

# ==============================================================================
# EXPOSED CONFIG
# ==============================================================================

# Maze dimensions and appearance
@export var cell_size: int = 100
@export var wall_thickness: int = 5
@export var maze_width: int = 16
@export var maze_height: int = 16

# Random seed (0 = random each time)
@export var seed_value: int = 0:
	set(value):
		seed_value = value
		if is_inside_tree():
			regenerate()

# Goal placement
@export var goal_in_center: bool = true

# Generation algorithm selection
enum GenerationAlgorithm { PRIM, KRUSKAL, CUSTOM }
@export var algorithm: GenerationAlgorithm = GenerationAlgorithm.PRIM:
	set(value):
		algorithm = value
		if is_inside_tree():
			regenerate()

# Maze Colors
@export var wall_color: Color = Color.BLACK
@export var start_color: Color = Color.GREEN
@export var goal_color: Color = Color.RED
@export var floor_color: Color = Color.WHITE

# ==============================================================================
# INTERNAL STATE
# ==============================================================================

# Scene organization
var walls_node: Node2D
var floor_node: Node2D

# Maze structure - lines with walls are in between cells
var vertical_walls: Array = []    # Walls to the right of each cell
var horizontal_walls: Array = []  # Walls below each cell

# Start and goal locations (in cell coordinates)
var start_cell: Vector2i
var goal_cell: Vector2i

# ==============================================================================
# INIT
# ==============================================================================

func _ready():
	_initialize_nodes()
	generate_maze()

# Create or get the Walls and Floor container nodes
func _initialize_nodes():
	walls_node = _get_or_create_child("Walls")
	floor_node = _get_or_create_child("Floor")
	_clear_children(walls_node)
	_clear_children(floor_node)

# Helper to get existing node or create it if it doesn't exist
func _get_or_create_child(node_name: String) -> Node2D:
	if has_node(node_name):
		return get_node(node_name)
	var node = Node2D.new()
	node.name = node_name
	add_child(node)
	return node

# Remove all children from node
func _clear_children(node: Node2D):
	for child in node.get_children():
		child.queue_free()

# ==============================================================================
# MAZE GEN
# ==============================================================================

# Name speaks for itself :)
func generate_maze():
	# Apply seed for rand numbers
	if seed_value == 0:
		randomize()
	else:
		seed(seed_value)
	
	# Initialize all walls to closed
	_initialize_walls()
	
	# Run selected generation algorithm to carve passages
	match algorithm:
		GenerationAlgorithm.PRIM:
			_generate_prim()
		GenerationAlgorithm.KRUSKAL:
			_generate_kruskal()
		GenerationAlgorithm.CUSTOM:
			_generate_custom()
	
	# Set start and goal positions
	_set_start_goal_positions()
	
	# Create visual representation
	_create_visuals()

# Initialize wall arrays - all walls start as closed ( = true)
func _initialize_walls():
	vertical_walls.clear()
	horizontal_walls.clear()
	
	for y in range(maze_height):
		vertical_walls.append([])
		horizontal_walls.append([])
		for x in range(maze_width):
			vertical_walls[y].append(true)
			horizontal_walls[y].append(true)

# ==============================================================================
# PRIM'S ALGORITHM - Randomized maze generation
# ==============================================================================
# Starts from a random cell and expands outward, randomly selecting
# frontier cells to connect to the maze

func _generate_prim():
	var frontier = []
	var visited = _create_bool_grid(false)
	
	# Start from random cell
	var start_x = randi() % maze_width
	var start_y = randi() % maze_height
	visited[start_y][start_x] = true
	frontier.append([start_x, start_y, -1, -1])  # [x, y, from_x, from_y]
	
	# Expand maze until all cells are visited
	while frontier.size() > 0:
		# Pick random frontier cell
		var current = frontier.pop_at(randi() % frontier.size())
		var x = current[0]
		var y = current[1]
		var from_x = current[2]
		var from_y = current[3]
		
		# Remove wall between this cell and the cell it came from
		if from_x != -1:
			_remove_wall_between(from_x, from_y, x, y)
		
		# Add unvisited neighbors to the frontier
		for neighbor in _get_unvisited_neighbors(x, y, visited):
			var nx = neighbor[0]
			var ny = neighbor[1]
			if not visited[ny][nx]:
				visited[ny][nx] = true
				frontier.append([nx, ny, x, y])

# Get all neighbors of a cell that haven't been visited
func _get_unvisited_neighbors(x: int, y: int, visited: Array) -> Array:
	var neighbors = []
	var directions = [[0, -1], [1, 0], [0, 1], [-1, 0]]
	
	for dir in directions:
		var nx = x + dir[0]
		var ny = y + dir[1]
		if nx >= 0 and nx < maze_width and ny >= 0 and ny < maze_height: # Keep maze in specified height and width
			if not visited[ny][nx]:
				neighbors.append([nx, ny])
	
	return neighbors

# Remove wall between two adjacent cells
func _remove_wall_between(x1: int, y1: int, x2: int, y2: int):
	if x1 == x2:  # Vertically adjacent
		var min_y = min(y1, y2)
		horizontal_walls[min_y][x1] = false
	else:  # Horizontally adjacent
		var min_x = min(x1, x2)
		vertical_walls[y1][min_x] = false

# ==============================================================================
# KRUSKAL'S ALGORITHM
# ==============================================================================
# Treats each cell as a separate set and randomly connects sets until
# all cells are in one connected set

func _generate_kruskal():
	var edges = []
	var parent = []  # Union-find parent array
	var rank = []    # Union-find rank array
	
	# Initialize union-find structure - each cell is its own set
	for i in range(maze_width * maze_height):
		parent.append(i)
		rank.append(0)
	
	# Create list of all possible edges (walls between cells)
	for y in range(maze_height):
		for x in range(maze_width):
			if x < maze_width - 1:
				edges.append([x, y, x + 1, y])  # Right neighbor
			if y < maze_height - 1:
				edges.append([x, y, x, y + 1])  # Down neighbor
	
	# Randomize edge order
	_shuffle_array(edges)
	
	# Process edges - connect cells if they're not already connected
	for edge in edges:
		var id1 = edge[1] * maze_width + edge[0]
		var id2 = edge[3] * maze_width + edge[2]
		
		# If cells are in different sets, connect them
		if _find(parent, id1) != _find(parent, id2):
			_union(parent, rank, id1, id2)
			_remove_wall_between(edge[0], edge[1], edge[2], edge[3])

# Find root of set (with path compression)
func _find(parent: Array, x: int) -> int:
	if parent[x] != x:
		parent[x] = _find(parent, parent[x])
	return parent[x]

# Union two sets by rank
func _union(parent: Array, rank: Array, x: int, y: int):
	var root_x = _find(parent, x)
	var root_y = _find(parent, y)
	
	if root_x != root_y:
		if rank[root_x] < rank[root_y]:
			parent[root_x] = root_y
		elif rank[root_x] > rank[root_y]:
			parent[root_y] = root_x
		else:
			parent[root_y] = root_x
			rank[root_x] += 1

# Fisher-Yates shuffle using seed
func _shuffle_array(arr: Array):
	for i in range(arr.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = arr[i]
		arr[i] = arr[j]
		arr[j] = temp

# ==============================================================================
# CUSTOM MAZE / ALGORITH - Empty maze for now cause I am lazy hehe
# ==============================================================================

func _generate_custom():
	for y in range(maze_height):
		for x in range(maze_width):
			if x < maze_width - 1:
				vertical_walls[y][x] = false
			if y < maze_height - 1:
				horizontal_walls[y][x] = false

# ==============================================================================
# VISUAL GENERATION
# ==============================================================================

# Create visual elements (floor, walls, markers)
func _create_visuals():
	_generate_floor()
	_generate_walls()
	_generate_markers()

# Create floor tiles for each cell | TODO: Use 1 giant background instead of sprite for each cell (This way was easier for dynamically scaling)
func _generate_floor():
	for y in range(maze_height):
		for x in range(maze_width):
			var floor_tile = _create_colored_sprite(cell_size, cell_size, floor_color)
			floor_tile.position = Vector2((x + 0.5) * cell_size, (y + 0.5) * cell_size)
			floor_tile.z_index = -1  # Behind walls
			floor_node.add_child(floor_tile)

# Create all wall segments based on wall arrays
func _generate_walls():
	_create_border_walls()
	
	# Create internal walls
	for y in range(maze_height):
		for x in range(maze_width):
			# Vertical walls
			if x < maze_width - 1 and vertical_walls[y][x]:
				var pos = Vector2((x + 1) * cell_size, y * cell_size + cell_size * 0.5)
				_create_wall(pos, Vector2(wall_thickness, cell_size))
			
			# Horizontal walls
			if y < maze_height - 1 and horizontal_walls[y][x]:
				var pos = Vector2(x * cell_size + cell_size * 0.5, (y + 1) * cell_size)
				_create_wall(pos, Vector2(cell_size, wall_thickness))

# Create the four border walls around the maze
func _create_border_walls():
	var hw = maze_width * cell_size * 0.5
	var hh = maze_height * cell_size * 0.5
	var wt = wall_thickness * 0.5
	
	_create_wall(Vector2(hw, wt), Vector2(maze_width * cell_size, wall_thickness))  # Top
	_create_wall(Vector2(hw, maze_height * cell_size - wt), Vector2(maze_width * cell_size, wall_thickness))  # Bottom
	_create_wall(Vector2(wt, hh), Vector2(wall_thickness, maze_height * cell_size))  # Left
	_create_wall(Vector2(maze_width * cell_size - wt, hh), Vector2(wall_thickness, maze_height * cell_size))  # Right

# Create wall segment with collision
func _create_wall(pos: Vector2, size: Vector2):
	var wall = StaticBody2D.new()
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	
	var sprite = _create_colored_sprite(int(size.x), int(size.y), wall_color)
	sprite.centered = false
	sprite.position = -size * 0.5
	wall.add_child(sprite)
	
	wall.position = pos
	walls_node.add_child(wall)

# Determine start and goal cell positions
func _set_start_goal_positions():
	start_cell = Vector2i(0, 0)
	
	if goal_in_center:
		# Calculate true center cell (Off center for even maze sizes | TODO: Group middle cells together for even mazes (so there is a true center)
		goal_cell = Vector2i(
			int(floor((maze_width - 1) / 2.0)),
			int(floor((maze_height - 1) / 2.0))
		)
	else:
		goal_cell = Vector2i(maze_width - 1, maze_height - 1)

# Create start and goal marker sprites
func _generate_markers():
	var marker_size = cell_size - 2 * wall_thickness
	
	# Start marker
	var start_marker = _create_colored_sprite(marker_size, marker_size, start_color)
	start_marker.position = _cell_to_world_pos(start_cell)
	start_marker.z_index = 0
	floor_node.add_child(start_marker)
	
	# Goal marker
	var goal_marker = _create_colored_sprite(marker_size, marker_size, goal_color)
	goal_marker.position = _cell_to_world_pos(goal_cell)
	goal_marker.z_index = 0
	floor_node.add_child(goal_marker)

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Convert cell coordinates to world position (center of cell)
func _cell_to_world_pos(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)

# Create sprite filled with solid color
func _create_colored_sprite(width: int, height: int, color: Color) -> Sprite2D:
	var sprite = Sprite2D.new()
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	sprite.texture = ImageTexture.create_from_image(image)
	return sprite

# Create 2D boolean grid initialized to default value
func _create_bool_grid(default_value: bool) -> Array:
	var grid = []
	for y in range(maze_height):
		grid.append([])
		for x in range(maze_width):
			grid[y].append(default_value)
	return grid

# ==============================================================================
# PUBLIC API
# ==============================================================================

# Regenerate maze with current settings
func regenerate():
	_clear_children(walls_node)
	_clear_children(floor_node)
	generate_maze()

# Change random seed and regenerate
func set_seed(new_seed: int):
	seed_value = new_seed
	if seed_value == 0:
		randomize()
	else:
		seed(seed_value)
	regenerate()

# Change algorithm and regenerate
func set_algorithm(new_algorithm: GenerationAlgorithm):
	algorithm = new_algorithm
	regenerate()

# Change maze dimensions and regenerate
func set_maze_size(width: int, height: int):
	maze_width = width
	maze_height = height
	regenerate()

# Get world position of the start marker
func get_start_position() -> Vector2:
	return _cell_to_world_pos(start_cell)

# Get world position of the goal marker
func get_goal_position() -> Vector2:
	return _cell_to_world_pos(goal_cell)

# Convert world position to cell coordinates
func get_cell_at_position(pos: Vector2) -> Vector2:
	return Vector2(int(pos.x / cell_size), int(pos.y / cell_size))

# Save maze to file
func save_maze(filename: String):
	var file = FileAccess.open("user://" + filename, FileAccess.WRITE)
	if file:
		var data = {
			"width": maze_width,
			"height": maze_height,
			"vertical_walls": vertical_walls,
			"horizontal_walls": horizontal_walls,
			"seed": seed_value,
			"algorithm": algorithm
		}
		file.store_string(JSON.stringify(data))
		file.close()

# Load maze from file
func load_maze(filename: String):
	var file = FileAccess.open("user://" + filename, FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		
		if data:
			maze_width = data.get("width", 16)
			maze_height = data.get("height", 16)
			vertical_walls = data.get("vertical_walls", [])
			horizontal_walls = data.get("horizontal_walls", [])
			seed_value = data.get("seed", 0)
			algorithm = data.get("algorithm", GenerationAlgorithm.PRIM)
			
			_clear_children(walls_node)
			_clear_children(floor_node)
			_create_visuals()
