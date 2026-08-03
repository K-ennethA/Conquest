extends GutTest

## Unit tests for [CommunityClient] -- the guarded front door between the community
## service and the local library.
##
## The load-bearing property under test: a downloaded payload is UNTRUSTED, and the ONLY
## way it reaches disk is through the two hardened importers ([method ChallengeCodec.validate]
## + [method ChallengeCodec.save_to_file], and catalog-strict [method MapResource.import_from_json]
## then a re-export of the VALIDATED resource as inert JSON). A payload that fails validation
## must be rejected AND leave nothing behind.
##
## Coverage:
##  - a tampered CHALLENGE payload is rejected and writes NOTHING to user://challenges/;
##  - a tampered MAP payload (unknown tile id) is rejected and writes NOTHING to user://maps/;
##  - a mislabelled payload cannot smuggle a bad map in under the "challenge" label;
##  - the end-to-end download_to_library path (through a temp-root LocalProvider) rejects
##    a tampered payload the mock is serving;
##  - a VALID map/challenge does install, and a re-download is idempotent ("already_owned");
##  - an installed challenge is STAMPED with the service's item id as "community_id" (the
##    handle the challenge-completion flow reports attempts against) without disturbing the
##    checksum;
##  - provider selection: no user://community.cfg -> LocalProvider; a cfg with a base_url
##    -> HttpProvider.
##
## Everything written during a test is removed again in after_each: the mock provider lives
## under a throwaway user:// root, and the (unavoidably fixed) library paths are restored to
## the exact file set they had before the test.

## A provider that only RECORDS what the client handed it. The forwarding signatures are
## load-bearing across agents -- screens call `list_items(..., cb, query)` and the challenge
## completion flow calls `report_attempt(id, outcome, cb)` -- so a test pins them here rather
## than leaving them to be discovered by a broken build.
class RecordingProvider extends CommunityProvider:
	## One entry per forwarded call: { "call": String, ... the arguments }.
	var calls: Array = []

	func list_items(sort: String, type: String, page: int, cb: Callable, query: String = "") -> void:
		calls.append({"call": "list_items", "sort": sort, "type": type, "page": page, "query": query})
		_emit(cb, ok([]))

	func report_attempt(id: String, outcome: Dictionary, cb: Callable) -> void:
		calls.append({"call": "report_attempt", "id": id, "outcome": outcome.duplicate(true)})
		_emit(cb, ok({"id": id, "attempts": 1, "clears": 0, "outcome": outcome}))

	func my_bases(cb: Callable) -> void:
		calls.append({"call": "my_bases"})
		_emit(cb, ok([]))

	func set_base_active(id: String, active: bool, cb: Callable) -> void:
		calls.append({"call": "set_base_active", "id": id, "active": active})
		_emit(cb, ok({"id": id, "active": active}))


const TMP_ROOT := "user://test_community_client/"
## Own device identity: an upload stamps ownership from it, and a test must not write the
## player's real community_device.txt.
const TMP_DEVICE := "user://test_community_client_device.txt"
## Somewhere to park a real user://community.cfg while the selection tests own that path.
const CFG_BACKUP := "user://community.cfg.testbak"
## The base_url the selection tests write. Unroutable on purpose (no request is ever made --
## only provider CHOICE is asserted) and used as the marker that identifies a config this
## suite left behind if a previous run was killed mid-test.
const TEST_BASE_URL := "https://community-test.invalid"

## Snapshots of the library directories taken in before_each, so a test can prove it wrote
## nothing (or clean up exactly what it did write).
var _maps_before: PackedStringArray = PackedStringArray()
var _challenges_before: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_recover_stale_config()
	CommunityProvider.set_device_path(TMP_DEVICE)
	_maps_before = _list_dir(CommunityClient.MAPS_DIR)
	_challenges_before = _list_dir(ChallengeCodec.challenge_dir())


