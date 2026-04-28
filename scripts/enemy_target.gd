extends CharacterBody3D

var health = 2000

func take_damage(amount):
	health -= amount
	print("Enemy HP:", health)
	
	if health <= 0:
		queue_free()
