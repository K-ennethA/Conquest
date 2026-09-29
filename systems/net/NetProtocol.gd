extends RefCounted
class_name NetProtocol

## Wire protocol for [NetSession].
##
## Central place for action-type identifiers, payload shapes, the cell
## (de)serialisation helper, the join handshake (build gate) and the rejection
## vocabulary, so client and host never disagree on message shape. Kept tiny and
## dependency-free on purpose: everything that crosses the wire is a plain
## [Dictionary] of ints / Strings / Arrays.
##
## CELLS: board cells are Vector3i (col, row, floor) -- see docs/MULTI_FLOOR.md --
## and are ALWAYS serialised through [method cell_to_wire] / [method cell_from_wire]
## as a plain int Array [col, row, floor] (built on Cells.to_array / from_variant).
## In-process producers (replay decoding, tests) may also hand a Vector3i / Vector2i
## cell straight to the validators; [method is_cell] accepts those too.
##
## UNIT IDS: a unit is named by its [NetUnitIds] string ("<slot>:<n>", mid-match
## arrivals "<slot>:s<k>") -- the same id on every peer, derived from the board.
##
## ONE VOCABULARY. The network actions and the replay / command-log commands are the
## same thing: MOVE, USE_MOVE, WAIT, END_TURN, USE_ITEM, SWITCH. The older command names (MOVE_UNIT,
## CAST_MOVE, WAIT_UNIT) and payload-key constants (KEY_UNIT_ID, KEY_DEST_CELL,
## KEY_MOVE_SLOT, KEY_AIM_CELL, KEY_RNG_SEED) are ALIASES of the canonical ones, kept so
## the replay system and the battle UI read unchanged -- they build and match the very
## same dictionaries.

## Action types a client may request (an INTENT); the host validates and, if
## legal, broadcasts the same dictionary back as an ACCEPTED action (stamped
## with actor + seq). The last three members are aliases (same values).
enum Action {
	MOVE = 0,       ## data: { unit_id:String, to:cell }
	USE_MOVE = 1,   ## data: { unit_id:String, slot:int, aim:cell }  (attack / ability / ultimate)
	WAIT = 2,       ## data: { unit_id:String }   (end this unit's turn without acting)
	END_TURN = 3,   ## data: { [player_id:int] }  (end the active player's / unit's turn)
	MOVE_UNIT = 0,  ## alias of MOVE (command-log name)
	CAST_MOVE = 1,  ## alias of USE_MOVE (command-log name)
	WAIT_UNIT = 2,  ## alias of WAIT (command-log name)
	## Reserved legacy id with NO apply branch (an attack is a USE_MOVE). Never well-formed;
	## kept so older command-log code and tests can name "a type nothing applies".
	ATTACK_UNIT = 4,
	## data: { unit_id:String, item:String, target:String }  -- use a consumable from the
	## user's bag on [target] (a unit id; the user itself in a 1v1 duel). Spends the unit's turn.
	## Duels only today (DECISIONS.md #28): the bag lives on the duel ([DuelBattle]), the
	## effect is the item's [ConsumableEffect] -- deterministic, no RNG.
	USE_ITEM = 5,
	## data: { unit_id:String }  -- PARTY DUELS: bring the benched team member [unit_id] onto its
	## side's station. Two uses, told apart by the duel's state (never by the payload): a VOLUNTARY
	## switch on the side's own turn (the outgoing combatant's turn is SPENT; the incoming one does
	## not act again this round), or a KO REPLACEMENT the fainted combatant's owner picks (free,
	## before any other turn opens). Deterministic, no roll ([DuelBattle], [DuelNetRules]).
	SWITCH = 6,
}

## Highest canonical action value (the enum carries aliases and a reserved id, so
## Action.size() is not the range; the reserved ATTACK_UNIT inside it is never well-formed).
const ACTION_MAX := 6

