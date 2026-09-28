extends CanvasLayer
class_name EvolutionScreen

## The EVOLUTION MOMENT (docs/design/EVOLUTION.md §2.1, §5): a full-screen grove overlay that
## asks "Barkling is evolving...", plays the change on a turntable (white pulses, a burst, the
## new model) and reveals the result -- stat diff, new moves, new ability, the carried item.
##
##   PROMPT     ribbon "<Name> is evolving..." · from-crest | turntable | "?" crest
##              [Not now] [Evolve]            (several edges: pick one first)
##   ANIMATING  presentation only; the ledger is ALREADY committed
##   REVEAL     ribbon "<Name> evolved into <Form>!" · stat diff · new move / ability cards
##              [Continue]
##
## One entry point for every caller: Character Select today, the overworld's post-battle hook
## and the duel results card later (§6) -- [method open] then await [signal finished].
## [signal finished] fires EXACTLY ONCE per screen, whichever way it closes, so an awaiting
## caller can never hang (the UltimateCutIn contract), and the screen frees itself after.
##
## Pressing Evolve commits through [method RosterLedger.evolve] (or the story caller's
## [member commit], which evolves the journey's member record) SYNCHRONOUSLY; the animation
## only decorates a decided change, so closing mid-animation can never half-evolve a unit.
## Animations off (GameSettings) replace the sequence with one short static flash. Headless-
## safe: nothing here needs a renderer to reach [signal finished].
##
## Input: Esc / pad B = Not now (prompt) or Continue (reveal); Enter / pad A presses the
## focused button. Focus is trapped inside the overlay and handed back on close. While open the
## overlay is in [constant InputActions.OVERLAY_GROUP], so the overworld hero cannot walk behind it.
##
## PROMOTIONS (DECISIONS.md #8, #16): an edge whose [member EvolutionResource.kind_label] is
## "Promote" reads "<Name> is being promoted..." / [Promote] / "<Name> was promoted to <Class>!".

signal finished(evolved: bool, edge: EvolutionResource)

## Above menus and the in-battle HUD overlays, below the scene fade.
const OVERLAY_LAYER: int = 110
const CARD_WIDTH: float = 960.0
const PREVIEW_PX: float = 196.0
const CREST_PX: float = 72.0
const STATIC_FLASH: float = 0.15
## Over-bright modulate: every lit pixel of the model clamps to white (the silhouette).
const WHITE_OUT := Color(8.0, 8.0, 8.0, 1.0)
## Stat rows of the diff: [key, label].
const STAT_ROWS: Array = [
	["health", "HP"], ["attack", "Attack"], ["defense", "Defense"], ["magic", "Magic"],
	["magic_defense", "Resist"], ["speed", "Speed"], ["movement", "Move"],
]

enum Phase { PROMPT, ANIMATING, REVEAL, DONE }

var phase: int = Phase.PROMPT
var uid: String = ""
var edges: Array = []
## The edge being (or that was) taken; null until chosen when several are offered.
var chosen_edge: EvolutionResource = null
## {success, reason, item_moved, from, to} from the commit, {} before it.
var result: Dictionary = {}
## The commit call, edge -> {success, reason, item_moved, from, to}. Empty = open modes:
## [method RosterLedger.evolve] on [member uid]. The STORY overworld passes one that evolves
## the journey's own member record ([StoryGrowth.evolve]) -- the member BECOMES the form.
var commit: Callable = Callable()
## STORY: the member's equipped story-bag item (it always stays on the member), "" = none.
var carried_item_id: String = ""
## The member's own name for the ribbons ("Sprig is evolving..."); "" = the form's name.
var member_name: String = ""
## {edge id: item_id}: the bag item an edge SPENDS when taken ([UseItemTrigger]); shown on the
## prompt ("Uses one Sunstone.").
var use_items: Dictionary = {}

var _from: CharacterResource = null
var _to: CharacterResource = null
var _prev_focus: Control = null
var _tween: Tween = null

var _root: Control = null
var _ribbon: PanelContainer = null
var _preview: UnitPreview3D = null
## A soft radial glow behind the model (the pulse's halo).
var _glow: TextureRect = null
var _burst: _Burst = null
var _to_crest: PanelContainer = null
var _to_name: Label = null
var _to_tags: HBoxContainer = null
var _flavor: Label = null
var _branch_row: HBoxContainer = null
var _reveal_box: HBoxContainer = null
var _status: Label = null
## "Uses one Sunstone." under the flavour (an item-driven edge).
var _uses: Label = null
## "Not now keeps it: evolve later from Journey > Party." (story prompt).
var _later_hint: Label = null
var not_now_button: Button = null
var evolve_button: Button = null
var continue_button: Button = null