func after_each() -> void:
	# Remove anything a test added to the shared library dirs, then the mock root.
	_restore_dir(CommunityClient.MAPS_DIR, _maps_before)
	_restore_dir(ChallengeCodec.challenge_dir(), _challenges_before)
	_rm_rf(TMP_ROOT)
	CommunityProvider.set_device_path("")
	if FileAccess.file_exists(TMP_DEVICE):
		DirAccess.remove_absolute(TMP_DEVICE)
	_restore_config()


# --- Fixtures ---------------------------------------------------------------

## A real roster character id: the strict validator resolves ids against CharacterLibrary,
## so fixtures must name a genuine one to be valid in the first place.
func _a_character_id() -> String:
	var ids: Array = CharacterLibrary.all_ids()
	assert_gt(ids.size(), 0, "roster must have at least one character for these tests")
	return String(ids[0]) if ids.size() > 0 else ""


## A map that PASSES the catalog-strict validator: default layout (empty tile_ids resolve
## through the legacy path), two players, in-bounds spawns.
func _make_map(map_name: String) -> MapResource:
	var res := MapResource.new()
	res.map_name = map_name
	res.author = "Community Client Test"
	res.width = 5
	res.height = 5
	res.max_players = 2
	res.create_default_layout()
	var cid: String = _a_character_id()
	res.set_character_spawn_at_position(Vector2i(0, 0), 0, cid)
	res.set_character_spawn_at_position(Vector2i(4, 4), 1, cid)
	return res


## The canonical JSON dict a map payload rides as on the wire.
func _map_payload(map_name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_make_map(map_name).export_to_json())
	return parsed if parsed is Dictionary else {}


## A valid challenge payload (checksum stamped by build_challenge).
func _challenge_payload(challenge_name: String) -> Dictionary:
	return ChallengeCodec.build_challenge(_make_map(challenge_name), challenge_name,
		"Community Client Test", "2026-07-30T18:00:00",
		{"challenger_squad_size": 4, "turn_system": 0, "ai_difficulty": 1})


## A client wired to a mock provider under the throwaway root (no network, sync callbacks).
func _client() -> CommunityClient:
	return CommunityClient.new(LocalProvider.new(TMP_ROOT))


# --- Tamper rejection -------------------------------------------------------

func test_tampered_challenge_is_rejected_and_writes_nothing() -> void:
	var payload: Dictionary = _challenge_payload("Community Tamper Challenge")
	assert_false(payload.is_empty(), "fixture challenge should build")
	# Edit the content AFTER the checksum was stamped -- exactly what a hand-edited or
	# man-in-the-middle payload looks like.
	payload["name"] = "Community Tamper Challenge (edited)"

	var result: Dictionary = _client().install_payload(CommunityProvider.TYPE_CHALLENGE, payload)
	assert_false(bool(result.get("ok", true)), "a tampered challenge must be rejected")
	assert_true(String(result.get("error", "")).length() > 0, "rejection must carry a reason")
	assert_eq(_list_dir(ChallengeCodec.challenge_dir()), _challenges_before,
		"a rejected challenge must write NOTHING to the challenge library")


func test_tampered_map_is_rejected_and_writes_nothing() -> void:
	var payload: Dictionary = _map_payload("Community Tamper Map")
	assert_false(payload.is_empty(), "fixture map should export")
	# Name a tile this install does not have: catalog-strict import must refuse it.
	var layout: Dictionary = payload.get("layout", {})
	var tiles: Array = layout.get("tiles", [])
	assert_gt(tiles.size(), 0, "the fixture map should have tiles to tamper with")
	(tiles[0] as Dictionary)["tile_id"] = "not_a_real_tile_id_xyz"

	var result: Dictionary = _client().install_payload(CommunityProvider.TYPE_MAP, payload)
	assert_false(bool(result.get("ok", true)), "a map naming an unknown tile must be rejected")
	assert_eq(_list_dir(CommunityClient.MAPS_DIR), _maps_before,
		"a rejected map must write NOTHING to the map library")


