extends RefCounted
class_name ReplayLog

## The REPLAY FORMAT and its codec. Pure and static -- no scene, no autoload mutation, no
## gameplay -- so the whole contract is unit-testable headless. [ReplayRecorder] produces
## these dictionaries; the (later) playback wave consumes them. This file is the seam
## between the two: nothing else may define the shape.
##
## WHAT A REPLAY IS. Not video. A Conquest match is LOCKSTEP-DETERMINISTIC -- every
## gameplay mutation funnels through [method CommandApplier.apply_command] and every roll
## comes from a [MatchRng] stream seeded per command -- so the complete record of a battle
## is: the initial setup (header) + every command every actor issued (human AND AI, in
## order) + a version stamp + a per-turn state checksum. Playback re-simulates through the
## SAME apply path with input and AI disabled; a version mismatch refuses the file outright
## and a checksum divergence bails gracefully at the turn it diverged.
##
## THE SHAPE (format_version 1):
## [codeblock]
## {
##   "format_version": 1,
##   "game_version": "dev",              # ProjectSettings application/config/version,
##                                       # read through NetProtocol.local_game_version()
##                                       # -- the SAME source the net join handshake gates on
##   "protocol_version": 1,              # NetProtocol.PROTOCOL_VERSION (command vocabulary)
##   "recorded_at_utc": "2026-08-02T14:03:11",   # display only; nothing gameplay reads it
##   "mode": "skirmish",                 # one of MODES
##   "map": {
##     "path": "res://... | user://...", # map identity, mirroring BattleSnapshot's context
##     "name": "Forgotten Forest",
##     "custom": false,
##     "payload": { }                    # embedded map dict for a custom/challenge map
##                                       # (empty for a res:// map -- the path IS the identity)
##   },
##   "participants": [                   # one per player slot, ascending
##     { "slot": 0, "name": "Player 1", "is_ai": false,
##       "squad": ["vineweave"],         # character ids, pick order
##       "items":  ["ironband"],         # item ids in force
##       "skins":  { "vineweave": "ashen" } }
##   ],
##   "rng":  { "match_seed": 123456789 },  # MatchRng.match_seed for the battle
##   "turn_system": 0,                   # TurnSystemBase.TurnSystemType
##   "difficulty": 1,                    # BotController.Difficulty
##   "challenge_id": "",                 # set in challenge mode (ChallengeCodec.challenge_id)
##   "campaign_chapter_id": "",
##   "entries": [                        # THE BODY -- ordered, one per committed command
##     { "turn": 3, "actor_slot": 0, "cmd": { ...encoded NetProtocol command... } }
##   ],
##   "checksums": [ { "turn": 3, "hash": "0a1b2c3d4e5f6071" } ],
##   "outcome": { "result": "victory", "winner_slot": 0, "turns": 12 },
##   "truncated": false                  # true when the entry cap stopped recording
## }
## [/codeblock]
##
## COMMANDS ARE STORED IN THE NETPROTOCOL VOCABULARY, JSON-flattened. A [Vector2i] becomes
## [code][x, y][/code] (exactly as [method BattleSnapshot.cell_to_array] does) because JSON
## has no vector type; [method decode_command] puts it back. Only the four command types the
## applier can actually APPLY are accepted ([constant APPLIABLE_TYPES]) -- ATTACK_UNIT exists
## in [enum NetProtocol.Action] but has no apply branch, so a replay carrying one could never
## be re-simulated and is rejected at the gate rather than mid-playback.
##
## SECURITY POSTURE -- a replay file is UNTRUSTED input (the headline use case is a challenge
## base-defense replay recorded on the ATTACKER's machine and watched by the defender):
##   * Never [ResourceLoader] / [code]load()[/code] on any of it. It is inert JSON end to end.
##   * Parsing uses an INSTANCE [JSON] -- never [method JSON.parse_string], which logs an
##     engine error on malformed input. A corrupt or hostile file is an EXPECTED case here,
##     so every rejection returns [code]{}[/code] / [code]false[/code] and NOTHING reaches
##     the engine log (project convention #1; GUT fails a test on any engine error).
##   * [method validate] whitelists every field: unknown keys are dropped, every command type
##     is checked against the vocabulary, every string is length-capped, and the entry /
##     checksum / participant counts are capped.
##   * The on-disk container carries a SHA-256 of its own compressed payload and is verified
##     BEFORE inflation, so bytes we did not write never reach the decompressor at all (its
##     failure path is an engine error we cannot catch) and a decompression bomb is capped
##     twice over -- by the declared size and by [constant MAX_DECOMPRESSED_BYTES].

