extends RefCounted

class_name ChallengeCodec

## Serverless async CHALLENGE format + share codec (Challenge Maps, Phase A).
##
## A "challenge" is a map a player built in the creator with THEIR units placed as
## AI-controlled defenders (player slots 1+), packaged so another player can import it,
## pick a squad, and battle the defense. There is no server and no live connection: the
## whole challenge travels as one validated JSON blob, or as a compact base64 SHARE CODE.
##
## This class is the ONE place that encodes/decodes/validates that blob. It is pure and
## static so it can be unit-tested headless and reused by the creator, the browse screen
## and the play controller without any of them depending on each other.
##
## SECURITY POSTURE: a share code is UNTRUSTED input authored by another player.
##   * The map inside it is only ever turned into a live resource through
##     [method MapResource.import_from_json], which runs the hardened, catalog-strict
##     validator and returns null on anything unknown / out of bounds / oversized. We
##     NEVER instantiate a resource from the raw blob any other way (no ResourceLoader
##     on shared bytes -> no arbitrary-code-execution vector).
##   * decode() caps the decompressed size, so a tiny code cannot expand into a
##     decompression bomb.
##   * The checksum is a plain content hash for TAMPER DETECTION, not a signature. It
##     catches accidental corruption / casual edits; it is not a security boundary.

## The only format this build writes. Bump when the on-wire shape changes.
## v2 (this build) ADDS rules.mode / rules.survive_turns / rules.par_turns. v1 codes still
## decode: the reader version-gates the new fields (see [method rules_mode] etc.) and the
## checksum is hashed with the v1 field set for v1 blobs, so old share codes stay valid.
const FORMAT_VERSION := 2

## Every format_version this build can still decode (kept as a set so old codes keep
## importing after a bump).
const SUPPORTED_VERSIONS: Array[int] = [1, 2]

## Challenge MODES (rules.mode). "breach" is the original behaviour (beat the map's own
## win condition -- clear the defense / kill the boss). "survive" wins when the challenger
## still has a unit standing after rules.survive_turns rounds (or clears the defense early).
const MODE_BREACH := "breach"
const MODE_SURVIVE := "survive"
const MODES: Array[String] = [MODE_BREACH, MODE_SURVIVE]
const DEFAULT_MODE := MODE_BREACH

## survive_turns band (rounds a challenger must last in "survive" mode).
const MIN_SURVIVE_TURNS := 6
const MAX_SURVIVE_TURNS := 30
const DEFAULT_SURVIVE_TURNS := 10

## par_turns band (author's target clear length, drives scoring). The sane default is a
## function of the defender count (see [method default_par_for]).
const MIN_PAR_TURNS := 3
const MAX_PAR_TURNS := 30

## Where saved / imported challenges live, as inert JSON (never .tres -- a shared .tres
## is an arbitrary-code-execution vector).
const DEFAULT_CHALLENGE_DIR := "user://challenges/"

static var _challenge_dir: String = DEFAULT_CHALLENGE_DIR

## Hard ceiling on the JSON a share code may decompress to (bytes). A 12x12 map's blob
## is a few KB; this is generous headroom while still stopping a decompression bomb.
const MAX_DECODE_BYTES := 4 * 1024 * 1024  # 4 MB

## Squad-size band the author may demand of a challenger (mirrors the roster cap).
const MIN_SQUAD_SIZE := 1
const MAX_SQUAD_SIZE := 6


# --- Construction -----------------------------------------------------------

