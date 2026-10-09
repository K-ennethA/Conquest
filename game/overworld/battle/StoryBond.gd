class_name StoryBond
extends RefCounted

## THE BOND ACTIVATION HOOK (DECISIONS.md #54, #65; docs/design/HUMANS.md "Bonds"): a HUMAN
## party member bonded to a CREATURE ([member StoryPartyMember.bond_partner]) can ACTIVATE that
## creature in battle for a bonus. The real bonuses are "defined later" by the owner -- this is the
## hook plus a PLACEHOLDER stat bonus: +[member StoryRuleset.bond_bonus_per_level] of the creature's
## attack / defense / magic / magic_defense per BOND LEVEL of that creature (#68), for
## [member StoryRuleset.bond_bonus_turns] turns. Behind [member StoryRuleset.bond_activation_enabled]
## (default OFF: it changes balance). No player-facing action / command is wired yet.
##
## Pure rules on duck-typed units (anything with get_base_stat / add_stat_modifier through
## unit_stats or the unit itself): failures return {success: false, reason} (rule 1). A second
## activation REFRESHES the bonus (rule 6): the old modifiers go, the new ones replace them.

const STATS: Array[String] = ["attack", "defense", "magic", "magic_defense"]
const MODS_META := &"story_bond_mods"


## The placeholder bonus a creature at [param bond_level] gets: {stat: +amount} from its base stats
## [param base] ({stat: value}). Empty when the hook is off or the bond level is 0.
static func bonus_for(base: Dictionary, bond_level: int, rules: StoryRuleset) -> Dictionary:
	var out: Dictionary = {}
	if rules == null or not rules.bond_activation_enabled or bond_level <= 0:
		return out
	for s in STATS:
		var amt: int = roundi(float(int(base.get(s, 0))) * rules.bond_bonus_per_level * float(bond_level))
		if amt > 0:
			out[s] = amt
	return out


## Can [param human] (a story member) activate its bond now? {ok, reason}: "disabled", "not_human",
## "no_partner", "partner_gone" (its creature left / fell), "no_bond" (bond level 0).
static func can_activate(state: StoryState, human_id: String, rules: StoryRuleset) -> Dictionary:
	if rules == null or not rules.bond_activation_enabled:
		return {"ok": false, "reason": "disabled"}
	var h: StoryPartyMember = state.member(human_id) if state != null else null
	if h == null or not h.is_human():
		return {"ok": false, "reason": "not_human"}
	if h.bond_partner.is_empty():
		return {"ok": false, "reason": "no_partner"}
	var c: StoryPartyMember = state.member(h.bond_partner)
	if c == null:
		return {"ok": false, "reason": "partner_gone"}
	if c.bond_level() <= 0:
		return {"ok": false, "reason": "no_bond"}
	return {"ok": true, "reason": ""}


## ACTIVATE: put the bonus for [param bond_level] on [param creature_unit]. {success, reason,
## bonus: {stat: amount}}. Reasons: "disabled", "no_unit", "no_bond".
static func activate(creature_unit, bond_level: int, rules: StoryRuleset) -> Dictionary:
	if rules == null or not rules.bond_activation_enabled:
		return {"success": false, "reason": "disabled", "bonus": {}}
	if creature_unit == null or not is_instance_valid(creature_unit):
		return {"success": false, "reason": "no_unit", "bonus": {}}
	var stats = creature_unit.get("unit_stats") if "unit_stats" in creature_unit else null
	if stats == null:
		return {"success": false, "reason": "no_unit", "bonus": {}}
	var base: Dictionary = {}
	for s in STATS:
		base[s] = int(stats.get_base_stat(s))
	var bonus: Dictionary = bonus_for(base, bond_level, rules)
	if bonus.is_empty():
		return {"success": false, "reason": "no_bond", "bonus": {}}
	# REFRESH, never stack (CONQUEST.md rule 6).
	for id in creature_unit.get_meta(MODS_META, []):
		stats.remove_stat_modifier(int(id))
	var ids: Array = []
	for s in bonus.keys():
		ids.append(stats.add_stat_modifier(String(s), int(bonus[s]), rules.bond_bonus_turns))
	creature_unit.set_meta(MODS_META, ids)
	return {"success": true, "reason": "", "bonus": bonus}
