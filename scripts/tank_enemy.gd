extends CharacterBody3D
# Tank Enemy - slow, durable, high damage melee unit
# Acts as a "road blocker" that forces players to deal with it

enum State {
	IDLE,
	CHASE,
	ATTACK,
	DEAD
}

var current_state = State.IDLE

const GRAVITY = 9.8

@onready var attack_timer = $AttackTimer
@onready var health_bar = $HealthBar3D

var target = null
var speed = 2.0  # Slow
var max_health = 200  # Durable
var health = 200
var attack_range = 2.5
var attack_damage = 20  # High melee damage
var attack_cooldown = 1.5

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

	if global_transform.origin.distance_to(target.global_transform.origin) < attack_range:
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

	if global_transform.origin.distance_to(target.global_transform.origin) > attack_range:
		current_state = State.CHASE

func _on_attack_timer_timeout():
	if current_state != State.ATTACK:
		return

	if target and target.has_method("take_damage"):
		target.take_damage(attack_damage)

func take_damage(amount):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if current_state == State.DEAD:
		return

	health -= amount
	print("Tank Enemy HP:", health)
	_update_health_bar()

	if health <= 0:
		die()

func die():
	current_state = State.DEAD
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
