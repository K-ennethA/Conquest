class_name ChoiceOption
extends Resource

## One answer of a [ChoiceCommand]: its label, an optional condition (hidden when false), the
## commands it runs, and whether Cancel picks it.

@export var label: String = ""
@export var condition: String = ""
@export var commands: Array[Resource] = []
@export var is_cancel: bool = false


static func make(p_label: String, p_commands: Array = [], p_is_cancel: bool = false) -> ChoiceOption:
	var o := ChoiceOption.new()
	o.label = p_label
	o.commands = StoryCommand.list(p_commands)
	o.is_cancel = p_is_cancel
	return o
