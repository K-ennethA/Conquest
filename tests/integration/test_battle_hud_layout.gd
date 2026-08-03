extends GutTest

## Geometry regressions for the in-battle HUD.
##
## Every assertion here corresponds to something a player saw on screen:
##   * the BATTLE LOG chip drawn over the unit card's title;
##   * the unit portrait stacked on top of the stat rows, with the stat labels spilling
##     out from under it (a BoxContainer given less than its minimum distributes NEGATIVE
##     space -- the card was being budgeted below its own fixed content);
##   * the HP bar running past the card's right edge;
##   * the ABILITIES section cut off at the bottom of the card -- which is what the
##     compact-card redesign fixed by moving abilities to the full-screen
##     [UnitDetailPage] and PINNING the card at UnitInfoPanel.CARD_HEIGHT;
##   * the terrain card cut off at the bottom of the screen.
##
## Builds the REAL GameUILayout.tscn, so it is an integration test by tests/README's split.
##
## RESOLUTION: the suite asks the root window for the 1280x720 design size and then
## measures against whatever the viewport actually reports, so it is meaningful on a
## headless runner whose window is some other size. The exact 720p budget arithmetic is
## pinned separately, as pure statics, in unit/test_turn_banner_and_hud_budget.gd.

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")

const DESIGN := Vector2i(1280, 720)

var _prev_window_size: Vector2i


func before_all() -> void:
	var root := get_tree().root
	_prev_window_size = root.size
	root.size = DESIGN


func after_all() -> void:
	get_tree().root.size = _prev_window_size


## The live design-space viewport, which is what every anchor and container resolves
## against (canvas_items stretch), not the OS window size.
func _vp() -> Vector2:
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2(DESIGN)


func _make_unit() -> Unit:
	var character := CharacterResource.new()
	character.character_id = &"vineweave"
	character.display_name = "Torvald Ironhide"
	var unit := Unit.new()
	unit.character_resource = character
	add_child_autofree(unit)
	return unit


func _rect_of(node: Control) -> Rect2:
	return Rect2(node.global_position, node.size)


## Compact geometry dump. Kept because every bug this suite covers was diagnosed by
## reading a control's MINIMUM against the rect it was actually granted.
func _dump_tree(node: Node, depth: int) -> void:
	for child in node.get_children():
		if child is Control and child.visible:
			gut.p("    %s%-22s min=%s size=%s"
					% ["  ".repeat(depth + 1), child.name,
					child.get_combined_minimum_size(), child.size])
			if depth < 1:
				_dump_tree(child, depth + 1)


## Build the HUD and let every deferred re-budget / re-fit settle.
func _build_hud() -> Control:
	var layout: Control = LAYOUT.instantiate()
	add_child_autofree(layout)
	for i in range(8):
		await get_tree().process_frame
	gut.p("viewport    : %s" % _vp())
	return layout


func _select_unit(layout: Control) -> void:
	layout.unit_info_panel._on_unit_selected(_make_unit(), Vector3.ZERO)
	for i in range(8):
		await get_tree().process_frame


# --- The left column ---------------------------------------------------------

func test_the_battle_log_and_the_unit_card_never_overlap() -> void:
	var layout: Control = await _build_hud()
	await _select_unit(layout)

	var log_rect: Rect2 = _rect_of(layout.battle_log)
	var card_rect: Rect2 = _rect_of(layout.unit_info_panel)

	gut.p("battle log  : %s" % log_rect)
	gut.p("unit card   : %s" % card_rect)

	assert_false(log_rect.intersects(card_rect),
			"the log owns the column's top row and the card stacks under it")
	assert_true(card_rect.position.y >= log_rect.end.y,
			"the card starts below the log, not on top of its title")


