extends CharacterBody3D

const PROJECTILE_SCENE = preload("res://scenes/projectile.tscn")

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
var speed = 0.0
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

	match current_state:
		State.IDLE:
			_look_for_player()
		State.PATROL:
			_patrol(delta)
		State.CHASE:
			_chase(delta)
		State.ATTACK:
			_attack()

	move_and_slide()

func _look_for_player():
	var closest = _find_closest_player(get_tree().get_nodes_in_group("players"))
	if closest == null:
		return

	var closest_d = global_position.distance_to(closest.global_position)
	if closest and closest_d <= attack_range * 1.5:
		target = closest
		current_state = State.CHASE

func _chase(delta):
	target = _find_closest_player(get_tree().get_nodes_in_group("players"))

	if not target or not is_instance_valid(target):
		current_state = State.IDLE
		return
	var to_target = target.global_position - global_position
	# Face the target but remain stationary (ranged enemy is fixed)
	look_at(target.global_transform.origin, Vector3.UP)

	if to_target.length() <= attack_range:
		current_state = State.ATTACK
		attack_timer.start()
		velocity.x = 0
		velocity.z = 0
		return

	# Do not set velocity; keep enemy in place
	velocity.x = 0
	velocity.z = 0

func _patrol(delta):
	# Simple placeholder patrol (no pathing yet)
	velocity.x = 0
	velocity.z = 0

func _attack():
	target = _find_closest_player(get_tree().get_nodes_in_group("players"))

	if not target or not is_instance_valid(target):
		current_state = State.IDLE
		return

	var to_target = target.global_position - global_position
	look_at(target.global_transform.origin, Vector3.UP)
	velocity.x = 0
	velocity.z = 0

	if to_target.length() > attack_range:
		current_state = State.CHASE

func _on_attack_timer_timeout():
	if current_state != State.ATTACK:
		return

	target = _find_closest_player(get_tree().get_nodes_in_group("players"))
	if not target or not is_instance_valid(target):
		current_state = State.IDLE
		return

	# If target went invalid or moved out of attack range, stop attacking
	if not target or not is_instance_valid(target):
		current_state = State.IDLE
		return
	var dist_to_target := global_position.distance_to(target.global_position)
	# allow a small hysteresis so it doesn't flicker when near the edge
	if dist_to_target > attack_range * 1.2:
		current_state = State.CHASE
		return
	if target.has_method("take_damage"):
		_spawn_projectile()
		attack_timer.start()

func _spawn_projectile():
	var nav_region = _get_navigation_region()
	if nav_region == null:
		return

	var projectile = PROJECTILE_SCENE.instantiate()
	projectile.name = "RangedProjectile_%d" % Time.get_ticks_usec()
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
	projectile.setup(dir, 11.0, attack_damage, self, attack_range * 2.0)

func _get_navigation_region() -> Node3D:
	var root_scene := get_tree().current_scene
	if root_scene == null:
		return null

	var found := root_scene.find_child("NavigationRegion3D", true, false)
	if found is Node3D:
		return found

	return root_scene.find_child("MapArena", true, false) as Node3D

func _find_closest_player(players: Array) -> Node3D:
	var closest_player: Node3D = null
	var closest_distance := INF

	for player in players:
		if not is_instance_valid(player):
			continue
		if player.has_method("get") and float(player.get("health")) <= 0.0:
			continue

		var distance = global_position.distance_squared_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player

	return closest_player

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
		"state": current_state,
		"sync_name": name,
		"scene_path": "res://scenes/ranged_enemy.tscn"
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

func _is_match_finished() -> bool:
	var root_scene := get_tree().current_scene
	if root_scene == null:
		return false

	var network_manager = root_scene.find_child("NetworkManager", true, false)
	if network_manager == null:
		return false

	return network_manager.game_state == network_manager.GameState.VICTORY or network_manager.game_state == network_manager.GameState.GAME_OVER
