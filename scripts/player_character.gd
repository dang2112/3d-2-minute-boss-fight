extends CharacterBody3D
# TODO: acceleration and movement physics
# TODO: input buffer (so no dropping input over net)
# TODO: rollback netcode (predicting next action based on previous action and rolling back if prediction is wrong to preserve feeling of low latency).

const SPEED = 6.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8
const MOUSE_SENS = 0.002

@onready var camera = $Camera3D
@onready var ray = $Camera3D/RayCast3D

var health := 100
var player_peer_id := 1
var is_local_player := false

var look_yaw := 0.0
var look_pitch := 0.0

var collected_input := {
	"move_x": 0.0,
	"move_z": 0.0,
	"jump": false,
	"shoot": false,
	"yaw": 0.0,
	"shot_origin": Vector3.ZERO,
	"shot_direction": Vector3.ZERO
}

var server_input := {
	"move_x": 0.0,
	"move_z": 0.0,
	"jump": false,
	"shoot": false,
	"yaw": 0.0,
	"shot_origin": Vector3.ZERO,
	"shot_direction": Vector3.ZERO
}

func _ready():
	look_yaw = rotation.y
	look_pitch = camera.rotation.x
	_update_local_player_state()

func configure_for_peer(peer_id: int):
	player_peer_id = peer_id
	name = "Player_%s" % peer_id
	_update_local_player_state()

func _update_local_player_state():
	is_local_player = multiplayer.has_multiplayer_peer() and player_peer_id == multiplayer.get_unique_id()
	camera.current = is_local_player

	if is_local_player:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event):
	if not is_local_player:
		return

	if event is InputEventMouseMotion:
		look_yaw -= event.relative.x * MOUSE_SENS
		look_pitch = clamp(look_pitch - event.relative.y * MOUSE_SENS, -1.2, 1.2)
		_apply_view_rotation(look_yaw, look_pitch)

func _physics_process(delta):
	if is_local_player:
		collect_input()

	if not multiplayer.has_multiplayer_peer():
		server_input = collected_input.duplicate(true)
		_process_authoritative_physics(delta)
		return

	if multiplayer.is_server():
		if is_local_player:
			server_input = collected_input.duplicate(true)
		_process_authoritative_physics(delta)
	else:
		if is_local_player:
			send_input_to_server()

func collect_input():
	collected_input["move_x"] = Input.get_axis("move_left", "move_right")
	collected_input["move_z"] = Input.get_axis("move_forward", "move_backward")
	collected_input["jump"] = Input.is_action_just_pressed("jump")
	collected_input["shoot"] = Input.is_action_just_pressed("primary_action")
	collected_input["yaw"] = look_yaw
	collected_input["shot_origin"] = ray.global_position
	collected_input["shot_direction"] = -camera.global_transform.basis.z

func send_input_to_server():
	rpc_id(1, "submit_input", collected_input)

@rpc("any_peer", "unreliable")
func submit_input(input_data: Dictionary):
	if not multiplayer.is_server():
		return

	if multiplayer.get_remote_sender_id() != player_peer_id:
		return

	server_input = input_data.duplicate(true)

func _process_authoritative_physics(delta):
	rotation.y = server_input["yaw"]
	look_yaw = rotation.y

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif server_input["jump"]:
		velocity.y = JUMP_VELOCITY

	var move_input = Vector3(server_input["move_x"], 0.0, server_input["move_z"])
	var input_dir = (transform.basis * move_input).normalized()

	velocity.x = input_dir.x * SPEED
	velocity.z = input_dir.z * SPEED

	move_and_slide()

	if server_input["shoot"]:
		_process_server_shot()

func _process_server_shot():
	var shot_origin: Vector3 = server_input["shot_origin"]
	var shot_direction: Vector3 = server_input["shot_direction"]

	if shot_direction.length_squared() <= 0.0:
		print("Miss")
		return

	var query := PhysicsRayQueryParameters3D.create(
		shot_origin,
		shot_origin + shot_direction.normalized() * 100.0
	)
	query.exclude = [self]

	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		print("Miss")
		return

	var collider = result["collider"]

	if collider.has_method("take_damage"):
		collider.take_damage(10)

	print("Hit: ", collider.name)

func _apply_view_rotation(yaw: float, pitch: float):
	look_yaw = yaw
	look_pitch = clamp(pitch, -1.2, 1.2)
	rotation.y = look_yaw
	camera.rotation.x = look_pitch

func get_sync_state() -> Dictionary:
	return {
		"position": global_position,
		"velocity": velocity,
		"yaw": rotation.y,
		"health": health
	}

func apply_sync_state(state: Dictionary):
	global_position = state["position"]
	velocity = state["velocity"]
	health = state["health"]
	if not is_local_player:
		rotation.y = state["yaw"]

func take_damage(amount):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	health -= amount
	print("Player HP:", health)
