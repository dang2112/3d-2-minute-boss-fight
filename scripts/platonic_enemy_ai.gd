extends CharacterBody3D
#Bosses just extend this platonic enemy
#TODO: move ai to server for multiplayer

enum State {
	IDLE,
	CHASE,
	ATTACK,
	DEAD
} #TODO: state transitions, more sophisticated state machine

var current_state = State.IDLE

const GRAVITY = 9.8

@onready var agent = $NavigationAgent3D
@onready var attack_timer = $AttackTimer

var target = null
var speed = 3.0
var health = 100
var attack_range = 2.5

func _ready():
	attack_timer.wait_time = 1.0
	attack_timer.timeout.connect(_on_attack_timer_timeout)

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		move_and_slide()
	
	if current_state == State.DEAD:
		return

	match current_state:
		State.IDLE:
			look_for_player()

		State.CHASE:
			chase_player()

		State.ATTACK:
			attack_player()

func look_for_player():
	var players = get_tree().get_nodes_in_group("players")
	
	if players.size() > 0:
		target = players[0]
		current_state = State.CHASE

func chase_player():
	if not target:
		current_state = State.IDLE
		return

	look_at(target.global_transform.origin, Vector3.UP)
	agent.target_position = target.global_transform.origin
	var next_pos = agent.get_next_path_position()

	var direction = (next_pos - global_transform.origin).normalized()
	velocity = direction * speed
	if agent.is_navigation_finished():
		velocity = Vector3.ZERO
	move_and_slide()

	# Switch to attack if close enough
	if global_transform.origin.distance_to(target.global_transform.origin) < attack_range:
		current_state = State.ATTACK
		attack_timer.start()

func attack_player():
	if not target:
		current_state = State.IDLE
		return

	velocity = Vector3.ZERO
	move_and_slide()

	# If player moved away, chase again
	if global_transform.origin.distance_to(target.global_transform.origin) > attack_range:
		current_state = State.CHASE

func _on_attack_timer_timeout():
	if current_state != State.ATTACK:
		return

	if target and target.has_method("take_damage"):
		target.take_damage(10)

func take_damage(amount):
	if current_state == State.DEAD:
		return

	health -= amount
	print("Enemy HP:", health)

	if health <= 0:
		die()

func die():
	current_state = State.DEAD
	queue_free()
