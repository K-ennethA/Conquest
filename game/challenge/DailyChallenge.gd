extends RefCounted

class_name DailyChallenge

## The DAILY CHALLENGE picker + the built-in challenge pool it draws from. Serverless NOW,
## server-ready LATER:
##
##   * [method pick_for_date] is PURE and deterministic: given the same pool and the same
##     UTC date string it returns the same challenge on every install, with no wall-clock
##     read of its own (the caller passes the date in -- see [method today_utc]). That is
##     exactly the contract a future "daily challenge" server endpoint would honour, so the
##     UI can switch from local pool to server feed without changing how it picks.
##   * The pool is the BUILT-IN challenges shipped in res:// plus whatever local challenges
##     the player has built / imported. Built-ins are TRUSTED (authored by us, shipped as
##     inert JSON) so their checksum is stamped at load time by the codec, the same way a
##     freshly built challenge is finalised.

## Where the shipped, trusted challenge JSONs live.
const BUILTIN_DIR := "res://game/challenge/builtin/"

## Known built-in file names. Used to load the pool when the directory can't be scanned
## (exported PCK quirks can hide DirAccess listing), mirroring CharacterLibrary's fallback.
## Keep in sync with the files actually present in [constant BUILTIN_DIR].
const BUILTIN_FILES: Array[String] = [
	"grove_ambush.json",
	"throne_gauntlet.json",
	"last_stand.json",
]


## Today's date as a stable UTC day-string ("YYYY-MM-DD"), the key [method pick_for_date]
## expects. The ONLY wall-clock read in this file, and it is kept OUT of the pure picker so
## the picker stays testable. utc=true so every timezone rolls the daily over together.
static func today_utc() -> String:
	return Time.get_date_string_from_system(true)


## Deterministically choose one challenge from [param pool] for [param date_utc]. Same date +
## same pool -> same pick on every machine, and reordering the pool does NOT change the pick
## (the pool is stable-sorted by checksum first). Returns {} for an empty pool.
##
## Determinism rests on: (1) a checksum sort gives a canonical order regardless of how the
## caller assembled the pool; (2) String.hash() of the date is stable across runs/platforms;
## (3) modulo maps it into range. No RNG, no time read.
static func pick_for_date(pool: Array[Dictionary], date_utc: String) -> Dictionary:
	if pool.is_empty():
		return {}
	var ordered: Array[Dictionary] = _sorted_by_checksum(pool)
	var index: int = absi(date_utc.hash()) % ordered.size()
	return ordered[index]


## A copy of [param pool] sorted into ONE canonical order -- by challenge checksum ascending,
## breaking a tie on name -- so the picker sees the same sequence no matter how the caller
## assembled the pool. The name tiebreak matters because [method Array.sort_custom] is NOT a
## stable sort: with a bare checksum comparator, two entries that hashed alike could land in
## either order depending on the input order, and the day's pick would stop being reproducible.
static func _sorted_by_checksum(pool: Array[Dictionary]) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = pool.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var id_a: String = ChallengeCodec.challenge_id(a)
		var id_b: String = ChallengeCodec.challenge_id(b)
		if id_a == id_b:
			return String(a.get("name", "")) < String(b.get("name", ""))
		return id_a < id_b)
	return ordered


# --- Built-in pool ----------------------------------------------------------

## Every shipped built-in challenge, each finalised (checksum stamped) and validated. Invalid
## or unreadable files are skipped so one bad ship-file can't break the whole daily feature.
static func load_builtin_pool() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for file_name in _builtin_file_names():
		var challenge: Dictionary = load_builtin_file(BUILTIN_DIR + file_name)
		if challenge.is_empty():
			continue
		if ChallengeCodec.validate(challenge).is_empty():
			out.append(challenge)
	return out


## The full daily POOL: built-ins + the player's local challenges. Deduped by checksum (a
## local copy of a built-in doesn't double its odds). Used by the browse screen.
static func full_pool() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for challenge in load_builtin_pool():
		var id: String = ChallengeCodec.challenge_id(challenge)
		if not seen.has(id):
			seen[id] = true
			out.append(challenge)
	for entry in ChallengeCodec.list_saved():
		var challenge: Dictionary = entry.get("challenge", {})
		if challenge.is_empty():
			continue
		var id: String = ChallengeCodec.challenge_id(challenge)
		if not seen.has(id):
			seen[id] = true
			out.append(challenge)
	return out


## True when the pool is made up ONLY of built-ins (no local player challenges yet). The
## browse screen shows a "local pool only" note in that case.
static func pool_is_builtin_only() -> bool:
	return ChallengeCodec.list_saved().is_empty()


## Load ONE built-in JSON file and stamp its checksum. Built-ins are TRUSTED (we ship them),
## so recomputing the checksum is the correct finalise -- the file itself ships with an empty
## one and never needs a hand-computed hash. Returns {} on any read/parse failure.
##
## Public because [method load_builtin_pool] silently SKIPS a file that fails validation
## (one bad ship-file must not break the daily); tests go through this instead so they can
## report exactly which file failed and why.
static func load_builtin_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var challenge: Dictionary = parsed
	return ChallengeCodec.stamp_checksum(challenge)


## The built-in file names to load: the live directory listing when it is available, else the
## hard-coded [constant BUILTIN_FILES] fallback (exported builds may not list res:// dirs).
static func _builtin_file_names() -> Array[String]:
	var names: Array[String] = []
	var dir: DirAccess = DirAccess.open(BUILTIN_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json") and not file_name.begins_with("."):
				names.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	if names.is_empty():
		names = BUILTIN_FILES.duplicate()
	return names
