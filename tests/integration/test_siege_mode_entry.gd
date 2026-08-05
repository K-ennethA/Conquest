extends GutTest

## SIEGE as the player reaches it: a card on the real solo picker, a card on the real versus
## picker, and a setup screen that opens on the mode's own map.
##
## Everything is asserted on RENDERED nodes of the real screens (the standing rule), not on
## the mode strings alone -- a mode that is "wired" but has no card is a mode nobody can
## play.
##
## WHAT IS DELIBERATELY NOT DONE HERE: nobody presses a card. Both pickers finish with
## `get_tree().change_scene_to_file`, and swapping the current scene out from under GUT ends
## the run. So the card's WIRING is asserted by reading the live `pressed` connection and the
## argument it is bound to -- which is the same fact a press would prove -- and the other
## half (what MatchSetup does with that mode) is asserted by opening MatchSetup in exactly
## the state a press leaves behind, which is how `integration/test_match_setup_map_sources.gd`
## already drives that screen.
##
## The CATALOG is a stand-in, for the reason that suite states: the real one reads this
## machine's `user://maps/` library.

const MapRowBuilder := preload("res://menus/MapRowBuilder.gd")

## Real shipped maps -- MatchSetup loads each listed path to draw its preview, so a made-up
## path would list as unreadable and prove nothing.
const MAP_PLAIN := "res://game/maps/resources/default_skirmish.tres"
const MAP_OTHER := "res://game/maps/resources/proving_grounds.tres"

const DESIGN := Vector2i(1280, 720)


class StubCatalog extends RefCounted:
	var maps: Array = []

	func versus_maps() -> Array:
		return maps

	func network_eligible(_path: String) -> bool:
		return true


## Stand-in for the mode controller the parallel workstream owns. Only the two methods this
## screen asks for -- MatchSetup resolves it by path/autoload with a has-method guard, so a
## build without one simply falls back to reading the maps' own declarations.
class SiegeControllerStub extends Node:
	var map_path: String = ""

	func is_active() -> bool:
		return true

	func recommended_map_path() -> String:
		return map_path


var _catalog: StubCatalog
var _previous_mode: String = ""
var _previous_game_mode: int = 0
var _prev_window_size: Vector2i


func before_all() -> void:
	var root := get_tree().root
	_prev_window_size = root.size
	root.size = DESIGN


func after_all() -> void:
	get_tree().root.size = _prev_window_size


func before_each() -> void:
	_catalog = StubCatalog.new()
	_catalog.maps = [
		{"path": MAP_PLAIN, "name": "Ashfall", "source": MapRowBuilder.SOURCE_BUILTIN},
	]
	MapRowBuilder.set_catalog(_catalog)
	# Both are process-wide statics/autoload fields that survive a scene change -- snapshot
	# them, or this suite decides what the next one opens as.
	_previous_mode = MatchSetup.requested_mode
	_previous_game_mode = int(GameSettings.game_mode)


func after_each() -> void:
	MapRowBuilder.reset_catalog()
	MatchSetup.requested_mode = _previous_mode
	GameSettings.game_mode = _previous_game_mode
	_catalog = null


# =====================================================================================
#  Mounting
# =====================================================================================

func _open(script_path: String) -> Control:
	var screen := Control.new()
	screen.set_script(load(script_path))
	add_child_autofree(screen)
	for i in range(4):
		await get_tree().process_frame
	return screen


func _open_match_setup(mode: String) -> Control:
	MatchSetup.requested_mode = mode
	return await _open("res://menus/MatchSetup.gd")


## Every Button under [param root] whose stacked labels contain [param needle].
func _card_with(root: Node, needle: String) -> Button:
	if root is Button and _label_text(root).contains(needle):
		return root as Button
	for child in root.get_children():
		var found: Button = _card_with(child, needle)
		if found != null:
			return found
	return null


func _label_text(root: Node) -> String:
	var out: String = ""
	if root is Label:
		out += (root as Label).text + "\n"
	for child in root.get_children():
		out += _label_text(child)
	return out


## The mode string a card is bound to, or "" when it is not a mode card.
func _bound_mode(button: Button) -> String:
	for connection in button.pressed.get_connections():
		var target: Callable = connection["callable"]
		var bound: Array = target.get_bound_arguments()
		if bound.size() == 1:
			return String(bound[0])
	return ""


