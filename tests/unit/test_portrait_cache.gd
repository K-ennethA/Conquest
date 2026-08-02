extends GutTest

## Covers PortraitCache (game/ui/PortraitCache.gd) headless-safely -- see that file's class
## doc for the full design. GUT always runs --headless, so every scenario here resolves
## SYNCHRONOUSLY (disk-hit and the headless capture-gate both return before any `await`
## inside PortraitCache actually suspends) -- no wall-clock or frame waiting needed.

## A roster id that ships with a real model_scene (see game/characters/roster/vineweave.tres),
## used to prove the headless gate specifically -- CharacterLibrary resolves it, model_scene
## is non-null, so _capture() reaches (and is stopped by) the DisplayServer.get_name() ==
## "headless" check rather than bailing earlier on an unknown id.
const REAL_ID_WITH_MODEL: String = "vineweave"

## Synthetic ids that are never real roster entries, so their disk-cache reads/writes can
## never collide with anything a real play session captured.
const DISK_ROUNDTRIP_ID: String = "__test_portrait_cache_roundtrip__"
const VERSION_GUARD_ID: String = "__test_portrait_cache_version_guard__"


func before_each() -> void:
	# Full clean slate BOTH ways: reset() drops the MEMORY cache too - an earlier suite in
	# the same GUT process may have resolved one of these ids (e.g. a screen test touching
	# CharacterSelect), and a memory hit would satisfy get_portrait before the headless
	# gate runs, breaking the null expectation below.
	PortraitCache.reset()
	# The portrait disk cache is a pure, regenerable CACHE (not save data) -- deleting a
	# stale entry before/after a test is safe and loses nothing; it is the only way to give
	# this non-injectable, real user:// path (see tests/README.md rule 4) a clean slate.
	_delete_disk_file(REAL_ID_WITH_MODEL)
	_delete_disk_file(DISK_ROUNDTRIP_ID)
	_delete_disk_file(VERSION_GUARD_ID)


func after_each() -> void:
	# Drop the Node PortraitCache mounted under the scene tree so it never leaks into the
	# next suite (see tests/README.md on orphans / global state).
	PortraitCache.reset()
	_delete_disk_file(REAL_ID_WITH_MODEL)
	_delete_disk_file(DISK_ROUNDTRIP_ID)
	_delete_disk_file(VERSION_GUARD_ID)


# --- 1. Headless capture returns null cleanly --------------------------------

func test_get_portrait_returns_null_headless_without_engine_errors() -> void:
	var calls: Array = []
	PortraitCache.get_portrait(REAL_ID_WITH_MODEL, func(tex): calls.append(tex))

	assert_eq(calls.size(), 1, "the callback fires exactly once")
	assert_null(calls[0], "a headless run cannot render a capture, so the result is null")
	# No push_error/push_warning path exists in PortraitCache for this case (see its class
	# doc) -- GUT would already have failed this test on any engine error if there were one.


func test_get_cached_is_null_before_any_resolution() -> void:
	assert_null(PortraitCache.get_cached(REAL_ID_WITH_MODEL),
		"nothing has resolved this id yet, so get_cached must not fabricate a result")


func test_get_portrait_empty_id_calls_back_null() -> void:
	var calls: Array = []
	PortraitCache.get_portrait("", func(tex): calls.append(tex))
	assert_eq(calls.size(), 1, "an empty id still calls back exactly once")
	assert_null(calls[0], "an empty id can never resolve to a portrait")


# --- 2. Disk-cache round trip -------------------------------------------------

func test_disk_cache_round_trip_via_preseeded_image() -> void:
	var path: String = PortraitCache.disk_path(DISK_ROUNDTRIP_ID)
	_seed_png(path, Color(0.2, 0.6, 0.9, 1.0))

	var calls: Array = []
	PortraitCache.get_portrait(DISK_ROUNDTRIP_ID, func(tex): calls.append(tex))

	assert_eq(calls.size(), 1, "a disk hit resolves synchronously in one callback")
	assert_not_null(calls[0], "the pre-seeded PNG must be loaded, not treated as a miss")
	assert_true(calls[0] is Texture2D, "the resolved value is a usable Texture2D")

	# A second request for the same id must now be served from MEMORY (get_cached), with
	# no further disk touch needed.
	var cached: Texture2D = PortraitCache.get_cached(DISK_ROUNDTRIP_ID)
	assert_same(cached, calls[0], "the memory cache holds the exact texture the disk hit produced")


# --- 3. Version-name invalidation ---------------------------------------------

func test_stale_version_file_is_never_read() -> void:
	# Write a PNG at a WRONG-version path (never what disk_path() computes for the current
	# CACHE_VERSION) and confirm PortraitCache ignores it entirely.
	var real_path: String = PortraitCache.disk_path(VERSION_GUARD_ID)
	var stale_path: String = real_path.replace("v1_", "v0_")
	assert_ne(stale_path, real_path,
		"the fixture must actually target a different filename than the current version")
	_seed_png(stale_path, Color(0.9, 0.2, 0.2, 1.0))

	var calls: Array = []
	PortraitCache.get_portrait(VERSION_GUARD_ID, func(tex): calls.append(tex))

	assert_eq(calls.size(), 1, "the callback still fires exactly once")
	assert_null(calls[0],
		"a stale-version file must never be picked up -- headless + unknown id + no v1 file = null")

	_delete_absolute(stale_path)


# --- Helpers -------------------------------------------------------------------

func _seed_png(path: String, color: Color) -> void:
	var dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var err: int = img.save_png(path)
	assert_eq(err, OK, "test fixture must actually write %s" % path)


func _delete_disk_file(character_id: String) -> void:
	_delete_absolute(PortraitCache.disk_path(character_id))


func _delete_absolute(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