# --- Format ------------------------------------------------------------------

## Bump ONLY on a breaking change to the shape above. [method validate] refuses anything
## else, and playback refuses a file this build cannot re-simulate rather than desyncing.
const FORMAT_VERSION: int = 1

## Modes a replay may be recorded from. EVERY mode funnels through the recorder, so this is
## the complete list; an unrecognised mode is normalised to [constant MODE_SKIRMISH] rather
## than rejecting the file (the mode is a label, not a simulation input).
const MODE_SKIRMISH := "skirmish"
const MODE_VERSUS := "versus"
const MODE_ARENA := "arena"
const MODE_CHALLENGE := "challenge"
const MODE_CAMPAIGN := "campaign"
const MODE_KING_OF_THE_HILL := "king_of_the_hill"
const MODES: Array[String] = [
	MODE_SKIRMISH, MODE_VERSUS, MODE_ARENA, MODE_CHALLENGE, MODE_CAMPAIGN, MODE_KING_OF_THE_HILL,
]

## Outcome labels. "" means the battle never finished (the player quit mid-match).
const RESULT_UNKNOWN := ""
const RESULT_VICTORY := "victory"
const RESULT_DEFEAT := "defeat"
const RESULT_DRAW := "draw"
const RESULTS: Array[String] = [RESULT_UNKNOWN, RESULT_VICTORY, RESULT_DEFEAT, RESULT_DRAW]

## The command types a replay may carry: exactly the ones [method CommandApplier.apply_command]
## has an apply branch for. See the class docs for why ATTACK_UNIT is excluded.
const APPLIABLE_TYPES: Array[int] = [
	NetProtocol.Action.MOVE_UNIT,
	NetProtocol.Action.WAIT_UNIT,
	NetProtocol.Action.END_TURN,
	NetProtocol.Action.CAST_MOVE,
]

# --- Caps (the untrusted-input ceilings) -------------------------------------

## Hard ceiling on recorded commands. A long 2-player battle is a few hundred; 5000 is far
## above any real match, so hitting it means either a pathological game or a hostile file.
const MAX_ENTRIES: int = 5000
## Ceiling on per-turn checksums (one per turn end).
const MAX_CHECKSUMS: int = 4000
## Ceiling on participants (player slots).
const MAX_PARTICIPANTS: int = 8
## Ceiling on a squad / item list / skin map inside one participant.
const MAX_LIST: int = 64
## Longest ordinary string (names, ids, mode, hashes) that is even considered.
const MAX_STRING: int = 256
## Longest path-ish string (map path).
const MAX_PATH: int = 512
## Ceiling on an embedded custom-map payload, in keys at the top level.
const MAX_PAYLOAD_KEYS: int = 64
## Ceiling on the JSON a replay file may inflate to. A 5000-entry log is well under 1 MB.
const MAX_DECOMPRESSED_BYTES: int = 8 * 1024 * 1024
## Ceiling on the compressed file we will even read off disk.
const MAX_FILE_BYTES: int = 4 * 1024 * 1024
## Ceiling on how many files [method list_replays] reports.
const MAX_LISTED_FILES: int = 512

# --- On-disk container -------------------------------------------------------

## Where replays live. Injectable for tests (never write the player's real directory).
const DEFAULT_REPLAY_DIR := "user://replays/"
const FILE_EXTENSION := ".cqrep"

## Container magic + version. The container wraps gzip'd JSON with a digest so a tampered or
## truncated file is refused BEFORE the decompressor sees it (see the security note above).
const CONTAINER_MAGIC := "CQRP"
const CONTAINER_VERSION: int = 1
## magic(4) + container_version(4) + uncompressed_size(4) + sha256(32).
const CONTAINER_HEADER_SIZE: int = 44

