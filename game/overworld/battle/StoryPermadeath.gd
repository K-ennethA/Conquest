class_name StoryPermadeath
extends RefCounted

## PURE: the story's DIFFICULTY-TIER rules -- permadeath, revives and the game-over rule
## (docs/design/DECISIONS.md #29 + "Permadeath refinements"). No nodes, no disk: the result
## applier, the Wayshrine's revive offer and StoryController call these, and every rule is
## unit-testable on its own.
##
##   * CLASSIC (permadeath): a party member knocked out in a REAL battle (tactical: dead on the
##     board at the end; duel: the member that fainted) FALLS for the rest of the journey
##     ([method apply_fallen] -> [method StoryState.mark_fallen]): kept as a record (form,
##     growth), shown under Journey -> Party -> Fallen, out of every squad and duel, never healed
##     or revived; its equipped item returns to the bag. Marked when the result is APPLIED, never
##     mid-battle, so the battle simulation (and its replays) know nothing about tiers.
##   * CASUAL: knocked-out members stay down until revived -- a Wayshrine revives them for
##     [member StoryRuleset.revive_fee_per_member] gold each ([method revive_quote]); revive
##     items work in both tiers (never on the fallen).
##   * SPAR: a friendly battle never marks anyone fallen (and never ends the journey through the
##     hero rule); with [member StoryRuleset.spar_ko_recovers] its knocked-out leave at 1 HP.
##   * GAME OVER ([method game_over_reason]): the HERO falling (a party entry flagged hero -- the
##     main character is not a battle unit yet; this is the hook), a unit the battle says to
##     PROTECT falling, or (Classic, [member StoryRuleset.classic_wipe_is_game_over]) a battle
##     that would leave nobody alive. A game over is never applied: the player goes back to the
##     last save (the pre-battle autosave).

const REASON_HERO := "hero"
const REASON_PROTECT := "protect"
const REASON_WIPE := "wipe"


# --- Who went down --------------------------------------------------------------------

## Member ids knocked out IN this battle: party_after rows that fought and ended wounded / at 0.
## (A duel's bench never fought; a member already down was never fielded.)
static func downed_members(result: BattleResult) -> Array[String]:
	var out: Array[String] = []
	if result == null:
		return out
	for e in result.party_after:
		if not (e is Dictionary):
			continue
		if not bool(e.get("fought", true)):
			continue
		var hp: int = int(e.get("current_hp", StoryPartyMember.HP_FULL))
		if bool(e.get("wounded", false)) or hp == 0:
			var mid: String = String(e.get("member_id", ""))
			if not mid.is_empty() and not out.has(mid):
				out.append(mid)
	return out


## Does this battle make its knocked-out members FALL? Classic, a real (non-spar) battle that
## ended (not aborted), and not a game over (a game over is rewound, never applied).
static func marks_fallen(state: StoryState, request: BattleRequest, result: BattleResult) -> bool:
	if state == null or result == null or not state.is_classic():
		return false
	if result.outcome == BattleResult.OUTCOME_ABORTED or result.is_game_over():
		return false
	if result.spar or (request != null and request.is_spar()):
		return false
	return true


## Where / when a member fell in this battle (the record's [member StoryPartyMember.fallen_info]).
static func fall_info(state: StoryState, request: BattleRequest) -> Dictionary:
	var area_id: String = ""
	if request != null:
		area_id = String(request.backdrop.get("area_id", request.return_to.get("area_id", "")))
	if area_id.is_empty() and state != null:
		area_id = state.location_area()
	return {
		"area_id": area_id,
		"encounter_id": request.encounter_id if request != null else "",
		"foe": request.opponent_name() if request != null else "",
		"kind": request.kind if request != null else "",
		"play_seconds": int(state.play_seconds) if state != null else 0,
		"at_utc": Time.get_datetime_string_from_system(true),
	}


## CLASSIC: every member knocked out in this battle FALLS ([method StoryState.mark_fallen]).
## Returns the member ids that fell (none unless [method marks_fallen]).
static func apply_fallen(state: StoryState, request: BattleRequest, result: BattleResult) -> Array[String]:
	var out: Array[String] = []
	if not marks_fallen(state, request, result):
		return out
	var info: Dictionary = fall_info(state, request)
	for mid in downed_members(result):
		if state.mark_fallen(mid, info) != null:
			out.append(mid)
	return out


## SPAR: the members knocked out in it get back up at 1 HP (the ruleset's spar_ko_recovers).
## Returns their ids.
static func recover_spar_knockouts(state: StoryState, result: BattleResult) -> Array[String]:
	var out: Array[String] = []
	if state == null or result == null:
		return out
	for mid in downed_members(result):
		var m: StoryPartyMember = state.member(mid)
		if m == null:
			continue
		m.wounded = false
		m.current_hp = 1
		out.append(mid)
	return out


# --- Game over ------------------------------------------------------------------------

