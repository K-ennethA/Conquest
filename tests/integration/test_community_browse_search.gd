extends GutTest

# CommunityBrowse's search field, the Recommended default, and the defense readout on cards.
#
# The screen is built for real (it is a Control that assembles its whole tree in _ready), but
# the SERVICE is a stand-in -- the same shape as the MockNetSession pattern in
# unit/test_lobby_transport_adapter.gd. That matters for more than speed: the real client
# picks a LocalProvider that seeds and writes user://community/, so a test that let the real
# one through would be editing the player's sandbox to assert on a label.
#
# The stub is injected BEFORE the node enters the tree. The screen only constructs a real
# client when none was supplied, so `_ready` never reaches disk here.

## Stand-in for CommunityClient. Records every list_items call so the test can assert on the
## query that went out, and answers synchronously (the real HttpProvider does not -- the
## screen's callbacks are guarded for that, this suite is not the place that proves it).
class StubClient extends RefCounted:
	## [{sort, type, page, query}], appended in call order.
	var list_calls: Array = []
	## What the next page load returns.
	var items: Array = []
	## Force a failure result out of list_items.
	var fail_with: String = ""

	func is_local() -> bool:
		return false

	func provider():
		return null

	func daily(cb: Callable) -> void:
		cb.call({"ok": true, "data": {"id": ""}})

	func list_items(sort: String, type: String, page: int, cb: Callable, query: String = "") -> void:
		list_calls.append({"sort": sort, "type": type, "page": page, "query": query})
		if not fail_with.is_empty():
			cb.call({"ok": false, "error": fail_with})
			return
		cb.call({"ok": true, "data": items})

	func fetch_item(_id: String, cb: Callable) -> void:
		cb.call({"ok": false, "error": "not needed"})

	func vote(id: String, dir: int, cb: Callable) -> void:
		cb.call({"ok": true, "data": {"id": id, "votes": dir}})

	func download_to_library(_item: Dictionary, cb: Callable) -> void:
		cb.call({"ok": true, "data": {"status": "downloaded"}})


var screen: Control
## Named `service`, not `stub`: GutTest already owns a member called `stub` (its doubling
## helper), and shadowing it is a parse error rather than a warning.
var service: StubClient


func _challenge(id: String, name: String, attempts: int, clears: int) -> Dictionary:
	return {
		"id": id, "name": name, "author": "Kestrel", "type": CommunityProvider.TYPE_CHALLENGE,
		"votes": 5, "attempts": attempts, "clears": clears, "size_bytes": 900,
	}


func _open() -> void:
	screen = Control.new()
	screen.set_script(load("res://menus/CommunityBrowse.gd"))
	# Injected before add_child: the script is live the moment it is set, `_ready` is not.
	screen.set_community_client(service)
	add_child_autofree(screen)
	await get_tree().process_frame


## Every Label's text under [param root], flattened. Assertions read the SCREEN, not the
## data that fed it.
func _all_label_text(root: Node) -> String:
	var out: String = ""
	if root is Label:
		out += (root as Label).text + "\n"
	for child in root.get_children():
		out += _all_label_text(child)
	return out


func before_each() -> void:
	service = StubClient.new()


func after_each() -> void:
	screen = null
	service = null


# --- the default sort --------------------------------------------------------

func test_the_browse_feed_opens_on_recommended():
	service.items = [_challenge("c1", "Gauntlet", 0, 0)]

	await _open()

	assert_gt(service.list_calls.size(), 0, "opening the screen loaded a page")
	assert_eq(str(service.list_calls[0]["sort"]), "recommended",
		"the first page asked for the server-ranked Recommended feed")
	assert_eq(str(service.list_calls[0]["query"]), "",
		"and asked for it unfiltered -- Recommended is a feed, not a search")

func test_top_new_and_daily_are_still_one_click_away():
	await _open()
	service.list_calls.clear()

	screen._on_sort_selected(CommunityProvider.SORT_TOP)
	screen._on_sort_selected(CommunityProvider.SORT_NEW)
	screen._on_sort_selected(CommunityProvider.SORT_DAILY)

	assert_eq(service.list_calls.size(), 3, "each tab reloaded the feed")
	assert_eq(str(service.list_calls[0]["sort"]), "top", "Top still sorts by score")
	assert_eq(str(service.list_calls[1]["sort"]), "new", "New still sorts by recency")
	assert_eq(str(service.list_calls[2]["sort"]), "daily", "Daily still leads with the daily pick")

# --- search ------------------------------------------------------------------

func test_typing_does_not_fire_a_request_until_the_debounce_elapses():
	await _open()
	service.list_calls.clear()

	screen._search_edit.text = "gaun"
	screen._on_search_text_changed("gaun")

	assert_eq(service.list_calls.size(), 0,
		"a keystroke only restarts the 0.4s clock -- it does not hit the service")

