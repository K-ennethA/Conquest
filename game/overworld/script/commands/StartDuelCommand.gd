class_name StartDuelCommand
extends StartBattleCommand

## A DUEL (1v1 turn-based, DUEL_BATTLE.md) from a [BattleSpec] or a wild [EncounterEntry]. The
## overworld never renders a duel: the request goes to [DuelLauncher] (the debug [DuelStub] until
## feat/duel registers the real launcher -- no overworld change needed).

## Wild alternative to [member StartBattleCommand.spec] (grass encounters build this at runtime).
@export var entry: EncounterEntry
@export var area_id: String = ""
## Wild only: how the encounter began -- "grass" (a hidden roll) or "wild" (a visible creature);
## part of the encounter id ("mossway.wild.petalfang").
@export var id_kind: String = "grass"
## Wild only: the CONTACT opening ([constant BattleRequest.OPENING_AMBUSH] / ..._AMBUSHED /
## ..._NEUTRAL; "" = none) written to the request's rules.
@export var opening: String = ""


func build_request(ctx: ScriptContext) -> BattleRequest:
	var r: BattleRequest = null
	if entry != null:
		r = entry.to_request(area_id if not area_id.is_empty() else ctx.area_id, id_kind, opening)
	elif spec != null:
		r = spec.to_request(source, encounter_id)
	if r != null:
		r.kind = BattleRequest.KIND_DUEL
	return r


func describe() -> String:
	if entry != null:
		return "Start duel: wild %s" % entry.character_id
	return "Start duel: %s" % (str(spec) if spec != null else "(none)")


func validate(issues: Array[String]) -> void:
	if spec == null and entry == null:
		issues.append("has neither a battle spec nor an encounter entry")
	elif spec != null:
		for t in spec.opponent_team:
			var cid: String = String((t as Dictionary).get("character_id", ""))
			if CharacterLibrary.get_character(StringName(cid)) == null:
				issues.append("opponent character '%s' does not exist" % cid)
		if spec.opponent_team.is_empty():
			issues.append("duel has no opponent_team")
