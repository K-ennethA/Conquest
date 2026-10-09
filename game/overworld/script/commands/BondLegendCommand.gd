class_name BondLegendCommand
extends StoryCommand

## The hero BONDS WITH A LEGEND (docs/design/DECISIONS.md #39 / #74 / #75): the legend is recorded in
## the journey's [member StoryState.legends] -- NOT the party. A legend never accompanies the hero;
## it "can be called upon in special battles or online" (not implemented yet). Bonding is OPTIONAL:
## content offers it with a Yes / No after the legend battle is won (and pairs it with a SetFlag so
## the legend's overworld entity can leave). Toasts on a new bond.

@export var character_id: StringName = &""
## The toast. {name} = the legend's display name.
@export var toast_text: String = "Bonded with {name}."


func run(ctx: ScriptContext) -> void:
	var added: bool = ctx.state.add_legend(String(character_id))
	ctx.vars["bonded"] = added
	ctx.world_changed()
	if added and ctx.has_host_method(&"toast"):
		ctx.host.toast(toast_text.replace("{name}", legend_name()), "quest")


## The legend's display name (its roster entry's, else the id).
func legend_name() -> String:
	var c: CharacterResource = CharacterLibrary.get_character(character_id)
	return c.display_name if c != null else String(character_id).capitalize()


func describe() -> String:
	return "Bond with legend: %s" % character_id


func validate(issues: Array[String]) -> void:
	if CharacterLibrary.get_character(character_id) == null:
		issues.append("legend '%s' does not exist" % character_id)
