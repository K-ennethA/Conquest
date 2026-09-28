class_name TournamentLadderPanel
extends CanvasLayer

## THE TOURNAMENT LADDER (docs/design/DECISIONS.md #33) -- a grove card over the overworld, opened
## by [RunTournamentCommand] through the host ([code]open_ladder[/code]):
##
##   ribbon  THE CROWN CUP                                  ◆ 240 gold
##   description
##   [Entry 100 gold] [Prize 400 gold + Hollowbark Ward] [Crown Cup Champion x1]
##   ── The ladder ───────────────────────────────────────────────────────
##   ROUND 1  (M) Tamsin -- Mycothrall            ◆◆○○○     WON
##   ROUND 2  (B) Old Harl -- Blightcap           ◆◆◆○○     NEXT
##   ...
##   status line
##   [ FIGHT ROUND 2 ]  [ Withdraw ]  [ Leave ]           (no run: [ ENTER · 100 G ] [ Leave ])
##
## "Threat" pips compare each entrant (its species' stats x its strength, scaling included) with
## your party lead: 3 = an even match. Every rule is [TournamentLedger]'s; this panel only shows it
## and reports the player's pick through [signal chosen] ("enter" / "fight" / "withdraw" /
## "leave"). Keyboard / pad: left / right between the buttons, Confirm picks, Esc / B leaves.
## Modal ([constant InputActions.OVERLAY_GROUP]) while open.

signal chosen(action: String)

const LAYER_INDEX: int = 70
const NODE_NAME := "TournamentLadder"

var tournament: TournamentResource = null
var state: StoryState = null

var _root: Control = null
var _title: PanelContainer = null
var _gold: Label = null
var _desc: Label = null
var _badges: HBoxContainer = null
var _rows_box: VBoxContainer = null
var _status: Label = null
var _buttons_row: HBoxContainer = null
var _buttons: Dictionary = {}
var _open: bool = false


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## Show [param t] for the journey [param s].
func open(t: TournamentResource, s: StoryState) -> void:
	tournament = t
	state = s
	if _root == null:
		_build()
	_open = true
	_root.visible = true
	_root.add_to_group(InputActions.OVERLAY_GROUP)
	refresh()


func is_open() -> bool:
	return _open


## Report [param action] and close. Only the first pick counts; a disabled button's pick is refused.
func choose(action: String) -> bool:
	if not _open:
		return false
	var b: Button = _buttons.get(action, null)
	if b != null and b.disabled:
		return false
	_open = false
	_root.visible = false
	_root.remove_from_group(InputActions.OVERLAY_GROUP)
	chosen.emit(action)
	return true


## The button of [param action] (null when not offered right now).
func button(action: String) -> Button:
	return _buttons.get(action, null)


## The offered actions, in order (tests).
func actions() -> Array[String]:
	var out: Array[String] = []
	for k in _buttons.keys():
		out.append(String(k))
	return out


func status_text() -> String:
	return _status.text if _status != null else ""


## The round rows (one PanelContainer per round, named "Round<n>").
func round_row(n: int) -> Control:
	return _rows_box.get_node_or_null("Round%d" % n) as Control if _rows_box != null else null


func refresh() -> void:
	if _root == null or tournament == null:
		return
	var t := tournament
	_set_title(t.display_name)
	_gold.text = "◆  %d gold" % (state.gold if state != null else 0)
	_desc.text = t.description
	_desc.visible = not t.description.is_empty()
	for c in _badges.get_children():
		_badges.remove_child(c)
		c.queue_free()
	var champion: bool = TournamentLedger.is_champion(state, t)
	_badges.add_child(MenuKit.badge("Entry %d gold" % t.entry_fee, MenuTheme.GOLD))
	_badges.add_child(MenuKit.badge("Prize " + _prize_text(champion), MenuTheme.SUCCESS))
	_badges.add_child(MenuKit.badge("Healed before every bout" if t.heal_between_bouts else "HP carries between bouts", MenuTheme.ACCENT))
	if champion and not t.title.is_empty():
		var cups: int = TournamentLedger.cups_won(state, t)
		var tb := MenuKit.badge("%s%s" % [t.title, "  ×%d" % cups if cups > 1 else ""], MenuTheme.GOLD, true)
		tb.name = "TitleBadge"
		_badges.add_child(tb)
	_fill_rows()
	_fill_buttons()


# =====================================================================================
#  Build
# =====================================================================================

