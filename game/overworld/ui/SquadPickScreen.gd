class_name SquadPickScreen
extends CanvasLayer

## THE DEPLOY PICKER before a story TACTICAL battle (docs/design/HUMANS.md "Deploying"): the
## fieldable party (hero first) and any guest the battle offers, as toggle cards; up to the
## battle's squad size; the hero locked in when the battle requires him. A view only -- every rule
## is [SquadPick]'s. StoryController opens it and awaits [signal confirmed] (the picked ids, in
## pick order). There is no "back": the battle was already committed to by the story (a scripted
## fight must not be skipped), so the picker only decides WHO goes.
##
## Grove look (docs/UI_STYLE.md): veil, gold-framed card, a ribbon title. Keyboard / pad: the
## cards and the Deploy button are focusable; Confirm toggles / presses.

const NODE_NAME := "SquadPickScreen"
const LAYER_INDEX: int = 130

signal confirmed(picks: Array)

var _cands: Array = []
var _squad_size: int = 3
var _picks: Array[String] = []
var _title: String = ""
var _root: Control = null
var _cards: Dictionary = {}
var _count_label: Label = null
var _go: Button = null
var _done: bool = false


## Open the picker under [param parent].
static func open(parent: Node, cands: Array, squad_size: int, title: String = "") -> SquadPickScreen:
	var s := SquadPickScreen.new()
	s.name = NODE_NAME
	s._cands = cands
	s._squad_size = maxi(1, squad_size)
	s._picks = SquadPick.default_picks(cands, squad_size)
	s._title = title
	parent.add_child(s)
	return s


func picks() -> Array[String]:
	return _picks.duplicate()


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "SquadPickRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = ConquestTheme.build()
	_root.add_to_group(InputActions.OVERLAY_GROUP)
	add_child(_root)

	var veil := ColorRect.new()
	veil.color = Color(MenuTheme.BG_DEEP, 0.8)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var card := PanelContainer.new()
	card.name = "SquadCard"
	card.custom_minimum_size = Vector2(560, 0)
	var sb := MenuTheme.card_box(MenuTheme.PANEL, MenuTheme.GOLD_DK)
	sb.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", sb)
	ConquestTheme.keep_style(card)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.SP_M)
	card.add_child(col)
	var ribbon := ConquestTheme.title_ribbon("DEPLOY", MenuTheme.GOLD_DK, MenuTheme.FS_HEADING)
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ribbon)
	if not _title.is_empty():
		var sub := MenuKit.label(_title, &"DimLabel", true)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)
	_count_label = MenuKit.label("", &"SubheadingLabel")
	_count_label.name = "Count"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_count_label)

	var list := VBoxContainer.new()
	list.name = "Candidates"
	list.add_theme_constant_override("separation", 6)
	col.add_child(list)
	var first: Button = null
	for c in _cands:
		var b := Button.new()
		b.name = "Pick_" + String(c["id"]).replace(":", "_").replace("#", "_")
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(500, 44)
		b.text = _card_text(c)
		b.pressed.connect(_on_card_pressed.bind(String(c["id"])))
		list.add_child(b)
		_cards[String(c["id"])] = b
		if first == null:
			first = b

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", MenuTheme.SP_L)
	col.add_child(row)
	_go = MenuKit.button("Deploy", MenuKit.PRIMARY, 200)
	_go.name = "DeployButton"
	_go.pressed.connect(confirm)
	row.add_child(_go)
	_refresh()
	MenuNav.focus_deferred(first if first != null else _go)


static func _card_text(c: Dictionary) -> String:
	var tags: PackedStringArray = []
	if bool(c.get("hero", false)):
		tags.append("Hero")
	if String(c.get("kind", "")) == "human":
		tags.append("Human")
	if bool(c.get("guest", false)):
		tags.append("Guest")
	if bool(c.get("required", false)):
		tags.append("Required")
	return "%s  ·  Lv %d%s" % [String(c.get("name", "?")), int(c.get("level", 1)),
		("  ·  " + " · ".join(tags)) if not tags.is_empty() else ""]


func _on_card_pressed(id: String) -> void:
	_picks = SquadPick.toggle(_picks, id, _cands, _squad_size)
	_refresh()


func _refresh() -> void:
	for id in _cards.keys():
		var b: Button = _cards[id]
		b.set_pressed_no_signal(_picks.has(String(id)))
		var c: Dictionary = SquadPick.find(_cands, String(id))
		b.disabled = bool(c.get("required", false))
	if _count_label != null:
		_count_label.text = "%d / %d deployed" % [_picks.size(), _squad_size]
	if _go != null:
		_go.disabled = not bool(SquadPick.validate(_picks, _cands, _squad_size)["ok"])


## Press a candidate (tests / pad).
func toggle(id: String) -> void:
	_on_card_pressed(id)


func confirm() -> void:
	if _done or not bool(SquadPick.validate(_picks, _cands, _squad_size)["ok"]):
		return
	_done = true
	confirmed.emit(_picks.duplicate())


func _unhandled_input(event: InputEvent) -> void:
	# Modal: nothing behind the card reacts to Back.
	if _root != null and _root.visible and MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _root != null:
		_root.remove_from_group(InputActions.OVERLAY_GROUP)