## Open the screen over [param parent] for member [param member_uid] with the offered
## [param offered_edges] (from [method RosterLedger.available_evolutions]). Await
## [signal finished] on the returned screen.
## [param p_commit] / [param p_item_id]: the STORY caller's commit and carried item (see
## [member commit]); omitted in open modes.
## [param p_use_items]: {edge id: item_id} the edge spends (see [member use_items]).
static func open(parent: Node, member_uid: String, offered_edges: Array,
		p_commit: Callable = Callable(), p_item_id: String = "", p_member_name: String = "",
		p_use_items: Dictionary = {}) -> EvolutionScreen:
	var screen := EvolutionScreen.new()
	screen.configure(member_uid, offered_edges)
	screen.commit = p_commit
	screen.carried_item_id = p_item_id
	screen.member_name = p_member_name
	screen.use_items = p_use_items
	parent.add_child(screen)
	return screen


## True when a story caller owns the commit (the member becomes the form).
func is_story() -> bool:
	return commit.is_valid()


## Who is evolving: the member's nickname when it has one ("Sprig"), else the form's name.
func _who() -> String:
	return member_name if not member_name.strip_edges().is_empty() else _from.display_name


## The edge whose words the screen uses (the chosen one, else the first offered).
func _word_edge() -> EvolutionResource:
	if chosen_edge != null:
		return chosen_edge
	return edges[0] if not edges.is_empty() else null


## "Evolve" / "Promote" for the action button.
func verb() -> String:
	var e: EvolutionResource = _word_edge()
	return e.verb() if e != null else "Evolve"


func configure(member_uid: String, offered_edges: Array) -> void:
	uid = member_uid
	edges.clear()
	for e in offered_edges:
		if e is EvolutionResource:
			edges.append(e)
	chosen_edge = edges[0] if edges.size() == 1 else null
	var from_id: StringName = (edges[0] as EvolutionResource).from_id if not edges.is_empty() \
		else RosterLedger.form_of(uid)
	_from = CharacterLibrary.get_character(from_id)
	_to = CharacterLibrary.get_character(chosen_edge.to_id) if chosen_edge != null else null


func _ready() -> void:
	layer = OVERLAY_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vp := get_viewport()
	_prev_focus = vp.gui_get_focus_owner() if vp != null else null
	_build()
	if edges.is_empty() or _from == null:
		# Nothing to offer: report "not evolved" rather than hang an awaiting caller --
		# deferred, so the caller has connected to finished by the time it fires.
		call_deferred(&"_finish", false)
		return
	_show_prompt()


# --- Actions (public so tests and callers can drive them) --------------------

## Evolve along the chosen edge: commit to the ledger, then play the change.
## Returns the [method RosterLedger.evolve] result ({} when there is nothing to confirm).
func confirm() -> Dictionary:
	if phase != Phase.PROMPT or chosen_edge == null:
		return {}
	if commit.is_valid():
		var r = commit.call(chosen_edge)
		result = r if r is Dictionary else {"success": false, "reason": "no_commit"}
	else:
		result = RosterLedger.evolve(uid, chosen_edge)
	if not bool(result.get("success", false)):
		MenuKit.set_status(_status, "Cannot evolve right now (%s)." % String(result.get("reason", "")), "warn")
		_status.visible = true
		return result
	phase = Phase.ANIMATING
	_set_buttons_for(Phase.ANIMATING)
	if _animations_on():
		_play_sequence()
	else:
		_play_static()
	return result


## "Not now": close without evolving. The offer stays open (nothing was written).
func decline() -> void:
	if phase != Phase.PROMPT:
		return
	_finish(false)


## Leave the reveal (or skip the rest of the animation straight to the end).
func dismiss() -> void:
	if phase == Phase.ANIMATING:
		_kill_tween()
		_show_reveal()
		return
	if phase == Phase.REVEAL:
		_finish(true)