## Wire/format version. Bump whenever the envelope or any action's data shape changes
## so peers on mismatched builds refuse each other at join time rather than silently
## desyncing (see [method validate_hello]). Also stamped into replay headers: a replay
## recorded under another version is refused by its own gate. Deliberately NOT
## wall-clock time -- nothing gameplay-affecting may depend on real time.
##   1: local command vocabulary (int unit ids, Vector2i cells, one match seed)
##   2: merged core -- NetUnitIds string ids, [col,row,floor] cells, per-action
##      commit-reveal RNG, host-seated handshake
##   3: USE_ITEM (battle consumables -- the duel's Items action)
##   4: lobby MODE (conquest / duel) in the hello + match config, the duel match-config
##      keys (duel_units / duel_stage / duel_weather) and REJECT_MODE_MISMATCH
##   5: used by two parallel builds with DIFFERENT wire changes (neither can talk to the
##      other, nor to 6):
##      a) the online TURN CLOCK -- the host's clock broadcast, host-issued timeout actions
##         (KEY_TIMEOUT), the attach report, the clock forfeit and the turn_clock / afk_limit
##         config keys (see NetTurnClock)
##      b) PARTY DUELS -- the SWITCH action (voluntary switch / KO replacement pick), the duel
##         match-config keys duel_format / duel_teams, the team-carrying duel_pick lobby message
##   6: both 5a and 5b together, plus party-aware duel timeouts (a clock expiry during a
##      pending KO replacement pick is the host-issued, timeout-stamped auto-pick SWITCH)
const PROTOCOL_VERSION := 6

## What a network lobby plays (DECISIONS.md #32). Fixed per lobby: the host (or a dedicated
## server's --mode) decides it, the joiner's hello names the mode it came for, and a mismatch
## is refused at the gate ([constant REJECT_MODE_MISMATCH]). Stamped into the match config as
## [constant CONFIG_MODE] so every peer boots the same kind of battle.
const MODE_CONQUEST := "conquest"
const MODE_DUEL := "duel"
const MODES: Array[String] = [MODE_CONQUEST, MODE_DUEL]
## Match-config key naming the mode (absent = conquest: older configs are map battles).
const CONFIG_MODE := "mode"


## The player-facing name of a lobby mode ("Conquest" / "Duel").
static func mode_label(mode: String) -> String:
	return "Duel" if mode == MODE_DUEL else "Conquest"


## The mode a match config / hello names ([constant MODE_CONQUEST] when absent or unknown).
static func mode_of(d: Variant) -> String:
	if d is Dictionary:
		var m = (d as Dictionary).get(CONFIG_MODE, MODE_CONQUEST)
		if (m is String or m is StringName) and String(m) in MODES:
			return String(m)
	return MODE_CONQUEST

## Standard keys used on every action dictionary.
const KEY_TYPE := "type"        ## int, one of [enum Action]
const KEY_DATA := "data"        ## Dictionary payload
const KEY_ACTOR := "actor"      ## int, player slot that issued the action (host-stamped)
const KEY_SEQ := "seq"          ## int, host-assigned order (0 on the wire from a client)
## int, the action's 64-bit RNG seed. NEVER read from the wire: every peer stamps
## it locally from the VERIFIED commit-reveal shares (see NetCommitReveal) just
## before applying; senders strip it. Recorded commands (replays) keep it so a
## playback rolls exactly what the match rolled.
const KEY_RNG := "rng"
const KEY_PV := "pv"            ## int, PROTOCOL_VERSION stamped on a resolved (recorded) command
## bool, true on an action the HOST issued because the acting seat's turn clock ran out
## ([NetTurnClock]). Only the host may issue one: a client intent carrying it has the key
## stripped, and clients check a timeout is the rules' canonical one and never early.
const KEY_TIMEOUT := "timeout"

## Payload keys.
const K_UNIT := "unit_id"
const K_TO := "to"
const K_SLOT := "slot"
const K_AIM := "aim"
const K_PLAYER := "player_id"
const K_ITEM := "item"
const K_TARGET := "target"

## Command-log aliases of the keys above (same strings -- one payload shape).
const KEY_UNIT_ID := K_UNIT
const KEY_DEST_CELL := K_TO
const KEY_MOVE_SLOT := K_SLOT
const KEY_AIM_CELL := K_AIM
const KEY_PLAYER_ID := K_PLAYER
const KEY_RNG_SEED := KEY_RNG


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


