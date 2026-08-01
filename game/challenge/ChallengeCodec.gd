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
const FORMAT_VERSION := 1

## Every format_version this build can still decode (kept as a set so old codes keep
## importing after a bump).
const SUPPORTED_VERSIONS: Array[int] = [1]

## Where saved / imported challenges live, as inert JSON (never .tres -- a shared .tres
## is an arbitrary-code-execution vector).
const CHALLENGE_DIR := "user://challenges/"

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
		},
	}
	challenge["checksum"] = content_hash(challenge)
	return challenge


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
	var rules: Dictionary = challenge.get("rules", {})
	var parts: Array = [
		str(int(challenge.get("format_version", 0))),
		String(challenge.get("name", "")),
		String(challenge.get("author", "")),
		String(challenge.get("created", "")),
		JSON.stringify(challenge.get("map", {})),
		str(int(rules.get("challenger_squad_size", 0))),
		str(int(rules.get("turn_system", 0))),
		str(int(rules.get("ai_difficulty", 0))),
	]
	return str("".join(PackedStringArray(parts)).hash())


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
	var path: String = CHALLENGE_DIR + stem + ".json"
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
	var dir: DirAccess = DirAccess.open(CHALLENGE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and not file_name.begins_with("."):
			# results.json holds play records, not a challenge -- keep it out of the list.
			if file_name != "results.json":
				var challenge: Dictionary = load_from_file(CHALLENGE_DIR + file_name)
				if not challenge.is_empty():
					out.append({"path": CHALLENGE_DIR + file_name, "challenge": challenge})
		file_name = dir.get_next()
	dir.list_dir_end()
	return out


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(CHALLENGE_DIR):
		DirAccess.make_dir_recursive_absolute(CHALLENGE_DIR)


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
