extends GutTest

## The post-move contextual action menu's LAYOUT (game/ui/panels/UnitActionMenu.gd).
##
## Mounts the REAL menu in a real tree, with the REAL long-named move resources
## (Bramble Cleave / Strangling Roots / Thornward / Refraction Lance) and the real
## ConquestTheme, and measures what it actually renders. Two shipped defects are pinned
## here, both of which looked fine to any test that only asked the menu what it intended:
##
##  1. DEAD SPACE. open_for_unit() rebuilt its rows with queue_free(), which leaves the old
##     rows in the tree (and in the VBox's minimum size) until the frame's delete queue
##     flushes -- after BOTH _reposition_to_unit() calls. The inflated minimum was baked
##     into _card.size, an explicit size nothing shrinks back, so from the second open
##     onward the card was 654px tall around 345px of content.
##
##  2. TRUNCATED NAMES. Every button was clip_text = true, which makes Button report a
##     minimum width of just its stylebox padding -- so the card sat at its 168px floor and
##     cut "Bramble Cleave" to "Bramble Cleav". Widths are therefore asserted against
##     FONT-MEASURED text, never against get_combined_minimum_size(), which a trimmed
##     control always under-reports (a trimmed Label reports 1px).
##
## Everything here is measured off the mounted nodes: card.size, button.size, and
## Font.get_string_size on the exact string the control is drawing.

const MENU_SCRIPT := preload("res://game/ui/panels/UnitActionMenu.gd")

const BRAMBLE := "res://game/combat/moves/bramble_cleave.tres"
const STRANGLING := "res://game/combat/moves/strangling_roots.tres"
const THORNWARD := "res://game/combat/moves/thornward.tres"
const REFRACTION := "res://game/combat/moves/refraction_lance.tres"

## Duck-typed MovesetController stand-in: the menu only ever asks can_use() / remaining().
class StubController extends RefCounted:
	var remaining_by_id: Dictionary = {}
	var unusable: Array = []

	func can_use(move) -> bool:
		return not (String(move.move_id) in unusable)

	func remaining(move) -> int:
		return int(remaining_by_id.get(String(move.move_id), 0))

## Duck-typed unit. Node3D because _reposition_to_unit() projects `_unit as Node3D`.
## get_stat("range_bonus") = 2 so the reach hint carries its "^+2" delta -- the widest
## form of the hint, which is the one the layout has to survive.
class StubUnit extends Node3D:
	var moves: Array = []
	var controller = null
	var actable: bool = true

	func get_moveset() -> Array:
		return moves

	func get_moveset_controller():
		return controller

	func can_act() -> bool:
		return actable

	func get_stat(_stat_name: String) -> int:
		return 2

var menu: Control
var unit: StubUnit
var controller: StubController


func before_each() -> void:
	menu = Control.new()
	menu.set_script(MENU_SCRIPT)
	add_child_autofree(menu)

	controller = StubController.new()
	# Thornward mid-recharge: the longest hint form, "(range 0-2 ^+2, CD 2/2)".
	controller.remaining_by_id = {"thornward": 2}

	unit = StubUnit.new()
	add_child_autofree(unit)
	unit.controller = controller
	unit.moves = [
		load(BRAMBLE), load(STRANGLING), load(THORNWARD), load(REFRACTION),
	]


func after_each() -> void:
	menu = null
	unit = null
	controller = null


# --- helpers ------------------------------------------------------------------

func _card() -> PanelContainer:
	return menu.get_node("Card") as PanelContainer


func _rows() -> VBoxContainer:
	return _card().get_node("Margin/Rows") as VBoxContainer


func _buttons(node: Node = null) -> Array:
	var out: Array = []
	var root: Node = node if node != null else _rows()
	for c in root.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out


func _hint_labels() -> Array:
	var out: Array = []
	for row in _rows().get_children():
		var hint := row.find_child("Hint", true, false)
		if hint != null:
			out.append(hint)
	return out


