extends RefCounted
class_name NetProtocol

## Wire protocol for [NetSession].
##
## Central place for action-type identifiers and helpers so client and server
## never disagree on message shape. Kept tiny and dependency-free on purpose:
## everything that crosses the wire is a plain [Dictionary] with these keys.

## Action types a client may request. Extend this enum as gameplay grows;
## the server's validator ([member NetSession.action_validator]) decides which
## are legal for a given player/turn.
enum Action {
	MOVE_UNIT,      ## data: { unit_id:int, dest_cell:Vector2i }
	ATTACK_UNIT,    ## data: { attacker_id:int, target_id:int }
	WAIT_UNIT,      ## data: { unit_id:int }
	END_TURN,       ## data: { player_id:int }
	## Cast a move from a unit's slot at an aim cell. Appended (value 4) so the
	## existing on-the-wire values above never shift. data: { unit_id:int,
	## move_slot:int, aim_cell:Vector2i }.
	CAST_MOVE,
}

## Wire/format version. Bump when the envelope or any command's data shape changes
## so peers on mismatched builds can refuse rather than silently desync. Deliberately
## NOT wall-clock time — nothing gameplay-affecting may depend on real time.
const PROTOCOL_VERSION := 1

## Standard keys used on every action dictionary.
const KEY_TYPE := "type"        ## int, one of [enum Action]
const KEY_DATA := "data"        ## Dictionary payload
const KEY_ACTOR := "actor"      ## int, player slot that issued the action
const KEY_SEQ := "seq"          ## int, server-assigned order (0 on the wire from client)
const KEY_RNG_SEED := "rng_seed"   ## int, server-stamped per-command RNG seed (0 until resolved)
const KEY_PV := "pv"               ## int, PROTOCOL_VERSION stamped on a resolved command

## Data-payload keys for the command vocabulary.
const KEY_UNIT_ID := "unit_id"
const KEY_MOVE_SLOT := "move_slot"
const KEY_AIM_CELL := "aim_cell"
const KEY_DEST_CELL := "dest_cell"
const KEY_PLAYER_ID := "player_id"

## Build a well-formed action dictionary. Slot/seq are stamped by the server on
## apply, so clients can leave [param actor] as their own slot and seq as 0.
static func make_action(type: Action, data: Dictionary = {}, actor: int = -1) -> Dictionary:
	return {
		KEY_TYPE: type,
		KEY_DATA: data.duplicate(true),
		KEY_ACTOR: actor,
		KEY_SEQ: 0,
	}

## True if [param action] carries the required keys with the right types.
## The server calls this before trusting anything a peer sent.
static func is_well_formed(action: Variant) -> bool:
	if action is not Dictionary:
		return false
	if not action.has(KEY_TYPE) or action[KEY_TYPE] is not int:
		return false
	if not action.has(KEY_DATA) or action[KEY_DATA] is not Dictionary:
		return false
	return action[KEY_TYPE] >= 0 and action[KEY_TYPE] < Action.size()


# ---------------------------------------------------------------------------
# Command vocabulary — typed builders
# ---------------------------------------------------------------------------
# Each returns an unresolved envelope (seq/rng_seed 0, pv unset). The authority
# stamps ordering + seed via [method stamp_resolution] before broadcasting.

## Cast the move in [param move_slot] of [param unit_id], aimed at [param aim_cell].
static func make_cast_move(unit_id: int, move_slot: int, aim_cell: Vector2i, actor: int = -1) -> Dictionary:
	return make_action(Action.CAST_MOVE, {
		KEY_UNIT_ID: unit_id,
		KEY_MOVE_SLOT: move_slot,
		KEY_AIM_CELL: aim_cell,
	}, actor)

## Reposition [param unit_id] to [param dest_cell] (a plain board move, no attack).
static func make_move_unit(unit_id: int, dest_cell: Vector2i, actor: int = -1) -> Dictionary:
	return make_action(Action.MOVE_UNIT, {
		KEY_UNIT_ID: unit_id,
		KEY_DEST_CELL: dest_cell,
	}, actor)

## End [param unit_id]'s turn without moving or acting.
static func make_wait_unit(unit_id: int, actor: int = -1) -> Dictionary:
	return make_action(Action.WAIT_UNIT, {
		KEY_UNIT_ID: unit_id,
	}, actor)

## End [param player_id]'s whole turn.
static func make_end_turn(player_id: int, actor: int = -1) -> Dictionary:
	return make_action(Action.END_TURN, {
		KEY_PLAYER_ID: player_id,
	}, actor)


# ---------------------------------------------------------------------------
# Command vocabulary — validation
# ---------------------------------------------------------------------------

## True if [param action] is a well-formed action AND its data payload carries the
## keys and types its command type requires. Stricter than [method is_well_formed]:
## the authority uses this before handing a command to the applier.
static func is_command_well_formed(action: Variant) -> bool:
	if not is_well_formed(action):
		return false
	var data: Dictionary = action[KEY_DATA]
	match int(action[KEY_TYPE]):
		Action.CAST_MOVE:
			return _has_int(data, KEY_UNIT_ID) \
				and _has_int(data, KEY_MOVE_SLOT) \
				and _has_vec2i(data, KEY_AIM_CELL)
		Action.MOVE_UNIT:
			return _has_int(data, KEY_UNIT_ID) and _has_vec2i(data, KEY_DEST_CELL)
		Action.WAIT_UNIT:
			return _has_int(data, KEY_UNIT_ID)
		Action.END_TURN:
			return _has_int(data, KEY_PLAYER_ID)
		Action.ATTACK_UNIT:
			return _has_int(data, "attacker_id") and _has_int(data, "target_id")
	return false


## True once the authority has stamped ordering, seed, and protocol version onto
## [param action] (i.e. it is a resolved command safe to apply).
static func is_resolved(action: Variant) -> bool:
	if not is_command_well_formed(action):
		return false
	return action.has(KEY_SEQ) and action[KEY_SEQ] is int and int(action[KEY_SEQ]) > 0 \
		and action.has(KEY_RNG_SEED) and action[KEY_RNG_SEED] is int \
		and action.has(KEY_PV) and int(action.get(KEY_PV, 0)) == PROTOCOL_VERSION


## Authority-only: stamp monotonic [param seq], the per-command [param rng_seed],
## and [constant PROTOCOL_VERSION] onto [param action] in place. Mutates and returns
## the same dictionary for convenience.
static func stamp_resolution(action: Dictionary, seq: int, rng_seed: int) -> Dictionary:
	action[KEY_SEQ] = seq
	action[KEY_RNG_SEED] = rng_seed
	action[KEY_PV] = PROTOCOL_VERSION
	return action


static func _has_int(data: Dictionary, key: String) -> bool:
	return data.has(key) and data[key] is int

static func _has_vec2i(data: Dictionary, key: String) -> bool:
	return data.has(key) and data[key] is Vector2i