func _build() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.name = NODE_NAME
	_root.theme = ConquestTheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(MenuTheme.BG_DEEP, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var card := PanelContainer.new()
	card.name = "LadderCard"
	card.custom_minimum_size = Vector2(820, 0)
	var sb := MenuTheme.card_box(MenuTheme.PANEL, MenuTheme.GOLD_DK)
	sb.crest = true
	sb.set_content_margin_all(22)
	sb.content_margin_top = 30
	card.add_theme_stylebox_override("panel", sb)
	ConquestTheme.keep_style(card)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.SP_S)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", MenuTheme.SP_M)
	col.add_child(head)
	_title = ConquestTheme.title_ribbon("TOURNAMENT", MenuTheme.GOLD_DK, MenuTheme.FS_SUBHEADING)
	_title.name = "LadderTitle"
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var gold_pill := PanelContainer.new()
	gold_pill.name = "GoldPill"
	gold_pill.add_theme_stylebox_override("panel", MenuTheme.pill_box(Color(MenuTheme.GOLD_DK, 0.35), MenuTheme.GOLD))
	ConquestTheme.keep_style(gold_pill)
	gold_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(gold_pill)
	_gold = Label.new()
	_gold.name = "Gold"
	_gold.add_theme_font_override("font", MenuTheme.heading_font(1))
	_gold.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	_gold.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	gold_pill.add_child(_gold)

	_desc = MenuKit.label("", &"DimLabel", true)
	_desc.name = "Description"
	_desc.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	col.add_child(_desc)

	_badges = HBoxContainer.new()
	_badges.name = "Badges"
	_badges.add_theme_constant_override("separation", MenuTheme.SP_S)
	col.add_child(_badges)

	var rule := GroveRule.new()
	rule.custom_minimum_size = Vector2(0, 10)
	col.add_child(rule)
	col.add_child(MenuKit.section("The ladder"))

	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rounds"
	_rows_box.add_theme_constant_override("separation", 4)
	col.add_child(_rows_box)

	var rule2 := GroveRule.new()
	rule2.custom_minimum_size = Vector2(0, 10)
	col.add_child(rule2)

	_status = MenuKit.label("", &"", true)
	_status.name = "Status"
	_status.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	_status.add_theme_color_override("font_color", MenuTheme.CREAM)
	col.add_child(_status)

	_buttons_row = HBoxContainer.new()
	_buttons_row.name = "Actions"
	_buttons_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	col.add_child(_buttons_row)

	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", MenuTheme.SP_L)
	col.add_child(hints)
	hints.add_child(MenuKit.key_hint("← →", "◀ ▶", "Choose"))
	MenuKit.add_standard_hints(hints, "Select", "Leave")


func _set_title(text: String) -> void:
	var l := _title.get_node_or_null("Text") as Label
	if l == null:
		l = _title.find_child("*", true, false) as Label
	if l != null:
		l.text = text.to_upper()


func _prize_text(champion: bool) -> String:
	var t := tournament
	var gold: int = t.prize_gold if not champion or t.repeat_prize_gold <= 0 else t.repeat_prize_gold
	var parts: Array[String] = ["%d gold" % gold]
	if not champion:
		for item_id in t.first_prize_items:
			var item: ItemResource = ItemLibrary.get_item(item_id)
			if item != null:
				parts.append(item.display_name)
	return " + ".join(parts)


func _fill_rows() -> void:
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	var lead_power: float = _lead_power()
	for r in TournamentLedger.ladder_rows(state, tournament):
		_rows_box.add_child(_make_row(r, lead_power))


func _make_row(r: Dictionary, lead_power: float) -> PanelContainer:
	var n: int = int(r["index"]) + 1
	var status: String = String(r["status"])
	var p := PanelContainer.new()
	p.name = "Round%d" % n
	var wash: Color = MenuTheme.PANEL_SUNK
	var edge: Color = MenuTheme.BORDER_SOFT
	if status == "next":
		wash = Color(MenuTheme.GOLD_DK, 0.3)
		edge = MenuTheme.GOLD
	elif status == "won":
		wash = Color(MenuTheme.SUCCESS, 0.12)
		edge = Color(MenuTheme.SUCCESS, 0.7)
	var box := MenuTheme.card_box(wash, edge, 0.95)
	box.set_content_margin_all(8)
	box.content_margin_left = 14
	box.content_margin_right = 14
	p.add_theme_stylebox_override("panel", box)
	ConquestTheme.keep_style(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", MenuTheme.SP_M)
	p.add_child(h)
	var round_l := MenuKit.label("FINAL" if n == tournament.round_count() else "ROUND %d" % n, &"SectionLabel")
	round_l.custom_minimum_size = Vector2(92, 0)
	round_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(round_l)
	var chr: CharacterResource = CharacterLibrary.get_character(StringName(String(r["character_id"])))
	var el_col: Color = MenuKit.element_color(String(chr.element)) if chr != null else MenuTheme.GOLD
	var crest := MenuKit.crest(chr.display_name if chr != null else "?", el_col, MenuTheme.GOLD_DK, 36.0)
	h.add_child(crest)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(names)
	var who := MenuKit.label(String(r["name"]), &"SubheadingLabel")
	who.name = "Entrant"
	who.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	names.add_child(who)
	var species := MenuKit.label(chr.display_name if chr != null else "", &"DimLabel")
	species.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	names.add_child(species)
	var pips: int = _threat_pips(chr, float(r["strength"]), lead_power)
	var threat := Label.new()
	threat.name = "Threat"
	threat.text = "◆".repeat(pips) + "◇".repeat(5 - pips)
	threat.tooltip_text = "Threat compared with your lead"
	threat.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	threat.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	threat.add_theme_color_override("font_color", MenuTheme.DANGER if pips >= 4 else MenuTheme.GOLD_LITE)
	h.add_child(threat)
	var tag_text: String = {"won": "WON", "next": "NEXT"}.get(status, "")
	var tag_col: Color = MenuTheme.SUCCESS if status == "won" else MenuTheme.GOLD
	var tag: Control
	if tag_text.is_empty():
		tag = Control.new()
	else:
		tag = ConquestTheme.chip(tag_text, tag_col, MenuTheme.FS_CAPTION)
	tag.name = "Status"
	tag.custom_minimum_size = Vector2(72, 0)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag)
	return p