## PARTY DUELS: send the benched team member [param unit_id] in (a switch or a KO replacement).
static func switch_to(unit_id: String) -> Dictionary:
	return make_action(Action.SWITCH, {K_UNIT: unit_id})


## Use consumable [param item_id] on the unit [param target_id] ("" = the user itself).
static func use_item(unit_id: String, item_id: String, target_id: String = "") -> Dictionary:
	return make_action(Action.USE_ITEM, {K_UNIT: unit_id, K_ITEM: item_id,
		K_TARGET: target_id if target_id != "" else unit_id})


## End the active turn. [param player_id] (optional) is informational -- recorded in
## command logs; the host always ends the SENDER's turn.
static func end_turn(player_id: int = -1) -> Dictionary:
	var data := {}
	if player_id >= 0:
		data[K_PLAYER] = player_id
	return make_action(Action.END_TURN, data)


# --- Command-log builders (same actions, command-log names) ------------------
# Used by the replay recorder and the battle UI. [param actor] is informational for a
# recorded command; on the network the host always derives the actor from the seat.

static func make_move_unit(unit_id: String, dest_cell, actor: int = -1) -> Dictionary:
	var a := move(unit_id, dest_cell)
	a[KEY_ACTOR] = actor
	return a


static func make_cast_move(unit_id: String, move_slot: int, aim_cell, actor: int = -1) -> Dictionary:
	var a := use_move(unit_id, move_slot, aim_cell)
	a[KEY_ACTOR] = actor
	return a


static func make_wait_unit(unit_id: String, actor: int = -1) -> Dictionary:
	var a := wait(unit_id)
	a[KEY_ACTOR] = actor
	return a


static func make_end_turn(player_id: int, actor: int = -1) -> Dictionary:
	var a := end_turn(player_id)
	a[KEY_ACTOR] = actor
	return a


# --- Cells -------------------------------------------------------------------

## THE single cell serialiser: any cell (Vector3i (col, row, floor), or a legacy
## Vector2i lifted to floor 0) -> [col, row, floor] via [Cells]. Anything
## unreadable yields an empty array (never well-formed).
static func cell_to_wire(cell) -> Array:
	var c: Vector3i = Cells.from_variant(cell)
	if c == Cells.INVALID:
		return []
	return Cells.to_array(c)


## THE single cell deserialiser: [col, row(, floor)] (or an in-process Vector3i /
## Vector2i) -> Vector3i (a missing floor reads as 0). Returns [param fallback] on a
## malformed value.
static func cell_from_wire(wire, fallback: Vector3i = Cells.INVALID) -> Vector3i:
	if not is_cell(wire):
		return fallback
	return Cells.from_variant(wire)


## True when [param wire] is an array of 2..3 ints, or an in-process Vector3i / Vector2i.
static func is_cell(wire) -> bool:
	if wire is Vector3i or wire is Vector2i:
		return true
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
	if t < 0 or t > ACTION_MAX:
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
			return not d.has(K_PLAYER) or typeof(d[K_PLAYER]) == TYPE_INT
		Action.USE_ITEM:
			return _has_unit(d) and typeof(d.get(K_ITEM)) == TYPE_STRING and String(d[K_ITEM]) != "" \
				and typeof(d.get(K_TARGET)) == TYPE_STRING and String(d[K_TARGET]) != ""
		Action.SWITCH:
			return _has_unit(d)
	return false


## Command-log name of [method is_well_formed] (one shape, one check).
static func is_command_well_formed(action: Variant) -> bool:
	return is_well_formed(action)


static func _has_unit(d: Dictionary) -> bool:
	return typeof(d.get(K_UNIT)) == TYPE_STRING and String(d[K_UNIT]) != ""


