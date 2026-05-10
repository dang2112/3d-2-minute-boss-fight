extends CharacterBody3D

const PROJECTILE_SCENE = preload("res://scenes/projectile.tscn")
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
var phase2_cooldown = 0.5  # 4x faster in phase 2
var phase2_trigger = 250  # 50% HP

func _ready():
	add_to_group("network_sync_objects")
	attack_timer.wait_time = attack_cooldown
	attack_timer.timeout.connect(_on_attack_timer_timeout)

func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if _is_match_finished():
		velocity = Vector3.ZERO
		move_and_slide()
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
		attack_timer.wait_time = phase2_cooldown
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
			# Phase 2: Visible ranged projectile attack
			_spawn_projectile()

	attack_timer.start()

func _spawn_projectile():
	var nav_region = _get_navigation_region()
	if nav_region == null:
		return

	var projectile = PROJECTILE_SCENE.instantiate()
	projectile.name = "BossProjectile_%d" % Time.get_ticks_usec()
	nav_region.add_child(projectile)
	projectile.global_position = global_transform.origin + Vector3(0, 1.2, 0)
	if not target or not is_instance_valid(target):
		projectile.queue_free()
		return
	# Aim vertically at the player's head if they have a Camera3D, otherwise at their center
	var aim_y: float = target.global_position.y
	var target_cam: Camera3D = target.get_node_or_null("Camera3D") as Camera3D
	if target_cam != null:
		aim_y = target_cam.global_position.y
	# Aim on the same horizontal plane as the projectile but vertically at aim_y
	var aim_target: Vector3 = Vector3(target.global_position.x, aim_y, target.global_position.z)
	var dir: Vector3 = (aim_target - projectile.global_position).normalized()
	projectile.setup(dir, 9.0, projectile_damage, self, 24.0)

func _get_navigation_region() -> Node3D:
	var root_scene := get_tree().current_scene
	if root_scene == null:
		return null

	var found := root_scene.find_child("NavigationRegion3D", true, false)
	if found is Node3D:
		return found

	return root_scene.find_child("MapArena", true, false) as Node3D

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
		"phase": current_phase,
		"sync_name": name,
		"scene_path": "res://scenes/boss.tscn"
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

func _is_match_finished() -> bool:
	var root_scene := get_tree().current_scene
	if root_scene == null:
		return false

	var network_manager = root_scene.find_child("NetworkManager", true, false)
	if network_manager == null:
		return false

	return network_manager.game_state == network_manager.GameState.VICTORY or network_manager.game_state == network_manager.GameState.GAME_OVER
