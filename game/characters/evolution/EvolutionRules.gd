extends Resource
class_name EvolutionRules

## The balance and progression knobs of the EVOLUTION feature, as data (CONQUEST.md rule 11:
## every number is a .tres edit). The shipped values live in
## res://game/characters/evolution/evolution_rules.tres; [method current] loads it once.
##
## These are GLOBAL rules (how Growth is earned, what the validator accepts). Per-MODE switches
## (e.g. a format's max form stage) go through [ModeTuning] on the mode's own ruleset instead.

const RULES_PATH: String = "res://game/characters/evolution/evolution_rules.tres"

## Growth a squad unit earns for fighting and SURVIVING a won battle.
@export var growth_per_win: int = 1
## Bonus Growth per enemy KO in a won battle (0 = KOs do not count).
@export var growth_per_ko: int = 0
## Maximum KO bonus per unit per battle.
@export var growth_ko_cap: int = 2
## Participation Growth for every fielded unit on a defeat (0 = none).
@export var growth_on_loss: int = 0
## Mode ids ([method GrowthTracker.detect_mode]) in which Growth is earned. Arena and versus
## are deliberately absent: an arena run is its own progression and versus must not grind.
## "story" = every story battle, tactical AND duel ([StoryGrowth]); "duel" = a STANDALONE duel
## (Solo -> Duel), shipped OFF: a free pick-any-unit 1v1 against the AI is the cheapest grind in
## the game, so it earns Growth only if a designer lists it here.
@export var growth_modes: PackedStringArray = PackedStringArray(["skirmish", "campaign", "challenge"])
## Validator ceiling: an evolved form's power budget may be at most this multiple of its
## parent's ([method EvolutionLibrary.validate]).
@export var max_budget_growth: float = 1.75
## Character Select hides evolved forms the player has not unlocked yet.
@export var hide_locked_forms: bool = true
## BATTLE FEATS ([BattleFeatTrigger] CLUTCH_WINS): a won battle counts as a clutch win for a
## member that finished it alive at or under this fraction of its max HP.
@export_range(0.0, 1.0, 0.01) var clutch_hp_ratio: float = 0.25

static var _current: EvolutionRules = null


## The shipped rules (cached). Falls back to the script defaults when the .tres is missing, so
## a content mistake degrades to sane numbers rather than a crash.
static func current() -> EvolutionRules:
	if _current == null:
		if ResourceLoader.exists(RULES_PATH):
			_current = load(RULES_PATH) as EvolutionRules
		if _current == null:
			_current = EvolutionRules.new()
	return _current


## True when battles of [param mode] earn Growth.
func earns_growth_in(mode: String) -> bool:
	return growth_modes.has(mode)
