class_name DuelStub
extends CanvasLayer

## THE DEBUG DUEL STUB (docs/design/OVERWORLD.md §5 task 6). Until feat/duel registers the real
## launcher with [DuelLauncher], a tall-grass encounter (or a scripted StartDuel) opens this
## small grove panel over the overworld: the foe, and buttons that END the duel --
##   Win · Win (befriend) · Lose · Flee
## It speaks the SAME contract the real duel will: it builds a [BattleResult] and calls
## StoryController.report_battle_result EXACTLY ONCE, never writes the story save, and never
## changes scene itself (StoryController does, on the way back to the overworld).
##
## "Win" rolls the befriend offer the way the real duel must -- deterministically off the
## battle's seed (EncounterRoller.befriend_offered), never randf(); "Win (befriend)" forces an
## offer so the whole collect loop is testable end to end.
##
## Registered by StoryController in DEBUG builds only; a release build without the real duel
## simply has no wild encounters (DuelLauncher.launch fails and the grass stays quiet).

const LAYER_INDEX: int = 130
const NODE_NAME := "DuelStub"

signal resolved(result: BattleResult)

var request: BattleRequest = null
var join_chance: float = 0.35
var _done: bool = false
var _buttons: Array[Button] = []


## The [DuelLauncher] entry point: mount a stub panel for [param p_request] on the tree root.
static func launch(p_request: BattleRequest) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return {"success": false, "reason": "no_tree"}
	var old := tree.root.get_node_or_null(NODE_NAME)
	if old != null:
		old.queue_free()
	var stub := DuelStub.new()
	stub.request = p_request
	var ctrl := tree.root.get_node_or_null("StoryController")
	if ctrl != null and ctrl.has_method("ruleset"):
		var rs = ctrl.ruleset()
		if rs != null:
			stub.join_chance = float(rs.befriend_join_chance)
	tree.root.add_child(stub)
	stub.name = NODE_NAME
	return {"success": true, "reason": ""}


## PURE: the result this stub reports for [param outcome] ("victory"/"defeat"/"fled").
## [param force_offer] makes a won wild duel offer to join regardless of the roll.
static func build_result(p_request: BattleRequest, outcome: String, force_offer: bool,
		p_join_chance: float) -> BattleResult:
	var r := BattleResult.make(p_request.encounter_id, outcome)
	r.turns = 3
	# The lead healthy member fought: a win costs a little HP, a loss KOs it. The bench keeps
	# its HP (DUEL_BATTLE.md §8.3).
	var lead_done: bool = false
	for p in p_request.party:
		var hp: int = int(p.get("current_hp", StoryPartyMember.HP_FULL))
		var entry: Dictionary = {"member_id": String(p.get("member_id", "")), "current_hp": hp, "wounded": false,
			"fought": false, "kos": 0}
		if not lead_done and hp != 0:
			lead_done = true
			entry["fought"] = true
			entry["kos"] = 1 if outcome == BattleResult.OUTCOME_VICTORY else 0
			var c: CharacterResource = CharacterLibrary.get_character(StringName(String(p.get("character_id", ""))))
			var max_hp: int = c.base_health if c != null else 100
			var cur: int = max_hp if hp == StoryPartyMember.HP_FULL else hp
			match outcome:
				BattleResult.OUTCOME_VICTORY:
					entry["current_hp"] = maxi(1, cur - int(max_hp * 0.2))
				BattleResult.OUTCOME_DEFEAT:
					entry["current_hp"] = 0
					entry["wounded"] = true
		r.party_after.append(entry)
	if outcome == BattleResult.OUTCOME_VICTORY:
		var foe: String = p_request.lead_foe_id()
		if not foe.is_empty():
			r.defeated.append(foe)
		# A crit KO never forfeits a befriend: the offer is rolled on VICTORY (DECISIONS.md).
		# A STORY-CRITICAL recruit always offers (it must be non-missable).
		if not foe.is_empty() and p_request.can_befriend():
			if force_offer or p_request.is_story_critical() \
					or EncounterRoller.befriend_offered(p_request.seed, p_join_chance):
				r.befriend_offer = {"character_id": foe, "accepted": false}
	return r


## End the duel with [param outcome]. Reports exactly once; later calls are ignored.
func resolve(outcome: String, force_offer: bool = false) -> void:
	if _done or request == null:
		return
	_done = true
	var result: BattleResult = build_result(request, outcome, force_offer, join_chance)
	resolved.emit(result)
	var ctrl := get_node_or_null("/root/StoryController")
	if ctrl != null and ctrl.has_method("report_battle_result"):
		ctrl.report_battle_result(result)
	queue_free()


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var root := Control.new()
	root.name = "StubRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = MenuTheme.build()
	root.add_to_group(InputActions.OVERLAY_GROUP)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(MenuTheme.BG_DEEP, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(460, 0)
	var sb := MenuTheme.card_box(MenuTheme.PANEL, MenuTheme.GOLD_DK)
	sb.crest = true
	sb.set_content_margin_all(24)
	sb.content_margin_top = 28
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.SP_M)
	card.add_child(col)

	var ribbon := ConquestTheme.title_ribbon("A WILD DUEL", MenuTheme.GOLD_DK, MenuTheme.FS_SUBHEADING)
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ribbon)

	var foe := MenuKit.label(request.opponent_name() if request != null else "?", &"SubheadingLabel")
	foe.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foe)

	var lead_name: String = ""
	if request != null and not request.party.is_empty():
		var c: CharacterResource = CharacterLibrary.get_character(StringName(String(request.party[0].get("character_id", ""))))
		lead_name = c.display_name if c != null else ""
	var note := MenuKit.label("Debug duel stub -- the real 1v1 duel arrives from feat/duel.\n%s steps forward." % lead_name, &"DimLabel", true)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	col.add_child(note)

	col.add_child(GroveRule.new())

	_add_button(col, "Win", MenuKit.PRIMARY, func() -> void: resolve(BattleResult.OUTCOME_VICTORY))
	if request != null and request.can_befriend():
		_add_button(col, "Win (befriend)", &"", func() -> void: resolve(BattleResult.OUTCOME_VICTORY, true))
	_add_button(col, "Lose", &"", func() -> void: resolve(BattleResult.OUTCOME_DEFEAT))
	if request != null and request.can_flee():
		_add_button(col, "Flee", MenuKit.GHOST, func() -> void: resolve(BattleResult.OUTCOME_FLED))
	if not _buttons.is_empty():
		MenuNav.focus_deferred(_buttons[0])


func _add_button(col: VBoxContainer, text: String, variation: StringName, cb: Callable) -> void:
	var b := MenuKit.button(text, variation, 0, 46)
	b.pressed.connect(cb)
	MenuNav.hover_focus(b)
	col.add_child(b)
	_buttons.append(b)


func buttons() -> Array[Button]:
	return _buttons
