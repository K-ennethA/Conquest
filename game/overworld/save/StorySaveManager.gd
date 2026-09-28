class_name StorySaveManager
extends RefCounted

## The three story save SLOTS on disk: user://story/slot_<n>.json. A static store with an
## injectable directory ([method set_save_dir]) exactly like [ItemInventory] /
## [BattleSaveManager], so tests never touch the player's real journey (tests/README rule 4).
##
## Writes are atomic-ish (write a .tmp, then rename over the slot) so a crash mid-save cannot
## leave a half-written journey. A corrupt or unreadable file reads as an EMPTY slot rather
## than an error (CONQUEST.md rule 1).

const DEFAULT_SAVE_DIR := "user://story/"
const SLOT_COUNT: int = 3

static var _save_dir: String = DEFAULT_SAVE_DIR


static func set_save_dir(dir: String) -> void:
	_save_dir = dir if not dir.is_empty() else DEFAULT_SAVE_DIR
	if not _save_dir.ends_with("/"):
		_save_dir += "/"


static func save_dir() -> String:
	return _save_dir


static func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


static func slot_path(slot: int) -> String:
	return "%sslot_%d.json" % [_save_dir, slot]


static func has_save(slot: int) -> bool:
	return is_valid_slot(slot) and not peek(slot).is_empty()


## Serialize [param state] into [param slot]. Returns {success, reason}.
static func save(slot: int, state: StoryState) -> Dictionary:
	if not is_valid_slot(slot):
		return {"success": false, "reason": "invalid_slot"}
	if state == null:
		return {"success": false, "reason": "no_state"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_save_dir))
	var path: String = slot_path(slot)
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"success": false, "reason": "write_failed"}
	f.store_string(JSON.stringify(StorySnapshot.to_dict(state), "\t"))
	f.close()
	var abs_tmp: String = ProjectSettings.globalize_path(tmp)
	var abs_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_path)
	if DirAccess.rename_absolute(abs_tmp, abs_path) != OK:
		return {"success": false, "reason": "rename_failed"}
	return {"success": true, "reason": ""}


## The raw parsed dictionary in [param slot], or {} when empty / unreadable / not a story
## save. For captions (menus) -- use [method load_state] to play it.
static func peek(slot: int) -> Dictionary:
	if not is_valid_slot(slot):
		return {}
	var path: String = slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data = json.data
	if not (data is Dictionary) or int(data.get("format_version", 0)) <= 0:
		return {}
	return data


## Load [param slot] into a fresh [StoryState]. {success, state, reason}.
static func load_state(slot: int) -> Dictionary:
	var data: Dictionary = peek(slot)
	if data.is_empty():
		return {"success": false, "state": null, "reason": "empty_slot"}
	return StorySnapshot.from_dict(data)


static func delete(slot: int) -> void:
	if not is_valid_slot(slot):
		return
	var path: String = slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The slot whose save was written most recently, or 0 when none exists (the main menu's
## "Continue Journey" target). An outdated (pre-opening) journey cannot be continued and is
## skipped -- see [StorySnapshot].
static func most_recent_slot() -> int:
	var best: int = 0
	var best_stamp: String = ""
	for slot in range(1, SLOT_COUNT + 1):
		var data: Dictionary = peek(slot)
		if data.is_empty() or StorySnapshot.is_outdated(data):
			continue
		var stamp: String = String(data.get("saved_at_utc", ""))
		if best == 0 or stamp > best_stamp:
			best = slot
			best_stamp = stamp
	return best
