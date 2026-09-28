extends RefCounted
## Shared helpers for the in-process multiplayer tests.
##
## Each simulated peer is a plain Node ("HostPeer", "ClientPeer", ...) that owns
## its OWN SceneMultiplayer (SceneTree.set_multiplayer on the node's path) and a
## NetSessionNode child named "NetSession". Every peer subtree therefore has the
## identical relative path "NetSession", which is what makes RPCs line up, and the
## SceneTree polls every registered custom MultiplayerAPI each frame, so real ENet
## traffic flows over 127.0.0.1 inside a single headless process.

const NET_SESSION_SCRIPT := preload("res://systems/net/NetSession.gd")


## Build a peer root under [param parent]; returns { root, session, api }.
static func make_peer(parent: Node, peer_name: String) -> Dictionary:
	var root := Node.new()
	root.name = peer_name
	parent.add_child(root)
	var api := SceneMultiplayer.new()
	parent.get_tree().set_multiplayer(api, root.get_path())
	var session: NetSessionNode = NET_SESSION_SCRIPT.new()
	session.name = "NetSession"
	root.add_child(session)
	return {"root": root, "session": session, "api": api}


## Close a peer's session and detach its MultiplayerAPI.
static func free_peer(peer: Dictionary) -> void:
	if peer.is_empty():
		return
	var root: Node = peer.get("root")
	var session = peer.get("session")
	if session != null and is_instance_valid(session):
		session.leave()
	if root != null and is_instance_valid(root):
		if root.is_inside_tree():
			root.get_tree().set_multiplayer(null, root.get_path())
		root.queue_free()


## A random high port so parallel / repeated runs do not collide.
static func random_port() -> int:
	return 20000 + (randi() % 30000)


## Pump frames until [param cond] returns true or [param timeout_ms] elapse
## (wall clock -- headless frames are not rate limited).
static func wait_until(tree: SceneTree, cond: Callable, timeout_ms: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await tree.process_frame
	return bool(cond.call())


static func wait_frames(tree: SceneTree, n: int) -> void:
	for i in range(n):
		await tree.process_frame
