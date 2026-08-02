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
##  - provider selection: no user://community.cfg -> LocalProvider; a cfg with a base_url
##    -> HttpProvider.
##
## Everything written during a test is removed again in after_each: the mock provider lives
## under a throwaway user:// root, and the (unavoidably fixed) library paths are restored to
## the exact file set they had before the test.

const TMP_ROOT := "user://test_community_client/"
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
	_maps_before = _list_dir(CommunityClient.MAPS_DIR)
	_challenges_before = _list_dir(ChallengeCodec.challenge_dir())


func after_each() -> void:
	# Remove anything a test added to the shared library dirs, then the mock root.
	_restore_dir(CommunityClient.MAPS_DIR, _maps_before)
	_restore_dir(ChallengeCodec.challenge_dir(), _challenges_before)
	_rm_rf(TMP_ROOT)
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
