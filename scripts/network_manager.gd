extends Node
# client: receives inputs and sends to server
# then receives state from server to display
#
# server: spawns players
# moves players
# runs ai
# handles shooting and damage
# then sends the states to players

enum GameState { SPAWNING, PLAYING, BOSS_FIGHT, VICTORY, GAME_OVER }

const PORT := 12345
const PLAYER_SPAWN_POSITION := Vector3(0, 8, 0)
const PLAYER_SPAWN_SPACING := 2.0
const PLAYER_SCENE := preload("res://scenes/player_character.tscn")
const ITEM_SCENE := preload("res://scenes/item.tscn")
const RANGED_SCENE := preload("res://scenes/ranged_enemy.tscn")
const TANK_SCENE := preload("res://scenes/tank_enemy.tscn")
const MELEE_SCENE := preload("res://scenes/platonic_enemy_ai.tscn")
const BOSS_SCENE := preload("res://scenes/boss.tscn")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

const GAME_PHASE_LOBBY := "lobby"
const GAME_PHASE_IN_SESSION := "in_session"

# Enemy spawn positions: melee/tank enemies (relatively close)
const MELEE_SPAWNS := [
	[Vector3(5, 1, 5), "melee"],
	[Vector3(-5, 1, 5), "melee"],
	[Vector3(5, 1, -3), "tank"],
]

# Ranged enemy spawns (far from start)
const RANGED_SPAWNS := [
	[Vector3(12, 1, 8), "ranged"],
	[Vector3(-12, 1, 8), "ranged"],
]

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
var enemies: Array = []
var items_spawned := false
var connected_peers: Dictionary = {}
var active_peer_ids: Array[int] = []
var game_phase := GAME_PHASE_LOBBY
var initial_world_templates: Array = []
var enemies_spawned := false
var boss: Node3D = null
var game_state: GameState = GameState.SPAWNING
var boss_spawn_timer: float = 0.0
var boss_ranged_spawn_timer: float = 0.0
var server_world_initializing := false
var server_world_initialized := false

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
	_connect_lobby_ui()
	# Delay UI/world setup to ensure scene tree is fully loaded
	await get_tree().process_frame
	if multiplayer.is_server():
		_initialize_server_world()
	_capture_initial_world_snapshot()
	_push_lobby_state_to_ui()

func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_update_game_state(delta)
		_broadcast_world_state()
		_broadcast_game_state.rpc(game_state)

func host_game():
	peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer

	print("Server started")
	connected_peers[str(multiplayer.get_unique_id())] = false
	_broadcast_lobby_state()
	_initialize_server_world()

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

func _initialize_server_world():
	"""Spawn server-side items/enemies once multiplayer server is ready."""
	if not multiplayer.is_server():
		return
	if server_world_initializing or server_world_initialized:
		return

	server_world_initializing = true

	# Delay one frame so the scene tree and current scene are stable
	await get_tree().process_frame

	_spawn_items()
	_spawn_initial_enemies()
	game_state = GameState.PLAYING
	boss = null
	boss_ranged_spawn_timer = 0.0
	server_world_initialized = true
	server_world_initializing = false
	print("Server world initialized")

func _on_peer_connected(peer_id: int):
	if not multiplayer.is_server():
		return

	connected_peers[str(peer_id)] = false
	_broadcast_lobby_state()

func _on_peer_disconnected(peer_id: int):
	connected_peers.erase(str(peer_id))
	active_peer_ids.erase(peer_id)
	_remove_player(peer_id)

	if multiplayer.is_server():
		despawn_player_remote.rpc(peer_id)
		if active_peer_ids.is_empty():
			_end_session_to_lobby()
		else:
			_broadcast_lobby_state()

func _on_connected_to_server():
	print("Connected to server")
	_push_lobby_state_to_ui()

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
	player.global_position = _get_spawn_position_for_peer(peer_id)
	player.configure_for_peer(peer_id)
	players[peer_id] = player