## True once ordering, the RNG seed and [constant PROTOCOL_VERSION] are stamped onto
## [param action] (a resolved / recorded command, safe to re-apply offline).
static func is_resolved(action: Variant) -> bool:
	if not is_well_formed(action):
		return false
	return action.has(KEY_SEQ) and typeof(action[KEY_SEQ]) == TYPE_INT and int(action[KEY_SEQ]) > 0 \
		and action.has(KEY_RNG) and typeof(action[KEY_RNG]) == TYPE_INT \
		and int(action.get(KEY_PV, 0)) == PROTOCOL_VERSION


## True when [param action] is a host-issued turn-clock TIMEOUT (see [constant KEY_TIMEOUT]).
static func is_timeout(action: Variant) -> bool:
	return action is Dictionary and bool((action as Dictionary).get(KEY_TIMEOUT, false))


## Stamp [param seq], the per-action [param rng_seed] and [constant PROTOCOL_VERSION]
## onto [param action] in place (returns it). NetSession stamps seq / rng itself when
## it applies; this is for offline producers (replays, tests) that build resolved
## commands without a session.
static func stamp_resolution(action: Dictionary, seq: int, rng_seed: int) -> Dictionary:
	action[KEY_SEQ] = seq
	action[KEY_RNG] = rng_seed
	action[KEY_PV] = PROTOCOL_VERSION
	return action


static func type_name(t: int) -> String:
	match t:
		Action.MOVE:
			return "MOVE"
		Action.USE_MOVE:
			return "USE_MOVE"
		Action.WAIT:
			return "WAIT"
		Action.END_TURN:
			return "END_TURN"
		Action.USE_ITEM:
			return "USE_ITEM"
		Action.SWITCH:
			return "SWITCH"
	return "UNKNOWN(%d)" % t


# ---------------------------------------------------------------------------
# Join handshake -- the build/version gate
# ---------------------------------------------------------------------------
# Two machines running mismatched builds must refuse each other AT CONNECT TIME,
# not silently desync on the first action. A joining client's FIRST message is a
# hello carrying its display name plus both version stamps; the host validates it
# with [method validate_hello] before it is given a roster slot.
#
# [constant PROTOCOL_VERSION] is the hard gate: a difference means the two peers do
# not agree on the wire format, so the join is refused. The game version string is
# advisory -- an editor run ("dev") joining an exported build is a normal and useful
# testing setup, so a difference is reported, never fatal.

## Keys on the hello payload.
const KEY_HELLO_NAME := "name"   ## String, the joiner's display name
const KEY_HELLO_PV := "pv"       ## int, the joiner's PROTOCOL_VERSION
const KEY_HELLO_GAME := "game"   ## String, the joiner's application/config/version
const KEY_HELLO_MODE := "mode"   ## String, the lobby mode the joiner came for (MODES; absent = conquest)

## Join rejection reasons. Empty string means "accepted" everywhere in this API.
const REJECT_NONE := ""
const REJECT_MALFORMED_HELLO := "malformed_hello"
const REJECT_VERSION_MISMATCH := "version_mismatch"
const REJECT_LOBBY_FULL := "lobby_full"
const REJECT_MATCH_IN_PROGRESS := "match_in_progress"
## The host runs another mode's lobby (a Duel joiner at a Conquest host, or the reverse).
const REJECT_MODE_MISMATCH := "mode_mismatch"

## Reported as the game version when the project declares no
## [code]application/config/version[/code] (an editor / unversioned run).
const GAME_VERSION_FALLBACK := "dev"

## This build's game version string, or [constant GAME_VERSION_FALLBACK] when the
## project setting is absent or blank. Never reads wall-clock time or the filesystem.
static func local_game_version() -> String:
	var raw: Variant = ProjectSettings.get_setting("application/config/version", "")
	var version := String(raw).strip_edges()
	return version if version != "" else GAME_VERSION_FALLBACK

## Build the hello a joining client sends to the host. [param game_version] defaults
## to this build's own version; [param mode] is the lobby mode the joiner came for.
static func make_hello(player_name: String, game_version: String = "", mode: String = MODE_CONQUEST) -> Dictionary:
	return {
		KEY_HELLO_NAME: player_name,
		KEY_HELLO_PV: PROTOCOL_VERSION,
		KEY_HELLO_GAME: game_version if game_version != "" else local_game_version(),
		KEY_HELLO_MODE: mode if mode in MODES else MODE_CONQUEST,
	}