## Build a fresh challenge dictionary from an in-memory [MapResource] and metadata.
## [param created] is passed in by the caller (authoring time) and stored verbatim --
## gameplay logic never derives it from the wall clock. The checksum is computed last so
## the returned dict is self-consistent and ready to [method encode] / [method validate].
static func build_challenge(map_resource: MapResource, p_name: String, p_author: String, p_created: String, rules: Dictionary) -> Dictionary:
	var map_dict: Dictionary = _map_resource_to_dict(map_resource)

	# Mode + its dependent fields (v2). An unknown mode falls back to breach.
	var mode: String = String(rules.get("mode", DEFAULT_MODE))
	if not MODES.has(mode):
		mode = DEFAULT_MODE
	var survive_turns: int = clampi(int(rules.get("survive_turns", DEFAULT_SURVIVE_TURNS)), MIN_SURVIVE_TURNS, MAX_SURVIVE_TURNS)
	# Par defaults from the defense size when the author didn't set it, then clamps to band.
	var default_par: int = default_par_for(_defender_count_in_map(map_dict))
	var par_turns: int = clampi(int(rules.get("par_turns", default_par)), MIN_PAR_TURNS, MAX_PAR_TURNS)

	var challenge: Dictionary = {
		"format_version": FORMAT_VERSION,
		"name": String(p_name),
		"author": String(p_author),
		"created": String(p_created),
		"map": map_dict,
		"rules": {
			"challenger_squad_size": clampi(int(rules.get("challenger_squad_size", 4)), MIN_SQUAD_SIZE, MAX_SQUAD_SIZE),
			"turn_system": int(rules.get("turn_system", 0)),
			"ai_difficulty": int(rules.get("ai_difficulty", 1)),
			"mode": mode,
			"survive_turns": survive_turns,
			"par_turns": par_turns,
		},
	}
	challenge["checksum"] = content_hash(challenge)
	return challenge


## The sane default par (author's target clear length) for a defense of [param defenders]
## units: defenders + 3, clamped to the par band. Exposed so the creator UI can seed its par
## spinbox with the same value the codec would.
static func default_par_for(defenders: int) -> int:
	return clampi(defenders + 3, MIN_PAR_TURNS, MAX_PAR_TURNS)


## Recompute the checksum over [param challenge] and stamp it in place, returning the same
## dict. Used to FINALISE a trusted, hand-authored challenge (a builtin JSON shipped in
## res://) whose file carries no valid checksum -- the equivalent of what [method build_challenge]
## does at the end. NEVER call this on an untrusted imported code: that would paper over a
## real tamper. Untrusted codes keep their author's checksum and are verified by [method validate].
static func stamp_checksum(challenge: Dictionary) -> Dictionary:
	challenge["checksum"] = content_hash(challenge)
	return challenge


## Defender count straight off a map DICT (not a challenge), used while building. Mirrors
## [method defense_count] but reads the already-extracted map layout.
static func _defender_count_in_map(map_dict: Dictionary) -> int:
	var layout: Dictionary = map_dict.get("layout", {})
	var spawns: Array = layout.get("unit_spawns", [])
	var count: int = 0
	for entry in spawns:
		if not (entry is Dictionary):
			continue
		if int(entry.get("player_id", 0)) < 1:
			continue
		if not String(entry.get("character_id", "")).strip_edges().is_empty():
			count += 1
	return count


## Parse a [MapResource]'s canonical JSON export into a Dictionary so the map rides inside
## the challenge as structured data (not a doubly-escaped string). Round-trips exactly
## through [method MapResource.import_from_json] on the way back.
static func _map_resource_to_dict(map_resource: MapResource) -> Dictionary:
	if map_resource == null:
		return {}
	var parsed: Variant = JSON.parse_string(map_resource.export_to_json())
	return parsed if parsed is Dictionary else {}


# --- Checksum ---------------------------------------------------------------

## Deterministic content hash of everything in [param challenge] EXCEPT the checksum
## field itself. Built from a fixed field ORDER (not dict iteration order) so encode and
## decode always agree, then hashed via String.hash(). Tamper detection only.
static func content_hash(challenge: Dictionary) -> String:
	var version: int = int(challenge.get("format_version", 0))
	var rules: Dictionary = challenge.get("rules", {})
	var parts: Array = [
		str(version),
		String(challenge.get("name", "")),
		String(challenge.get("author", "")),
		String(challenge.get("created", "")),
		JSON.stringify(challenge.get("map", {})),
		str(int(rules.get("challenger_squad_size", 0))),
		str(int(rules.get("turn_system", 0))),
		str(int(rules.get("ai_difficulty", 0))),
	]
	# v2 fields are hashed ONLY for v2+ blobs, so a v1 code's checksum is computed over the
	# exact v1 field set and still verifies after this build added the new fields.
	if version >= 2:
		parts.append(String(rules.get("mode", DEFAULT_MODE)))
		parts.append(str(int(rules.get("survive_turns", DEFAULT_SURVIVE_TURNS))))
		parts.append(str(int(rules.get("par_turns", 0))))
	return str("".join(PackedStringArray(parts)).hash())