static var _replay_dir: String = DEFAULT_REPLAY_DIR

## Domain-separation salt so a state checksum can never collide with a MatchRng seed hash.
const _SALT_CHECKSUM := 0x5265706C6179      # "Replay"
## Separator between variable-length sub-records, mirroring CommandApplier's mixer marker.
const _SEP := 0x7FFFFFF1


## Redirect the replay directory (tests; a future "export this replay" flow). A blank path
## restores the default.
static func set_replay_dir(path: String) -> void:
	_replay_dir = path if not path.strip_edges().is_empty() else DEFAULT_REPLAY_DIR


static func get_replay_dir() -> String:
	return _replay_dir


# --- Construction ------------------------------------------------------------

## A normalised header from whatever [param fields] the caller could resolve. Every key gets
## a defined default, so a headless / partially-booted battle still produces a loadable file.
static func make_header(fields: Dictionary = {}) -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"game_version": _clip(String(fields.get("game_version", NetProtocol.local_game_version())), MAX_STRING),
		"protocol_version": int(fields.get("protocol_version", NetProtocol.PROTOCOL_VERSION)),
		"recorded_at_utc": _clip(String(fields.get("recorded_at_utc", "")), MAX_STRING),
		"mode": _mode_or_default(fields.get("mode", MODE_SKIRMISH)),
		"map": _clean_map(fields.get("map", {})),
		"participants": _clean_participants(fields.get("participants", [])),
		"rng": { "match_seed": int(_dict(fields.get("rng", {})).get("match_seed", 0)) },
		"turn_system": int(fields.get("turn_system", 0)),
		"difficulty": int(fields.get("difficulty", 0)),
		"challenge_id": _clip(String(fields.get("challenge_id", "")), MAX_STRING),
		"campaign_chapter_id": _clip(String(fields.get("campaign_chapter_id", "")), MAX_STRING),
	}


## An empty replay log around [param header] -- header keys plus the (empty) body. This is
## the dictionary [ReplayRecorder] appends into and the one [method validate] returns.
static func make_log(header: Dictionary = {}) -> Dictionary:
	var out: Dictionary = make_header(header)
	out["entries"] = []
	out["checksums"] = []
	out["outcome"] = make_outcome()
	out["truncated"] = false
	return out


static func make_outcome(result: String = RESULT_UNKNOWN, winner_slot: int = -1, turns: int = 0) -> Dictionary:
	return {
		"result": result if RESULTS.has(result) else RESULT_UNKNOWN,
		"winner_slot": int(winner_slot),
		"turns": maxi(0, int(turns)),
	}


## One body entry. [param cmd] is a LIVE NetProtocol command (Vector2i cells and all); it is
## encoded to its JSON-safe form here, so callers never have to think about the flattening.
static func make_entry(turn: int, actor_slot: int, cmd: Dictionary) -> Dictionary:
	return {
		"turn": maxi(0, int(turn)),
		"actor_slot": int(actor_slot),
		"cmd": encode_command(cmd),
	}


static func make_checksum(turn: int, hash_hex: String) -> Dictionary:
	return { "turn": maxi(0, int(turn)), "hash": _clip(hash_hex, MAX_STRING) }


# --- Command encoding --------------------------------------------------------

## [Vector2i] -> [code][x, y][/code] (same convention as [method BattleSnapshot.cell_to_array]).
static func encode_cell(cell: Vector2i) -> Array:
	return [int(cell.x), int(cell.y)]