func _get_spawn_position_for_peer(peer_id: int) -> Vector3:
	var peer_keys := connected_peers.keys()
	peer_keys.sort()

	var spawn_index := peer_keys.find(str(peer_id))
	if spawn_index == -1:
		spawn_index = players.size()

	var column := spawn_index % 2
	var row := spawn_index / 2
	var offset_x := (float(column) - 0.5) * PLAYER_SPAWN_SPACING
	var offset_z := float(row) * PLAYER_SPAWN_SPACING

	return PLAYER_SPAWN_POSITION + Vector3(offset_x, 0.0, offset_z)

func _connect_lobby_ui():
	var lobby_ui = get_node_or_null("../LobbyUI")
	if lobby_ui and not lobby_ui.ready_toggled.is_connected(_on_lobby_ready_toggled):
		lobby_ui.ready_toggled.connect(_on_lobby_ready_toggled)

func _get_lobby_ui():
	return get_node_or_null("../LobbyUI")

func _get_hud():
	return get_node_or_null("../HUD")

func _remove_player(peer_id: int):
	if not players.has(peer_id):
		return

	var player = players[peer_id]
	players.erase(peer_id)

	if is_instance_valid(player):
		player.queue_free()

func handle_player_death(peer_id: int):
	if not multiplayer.is_server():
		return

	if not active_peer_ids.has(peer_id):
		return

	active_peer_ids.erase(peer_id)
	_remove_player(peer_id)
	despawn_player_remote.rpc(peer_id)

	var death_message := "Player %d has died!" % peer_id
	if active_peer_ids.has(multiplayer.get_unique_id()):
		_push_match_message(death_message)
	for active_peer_id in active_peer_ids:
		if active_peer_id != multiplayer.get_unique_id():
			receive_match_message.rpc_id(active_peer_id, death_message)

	if active_peer_ids.is_empty():
		_end_session_to_lobby()
	else:
		_broadcast_lobby_state()

func _on_lobby_ready_toggled(ready: bool):
	if not multiplayer.has_multiplayer_peer():
		return

	if multiplayer.is_server():
		_set_peer_ready(multiplayer.get_unique_id(), ready)
	else:
		rpc_id(1, "request_set_ready", ready)

@rpc("any_peer", "reliable")
func request_set_ready(ready: bool):
	if not multiplayer.is_server():
		return

	if game_phase != GAME_PHASE_LOBBY:
		return

	_set_peer_ready(multiplayer.get_remote_sender_id(), ready)

func _set_peer_ready(peer_id: int, ready: bool):
	var peer_key := str(peer_id)
	if not connected_peers.has(peer_key):
		return

	connected_peers[peer_key] = ready
	_broadcast_lobby_state()
	_try_start_session()

func _try_start_session():
	if game_phase != GAME_PHASE_LOBBY:
		return

	if connected_peers.is_empty():
		return

	for peer_key in connected_peers.keys():
		if not bool(connected_peers[peer_key]):
			return

	game_phase = GAME_PHASE_IN_SESSION
	active_peer_ids.clear()

	var peer_keys := connected_peers.keys()
	peer_keys.sort()
	for peer_key in peer_keys:
		var peer_id = int(peer_key)
		active_peer_ids.append(peer_id)
		connected_peers[peer_key] = false
		_spawn_player_for_peer(peer_id)

	_broadcast_lobby_state()

func _end_session_to_lobby():
	game_phase = GAME_PHASE_LOBBY
	active_peer_ids.clear()

	for peer_key in connected_peers.keys():
		connected_peers[peer_key] = false

	_reset_game_world()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		reset_game_world_remote.rpc()
	_broadcast_lobby_state()

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
			player.call_deferred("_update_local_player_state")
			players[peer_id] = player

		players[peer_id].apply_sync_state(state["players"][peer_id_string])
		if players[peer_id].player_peer_id == multiplayer.get_unique_id():
			players[peer_id].call_deferred("_update_local_player_state")

	for synced_object in get_tree().get_nodes_in_group("network_sync_objects"):
		var object_path = str(synced_object.get_path())
		if not state["objects"].has(object_path):
			synced_object.queue_free()

	for object_path in state["objects"].keys():
		var synced_object = get_node_or_null(NodePath(object_path))
		if synced_object == null:
			synced_object = _instantiate_synced_object(object_path, state["objects"][object_path], nav_region)
		if synced_object and synced_object.has_method("apply_sync_state"):
			synced_object.apply_sync_state(state["objects"][object_path])

