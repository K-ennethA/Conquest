class_name HealPartyCommand
extends StoryCommand

## A full rest (Wayshrines, healer NPCs): every living member back to full HP. The KNOCKED-OUT
## get up too -- except in a CASUAL journey with a revive fee, where they are recovered for gold
## ([ReviveOfferCommand], DECISIONS.md #29 refinements). The FALLEN are never healed.


func run(ctx: ScriptContext) -> void:
	var ruleset: StoryRuleset = ctx.session.ruleset() if ctx.has_session_method(&"ruleset") else null
	ctx.state.heal_party(not StoryPermadeath.revive_costs_gold(ctx.state, ruleset))


func describe() -> String:
	return "Heal party"