func test_out_of_bounds_map_is_rejected() -> void:
	var payload: Dictionary = _map_payload("Community Oob Map")
	# Shrink the declared size so every existing cell falls outside it.
	payload["dimensions"] = {"width": 3, "height": 3}

	var result: Dictionary = _client().install_payload(CommunityProvider.TYPE_MAP, payload)
	assert_false(bool(result.get("ok", true)), "out-of-bounds cells must be rejected")
	assert_eq(_list_dir(CommunityClient.MAPS_DIR), _maps_before, "nothing should be written")


func test_mislabelled_payload_cannot_smuggle_a_bad_map() -> void:
	# Label a tampered MAP as a challenge: the challenge importer must still refuse it
	# (the label never decides whether the content is safe -- validation does).
	var payload: Dictionary = _map_payload("Community Mislabelled Map")
	var tiles: Array = (payload.get("layout", {}) as Dictionary).get("tiles", [])
	if tiles.size() > 0:
		(tiles[0] as Dictionary)["tile_id"] = "not_a_real_tile_id_xyz"

	var result: Dictionary = _client().install_payload(CommunityProvider.TYPE_CHALLENGE, payload)
	assert_false(bool(result.get("ok", true)), "a map labelled 'challenge' must not install")
	assert_eq(_list_dir(ChallengeCodec.challenge_dir()), _challenges_before, "nothing written")
	assert_eq(_list_dir(CommunityClient.MAPS_DIR), _maps_before, "nothing written")


func test_download_to_library_rejects_a_tampered_payload_end_to_end() -> void:
	# Serve a tampered payload from the mock service, then take the full client path:
	# fetch -> validate -> (must not) save.
	var client: CommunityClient = _client()
	var payload: Dictionary = _challenge_payload("Community E2E Challenge")
	payload["author"] = "someone else"  # invalidates the stamped checksum

	var uploaded: Dictionary = _sync(func(cb: Callable): client.upload(payload, cb))
	assert_true(bool(uploaded.get("ok", false)), "the mock accepts any structural payload")
	var summary: Dictionary = uploaded.get("data", {})

	var result: Dictionary = _sync(func(cb: Callable): client.download_to_library(summary, cb))
	assert_false(bool(result.get("ok", true)), "download must reject the tampered payload")
	assert_eq(_list_dir(ChallengeCodec.challenge_dir()), _challenges_before,
		"a rejected download must leave the library untouched")


# --- Happy path -------------------------------------------------------------

func test_valid_map_installs_and_redownload_is_idempotent() -> void:
	var client: CommunityClient = _client()
	var payload: Dictionary = _map_payload("Community Client Fixture Map")

	var first: Dictionary = client.install_payload(CommunityProvider.TYPE_MAP, payload)
	assert_true(bool(first.get("ok", false)), "a valid map should install: %s" % String(first.get("error", "")))
	var data: Dictionary = first.get("data", {})
	var path: String = String(data.get("path", ""))
	assert_eq(String(data.get("status", "")), "downloaded", "first install is a download")
	assert_true(FileAccess.file_exists(path), "the map file should exist on disk")
	# A downloaded map MUST land as inert JSON in the Map Creator's own directory: that is
	# both the no-ResourceLoader-on-shared-content rule AND what makes it discoverable --
	# MapLoader.get_available_map_entries only scans user://maps/*.json.
	assert_true(path.ends_with(".json"), "a downloaded map must be inert JSON, never a .tres")
	assert_not_null(MapResource.import_from_json(FileAccess.get_file_as_string(path), true),
		"the written file must re-import through the strict validator")

	var second: Dictionary = client.install_payload(CommunityProvider.TYPE_MAP, payload)
	assert_true(bool(second.get("ok", false)), "a re-install should still succeed")
	assert_eq(String(second.get("data", {}).get("status", "")), "already_owned",
		"a re-download must not duplicate the file")