func _make_lobby_state() -> Dictionary:
	return {
		"phase": game_phase,
		"connected_peers": connected_peers.duplicate(true),
		"active_peer_ids": active_peer_ids.duplicate()
	}

func _broadcast_lobby_state():
	_push_lobby_state_to_ui()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		receive_lobby_state.rpc(_make_lobby_state())

func _push_lobby_state_to_ui():
	var lobby_ui = _get_lobby_ui()
	if lobby_ui:
		var local_peer_id := 1
		if multiplayer.has_multiplayer_peer():
			local_peer_id = multiplayer.get_unique_id()
		lobby_ui.update_lobby_state(_make_lobby_state(), local_peer_id)

func _push_match_message(message: String):
	var hud = _get_hud()
	if hud and hud.has_method("show_message"):
		hud.show_message(message)

@rpc("authority", "reliable")
func receive_lobby_state(state: Dictionary):
	if multiplayer.is_server():
		return

	game_phase = str(state.get("phase", GAME_PHASE_LOBBY))
	connected_peers = state.get("connected_peers", {}).duplicate(true)
	active_peer_ids.clear()
	for peer_id in state.get("active_peer_ids", []):
		active_peer_ids.append(int(peer_id))

	_push_lobby_state_to_ui()

@rpc("authority", "reliable")
func receive_match_message(message: String):
	if multiplayer.is_server():
		return

	_push_match_message(message)

func _instantiate_synced_object(object_path: String, object_state: Dictionary, nav_region: Node3D) -> Node:
	var scene_path := str(object_state.get("scene_path", ""))
	if scene_path.is_empty():
		return null

	var scene_res := load(scene_path)
	if scene_res == null or not (scene_res is PackedScene):
		return null

	var synced_object = scene_res.instantiate()
	nav_region.add_child(synced_object)

	var sync_name := str(object_state.get("sync_name", ""))
	if sync_name.is_empty():
		var path_parts := object_path.split("/")
		sync_name = path_parts[path_parts.size() - 1]

	synced_object.name = sync_name
	return synced_object

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

func _capture_initial_world_snapshot():
	if not initial_world_templates.is_empty():
		return

	for synced_object in get_tree().get_nodes_in_group("network_sync_objects"):
		initial_world_templates.append(synced_object.duplicate())

func _reset_game_world(allow_client_reset := false):
	if not allow_client_reset and not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		return

	var nav_region = _get_navigation_region()
	if nav_region == null:
		return

	for synced_object in get_tree().get_nodes_in_group("network_sync_objects"):
		if is_instance_valid(synced_object):
			synced_object.free()

	items.clear()
	items_spawned = false

	for template in initial_world_templates:
		if not is_instance_valid(template):
			continue

		var instance = template.duplicate()
		if instance == null:
			continue

		nav_region.add_child(instance)

		if instance is CharacterBody3D and instance.has_method("get") and instance.get("item_type") != null:
			items.append(instance)
		elif instance.has_method("get") and instance.get("item_type") != null:
			items.append(instance)

	items_spawned = true

@rpc("authority", "reliable")
func reset_game_world_remote():
	if multiplayer.is_server():
		return

	_reset_game_world(true)

func _spawn_initial_enemies():
	"""Spawn melee/tank enemies at fixed positions (server only)"""
	if enemies_spawned:
		return
	
	var nav_region = _get_navigation_region()
	if nav_region == null:
		print("ERROR: Cannot spawn enemies - navigation region not found")
		return
	
	# Spawn melee and tank enemies
	for spawn_data in MELEE_SPAWNS:
		var position = spawn_data[0]
		var enemy_type = spawn_data[1]
		
		var scene = MELEE_SCENE if enemy_type == "melee" else TANK_SCENE
		var enemy = scene.instantiate()
		nav_region.add_child(enemy)
		enemy.global_position = position
		enemies.append(enemy)
	
	# Spawn initial ranged enemies
	for spawn_data in RANGED_SPAWNS:
		var position = spawn_data[0]
		var enemy = RANGED_SCENE.instantiate()
		nav_region.add_child(enemy)
		enemy.global_position = position
		enemies.append(enemy)
	
	enemies_spawned = true
	print("Spawned %d initial enemies" % enemies.size())

