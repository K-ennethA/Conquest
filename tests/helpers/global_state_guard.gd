extends RefCounted

## Snapshot-and-restore for the GLOBAL state a test is allowed to touch.
##
## THE PROBLEM IT SOLVES: several suites need real global state -- an autoload field
## ([code]GameSettings.selected_map_path[/code], [code]animations_enabled[/code]), a real
## save file ([code]user://challenges/results.json[/code]), or a real library directory
## ([code]user://maps/[/code]). Hand-rolled snapshot/restore code was duplicated per suite
## and, worse, several suites restored INSIDE the test body -- so the moment an assertion
## failed early, the mutation leaked into every later suite in the run and into the
## player's real save.
##
## THE CONTRACT: build the guard in [code]before_each[/code], declare what you touch, and
## call [method restore] from [code]after_each[/code] -- GUT runs [code]after_each[/code]
## even when a test FAILS, so the restore happens on the failure path too.
##
## [codeblock]
## const Guard := preload("res://tests/helpers/global_state_guard.gd")
##
## var _guard
##
## func before_each() -> void:
##     _guard = Guard.new()
##     _guard.watch_setting("selected_map_path")
##     _guard.watch_dir(MapLoader.CUSTOM_MAPS_DIR)
##
## func after_each() -> void:
##     _guard.restore()
## [/codeblock]
##
## WHAT IT CANNOT DO: if the process is KILLED mid-test (or the engine crashes),
## [code]after_each[/code] never runs and the mutation survives. That is why the real fix
## for save-file suites is a PATH INJECTION API on the runtime class
## (see [method ItemInventory.set_save_path] / [method PlayerProfile.set_source_paths] /
## [method ChallengeController.set_results_path] / [method ChallengeCodec.set_challenge_dir] /
## [method CommunityClient.set_maps_dir]) and a [code]user://test_*[/code] temp path -- the
## guard is the fallback for the few paths still without one
## ([constant MapLoader.CUSTOM_MAPS_DIR], [constant CommunityClient.CONFIG_PATH]).
## See tests/README.md ("Temp paths").
##
## NEVER call a GameSettings setter that PERSISTS ([method GameSettings.set_animations_enabled]
## writes user://settings.cfg). Assign the field directly; that is what [method set_setting]
## does, and it is what keeps a test out of the player's settings file.

## property name -> value captured at watch time.
var _settings: Dictionary = {}
## absolute path -> { "existed": bool, "text": String }
var _files: Dictionary = {}
## absolute directory path -> PackedStringArray of file names present at watch time.
var _dirs: Dictionary = {}


# --- Autoload fields ---------------------------------------------------------

## Remember [param property] on the GameSettings autoload so [method restore] puts it back.
## Watching the same property twice keeps the FIRST (true original) value.
func watch_setting(property: String) -> void:
	if _settings.has(property):
		return
	if GameSettings == null:
		return
	_settings[property] = GameSettings.get(property)


## Watch [param property] and set it to [param value] in one step, bypassing any setter
## that would persist to disk.
func set_setting(property: String, value: Variant) -> void:
	watch_setting(property)
	if GameSettings != null:
		GameSettings.set(property, value)


# --- Files -------------------------------------------------------------------

## Remember whether [param path] exists and, if so, its exact contents. [method restore]
## rewrites it byte-for-byte, or deletes it again when it did not exist before.
func watch_file(path: String) -> void:
	if _files.has(path):
		return
	var record: Dictionary = {"existed": false, "text": ""}
	if FileAccess.file_exists(path):
		record["existed"] = true
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file != null:
			record["text"] = file.get_as_text()
			file.close()
	_files[path] = record


# --- Directories -------------------------------------------------------------

## Remember the file names directly inside [param path]. [method restore] deletes anything
## the test ADDED and never touches anything that was already there -- which is what makes
## this safe against a shared, non-injectable library directory such as
## [code]user://maps/[/code].
##
## It cannot restore a file the test OVERWROTE or DELETED; if your test does either, watch
## that file explicitly with [method watch_file] as well.
func watch_dir(path: String) -> void:
	if _dirs.has(path):
		return
	_dirs[path] = list_dir(path)


# --- Restore -----------------------------------------------------------------

## Put every watched thing back and forget it. Safe to call twice.
func restore() -> void:
	for property in _settings:
		if GameSettings != null:
			GameSettings.set(property, _settings[property])
	_settings.clear()

	for path in _files:
		var record: Dictionary = _files[path]
		if bool(record.get("existed", false)):
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_string(String(record.get("text", "")))
				file.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_files.clear()

	for path in _dirs:
		var before: PackedStringArray = _dirs[path]
		for file_name in list_dir(path):
			if not before.has(file_name):
				DirAccess.remove_absolute(_joined(path, file_name))
	_dirs.clear()


# --- Static utilities --------------------------------------------------------

## Sorted names of the files directly inside [param path]; empty when it does not exist.
static func list_dir(path: String) -> PackedStringArray:
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


## Recursively delete [param path] and everything under it. For throwaway
## [code]user://test_*[/code] roots ONLY -- never point this at a real library directory.
static func rm_rf(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var child: String = _joined(path, file_name)
		if dir.current_is_dir():
			rm_rf(child + "/")
		else:
			DirAccess.remove_absolute(child)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


static func _joined(dir_path: String, file_name: String) -> String:
	return dir_path + file_name if dir_path.ends_with("/") else dir_path + "/" + file_name