# =====================================================================================
#  The solo picker
# =====================================================================================

func test_siege_is_a_card_on_the_solo_picker_beside_skirmish() -> void:
	var screen: Control = await _open("res://menus/SoloModeSelect.gd")
	var card: Button = _card_with(screen, "Siege")

	assert_not_null(card, "the solo picker offers Siege as a card, where Skirmish is offered")
	if card == null:
		return
	gut.p("siege card  : rect=%s" % Rect2(card.global_position, card.size))
	assert_true(card.is_visible_in_tree(), "and it is drawn, not built and hidden")
	assert_eq(_bound_mode(card), MatchConfigPanel.MODE_SIEGE,
			"pressing it stages the SIEGE variant of the setup screen")


func test_five_cards_still_fit_the_720p_page() -> void:
	# Adding a fifth card cost WIDTH, not height, and the cards are EXPAND_FILL inside one
	# HBox -- so what has to fit is the row's MINIMUM, which a container will never go under.
	var screen: Control = await _open("res://menus/SoloModeSelect.gd")
	var cards: HBoxContainer = _find_named(screen, "ModeCards") as HBoxContainer
	assert_not_null(cards, "the card row is mounted")
	if cards == null:
		return

	var count: int = cards.get_child_count()
	var expected: float = SoloModeSelect.CARD_WIDTH * count \
			+ SoloModeSelect.CARD_SEPARATION * maxi(count - 1, 0)
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	gut.p("cards       : %d   min row width=%.0f   page=%.0f   viewport=%.0f"
			% [count, expected, SoloModeSelect.PAGE_WIDTH, viewport_width])

	assert_eq(count, 5, "Campaign, Skirmish, Siege, Arena Run, Challenges")
	assert_true(expected <= SoloModeSelect.PAGE_WIDTH + 0.5,
			"5 x %.0f + 4 x %d = %.0f fits the page's %.0f"
			% [SoloModeSelect.CARD_WIDTH, SoloModeSelect.CARD_SEPARATION,
			expected, SoloModeSelect.PAGE_WIDTH])
	assert_true(cards.get_combined_minimum_size().x <= viewport_width + 0.5,
			"and the row the container actually resolved still fits the 720p viewport")
	assert_true(cards.size.y <= SoloModeSelect.CARD_HEIGHT + 0.5,
			"the row is no TALLER than it was, so the page's vertical stack is untouched")


func test_the_key_hint_names_the_new_card_and_renumbers_the_rest() -> void:
	var screen: Control = await _open("res://menus/SoloModeSelect.gd")
	var hint: Label = _find_named(screen, "KeyHint") as Label
	assert_not_null(hint, "the picker still shows its key hints")
	if hint == null:
		return
	gut.p("key hint    : \"%s\"" % hint.text)
	assert_true(hint.text.contains("3 Siege"), "Siege takes the 3 key")
	assert_true(hint.text.contains("4 Arena Run") and hint.text.contains("5 Challenges"),
			"and the cards after it are renumbered rather than left lying about the keys")


# =====================================================================================
#  The versus picker
# =====================================================================================

func test_siege_is_also_offerable_hot_seat() -> void:
	var screen: Control = await _open("res://menus/MultiplayerModeSelection.gd")
	var card: Button = _card_with(screen, "Siege")

	assert_not_null(card, "local versus offers Siege too -- the mode is not solo-only")
	if card == null:
		return
	assert_true(card.is_visible_in_tree(), "and it is drawn")
	var hint: Label = _find_named(screen, "KeyHint") as Label
	assert_true(hint != null and hint.text.contains("2 Siege"),
			"with a key of its own on the hint line")


# =====================================================================================
#  The setup screen it stages
# =====================================================================================

func test_the_siege_setup_screen_names_itself_and_asks_for_a_difficulty() -> void:
	var screen: Control = await _open_match_setup(MatchConfigPanel.MODE_SIEGE)
	var text: String = _label_text(screen)
	gut.p("labels      : %s" % text.replace("\n", " | "))

	assert_true(text.contains("SIEGE"), "the page says which mode is being set up")
	assert_true(text.contains("AI Difficulty"),
			"solo Siege is a match against the AI, so it asks the same question Skirmish does")
	assert_true(text.contains("Turn System"), "and the universal turn-system row is still there")
	assert_not_null(screen._map_list, "the map list is on screen -- Siege is a map mode")


