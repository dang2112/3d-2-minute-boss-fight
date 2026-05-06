extends Sprite3D

@export var bar_width := 128
@export var bar_height := 16
@export var bar_color := Color(1.0, 0.15, 0.1, 1.0)
@export var background_color := Color(0.08, 0.02, 0.02, 0.85)

@export var face_camera: bool = true
@export var face_y_only: bool = true

var _texture: ImageTexture
var _last_ratio: float = -1.0

func _ready():
	# Avoid assigning billboard constant (editor GDScript type resolver may misidentify enum)
	# billboard = Sprite3D.BILLBOARD_ENABLED
	pixel_size = 0.01
	hide()
	_texture = ImageTexture.create_from_image(_build_image(1.0))
	texture = _texture
	update_from_health()

func update_from_health(current_health: float = -1.0, max_health: float = -1.0):
	var owner_node = get_parent()
	if current_health < 0.0 and owner_node:
		var owner_health = owner_node.get("health")
		if owner_health != null:
			current_health = float(owner_health)
	if max_health < 0.0 and owner_node:
		var owner_max_health = owner_node.get("max_health")
		if owner_max_health != null:
			max_health = float(owner_max_health)
	if current_health < 0.0:
		return
	if max_health <= 0.0:
		max_health = 1.0

	var ratio: float = clamp(current_health / max_health, 0.0, 1.0)
	if is_equal_approx(ratio, _last_ratio):
		return
	_last_ratio = ratio
	texture = ImageTexture.create_from_image(_build_image(ratio))
	visible = true

func _build_image(ratio: float) -> Image:
	var image: Image = Image.create(bar_width, bar_height, false, Image.FORMAT_RGBA8)
	image.fill(background_color)

	var fill_width: int = int(round(bar_width * ratio))
	for x in range(fill_width):
		for y in range(bar_height):
			image.set_pixel(x, y, bar_color)
	return image

func _process(delta: float) -> void:
	if not face_camera:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var cam_pos: Vector3 = cam.global_transform.origin
	var my_pos: Vector3 = global_transform.origin
	if face_y_only:
		var target: Vector3 = Vector3(cam_pos.x, my_pos.y, cam_pos.z)
		look_at(target, Vector3.UP)
	else:
		look_at(cam_pos, Vector3.UP)