## Pick [param edge] (branching lines): the prompt then names that form.
func choose(edge: EvolutionResource) -> void:
	if phase != Phase.PROMPT or not edges.has(edge):
		return
	chosen_edge = edge
	_to = CharacterLibrary.get_character(edge.to_id)
	evolve_button.disabled = false
	evolve_button.text = verb()
	_set_ribbon("%s %s" % [_who(), edge.progressive_text()])
	_refresh_prompt_notes(phase)
	_refresh_branch_row()


# --- Build -------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "EvolutionRoot"
	_root.theme = MenuTheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_to_group(InputActions.OVERLAY_GROUP)
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(MenuTheme.BG_DEEP, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var card := MenuKit.card(&"CrestCard")
	card.name = "EvolutionCard"
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	center.add_child(card)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, MenuTheme.SP_XL)
	pad.add_theme_constant_override("margin_top", MenuTheme.SP_XL)
	pad.add_theme_constant_override("margin_bottom", MenuTheme.SP_L)
	card.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.SP_M)
	pad.add_child(col)

	_ribbon = ConquestTheme.title_ribbon("", MenuTheme.GOLD_DK, MenuTheme.FS_HEADING)
	_ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_ribbon)

	# Stage: from | turntable | to.
	var stage := HBoxContainer.new()
	stage.name = "Stage"
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override("separation", MenuTheme.SP_XXL)
	col.add_child(stage)
	stage.add_child(_form_column(_from, true))

	var art := Control.new()
	art.name = "Art"
	art.custom_minimum_size = Vector2(PREVIEW_PX * 1.3, PREVIEW_PX)
	stage.add_child(art)
	_glow = TextureRect.new()
	_glow.name = "Glow"
	_glow.texture = _glow_texture()
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.modulate.a = 0.0
	art.add_child(_glow)
	_preview = UnitPreview3D.new()
	_preview.name = "Preview"
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.add_child(_preview)
	_burst = _Burst.new()
	_burst.name = "Burst"
	_burst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.add_child(_burst)

	stage.add_child(_form_column(null, false))

	_flavor = MenuKit.label("", &"DimLabel", true)
	_flavor.name = "Flavor"
	_flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_flavor)

	_branch_row = HBoxContainer.new()
	_branch_row.name = "Branches"
	_branch_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_branch_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	_branch_row.visible = false
	col.add_child(_branch_row)

	_reveal_box = HBoxContainer.new()
	_reveal_box.name = "Reveal"
	_reveal_box.add_theme_constant_override("separation", MenuTheme.SP_XL)
	_reveal_box.visible = false
	col.add_child(_reveal_box)

	_uses = MenuKit.label("", &"", true)
	_uses.name = "UsesItem"
	_uses.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_uses.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	_uses.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	_uses.visible = false
	col.add_child(_uses)

	_status = MenuKit.label("", &"")
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.visible = false
	col.add_child(_status)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", MenuTheme.SP_L)
	col.add_child(actions)
	not_now_button = MenuKit.button("Not now", MenuKit.GHOST, 170, 50)
	not_now_button.name = "NotNowButton"
	not_now_button.pressed.connect(decline)
	actions.add_child(not_now_button)
	evolve_button = MenuKit.button("Evolve", MenuKit.PRIMARY, 220, 50)
	evolve_button.name = "EvolveButton"
	evolve_button.pressed.connect(confirm)
	actions.add_child(evolve_button)
	continue_button = MenuKit.button("Continue", MenuKit.PRIMARY, 220, 50)
	continue_button.name = "ContinueButton"
	continue_button.pressed.connect(dismiss)
	actions.add_child(continue_button)
	_later_hint = MenuKit.label("", &"MutedLabel", true)
	_later_hint.name = "LaterHint"
	_later_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_later_hint.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	_later_hint.visible = false
	col.add_child(_later_hint)
	_trap_focus()


