class_name TeachFieldMoveCommand
extends StoryCommand

## A chief TEACHES a FIELD MOVE (docs/design/DECISIONS.md #92: Nyra teaches the tree-felling move, a
## member LEARNS it, HM-style). The candidates are the party members who can learn it and do not
## know it yet ([method FieldMoveResource.teachable_members]):
##   * none -> nothing happens (ctx.vars["taught"] false, "teach_reason" "no_candidate"); content
##     says "come back with one who can" and the move stays teachable by talking again;
##   * exactly one, and nobody knows the move yet -> it just learns it (no question);
##   * otherwise -> [member prompt] with the candidates' names and [member cancel_label] (pages of
##     names with "More..." when they do not fit one choice box); the pick learns it, Cancel
##     declines ("teach_reason" "declined").
## A member who learns it: a toast ([member FieldMoveResource.learned_text]); [member learned_flag]
## (when set) marks that someone has (a quest step reads it). ctx.vars["taught_member"] = its id.

## The [FieldMoveResource] id.
@export var move_id: StringName = &""
## The question ("Who will learn {move}?"). {move} = the move's name.
@export var prompt: StoryBeat
@export var cancel_label: String = "Not now"
@export var more_label: String = "More..."
## Set (to 1) whenever a member learns it here ("" = none).
@export var learned_flag: String = ""

## A choice box shows at most this many options (ChoiceCommand's 2-4 rule).
const MAX_OPTIONS := 4


func move() -> FieldMoveResource:
	return FieldMoveResource.load_by_id(String(move_id))


func run(ctx: ScriptContext) -> void:
	ctx.vars["taught"] = false
	var fm: FieldMoveResource = move()
	if fm == null:
		ctx.vars["teach_reason"] = "no_move"
		return
	var cands: Array[StoryPartyMember] = fm.teachable_members(ctx.state)
	if cands.is_empty():
		ctx.vars["teach_reason"] = "no_candidate"
		return
	var pick: StoryPartyMember = null
	if cands.size() == 1 and fm.known_by(ctx.state).is_empty():
		pick = cands[0]
	else:
		pick = await _choose(ctx, fm, cands)
	if pick == null:
		ctx.vars["teach_reason"] = "declined"
		return
	var r: Dictionary = ctx.state.teach_field_move(pick.member_id, fm)
	if not bool(r["ok"]):
		ctx.vars["teach_reason"] = String(r["reason"])
		return
	ctx.vars["taught"] = true
	ctx.vars["teach_reason"] = ""
	ctx.vars["taught_member"] = pick.member_id
	if not learned_flag.is_empty():
		ctx.state.set_flag(learned_flag, 1)
	ctx.world_changed()
	if ctx.has_host_method(&"toast"):
		ctx.host.toast(fm.fill(fm.learned_text, pick.display_name()), "quest")


## The pages of candidates: every candidate fits one box (names + Cancel), else pages of
## MAX_OPTIONS - 2 names + "More..." + Cancel (the last page's More goes back to the first).
static func pages(count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	if count <= MAX_OPTIONS - 1:
		out.append(range(count))
		return out
	var per: int = MAX_OPTIONS - 2
	var i: int = 0
	while i < count:
		out.append(range(i, mini(i + per, count)))
		i += per
	return out


func _choose(ctx: ScriptContext, fm: FieldMoveResource, cands: Array[StoryPartyMember]) -> StoryPartyMember:
	if not ctx.has_host_method(&"show_choice"):
		return null  # no one to ask: declined (as a ChoiceCommand with no host picks Cancel)
	var beat: StoryBeat = prompt if prompt != null else SayCommand.beat(StoryBeat.NARRATOR, "", "Who will learn {move}?")
	var shown: StoryBeat = SayCommand.resolve_beat(beat, ctx)
	shown.text = fm.fill(shown.text)
	var book: Array = pages(cands.size())
	var p: int = 0
	# A safety cap: a host that keeps answering "More..." cycles the pages, never forever.
	for _guard in range(64):
		var page: Array = book[p]
		var labels := PackedStringArray()
		for i in page:
			labels.append(cands[int(i)].display_name())
		var more_index: int = -1
		if book.size() > 1:
			more_index = labels.size()
			labels.append(more_label)
		var cancel_index: int = labels.size()
		labels.append(cancel_label)
		var picked: int = int(await ctx.host.show_choice(shown, labels, cancel_index))
		if picked >= 0 and picked < page.size():
			return cands[int(page[picked])]
		if picked == more_index:
			p = (p + 1) % book.size()
			continue
		return null
	return null


func describe() -> String:
	return "Teach field move: %s" % move_id


func validate(issues: Array[String]) -> void:
	if move() == null:
		issues.append("field move '%s' does not exist" % move_id)
	if cancel_label.strip_edges().is_empty():
		issues.append("teach '%s': needs a cancel label" % move_id)
