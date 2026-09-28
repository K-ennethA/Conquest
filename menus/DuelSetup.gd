extends Control

class_name DuelSetup

## Solo -> Duel: pick your unit and the foe, the stage, the weather, the AI and the
## encounter kind, then Fight (docs/design/DUEL_BATTLE.md §9). Builds a standalone
## [DuelRequest] and hands it to [code]DuelController.start[/code]; the duel's results card
## owns the way back (Rematch / Change Units / Menu).
##
## Only DUEL-ELIGIBLE units are offered ([method DuelMoveCompiler.is_duel_eligible]: a kit
## that cannot damage the foe cannot win a duel). Each unit card lists the duel moveset --
## the compiled moves, variants included -- so what you pick is what you fight with.
##
## Look: the shared grove page ([method MenuKit.build_page]); two carousels of crested
## option cards, option rows, Back / Fight in the footer.
## Keys: Left / Right (or Q / E) cycle the focused carousel, Enter fights, Esc goes back.

const SOLO_SCENE := "res://menus/SoloModeSelect.tscn"

const STAGES := [["meadow", "Meadow"], ["tall_grass", "Tall Grass"], ["grove", "Grove"]]
const DIFFICULTIES := [["Easy", 0], ["Normal", 1]]
const ENCOUNTERS := [["Trainer duel", DuelRequest.KIND_STANDALONE], ["Wild encounter", DuelRequest.KIND_WILD]]

var _ids: Array[StringName] = []
var _pick: Array[int] = [0, 1]
var _cards: Array = [null, null]
var _stage_opt: OptionButton
var _weather_opt: OptionButton
var _difficulty_opt: OptionButton
var _kind_opt: OptionButton
var _fight: Button
var _status: Label
var _weathers: Array[StringName] = []


func _ready() -> void:
	_ids = eligible_ids()
	var vw := _ids.find(&"vineweave")
	var geode := _ids.find(&"gem_knight")
	_pick = [maxi(vw, 0), geode if geode >= 0 else mini(1, _ids.size() - 1)]
	var page := MenuKit.build_page(self, ["Solo"], "Duel", "One on one. No movement -- just the moves.")
	_build(page)
	_refresh_cards()
	MenuNav.focus_deferred(_fight)


## Roster ids a duel can field, sorted by name.
static func eligible_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var rules := DuelRuleset.load_default()
	for id in CharacterLibrary.all_ids():
		var ch := CharacterLibrary.get_character(id)
		if ch != null and DuelMoveCompiler.is_duel_eligible(ch, rules):
			out.append(StringName(id))
	out.sort_custom(func(a, b): return String(a) < String(b))
	return out


func _build(page: Dictionary) -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.body.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.SP_L)
	center.add_child(col)

	var duo := HBoxContainer.new()
	duo.name = "Carousels"
	duo.alignment = BoxContainer.ALIGNMENT_CENTER
	duo.add_theme_constant_override("separation", MenuTheme.SP_L)
	col.add_child(duo)
	duo.add_child(_carousel(0, "Your unit"))
	var vs := MenuKit.label("VS", &"TitleLabel")
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vs.add_theme_font_override("font", MenuTheme.display_font(2))
	vs.add_theme_font_size_override("font_size", MenuTheme.FS_TITLE)
	vs.add_theme_color_override("font_color", MenuTheme.GOLD)
	duo.add_child(vs)
	duo.add_child(_carousel(1, "The foe"))

	var opts := GridContainer.new()
	opts.name = "Options"
	opts.columns = 4
	opts.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	opts.add_theme_constant_override("h_separation", MenuTheme.SP_L)
	opts.add_theme_constant_override("v_separation", MenuTheme.SP_S)
	col.add_child(opts)
	_stage_opt = _option(opts, "Stage", STAGES.map(func(s): return s[1]))
	_weathers = [&"clear"]
	for w in Weather.all_ids():
		if w != &"clear":
			_weathers.append(w)
	_weather_opt = _option(opts, "Weather", _weathers.map(func(w): return Weather.get_weather(w).display_name if Weather.get_weather(w) != null else String(w)))
	_difficulty_opt = _option(opts, "Foe AI", DIFFICULTIES.map(func(d): return d[0]))
	_difficulty_opt.select(1)
	_kind_opt = _option(opts, "Encounter", ENCOUNTERS.map(func(e): return e[0]))

	_status = MenuKit.label("", &"DimLabel")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)

	var back := MenuKit.button("Back", MenuKit.GHOST, 140)
	back.name = "BackButton"
	back.pressed.connect(_on_back)
	page.actions.add_child(back)
	_fight = MenuKit.button("Fight", MenuKit.PRIMARY, 180)
	_fight.name = "FightButton"
	_fight.pressed.connect(_on_fight)
	page.actions.add_child(_fight)
	MenuKit.add_standard_hints(page.hints, "Select")
	var hint := MenuKit.label("← → change unit  •  Enter fight", &"MutedLabel")
	hint.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	page.hints.add_child(hint)


