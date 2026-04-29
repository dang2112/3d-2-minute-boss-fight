extends CharacterBody3D
# Bosses just extend this platonic enemy

enum State {
	IDLE,
	CHASE,
	ATTACK,
	DEAD
} # TODO: state transitions, more sophisticated state machine

var current_state = State.IDLE

const GRAVITY = 9.8

@onready var agent = $NavigationAgent3D
@onready var attack_timer = $AttackTimer

var target = null
var speed = 3.0
var health = 100
var attack_range = 2.5

func _ready():
	add_to_group("network_sync_objects")
	attack_timer.wait_time = 1.0
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
	agent.target_position = target.global_transform.origin
	var next_pos = agent.get_next_path_position()

	var direction = (next_pos - global_transform.origin).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0

	if global_transform.origin.distance_to(target.global_transform.origin) < attack_range:
		current_state = State.ATTACK
		attack_timer.start()

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
		target.take_damage(10)

func take_damage(amount):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if current_state == State.DEAD:
		return

	health -= amount
	print("Enemy HP:", health)

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
