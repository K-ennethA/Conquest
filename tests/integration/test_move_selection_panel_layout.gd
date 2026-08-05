extends GutTest

## The SELECT MOVE modal's LAYOUT (game/ui/panels/MoveSelectionPanel.gd).
##
## Mounts the REAL panel in a real tree with the REAL long-named move resources and the
## real ConquestTheme, and measures what it actually renders. This is the same latent
## defect test_unit_action_menu_layout.gd pins on the contextual menu: every move button
## (and the boost caption) was clip_text = true, and a trimmed control reports a minimum
## width of just its padding (a trimmed Label reports 1px) -- so the 340px card looked
## correctly sized to every intent-level check while a longer label would have been cut
## mid-name. No shipped name overflows TODAY (the widest label measures ~229px of the
## ~275px of text room), which is exactly why the fit has to be pinned against a
## DELIBERATELY long crafted name before a real one ships.
##
## Widths are therefore asserted against FONT-MEASURED text
## (Font.get_string_size on the exact string the control draws), never against
## get_combined_minimum_size(). The crafted names are padded against the live themed
## font to hit pixel targets, so the tests do not depend on any particular font metrics.

const BRAMBLE := "res://game/combat/moves/bramble_cleave.tres"
const STRANGLING := "res://game/combat/moves/strangling_roots.tres"
const THORNWARD := "res://game/combat/moves/thornward.tres"
const REFRACTION := "res://game/combat/moves/refraction_lance.tres"

## Duck-typed unit: the panel only ever asks get_moveset() / get_moveset_controller(),
## plus get_stat() through MoveResource.range_bonus_of. Plain Node -- this modal never
## projects a world position. get_stat 0 = nothing boosted, so shipped-label tests are
## not polluted by boost captions.
class StubUnit extends Node:
	var moves: Array[MoveResource] = []
	var controller: MovesetController = null

	func get_moveset() -> Array[MoveResource]:
		return moves

	func get_moveset_controller() -> MovesetController:
		return controller

	func get_stat(_stat_name: String) -> int:
		return 0

## get_stat = 2: a live range bonus, so the boost caption ("Range 2 → 4 ^+2") renders.
class BoostedStubUnit extends StubUnit:
	func get_stat(_stat_name: String) -> int:
		return 2

var panel: MoveSelectionPanel
var unit: StubUnit
var controller: MovesetController


func before_each() -> void:
	panel = MoveSelectionPanel.new()
	add_child_autofree(panel)

	unit = StubUnit.new()
	add_child_autofree(unit)
	controller = MovesetController.new()
	unit.add_child(controller)  # freed with the unit
	unit.controller = controller
	unit.moves = [
		load(BRAMBLE), load(STRANGLING), load(THORNWARD), load(REFRACTION),
	]


func after_each() -> void:
	panel = null
	unit = null
	controller = null


# --- helpers ------------------------------------------------------------------

func _card() -> PanelContainer:
	return panel.get_node("Center/Card") as PanelContainer


func _open() -> void:
	panel.show_moves_for_unit(unit)
	await get_tree().process_frame
	await get_tree().process_frame


## Width of the exact string [param c] is drawing, in the font it is drawing it in.
func _text_width(c: Control) -> float:
	return _width_of(c, String(c.get("text")))


