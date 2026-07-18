extends SceneTree

## Headless content generator: builds every sample move and character in code via
## [SampleRoster] and serializes them to .tres files a human can inspect and edit.
##
## Run it (from the project root) with:
##   godot --headless --script res://game/characters/build_sample_content.gd
##
## Outputs:
##   res://game/combat/moves/<move_id>.tres        (one per pooled move)
##   res://game/characters/roster/<character_id>.tres  (one per character)
##
## Re-running overwrites the generated files, so this is a safe, repeatable
## "content generation" entry point. It does not touch any hand-authored content.

const MOVES_DIR: String = "res://game/combat/moves"
const ROSTER_DIR: String = "res://game/characters/roster"


func _initialize() -> void:
	var moves_saved := _save_moves()
	var characters_saved := _save_characters()
	print("[build_sample_content] saved %d moves to %s" % [moves_saved, MOVES_DIR])
	print("[build_sample_content] saved %d characters to %s" % [characters_saved, ROSTER_DIR])
	quit()


func _save_moves() -> int:
	_ensure_dir(MOVES_DIR)
	var count := 0
	for move in SampleRoster.build_move_pool():
		var path := "%s/%s.tres" % [MOVES_DIR, String(move.move_id)]
		var err := ResourceSaver.save(move, path)
		if err != OK:
			push_error("Failed to save move '%s' (error %d)" % [String(move.move_id), err])
			continue
		count += 1
	return count


func _save_characters() -> int:
	_ensure_dir(ROSTER_DIR)
	var count := 0
	for character in SampleRoster.build_roster():
		var path := "%s/%s.tres" % [ROSTER_DIR, String(character.character_id)]
		var err := ResourceSaver.save(character, path)
		if err != OK:
			push_error("Failed to save character '%s' (error %d)" % [String(character.character_id), err])
			continue
		count += 1
	return count


## Create [param path] (and any missing parents) if it does not already exist.
func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("Could not create directory '%s' (error %d)" % [path, err])
