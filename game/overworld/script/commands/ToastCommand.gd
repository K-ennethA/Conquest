class_name ToastCommand
extends StoryCommand

## A gold ribbon toast on the overworld HUD ("Quest: The Blighted Road").

@export var text: String = ""
## "quest" | "item" | "gold" | "info"
@export var toast_kind: String = "info"


static func make(p_text: String, p_kind: String = "info") -> ToastCommand:
	var t := ToastCommand.new()
	t.text = p_text
	t.toast_kind = p_kind
	return t


func run(ctx: ScriptContext) -> void:
	if ctx.has_host_method(&"toast"):
		ctx.host.toast(ctx.substitute(text), toast_kind)


func describe() -> String:
	return "Toast: %s" % text