func _update_game_state(delta):
	"""Update game state and handle transitions (server only)"""
	# Check if all players are knocked out -> GAME_OVER
	if game_state != GameState.GAME_OVER and game_state != GameState.VICTORY:
		if _all_players_knocked():
			game_state = GameState.GAME_OVER
			print("All players knocked! GAME OVER!")
			return
	
	match game_state:
		GameState.PLAYING:
			# Only spawn boss when all regular enemies are dead
			if not _check_enemies_alive() and boss == null:
				# All regular enemies dead - spawn boss once
				_spawn_boss()
				game_state = GameState.BOSS_FIGHT
				print("All enemies killed! Boss spawned! Entering BOSS_FIGHT state")
		
		GameState.BOSS_FIGHT:
			boss_ranged_spawn_timer += delta
			if boss_ranged_spawn_timer >= 10.0:
				_spawn_periodic_ranged_enemy()
				boss_ranged_spawn_timer = 0.0
			
			if boss == null or not is_instance_valid(boss):
				game_state = GameState.VICTORY
				print("Boss defeated! VICTORY!")
				_broadcast_victory()
		
		GameState.VICTORY:
			pass  # Wait for players to press M to return to menu
		
		GameState.GAME_OVER:
			pass  # All players dead
	
	# Clean up dead enemies from array
	enemies = enemies.filter(func(e): return is_instance_valid(e))

func _check_enemies_alive() -> bool:
	"""Return true if there are any regular enemies alive"""
	for enemy in enemies:
		if is_instance_valid(enemy):
			return true
	return false

func _all_players_knocked() -> bool:
	"""Return true if all players are knocked out"""
	if players.is_empty():
		return false
	
	for peer_id in players:
		var player = players[peer_id]
		if is_instance_valid(player) and not player.is_knocked:
			return false
	return true

func _spawn_boss():
	"""Spawn boss at center of arena (server only)"""
	if boss != null and is_instance_valid(boss):
		return
	
	var nav_region = _get_navigation_region()
	if nav_region == null:
		return
	
	boss = BOSS_SCENE.instantiate()
	nav_region.add_child(boss)
	boss.global_position = Vector3(0, 1, 0)
	boss.add_to_group("network_sync_objects")

func _spawn_periodic_ranged_enemy():
	"""Spawn 3 random ranged enemies during boss fight (server only)"""
	var nav_region = _get_navigation_region()
	if nav_region == null:
		return
	
	for i in range(3):
		var enemy = RANGED_SCENE.instantiate()
		nav_region.add_child(enemy)
		# Spawn near a live player so the ranged enemy can reliably shoot,
		# but keep enough space for dodging.
		var anchor := _get_spawn_anchor_player_position()
		var angle = randf() * TAU
		var distance = randf_range(8.0, 11.0)
		var pos = anchor + Vector3(cos(angle) * distance, 1, sin(angle) * distance)
		enemy.global_position = pos
		enemies.append(enemy)

func _get_spawn_anchor_player_position() -> Vector3:
	"""Pick a player position to bias boss-phase ranged spawns near combat."""
	for peer_id in players.keys():
		var player = players[peer_id]
		if is_instance_valid(player) and not player.is_knocked:
			return player.global_position

	if not players.is_empty():
		for peer_id in players.keys():
			var player = players[peer_id]
			if is_instance_valid(player):
				return player.global_position

	return Vector3.ZERO

@rpc("authority", "reliable")
func _broadcast_victory():
	"""Notify all clients game is over - players defeated boss"""
	if not multiplayer.is_server():
		game_state = GameState.VICTORY

@rpc("authority", "unreliable")
func _broadcast_game_state(new_state: int):
	"""Broadcast current game state to all clients"""
	if not multiplayer.is_server():
		game_state = new_state

func _return_to_main_menu():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null

	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