func test_the_hot_seat_variant_drops_the_ai_row_exactly_as_local_versus_does() -> void:
	var screen: Control = await _open_match_setup(MatchConfigPanel.MODE_SIEGE_LOCAL)
	var text: String = _label_text(screen)

	assert_true(text.contains("LOCAL SIEGE"), "the page names the hot-seat variant")
	assert_false(text.contains("AI Difficulty"),
			"there is no AI in a hot-seat match, so there is no difficulty to pick")


func test_siege_opens_on_the_map_its_controller_recommends() -> void:
	_catalog.maps.append({"path": MAP_OTHER, "name": "Zenith Rise",
			"source": MapRowBuilder.SOURCE_BUILTIN})
	# Named "Zenith Rise" so it sorts LAST -- if the screen still lands on it, that is the
	# recommendation winning rather than the list order.
	var controller := SiegeControllerStub.new()
	controller.name = "SiegeControllerStub"
	controller.map_path = MAP_OTHER
	controller.add_to_group(&"siege_controller")
	add_child_autofree(controller)

	var screen: Control = await _open_match_setup(MatchConfigPanel.MODE_SIEGE)
	gut.p("selected    : %s" % screen._current_selected_map)
	assert_eq(screen._current_selected_map, MAP_OTHER,
			"the mode's own recommended map is what the picker opens on")
	assert_false(screen._start_btn.disabled,
			"and Start is live immediately -- the player can begin without touching the list")


func test_without_a_controller_it_falls_back_to_a_map_that_declares_itself() -> void:
	# The build that has the MAP but not (yet) the controller. Nothing is stubbed except the
	# catalog: the screen loads each listed map and reads its own authored objectives.
	var siege_map := MapResource.new()
	siege_map.map_name = "Riftwood"
	siege_map.width = 20
	siege_map.height = 14
	siege_map.victory_conditions = ["Capture Enemy Base"] as Array[String]
	var temp_path := "user://test_siege_entry_map.tres"
	assert_eq(ResourceSaver.save(siege_map, temp_path), OK, "the fixture map was written")
	_catalog.maps.append({"path": temp_path, "name": "Zenith Rise",
			"source": MapRowBuilder.SOURCE_BUILTIN})

	var screen: Control = await _open_match_setup(MatchConfigPanel.MODE_SIEGE)
	gut.p("selected    : %s" % screen._current_selected_map)
	assert_eq(screen._current_selected_map, temp_path,
			"a map whose authored objective is a base CAPTURE is what Siege opens on, "
			+ "even though it sorts last")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))


func test_the_siege_picker_still_lists_every_other_map() -> void:
	# A preselection, never a filter: Siege on a small skirmish map is a legal (if short)
	# match, and a picker that hid every map but one would be a launcher wearing a list.
	_catalog.maps.append({"path": MAP_OTHER, "name": "Basalt Rise",
			"source": MapRowBuilder.SOURCE_BUILTIN})
	var screen: Control = await _open_match_setup(MatchConfigPanel.MODE_SIEGE)
	assert_eq(screen._map_list.get_item_count(), 2,
			"both maps are still selectable -- nothing was filtered out")


func test_skirmish_is_untouched_by_any_of_this() -> void:
	# The regression that matters most: a recommendation that leaked into the other modes
	# would silently change which map every existing screen opens on.
	_catalog.maps.append({"path": MAP_OTHER, "name": "Zenith Rise",
			"source": MapRowBuilder.SOURCE_BUILTIN})
	var controller := SiegeControllerStub.new()
	controller.name = "SiegeControllerStub"
	controller.map_path = MAP_OTHER
	controller.add_to_group(&"siege_controller")
	add_child_autofree(controller)

	var screen: Control = await _open_match_setup(MatchConfigPanel.MODE_SKIRMISH)
	assert_eq(screen._current_selected_map, MAP_PLAIN,
			"skirmish still opens on the first row, recommendation or no recommendation")


# =====================================================================================
#  Helpers
# =====================================================================================

func _find_named(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found: Node = _find_named(child, node_name)
		if found != null:
			return found
	return null
