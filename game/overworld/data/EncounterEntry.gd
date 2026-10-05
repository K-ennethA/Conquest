class_name EncounterEntry
extends Resource

## One row of an [EncounterZone]'s table: who lives here, how likely, as what kind of battle --
## and, in a VISIBLE zone, how the creature behaves on the map ([member behaviour]).

enum Kind { DUEL, TACTICAL }

## How a VISIBLE wild creature moves (one cell per player step, never in real time -- [WildSpawner]).
enum Behaviour {
	WANDER,      ## a random walk leashed to its zone
	TIMID,       ## steps away while the hero is within [member sense_range]; else wanders
	AGGRESSIVE,  ## trainer-style line of sight ([TrainerSight], [member sense_range]): "!" and approaches
	SLEEPING,    ## never moves; walking into it is always an ambush
	PATROL,      ## walks the [member patrol] waypoint loop
}

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

@export_group("Visible behaviour")
@export var behaviour: Behaviour = Behaviour.WANDER
## TIMID: flee radius (Manhattan). AGGRESSIVE: sight range along its facing.
@export_range(1, 8) var sense_range: int = 3
## WANDER / TIMID / AGGRESSIVE (when idle): the chance per player step that it moves at all.
@export_range(0.0, 1.0) var move_chance: float = 0.5
## PATROL: waypoint cells (x, y on floor 0), walked in order and looped. A patrol leaves its zone
## freely (the route is authored); fewer than two waypoints = wander.
@export var patrol: Array[Vector2i] = []


## The runtime request for this wild encounter. [param id_kind] names how it started ("grass" =
## a hidden roll, "wild" = a visible creature); [param opening] is the contact's
## [constant BattleRequest.OPENING_AMBUSH] / [constant BattleRequest.OPENING_AMBUSHED] /
## [constant BattleRequest.OPENING_NEUTRAL] ("" = none: a hidden roll). [param level]: the wild
## creature's STORY LEVEL, rolled from its zone's band ([method EncounterRoller.roll_level]); 0 = no
## level (roster base).
func to_request(area_id: String, id_kind: String = "grass", opening: String = "", level: int = 0) -> BattleRequest:
	var r: BattleRequest
	var eid: String = "%s.%s.%s" % [area_id, id_kind, character_id]
	if kind == Kind.TACTICAL and battle != null:
		r = battle.to_request(BattleRequest.SOURCE_WILD, eid)
		if level > 0:
			r.enemy_level = level
	else:
		r = BattleRequest.new()
		r.kind = BattleRequest.KIND_DUEL
		r.encounter_id = eid
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
		if level > 0:
			r.enemy_level = level
			(r.opponent["team"][0] as Dictionary)["level"] = level
	if BattleRequest.OPENINGS.has(opening):
		r.rules[BattleRequest.RULE_OPENING] = opening
	return r


## Does this row walk a patrol route (two or more waypoints)?
func patrols() -> bool:
	return behaviour == Behaviour.PATROL and patrol.size() >= 2


static func behaviour_name(b: int) -> String:
	match b:
		Behaviour.TIMID:
			return "timid"
		Behaviour.AGGRESSIVE:
			return "aggressive"
		Behaviour.SLEEPING:
			return "sleeping"
		Behaviour.PATROL:
			return "patrol"
	return "wander"


func _to_string() -> String:
	return "Encounter(%s x%.1f)" % [String(character_id), weight]
