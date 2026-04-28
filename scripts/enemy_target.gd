extends CharacterBody3D

const GRAVITY = 9.8
var health = 2000

func take_damage(amount):
	health -= amount
	print("Enemy HP:", health)
	
	if health <= 0:
		queue_free()

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	move_and_slide()
