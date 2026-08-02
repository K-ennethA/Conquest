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


# ---------------------------------------------------------------------------
# Join handshake — the build/version gate
# ---------------------------------------------------------------------------
# Two machines running mismatched builds must refuse each other AT CONNECT TIME,
# not silently desync on the first command. A joining client's FIRST message is a
# hello carrying its display name plus both version stamps; the server validates it
# with [method validate_hello] before it is given a roster slot.
#
# [constant PROTOCOL_VERSION] is the hard gate: a difference means the two peers do
# not agree on the wire format, so the join is refused. The game version string is
# advisory — an editor run ("dev") joining an exported build is a normal and useful
# testing setup, so a difference is reported, never fatal.

## Keys on the hello payload.
const KEY_HELLO_NAME := "name"   ## String, the joiner's display name
const KEY_HELLO_PV := "pv"       ## int, the joiner's PROTOCOL_VERSION
const KEY_HELLO_GAME := "game"   ## String, the joiner's application/config/version

## Rejection reasons. Empty string means "accepted" everywhere in this API.
const REJECT_NONE := ""
const REJECT_MALFORMED_HELLO := "malformed_hello"
const REJECT_VERSION_MISMATCH := "version_mismatch"
const REJECT_LOBBY_FULL := "lobby_full"

## Reported as the game version when the project declares no
## [code]application/config/version[/code] (an editor / unversioned run).
const GAME_VERSION_FALLBACK := "dev"

## This build's game version string, or [constant GAME_VERSION_FALLBACK] when the
## project setting is absent or blank. Never reads wall-clock time or the filesystem.
static func local_game_version() -> String:
	var raw: Variant = ProjectSettings.get_setting("application/config/version", "")
	var version := String(raw).strip_edges()
	return version if version != "" else GAME_VERSION_FALLBACK

## Build the hello a joining client sends to the server. [param game_version] defaults
## to this build's own version.
static func make_hello(player_name: String, game_version: String = "") -> Dictionary:
	return {
		KEY_HELLO_NAME: player_name,
		KEY_HELLO_PV: PROTOCOL_VERSION,
		KEY_HELLO_GAME: game_version if game_version != "" else local_game_version(),
	}

## Server-side gate: decide whether [param hello] may be seated. PURE — pass
## [param host_pv] / [param host_game] explicitly and this function touches nothing
## outside its arguments (that is how the unit test drives it). [param host_game]
## left empty means "this build's version".
##
## Returns:
## [codeblock]
## {
##   "accepted": bool,          # false -> refuse the peer
##   "reason": String,          # one of the REJECT_* constants, "" when accepted
##   "name": String,            # the joiner's display name ("Player" when absent)
##   "host_pv": int, "client_pv": int,
##   "host_game": String, "client_game": String,
##   "build_differs": bool,     # advisory: same protocol, different game version
## }
## [/codeblock]
static func validate_hello(hello: Variant, host_pv: int = PROTOCOL_VERSION, host_game: String = "") -> Dictionary:
	var resolved_host_game: String = host_game if host_game != "" else local_game_version()
	var result: Dictionary = {
		"accepted": false,
		"reason": REJECT_MALFORMED_HELLO,
		"name": "Player",
		"host_pv": host_pv,
		"client_pv": -1,
		"host_game": resolved_host_game,
		"client_game": "",
		"build_differs": false,
	}
	if hello is not Dictionary:
		return result
	var payload: Dictionary = hello
	if not payload.has(KEY_HELLO_PV) or payload[KEY_HELLO_PV] is not int:
		return result
	if not payload.has(KEY_HELLO_GAME) or payload[KEY_HELLO_GAME] is not String:
		return result
	var client_name := String(payload.get(KEY_HELLO_NAME, "")).strip_edges()
	result["name"] = client_name if client_name != "" else "Player"
	result["client_pv"] = int(payload[KEY_HELLO_PV])
	result["client_game"] = String(payload[KEY_HELLO_GAME])
	result["build_differs"] = String(payload[KEY_HELLO_GAME]) != resolved_host_game
	if int(payload[KEY_HELLO_PV]) != host_pv:
		result["reason"] = REJECT_VERSION_MISMATCH
		return result
	result["accepted"] = true
	result["reason"] = REJECT_NONE
	return result

## Human-readable one-liner for a refused join, for the client's status label.
## [param info] is the dictionary [method validate_hello] produced on the server.
static func describe_rejection(reason: String, info: Dictionary = {}) -> String:
	match reason:
		REJECT_VERSION_MISMATCH:
			return "Version mismatch: host %s (protocol %d), you %s (protocol %d). Both machines must run the same build." % [
				String(info.get("host_game", "?")),
				int(info.get("host_pv", -1)),
				String(info.get("client_game", "?")),
				int(info.get("client_pv", -1)),
			]
		REJECT_LOBBY_FULL:
			return "The host's lobby is full."
		REJECT_MALFORMED_HELLO:
			return "The host did not understand this build's join request (incompatible version)."
	return "Join refused by the host (%s)." % reason


static func _has_int(data: Dictionary, key: String) -> bool:
	return data.has(key) and data[key] is int

static func _has_vec2i(data: Dictionary, key: String) -> bool:
	return data.has(key) and data[key] is Vector2i
