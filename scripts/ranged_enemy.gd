extends CharacterBody3D

enum State {
	IDLE,
	PATROL,
	CHASE,
	ATTACK,
	DEAD
}

var current_state = State.IDLE

const GRAVITY = 9.8

@onready var attack_timer = $AttackTimer
@onready var ray_from = $RayCast3D
@onready var health_bar = $HealthBar3D

var target = null
var speed = 2.5
var max_health = 80
var health = 80
var attack_range = 12.0
var attack_damage = 12
var attack_cooldown = 1.6

func _ready():
	add_to_group("network_sync_objects")
	attack_timer.wait_time = attack_cooldown
	attack_timer.timeout.connect(_on_attack_timer_timeout)

func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if current_state == State.DEAD:
		move_and_slide()
		return

	match current_state:
		State.IDLE:
			_look_for_player()
		State.PATROL:
			_patrol(delta)
		State.CHASE:
			_chase(delta)
		State.ATTACK:
			pass

	move_and_slide()

func _look_for_player():
	var players = get_tree().get_nodes_in_group("players")
	var closest = null
	var closest_d = INF
	for p in players:
		if not is_instance_valid(p):
			continue
		var d = global_position.distance_to(p.global_position)
		if d < closest_d:
			closest_d = d
			closest = p

	if closest and closest_d <= attack_range * 1.5:
		target = closest
		current_state = State.CHASE

func _chase(delta):
	if not target or not is_instance_valid(target):
		current_state = State.IDLE
		return

	var to_target = target.global_position - global_position
	look_at(target.global_transform.origin, Vector3.UP)

	if to_target.length() <= attack_range:
		current_state = State.ATTACK
		attack_timer.start()
		velocity.x = 0
		velocity.z = 0
		return

	var dir = to_target.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

func _patrol(delta):
	# Simple placeholder patrol (no pathing yet)
	velocity.x = 0
	velocity.z = 0

func _on_attack_timer_timeout():
	if current_state != State.ATTACK:
		return
	if target and target.has_method("take_damage"):
		# Raycast toward target to simulate projectile hit
		var origin = global_transform.origin + Vector3(0, 1.2, 0)
		var dir = (target.global_transform.origin - origin).normalized()
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * attack_range)
		query.exclude = [self]
		var result = get_world_3d().direct_space_state.intersect_ray(query)
		if not result.is_empty():
			var collider = result["collider"]
			if collider and collider.has_method("take_damage"):
				collider.take_damage(attack_damage)

func take_damage(amount):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if current_state == State.DEAD:
		return

	health -= amount
	print("RangedEnemy HP:", health)
	_update_health_bar()
	if health <= 0:
		die()

func die():
	current_state = State.DEAD
	queue_free()

func get_sync_state() -> Dictionary:
	return {
		"position": global_position,
		"velocity": velocity,
		"rotation": rotation,
		"health": health,
		"state": current_state
	}

func apply_sync_state(state: Dictionary):
	global_position = state["position"]
	velocity = state["velocity"]
	rotation = state["rotation"]
	health = state["health"]
	current_state = state["state"]
	_update_health_bar()

func _update_health_bar():
	if health_bar and health_bar.has_method("update_from_health"):
		health_bar.update_from_health(health, max_health)
