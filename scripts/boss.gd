extends CharacterBody3D
# Boss Enemy - 2-phase boss
# Phase 1 (<100% HP): Heavy melee attacks
# Phase 2 (<50% HP): Adds ranged projectile attacks

enum State {
	IDLE,
	CHASE,
	ATTACK,
	DEAD
}

var current_state = State.IDLE
var current_phase = 1

const GRAVITY = 9.8

@onready var attack_timer = $AttackTimer
@onready var health_bar = $HealthBar3D

var target = null
var speed = 1.5  # Very slow
var max_health = 500  # Very durable
var health = 500
var attack_range = 3.0  # Melee range
var melee_damage = 25
var projectile_damage = 15
var attack_cooldown = 2.0
var phase2_trigger = 250  # 50% HP

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

	# Check phase transition
	if health <= phase2_trigger and current_phase == 1:
		current_phase = 2
		print("Boss entered Phase 2!")

	match current_state:
		State.IDLE:
			look_for_player()
		State.CHASE:
			chase_player()
		State.ATTACK:
			attack_player()

	move_and_slide()

func look_for_player():
	var players = get_tree().get_nodes_in_group("players")
	var closest_player = _find_closest_player(players)

	if closest_player:
		target = closest_player
		current_state = State.CHASE

func chase_player():
	target = _find_closest_player(get_tree().get_nodes_in_group("players"))

	if not target:
		current_state = State.IDLE
		return

	look_at(target.global_transform.origin, Vector3.UP)

	var direction = (target.global_transform.origin - global_transform.origin).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	var dist_to_target = global_transform.origin.distance_to(target.global_transform.origin)
	
	# Phase 1: Only melee range
	if current_phase == 1 and dist_to_target < attack_range:
		current_state = State.ATTACK
		attack_timer.start()
		velocity.x = 0.0
		velocity.z = 0.0
	# Phase 2: Attack from range
	elif current_phase == 2 and dist_to_target < 12.0:
		current_state = State.ATTACK
		attack_timer.start()
		velocity.x = 0.0
		velocity.z = 0.0

func attack_player():
	target = _find_closest_player(get_tree().get_nodes_in_group("players"))

	if not target:
		current_state = State.IDLE
		return

	velocity.x = 0.0
	velocity.z = 0.0

	var dist = global_transform.origin.distance_to(target.global_transform.origin)
	
	# Phase 1: Stop attacking if target too far
	if current_phase == 1 and dist > attack_range:
		current_state = State.CHASE
	# Phase 2: Stop attacking if target too far
	elif current_phase == 2 and dist > 12.0:
		current_state = State.CHASE

func _on_attack_timer_timeout():
	if current_state != State.ATTACK:
		return

	if target and target.has_method("take_damage"):
		if current_phase == 1:
			# Phase 1: Direct melee
			target.take_damage(melee_damage)
		else:
			# Phase 2: Ranged projectile attack
			var origin = global_transform.origin + Vector3(0, 1.2, 0)
			var dir = (target.global_transform.origin - origin).normalized()
			var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 12.0)
			query.exclude = [self]
			var result = get_world_3d().direct_space_state.intersect_ray(query)
			if not result.is_empty():
				var collider = result["collider"]
				if collider and collider.has_method("take_damage"):
					collider.take_damage(projectile_damage)

func take_damage(amount):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if current_state == State.DEAD:
		return

	health -= amount
	print("Boss HP: %d / %d (Phase %d)" % [health, max_health, current_phase])
	_update_health_bar()

	if health <= 0:
		die()

func die():
	current_state = State.DEAD
	print("Boss defeated!")
	queue_free()

func _find_closest_player(players: Array) -> Node3D:
	var closest_player: Node3D = null
	var closest_distance := INF

	for player in players:
		if not is_instance_valid(player):
			continue

		var distance = global_position.distance_squared_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player

	return closest_player

func get_sync_state() -> Dictionary:
	return {
		"position": global_position,
		"velocity": velocity,
		"rotation": rotation,
		"health": health,
		"state": current_state,
		"phase": current_phase
	}

func apply_sync_state(state: Dictionary):
	global_position = state["position"]
	velocity = state["velocity"]
	rotation = state["rotation"]
	health = state["health"]
	current_state = state["state"]
	current_phase = state.get("phase", 1)
	_update_health_bar()

func _update_health_bar():
	if health_bar and health_bar.has_method("update_from_health"):
		health_bar.update_from_health(health, max_health)
