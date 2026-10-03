class_name WildOutcomeCommand
extends StoryCommand

## After a battle with a VISIBLE wild creature ([WildSpawner]): a WIN (victory -- befriended or
## not) despawns it -- its slot stays empty until the zone's respawn rule fires. A flee, a loss or
## an aborted battle leaves it standing where it was. Built at runtime by the overworld
## ([method OverworldController.start_wild_battle]); runs between the duel and the befriend prompt.

@export var area_id: String = ""
## The creature's spawner key ("<zone key>#<slot>").
@export var creature_key: String = ""


func run(ctx: ScriptContext) -> void:
	var result = ctx.last_result
	if result == null or creature_key.is_empty():
		return
	var outcome: String = String(result.outcome)
	if outcome != BattleResult.OUTCOME_VICTORY and outcome != BattleResult.OUTCOME_BEFRIENDED:
		return
	var aid: String = area_id if not area_id.is_empty() else ctx.area_id
	WildSpawner.forget(ctx.state, aid, creature_key)
	if ctx.has_host_method(&"despawn_wild"):
		ctx.host.despawn_wild(creature_key)


func describe() -> String:
	return "Wild outcome: %s" % creature_key


func validate(issues: Array[String]) -> void:
	if creature_key.is_empty():
		issues.append("has no creature key")