## Why [param result] ENDS THE JOURNEY, or "" when it does not (see the class docs):
## "hero", "protect:<name>" or "wipe". A reason the battle already set (the tactical bridge's
## protect guards) wins.
static func game_over_reason(state: StoryState, request: BattleRequest, result: BattleResult,
		ruleset: StoryRuleset = null) -> String:
	if result == null or result.outcome == BattleResult.OUTCOME_ABORTED:
		return ""
	if result.is_game_over():
		return result.game_over_reason
	var spar: bool = result.spar or (request != null and request.is_spar())
	var down: Array[String] = downed_members(result)
	if request != null:
		# The main character: always a game over (a friendly spar only knocks them out).
		if not spar:
			for mid in request.hero_member_ids():
				if down.has(mid):
					return REASON_HERO
		# A party member the mission said to protect (a duel's protect, or a tactical one the
		# board guard did not already report).
		for target in request.protect_targets():
			for p in request.party:
				if not (p is Dictionary):
					continue
				var mid: String = String(p.get("member_id", ""))
				if not down.has(mid):
					continue
				if _names(target, mid, String(p.get("character_id", "")), state):
					return "%s:%s" % [REASON_PROTECT, target]
	# CLASSIC: nobody would be left to carry on.
	if state != null and not spar and state.is_classic() and not down.is_empty() \
			and (ruleset == null or ruleset.classic_wipe_is_game_over) \
			and result.outcome != BattleResult.OUTCOME_ABORTED:
		var alive: int = 0
		for m in state.party:
			if not down.has(m.member_id):
				alive += 1
		if alive == 0:
			return REASON_WIPE
	return ""


static func _names(target: String, member_id: String, character_id: String, state: StoryState) -> bool:
	var t: String = target.to_lower()
	if t == member_id.to_lower() or t == character_id.to_lower():
		return true
	var m: StoryPartyMember = state.member(member_id) if state != null else null
	return m != null and m.display_name().to_lower() == t


## The game-over screen's line for [param reason] ("Linnea has fallen."), naming the hero
## [param hero_name] for the hero rule.
static func game_over_text(reason: String, hero_name: String = "") -> String:
	if reason == REASON_HERO:
		return "%s has fallen. The journey cannot go on without them." % (hero_name if not hero_name.is_empty() else "The hero")
	if reason.begins_with(REASON_PROTECT + ":"):
		return "%s has fallen. You were sworn to protect them." % reason.substr(REASON_PROTECT.length() + 1)
	if reason == REASON_WIPE:
		return "Every companion has fallen. There is no one left to go on with."
	return "The journey cannot go on from here."


# --- Revives (Casual) -------------------------------------------------------------------

## True when reviving the knocked-out costs gold in this journey: Casual with a fee.
static func revive_costs_gold(state: StoryState, ruleset: StoryRuleset) -> bool:
	return state != null and not state.is_classic() and ruleset != null and ruleset.revive_fee_per_member > 0


## What a Wayshrine revive of [param state]'s knocked-out members costs:
## {count, fee_each, total, costs_gold, affordable, pity}. [code]pity[/code]: nobody can fight and
## the fee cannot be paid -- the shrine revives them anyway (a journey is never stuck).
static func revive_quote(state: StoryState, ruleset: StoryRuleset) -> Dictionary:
	var out: Dictionary = {"count": 0, "fee_each": 0, "total": 0, "costs_gold": false,
		"affordable": true, "pity": false}
	if state == null:
		return out
	var count: int = state.knocked_out_members().size()
	out["count"] = count
	if count == 0:
		return out
	if not revive_costs_gold(state, ruleset):
		return out
	var each: int = maxi(0, ruleset.revive_fee_per_member)
	out["fee_each"] = each
	out["total"] = each * count
	out["costs_gold"] = true
	out["affordable"] = state.gold >= int(out["total"])
	out["pity"] = not bool(out["affordable"]) and state.healthy_members().is_empty()
	return out


## Revive every knocked-out member to full HP (the Wayshrine's paid / free revive). Returns how
## many got up.
static func revive_all(state: StoryState) -> int:
	if state == null:
		return 0
	var n: int = 0
	for m in state.knocked_out_members():
		m.heal_full()
		n += 1
	return n


# --- Tier words -----------------------------------------------------------------------

static func tier_name(tier: String) -> String:
	return "Classic" if tier == StoryState.TIER_CLASSIC else "Casual"


## The New Journey / Journey menu explanation of [param tier].
static func tier_blurb(tier: String, ruleset: StoryRuleset = null) -> String:
	if tier == StoryState.TIER_CLASSIC:
		return "Permadeath. A companion who falls in a real battle is gone for the rest of the journey. Friendly spars never cost a life."
	var fee: int = ruleset.revive_fee_per_member if ruleset != null else 50
	if fee > 0:
		return "Knocked-out companions wait to be revived: %d gold each at a Wayshrine, or a revive item. Nothing is lost for good." % fee
	return "Knocked-out companions recover at any Wayshrine, or with a revive item. Nothing is lost for good."