## Keep keyboard / pad focus inside the overlay: every edge of every button leads to another
## overlay control (or back to itself), never to the screen behind.
func _trap_focus() -> void:
	var first_branch: Control = _branch_row.get_child(0) as Control if _branch_row.get_child_count() > 0 else null
	for b in [not_now_button, evolve_button, continue_button]:
		var up: NodePath = first_branch.get_path() if first_branch != null and _branch_row.visible else b.get_path()
		b.focus_neighbor_top = up
		b.focus_neighbor_bottom = b.get_path()
		b.focus_next = b.get_path()
		b.focus_previous = b.get_path()
	not_now_button.focus_neighbor_left = not_now_button.get_path()
	not_now_button.focus_neighbor_right = evolve_button.get_path()
	not_now_button.focus_next = evolve_button.get_path()
	evolve_button.focus_neighbor_left = not_now_button.get_path()
	evolve_button.focus_neighbor_right = evolve_button.get_path()
	evolve_button.focus_previous = not_now_button.get_path()
	continue_button.focus_neighbor_left = continue_button.get_path()
	continue_button.focus_neighbor_right = continue_button.get_path()
	for i in range(_branch_row.get_child_count()):
		var card := _branch_row.get_child(i) as Control
		card.focus_neighbor_top = card.get_path()
		card.focus_neighbor_bottom = evolve_button.get_path()
		card.focus_neighbor_left = _branch_row.get_child(maxi(0, i - 1)).get_path()
		card.focus_neighbor_right = _branch_row.get_child(mini(_branch_row.get_child_count() - 1, i + 1)).get_path()


## A crest + name + element column. [param chr] null = the unknown target ("?").
func _form_column(chr: CharacterResource, is_from: bool) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "FromColumn" if is_from else "ToColumn"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size = Vector2(190, 0)
	v.add_theme_constant_override("separation", MenuTheme.SP_S)
	var crest := MenuKit.crest("?", MenuTheme.PANEL_SUNK, MenuTheme.GOLD_DK, CREST_PX)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(crest)
	var name_lbl := MenuKit.label("???", &"HeadingLabel")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_lbl)
	var tags := HBoxContainer.new()
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override("separation", 6)
	v.add_child(tags)
	if is_from:
		_fill_form(crest, name_lbl, tags, chr)
	else:
		_to_crest = crest
		_to_name = name_lbl
		_to_tags = tags
	return v


func _fill_form(crest: PanelContainer, name_lbl: Label, tags: HBoxContainer, chr: CharacterResource) -> void:
	for c in tags.get_children():
		tags.remove_child(c)
		c.free()
	if chr == null:
		MenuKit.set_crest(crest, "?", MenuTheme.PANEL_SUNK)
		name_lbl.text = "???"
		return
	var ecol: Color = MenuKit.element_color(String(chr.element))
	MenuKit.set_crest(crest, chr.display_name, ecol)
	name_lbl.text = chr.display_name
	var el_text: String = String(chr.element).capitalize() if chr.element != &"" else "Neutral"
	var gem := GroveGem.new()
	gem.color = ecol
	gem.custom_minimum_size = Vector2(12, 16)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tags.add_child(gem)
	tags.add_child(MenuKit.badge(el_text, ecol))
	tags.add_child(MenuKit.badge("Stage %s" % EvolutionDetailBlock._roman(EvolutionLibrary.stage_of(chr.character_id)), MenuTheme.GOLD))


# --- Phases --------------------------------------------------------------------

func _show_prompt() -> void:
	phase = Phase.PROMPT
	var we: EvolutionResource = _word_edge()
	_set_ribbon("%s %s" % [_who(), we.progressive_text() if we != null else "is evolving..."])
	_preview.show_character(_from)
	_fill_form(_to_crest, _to_name, _to_tags, null)
	var flavor: String = chosen_edge.flavor if chosen_edge != null else "It could grow in more than one direction."
	_flavor.text = flavor
	_flavor.visible = not flavor.is_empty()
	if edges.size() > 1:
		_branch_row.visible = true
		_refresh_branch_row()
	_set_buttons_for(Phase.PROMPT)


func _show_reveal() -> void:
	phase = Phase.REVEAL
	_preview.modulate = Color.WHITE
	_glow.modulate.a = 0.0
	_preview.show_character(_to)
	_fill_form(_to_crest, _to_name, _to_tags, _to)
	_set_ribbon("%s %s %s!" % [_who(), chosen_edge.past_text() if chosen_edge != null else "evolved into",
		_to.display_name])
	_flavor.visible = false
	_uses.visible = false
	_later_hint.visible = false
	_branch_row.visible = false
	_build_reveal()
	_reveal_box.visible = true
	_set_buttons_for(Phase.REVEAL)


