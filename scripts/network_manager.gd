extends Node
#client: receives inputs and sends to server
#then receives state from server to display

#server: moves players
#runs ai
#handles shooting and damage
#then sends the states to players

var peer

func host_game():
	peer = ENetMultiplayerPeer.new()
	peer.create_server(12345)
	multiplayer.multiplayer_peer = peer
	
	print("Server started")

func join_game(ip):
	peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, 12345)
	multiplayer.multiplayer_peer = peer
	
	print("Connected to server")
