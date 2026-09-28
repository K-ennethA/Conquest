extends RefCounted
class_name LocalPlayer

## "Who is the person at this screen?" helpers shared by the HUD (map menu, danger
## zone, End Turn guards). Shared by MapMenu / UnitActionsPanel:
##   single-player / hotseat -- a player is local when it is not AI;
##   multiplayer             -- only this client's own player slot is local.
## Every accessor is null-safe for headless tests (no autoloads -> null / false).

## The player whose turn it is (turn system first, PlayerManager fallback).
static func current_turn_player() -> Player:
	var tsm = _autoload("TurnSystemManager")
	if tsm != null and tsm.has_active_turn_system():
		var p = tsm.get_active_turn_system().get_current_active_player()
		if p != null:
			return p
	var pm = _autoload("PlayerManager")
	return pm.get_current_player() if pm != null else null


## True when [param player] is controlled by the person at this screen.
static func is_local_human(player: Player) -> bool:
	if player == null:
		return false
	var gs = _autoload("GameSettings")
	if gs != null and gs.game_mode == GameSettings.GameMode.MULTIPLAYER:
		var gmm = _autoload("GameModeManager")
		var local_raw = gmm.get_local_player_id() if gmm != null else -1
		var local_id = int(local_raw) if local_raw is String else local_raw
		return int(player.player_id) == int(local_id)
	return not player.is_ai


## True when it is the local human's turn (the End Turn guard).
static func current_is_local_human() -> bool:
	return is_local_human(current_turn_player())


## The player whose point of view the HUD takes: the current player when that is a
## local human (hotseat hands the view over each turn), else the first local human.
static func viewer() -> Player:
	var cur := current_turn_player()
	if is_local_human(cur):
		return cur
	var pm = _autoload("PlayerManager")
	if pm == null:
		return null
	for p in pm.players:
		if is_local_human(p):
			return p
	return null


## The Player owning [param unit] (unit.get_owner_player(), else PlayerManager).
static func owner_of(unit) -> Player:
	if unit == null:
		return null
	if unit.has_method("get_owner_player"):
		var o = unit.get_owner_player()
		if o != null:
			return o
	var pm = _autoload("PlayerManager")
	return pm.get_player_owning_unit(unit) if pm != null else null


static func _autoload(node_name: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(node_name)
	return null
