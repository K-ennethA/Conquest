extends EvolutionTrigger
class_name BattleFeatTrigger

## A BATTLE FEAT (docs/design/DECISIONS.md #26): met once the member's post-battle counter
## reaches [member count]. The counters are recorded AFTER a battle, from what the
## [GrowthTracker] roll call already sees (open modes) or the [BattleResult] party rows
## ([StoryGrowth], story) -- never inside the simulation, so replays and lockstep are untouched:
##   WINS         won battles the member fought in
##   KOS          enemy KOs it landed (won or lost)
##   ELEMENT_KOS  KOs of foes of [member element]
##   CLUTCH_WINS  won battles it finished alive at or under
##                [member EvolutionRules.clutch_hp_ratio] of its max HP
## Reads ctx key [code]feats[/code] ({wins, kos, clutch_wins, element_kos: {element: n}}). Works
## in every mode (open-mode members count in [RosterLedger]).

enum Feat { WINS, KOS, ELEMENT_KOS, CLUTCH_WINS }

@export var feat: Feat = Feat.WINS
@export var count: int = 1
## The foe element ELEMENT_KOS counts ("dark").
@export var element: String = ""


func is_met(ctx: Dictionary) -> bool:
	return current(ctx) >= maxi(1, count)


## The member's counter for [member feat].
func current(ctx: Dictionary) -> int:
	var feats = ctx.get("feats", {})
	if not (feats is Dictionary):
		return 0
	match feat:
		Feat.WINS:
			return int(feats.get("wins", 0))
		Feat.KOS:
			return int(feats.get("kos", 0))
		Feat.CLUTCH_WINS:
			return int(feats.get("clutch_wins", 0))
		Feat.ELEMENT_KOS:
			var by = feats.get("element_kos", {})
			return int((by as Dictionary).get(element, 0)) if by is Dictionary else 0
	return 0


func describe() -> String:
	var n: int = maxi(1, count)
	var s: String = "" if n == 1 else "s"
	match feat:
		Feat.WINS:
			return "Win %d battle%s with it" % [n, s]
		Feat.KOS:
			return "Land %d KO%s" % [n, s]
		Feat.ELEMENT_KOS:
			return "KO %d %s foe%s" % [n, element.capitalize(), s]
		Feat.CLUTCH_WINS:
			return "Win %d battle%s at %d%% HP or less" % [n, s,
				roundi(EvolutionRules.current().clutch_hp_ratio * 100.0)]
	return ""


func progress(ctx: Dictionary) -> String:
	var n: int = maxi(1, count)
	return "%d/%d" % [mini(current(ctx), n), n]


func responds_to(event: Dictionary) -> bool:
	return event_has(event, "battle")


func problem() -> String:
	if count <= 0:
		return "a BattleFeat requirement asks for %d" % count
	if feat == Feat.ELEMENT_KOS and element.strip_edges().is_empty():
		return "an ELEMENT_KOS BattleFeat names no element"
	return ""