func test_valid_challenge_installs_and_redownload_is_idempotent() -> void:
	var client: CommunityClient = _client()
	var payload: Dictionary = _challenge_payload("Community Client Fixture Challenge")

	var first: Dictionary = client.install_payload(CommunityProvider.TYPE_CHALLENGE, payload)
	assert_true(bool(first.get("ok", false)), "a valid challenge should install: %s" % String(first.get("error", "")))
	assert_eq(String(first.get("data", {}).get("status", "")), "downloaded", "first install is a download")
	assert_true(FileAccess.file_exists(String(first.get("data", {}).get("path", ""))),
		"the challenge json should exist on disk")

	var second: Dictionary = client.install_payload(CommunityProvider.TYPE_CHALLENGE, payload)
	assert_true(bool(second.get("ok", false)), "a re-install should still succeed")
	assert_eq(String(second.get("data", {}).get("status", "")), "already_owned",
		"a re-download must resolve to the challenge already owned")


# --- Community id stamping --------------------------------------------------

func test_installed_challenge_is_stamped_with_the_community_id() -> void:
	var client: CommunityClient = _client()
	var payload: Dictionary = _challenge_payload("Community Stamp Challenge")

	var result: Dictionary = client.install_payload(CommunityProvider.TYPE_CHALLENGE, payload, "challenge_abc123")
	assert_true(bool(result.get("ok", false)), "a valid challenge should install: %s" % String(result.get("error", "")))
	var path: String = String(result.get("data", {}).get("path", ""))

	var saved: Dictionary = ChallengeCodec.load_from_file(path)
	# The field name is load-bearing: the challenge-completion flow reads exactly this key
	# and hands it to CommunityClient.report_attempt.
	assert_eq(String(saved.get("community_id", "")), "challenge_abc123",
		"the installed challenge carries the service's item id as 'community_id'")
	assert_eq(ChallengeCodec.validate(saved).size(), 0,
		"stamping must not disturb the checksum -- the saved file still validates")
	assert_false(payload.has("community_id"),
		"the caller's payload dict is not mutated; the stamp goes on the saved copy")


func test_install_without_a_community_id_stamps_nothing() -> void:
	var client: CommunityClient = _client()
	var result: Dictionary = client.install_payload(CommunityProvider.TYPE_CHALLENGE,
		_challenge_payload("Community Unstamped Challenge"))
	assert_true(bool(result.get("ok", false)), "the challenge should still install")
	var saved: Dictionary = ChallengeCodec.load_from_file(String(result.get("data", {}).get("path", "")))
	assert_false(saved.has("community_id"),
		"a locally installed challenge has no service id, so the key is absent entirely")


func test_download_to_library_stamps_the_items_id_end_to_end() -> void:
	var client: CommunityClient = _client()
	var payload: Dictionary = _challenge_payload("Community Download Stamp")

	var uploaded: Dictionary = _sync(func(cb: Callable): client.upload(payload, cb))
	assert_true(bool(uploaded.get("ok", false)), "the mock should accept the upload")
	var summary: Dictionary = uploaded.get("data", {})
	var item_id: String = String(summary.get("id", ""))
	assert_false(item_id.is_empty(), "the mock should mint an item id")

	var result: Dictionary = _sync(func(cb: Callable): client.download_to_library(summary, cb))
	assert_true(bool(result.get("ok", false)), "the download should install: %s" % String(result.get("error", "")))
	var saved: Dictionary = ChallengeCodec.load_from_file(String(result.get("data", {}).get("path", "")))
	assert_eq(String(saved.get("community_id", "")), item_id,
		"a downloaded challenge is stamped with the id it was downloaded under")


