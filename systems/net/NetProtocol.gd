extends RefCounted
class_name NetProtocol

## Wire protocol for [NetSession].
##
## Central place for action-type identifiers, payload shapes and the cell
## (de)serialisation helper so client and server never disagree on message
## shape. Kept tiny and dependency-free on purpose: everything that crosses the
## wire is a plain [Dictionary] of ints / Strings / Arrays.
##
## CELLS: board cells are ALWAYS serialised through [method cell_to_wire] /
## [method cell_from_wire] as a plain int Array ([x, y] today). When the board
## grows floors (Vector3i cells with z = floor) only those two helpers change --
## the wire already accepts [x, y, z] and ignores trailing components it does
## not understand.

## Action types a client may request (an INTENT); the host validates and, if
## legal, broadcasts the same dictionary back as an ACCEPTED action (stamped
## with actor + seq).
enum Action {
	MOVE,       ## data: { unit_id:String, to:Array(cell) }
	USE_MOVE,   ## data: { unit_id:String, slot:int, aim:Array(cell) }  (attack / ability)
	WAIT,       ## data: { unit_id:String }   (end this unit's turn without acting)
	END_TURN,   ## data: {}                   (end the active player's / unit's turn)
}

## Standard keys used on every action dictionary.
const KEY_TYPE := "type"        ## int, one of [enum Action]
const KEY_DATA := "data"        ## Dictionary payload
const KEY_ACTOR := "actor"      ## int, player slot that issued the action (host-stamped)
const KEY_SEQ := "seq"          ## int, host-assigned order (0 on the wire from a client)

## Payload keys.
const K_UNIT := "unit_id"
const K_TO := "to"
const K_SLOT := "slot"
const K_AIM := "aim"


## Build a well-formed action dictionary. Actor/seq are stamped by the host when
## it accepts the intent, so clients leave them at their defaults.
static func make_action(type: Action, data: Dictionary = {}, actor: int = -1) -> Dictionary:
	return {
		KEY_TYPE: type,
		KEY_DATA: data.duplicate(true),
		KEY_ACTOR: actor,
		KEY_SEQ: 0,
	}


static func move(unit_id: String, to_cell) -> Dictionary:
	return make_action(Action.MOVE, {K_UNIT: unit_id, K_TO: cell_to_wire(to_cell)})


static func use_move(unit_id: String, slot: int, aim_cell) -> Dictionary:
	return make_action(Action.USE_MOVE, {K_UNIT: unit_id, K_SLOT: slot, K_AIM: cell_to_wire(aim_cell)})


static func wait(unit_id: String) -> Dictionary:
	return make_action(Action.WAIT, {K_UNIT: unit_id})


static func end_turn() -> Dictionary:
	return make_action(Action.END_TURN, {})


# --- Cells -------------------------------------------------------------------

## THE single cell serialiser. Vector2i -> [x, y]; Vector3i -> [x, y, z] (future
## multi-floor cells). Anything else yields an empty array (never well-formed).
static func cell_to_wire(cell) -> Array:
	if cell is Vector2i:
		return [cell.x, cell.y]
	if cell is Vector3i:
		return [cell.x, cell.y, cell.z]
	if cell is Vector2:
		return [int(round(cell.x)), int(round(cell.y))]
	return []


## THE single cell deserialiser: [x, y(, z...)] -> Vector2i (today's board cell).
## Returns [param fallback] on a malformed value. When the board moves to
## Vector3i this is the one place to start returning Vector3i(x, y, z).
static func cell_from_wire(wire, fallback: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	if not is_cell(wire):
		return fallback
	return Vector2i(int(wire[0]), int(wire[1]))


## True when [param wire] is an array of 2..3 ints.
static func is_cell(wire) -> bool:
	if not (wire is Array):
		return false
	if wire.size() < 2 or wire.size() > 3:
		return false
	for v in wire:
		if typeof(v) != TYPE_INT:
			return false
	return true


# --- Validation (shape only; game rules live in NetGameRules) ---------------

## True if [param action] carries the required keys with the right types AND the
## payload for its type is well-formed. The host calls this before trusting
## anything a peer sent.
static func is_well_formed(action: Variant) -> bool:
	if action is not Dictionary:
		return false
	if not action.has(KEY_TYPE) or typeof(action[KEY_TYPE]) != TYPE_INT:
		return false
	if not action.has(KEY_DATA) or action[KEY_DATA] is not Dictionary:
		return false
	var t: int = action[KEY_TYPE]
	if t < 0 or t >= Action.size():
		return false
	var d: Dictionary = action[KEY_DATA]
	match t:
		Action.MOVE:
			return _has_unit(d) and is_cell(d.get(K_TO))
		Action.USE_MOVE:
			return _has_unit(d) and typeof(d.get(K_SLOT)) == TYPE_INT and is_cell(d.get(K_AIM))
		Action.WAIT:
			return _has_unit(d)
		Action.END_TURN:
			return true
	return false


static func _has_unit(d: Dictionary) -> bool:
	return typeof(d.get(K_UNIT)) == TYPE_STRING and String(d[K_UNIT]) != ""


static func type_name(t: int) -> String:
	if t >= 0 and t < Action.size():
		return Action.keys()[t]
	return "UNKNOWN(%d)" % t