func _width_of(c: Control, text: String) -> float:
	var font: Font = c.get_theme_font("font")
	var size: int = c.get_theme_font_size("font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## The width inside [param btn] that its label may actually use.
func _drawable_width(btn: Button) -> float:
	return btn.size.x - btn.get_theme_stylebox("normal").get_minimum_size().x


## Every VISIBLE hint caption (the line a demoted "(range ...)" hint lands on).
func _visible_hint_captions() -> Array:
	var out: Array = []
	for btn in panel.move_buttons:
		var caption: Label = btn.get_parent().find_child("HintCaption", true, false)
		if caption != null and caption.visible:
			out.append(caption)
	return out


## Pad [param seed_name] with characters until "<name><tail>" measures at least
## [param target_px] in [param proto]'s themed font -- one character at a time, so the
## result lands just past the target instead of far past it. Measuring the live font
## keeps these fixtures meaningful on any font the theme ships.
func _padded_name(proto: Control, seed_name: String, tail: String, target_px: float) -> String:
	var padded := seed_name
	while _width_of(proto, padded + tail) < target_px:
		padded += "w"
	return padded


## Open once with the shipped moveset just to get a real themed button to measure
## crafted names against.
func _proto_button() -> Button:
	panel.show_moves_for_unit(unit)
	return panel.move_buttons[0]


# --- 1. shipped labels render whole, inline, at the preferred width ---------------

func test_every_shipped_label_is_rendered_whole() -> void:
	controller.restore_state({"cooldowns": {"thornward": 2}})
	await _open()
	var names := ["Bramble Cleave", "Strangling Roots", "Thornward", "Refraction Lance"]
	assert_eq(panel.move_buttons.size(), 4, "all four shipped moves get a button")
	for i in panel.move_buttons.size():
		var btn: Button = panel.move_buttons[i]
		assert_true(btn.text.begins_with(names[i]),
			"button %d starts with the move's WHOLE name (%s), got '%s'" % [i, names[i], btn.text])
		assert_true("(range" in btn.text,
			"'%s': a hint that fits stays INLINE on the button" % btn.text)
		assert_false(btn.clip_text,
			"'%s' fits inside the cap, so nothing about it is ellipsized" % btn.text)
		assert_gte(_drawable_width(btn), _text_width(btn),
			"'%s' has at least its own measured text width (%.0fpx) to draw in, got %.0fpx"
			% [btn.text, _text_width(btn), _drawable_width(btn)])
	assert_eq(_visible_hint_captions().size(), 0,
		"no shipped hint needs the caption line -- it only exists for longer names")


func test_shipped_names_keep_the_card_at_its_preferred_width() -> void:
	await _open()
	assert_almost_eq(_card().size.x, panel.CARD_WIDTH, 1.0,
		"every shipped label fits the authored %.0fpx card -- growth is reserved for " % panel.CARD_WIDTH +
		"labels that genuinely need it")


func test_a_recharging_move_reports_its_cooldown_inline() -> void:
	controller.restore_state({"cooldowns": {"thornward": 2}})
	await _open()
	var thornward: Button = panel.move_buttons[2]
	assert_string_contains(thornward.text, "(CD 2/2)",
		"a recharging move still says how far through the wait it is")
	assert_gte(_drawable_width(thornward), _text_width(thornward),
		"and the suffix did not push the name past its drawable width")


func test_a_uses_limited_move_reports_its_charges_inline() -> void:
	# The exact future label the 340px card was one long name away from clipping:
	# a "(n/m uses)" suffix on top of the name and range.
	var limited: MoveResource = load(BRAMBLE).duplicate()
	limited.max_uses = 3
	controller.restore_state({"uses_spent": {"bramble_cleave": 1}})
	unit.moves = [limited]
	await _open()
	var btn: Button = panel.move_buttons[0]
	assert_string_contains(btn.text, "(2/3 uses)",
		"a uses-limited move reports its remaining charges on the button")
	assert_false(btn.clip_text, "the suffix fits inline, so nothing is ellipsized")
	assert_gte(_drawable_width(btn), _text_width(btn),
		"'%s' is rendered whole, suffix included" % btn.text)


# --- 2. longer names: grow, then demote the hint, then (only then) ellipsize ------

func test_a_longer_name_grows_the_card_instead_of_clipping() -> void:
	var proto := _proto_button()
	# Inline text ~330px: past the ~275px the preferred card offers, comfortably under
	# the cap -- the card must GROW rather than clip, and the hint must stay inline.
	var long_move: MoveResource = load(THORNWARD).duplicate()
	long_move.display_name = _padded_name(proto, "Thornward of the Verdant", " (range 0-2)", 330.0)
	unit.moves = [long_move]
	await _open()
	var btn: Button = panel.move_buttons[0]
	assert_gt(_card().size.x, panel.CARD_WIDTH,
		"a name the preferred width cannot hold grows the card")
	assert_lte(_card().size.x, panel.CARD_MAX_WIDTH,
		"but never past the %.0fpx cap" % panel.CARD_MAX_WIDTH)
	assert_true("(range" in btn.text,
		"the hint still fits inline at the grown width, so it stays on the button")
	assert_false(btn.clip_text, "nothing is ellipsized inside the cap")
	assert_gte(_drawable_width(btn), _text_width(btn),
		"the crafted name '%s' is rendered whole (needs %.0fpx, got %.0fpx)"
		% [btn.text, _text_width(btn), _drawable_width(btn)])


func test_an_inline_hint_that_cannot_fit_demotes_to_a_caption_line() -> void:
	var proto := _proto_button()
	# Name alone ~335px: fits inside the cap, but name + "(range ...) (CD 2/4)" does
	# not -- so the hint must move DOWN to the caption line, and the name (the part the
	# player is reading) must keep the whole width, unclipped.
	var long_move: MoveResource = load(STRANGLING).duplicate()
	var crafted := _padded_name(proto, "Strangling Roots of the", "", 335.0)
	long_move.display_name = crafted
	controller.restore_state({"cooldowns": {"strangling_roots": 2}})
	unit.moves = [long_move]
	await _open()
	var btn: Button = panel.move_buttons[0]
	assert_eq(btn.text, crafted,
		"the button carries the bare name -- the hint is no longer glued onto it")
	assert_false(btn.clip_text,
		"the name alone fits inside the cap, so it is not ellipsized")
	assert_gte(_drawable_width(btn), _text_width(btn),
		"the crafted name is rendered whole (needs %.0fpx, got %.0fpx)"
		% [_text_width(btn), _drawable_width(btn)])
	var captions := _visible_hint_captions()
	assert_eq(captions.size(), 1, "the demoted hint landed on its caption line")
	var caption: Label = captions[0]
	assert_string_contains(String(caption.text), "range",
		"the caption still reports the move's reach")
	assert_string_contains(String(caption.text), "CD 2/4",
		"and its cooldown -- nothing the inline form said is lost")
	assert_false(caption.clip_text, "the caption fits at caption size, so it is whole too")
	assert_gte(caption.size.x, _text_width(caption),
		"the caption '%s' gets its measured %.0fpx, got %.0fpx"
		% [caption.text, _text_width(caption), caption.size.x])


func test_a_name_past_the_cap_ellipsizes_only_as_last_resort() -> void:
	var proto := _proto_button()
	# Name alone ~600px: no width inside the cap can hold it, so ellipsis -- on THAT
	# button only, after the hint has already been demoted off it.
	var absurd: MoveResource = load(STRANGLING).duplicate()
	absurd.display_name = _padded_name(proto, "Strangling Roots of the Endlessly Verbose", "", 600.0)
	unit.moves = [absurd]
	await _open()
	assert_almost_eq(_card().size.x, panel.CARD_MAX_WIDTH, 1.0,
		"an over-long name pins the card to the cap rather than pushing past it")
	var btn: Button = panel.move_buttons[0]
	assert_true(btn.clip_text, "and that button, only, falls back to ellipsis")
	assert_eq(_visible_hint_captions().size(), 1,
		"the hint was still demoted first, so the ellipsis eats hint-free name text")


# --- 3. the boost caption is measured too ----------------------------------------

func test_the_boost_caption_is_rendered_whole() -> void:
	var boosted := BoostedStubUnit.new()
	add_child_autofree(boosted)
	boosted.controller = controller
	boosted.moves = [load(THORNWARD)]
	panel.show_moves_for_unit(boosted)
	await get_tree().process_frame
	await get_tree().process_frame
	var caption: Label = panel.move_buttons[0].get_parent().find_child("BoostCaption", true, false)
	assert_not_null(caption, "a live range bonus draws its boost caption")
	assert_string_contains(String(caption.text), "Range",
		"and it names the stat that changed")
	assert_false(caption.clip_text,
		"the caption fits, so it is not ellipsized (it used to be clip_text from birth)")
	assert_gte(caption.size.x, _text_width(caption),
		"the boost caption '%s' gets its measured %.0fpx, got %.0fpx"
		% [caption.text, _text_width(caption), caption.size.x])


# --- 4. the rebuild and the wiring kept working -----------------------------------

func test_reopening_does_not_stack_ghost_rows() -> void:
	await _open()
	panel.show_moves_for_unit(unit)
	# BEFORE any frame flushes the delete queue: queue_free()d rows must already be out
	# of the container, or this populate briefly lays out on top of the last one.
	assert_eq(panel.get_node("Center/Card").find_child("MovesContainer", true, false).get_child_count(), 4,
		"the old rows are REMOVED on the spot, not left as ghosts until end of frame")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(panel.move_buttons.size(), 4, "and the fresh rows are all there")


func test_choosing_a_move_still_emits_its_slot() -> void:
	await _open()
	# GUT lambdas capture by VALUE, so the slot is collected through a shared Array.
	var got: Array = []
	panel.move_selected.connect(func(slot: int) -> void: got.append(slot))
	panel.move_buttons[3].emit_signal("pressed")
	assert_eq(got, [3],
		"the fourth row still reports slot 3 -- the fit pass did not shift the indices")
