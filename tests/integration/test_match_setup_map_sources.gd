extends GutTest

# MatchSetup's map list once community + creator maps surface in it: every source is listed
# and badged, the list rebuilds when a new map appears (the round trip through the community
# browser), and "Get More Maps" is on the screen.
#
# The CATALOG is a stand-in (the same injection shape unit/test_map_row_builder.gd uses), for
# the same reason integration/test_community_browse_search.gd stubs the community client: the
# real one reads the player's `user://maps/` library, and a test that let it through would be
# asserting on whatever happens to be on this machine.
#
# The paths it hands back are REAL shipped maps -- the screen loads each one to draw its
# preview, so a made-up path would list as unreadable and prove nothing about badges.

const MapRowBuilder := preload("res://menus/MapRowBuilder.gd")

const MAP_A := "res://game/maps/resources/default_skirmish.tres"
const MAP_B := "res://game/maps/resources/proving_grounds.tres"
const MAP_C := "res://game/maps/resources/skirmish_arena.tres"


class StubCatalog extends RefCounted:
	var maps: Array = []
	var ineligible: Array = []

	func versus_maps() -> Array:
		return maps

	func network_eligible(path: String) -> bool:
		return not ineligible.has(path)


var screen: Control
var catalog: StubCatalog
var _previous_mode: String = ""


func _map(path: String, name: String, source: String) -> Dictionary:
	return {"path": path, "name": name, "source": source}


func before_each() -> void:
	catalog = StubCatalog.new()
	catalog.maps = [
		_map(MAP_A, "Ashfall", MapRowBuilder.SOURCE_BUILTIN),
		_map(MAP_B, "Basalt Rise", MapRowBuilder.SOURCE_CUSTOM),
	]
	MapRowBuilder.set_catalog(catalog)
	# `requested_mode` is a static that survives a scene change -- snapshot it, or this suite
	# decides what the next one's MatchSetup opens as.
	_previous_mode = MatchSetup.requested_mode
	MatchSetup.requested_mode = MatchConfigPanel.MODE_LOCAL


func after_each() -> void:
	MapRowBuilder.reset_catalog()
	MatchSetup.requested_mode = _previous_mode
	screen = null
	catalog = null


func _open() -> void:
	screen = Control.new()
	screen.set_script(load("res://menus/MatchSetup.gd"))
	add_child_autofree(screen)
	await get_tree().process_frame


## The list's item texts, in list order.
func _rows() -> Array:
	var out: Array = []
	var list: ItemList = screen._map_list
	for i in list.get_item_count():
		out.append(list.get_item_text(i))
	return out


## Every Label's text under [param root], flattened.
func _all_label_text(root: Node) -> String:
	var out: String = ""
	if root is Label:
		out += (root as Label).text + "\n"
	for child in root.get_children():
		out += _all_label_text(child)
	return out


func _find_button(root: Node, label: String) -> Button:
	if root is Button and (root as Button).text == label:
		return root as Button
	for child in root.get_children():
		var found: Button = _find_button(child, label)
		if found != null:
			return found
	return null


# --- every source is listed ---------------------------------------------------

func test_the_local_versus_list_shows_every_source():
	catalog.maps.append(_map(MAP_C, "Coldwater", MapRowBuilder.SOURCE_COMMUNITY))

	await _open()

	assert_eq(_rows(), ["Ashfall", "Basalt Rise   [CUSTOM]", "Coldwater   [COMMUNITY]"],
		"builtin, creator and downloaded maps share one list, badged and grouped")

func test_nothing_is_refused_in_a_local_match():
	catalog.maps.append(_map(MAP_C, "Coldwater", MapRowBuilder.SOURCE_COMMUNITY))
	catalog.ineligible = [MAP_C]

	await _open()

	assert_false(screen._map_list.is_item_disabled(2),
		"hot-seat sends nothing to an opponent, so 'too large to send' cannot apply here")

func test_a_downloaded_map_gets_the_same_preview_details_as_a_shipped_one():
	catalog.maps = [_map(MAP_C, "Coldwater", MapRowBuilder.SOURCE_COMMUNITY)]

	await _open()

	var text: String = _all_label_text(screen)
	assert_true(text.contains("Source: Downloaded"),
		"the preview card says where the map came from")
	assert_true(text.contains("Size: "),
		"and still reads its size off the map's own display info, like a builtin does")

func test_selecting_a_community_map_stages_it():
	catalog.maps = [_map(MAP_C, "Coldwater", MapRowBuilder.SOURCE_COMMUNITY)]

	await _open()

	assert_eq(screen._current_selected_map, MAP_C, "a downloaded map is a startable choice")
	assert_false(screen._start_btn.disabled, "and Start is live once it is selected")


# --- the rebuild --------------------------------------------------------------

func test_a_newly_downloaded_map_appears_on_the_next_rebuild():
	await _open()
	assert_eq(_rows().size(), 2, "two maps before the download")

	# What a Download does: the map is in the library the next time the catalog is asked.
	catalog.maps.append(_map(MAP_C, "Coldwater", MapRowBuilder.SOURCE_COMMUNITY))
	screen.refresh_map_list()

	assert_eq(_rows(), ["Ashfall", "Basalt Rise   [CUSTOM]", "Coldwater   [COMMUNITY]"],
		"coming back from the community browser lists what was just downloaded")

func test_a_rebuild_keeps_the_map_the_player_had_selected():
	await _open()
	screen._map_list.select(1)
	screen._on_map_selected(1)
	assert_eq(screen._current_selected_map, MAP_B, "the player picked the second map")

	# A download lands ABOVE nothing and BELOW nothing in particular -- the point is that the
	# selection follows the map, not the index.
	catalog.maps.push_front(_map(MAP_C, "Aardvark Pass", MapRowBuilder.SOURCE_BUILTIN))
	screen.refresh_map_list()

	assert_eq(screen._current_selected_map, MAP_B,
		"a refresh must not silently re-point Start at a different map")

func test_becoming_visible_again_rebuilds_the_list():
	await _open()
	catalog.maps.append(_map(MAP_C, "Coldwater", MapRowBuilder.SOURCE_COMMUNITY))

	screen.visible = false
	screen.visible = true

	assert_eq(_rows().size(), 3,
		"a MatchSetup that was hidden rather than reloaded still picks up the new map")


# --- the entry point ----------------------------------------------------------

func test_the_screen_offers_a_way_to_get_more_maps():
	await _open()

	var more: Button = _find_button(screen, "Get More Maps")
	assert_not_null(more, "the map list is also where you go looking for more maps")
	assert_false(more.disabled, "and the community browser ships in this build")

func test_get_more_maps_opens_the_browser_filtered_to_maps_and_pointing_back_here():
	await _open()

	# The scene change itself is not exercised (it would tear down the test's own tree); the
	# HINT it leaves behind is the whole contract with CommunityBrowse.
	CommunityBrowse.open_filtered(CommunityProvider.TYPE_MAP, MatchSetup.MATCH_SETUP_SCENE)

	assert_eq(CommunityBrowse.entry_type, CommunityProvider.TYPE_MAP,
		"the browser is asked to open on maps, not on the mixed feed")
	assert_eq(CommunityBrowse.entry_return_scene, MatchSetup.MATCH_SETUP_SCENE,
		"and to come back to the setup screen the player left")
	# Leave no hint behind for the next suite.
	CommunityBrowse.open_filtered("", "")
