extends RefCounted

## The SHARED half of every replay-watching surface: the sentences a player reads when a
## replay cannot be watched, and the two seams that reach the (parallel-workstream) replay
## codec + playback launcher.
##
## WHY THIS FILE EXISTS. Two screens watch replays -- [MyBases] (a defense replay pulled off
## the attempt ledger) and MyReplays (a recording off this device's disk) -- and both must
## say the SAME thing when a file was recorded on another build, when it decodes to nothing,
## or when playback bails on a divergence. Copy that lives in two screens drifts; this is the
## one place a future wording change is made. Every string below is a [code]const[/code] so a
## test pins the wording rather than retyping it.
##
## It is also the one place that RESOLVES the codec + playback entry points. Both are owned
## by the replay workstream and may not have landed in a given build, so nothing here
## references them by name at parse time:
##   * [method decode_container] prefers [code]ReplayLog.decode_container[/code] when the
##     build has it and falls back to the [method ReplayLog.from_bytes] that ships today;
##   * [method launch] loads [code]ReplayPlayback[/code] by PATH and reports
##     [code]{ok:false, error:"unavailable"}[/code] when the build does not ship it.
## Both take an INJECTED stand-in first, which is how a screen test watches a replay without
## a scene change ever happening.
##
## Preloaded BY PATH (`const ReplayWatch := preload("res://menus/ReplayWatch.gd")`), never by
## `class_name`: a brand new script is not in the project's global class cache until the
## project is next imported, and a screen that only parses after someone opens the editor is
## a screen that does not ship.
##
## Pure and static end to end -- no scene, no node, no state.

## Where the playback launcher lives when this build ships it. Loaded by path (see above).
const PLAYBACK_SCRIPT := "res://systems/replay/ReplayPlayback.gd"

# --- The copy ---------------------------------------------------------------
# One sentence per failure a player can actually hit. Each says what happened AND, where
# there is one, what to do about it -- never a raw error code.

## The file (or the downloaded blob) is not a replay this build can read at all: bad base64,
## a failed digest, a truncated container, a format version from another world.
const UNAVAILABLE := "Replay unavailable -- this recording could not be read."

## The replay is well-formed but was written by a different build of the game. The single
## source for the version-mismatch wording, per the brief.
const VERSION_MISMATCH := "Recorded on a different game version, so it can no longer be watched."

## Playback started and the re-simulation stopped matching the recorded checksums. Same
## single-source rule as [constant VERSION_MISMATCH].
const DIVERGED := "This replay diverged from the recorded battle and stopped early."

## The service has no replay for that attempt (or it has aged out of the ledger).
const NOT_FOUND := "That replay is no longer available."

## Someone else's base / someone else's attempt.
const NOT_OWNER := "That is not yours to watch."

## The build ships no playback path (the replay workstream's scene is absent).
const PLAYBACK_UNAVAILABLE := "Replay playback is not available in this build."

## The client predates the attempt-ledger endpoints.
const LOG_UNAVAILABLE := "Attack logs are not available in this build."

## Transient states, so the two screens spell "working on it" identically.
const LOADING_LOG := "Loading attacks..."
const LOADING_REPLAY := "Loading replay..."

## The ledger came back with nothing.
const NO_ATTACKS := "No attacks yet. When someone plays this base, every attempt lands here."

## No local recordings on disk.
const NO_RECORDINGS := "No replays saved yet. Finish a battle and it is recorded here."


# --- Error -> sentence ------------------------------------------------------

## What to say when [method ReplayPlayback.launch] refuses. [param error] is the contract's
## code; an unrecognised one is SURFACED (never swallowed) so a new refusal reason is visible
## in the wild rather than silently reading as success.
static func playback_notice(error: String) -> String:
	match error.strip_edges():
		"version_mismatch", "game_version", "build_mismatch":
			return VERSION_MISMATCH
		"diverged", "divergence", "checksum_mismatch", "desync":
			return DIVERGED
		"unavailable", "no_playback":
			return PLAYBACK_UNAVAILABLE
		"invalid", "unsupported", "format_version", "protocol_version", "empty":
			return UNAVAILABLE
		"not_found":
			return NOT_FOUND
		"":
			return "That replay could not be played."
	return "That replay could not be played: %s" % error


## What to say when fetching a replay blob fails. The pinned contract names "not_found" and
## "not_owner"; anything else is reported verbatim rather than hidden.
static func fetch_notice(error: String) -> String:
	match error.strip_edges():
		"not_found":
			return NOT_FOUND
		"not_owner":
			return NOT_OWNER
		"":
			return "That replay could not be loaded."
	return "That replay could not be loaded: %s" % error


