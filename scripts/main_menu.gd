extends Control

const GAME_SCENE := preload("res://scenes/game.tscn")

@onready var ip_input: LineEdit = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/IpInput

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ip_input.text = "127.0.0.1"

func _on_host_button_pressed():
	_open_game(true)

func _on_join_button_pressed():
	_open_game(false)

func _on_quit_button_pressed():
	get_tree().quit()

func _open_game(as_host: bool):
	var game = GAME_SCENE.instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	hide()

	var network_manager = game.get_node("NetworkManager")
	if as_host:
		network_manager.host_game()
	else:
		network_manager.join_game(ip_input.text.strip_edges())

	queue_free()
