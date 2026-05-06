extends Node
# client: receives inputs and sends to server
# then receives state from server to display
#
# server: spawns players
# moves players
# runs ai
# handles shooting and damage
# then sends the states to players

const PORT := 12345
const PLAYER_SPAWN_POSITION := Vector3(0, 8, 0)
const PLAYER_SCENE := preload("res://scenes/player_character.tscn")
const ITEM_SCENE := preload("res://scenes/item.tscn")
const RANGED_SCENE := preload("res://scenes/ranged_enemy.tscn")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

# Item spawn data: [position, item_type]
const ITEM_SPAWNS := [
	[Vector3(3, 1.5, 5), 0],  # DAMAGE_BOOST
	[Vector3(-3, 1.5, 5), 1],  # HEALTH_REGEN
	[Vector3(3, 1.5, -5), 2],  # SPEED_BOOST
	[Vector3(-3, 1.5, -5), 0],  # DAMAGE_BOOST
	[Vector3(0, 1.5, -8), 1],  # HEALTH_REGEN
]

var peer: ENetMultiplayerPeer
var players: Dictionary = {}
var items: Array = []
var items_spawned := false

func _get_navigation_region() -> Node3D:
	"""Get or find navigation region"""
	var root_scene := get_tree().current_scene
	if root_scene == null:
		root_scene = get_parent()
	
	if root_scene == null:
		return null

	var found := root_scene.find_child("NavigationRegion3D", true, false)
	if found is Node3D:
		return found

	return root_scene.find_child("MapArena", true, false) as Node3D

func _ready():
	_connect_multiplayer_signals()
	# Delay spawn items to ensure scene tree is fully loaded
	await get_tree().process_frame
	_spawn_items()

func _physics_process(_delta):
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_broadcast_world_state()

func host_game():
	peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer

	print("Server started")
	_spawn_player_for_peer(multiplayer.get_unique_id())

func join_game(ip):
	peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, PORT)
	multiplayer.multiplayer_peer = peer

	print("Connecting to server: ", ip)

func _connect_multiplayer_signals():
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_peer_connected(peer_id: int):
	if not multiplayer.is_server():
		return

	_spawn_player_for_peer(peer_id)

func _on_peer_disconnected(peer_id: int):
	_remove_player(peer_id)

	if multiplayer.is_server():
		despawn_player_remote.rpc(peer_id)

func _on_connected_to_server():
	print("Connected to server")

func _on_connection_failed():
	print("Connection failed")
	_return_to_main_menu()

func _on_server_disconnected():
	print("Disconnected from server")
	_return_to_main_menu()

func _spawn_player_for_peer(peer_id: int):
	if players.has(peer_id):
		return

	var nav_region = _get_navigation_region()
	if nav_region == null:
		print("ERROR: Cannot find navigation region to spawn player")
		return

	var player = PLAYER_SCENE.instantiate()
	nav_region.add_child(player)
	player.global_position = PLAYER_SPAWN_POSITION
	player.configure_for_peer(peer_id)
	players[peer_id] = player

func _remove_player(peer_id: int):
	if not players.has(peer_id):
		return

	var player = players[peer_id]
	players.erase(peer_id)

	if is_instance_valid(player):
		player.queue_free()

@rpc("authority", "reliable")
func despawn_player_remote(peer_id: int):
	if multiplayer.is_server():
		return

	_remove_player(peer_id)

func _broadcast_world_state():
	var state := {
		"players": {},
		"objects": {}
	}

	for peer_id in players.keys():
		var player = players[peer_id]
		if is_instance_valid(player):
			state["players"][str(peer_id)] = player.get_sync_state()

	for synced_object in get_tree().get_nodes_in_group("network_sync_objects"):
		if synced_object.has_method("get_sync_state"):
			state["objects"][str(synced_object.get_path())] = synced_object.get_sync_state()

	receive_world_state.rpc(state)

@rpc("authority", "unreliable")
func receive_world_state(state: Dictionary):
	if multiplayer.is_server():
		return

	var nav_region = _get_navigation_region()
	if nav_region == null:
		return

	for peer_id_string in state["players"].keys():
		var peer_id = int(peer_id_string)
		if not players.has(peer_id):
			var player = PLAYER_SCENE.instantiate()
			nav_region.add_child(player)
			player.configure_for_peer(peer_id)
			players[peer_id] = player

		players[peer_id].apply_sync_state(state["players"][peer_id_string])

	for synced_object in get_tree().get_nodes_in_group("network_sync_objects"):
		var object_path = str(synced_object.get_path())
		if not state["objects"].has(object_path):
			synced_object.queue_free()

	for object_path in state["objects"].keys():
		var synced_object = get_node_or_null(NodePath(object_path))
		if synced_object and synced_object.has_method("apply_sync_state"):
			synced_object.apply_sync_state(state["objects"][object_path])

func _spawn_items():
	"""Spawn items on server only (will be synced to clients via _broadcast_world_state)"""
	if items_spawned:
		return
	
	var nav_region = _get_navigation_region()
	if nav_region == null:
		print("ERROR: Cannot spawn items - navigation region not found")
		return
	
	for spawn_data in ITEM_SPAWNS:
		var position = spawn_data[0]
		var item_type = spawn_data[1]
		
		var item = ITEM_SCENE.instantiate()
		nav_region.add_child(item)
		item.item_type = item_type
		item.global_position = position
		item._apply_item_color()
		items.append(item)

	items_spawned = true
	print("Spawned %d items" % items.size())

func _return_to_main_menu():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null

	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
