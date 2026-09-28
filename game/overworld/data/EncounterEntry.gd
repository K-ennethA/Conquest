class_name EncounterEntry
extends Resource

## One row of an [EncounterZone]'s table: who can leap out of the grass, how likely, and as
## what kind of battle.

enum Kind { DUEL, TACTICAL }

@export var character_id: StringName = &""
@export_range(0.0, 100.0) var weight: float = 1.0
@export var kind: Kind = Kind.DUEL
## Opaque strength (EVOLUTION decides: a level, or a stat scale where 1.0 = roster base).
@export var strength: float = 1.0
@export var condition: String = ""
## TACTICAL entries: the battle to fight.
@export var battle: BattleSpec
## May the wild unit offer to join after a win (DECISIONS.md: befriending is in scope).
@export var can_befriend: bool = true


## The runtime request for this wild encounter.
func to_request(area_id: String) -> BattleRequest:
	var r: BattleRequest
	if kind == Kind.TACTICAL and battle != null:
		r = battle.to_request(BattleRequest.SOURCE_WILD, "%s.grass.%s" % [area_id, character_id])
	else:
		r = BattleRequest.new()
		r.kind = BattleRequest.KIND_DUEL
		r.encounter_id = "%s.grass.%s" % [area_id, character_id]
		r.source = BattleRequest.SOURCE_WILD
		var c: CharacterResource = CharacterLibrary.get_character(character_id)
		r.opponent = {
			"name": "Wild " + (c.display_name if c != null else String(character_id).capitalize()),
			"speaker_id": String(character_id),
			"portrait": String(character_id),
			"team": [{"character_id": String(character_id), "strength": strength}],
		}
		r.rules = {"can_flee": true, "can_befriend": can_befriend,
			"defeat_policy": BattleRequest.DEFEAT_WHITEOUT, "story_critical": false}
		r.rewards = {"gold": 0, "items": [], "points": 0, "flags": []}
	return r


func _to_string() -> String:
	return "Encounter(%s x%.1f)" % [String(character_id), weight]