func _set_buttons_for(p: int) -> void:
	not_now_button.visible = p == Phase.PROMPT
	evolve_button.visible = p == Phase.PROMPT
	evolve_button.disabled = chosen_edge == null
	evolve_button.text = verb()
	_refresh_prompt_notes(p)
	continue_button.visible = p == Phase.REVEAL
	if not is_inside_tree():
		return
	match p:
		Phase.PROMPT:
			call_deferred(&"_grab_if_live", evolve_button if chosen_edge != null else not_now_button)
		Phase.REVEAL:
			call_deferred(&"_grab_if_live", continue_button)


## The prompt's small print: the item the chosen edge spends, and (story) where to find the offer
## again after "Not now".
func _refresh_prompt_notes(p: int) -> void:
	var item_id: String = String(use_items.get(chosen_edge.id, "")) if chosen_edge != null else ""
	if item_id.is_empty() and chosen_edge == null and edges.size() > 1:
		for e in edges:
			if use_items.has((e as EvolutionResource).id):
				item_id = String(use_items[(e as EvolutionResource).id])
	var item: ItemResource = ItemLibrary.get_item(item_id) if not item_id.is_empty() else null
	_uses.text = ("Uses one %s %s from your bag." % [item.icon_hint, item.display_name]) if item != null else ""
	_uses.visible = p == Phase.PROMPT and item != null
	var we: EvolutionResource = _word_edge()
	_later_hint.text = "Not now keeps the offer: %s later from Journey > Party." % \
		(we.verb().to_lower() if we != null else "evolve")
	_later_hint.visible = p == Phase.PROMPT and is_story()


## The ribbon's text ("Sprig is evolving...") -- tests and tools.
func ribbon_text() -> String:
	var l := _ribbon.get_node_or_null("Text") as Label if _ribbon != null else null
	return l.text if l != null else ""


## The "Uses one Sunstone" line while shown, else "".
func uses_text() -> String:
	return _uses.text if _uses != null and _uses.visible else ""


## True while the story prompt's "evolve later from Journey > Party" hint is shown.
func later_hint_visible() -> bool:
	return _later_hint != null and _later_hint.visible


func _grab_if_live(c: Control) -> void:
	if phase != Phase.DONE and is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()


func _set_ribbon(text: String) -> void:
	var l := _ribbon.get_node_or_null("Text") as Label
	if l != null:
		l.text = text


func _refresh_branch_row() -> void:
	if _branch_row.get_child_count() > 0:
		# Already built: only the selection moves (never free a card from its own pressed signal).
		for i in range(mini(edges.size(), _branch_row.get_child_count())):
			(_branch_row.get_child(i) as Button).set_pressed_no_signal(edges[i] == chosen_edge)
		return
	for e in edges:
		var to_c: CharacterResource = CharacterLibrary.get_character(e.to_id)
		var parts := MenuKit.option_card(Vector2(220, 64), true)
		var b: Button = parts["button"]
		b.name = "Branch_" + String(e.id)
		MenuKit.accent_card(b, MenuKit.element_color(String(to_c.element if to_c != null else &"")))
		var content: VBoxContainer = parts["content"]
		content.add_child(MenuKit.label(to_c.display_name if to_c != null else String(e.to_id), &"SubheadingLabel"))
		var trig := MenuKit.label(e.describe_triggers(), &"DimLabel")
		trig.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		content.add_child(trig)
		MenuKit.ignore_mouse(b)
		b.set_pressed_no_signal(e == chosen_edge)
		b.pressed.connect(choose.bind(e))
		_branch_row.add_child(b)
	if is_inside_tree():
		_trap_focus()


