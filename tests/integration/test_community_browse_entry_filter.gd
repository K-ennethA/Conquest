extends GutTest

# CommunityBrowse's ENTRY HINT: the optional pre-filter a screen sets before sending the
# player here ("get more maps"), and the return trip back to whoever sent them.
#
# Same stand-in service, and the same reason for it, as
# integration/test_community_browse_search.gd -- the real client seeds and writes
# user://community/, so a test that let it through would be editing the player's sandbox.

## Stand-in for CommunityClient. Records every list_items call so the test can assert on the
## TYPE that went out, and answers synchronously.
class StubClient extends RefCounted:
	## [{sort, type, page, query}], appended in call order.
	var list_calls: Array = []
	var items: Array = []

	func is_local() -> bool:
		return false

	func provider():
		return null

	func daily(cb: Callable) -> void:
		cb.call({"ok": true, "data": {"id": ""}})

	func list_items(sort: String, type: String, page: int, cb: Callable, query: String = "") -> void:
		list_calls.append({"sort": sort, "type": type, "page": page, "query": query})
		cb.call({"ok": true, "data": items})

	func fetch_item(_id: String, cb: Callable) -> void:
		cb.call({"ok": false, "error": "not needed"})

	func vote(id: String, dir: int, cb: Callable) -> void:
		cb.call({"ok": true, "data": {"id": id, "votes": dir}})

	func download_to_library(_item: Dictionary, cb: Callable) -> void:
		cb.call({"ok": true, "data": {"status": "downloaded"}})


var screen: Control
var service: StubClient


func before_each() -> void:
	service = StubClient.new()


func after_each() -> void:
	# The hint is static and survives a scene change BY DESIGN -- an unconsumed one would
	# filter the next suite's browse feed.
	CommunityBrowse.open_filtered("", "")
	screen = null
	service = null


## Open the screen. The hint (if any) must already be set: `_ready` consumes it.
func _open() -> void:
	screen = Control.new()
	screen.set_script(load("res://menus/CommunityBrowse.gd"))
	screen.set_community_client(service)
	add_child_autofree(screen)
	await get_tree().process_frame


func test_without_a_hint_the_screen_still_opens_on_the_whole_feed():
	await _open()

	assert_eq(str(service.list_calls[0]["type"]), CommunityProvider.TYPE_ALL,
		"an ordinary entry is unfiltered -- the hint is additive, not a new default")

func test_a_map_hint_opens_the_screen_filtered_to_maps():
	CommunityBrowse.open_filtered(CommunityProvider.TYPE_MAP)

	await _open()

	assert_eq(screen._type, CommunityProvider.TYPE_MAP, "the screen opened on the Maps tab")
	assert_eq(str(service.list_calls[0]["type"]), CommunityProvider.TYPE_MAP,
		"and its FIRST page load already asked the service for maps only")

func test_the_hinted_tab_is_the_one_highlighted():
	CommunityBrowse.open_filtered(CommunityProvider.TYPE_MAP)

	await _open()

	assert_eq(str(screen._type_btns[CommunityProvider.TYPE_MAP].theme_type_variation),
		"SelectedButton", "the Maps tab reads as the active one")
	assert_ne(str(screen._type_btns[CommunityProvider.TYPE_ALL].theme_type_variation),
		"SelectedButton", "and All does not")

func test_the_other_tabs_are_still_one_click_away():
	CommunityBrowse.open_filtered(CommunityProvider.TYPE_MAP)
	await _open()
	service.list_calls.clear()

	screen._on_type_selected(CommunityProvider.TYPE_ALL)

	assert_eq(str(service.list_calls[0]["type"]), CommunityProvider.TYPE_ALL,
		"a pre-filter is a starting point, not a cage")

func test_the_hint_is_consumed_by_the_screen_that_used_it():
	CommunityBrowse.open_filtered(CommunityProvider.TYPE_MAP, "res://menus/MatchSetup.tscn")

	await _open()

	assert_eq(CommunityBrowse.entry_type, "",
		"the hint is cleared on use, so the next plain entry is the ordinary feed")
	assert_eq(CommunityBrowse.entry_return_scene, "", "and Back goes back to its usual place")

func test_a_hint_this_build_does_not_understand_is_ignored():
	CommunityBrowse.open_filtered("sprockets")

	await _open()

	assert_eq(screen._type, CommunityProvider.TYPE_ALL,
		"an unknown type opens the default feed rather than filtering the list to nothing")

func test_the_return_scene_is_remembered_for_back():
	CommunityBrowse.open_filtered(CommunityProvider.TYPE_MAP, "res://menus/MatchSetup.tscn")

	await _open()

	assert_eq(screen._return_scene, "res://menus/MatchSetup.tscn",
		"Back returns to the screen that sent the player shopping, so a fresh download shows "
		+ "up in the list it was fetched for")