func test_redownload_backfills_a_missing_community_id() -> void:
	var client: CommunityClient = _client()
	var payload: Dictionary = _challenge_payload("Community Backfill Challenge")

	# First install: no service id known (e.g. the challenge was imported from a share code).
	var first: Dictionary = client.install_payload(CommunityProvider.TYPE_CHALLENGE, payload)
	assert_true(bool(first.get("ok", false)), "the first install should succeed")

	# Same content, now downloaded from the service: already owned, but the id is new
	# information and the file would otherwise never report attempts.
	var second: Dictionary = client.install_payload(CommunityProvider.TYPE_CHALLENGE, payload, "challenge_backfilled")
	assert_eq(String(second.get("data", {}).get("status", "")), "already_owned",
		"the same content is not installed twice")
	assert_eq(String(second.get("data", {}).get("path", "")), String(first.get("data", {}).get("path", "")),
		"and it stays the same file")
	var saved: Dictionary = ChallengeCodec.load_from_file(String(second.get("data", {}).get("path", "")))
	assert_eq(String(saved.get("community_id", "")), "challenge_backfilled",
		"the id is backfilled onto the copy already on disk")


func test_report_attempt_without_an_id_fails_without_touching_the_service() -> void:
	# A locally authored challenge has no community_id: the completion flow calls this
	# anyway, and it must be an ordinary refusal, not an error the player sees.
	var result: Dictionary = _sync(func(cb: Callable): _client().report_attempt("   ", {"cleared": true}, cb))
	assert_false(bool(result.get("ok", true)), "there is no ledger to write to")
	assert_eq(String(result.get("error", "")), CommunityProvider.ERR_NOT_FOUND, "and it says so in the shared vocabulary")


# --- Forwarding -------------------------------------------------------------

func test_client_forwards_the_whole_api_to_its_provider() -> void:
	var provider := RecordingProvider.new()
	var client := CommunityClient.new(provider)

	# The 5-argument list_items IS the browse screen's call. A 4-argument client would not
	# even compile against it, which is exactly the break this pins.
	_sync(func(cb: Callable): client.list_items(CommunityProvider.SORT_RECOMMENDED,
		CommunityProvider.TYPE_CHALLENGE, 2, cb, "  Frozen  "))
	_sync(func(cb: Callable): client.report_attempt("challenge_x", {"cleared": true, "score": 7, "turns": 3}, cb))
	_sync(func(cb: Callable): client.my_bases(cb))
	_sync(func(cb: Callable): client.set_base_active("challenge_x", false, cb))

	assert_eq(provider.calls.size(), 4, "every call reaches the provider exactly once")

	var listed: Dictionary = provider.calls[0]
	assert_eq(String(listed.get("sort", "")), CommunityProvider.SORT_RECOMMENDED)
	assert_eq(String(listed.get("type", "")), CommunityProvider.TYPE_CHALLENGE)
	assert_eq(int(listed.get("page", -1)), 2, "the page is forwarded unchanged")
	assert_eq(String(listed.get("query", "")), "  Frozen  ",
		"the raw needle is forwarded -- sanitising is the PROVIDER's boundary, not the client's")

	assert_eq(String(provider.calls[1].get("id", "")), "challenge_x")
	var forwarded: Dictionary = provider.calls[1].get("outcome", {})
	assert_true(bool(forwarded.get("cleared", false)), "the outcome reaches the provider intact...")
	assert_eq(int(forwarded.get("score", -1)), 7, "...score included...")
	assert_eq(int(forwarded.get("turns", -1)), 3, "...and turns, to be sanitised at that boundary")
	assert_eq(String(provider.calls[2].get("call", "")), "my_bases")
	assert_false(bool(provider.calls[3].get("active", true)), "the active flag is forwarded")


func test_report_attempt_with_a_real_id_reaches_the_provider() -> void:
	# The mirror of the blank-id refusal: a stamped id is NOT short-circuited.
	var provider := RecordingProvider.new()
	var result: Dictionary = _sync(func(cb: Callable):
		CommunityClient.new(provider).report_attempt("challenge_x", {"cleared": false}, cb))
	assert_true(bool(result.get("ok", false)), "a stamped id reports through to the service")
	assert_eq(provider.calls.size(), 1, "and it is the provider that answers")