## The REVEAL content: stat diff on the left; new moves, new ability and the item note on the
## right (scrolls when long).
func _build_reveal() -> void:
	for c in _reveal_box.get_children():
		_reveal_box.remove_child(c)
		c.free()

	var left := VBoxContainer.new()
	left.name = "StatDiff"
	left.add_theme_constant_override("separation", 2)
	left.custom_minimum_size = Vector2(300, 0)
	_reveal_box.add_child(left)
	left.add_child(MenuKit.section("Stats"))
	var grid := GridContainer.new()
	grid.name = "StatGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", MenuTheme.SP_M)
	grid.add_theme_constant_override("v_separation", 1)
	left.add_child(grid)
	for row in stat_diff(_from, _to):
		var name_l := MenuKit.label(String(row["label"]), &"DimLabel")
		name_l.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		name_l.custom_minimum_size = Vector2(80, 0)
		grid.add_child(name_l)
		var old_l := MenuKit.label(str(row["from"]), &"MutedLabel")
		old_l.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		old_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		old_l.custom_minimum_size = Vector2(36, 0)
		grid.add_child(old_l)
		var new_l := MenuKit.label("»  %d" % int(row["to"]), &"")
		new_l.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		new_l.add_theme_font_override("font", MenuTheme.bold_font())
		grid.add_child(new_l)
		var delta: int = int(row["delta"])
		var d_l := MenuKit.label(("+%d" % delta) if delta > 0 else (str(delta) if delta < 0 else ""), &"")
		d_l.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		d_l.add_theme_color_override("font_color", MenuTheme.SUCCESS if delta > 0 else MenuTheme.DANGER)
		grid.add_child(d_l)

	var scroll := ScrollContainer.new()
	scroll.name = "Gains"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 236)
	_reveal_box.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", MenuTheme.SP_S)
	scroll.add_child(right)

	var moves: Array = new_moves(_from, _to)
	if not moves.is_empty():
		right.add_child(MenuKit.section("New move" if moves.size() == 1 else "New moves"))
		for m in moves:
			right.add_child(UnitPageContent.build_move_card(m))
	var forgotten: Array = lost_moves(_from, _to)
	if not forgotten.is_empty():
		var names: PackedStringArray = []
		for m in forgotten:
			names.append(m.display_name)
		var lost_l := MenuKit.label("Replaces: " + ", ".join(names), &"MutedLabel", true)
		lost_l.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		right.add_child(lost_l)
	var abilities: Array = new_abilities(_from, _to)
	if not abilities.is_empty():
		right.add_child(MenuKit.section("New ability" if abilities.size() == 1 else "New abilities"))
		for a in abilities:
			right.add_child(UnitPageContent.build_ability_card(a))
	# Under the stats (always in view): the carried item and what the unlock means.
	var notes := VBoxContainer.new()
	notes.name = "Notes"
	notes.add_theme_constant_override("separation", 2)
	left.add_child(notes)
	var item: ItemResource = null
	if is_story():
		item = ItemLibrary.get_item(carried_item_id) if not carried_item_id.is_empty() else null
	elif bool(result.get("item_moved", false)):
		item = ItemInventory.equipped_resource(_to.character_id)
	if item != null:
		var note := MenuKit.label("%s %s carried over." % [item.icon_hint, item.display_name], &"", true)
		note.name = "ItemCarried"
		note.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		note.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
		notes.add_child(note)
	# Owner decision 2: in STORY the member itself becomes the new form (and the form unlocks for
	# the open modes); elsewhere evolving is an unlock and both forms stay pickable.
	var unlock_text: String = "%s joins your roster; %s stays pickable too." % [_to.display_name, _from.display_name]
	if is_story():
		unlock_text = "%s is now %s for the rest of your journey; %s is also unlocked in Skirmish." \
			% [_who(), _to.display_name, _to.display_name]
	var spent: Array = result.get("consumed", []) if result.get("consumed", []) is Array else []
	if not spent.is_empty():
		var spent_item: ItemResource = ItemLibrary.get_item(String(spent[0]))
		if spent_item != null:
			unlock_text += " The %s was used up." % spent_item.display_name
	var unlock := MenuKit.label(unlock_text, &"MutedLabel", true)
	unlock.name = "UnlockNote"
	unlock.custom_minimum_size = Vector2(300, 0)
	unlock.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	notes.add_child(unlock)


# --- Pure content diffs (tested directly) ----------------------------------------

## [{key, label, from, to, delta}] for the stats that matter on the reveal.
static func stat_diff(from_c: CharacterResource, to_c: CharacterResource) -> Array:
	var out: Array = []
	if from_c == null or to_c == null:
		return out
	for row in STAT_ROWS:
		var a: int = from_c.get_stat(String(row[0]))
		var b: int = to_c.get_stat(String(row[0]))
		out.append({ "key": row[0], "label": row[1], "from": a, "to": b, "delta": b - a })
	return out


## Moves the new form has that the old one did not (by move_id), in slot order.
static func new_moves(from_c: CharacterResource, to_c: CharacterResource) -> Array:
	return _moves_missing(to_c, from_c)


