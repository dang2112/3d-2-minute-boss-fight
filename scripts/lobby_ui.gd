extends CanvasLayer

signal ready_toggled(ready: bool)

@onready var title_label: Label = $Root/CenterContainer/Panel/Margin/VBox/Title
@onready var status_label: Label = $Root/CenterContainer/Panel/Margin/VBox/Status
@onready var players_label: Label = $Root/CenterContainer/Panel/Margin/VBox/Players
@onready var ready_button: Button = $Root/CenterContainer/Panel/Margin/VBox/ReadyButton

var local_ready := false

func update_lobby_state(state: Dictionary, local_peer_id: int):
	var phase := str(state.get("phase", "lobby"))
	var connected_peers: Dictionary = state.get("connected_peers", {})
	var active_peer_ids: Array = state.get("active_peer_ids", [])
	var local_key := str(local_peer_id)
	var is_local_active := active_peer_ids.has(local_peer_id)

	visible = phase == "lobby" or not is_local_active
	if not visible:
		return

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	title_label.text = "Lobby"
	local_ready = bool(connected_peers.get(local_key, false))

	if phase == "in_session":
		status_label.text = "Game in session"
		ready_button.disabled = true
		ready_button.text = "Waiting for next round"
	else:
		status_label.text = "Waiting for players"
		ready_button.disabled = false
		ready_button.text = "Unready" if local_ready else "Ready Up"

	var lines: Array[String] = []
	var peer_keys := connected_peers.keys()
	peer_keys.sort()

	for peer_key in peer_keys:
		var is_ready = bool(connected_peers[peer_key])
		var peer_id = int(peer_key)
		var line_status := "In Game" if active_peer_ids.has(peer_id) else ("Ready" if is_ready else "Waiting")
		lines.append("Player %s: %s" % [peer_key, line_status])

	players_label.text = "\n".join(lines)

func _on_ready_button_pressed():
	ready_toggled.emit(not local_ready)
