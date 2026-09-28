class_name StartBattleCommand
extends StoryCommand

## Start a battle from a [BattleSpec] and CONTINUE AFTER IT: the script pauses across the whole
## round trip (overworld -> battle -> overworld) and resumes with ctx.last_result set, so later
## If commands can branch on outcome(). The battle goes through the SESSION (StoryController),
## never the host -- the host is a scene node that dies on the way to the battle.
##
## A trainer battle with clash_intro plays the VS clash on the host first.

@export var spec: BattleSpec
@export var source: String = BattleRequest.SOURCE_SCRIPT
## Overrides the spec's encounter id ("" = the spec's own).
@export var encounter_id: String = ""


func build_request(_ctx: ScriptContext) -> BattleRequest:
	if spec == null:
		return null
	return spec.to_request(source, encounter_id)


func run(ctx: ScriptContext) -> void:
	var request: BattleRequest = build_request(ctx)
	if request == null:
		return
	if not encounter_id.is_empty():
		request.encounter_id = encounter_id
	if request.clash_intro and ctx.has_host_method(&"play_clash"):
		await ctx.host.play_clash(request)
	if not ctx.has_session_method(&"run_battle"):
		ctx.stop("no_session")
		return
	var result = await ctx.session.run_battle(request)
	ctx.last_result = result


func describe() -> String:
	return "Start battle: %s" % (str(spec) if spec != null else "(none)")


func validate(issues: Array[String]) -> void:
	if spec == null:
		issues.append("has no battle spec")
	else:
		spec.validate(issues)
