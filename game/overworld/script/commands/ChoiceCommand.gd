class_name ChoiceCommand
extends StoryCommand

## Asks a question with 2-4 answers (StoryDialogue.play_choice) and runs the chosen branch. The
## chosen label is stored in ctx.vars["last_choice"]; options whose condition is false are not
## offered. Cancel picks the option flagged is_cancel (else the prompt just waits for a pick).

@export var prompt: StoryBeat
@export var options: Array[Resource] = []


func offered(ctx: ScriptContext) -> Array[ChoiceOption]:
	var out: Array[ChoiceOption] = []
	for o in options:
		var opt := o as ChoiceOption
		if opt != null and ctx.condition(opt.condition):
			out.append(opt)
	return out


func run(ctx: ScriptContext) -> void:
	var opts: Array[ChoiceOption] = offered(ctx)
	if opts.is_empty():
		return
	var labels := PackedStringArray()
	var cancel_index: int = -1
	for i in range(opts.size()):
		labels.append(ctx.substitute(opts[i].label))
		if opts[i].is_cancel:
			cancel_index = i
	var beat: StoryBeat = prompt if prompt != null else SayCommand.beat(StoryBeat.NARRATOR, "", "")
	var shown: StoryBeat = SayCommand.resolve_beat(beat, ctx)
	var picked: int = maxi(0, cancel_index)
	if ctx.has_host_method(&"show_choice"):
		picked = int(await ctx.host.show_choice(shown, labels, cancel_index))
	if picked < 0 or picked >= opts.size():
		return
	ctx.vars["last_choice"] = opts[picked].label
	await StoryScriptRunner.run_list(opts[picked].commands, ctx)


func child_lists() -> Array:
	var out: Array = []
	for o in options:
		var opt := o as ChoiceOption
		if opt != null:
			out.append(opt.commands)
	return out


func describe() -> String:
	var labels: Array[String] = []
	for o in options:
		var opt := o as ChoiceOption
		if opt != null:
			labels.append(opt.label)
	return "Choice: %s" % " / ".join(labels)


func validate(issues: Array[String]) -> void:
	var n: int = 0
	for o in options:
		var opt := o as ChoiceOption
		if opt == null:
			continue
		n += 1
		StoryCommand.check_condition(opt.condition, issues, "option '%s' condition" % opt.label)
	if n < 2 or n > 4:
		issues.append("needs 2-4 options (has %d)" % n)