func test_the_expanded_log_still_cannot_reach_the_unit_card() -> void:
	var layout: Control = await _build_hud()
	await _select_unit(layout)

	# What the player does when they want to read the log.
	layout.battle_log._toggle_expanded()
	for i in range(8):
		await get_tree().process_frame

	var log_rect: Rect2 = _rect_of(layout.battle_log)
	var card_rect: Rect2 = _rect_of(layout.unit_info_panel)
	gut.p("expanded log: %s" % log_rect)
	gut.p("unit card   : %s" % card_rect)

	assert_false(log_rect.intersects(card_rect),
			"expanding the log can never push it over the card")

	# The compact card's dividend: the column can now afford BOTH at once, so the log
	# actually renders its scrollback instead of falling back to its chip.
	assert_true(layout.battle_log.is_showing_scrollback(),
			"and with the compact card there is room for the log's scrollback beside it")

	# ...and the pair still clears the terrain card's corner in that worst case.
	assert_true(card_rect.end.y <= _vp().y - UnitInfoPanel.BOTTOM_RESERVE + 0.5,
			"log + card together still stop short of the terrain card's band")


func test_the_unit_card_is_never_squeezed_below_its_fixed_rows() -> void:
	var layout: Control = await _build_hud()
	await _select_unit(layout)

	var card = layout.unit_info_panel
	var floor_h: float = card.fixed_content_height()
	gut.p("card height : %.1f  (fixed-content floor %.1f, top y %.1f)"
			% [card.size.y, floor_h, card.global_position.y])

	assert_true(card.size.y >= floor_h - 0.5,
			"the card is at least as tall as its own fixed rows")

	var vbox := card.get_node("MarginContainer/VBoxContainer") as VBoxContainer
	assert_true(vbox.size.y >= vbox.get_combined_minimum_size().y - 0.5,
			"so the inner VBox never distributes negative space (portrait over stats)")


func test_the_unit_card_is_pinned_to_its_declared_height() -> void:
	# The whole left-column budget (see unit/test_turn_banner_and_hud_budget.gd) is spent
	# against UnitInfoPanel.CARD_HEIGHT as a CONSTANT. If the real card ever measures
	# taller than the pin -- a font-metric change, a row someone added -- the arithmetic
	# silently stops being true, and this is the assertion that catches it.
	var layout: Control = await _build_hud()
	await _select_unit(layout)

	var card = layout.unit_info_panel
	var vbox := card.get_node("MarginContainer/VBoxContainer") as VBoxContainer
	gut.p("card pin    : %.1f   measured content+chrome: %.1f   actual: %.1f"
			% [UnitInfoPanel.CARD_HEIGHT,
			vbox.get_combined_minimum_size().y + UnitInfoPanel.CHROME_HEIGHT, card.size.y])
	_dump_tree(vbox, 0)

	assert_eq(card.fixed_content_height(), UnitInfoPanel.CARD_HEIGHT,
			"the card's real content fits the height the column budgets for it")
	assert_true(card.size.y <= UnitInfoPanel.CARD_HEIGHT + 0.5,
			"and the card on screen is exactly that tall, never taller")


func test_the_card_shows_no_ability_or_move_list_at_all() -> void:
	# The reported bug was "the Abilities section is STILL cut off". The fix was not a
	# taller card -- it was removing the section: abilities and moves live on the
	# full-screen UnitDetailPage now, reachable from the card's DETAILS chip.
	var layout: Control = await _build_hud()
	await _select_unit(layout)

	var card = layout.unit_info_panel
	for name in ["AbilitiesScroll", "AbilitiesContainer", "AbilitiesLabel",
			"AbilitiesSeparator", "MoveList"]:
		assert_null(card.find_child(name, true, false),
				"%s is gone from the compact card" % name)

	assert_not_null(card.find_child("DetailsButton", true, false),
			"and the DETAILS affordance that replaced them is present")


func test_the_portrait_row_and_the_stat_chips_do_not_overlap() -> void:
	var layout: Control = await _build_hud()
	await _select_unit(layout)

	var card = layout.unit_info_panel
	var portrait := card.get_node("MarginContainer/VBoxContainer/PortraitContainer") as Control
	var chips := card.get_node("MarginContainer/VBoxContainer/StatChips") as Control
	gut.p("portrait    : %s" % _rect_of(portrait))
	gut.p("stat chips  : %s" % _rect_of(chips))

	assert_false(_rect_of(portrait).intersects(_rect_of(chips)),
			"the portrait plate never sits on top of the stat chips")


