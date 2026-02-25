extends CharacterBody2D

@export var wheel_base := 60.0      # distance between wheels

var left_speed := 0.0
var right_speed := 0.0

var rampup := 2
var d1 := 0.0
var d2 := 0.0

func _physics_process(delta):

# Remove later	-------------------------
	right_speed = 0
	left_speed = 0
		
	if Input.is_action_pressed("left"):
		left_speed = lerp(0, 400, d1)
		d1 = clampf(d1 + (delta * rampup), 0, 1)
	else:
		d1 = 0
	if Input.is_action_pressed("right"):
		right_speed = lerp(0, 400, d2)
		d2 = clampf(d2 + (delta * rampup), 0, 1)
	else:
		d2 = 0
# ----------------------------------------
	
	
	var v = (left_speed + right_speed) / 2.0
	var omega = (right_speed - left_speed) / wheel_base

	rotation += omega * delta
	velocity = Vector2(0, -v).rotated(rotation)

	move_and_slide()
