extends CharacterBody2D

@export var wheel_base := 60.0      # distance between wheels

var left_speed := 0.0
var right_speed := 0.0

func _physics_process(delta):

# Manual Sim Control ----------------------
		
	if Input.is_action_pressed("left"):
		left_speed = 400
	if Input.is_action_pressed("right"):
		right_speed = 400
	if Input.is_action_just_released("left"):
		left_speed = 0
	if Input.is_action_just_released("right"):
		right_speed = 0	
# ----------------------------------------
	
	
	var v = (left_speed + right_speed) / 2.0
	var omega = (right_speed - left_speed) / wheel_base

	rotation += omega * delta
	velocity = Vector2(0, -v).rotated(rotation)

	move_and_slide()

func set_motor_speeds(left: float, right: float):
	left_speed = left
	right_speed = right
	return
