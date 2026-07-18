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
	MOVE_UNIT,      ## data: { unit_id:int, to:Vector2i }
	ATTACK_UNIT,    ## data: { attacker_id:int, target_id:int }
	WAIT_UNIT,      ## data: { unit_id:int }
	END_TURN,       ## data: {}
}

## Standard keys used on every action dictionary.
const KEY_TYPE := "type"        ## int, one of [enum Action]
const KEY_DATA := "data"        ## Dictionary payload
const KEY_ACTOR := "actor"      ## int, player slot that issued the action
const KEY_SEQ := "seq"          ## int, server-assigned order (0 on the wire from client)

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