## A rough fighting power: the species' stats x strength (only for the Threat pips).
static func power_of(chr: CharacterResource, strength: float) -> float:
	if chr == null:
		return 0.0
	return strength * float(chr.base_health + 2 * (chr.base_attack + chr.base_magic) + chr.base_defense)


func _lead_power() -> float:
	if state == null:
		return 0.0
	var lead: StoryPartyMember = null
	var healthy: Array[StoryPartyMember] = state.healthy_members()
	if not healthy.is_empty():
		lead = healthy[0]
	elif not state.party.is_empty():
		lead = state.party[0]
	if lead == null:
		return 0.0
	return power_of(CharacterLibrary.get_character(StringName(lead.character_id)), 1.0)


## 1..5: 3 = an even match with your lead.
static func _threat_pips(chr: CharacterResource, strength: float, lead_power: float) -> int:
	if lead_power <= 0.0 or chr == null:
		return 3
	var ratio: float = power_of(chr, strength) / lead_power
	if ratio < 0.7:
		return 1
	if ratio < 0.9:
		return 2
	if ratio < 1.1:
		return 3
	if ratio < 1.35:
		return 4
	return 5


func _fill_buttons() -> void:
	for c in _buttons_row.get_children():
		_buttons_row.remove_child(c)
		c.queue_free()
	_buttons.clear()
	var t := tournament
	var order: Array[Button] = []
	if TournamentLedger.is_running(state, t):
		var next: int = TournamentLedger.next_round(state, t) + 1
		var fight_text: String = "Fight the Final" if next == t.round_count() else "Fight Round %d" % next
		order.append(_add_button(RunTournamentCommand.ACTION_FIGHT, fight_text, MenuKit.PRIMARY, 240))
		order.append(_add_button(RunTournamentCommand.ACTION_WITHDRAW, "Withdraw", MenuKit.GHOST, 150))
		_status.text = "Your run: %d of %d bouts won. Your place is kept if you leave." \
			% [next - 1, t.round_count()]
	else:
		var can: Dictionary = TournamentLedger.can_enter(state, t)
		var enter := _add_button(RunTournamentCommand.ACTION_ENTER, "Enter  ·  %d G" % t.entry_fee, MenuKit.PRIMARY, 240)
		enter.disabled = not bool(can["ok"])
		order.append(enter)
		match String(can["reason"]):
			TournamentLedger.REASON_GOLD:
				_status.text = "The entry fee is %d gold -- you have %d." % [t.entry_fee, state.gold if state != null else 0]
			TournamentLedger.REASON_NO_PARTY:
				_status.text = "You need a partner who can fight."
			_:
				_status.text = "%d bouts, one after another. Lose one and the run is over." % t.round_count()
	order.append(_add_button(RunTournamentCommand.ACTION_LEAVE, "Leave", MenuKit.GHOST, 130))
	for i in range(order.size()):
		var b: Button = order[i]
		if i > 0:
			b.focus_neighbor_left = b.get_path_to(order[i - 1])
		if i < order.size() - 1:
			b.focus_neighbor_right = b.get_path_to(order[i + 1])
	for b in order:
		if not b.disabled:
			MenuNav.focus_deferred(b)
			break


func _add_button(action: String, text: String, variation: StringName, width: float) -> Button:
	var b := MenuKit.button(text, variation, width, 46)
	b.name = action.capitalize() + "Button"
	b.pressed.connect(func() -> void: choose(action))
	_buttons_row.add_child(b)
	_buttons[action] = b
	return b


func _input(event: InputEvent) -> void:
	if not _open or not event.is_pressed():
		return
	if MenuNav.is_back_event(event) or event.is_action_pressed(InputActions.MAP_MENU):
		get_viewport().set_input_as_handled()
		choose(RunTournamentCommand.ACTION_LEAVE)


func _exit_tree() -> void:
	if _root != null:
		_root.remove_from_group(InputActions.OVERLAY_GROUP)
