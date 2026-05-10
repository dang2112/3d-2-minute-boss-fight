extends CharacterBody3D

enum ItemType {
	DAMAGE_BOOST,
	HEALTH_REGEN,
	SPEED_BOOST
}

const ITEM_TYPE_NAMES = {
	ItemType.DAMAGE_BOOST: "Damage Boost",
	ItemType.HEALTH_REGEN: "Health Regen",
	ItemType.SPEED_BOOST: "Speed Boost"
}

const ITEM_EFFECTS = {
	ItemType.DAMAGE_BOOST: {"damage": 5},
	ItemType.HEALTH_REGEN: {"health": 20},
	ItemType.SPEED_BOOST: {"speed": 1.5}
}

const ITEM_COLORS = {
	ItemType.DAMAGE_BOOST: Color.RED,
	ItemType.HEALTH_REGEN: Color.GREEN,
	ItemType.SPEED_BOOST: Color.YELLOW
}

var item_type: ItemType = ItemType.DAMAGE_BOOST
var item_id: String = ""
var is_collected := false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var area_detector: Area3D = $Area3D

func _ready():
	add_to_group("network_sync_objects")
	
	# Set collision layers for item itself (so it doesn't interfere with physics)
	collision_layer = 2  # Items on layer 2
	collision_mask = 0   # Items don't collide with anything
	
	# Setup collision for pickup detection
	if collision_shape:
		collision_shape.disabled = false
	
	# Setup area detector for pickup
	if area_detector:
		# Set collision layers for item area
		area_detector.collision_layer = 0  # Don't be on any layer
		area_detector.collision_mask = 1   # Detect objects on layer 1 (players)
		area_detector.area_entered.connect(_on_area_entered)
		area_detector.body_entered.connect(_on_area_body_entered)
		print("Item Area3D configured - mask: %d" % area_detector.collision_mask)
	
	# Generate unique item ID
	item_id = "item_%s_%d" % [name, randi()]
	_apply_item_color()

func _apply_item_color():
	"""Apply visual color based on item type"""
	if not mesh_instance:
		return
	
	var material = StandardMaterial3D.new()
	material.albedo_color = ITEM_COLORS[item_type]
	material.metallic = 0.5
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission = ITEM_COLORS[item_type] * 0.5
	
	if mesh_instance.mesh.get_surface_count() > 0:
		mesh_instance.set_surface_override_material(0, material)

func _physics_process(delta):
	# Gentle bobbing animation
	position.y += sin(Time.get_ticks_msec() * 0.002) * 0.5 * delta

func _on_area_entered(area: Area3D):
	"""Detect when any area enters (for multiplayer sync)"""
	if is_collected:
		return
	
	# Check if area is player area or related to player
	if area.owner and area.owner.is_in_group("players"):
		_handle_pickup(area.owner)

func _on_area_body_entered(body: Node3D):
	"""Detect when body enters area (player is CharacterBody3D)"""
	if is_collected:
		return
	
	if body.is_in_group("players") and body.has_method("pickup_item"):
		_handle_pickup(body)

func _handle_pickup(player):
	"""Handle item pickup"""
	if is_collected or not player:
		return
	
	print("Item picked up by %s" % player.name)
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# Server authority: notify all clients and apply effect
		is_collected = true
		player.pickup_item(item_type, ITEM_EFFECTS[item_type])
		queue_free()
	elif multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Client: send RPC to server
		take_item_on_server.rpc(player.player_peer_id, item_type)
	else:
		# Single player: apply immediately
		player.pickup_item(item_type, ITEM_EFFECTS[item_type])
		is_collected = true
		queue_free()

@rpc("authority", "reliable")
func take_item_on_server(player_peer_id: int, item_type_value: int):
	if multiplayer.is_server():
		is_collected = true
		
		# Find player and apply effect
		var players = get_tree().get_nodes_in_group("players")
		for player in players:
			if player.player_peer_id == player_peer_id:
				player.pickup_item(item_type_value, ITEM_EFFECTS[item_type_value])
				break
		
		queue_free()
	else:
		# Client-side: just hide item
		is_collected = true
		queue_free()

func get_sync_state() -> Dictionary:
	return {
		"position": global_position,
		"item_type": item_type,
		"is_collected": is_collected,
		"sync_name": name,
		"scene_path": "res://scenes/item.tscn"
	}

func apply_sync_state(state: Dictionary):
	if state["is_collected"]:
		queue_free()
		return
	
	global_position = state["position"]
	item_type = state["item_type"]
	_apply_item_color()
