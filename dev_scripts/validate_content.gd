extends SceneTree

## Headless content-validation gate for Conquest.
##
## Loads every authored [.tres] under the roster / moves / maps content
## directories and runs each resource's own validation entry point:
## [method CharacterResource.validate], [method MoveResource.is_valid], and
## [method MapResource.validate_map]. Prints a PASS/FAIL summary and exits with
## a nonzero status if anything is invalid or fails to load, so this can be run
## by hand or wired into CI as the "content" gate:
##
##   godot --headless -s dev_scripts/validate_content.gd
##
## Robust to bad data: a file that fails to load, or that doesn't resolve to
## the expected resource type, is reported as a failure rather than crashing
## the script -- one bad .tres should not stop the rest of the content from
## being checked.

const ROSTER_DIR: String = "res://game/characters/roster/"
const MOVES_DIR: String = "res://game/combat/moves/"
const MAPS_DIR: String = "res://game/maps/resources/"

var _checked_count: int = 0
var _failure_count: int = 0


## Entry point for `-s` headless execution. Runs all three content checks,
## prints a summary, and quits with exit code 1 if anything failed.
func _initialize() -> void:
	print("=== Conquest Content Validation ===")

	_validate_directory(ROSTER_DIR, "CharacterResource", Callable(self, "_validate_character"))
	_validate_directory(MOVES_DIR, "MoveResource", Callable(self, "_validate_move"))
	_validate_directory(MAPS_DIR, "MapResource", Callable(self, "_validate_map"))

	print("")
	if _failure_count == 0:
		print("PASS: %d resource(s) checked, 0 failures." % _checked_count)
		quit(0)
	else:
		print("FAIL: %d/%d resource(s) failed validation." % [_failure_count, _checked_count])
		quit(1)


## Enumerates every top-level `.tres` in [param dir_path] and runs
## [param validator] (a `Callable(Resource) -> Array[String]` of problem
## descriptions, empty on success) against each one that loads successfully.
## Load failures and type mismatches are reported as failures directly.
func _validate_directory(dir_path: String, kind_label: String, validator: Callable) -> void:
	print("\n--- %s (%s) ---" % [kind_label, dir_path])

	var file_names := _list_tres_files(dir_path)
	if file_names.is_empty():
		print("  (no .tres files found)")
		return

	for file_name in file_names:
		var path := dir_path + file_name
		_checked_count += 1

		if not ResourceLoader.exists(path):
			_fail(path, "not recognized by ResourceLoader (missing or unsupported)")
			continue

		var resource: Resource = load(path)
		if resource == null:
			_fail(path, "failed to load (load() returned null)")
			continue

		var errors: Array = validator.call(resource)
		if errors.is_empty():
			print("  OK   %s" % file_name)
		else:
			for err in errors:
				_fail(path, String(err))


## Runs [method CharacterResource.validate] on [param resource]. Returns a
## list of human-readable problems (empty means valid).
func _validate_character(resource: Resource) -> Array[String]:
	var errors: Array[String] = []
	var char_res := resource as CharacterResource
	if char_res == null:
		errors.append("expected CharacterResource, got %s" % resource.get_class())
		return errors

	var result: Dictionary = char_res.validate()
	if not bool(result.get("valid", false)):
		for issue in result.get("issues", []):
			errors.append(String(issue))
	return errors


## Runs [method MoveResource.is_valid] on [param resource]. [code]is_valid()[/code]
## only returns a bool, so on failure this also inspects [member MoveResource.targeting]
## and [member MoveResource.effects] directly to give an actionable reason.
func _validate_move(resource: Resource) -> Array[String]:
	var errors: Array[String] = []
	var move_res := resource as MoveResource
	if move_res == null:
		errors.append("expected MoveResource, got %s" % resource.get_class())
		return errors

	if not move_res.is_valid():
		if move_res.targeting == null:
			errors.append("targeting is null")
		if move_res.effects.is_empty():
			errors.append("effects array is empty")
		if errors.is_empty():
			errors.append("is_valid() returned false")
	return errors


## Runs [method MapResource.validate_map] on [param resource]. Returns a
## list of human-readable problems (empty means valid).
func _validate_map(resource: Resource) -> Array[String]:
	var errors: Array[String] = []
	var map_res := resource as MapResource
	if map_res == null:
		errors.append("expected MapResource, got %s" % resource.get_class())
		return errors

	var result: Dictionary = map_res.validate_map()
	if not bool(result.get("valid", false)):
		for issue in result.get("issues", []):
			errors.append(String(issue))
	return errors


## Records a failed check and prints it immediately so output stays readable
## even if a later step in the run were to abort.
func _fail(path: String, reason: String) -> void:
	_failure_count += 1
	print("  FAIL %s -- %s" % [path, reason])


## Returns the `.tres` file names (not full paths) directly inside
## [param dir_path], sorted for stable output. Returns an empty array
## (never crashes) if the directory can't be opened, e.g. a moved or
## renamed content folder.
func _list_tres_files(dir_path: String) -> PackedStringArray:
	var names := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("validate_content: could not open directory '%s' (error %s)" % [dir_path, DirAccess.get_open_error()])
		return names

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	names.sort()
	return names
