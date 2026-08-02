class_name CommunityProvider
extends RefCounted

## Abstract transport for the community service (browse / vote / download / upload of
## player-authored maps + challenges). Every call is ASYNC via a result [Callable]: the
## provider invokes [param cb] exactly once with a result dictionary
## [code]{ "ok": bool, "data": Variant }[/code] on success or
## [code]{ "ok": false, "error": String }[/code] on failure. Callers never block.
##
## Two concrete providers implement this:
##   * [LocalProvider] -- an offline sandbox backed by user:// files (calls back
##     synchronously; makes the whole UI + tests work with zero network).
##   * [HttpProvider]  -- the real client, HTTPRequest against a configured base_url.
##
## The contract these implement is documented in docs/COMMUNITY_API.md.

# --- Vocabulary (shared by providers, client and UI) ------------------------
const SORT_TOP := "top"
const SORT_NEW := "new"
const SORT_DAILY := "daily"

const TYPE_MAP := "map"
const TYPE_CHALLENGE := "challenge"
const TYPE_ALL := "all"

## Summaries returned per list page. Small so a page stays light.
const PAGE_SIZE := 20

## Where the anonymous per-device identity is stored (see docs: soft identity for
## vote de-duplication only).
const DEVICE_PATH := "user://community_device.txt"


# --- Result helpers ---------------------------------------------------------

## Wrap a successful payload in the uniform result shape.
static func ok(data: Variant) -> Dictionary:
	return {"ok": true, "data": data}


## Wrap a failure reason in the uniform result shape.
static func fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}


## Invoke a result callback if it is still valid (guards freed listeners).
static func _emit(cb: Callable, result: Dictionary) -> void:
	if cb.is_valid():
		cb.call(result)


# --- Device identity --------------------------------------------------------

## The anonymous device UUID, generated once and cached on disk. Used as the client
## identity for idempotent voting. Real accounts come with the live service.
static func device_id() -> String:
	if FileAccess.file_exists(DEVICE_PATH):
		var f: FileAccess = FileAccess.open(DEVICE_PATH, FileAccess.READ)
		if f != null:
			var existing: String = f.get_as_text().strip_edges()
			f.close()
			if not existing.is_empty():
				return existing
	var generated: String = _new_uuid()
	var out: FileAccess = FileAccess.open(DEVICE_PATH, FileAccess.WRITE)
	if out != null:
		out.store_string(generated)
		out.close()
	return generated


## RFC-4122-ish v4 UUID from the engine RNG. Good enough for a soft, non-secret id.
static func _new_uuid() -> String:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16)
	for i in 16:
		bytes[i] = randi() % 256
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12)]


# --- API surface (override in subclasses) -----------------------------------

## List item summaries for a sort + type + 0-based page. data = Array[Dictionary].
func list_items(_sort: String, _type: String, _page: int, cb: Callable) -> void:
	_emit(cb, fail("list_items not implemented"))


## Fetch one item's FULL payload (the map or challenge JSON). data = Dictionary.
func fetch_item(_id: String, cb: Callable) -> void:
	_emit(cb, fail("fetch_item not implemented"))


## Upload a payload. data = the created summary Dictionary.
func upload(_payload: Dictionary, cb: Callable) -> void:
	_emit(cb, fail("upload not implemented"))


## Cast/clear this device's vote (dir in {1, -1, 0}). data = { id, votes } (new score).
func vote(_id: String, _dir: int, cb: Callable) -> void:
	_emit(cb, fail("vote not implemented"))


## The daily featured pick. data = { id }.
func daily(cb: Callable) -> void:
	_emit(cb, fail("daily not implemented"))
