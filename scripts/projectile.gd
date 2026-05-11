extends Node3D

const PROJECTILE_SCENE_PATH := "res://scenes/projectile.tscn"

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var hit_area: Area3D = $Area3D

var direction: Vector3 = Vector3.FORWARD
var speed := 10.0
var damage := 10
var max_distance := 30.0
var traveled_distance := 0.0
var owner_path: NodePath = NodePath()

func _ready():
	add_to_group("network_sync_objects")
	_apply_visual_orientation()
	_apply_visual_color()

func setup(new_direction: Vector3, new_speed: float, new_damage: int, new_owner: Node = null, new_max_distance: float = 30.0):
	direction = new_direction.normalized()
	speed = new_speed
	damage = new_damage
	max_distance = new_max_distance
	traveled_distance = 0.0

	if new_owner and is_instance_valid(new_owner):
		owner_path = new_owner.get_path()

	_apply_visual_orientation()

func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if direction.length_squared() == 0.0:
		return

	var start_position := global_position
	var step: Vector3 = direction.normalized() * speed * delta
	global_position += step
	traveled_distance += step.length()

	_apply_visual_orientation()
	_check_hit(start_position, global_position)

	if traveled_distance >= max_distance:
		queue_free()

func _apply_visual_orientation():
	# Orient projectile fully along its travel vector (allow pitch/roll)
	if direction.length_squared() > 0.0:
		look_at(global_position + direction.normalized(), Vector3.UP)

func _apply_visual_color():
	if not mesh_instance:
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.9, 0.2, 1.0)
	material.metallic = 0.15
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = Color(1.0, 0.85, 0.2, 1.0)

	if mesh_instance.mesh and mesh_instance.mesh.get_surface_count() > 0:
		mesh_instance.set_surface_override_material(0, material)

func _check_hit(start_position: Vector3, end_position: Vector3):
	var world := get_world_3d()
	if world == null:
		return

	var query := PhysicsRayQueryParameters3D.create(start_position, end_position)
	query.exclude = []
	if hit_area:
		query.exclude.append(hit_area.get_rid())
	query.collide_with_bodies = true
	query.collide_with_areas = true

	if owner_path != NodePath():
		var owner_node := get_node_or_null(owner_path)
		if owner_node and owner_node is CollisionObject3D:
			query.exclude.append((owner_node as CollisionObject3D).get_rid())

	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return

	var collider = result["collider"]
	if collider and collider.is_in_group("players") and collider.has_method("take_damage"):
		collider.take_damage(damage)

	queue_free()

func get_sync_state() -> Dictionary:
	return {
		"position": global_position,
		"direction": direction,
		"speed": speed,
		"damage": damage,
		"max_distance": max_distance,
		"traveled_distance": traveled_distance,
		"sync_name": name,
		"scene_path": PROJECTILE_SCENE_PATH,
	}

func apply_sync_state(state: Dictionary):
	global_position = state["position"]
	direction = state["direction"]
	speed = state["speed"]
	damage = state["damage"]
	max_distance = state.get("max_distance", max_distance)
	traveled_distance = state.get("traveled_distance", traveled_distance)

	var synced_name: String = str(state.get("sync_name", name))
	if name != synced_name:
		name = synced_name

	_apply_visual_orientation()