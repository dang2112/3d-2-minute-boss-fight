extends CharacterBody3D

const GRAVITY = 9.8
@onready var health_bar = $HealthBar3D

var max_health = 2000
var health = 2000

func _ready():
	add_to_group("network_sync_objects")

func take_damage(amount):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	health -= amount
	print("Enemy HP:", health)
	_update_health_bar()

	if health <= 0:
		queue_free()

func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	move_and_slide()

func get_sync_state() -> Dictionary:
	return {
		"position": global_position,
		"velocity": velocity,
		"health": health
	}

func apply_sync_state(state: Dictionary):
	global_position = state["position"]
	velocity = state["velocity"]
	health = state["health"]
	_update_health_bar()

func _update_health_bar():
	if health_bar and health_bar.has_method("update_from_health"):
		health_bar.update_from_health(health, max_health)
