extends CanvasLayer

@onready var health_bar: ProgressBar = $RootPanel/Margin/VBox/HealthBar
@onready var health_label: Label = $RootPanel/Margin/VBox/HealthLabel
@onready var buff_label: Label = $RootPanel/Margin/VBox/BuffLabel

var local_player: Node = null

func _ready():
	health_bar.max_value = 200
	health_bar.value = 100
	health_bar.show_percentage = false
	health_bar.add_theme_stylebox_override("fill", _make_fill_style(Color(0.2, 0.8, 0.2, 1.0)))
	health_bar.add_theme_stylebox_override("background", _make_fill_style(Color(0.08, 0.08, 0.08, 0.9)))
	health_label.text = "HP: 100 / 200"
	buff_label.text = "DMG x1.0   SPD 6.0"

func _process(_delta):
	local_player = _find_local_player()
	if not local_player:
		health_label.text = "Waiting for player..."
		buff_label.text = ""
		return

	var hp := int(local_player.health)
	var dmg := float(local_player.damage_multiplier)
	var speed := float(local_player.current_speed)
	var max_hp := 200

	health_bar.max_value = max_hp
	health_bar.value = clamp(hp, 0, max_hp)
	health_label.text = "HP: %d / %d" % [hp, max_hp]
	buff_label.text = "DMG x%.1f   SPD %.1f" % [dmg, speed]

func _find_local_player() -> Node:
	for player in get_tree().get_nodes_in_group("players"):
		if player and player.is_local_player:
			return player
	return null

func _make_fill_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 0
	style.border_width_right = 0
	style.border_width_top = 0
	style.border_width_bottom = 0
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style