## Host-side gate: decide whether [param hello] may be seated. PURE -- pass
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
##   "host_mode": String, "client_mode": String,   # lobby modes (MODES)
## }
## [/codeblock]
## [param host_mode] is the lobby's mode: a joiner who came for another mode is refused with
## [constant REJECT_MODE_MISMATCH] (after the protocol check -- a different wire format is
## the more fundamental answer).
static func validate_hello(hello: Variant, host_pv: int = PROTOCOL_VERSION, host_game: String = "",
		host_mode: String = MODE_CONQUEST) -> Dictionary:
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
		"host_mode": host_mode,
		"client_mode": MODE_CONQUEST,
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
	result["client_mode"] = mode_of(payload)
	if String(result["client_mode"]) != host_mode:
		result["reason"] = REJECT_MODE_MISMATCH
		return result
	result["accepted"] = true
	result["reason"] = REJECT_NONE
	return result

## Human-readable one-liner for a refused join, for the client's status label.
## [param info] is the dictionary [method validate_hello] produced on the host.
static func describe_rejection(reason: String, info: Dictionary = {}) -> String:
	match reason:
		REJECT_VERSION_MISMATCH:
			return "Version mismatch: host %s (protocol %d), you %s (protocol %d). Both machines must run the same build." % [
				String(info.get("host_game", "?")),
				int(info.get("host_pv", -1)),
				String(info.get("client_game", "?")),
				int(info.get("client_pv", -1)),
			]
		REJECT_MODE_MISMATCH:
			return "That host is running a %s lobby. Choose Online > Versus > %s to join it." % [
				mode_label(String(info.get("host_mode", MODE_CONQUEST))),
				mode_label(String(info.get("host_mode", MODE_CONQUEST)))]
		REJECT_LOBBY_FULL:
			return "The host's lobby is full."
		REJECT_MATCH_IN_PROGRESS:
			return "A match is already in progress on that host."
		REJECT_MALFORMED_HELLO:
			return "The host did not understand this build's join request (incompatible version)."
	return "Join refused by the host (%s)." % reason


# ---------------------------------------------------------------------------
# Intent rejection -- the vocabulary the host answers a refused action with
# ---------------------------------------------------------------------------
# [method NetGameRules.validate_intent] (via NetSession) returns one of these (empty =
# accepted) and the origin peer receives it on [signal NetSession.intent_rejected]. They
# are WIRE STRINGS: changing one is a protocol change, so they live here next to the
# join-gate reasons rather than as literals inside the session / rules.

const INTENT_OK := ""
const INTENT_MALFORMED := "malformed"
const INTENT_UNKNOWN_ACTOR := "unknown_actor"
const INTENT_NOT_YOUR_TURN := "not_your_turn"
## Generic "the rules said no" (kept for older callers; the rules now answer with the
## specific reasons below).
const INTENT_REJECTED_BY_GAME := "rejected_by_game"
const INTENT_NO_GAME := "no_game"
const INTENT_NO_ACTIVE_TURN := "no_active_turn"
const INTENT_CANNOT_END_TURN := "cannot_end_turn"
const INTENT_UNKNOWN_UNIT := "unknown_unit"
const INTENT_NOT_YOUR_UNIT := "not_your_unit"
const INTENT_UNIT_DEAD := "unit_dead"
const INTENT_UNIT_CANNOT_MOVE := "unit_cannot_move"
const INTENT_UNIT_CANNOT_ACT := "unit_cannot_act"
const INTENT_ILLEGAL_DESTINATION := "illegal_destination"
const INTENT_NO_MOVEMENT_PROFILE := "no_movement_profile"
const INTENT_NO_MOVE_IN_SLOT := "no_move_in_slot"
const INTENT_MOVE_UNAVAILABLE := "move_unavailable"
const INTENT_ILLEGAL_TARGET := "illegal_target"
const INTENT_UNKNOWN_ACTION := "unknown_action"
const INTENT_ACTION_LIMIT := "action_limit"
## Online DUEL reasons ([DuelNetRules]).
## The acting combatant is stunned / controlled: its only legal action is WAIT.
const INTENT_MUST_PASS := "must_pass"
## The duel is decided; nothing more is applied.
const INTENT_DUEL_OVER := "duel_over"
## Not offered online (items and running are local / story duel actions).
const INTENT_NOT_ONLINE := "not_allowed_online"
## A host-issued timeout that is not the rules' canonical timeout action for the seat.
const INTENT_TIMEOUT_MISMATCH := "timeout_mismatch"
## PARTY DUELS. A side's fielded combatant fainted: its owner must pick the replacement first
## (the only legal action for that seat; everyone else waits).
const INTENT_MUST_PICK := "must_pick_replacement"
## The format has no switching (Singles), or this combatant may not switch now.
const INTENT_NO_SWITCHING := "switching_not_allowed"
## The named member cannot come in: not on this team, already fielded, or fainted.
const INTENT_ILLEGAL_SWITCH := "illegal_switch"