# --- Rule accessors (version-gated reads) -----------------------------------
# The play/scoring code reads rules THROUGH these so a v1 challenge (which has none of the
# v2 fields) transparently gets sane defaults, and a v2 challenge gets its stored values.

## The challenge mode ("breach" | "survive"); breach for any v1 code or unknown value.
static func rules_mode(challenge: Dictionary) -> String:
	var rules: Dictionary = challenge.get("rules", {})
	var mode: String = String(rules.get("mode", DEFAULT_MODE))
	return mode if MODES.has(mode) else DEFAULT_MODE


## Rounds the challenger must last in survive mode (clamped to band; the default otherwise).
static func rules_survive_turns(challenge: Dictionary) -> int:
	var rules: Dictionary = challenge.get("rules", {})
	return clampi(int(rules.get("survive_turns", DEFAULT_SURVIVE_TURNS)), MIN_SURVIVE_TURNS, MAX_SURVIVE_TURNS)


## Author's target clear length (drives scoring). For a v1 code with no stored par this
## derives the same default build_challenge would (defenders + 3, clamped).
static func rules_par_turns(challenge: Dictionary) -> int:
	var rules: Dictionary = challenge.get("rules", {})
	if rules.has("par_turns"):
		return clampi(int(rules.get("par_turns", 0)), MIN_PAR_TURNS, MAX_PAR_TURNS)
	return default_par_for(defense_count(challenge))


## The stable id of a challenge (its checksum), used to key local results.
static func challenge_id(challenge: Dictionary) -> String:
	return String(challenge.get("checksum", ""))


# --- Encode / decode --------------------------------------------------------

## Encode a challenge dict into a compact, copy-pasteable share code:
## JSON -> UTF-8 -> gzip -> (4-byte length header + payload) -> base64.
## The length header lets [method decode] inflate with an exact output size, which is
## both faster and immune to any streaming-inflate quirk.
static func encode(challenge: Dictionary) -> String:
	var json_text: String = JSON.stringify(challenge)
	var raw: PackedByteArray = json_text.to_utf8_buffer()
	var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_GZIP)

	var header: PackedByteArray = PackedByteArray()
	header.resize(4)
	header.encode_u32(0, raw.size())

	var blob: PackedByteArray = header + compressed
	return Marshalls.raw_to_base64(blob)


