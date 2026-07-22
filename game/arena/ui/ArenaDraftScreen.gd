extends Control

## Between-round reward step: after clearing a round you pick one power-up (augment) to
## stack onto your build, then the next round loads. SKELETON: builds a minimal
## title + Continue UI and, if ArenaController offers options, a row of pick buttons.
## The real 3-card draft (icons, rarity framing, reroll, SINGLE_UNIT targeting, and the
## CURRENCY heal-vs-powerup trade) is a follow-up task; the loop wiring is done here.

func _ready() -> void:
	var arena := get_node_or_null("/root/ArenaController")

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.04, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	var round_num: int = arena.current_round() if arena != null and arena.has_method("current_round") else 0
	title.text = "Round %d cleared — choose a power-up" % round_num
	box.add_child(title)

	var options: Array = []
	if arena != null and arena.has_method("roll_draft_options"):
		options = arena.roll_draft_options()

	if options.is_empty():
		# No pool wired yet: a single Continue advances the loop.
		var cont := Button.new()
		cont.text = "Continue"
		cont.custom_minimum_size = Vector2(220, 48)
		cont.pressed.connect(func() -> void:
			if arena != null:
				arena.choose_augment(null))
		box.add_child(cont)
	else:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		box.add_child(row)
		for opt in options:
			var b := Button.new()
			b.custom_minimum_size = Vector2(200, 120)
			b.text = String(opt.display_name) if opt != null else "?"
			b.pressed.connect(func() -> void:
				if arena != null:
					arena.choose_augment(opt))
			row.add_child(b)