## Short label for the command an action carries, for a player-facing line ("Move rejected").
## [param action] may be anything at all -- a malformed payload off the wire, or null -- so an
## unrecognised/absent type degrades to the generic "Command".
static func describe_action(action: Variant) -> String:
	if action is not Dictionary or not (action as Dictionary).has(KEY_TYPE):
		return "Command"
	match int((action as Dictionary)[KEY_TYPE]):
		Action.MOVE:
			return "Move"
		Action.USE_MOVE, Action.ATTACK_UNIT:
			return "Attack"
		Action.WAIT:
			return "Wait"
		Action.END_TURN:
			return "End turn"
		Action.USE_ITEM:
			return "Item"
		Action.SWITCH:
			return "Switch"
	return "Command"


## The ONE player-facing line for a refused command -- "Move rejected — not your turn".
## PURE (no autoloads, no tree), so the toast that shows it is a thin renderer and this is
## what the tests pin. [param action] is optional and only names the command; an unknown
## [param reason] is still shown, de-underscored, rather than being swallowed -- a player
## seeing an odd phrase is strictly better than a command vanishing in silence.
static func describe_intent_rejection(reason: String, action: Variant = null) -> String:
	var what: String = describe_action(action)
	var why: String = ""
	match reason:
		INTENT_NOT_YOUR_TURN:
			why = "not your turn"
		INTENT_UNKNOWN_ACTOR:
			why = "you have no seat in this match"
		INTENT_MALFORMED:
			why = "the host did not understand it"
		INTENT_REJECTED_BY_GAME:
			why = "the rules do not allow it"
		INTENT_NOT_YOUR_UNIT:
			why = "that unit is not yours"
		INTENT_ILLEGAL_DESTINATION:
			why = "that unit cannot move there"
		INTENT_ILLEGAL_TARGET:
			why = "that target is not valid"
		INTENT_UNIT_CANNOT_MOVE:
			why = "that unit has already moved"
		INTENT_UNIT_CANNOT_ACT:
			why = "that unit has already acted"
		INTENT_MOVE_UNAVAILABLE:
			why = "that move is not ready yet"
		INTENT_UNKNOWN_UNIT, INTENT_UNIT_DEAD:
			why = "that unit is no longer on the board"
		INTENT_CANNOT_END_TURN:
			why = "the turn cannot be ended right now"
		INTENT_NO_MOVE_IN_SLOT:
			why = "that unit has no such move"
		INTENT_MUST_PASS:
			why = "your partner cannot act this turn"
		INTENT_DUEL_OVER:
			why = "the duel is already decided"
		INTENT_NOT_ONLINE:
			why = "not available in online duels"
		INTENT_MUST_PICK:
			why = "choose who fights next first"
		INTENT_NO_SWITCHING:
			why = "switching is not allowed right now"
		INTENT_ILLEGAL_SWITCH:
			why = "that partner cannot come in"
		_:
			why = String(reason).strip_edges().replace("_", " ")
			if why.is_empty():
				why = "refused by the host"
	return "%s rejected — %s" % [what, why]
