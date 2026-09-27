extends NetTransport
class_name ENetTransport

## Default transport: plain UDP via ENet (LAN / direct IP / port-forwarded host,
## or a dedicated server with a public address). Unencrypted -- see the trust
## model in systems/net/README.md.


func id() -> String:
	return "enet"


func create_host(port: int, max_clients: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	last_error = peer.create_server(port, max_clients)
	if last_error != OK:
		return null
	return peer


func create_client(address: String, port: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	last_error = peer.create_client(address, port)
	if last_error != OK:
		return null
	return peer