## Width of the exact string [param c] is drawing, in the font it is drawing it in.
func _text_width(c: Control) -> float:
	var font: Font = c.get_theme_font("font")
	var size: int = c.get_theme_font_size("font_size")
	return font.get_string_size(String(c.get("text")), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## The width inside [param btn] that its label may actually use.
func _drawable_width(btn: Button) -> float:
	return btn.size.x - btn.get_theme_stylebox("normal").get_minimum_size().x


func _open() -> void:
	menu.open_for_unit(unit, true)
	await get_tree().process_frame
	await get_tree().process_frame


# --- 1. the panel hugs its content --------------------------------------------

func test_card_is_exactly_its_content_plus_padding() -> void:
	await _open()
	var card := _card()
	var rows := _rows()
	var padding: float = float(menu.ROW_MARGIN * 2) + card.get_theme_stylebox("panel").get_minimum_size().y
	assert_almost_eq(card.size.y, rows.size.y + padding, 1.0,
		"the card's height is its rows plus the panel's own padding -- nothing else")
	assert_almost_eq(card.size.y, card.get_combined_minimum_size().y, 1.0,
		"a floating context menu is never taller than the minimum its rows need")


func test_no_dead_space_under_the_last_row() -> void:
	await _open()
	var rows := _rows()
	var lowest: float = 0.0
	for row in rows.get_children():
		lowest = maxf(lowest, (row as Control).position.y + (row as Control).size.y)
	assert_almost_eq(rows.size.y, lowest, 1.0,
		"the Cancel row ends where the rows box ends -- no empty amber below it")


func test_reopening_the_menu_never_stretches_the_card() -> void:
	await _open()
	var first: float = _card().size.y
	await _open()
	var second: float = _card().size.y
	await _open()
	var third: float = _card().size.y
	assert_eq(second, first,
		"REGRESSION: queue_free()d rows still counted toward the minimum, so the second " +
		"open baked the previous menu's height into the card on top of its own")
	assert_eq(third, first, "and it does not creep on any later open either")


func test_a_shorter_moveset_shrinks_the_card_back_down() -> void:
	await _open()
	var tall: float = _card().size.y
	unit.moves = [load(THORNWARD)]
	await _open()
	assert_lt(_card().size.y, tall,
		"dropping from four moves to one makes the menu smaller, not the same size")


# --- 2. names fit ---------------------------------------------------------------

func test_every_move_name_is_rendered_whole() -> void:
	await _open()
	var names := ["Bramble Cleave", "Strangling Roots", "Thornward", "Refraction Lance"]
	var seen: Array = []
	for btn in _buttons():
		seen.append(btn.text)
	for n in names:
		assert_true(n in seen, "the button is labelled with the move's WHOLE name: %s" % n)
	for btn in _buttons():
		assert_false(btn.clip_text,
			"'%s' fits inside the cap, so nothing about it is ellipsized" % btn.text)
		assert_gte(_drawable_width(btn), _text_width(btn),
			"'%s' has at least its own measured text width (%.0fpx) to draw in, got %.0fpx"
			% [btn.text, _text_width(btn), _drawable_width(btn)])


func test_the_range_and_cooldown_hint_moved_off_the_name() -> void:
	await _open()
	var hints := _hint_labels()
	assert_eq(hints.size(), 4, "each of the four moves carries its own hint caption")
	var thornward_hint := ""
	for h in hints:
		if "CD" in String(h.text):
			thornward_hint = String(h.text)
	assert_string_contains(thornward_hint, "CD 2/2",
		"a recharging move still reports how far through the wait it is")
	assert_string_contains(thornward_hint, "^+2",
		"and the boosted-reach delta still reads as a CHANGE, not a bare number")
	for btn in _buttons():
		assert_false("range" in btn.text,
			"'%s': the hint is a caption line now, never glued onto the name" % btn.text)


func test_every_hint_caption_fits_too() -> void:
	await _open()
	for h in _hint_labels():
		assert_false(h.clip_text,
			"the hint '%s' fits at caption size, so it is not ellipsized either" % h.text)
		assert_gte(h.size.x, _text_width(h),
			"the hint '%s' gets its measured %.0fpx, got %.0fpx"
			% [h.text, _text_width(h), h.size.x])


func test_a_caption_is_only_built_when_it_has_something_to_say() -> void:
	# Cleave has no authored cooldown, so with no controller there is no CD badge. Its
	# range caption still appears -- the point is that the caption is built per-move from
	# real content, never stamped as a blank row on every move.
	unit.moves = [load("res://game/combat/moves/cleave.tres")]
	unit.controller = null
	await _open()
	var hints := _hint_labels()
	assert_eq(hints.size(), 1, "the one move gets the one caption it has content for")
	assert_ne(String(hints[0].text), "", "and that caption is not an empty row")
	assert_string_contains(String(hints[0].text), "range",
		"a move with no cooldown still reports its reach")
	assert_false("CD" in String(hints[0].text),
		"but it never prints a cooldown badge it does not have")


func test_card_width_stays_inside_the_authored_cap() -> void:
	await _open()
	var w: float = _card().size.x
	assert_gte(w, menu.MENU_MIN_WIDTH, "the menu never collapses below its floor")
	assert_lte(w, menu.MENU_MAX_WIDTH,
		"a context menu that covers the board is a modal -- %.0fpx cap holds" % menu.MENU_MAX_WIDTH)
	assert_gt(w, menu.MENU_MIN_WIDTH,
		"and it DID grow past the floor to fit the real names (was stuck at the floor)")


func test_a_name_past_the_cap_ellipsizes_instead_of_widening_the_menu() -> void:
	var absurd = load(STRANGLING).duplicate()
	absurd.display_name = "Strangling Roots Of The Endlessly Verbose Understory Canopy"
	unit.moves = [absurd]
	await _open()
	assert_almost_eq(_card().size.x, menu.MENU_MAX_WIDTH, 1.0,
		"an over-long name pins the card to the cap rather than pushing past it")
	var clipped := false
	for btn in _buttons():
		if btn.text.begins_with("Strangling Roots Of"):
			clipped = btn.clip_text
	assert_true(clipped, "and THAT button, only, falls back to ellipsis")


# --- 3. placement ----------------------------------------------------------------

func test_the_menu_stays_on_screen_from_every_spawn_position() -> void:
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.current = true
	cam.position = Vector3(0, 12, 12)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	await get_tree().process_frame

	var view: Vector2 = menu.get_viewport().get_visible_rect().size
	var offscreen: Array = []  # lambdas capture by value; collect through a shared Array
	for x in [-40.0, -8.0, 0.0, 8.0, 40.0]:
		for z in [-40.0, -8.0, 0.0, 8.0, 40.0]:
			unit.global_position = Vector3(x, 0.0, z)
			await _open()
			var card := _card()
			var rect := Rect2(card.position, card.size)
			if rect.position.x < 0.0 or rect.position.y < 0.0 \
					or rect.end.x > view.x or rect.end.y > view.y:
				offscreen.append("(%.0f,%.0f) -> %s" % [x, z, str(rect)])
	assert_eq(offscreen, [],
		"the card is clamped fully inside the %s viewport from every spawn cell" % str(view))


func test_the_menu_fits_a_720p_screen() -> void:
	await _open()
	var card := _card()
	assert_lte(card.size.y, 720.0 - menu.SCREEN_MARGIN * 2.0,
		"a full four-move menu still fits between the 720p edges with its margins")
	assert_lte(card.size.x, 1280.0 - menu.SCREEN_MARGIN * 2.0,
		"and inside the width")


# --- 4. the rows kept working ------------------------------------------------------

func test_the_element_stripe_and_recharge_bar_survived_the_relayout() -> void:
	await _open()
	# Bramble Cleave / Strangling Roots / Thornward are nature; Refraction Lance is earth.
	var expected := ["nature", "nature", "nature", "earth"]
	var stripes: Array = []
	var bars: int = 0
	for row in _rows().get_children():
		for child in row.get_children():
			if child is ColorRect:
				stripes.append((child as ColorRect).color)
		var bar := row.find_child("RechargeBar", true, false)
		if bar != null:
			bars += 1
	assert_eq(stripes.size(), 4, "one element stripe per move row")
	for i in mini(stripes.size(), expected.size()):
		assert_eq(stripes[i], ConquestTheme.element_color(expected[i]),
			"row %d's stripe still reads that move's own element (%s)" % [i, expected[i]])
	# Strangling Roots (4), Thornward (2) and Refraction Lance (3) have authored cooldowns;
	# Bramble Cleave's is 0, and a move with nothing to recharge draws no bar at all.
	assert_eq(bars, 3, "a recharge bar on exactly the moves that have an authored cooldown")


func test_the_recharge_bar_still_reads_the_live_cooldown() -> void:
	await _open()
	var thornward_row: Control = null
	for row in _rows().get_children():
		for btn in _buttons(row):
			if btn.text == "Thornward":
				thornward_row = row
	assert_not_null(thornward_row, "the Thornward row is there to look at")
	var bar: ProgressBar = thornward_row.find_child("RechargeBar", true, false)
	assert_not_null(bar, "a move on cooldown draws its recharge bar")
	assert_almost_eq(bar.value, MoveStatVisuals.recharge_fraction(2, 2), 0.001,
		"2 of 2 turns still to wait reads as no progress at all")


func test_a_move_the_controller_refuses_is_still_disabled() -> void:
	controller.unusable = ["strangling_roots"]
	await _open()
	for btn in _buttons():
		if btn.text == "Strangling Roots":
			assert_true(btn.disabled, "an unusable move stays greyed out through the relayout")
		elif btn.text == "Bramble Cleave":
			assert_false(btn.disabled, "and a usable one stays pressable")


func test_choosing_a_move_still_emits_its_slot() -> void:
	await _open()
	# GUT lambdas capture by VALUE, so the slot is collected through a shared Array.
	var got: Array = []
	menu.connect("move_chosen", func(slot: int) -> void: got.append(slot))
	for btn in _buttons():
		if btn.text == "Refraction Lance":
			btn.emit_signal("pressed")
	assert_eq(got, [3],
		"the fourth row still reports slot 3 -- the caption line did not shift the indices")
