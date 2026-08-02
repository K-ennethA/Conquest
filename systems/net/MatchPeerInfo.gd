class_name MatchPeerInfo
extends RefCounted

## PROCESS-WIDE holder for the profile cards the other participants of a networked match
## announced about themselves in the lobby ("profile_info": display name, local rank name,
## lifetime points).
##
## WHY THIS EXISTS: the post-match summary ([GameOverScreen]) wants to show the opponent's
## rank and points, but by the time a match ENDS the opponent may already have forfeited,
## crashed or dropped -- there is nothing left to ask. So the exchange happens at MATCH
## START, over the lobby channel, and the answer is parked here where a later scene can
## read it. This is deliberately a tiny static bag, not an autoload: it holds no signals,
## no node, and no lifecycle of its own.
##
## TRUST: every value here came off the wire as an UNTRUSTED peer-supplied Dictionary (see
## [method NetSession.send_lobby_message]). [method set_peer_info] therefore NORMALISES what
## it stores -- string fields are coerced and trimmed, the points figure is coerced to a
## non-negative int, and an over-long name is truncated -- so a hostile or buggy peer can
## only ever make the summary look silly, never break its layout or its readers.
##
## LIFECYCLE: [method clear] is called when a new lobby initialises ([CollaborativeLobby.
## initialize]), so one match's opponent can never be reported as the next match's.

## Longest peer-supplied display name that will be stored (the summary row is one line).
const MAX_NAME_LENGTH: int = 24

## Fallback name for a peer that announced itself without a usable one.
const DEFAULT_NAME: String = "Opponent"

## slot (int) -> { "name": String, "rank_name": String, "lifetime_points": int }.
## Static so it survives the scene change from the lobby into the battle.
static var _peers: Dictionary = {}


## Record (or replace) the profile card [param info] announced by the participant in
## [param slot]. A negative slot is still accepted -- the server stamps -1 when a sender had
## no seat yet -- so a very early announcement is not silently dropped.
static func set_peer_info(slot: int, info: Dictionary) -> void:
	_peers[int(slot)] = _normalise(info)


## The profile card recorded for [param slot], or {} when that peer never announced one.
## Returns a COPY: a caller mutating the result must not edit the stored record.
static func get_peer_info(slot: int) -> Dictionary:
	var stored: Variant = _peers.get(int(slot), null)
	if not (stored is Dictionary):
		return {}
	return (stored as Dictionary).duplicate(true)


## The first recorded card belonging to someone OTHER than [param exclude_slot] -- i.e. "the
## opponent", in the 1v1 case the summary screen cares about. {} when nobody else announced.
## Slots are visited in ascending order so the answer is stable rather than hash-ordered.
static func get_any_peer_info(exclude_slot: int = -1) -> Dictionary:
	var slots: Array = _peers.keys()
	slots.sort()
	for slot in slots:
		if int(slot) == int(exclude_slot):
			continue
		return get_peer_info(int(slot))
	return {}


## How many peers have announced a card.
static func peer_count() -> int:
	return _peers.size()


## Forget every recorded card. Called when a new lobby initialises so one match's opponent
## can never leak into the next match's summary.
static func clear() -> void:
	_peers.clear()


## Coerce an untrusted payload into the fixed three-field shape every reader expects.
static func _normalise(info: Dictionary) -> Dictionary:
	var peer_name: String = str(info.get("name", "")).strip_edges()
	if peer_name.is_empty():
		peer_name = DEFAULT_NAME
	if peer_name.length() > MAX_NAME_LENGTH:
		peer_name = peer_name.substr(0, MAX_NAME_LENGTH)

	var rank_name: String = str(info.get("rank_name", "")).strip_edges()
	if rank_name.length() > MAX_NAME_LENGTH:
		rank_name = rank_name.substr(0, MAX_NAME_LENGTH)

	return {
		"name": peer_name,
		"rank_name": rank_name,
		"lifetime_points": _to_int(info.get("lifetime_points", 0)),
	}


## Coerce an untrusted value to a non-negative int. Only the scalar types int() actually
## accepts are converted -- handing int() an Array or Dictionary raises, and a malformed
## payload must degrade to 0 rather than error out (tests/README rule 1).
static func _to_int(value: Variant) -> int:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return maxi(0, int(value))
		TYPE_STRING, TYPE_STRING_NAME:
			return maxi(0, String(value).to_int())
		_:
			return 0
