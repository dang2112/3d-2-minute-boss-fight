extends CharacterBody3D
#TODO: acceleration
#TODO: lighting

const SPEED = 6.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8
const MOUSE_SENS = 0.002

@onready var camera = $Camera3D
@onready var ray = $Camera3D/RayCast3D

var y_velocity = 0.0
var health = 100

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event.is_action_pressed("primary_action"):
		shoot()

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clamp(camera.rotation.x, -1.2, 1.2)

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		y_velocity -= GRAVITY * delta
	else:
		if Input.is_action_just_pressed("jump"):
			y_velocity = JUMP_VELOCITY

	# Movement input
	var input_dir = Vector3.ZERO

	if Input.is_action_pressed("move_forward"):
		input_dir -= transform.basis.z
	if Input.is_action_pressed("move_backward"):
		input_dir += transform.basis.z
	if Input.is_action_pressed("move_left"):
		input_dir -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		input_dir += transform.basis.x

	input_dir = input_dir.normalized()

	velocity.x = input_dir.x * SPEED
	velocity.z = input_dir.z * SPEED
	velocity.y = y_velocity

	move_and_slide()

func shoot():
	if ray.is_colliding():
		var collider = ray.get_collider()
		
		if collider.has_method("take_damage"): #Anything that CAN be hit MUST implement this method
			collider.take_damage(10)
		
		print("Hit: ", collider.name)
	else:
		print("Miss")

func take_damage(amount):
	health -= amount
	print("Player HP:", health)
