class_name TournamentResource
extends Resource

## A TOURNAMENT LADDER (docs/design/DECISIONS.md #33; docs/STORY_MODE.md "Duels in story"): a city
## arena's cup -- a fixed ladder of DUEL bouts ([member rounds], weakest first), an entry fee, a
## prize and a title. Pure data; the rules are [TournamentLedger], the flow is
## [RunTournamentCommand] (the arena master's script) and the screen is [TournamentLadderPanel].
##
## THE FORMAT (the shipped defaults, all data):
##   * pay [member entry_fee] to open a RUN; the bouts are fought in order, one at a time --
##     back-to-back, or one per visit: your place in the ladder is kept (in flags, so it saves)
##     until you win the cup, lose a bout or withdraw;
##   * [member heal_between_bouts]: the arena's healers restore the party's HP before EVERY bout
##     (not a rest -- it never refreshes a sparring partner or a merchant), so the ladder tests the
##     partner, not the walk to the Wayshrine;
##   * a lost bout ends the run (the fee is gone); withdrawing forfeits it too;
##   * winning the last bout wins the cup: [member prize_gold] + [member first_prize_items] the first
##     time, [member repeat_prize_gold] after; the title flag is set; [member wins_flag] counts cups,
##     and a round spec may scale on it ([member BattleSpec.scale_flag]) so repeat cups get harder;
##   * bouts should be SPARS (friendly competition: no permadeath) -- the ledger does not force it.
##
## Ids are save keys (flags "arena.<id>.*"): never rename a shipped id; names are free.

const DIR := "res://game/overworld/content/tournaments/"

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## The announcer (the arena master) who calls the bouts.
@export var host_name: String = ""
@export var host_speaker_id: StringName = &""
@export var entry_fee: int = 100
## The ladder, first bout first. Each a DUEL [BattleSpec] (opponent_name = the entrant).
@export var rounds: Array[BattleSpec] = []
@export var heal_between_bouts: bool = true
@export var prize_gold: int = 0
## Given only for the FIRST cup won.
@export var first_prize_items: Array[StringName] = []
## Gold for every later cup (0 = [member prize_gold] again).
@export var repeat_prize_gold: int = 0
## The title the first cup earns ("Crown Cup Champion"); its flag is [method title_flag].
@export var title: String = ""


static func path_for(tournament_id: String) -> String:
	return "%s%s.tres" % [DIR, tournament_id]


static func load_by_id(tournament_id: String) -> TournamentResource:
	var path: String = path_for(tournament_id)
	if tournament_id.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as TournamentResource


# --- The flags a tournament keeps (all under "arena.<id>.") ------------------------------

## 1 while a paid run is open.
func run_flag() -> String:
	return "arena.%s.run" % String(id)


## Bouts won in the open run (the next bout's index).
func round_flag() -> String:
	return "arena.%s.round" % String(id)


## Cups won, ever.
func wins_flag() -> String:
	return "arena.%s.wins" % String(id)


## Set once the first cup is won: the title.
func title_flag() -> String:
	return "arena.%s.champion" % String(id)


## The encounter id of bout [param index] (0-based): "arena.<id>.round<n>" (1-based n).
func bout_encounter_id(index: int) -> String:
	return "arena.%s.round%d" % [String(id), index + 1]


func round_count() -> int:
	return rounds.size()


func validate(issues: Array[String]) -> void:
	var where: String = "tournament '%s'" % String(id)
	if String(id).strip_edges().is_empty():
		issues.append("a tournament has no id")
	if rounds.is_empty():
		issues.append("%s has no rounds" % where)
	if entry_fee < 0 or prize_gold < 0 or repeat_prize_gold < 0:
		issues.append("%s: negative gold" % where)
	for i in range(rounds.size()):
		var spec: BattleSpec = rounds[i]
		if spec == null:
			issues.append("%s: round %d is empty" % [where, i + 1])
			continue
		if spec.kind != BattleSpec.Kind.DUEL:
			issues.append("%s: round %d is not a duel" % [where, i + 1])
		if spec.opponent_name.strip_edges().is_empty():
			issues.append("%s: round %d has no entrant name" % [where, i + 1])
		var own: Array[String] = []
		spec.validate(own)
		for msg in own:
			issues.append("%s round %d: %s" % [where, i + 1, msg])
	for item_id in first_prize_items:
		if not ItemLibrary.has_item(item_id):
			issues.append("%s: prize item '%s' does not exist" % [where, item_id])
