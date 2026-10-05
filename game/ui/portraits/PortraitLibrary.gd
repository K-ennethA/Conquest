class_name PortraitLibrary
extends RefCounted

## AUTHORED portraits: the owner's character art (cropped from the reference sheets in
## docs/design/characters/ by tools/crop_portraits.gd) as `game/ui/portraits/<id>.png`.
## [PortraitCache] asks here FIRST, so a person with authored art shows it everywhere a
## portrait is drawn (story dialogue, party / compendium panels); everyone else falls back to
## the live 3D capture, then to the monogram badge.
##
## LOOKUP for a speaker / character id (e.g. "elias", "npc_elias", "hero"):
##   1. strip a leading "npc_" (story NPC speaker ids are "npc_<entity id>");
##   2. map through [code]aliases.json[/code] (an entity or speaker id whose art is filed under a
##      different name, e.g. the barracks NPC "general" -> "varden", the hero -> "wren");
##   3. a roster CharacterResource with its own [member CharacterResource.portrait] wins;
##   4. else the file `<DIR><id>.png`, when it exists.
## Returns null when there is no authored art (never an error: most ids have none).

const DIR := "res://game/ui/portraits/"
const ALIASES_PATH := DIR + "aliases.json"

static var _aliases: Dictionary = {}
static var _aliases_loaded: bool = false


## The authored portrait for [param id], or null.
static func authored(id) -> Texture2D:
	var key: String = resolve_id(id)
	if key.is_empty():
		return null
	# Only roster ids are asked (a person like "hessa" is not one; get_character would note a miss).
	if ResourceLoader.exists(CharacterLibrary.ROSTER_DIR + key + ".tres"):
		var c: CharacterResource = CharacterLibrary.get_character(StringName(key))
		if c != null and c.portrait != null:
			return c.portrait
	var path: String = DIR + key + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## [param id] with the "npc_" prefix stripped and the alias applied ("" for null / empty).
static func resolve_id(id) -> String:
	if id == null:
		return ""
	var key: String = String(id)
	if key.begins_with("npc_"):
		key = key.substr(4)
	if key.is_empty():
		return ""
	return String(_alias_table().get(key, key))


static func _alias_table() -> Dictionary:
	if _aliases_loaded:
		return _aliases
	_aliases_loaded = true
	if not FileAccess.file_exists(ALIASES_PATH):
		return _aliases
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ALIASES_PATH))
	if parsed is Dictionary:
		_aliases = parsed
	return _aliases