## The inverse. Anything malformed reads as [param fallback] rather than raising.
static func decode_cell(value: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and (value as Array).size() >= 2:
		var a: Array = value
		if _is_number(a[0]) and _is_number(a[1]):
			return Vector2i(int(a[0]), int(a[1]))
	return fallback


## A live NetProtocol command -> its JSON-safe form. Returns {} for anything that is not a
## command this build can replay (the SAME gate [method decode_command] applies), so a
## recorder can never write an entry playback would have to reject.
static func encode_command(cmd: Variant) -> Dictionary:
	if not (cmd is Dictionary):
		return {}
	var src: Dictionary = cmd
	if not src.has(NetProtocol.KEY_TYPE) or not _is_number(src[NetProtocol.KEY_TYPE]):
		return {}
	var type: int = int(src[NetProtocol.KEY_TYPE])
	if not APPLIABLE_TYPES.has(type):
		return {}
	var data: Dictionary = _dict(src.get(NetProtocol.KEY_DATA, {}))
	var out_data: Dictionary = {}
	match type:
		NetProtocol.Action.CAST_MOVE:
			out_data[NetProtocol.KEY_UNIT_ID] = int(data.get(NetProtocol.KEY_UNIT_ID, -1))
			out_data[NetProtocol.KEY_MOVE_SLOT] = int(data.get(NetProtocol.KEY_MOVE_SLOT, -1))
			out_data[NetProtocol.KEY_AIM_CELL] = encode_cell(decode_cell(data.get(NetProtocol.KEY_AIM_CELL, null)))
		NetProtocol.Action.MOVE_UNIT:
			out_data[NetProtocol.KEY_UNIT_ID] = int(data.get(NetProtocol.KEY_UNIT_ID, -1))
			out_data[NetProtocol.KEY_DEST_CELL] = encode_cell(decode_cell(data.get(NetProtocol.KEY_DEST_CELL, null)))
		NetProtocol.Action.WAIT_UNIT:
			out_data[NetProtocol.KEY_UNIT_ID] = int(data.get(NetProtocol.KEY_UNIT_ID, -1))
		NetProtocol.Action.END_TURN:
			out_data[NetProtocol.KEY_PLAYER_ID] = int(data.get(NetProtocol.KEY_PLAYER_ID, 0))
	return {
		NetProtocol.KEY_TYPE: type,
		NetProtocol.KEY_DATA: out_data,
		NetProtocol.KEY_ACTOR: int(src.get(NetProtocol.KEY_ACTOR, -1)),
		NetProtocol.KEY_SEQ: int(src.get(NetProtocol.KEY_SEQ, 0)),
		NetProtocol.KEY_RNG_SEED: int(src.get(NetProtocol.KEY_RNG_SEED, 0)),
		NetProtocol.KEY_PV: int(src.get(NetProtocol.KEY_PV, NetProtocol.PROTOCOL_VERSION)),
	}


## The JSON-safe form -> a LIVE command the applier accepts (cells back to [Vector2i]).
## Returns {} for anything outside the vocabulary or missing a required field -- the ONE
## gate playback needs before handing an entry to [method CommandApplier.apply_command].
static func decode_command(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var src: Dictionary = raw
	if not src.has(NetProtocol.KEY_TYPE) or not _is_number(src[NetProtocol.KEY_TYPE]):
		return {}
	var type: int = int(src[NetProtocol.KEY_TYPE])
	if not APPLIABLE_TYPES.has(type):
		return {}
	var data: Dictionary = _dict(src.get(NetProtocol.KEY_DATA, {}))
	var out_data: Dictionary = {}
	match type:
		NetProtocol.Action.CAST_MOVE:
			if not _has_number(data, NetProtocol.KEY_UNIT_ID) or not _has_number(data, NetProtocol.KEY_MOVE_SLOT):
				return {}
			if not data.has(NetProtocol.KEY_AIM_CELL):
				return {}
			out_data[NetProtocol.KEY_UNIT_ID] = int(data[NetProtocol.KEY_UNIT_ID])
			out_data[NetProtocol.KEY_MOVE_SLOT] = int(data[NetProtocol.KEY_MOVE_SLOT])
			out_data[NetProtocol.KEY_AIM_CELL] = decode_cell(data[NetProtocol.KEY_AIM_CELL], Vector2i(-1, -1))
		NetProtocol.Action.MOVE_UNIT:
			if not _has_number(data, NetProtocol.KEY_UNIT_ID) or not data.has(NetProtocol.KEY_DEST_CELL):
				return {}
			out_data[NetProtocol.KEY_UNIT_ID] = int(data[NetProtocol.KEY_UNIT_ID])
			out_data[NetProtocol.KEY_DEST_CELL] = decode_cell(data[NetProtocol.KEY_DEST_CELL], Vector2i(-1, -1))
		NetProtocol.Action.WAIT_UNIT:
			if not _has_number(data, NetProtocol.KEY_UNIT_ID):
				return {}
			out_data[NetProtocol.KEY_UNIT_ID] = int(data[NetProtocol.KEY_UNIT_ID])
		NetProtocol.Action.END_TURN:
			if not _has_number(data, NetProtocol.KEY_PLAYER_ID):
				return {}
			out_data[NetProtocol.KEY_PLAYER_ID] = int(data[NetProtocol.KEY_PLAYER_ID])
	var out: Dictionary = {
		NetProtocol.KEY_TYPE: type,
		NetProtocol.KEY_DATA: out_data,
		NetProtocol.KEY_ACTOR: int(src.get(NetProtocol.KEY_ACTOR, -1)),
		NetProtocol.KEY_SEQ: int(src.get(NetProtocol.KEY_SEQ, 0)),
		NetProtocol.KEY_RNG_SEED: int(src.get(NetProtocol.KEY_RNG_SEED, 0)),
		NetProtocol.KEY_PV: int(src.get(NetProtocol.KEY_PV, NetProtocol.PROTOCOL_VERSION)),
	}
	# Final gate: the live protocol validator agrees this is appliable.
	if not NetProtocol.is_command_well_formed(out):
		return {}
	return out


# --- The per-turn state checksum ---------------------------------------------

## Stable hash of a board state, as a 16-char lowercase hex string.
##
## PURE and ORDER-INDEPENDENT by construction: [param rows] is sorted by unit id before
## anything is mixed, so the same state hashes identically no matter what order the caller
## walked the board in (scene order is NOT stable across peers, which is exactly the bug
## this guards). Each row is [code]{ "id": int, "cell": Vector2i|[x,y], "hp": int }[/code];
## a row that is not a Dictionary is skipped rather than raising.
##
## Deliberately CHEAP -- ids, cells and HP only. It is a divergence TRIPWIRE for playback,
## not a full state capture; [method CommandApplier.hash_match_state] is the richer
## (statuses + cooldowns) desync detector the live net layer uses, and this mirrors its
## mixing discipline (fixed order, separators between variable-length records).
static func state_checksum(rows: Array) -> String:
	var clean: Array = []
	for row in rows:
		if not (row is Dictionary):
			continue
		var r: Dictionary = row
		var cell: Vector2i = decode_cell(r.get("cell", null), Vector2i.ZERO)
		clean.append([int(r.get("id", -1)), int(cell.x), int(cell.y), int(r.get("hp", 0))])
	clean.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	var parts: Array = [_SALT_CHECKSUM, clean.size(), _SEP]
	for r in clean:
		parts.append(r[0])
		parts.append(r[1])
		parts.append(r[2])
		parts.append(r[3])
		parts.append(_SEP)
	return to_hex64(MatchRng._mix(parts))


## A signed 64-bit int as a fixed 16-char lowercase hex string. Split into two 32-bit halves
## because "%x" on a negative int prints a sign rather than the bit pattern.
static func to_hex64(value: int) -> String:
	return "%08x%08x" % [(value >> 32) & 0xFFFFFFFF, value & 0xFFFFFFFF]


# --- Text codec --------------------------------------------------------------

## Serialise to JSON. Compact (not pretty-printed): a replay is a machine artefact that gets
## gzip'd immediately, and 5000 entries of tab indentation is pure waste.
static func to_json(log: Dictionary) -> String:
	return JSON.stringify(log)


## Parse JSON text into a raw dictionary, or {} for anything that is not a JSON object.
##
## Uses an INSTANCE [JSON] rather than [method JSON.parse_string]: the static helper logs an
## engine error on malformed input, and a corrupt / hand-edited / hostile replay is an
## EXPECTED case here (convention #1 -- and GUT fails a test on any engine error).
static func parse_text(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return {}
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	return parsed if parsed is Dictionary else {}


## True when [param raw] is a dictionary this build knows how to replay. Cheap pre-check;
## [method validate] is the one that actually sanitises.
static func is_supported(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var d: Dictionary = raw
	if int(d.get("format_version", 0)) != FORMAT_VERSION:
		return false
	if not (d.get("entries", null) is Array):
		return false
	return true


## THE STRICT IMPORTER. Take an untrusted parsed dictionary and return a fully normalised
## replay log, or {} if it cannot be one. Every field is whitelisted, every string clipped,
## every list capped, and every command re-validated against the live NetProtocol vocabulary.
## Unknown keys are DROPPED (never carried through), so what playback sees is exactly the
## documented shape and nothing else.
##
## Returns {} -- never raises, never logs -- for: a non-dictionary, a wrong/absent
## format_version, a protocol_version this build cannot apply, or a body that is not a list.
static func validate(raw: Variant) -> Dictionary:
	if not is_supported(raw):
		return {}
	var d: Dictionary = raw
	# The command vocabulary is the hard gate, exactly as it is for a networked join: a file
	# written against a different protocol cannot be re-simulated by this build.
	if int(d.get("protocol_version", -1)) != NetProtocol.PROTOCOL_VERSION:
		return {}

	var out: Dictionary = make_log({
		"game_version": String(d.get("game_version", "")),
		"protocol_version": int(d.get("protocol_version", NetProtocol.PROTOCOL_VERSION)),
		"recorded_at_utc": String(d.get("recorded_at_utc", "")),
		"mode": d.get("mode", MODE_SKIRMISH),
		"map": d.get("map", {}),
		"participants": d.get("participants", []),
		"rng": d.get("rng", {}),
		"turn_system": int(d.get("turn_system", 0)),
		"difficulty": int(d.get("difficulty", 0)),
		"challenge_id": String(d.get("challenge_id", "")),
		"campaign_chapter_id": String(d.get("campaign_chapter_id", "")),
	})

	var entries: Array = []
	for item in (d.get("entries", []) as Array):
		if entries.size() >= MAX_ENTRIES:
			break
		if not (item is Dictionary):
			continue
		var e: Dictionary = item
		var cmd: Dictionary = decode_command(e.get("cmd", null))
		if cmd.is_empty():
			continue  # unknown / malformed command: dropped, never raised
		entries.append({
			"turn": maxi(0, int(e.get("turn", 0))),
			"actor_slot": int(e.get("actor_slot", -1)),
			"cmd": encode_command(cmd),
		})
	out["entries"] = entries

	var checks: Array = []
	for item in (d.get("checksums", []) as Array):
		if checks.size() >= MAX_CHECKSUMS:
			break
		if not (item is Dictionary):
			continue
		var c: Dictionary = item
		if not _is_number(c.get("turn", null)) or not (c.get("hash", null) is String):
			continue
		checks.append(make_checksum(int(c["turn"]), String(c["hash"])))
	out["checksums"] = checks

	var outcome: Dictionary = _dict(d.get("outcome", {}))
	out["outcome"] = make_outcome(
		String(outcome.get("result", RESULT_UNKNOWN)),
		int(outcome.get("winner_slot", -1)),
		int(outcome.get("turns", 0)))
	out["truncated"] = bool(d.get("truncated", false))
	return out


## True when this build can replay [param log] -- i.e. it validated AND its game_version
## matches this build's. The game version is the SOFT gate playback reports on; the format
## and protocol versions are already hard-refused by [method validate].
static func matches_this_build(log: Dictionary) -> bool:
	return String(log.get("game_version", "")) == NetProtocol.local_game_version()


# --- Byte codec (the on-disk container) --------------------------------------

## Serialise to the on-disk container: JSON -> UTF-8 -> gzip, wrapped in
## [code]magic | container_version | uncompressed_size | sha256(payload)[/code]. The digest
## is what lets [method from_bytes] refuse a tampered file WITHOUT handing it to the
## decompressor (whose failure path is an uncatchable engine error).
static func to_bytes(log: Dictionary) -> PackedByteArray:
	var raw: PackedByteArray = to_json(log).to_utf8_buffer()
	var payload: PackedByteArray = raw.compress(FileAccess.COMPRESSION_GZIP)
	var head: PackedByteArray = PackedByteArray()
	head.resize(CONTAINER_HEADER_SIZE)
	for i in 4:
		head.encode_u8(i, CONTAINER_MAGIC.unicode_at(i))
	head.encode_u32(4, CONTAINER_VERSION)
	head.encode_u32(8, raw.size())
	var digest: PackedByteArray = _sha256(payload)
	for i in 32:
		head.encode_u8(12 + i, digest[i] if i < digest.size() else 0)
	return head + payload


## The inverse: container bytes -> a VALIDATED replay log, or {} for anything that is not
## one. Quiet on every rejection path (bad magic, wrong container version, oversized,
## digest mismatch, short read, non-JSON, failed validation).
static func from_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() <= CONTAINER_HEADER_SIZE:
		return {}
	for i in 4:
		if bytes.decode_u8(i) != CONTAINER_MAGIC.unicode_at(i):
			return {}
	if bytes.decode_u32(4) != CONTAINER_VERSION:
		return {}
	var original_size: int = bytes.decode_u32(8)
	if original_size <= 0 or original_size > MAX_DECOMPRESSED_BYTES:
		return {}
	var payload: PackedByteArray = bytes.slice(CONTAINER_HEADER_SIZE)
	var digest: PackedByteArray = _sha256(payload)
	if digest.size() != 32:
		return {}
	for i in 32:
		if bytes.decode_u8(12 + i) != digest[i]:
			return {}
	# Only bytes byte-identical to something we wrote reach here, so decompress cannot fail.
	var raw: PackedByteArray = payload.decompress(original_size, FileAccess.COMPRESSION_GZIP)
	if raw.size() != original_size:
		return {}
	return validate(parse_text(raw.get_string_from_utf8()))


# --- Files -------------------------------------------------------------------

## A stable, collision-resistant filename for [param log]:
## [code]<mode>_<map>_<stamp><FILE_EXTENSION>[/code], everything sanitised to
## [code][a-z0-9_-][/code]. [param stamp] is injected (never read off the wall clock here)
## so the caller owns time and this stays pure.
static func suggest_filename(log: Dictionary, stamp: String = "") -> String:
	var mode: String = _safe_name(String(log.get("mode", MODE_SKIRMISH)))
	var map_path: String = String(_dict(log.get("map", {})).get("path", ""))
	var map_name: String = _safe_name(map_path.get_file().get_basename())
	if map_name.is_empty():
		map_name = "map"
	var tail: String = _safe_name(stamp)
	if tail.is_empty():
		tail = "replay"
	return "%s_%s_%s%s" % [mode, map_name, tail, FILE_EXTENSION]


## Write [param log] into the replay directory. [param filename] defaults to
## [method suggest_filename] with a UTC stamp. Returns the full path, or "" on any failure
## (unwritable directory, oversized log) -- quiet, per convention #1.
static func save_to_file(log: Dictionary, filename: String = "") -> String:
	var name: String = filename.strip_edges()
	if name.is_empty():
		name = suggest_filename(log, Time.get_datetime_string_from_system(true).replace(":", "").replace("-", ""))
	if not name.ends_with(FILE_EXTENSION):
		name += FILE_EXTENSION
	if not _ensure_dir():
		return ""
	var bytes: PackedByteArray = to_bytes(log)
	if bytes.is_empty() or bytes.size() > MAX_FILE_BYTES:
		return ""
	var path: String = _replay_dir.path_join(name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	return path


## Read and VALIDATE the replay at [param path]. Returns {} for a missing / unreadable /
## oversized / malformed / version-mismatched file. Never loads a resource, never logs.
static func load_from_file(path: String) -> Dictionary:
	if path.strip_edges().is_empty() or not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var length: int = int(file.get_length())
	if length <= CONTAINER_HEADER_SIZE or length > MAX_FILE_BYTES:
		file.close()
		return {}
	var bytes: PackedByteArray = file.get_buffer(length)
	file.close()
	return from_bytes(bytes)


## Every replay on disk, newest filename last, as
## [code]{ "path": String, "filename": String, "bytes": int }[/code]. Does NOT parse the
## files -- listing must stay cheap enough for a browse screen; call
## [method load_from_file] for the one the player picked.
static func list_replays() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(_replay_dir)
	if dir == null:
		return out
	var names: Array = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "" and names.size() < MAX_LISTED_FILES:
		if not dir.current_is_dir() and entry.ends_with(FILE_EXTENSION):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for n in names:
		var path: String = _replay_dir.path_join(String(n))
		var size: int = 0
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f != null:
			size = int(f.get_length())
			f.close()
		out.append({ "path": path, "filename": String(n), "bytes": size })
	return out


## Delete one replay. Returns true when the file is gone afterwards.
static func delete_replay(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return not FileAccess.file_exists(path)


# --- Internals ---------------------------------------------------------------

static func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(_replay_dir):
		return true
	return DirAccess.make_dir_recursive_absolute(_replay_dir) == OK


static func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var ctx: HashingContext = HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if ctx.update(bytes) != OK:
		return PackedByteArray()
	return ctx.finish()


static func _clean_map(value: Variant) -> Dictionary:
	var src: Dictionary = _dict(value)
	var payload: Dictionary = _dict(src.get("payload", {}))
	# An embedded custom-map payload is INERT JSON, carried verbatim for the playback wave to
	# hand to MapResource.import_from_json (the hardened importer) -- never to load(). Capped
	# so a hostile file cannot ship a million-key dictionary.
	if payload.size() > MAX_PAYLOAD_KEYS:
		payload = {}
	return {
		"path": _clip(String(src.get("path", "")), MAX_PATH),
		"name": _clip(String(src.get("name", "")), MAX_STRING),
		"custom": bool(src.get("custom", false)),
		"payload": payload,
	}


static func _clean_participants(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for item in (value as Array):
		if out.size() >= MAX_PARTICIPANTS:
			break
		if not (item is Dictionary):
			continue
		var p: Dictionary = item
		out.append({
			"slot": int(p.get("slot", out.size())),
			"name": _clip(String(p.get("name", "")), MAX_STRING),
			"is_ai": bool(p.get("is_ai", false)),
			"squad": _clean_id_list(p.get("squad", [])),
			"items": _clean_id_list(p.get("items", [])),
			"skins": _clean_id_map(p.get("skins", {})),
		})
	return out


## A plain [Array] of clipped id Strings. Deliberately NOT typed [code]Array[String][/code]:
## a JSON-parsed plain Array cannot be assigned to a typed one (project convention #3), and
## this value goes straight back into JSON.
static func _clean_id_list(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for item in (value as Array):
		if out.size() >= MAX_LIST:
			break
		var id: String = _clip(String(item), MAX_STRING).strip_edges()
		if not id.is_empty():
			out.append(id)
	return out


static func _clean_id_map(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	for key in (value as Dictionary).keys():
		if out.size() >= MAX_LIST:
			break
		var k: String = _clip(String(key), MAX_STRING).strip_edges()
		var v: String = _clip(String((value as Dictionary)[key]), MAX_STRING).strip_edges()
		if not k.is_empty() and not v.is_empty():
			out[k] = v
	return out


static func _mode_or_default(value: Variant) -> String:
	var mode: String = _clip(String(value), MAX_STRING)
	return mode if MODES.has(mode) else MODE_SKIRMISH


static func _safe_name(value: String) -> String:
	var out: String = ""
	for i in value.length():
		var c: int = value.to_lower().unicode_at(i)
		var ok: bool = (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95 or c == 45
		out += String.chr(c) if ok else "_"
		if out.length() >= 48:
			break
	return out.strip_edges()


static func _clip(value: String, limit: int) -> String:
	return value if value.length() <= limit else value.substr(0, limit)


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _has_number(data: Dictionary, key: String) -> bool:
	return data.has(key) and _is_number(data[key])