func test_unrecognised_payload_is_rejected() -> void:
	var result: Dictionary = _client().install_payload("", {"hello": "world"})
	assert_false(bool(result.get("ok", true)), "an unrecognisable payload must be rejected")


# --- Provider selection -----------------------------------------------------

func test_provider_defaults_to_local_without_config() -> void:
	_stash_config()
	var client := CommunityClient.new()
	assert_true(client.is_local(), "with no community.cfg the client must run the offline sandbox")
	assert_true(client.provider() is LocalProvider, "the provider should be a LocalProvider")


func test_config_with_base_url_selects_http_provider() -> void:
	_stash_config()
	var cfg := ConfigFile.new()
	cfg.set_value("service", "base_url", TEST_BASE_URL)
	assert_eq(cfg.save(CommunityClient.CONFIG_PATH), OK, "the test config should write")

	var client := CommunityClient.new()
	assert_false(client.is_local(), "a configured base_url must leave local mode")
	assert_true(client.provider() is HttpProvider, "the provider should be an HttpProvider")


func test_config_without_base_url_falls_back_to_local() -> void:
	_stash_config()
	var cfg := ConfigFile.new()
	cfg.set_value("service", "base_url", "   ")
	assert_eq(cfg.save(CommunityClient.CONFIG_PATH), OK, "the test config should write")

	var client := CommunityClient.new()
	assert_true(client.is_local(), "a blank base_url is not a service -- stay offline")


# --- Helpers ----------------------------------------------------------------

## Run a provider/client call that calls back synchronously (LocalProvider does) and return
## its uniform result dictionary.
func _sync(callable_runner: Callable) -> Dictionary:
	var holder: Array = []
	callable_runner.call(func(r: Dictionary): holder.append(r))
	assert_gt(holder.size(), 0, "the mock provider must call back synchronously")
	return holder[0] if holder.size() > 0 else {}


## Sorted file names directly inside [param path] ("" when the directory does not exist),
## used to prove a rejected payload wrote nothing.
func _list_dir(path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			out.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## Delete anything in [param path] that was not in [param before] -- the shared library dirs
## are fixed constants, so a test cleans up exactly what it added and nothing else.
func _restore_dir(path: String, before: PackedStringArray) -> void:
	for file_name in _list_dir(path):
		if not before.has(file_name):
			DirAccess.remove_absolute(path + file_name)


## Self-heal from a run that was killed between _stash_config and _restore_config: a leftover
## test config would otherwise point the real game at an unroutable service. Only a config
## this suite recognises as its own is removed -- a genuine user config is never touched.
func _recover_stale_config() -> void:
	if FileAccess.file_exists(CommunityClient.CONFIG_PATH):
		var cfg := ConfigFile.new()
		if cfg.load(CommunityClient.CONFIG_PATH) == OK \
				and String(cfg.get_value("service", "base_url", "")) == TEST_BASE_URL:
			DirAccess.remove_absolute(CommunityClient.CONFIG_PATH)
	if FileAccess.file_exists(CFG_BACKUP) and not FileAccess.file_exists(CommunityClient.CONFIG_PATH):
		DirAccess.rename_absolute(CFG_BACKUP, CommunityClient.CONFIG_PATH)


func _stash_config() -> void:
	if FileAccess.file_exists(CommunityClient.CONFIG_PATH):
		DirAccess.rename_absolute(CommunityClient.CONFIG_PATH, CFG_BACKUP)


func _restore_config() -> void:
	if FileAccess.file_exists(CommunityClient.CONFIG_PATH):
		DirAccess.remove_absolute(CommunityClient.CONFIG_PATH)
	if FileAccess.file_exists(CFG_BACKUP):
		DirAccess.rename_absolute(CFG_BACKUP, CommunityClient.CONFIG_PATH)


func _rm_rf(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var child: String = path + file_name
		if dir.current_is_dir():
			_rm_rf(child + "/")
		else:
			DirAccess.remove_absolute(child)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