func test_the_debounce_firing_sends_the_query():
	await _open()
	service.list_calls.clear()

	screen._search_edit.text = "gauntlet"
	screen._on_search_text_changed("gauntlet")
	screen._flush_search()   # what the debounce timer's timeout calls

	assert_eq(service.list_calls.size(), 1, "the pause at the end of typing costs exactly one request")
	assert_eq(str(service.list_calls[0]["query"]), "gauntlet", "which carried the typed query")
	assert_eq(int(service.list_calls[0]["page"]), 0, "and restarted at the first page of results")

func test_a_query_is_trimmed_before_it_is_sent():
	await _open()
	service.list_calls.clear()

	screen._search_edit.text = "  gauntlet  "
	screen._flush_search()

	assert_eq(str(service.list_calls[0]["query"]), "gauntlet",
		"surrounding whitespace is the player's typing, not part of what they meant")

func test_re_sending_an_unchanged_query_is_a_no_op():
	await _open()
	screen._search_edit.text = "gauntlet"
	screen._flush_search()
	service.list_calls.clear()

	screen._flush_search()
	screen._flush_search()

	assert_eq(service.list_calls.size(), 0,
		"Enter on an unchanged field must not re-fetch the same page")

func test_clearing_the_field_restores_the_browse_feed():
	await _open()
	screen._search_edit.text = "gauntlet"
	screen._flush_search()
	service.list_calls.clear()

	screen._on_search_cleared()

	assert_eq(screen._search_edit.text, "", "Clear emptied the field")
	assert_eq(service.list_calls.size(), 1, "and reloaded")
	assert_eq(str(service.list_calls[0]["query"]), "",
		"with no query at all -- the plain feed, not a search for an empty string")

func test_the_query_survives_a_sort_change():
	await _open()
	screen._search_edit.text = "gauntlet"
	screen._flush_search()
	service.list_calls.clear()

	screen._on_sort_selected(CommunityProvider.SORT_TOP)

	assert_eq(str(service.list_calls[0]["sort"]), "top", "the tab changed the sort")
	assert_eq(str(service.list_calls[0]["query"]), "gauntlet",
		"without dropping what the player was searching for")

func test_the_query_survives_a_type_filter_change():
	await _open()
	screen._search_edit.text = "gauntlet"
	screen._flush_search()
	service.list_calls.clear()

	screen._on_type_selected(CommunityProvider.TYPE_CHALLENGE)

	assert_eq(str(service.list_calls[0]["type"]), "challenge", "the filter changed the type")
	assert_eq(str(service.list_calls[0]["query"]), "gauntlet", "and kept the query")

func test_load_more_pages_within_the_search():
	await _open()
	screen._search_edit.text = "gauntlet"
	screen._flush_search()
	service.list_calls.clear()

	screen._on_load_more()

	assert_eq(int(service.list_calls[0]["page"]), 1, "Load more advanced the page")
	assert_eq(str(service.list_calls[0]["query"]), "gauntlet", "inside the same search")

func test_a_search_with_no_results_says_what_was_searched_for():
	await _open()
	service.items = []

	screen._search_edit.text = "nothingmatchesthis"
	screen._flush_search()

	var text: String = _all_label_text(screen)
	assert_true(text.contains("No results for \"nothingmatchesthis\""),
		"an empty search result names the query rather than claiming the community is empty")

func test_an_empty_feed_still_reads_as_an_invitation():
	service.items = []

	await _open()

	var text: String = _all_label_text(screen)
	assert_true(text.contains("Be the first"),
		"with no query, an empty list is an invitation to publish")

# --- the defense readout on cards -------------------------------------------

func test_a_challenge_card_shows_the_attack_count_and_defense_rate():
	service.items = [_challenge("c1", "Gauntlet", 42, 12)]

	await _open()

	var text: String = _all_label_text(screen._list_box)
	assert_true(text.contains("Attacked 42"), "the card shows how many players attacked it")
	assert_true(text.contains("defended 71%"), "and the derived rate, rounded")

func test_an_unattacked_challenge_card_never_claims_a_perfect_record():
	service.items = [_challenge("c1", "Fresh Fort", 0, 0)]

	await _open()

	var text: String = _all_label_text(screen._list_box)
	assert_true(text.contains("Not attacked yet"), "a brand new base says it is untested")
	assert_false(text.contains("100%"), "rather than reading as undefeated")

func test_a_map_card_carries_no_defense_readout():
	service.items = [{
		"id": "m1", "name": "Ridgeline", "author": "Kestrel", "type": CommunityProvider.TYPE_MAP,
		"votes": 3, "attempts": 0, "clears": 0, "size_bytes": 700,
	}]

	await _open()

	var text: String = _all_label_text(screen._list_box)
	assert_false(text.contains("Not attacked yet"),
		"a bare map is never attacked, so an attack line on one would be noise")
	assert_true(text.contains("Ridgeline"), "the map is still listed")