## Moves the old form had that the new one does not.
static func lost_moves(from_c: CharacterResource, to_c: CharacterResource) -> Array:
	return _moves_missing(from_c, to_c)


static func _moves_missing(have: CharacterResource, other: CharacterResource) -> Array:
	var out: Array = []
	if have == null or other == null:
		return out
	var ids: Dictionary = {}
	for m in other.moveset:
		if m != null:
			ids[m.move_id] = true
	for m in have.moveset:
		if m != null and not ids.has(m.move_id):
			out.append(m)
	return out


## Abilities the new form gains (by id).
static func new_abilities(from_c: CharacterResource, to_c: CharacterResource) -> Array:
	var out: Array = []
	if from_c == null or to_c == null:
		return out
	var ids: Dictionary = {}
	for a in from_c.abilities:
		if a != null:
			ids[a.id] = true
	for a in to_c.abilities:
		if a != null and not ids.has(a.id):
			out.append(a)
	return out


# --- Presentation ----------------------------------------------------------------

## The model pulses to a WHITE SILHOUETTE (an over-bright modulate clamps its pixels to white
## while the transparent background stays clear) in quickening beats under a halo, holds white
## for the swap, then the new form fades in from white with a burst.
func _play_sequence() -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for beat in [0.5, 0.36, 0.26, 0.18, 0.12]:
		_tween.tween_property(_preview, "modulate", WHITE_OUT, beat * 0.5)
		_tween.parallel().tween_property(_glow, "modulate:a", 0.85, beat * 0.5)
		_tween.tween_property(_preview, "modulate", Color.WHITE, beat * 0.5)
		_tween.parallel().tween_property(_glow, "modulate:a", 0.25, beat * 0.5)
	_tween.tween_property(_preview, "modulate", WHITE_OUT, 0.2)
	_tween.parallel().tween_property(_glow, "modulate:a", 1.0, 0.2)
	_tween.tween_interval(0.15)
	_tween.tween_callback(_swap_to_new_form)
	_tween.tween_property(_preview, "modulate", Color.WHITE, 0.55)
	_tween.parallel().tween_property(_glow, "modulate:a", 0.0, 0.7)
	_tween.tween_callback(_show_reveal)


## Animations off: one short static flash over an immediate reveal.
func _play_static() -> void:
	_show_reveal()
	_glow.modulate.a = 0.9
	_kill_tween()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_glow, "modulate:a", 0.0, STATIC_FLASH)


## A white radial halo (transparent at the rim), built once in code -- no texture assets.
static func _glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.95))
	g.set_color(1, Color(1, 0.96, 0.8, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 128
	t.height = 128
	return t


func _swap_to_new_form() -> void:
	_preview.show_character(_to)
	_fill_form(_to_crest, _to_name, _to_tags, _to)
	_burst.play(MenuKit.element_color(String(_to.element)))


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _animations_on() -> bool:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null and GameSettings.has_method("animations_on"):
		return GameSettings.animations_on()
	return true


func _finish(evolved: bool) -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	_kill_tween()
	if _prev_focus != null and is_instance_valid(_prev_focus) and _prev_focus.is_inside_tree():
		# Synchronous: the caller may rebuild its screen right after finished (freeing this
		# control), so a deferred grab could land on a node that has left the tree.
		_prev_focus.grab_focus()
	finished.emit(evolved, chosen_edge if evolved else null)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.DONE:
		return
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		if phase == Phase.PROMPT:
			decline()
		else:
			dismiss()


## An expanding element-coloured ring (the "burst" on the reveal). Presentation only.
class _Burst:
	extends Control

	var _t: float = 1.0
	var _color: Color = MenuTheme.GOLD

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func play(color: Color) -> void:
		_color = color
		_t = 0.0
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		_t = minf(1.0, _t + delta / 0.6)
		queue_redraw()
		if _t >= 1.0:
			set_process(false)

	func _draw() -> void:
		if _t >= 1.0:
			return
		var c := size * 0.5
		var r: float = lerpf(12.0, size.y * 0.7, _t)
		var a: float = 1.0 - _t
		draw_arc(c, r, 0.0, TAU, 64, Color(_color.lightened(0.4), a), 6.0 * a + 1.0, true)
		draw_arc(c, r * 0.72, 0.0, TAU, 48, Color(MenuTheme.GOLD_LITE, a * 0.7), 3.0 * a + 1.0, true)