## What to say when the attempt log itself will not load.
static func attempt_log_notice(error: String) -> String:
	match error.strip_edges():
		"not_owner":
			return "That base is not yours, so its attack log is closed."
		"not_found":
			return "That base is no longer on the service."
		"":
			return "The attack log could not be loaded."
	return "The attack log could not be loaded: %s" % error


## What to say when an upload is refused. The offline sandbox answers in prose ("Item already
## exists.") and the live service in codes, so BOTH shapes are matched -- a duplicate must
## read the same either way.
static func publish_notice(error: String) -> String:
	var trimmed: String = error.strip_edges()
	var lowered: String = trimmed.to_lower()
	if lowered == "duplicate" or lowered == "conflict" or lowered.contains("already exists"):
		return "That base is already published. Publish a different challenge."
	match trimmed:
		"base_limit":
			return "Your defense slots are full. Retire one, then publish again."
		"not_owner":
			return "That challenge is not yours to publish."
		"":
			return "That challenge could not be published."
	return "That challenge could not be published: %s" % trimmed


# --- Transport guards -------------------------------------------------------

## True when [param text] can be handed to [method Marshalls.base64_to_raw] WITHOUT the
## engine logging an error.
##
## This exists because [method Marshalls.base64_to_raw] is an [code]ERR_FAIL_COND_V[/code]
## on malformed input -- it prints to the engine log, and a hostile / truncated blob off a
## community service is an EXPECTED case here, not an impossible one (project convention #1,
## and GUT fails a test on any engine error). So the shape is checked HERE first and a bad
## blob simply never reaches the decoder.
##
## Callers should decode the STRIPPED string ([code]text.strip_edges()[/code]) -- that is
## what this validates.
static func is_base64(text: String) -> bool:
	var s: String = text.strip_edges()
	if s.is_empty() or s.length() % 4 != 0:
		return false
	# Padding may only TRAIL, and at most two of it.
	var body: int = s.length()
	while body > 0 and s.unicode_at(body - 1) == 61:  # '='
		body -= 1
	if body == 0 or s.length() - body > 2:
		return false
	for i in body:
		var c: int = s.unicode_at(i)
		var ok: bool = (c >= 65 and c <= 90) or (c >= 97 and c <= 122) \
			or (c >= 48 and c <= 57) or c == 43 or c == 47  # A-Z a-z 0-9 + /
		if not ok:
			return false
	return true


## Container bytes -> a validated replay log, or {} for anything that is not one.
##
## [param codec] is an injected stand-in (anything with
## [code]decode_container(PackedByteArray) -> Dictionary[/code]); null uses the real
## [ReplayLog], preferring its [code]decode_container[/code] when this build has one and
## falling back to [method ReplayLog.from_bytes], which is the same container reader under
## the older name. Never raises; {} is the one failure value.
static func decode_container(codec, bytes: PackedByteArray) -> Dictionary:
	if codec != null and codec.has_method("decode_container"):
		var injected: Variant = codec.decode_container(bytes)
		return injected if injected is Dictionary else {}
	var script: Object = ReplayLog
	if _script_has_method(script, "decode_container"):
		var out: Variant = script.call("decode_container", bytes)
		return out if out is Dictionary else {}
	return ReplayLog.from_bytes(bytes)


## Hand [param log] to the playback launcher. Returns the launcher's own
## [code]{ok, error}[/code] result; on success the SCENE HAS CHANGED, so a caller must do
## nothing afterwards but tear its own overlay down.
##
## [param playback] is an injected stand-in (anything with
## [code]launch(Dictionary) -> Dictionary[/code]) -- which is how a screen test proves the
## error paths without a real scene change. With none injected the launcher is loaded by
## PATH; a build that does not ship it answers "unavailable" rather than crashing.
static func launch(playback, log: Dictionary) -> Dictionary:
	if log.is_empty():
		return {"ok": false, "error": "empty"}
	if playback != null and playback.has_method("launch"):
		var injected: Variant = playback.launch(log)
		return injected if injected is Dictionary else {"ok": false, "error": ""}
	if not ResourceLoader.exists(PLAYBACK_SCRIPT):
		return {"ok": false, "error": "unavailable"}
	var script: Object = load(PLAYBACK_SCRIPT)
	if not _script_has_method(script, "launch"):
		return {"ok": false, "error": "unavailable"}
	var out: Variant = script.call("launch", log)
	return out if out is Dictionary else {"ok": false, "error": ""}


## Does [param script] (a GDScript object, not an instance) define [param method]?
## Walks the script's own method list rather than calling [method Object.has_method], which
## does not answer for STATIC functions on every engine build -- and a wrong answer here
## would be a hard crash on a build where the replay workstream's API has not landed.
static func _script_has_method(script: Object, method: String) -> bool:
	if script == null or not script.has_method("get_script_method_list"):
		return false
	for entry in script.get_script_method_list():
		if entry is Dictionary and String((entry as Dictionary).get("name", "")) == method:
			return true
	return false