func test_every_card_row_stays_inside_the_cards_frame() -> void:
	var layout: Control = await _build_hud()
	await _select_unit(layout)

	var card = layout.unit_info_panel
	var card_rect: Rect2 = _rect_of(card)
	gut.p("card rect   : %s" % card_rect)
	gut.p("left column : %s" % _rect_of(layout.left_sidebar))
	var margin := card.get_node("MarginContainer") as Control
	gut.p("card margin : %s min=%s" % [_rect_of(margin), margin.get_combined_minimum_size()])
	# The margin container is anchored FULL RECT inside the card. If its minimum is wider
	# than the card it overflows the frame -- which is the bug this test exists for.
	assert_true(margin.get_combined_minimum_size().x <= card_rect.size.x + 0.5,
			"nothing inside the card demands more width than the column gives it")

	for path in ["PortraitContainer", "HealthRow", "HealthBar", "StatChips",
			"StatusStrip", "DetailsButton"]:
		var row := card.get_node("MarginContainer/VBoxContainer/" + path) as Control
		var row_rect: Rect2 = _rect_of(row)
		assert_true(row_rect.position.x >= card_rect.position.x,
				"%s starts inside the card's left edge" % path)
		assert_true(row_rect.end.x <= card_rect.end.x + 0.5,
				"%s ends inside the card's right edge" % path)
		assert_true(row_rect.end.y <= card_rect.end.y + 0.5,
				"%s ends inside the card's bottom edge -- nothing is cut off" % path)


func test_the_unit_card_stays_clear_of_the_terrain_cards_corner() -> void:
	var layout: Control = await _build_hud()
	await _select_unit(layout)

	var card = layout.unit_info_panel
	var card_rect: Rect2 = _rect_of(card)
	# The reserve yields to the card's fixed rows and never the other way round, so the
	# ceiling is whichever of the two is larger (see UnitInfoPanel.height_budget).
	var allowed: float = maxf(_vp().y - UnitInfoPanel.BOTTOM_RESERVE,
			card_rect.position.y + card.fixed_content_height())
	assert_true(card_rect.end.y <= allowed + 0.5,
			"the card stops short of the bottom-left band the terrain card owns")


# --- The floating terrain card ------------------------------------------------

func test_the_terrain_card_is_fully_on_screen() -> void:
	var panel := TerrainInfoPanel.new()
	add_child_autofree(panel)
	for i in range(4):
		await get_tree().process_frame
	panel._reflow_card()
	await get_tree().process_frame

	var card_rect: Rect2 = _rect_of(panel._card)
	gut.p("terrain card: %s min=%s"
			% [card_rect, panel._card.get_combined_minimum_size()])
	_dump_tree(panel._card, 0)

	assert_true(card_rect.end.y <= _vp().y - TerrainInfoPanel.MARGIN + 0.5,
			"the card's bottom edge sits a margin above the window bottom, not past it")
	assert_true(card_rect.position.y >= 0.0, "and its top edge is on screen")
	assert_true(card_rect.size.y <= TerrainInfoPanel.MAX_HEIGHT + 0.5,
			"and it never exceeds the height the HUD reserved for it")


# --- The action banner ---------------------------------------------------------

func test_the_action_banner_starts_below_the_top_bar() -> void:
	var layout: Control = await _build_hud()

	var top_bar: Control = layout.top_bar
	var bar_bottom: float = top_bar.global_position.y + top_bar.size.y
	gut.p("top bar     : %s (bottom %.1f)" % [_rect_of(top_bar), bar_bottom])
	gut.p("banner top  : %.1f" % layout.action_announcer._plate.offset_top)

	assert_true(layout.action_announcer._plate.offset_top >= bar_bottom,
			"the banner's plate never starts inside the turn banner's band")