## Strict base64 shape check: length divisible by 4, only [A-Za-z0-9+/] with up to two
## trailing '=' pads. Keeps obviously-garbage codes away from Marshalls (which logs an
## engine error on malformed input instead of failing quietly).
static func _looks_like_base64(s: String) -> bool:
	if s.length() < 8 or s.length() % 4 != 0:
		return false
	var pad_start: int = s.find("=")
	var body: String = s if pad_start == -1 else s.substr(0, pad_start)
	var pad: String = "" if pad_start == -1 else s.substr(pad_start)
	if pad.length() > 2:
		return false
	for ch in pad:
		if ch != "=":
			return false
	for i in body.length():
		var c: int = body.unicode_at(i)
		var ok: bool = (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 43 or c == 47
		if not ok:
			return false
	return true


## Decode a share code back into a challenge dict. Returns an EMPTY dict on any failure
## (bad base64, truncated blob, oversized/failed inflate, non-JSON, wrong root type) so
## callers uniformly treat {} as "invalid code". Does NOT validate content -- run the
## result through [method validate] for that.
static func decode(code: String) -> Dictionary:
	var trimmed: String = code.strip_edges()
	if trimmed.is_empty():
		return {}

	# Pre-validate the base64 shape BEFORE handing it to Marshalls: base64_to_raw
	# push_error()s internally on malformed input, which would spam the log (and
	# fail tests as an unexpected engine error) for something that is simply an
	# invalid share code.
	if not _looks_like_base64(trimmed):
		return {}

	var blob: PackedByteArray = Marshalls.base64_to_raw(trimmed)
	if blob.size() < 5:
		return {}

	var orig_size: int = blob.decode_u32(0)
	if orig_size <= 0 or orig_size > MAX_DECODE_BYTES:
		return {}

	var compressed: PackedByteArray = blob.slice(4)
	var raw: PackedByteArray = compressed.decompress(orig_size, FileAccess.COMPRESSION_GZIP)
	if raw.size() != orig_size:
		return {}

	var json_text: String = raw.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return {}
	return parsed


# --- Validation -------------------------------------------------------------

## Validate a decoded challenge, returning a list of human-readable error strings (empty
## == valid). Checks, in order: supported format_version; required keys + types; the map
## passes [MapResource]'s catalog-strict validation; a defense exists (>=1 player-1+ spawn
## that names a character); squad size in band; checksum matches the content.
static func validate(challenge: Dictionary) -> Array[String]:
	var errors: Array[String] = []

	if not (challenge is Dictionary) or challenge.is_empty():
		errors.append("Challenge is empty or not an object.")
		return errors

	# format_version
	if not challenge.has("format_version"):
		errors.append("Missing format_version.")
	elif not SUPPORTED_VERSIONS.has(int(challenge.get("format_version", -1))):
		errors.append("Unsupported format_version %s (this build supports %s)." % [
			str(challenge.get("format_version")), str(SUPPORTED_VERSIONS)])

	# Required top-level keys + coarse types.
	for key in ["name", "author", "created", "checksum"]:
		if not challenge.has(key):
			errors.append("Missing '%s'." % key)
	if not (challenge.get("map", null) is Dictionary):
		errors.append("Missing or malformed 'map'.")
	if not (challenge.get("rules", null) is Dictionary):
		errors.append("Missing or malformed 'rules'.")

	# Nothing further is meaningful once the shape is broken.
	if not errors.is_empty():
		return errors

	# Rules band.
	var rules: Dictionary = challenge.get("rules", {})
	var squad_size: int = int(rules.get("challenger_squad_size", 0))
	if squad_size < MIN_SQUAD_SIZE or squad_size > MAX_SQUAD_SIZE:
		errors.append("challenger_squad_size %d is outside %d..%d." % [squad_size, MIN_SQUAD_SIZE, MAX_SQUAD_SIZE])

	# v2 mode/par/survive band. Only enforced when the fields are actually present (a v1 code
	# carries none of them and reads them through the defaulting accessors instead), so old
	# codes never trip these checks.
	if rules.has("mode") and not MODES.has(String(rules.get("mode", ""))):
		errors.append("Unknown mode '%s' (expected one of %s)." % [str(rules.get("mode")), str(MODES)])
	if rules.has("par_turns"):
		var par: int = int(rules.get("par_turns", 0))
		if par < MIN_PAR_TURNS or par > MAX_PAR_TURNS:
			errors.append("par_turns %d is outside %d..%d." % [par, MIN_PAR_TURNS, MAX_PAR_TURNS])
	if String(rules.get("mode", DEFAULT_MODE)) == MODE_SURVIVE and rules.has("survive_turns"):
		var st: int = int(rules.get("survive_turns", 0))
		if st < MIN_SURVIVE_TURNS or st > MAX_SURVIVE_TURNS:
			errors.append("survive_turns %d is outside %d..%d." % [st, MIN_SURVIVE_TURNS, MAX_SURVIVE_TURNS])

	# The map must survive the hardened, catalog-strict import (unknown tiles / characters,
	# out-of-bounds cells and a bad size are all hard failures here). quiet=true: a
	# rejection here is an EXPECTED probe outcome reported via our own errors list.
	var map_resource: MapResource = map_resource_from_challenge(challenge, true)
	if map_resource == null:
		errors.append("Map failed validation (unknown assets, bad size, or out-of-bounds cells).")

	# A challenge needs a DEFENSE: at least one player-1+ spawn that names a character.
	if defense_count(challenge) < 1:
		errors.append("No defenders: place at least one of your units on a player 2+ slot.")

	# Checksum: recompute over the content and compare. A mismatch means the code was
	# edited/corrupted after it was built.
	var expected: String = content_hash(challenge)
	if String(challenge.get("checksum", "")) != expected:
		errors.append("Checksum mismatch (the code was modified or corrupted).")

	return errors


## How many AI-defender spawns (player_id >= 1) name a character. Reads the map dict the
## way [method MapResource.export_to_json] writes it (layout.unit_spawns), so it never has
## to instantiate the map to answer.
static func defense_count(challenge: Dictionary) -> int:
	var map_dict: Dictionary = challenge.get("map", {})
	var layout: Dictionary = map_dict.get("layout", {})
	var spawns: Array = layout.get("unit_spawns", [])
	var count: int = 0
	for entry in spawns:
		if not (entry is Dictionary):
			continue
		if int(entry.get("player_id", 0)) < 1:
			continue
		if not String(entry.get("character_id", "")).strip_edges().is_empty():
			count += 1
	return count


## Reconstruct the challenge's map as a validated [MapResource], or null if it fails the
## strict import. This is the ONLY path that turns the untrusted map into a live resource.
## quiet=true (used by [method validate], which reports failures through its own error
## list) suppresses the import's push_error for EXPECTED rejections of untrusted codes.
static func map_resource_from_challenge(challenge: Dictionary, quiet: bool = false) -> MapResource:
	var map_dict: Dictionary = challenge.get("map", {})
	if map_dict.is_empty():
		return null
	return MapResource.import_from_json(JSON.stringify(map_dict), quiet)


# --- Local files ------------------------------------------------------------

## Point the codec at a different challenge directory. Exists for TESTS (a throwaway
## `user://test_*` dir) so a suite that saves or lists challenges never writes into -- or
## deletes out of -- the player's real library; normal play never calls it.
##
## An empty / whitespace-only [param dir] restores [constant DEFAULT_CHALLENGE_DIR]. The
## trailing "/" is forced because every internal use concatenates the dir with a bare file
## name, so a caller passing "user://test_challenges" must not silently produce
## "user://test_challengesfoo.json".
static func set_challenge_dir(dir: String) -> void:
	var trimmed: String = dir.strip_edges()
	if trimmed.is_empty():
		_challenge_dir = DEFAULT_CHALLENGE_DIR
		return
	_challenge_dir = trimmed if trimmed.ends_with("/") else trimmed + "/"


## The directory saved challenges currently read/write.
static func challenge_dir() -> String:
	return _challenge_dir


## Save a challenge to user://challenges/<sanitized-name>.json. Returns the path written,
## or "" on failure. Ensures the directory exists first.
static func save_to_file(challenge: Dictionary, file_name: String = "") -> String:
	_ensure_dir()
	var stem: String = file_name.strip_edges()
	if stem.is_empty():
		stem = String(challenge.get("name", "challenge"))
	stem = _sanitize_stem(stem)
	if stem.is_empty():
		stem = "challenge"
	var path: String = _challenge_dir + stem + ".json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(challenge, "\t"))
	file.close()
	return path


## Load a challenge dict from a JSON file, or {} if missing / unreadable / not an object.
static func load_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## Every saved challenge as { "path": String, "challenge": Dictionary }, skipping files
## that will not parse into an object. Used by the browse screen to build its list.
static func list_saved() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(_challenge_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and not file_name.begins_with("."):
			# results.json holds play records, not a challenge -- keep it out of the list.
			if file_name != "results.json":
				var challenge: Dictionary = load_from_file(_challenge_dir + file_name)
				if not challenge.is_empty():
					out.append({"path": _challenge_dir + file_name, "challenge": challenge})
		file_name = dir.get_next()
	dir.list_dir_end()
	return out


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(_challenge_dir):
		DirAccess.make_dir_recursive_absolute(_challenge_dir)


## Reduce an arbitrary name to a safe file stem (lowercase, alnum + underscore).
static func _sanitize_stem(name: String) -> String:
	var lowered: String = name.strip_edges().to_lower()
	var out: String = ""
	for i in lowered.length():
		var c: String = lowered[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")