func _carousel(side: int, caption: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", MenuTheme.SP_S)
	var cap := MenuKit.section(caption)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_S)
	box.add_child(row)
	var prev := MenuKit.button("‹", MenuKit.GHOST, 44)
	prev.name = "Prev%d" % side
	_arrow_style(prev)
	prev.pressed.connect(_cycle.bind(side, -1))
	row.add_child(prev)
	var parts := MenuKit.option_card(Vector2(380, 236))
	var card: Button = parts["button"]
	card.name = "UnitCard%d" % side
	card.pressed.connect(_cycle.bind(side, 1))
	MenuNav.hover_focus(card)
	row.add_child(card)
	var next := MenuKit.button("›", MenuKit.GHOST, 44)
	next.name = "Next%d" % side
	_arrow_style(next)
	next.pressed.connect(_cycle.bind(side, 1))
	row.add_child(next)

	var v: VBoxContainer = parts["content"]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var crest := MenuKit.crest("?", MenuTheme.GOLD, ConquestTheme.TEAM_BLUE if side == 0 else ConquestTheme.TEAM_RED, 52)
	head.add_child(crest)
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(names)
	var title := MenuKit.label("", &"SubheadingLabel")
	names.add_child(title)
	var badge := ElementVisuals.make_badge(&"", MenuTheme.FS_CAPTION)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	names.add_child(badge)
	var stats := MenuKit.label("", &"DimLabel")
	stats.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	v.add_child(stats)
	var moves := MenuKit.label("", &"", true)
	moves.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	v.add_child(moves)
	MenuKit.ignore_mouse(card)
	_cards[side] = {"card": card, "crest": crest, "title": title, "badge": badge, "stats": stats,
		"moves": moves, "side": side}
	return box


func _arrow_style(b: Button) -> void:
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size = Vector2(48, 72)
	b.add_theme_font_size_override("font_size", MenuTheme.FS_TITLE)
	b.tooltip_text = "Previous unit" if b.text == "‹" else "Next unit"


func _option(grid: GridContainer, caption: String, items: Array) -> OptionButton:
	var l := MenuKit.label(caption, &"DimLabel")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)
	var o := OptionButton.new()
	o.name = caption.replace(" ", "") + "Option"
	o.custom_minimum_size = Vector2(190, 40)
	for item in items:
		o.add_item(String(item))
	grid.add_child(o)
	return o


func _cycle(side: int, step: int) -> void:
	if _ids.is_empty():
		return
	_pick[side] = posmod(_pick[side] + step, _ids.size())
	_refresh_cards()


func _refresh_cards() -> void:
	var rules := DuelRuleset.load_default()
	for side in 2:
		var c: Dictionary = _cards[side]
		if c == null or _ids.is_empty():
			continue
		var ch := CharacterLibrary.get_character(_ids[_pick[side]])
		var compiled: DuelCharacter = DuelMoveCompiler.compile(ch, rules)["character"]
		c["title"].text = ch.display_name
		MenuKit.set_crest(c["crest"], ch.display_name, ConquestTheme.element_color(String(ch.element)),
			ConquestTheme.TEAM_BLUE if side == 0 else ConquestTheme.TEAM_RED)
		ElementVisuals.update_badge(c["badge"], ch.element)
		c["stats"].text = "HP %d · ATK %d · DEF %d · SPD %d" % [ch.base_health, ch.base_attack, ch.base_defense, ch.base_speed]
		var names: Array[String] = []
		for i in range(compiled.move_count()):
			var m := compiled.get_move(i)
			names.append(("★ " if MoveResource.is_ultimate_move(m, i) else "") + m.display_name)
		var text := "\n".join(names.map(func(n): return "•  " + n))
		if not compiled.excluded_moves.is_empty():
			text += "\n(no duel form: %s)" % ", ".join(compiled.excluded_moves.map(func(id): return String(id).capitalize()))
		c["moves"].text = text
		MenuKit.accent_card(c["card"], ConquestTheme.element_color(String(ch.element)))


## The request the screen's current choices describe.
func build_request() -> DuelRequest:
	var req := DuelRequest.standalone(_ids[_pick[0]], _ids[_pick[1]], int(DIFFICULTIES[_difficulty_opt.selected][1]))
	req.stage_id = String(STAGES[_stage_opt.selected][0])
	req.weather_id = _weathers[_weather_opt.selected]
	req.kind = String(ENCOUNTERS[_kind_opt.selected][1])
	return req


func _on_fight() -> void:
	if _ids.is_empty():
		MenuKit.set_status(_status, "No duel-eligible units.", "error")
		return
	var res: Dictionary = DuelController.start(build_request(), false)
	if not bool(res["success"]):
		MenuKit.set_status(_status, "Cannot start: %s" % String(res["reason"]), "error")
		return
	MenuNav.change_scene(self, DuelController.STAGE_SCENE)


func _on_back() -> void:
	MenuNav.change_scene(self, SOLO_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back()


## Left / Right on a focused unit card cycle that carousel (before the GUI would move focus).
func _input(event: InputEvent) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var side := -1
	for s in 2:
		var c = _cards[s]
		if c != null and focused != null and focused == c["card"]:
			side = s
	if side < 0:
		return
	if event.is_action_pressed("ui_left") or MenuNav.is_prev_event(event):
		get_viewport().set_input_as_handled()
		_cycle(side, -1)
	elif event.is_action_pressed("ui_right") or MenuNav.is_next_event(event):
		get_viewport().set_input_as_handled()
		_cycle(side, 1)
