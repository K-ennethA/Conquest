extends RefCounted
class_name NetUnitIds

## Stable, network-safe unit identities.
##
## Display names are NOT unique (mirror maps field the same character on both
## sides), and node names / instance ids differ between processes, so every unit
## in a network match carries a [code]net_id[/code] meta string that is assigned
## DETERMINISTICALLY from board state both peers share:
##
##   * units present at match start:  "<owner_slot>:<n>"  -- n is the unit's index
##     among its owner's units sorted by board cell (row, then column);
##   * units that appear mid-match (summons, reinforcements, respawns):
##     "<owner_slot>:s<k>" -- k is a per-match counter, assigned in the same
##     (owner, cell) order on every peer right after each applied action.
##
## Because every peer applies the same accepted actions in the same order, both
## rules above produce identical ids everywhere. Look units up with [method find].

const META := &"net_id"


## The unit's net id, or "" when it has none yet.
static func id_of(unit) -> String:
	if unit == null or not is_instance_valid(unit) or not (unit is Object):
		return ""
	if unit.has_meta(META):
		return String(unit.get_meta(META))
	return ""


## Owner slot of [param unit] (-1 for unowned / neutral). Duck-typed so test
## doubles work: get_team() (live [Unit]) > get_owner_player().player_id >
## owner_player.player_id.
static func owner_slot(unit) -> int:
	if unit == null or not is_instance_valid(unit):
		return -1
	if unit.has_method("get_team"):
		return int(unit.get_team())
	var owner = null
	if unit.has_method("get_owner_player"):
		owner = unit.get_owner_player()
	elif "owner_player" in unit:
		owner = unit.owner_player
	if owner != null and "player_id" in owner:
		return int(owner.player_id)
	return -1


## Give every unit on [param board] that lacks an id one, deterministically.
## [param first_pass] true = match start ("<slot>:<n>" scheme); false = mid-match
## arrivals, which draw from [param counter] (a one-element Array used as an
## in/out int so the caller keeps the running count). Returns the number of ids
## assigned.
static func assign(board, first_pass: bool, counter: Array = [0]) -> int:
	if board == null or not board.has_method("all_units"):
		return 0
	var fresh: Array = []
	for u in board.all_units():
		if u == null or not is_instance_valid(u):
			continue
		if id_of(u) == "":
			fresh.append(u)
	if fresh.is_empty():
		return 0
	fresh.sort_custom(func(a, b): return _sort_key(board, a) < _sort_key(board, b))
	var per_owner: Dictionary = {}
	for u in fresh:
		var slot := owner_slot(u)
		var id: String
		if first_pass:
			var n: int = per_owner.get(slot, 0)
			per_owner[slot] = n + 1
			id = "%d:%d" % [slot, n]
		else:
			id = "%d:s%d" % [slot, int(counter[0])]
			counter[0] = int(counter[0]) + 1
		u.set_meta(META, id)
	return fresh.size()


## Find the live unit carrying [param id] on [param board] (null if none / dead).
static func find(board, id: String):
	if board == null or id == "" or not board.has_method("all_units"):
		return null
	for u in board.all_units():
		if u != null and is_instance_valid(u) and id_of(u) == id:
			return u
	return null


## Sort key: owner slot, then anchor row, then column. Cells are unique per
## unit, so the order is total and identical on every peer.
static func _sort_key(board, unit) -> Array:
	var cell: Vector2i = board.cell_of(unit)
	return [owner_slot(unit), cell.y, cell.x]
