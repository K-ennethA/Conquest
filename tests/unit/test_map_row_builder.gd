extends GutTest

# The shared map-ROW model behind both versus map pickers (menus/MapRowBuilder.gd): which
# source gets which badge, what order the list comes out in, and when a row is refused.
#
# Everything here is PURE -- build_rows takes entries + a Callable, so none of it needs the
# catalog, the disk or a scene tree. The renderers are covered too, but only for the row
# facts a player can see (the chip, the disabled state, the tooltip sentence).

const MapRowBuilder := preload("res://menus/MapRowBuilder.gd")


## Two maps this build definitely ships, used wherever a row has to be READABLE for the
## assertion to mean anything.
const BIG_MAP := "res://game/maps/resources/default_skirmish.tres"
const SMALL_MAP := "res://game/maps/resources/proving_grounds.tres"


## Stand-in for the (parallel-workstream) MapCatalog, in its pinned shape.
class StubCatalog extends RefCounted:
	var maps: Array = []
	var ineligible: Array = []

	func versus_maps() -> Array:
		return maps

	func network_eligible(path: String) -> bool:
		return not ineligible.has(path)


func _entry(path: String, name: String, source: String) -> Dictionary:
	return {"path": path, "name": name, "source": source}


func after_each() -> void:
	# The catalog handle is process-wide static state; a suite that left one injected would
	# hand it to every later suite in the run.
	MapRowBuilder.reset_catalog()


# --- badges ------------------------------------------------------------------

func test_a_builtin_map_carries_no_badge():
	assert_eq(MapRowBuilder.badge_for(MapRowBuilder.SOURCE_BUILTIN), "",
		"the shipped maps are the default case -- a badge on every row badges nothing")

func test_a_player_authored_map_is_badged_custom():
	assert_eq(MapRowBuilder.badge_for(MapRowBuilder.SOURCE_CUSTOM), "CUSTOM",
		"a map the player built in the Map Creator says so")

func test_a_downloaded_map_is_badged_community():
	assert_eq(MapRowBuilder.badge_for(MapRowBuilder.SOURCE_COMMUNITY), "COMMUNITY",
		"a map pulled off the community service says where it came from")

func test_an_unknown_source_falls_back_to_the_unbadged_default():
	var row: Dictionary = MapRowBuilder.make_row(_entry("res://a.tres", "A", "wat"), false, true)
	assert_eq(String(row["source"]), MapRowBuilder.SOURCE_BUILTIN,
		"a source this build does not know is treated as builtin, not shown as garbage")
	assert_eq(String(row["badge"]), "", "and therefore carries no badge")

func test_the_two_badges_are_told_apart_by_colour_as_well_as_text():
	assert_ne(MapRowBuilder.badge_color(MapRowBuilder.SOURCE_CUSTOM),
		MapRowBuilder.badge_color(MapRowBuilder.SOURCE_COMMUNITY),
		"yours and someone else's must not read as the same chip at a glance")

func test_a_text_only_row_carries_its_badge_in_the_string():
	assert_eq(MapRowBuilder.list_text("Ridgeline", "CUSTOM"), "Ridgeline   [CUSTOM]",
		"an ItemList row cannot hold a chip Control, so the badge rides in the text")
	assert_eq(MapRowBuilder.list_text("Ridgeline", ""), "Ridgeline",
		"and an unbadged row is just the name")


# --- ordering (PINNED) -------------------------------------------------------

func test_rows_are_grouped_builtin_then_custom_then_community():
	var rows: Array = MapRowBuilder.build_rows([
		_entry("user://maps/zeta.json", "Zeta", MapRowBuilder.SOURCE_COMMUNITY),
		_entry("user://maps/mine.json", "Mine", MapRowBuilder.SOURCE_CUSTOM),
		_entry("res://game/maps/resources/arena.tres", "Arena", MapRowBuilder.SOURCE_BUILTIN),
	], false)

	assert_eq(rows.size(), 3, "every entry became a row")
	assert_eq(String(rows[0]["name"]), "Arena", "the shipped maps a new player recognises lead")
	assert_eq(String(rows[1]["name"]), "Mine", "then the player's own creations")
	assert_eq(String(rows[2]["name"]), "Zeta", "then the downloads")

func test_rows_inside_a_group_are_alphabetical_regardless_of_case():
	var rows: Array = MapRowBuilder.build_rows([
		_entry("res://b.tres", "beta", MapRowBuilder.SOURCE_BUILTIN),
		_entry("res://a.tres", "Alpha", MapRowBuilder.SOURCE_BUILTIN),
		_entry("res://c.tres", "Ceta", MapRowBuilder.SOURCE_BUILTIN),
	], false)

	assert_eq(String(rows[0]["name"]), "Alpha", "A before b")
	assert_eq(String(rows[1]["name"]), "beta", "lower case does not sort after every capital")
	assert_eq(String(rows[2]["name"]), "Ceta", "and C last")

func test_two_maps_with_the_same_name_keep_a_stable_order():
	var rows: Array = MapRowBuilder.build_rows([
		_entry("user://maps/b_ridge.json", "Ridge", MapRowBuilder.SOURCE_CUSTOM),
		_entry("user://maps/a_ridge.json", "Ridge", MapRowBuilder.SOURCE_CUSTOM),
	], false)

	assert_eq(String(rows[0]["path"]), "user://maps/a_ridge.json",
		"the path breaks the tie, so a rebuild never swaps two same-named maps")

func test_an_entry_with_no_path_is_not_a_row():
	var rows: Array = MapRowBuilder.build_rows([
		{"name": "Ghost", "source": MapRowBuilder.SOURCE_CUSTOM},
		_entry("res://a.tres", "Alpha", MapRowBuilder.SOURCE_BUILTIN),
	], false)

	assert_eq(rows.size(), 1, "a catalog entry with nothing to select is dropped, not listed")

func test_a_nameless_entry_falls_back_to_its_file_stem():
	var rows: Array = MapRowBuilder.build_rows([
		_entry("user://maps/frost_hollow.json", "", MapRowBuilder.SOURCE_COMMUNITY),
	], false)

	assert_eq(String(rows[0]["name"]), "frost_hollow",
		"a map with no title still reads as something rather than as an empty row")


# --- refusals ----------------------------------------------------------------

func test_an_oversized_map_is_refused_in_a_networked_lobby():
	var rows: Array = MapRowBuilder.build_rows(
		[_entry("user://maps/huge.json", "Huge", MapRowBuilder.SOURCE_COMMUNITY)],
		true,
		func(_path: String) -> bool: return false)

	assert_true(bool(rows[0]["disabled"]), "a map the opponent cannot be sent cannot be voted for")
	assert_eq(String(rows[0]["tooltip"]), "Too large to send to your opponent",
		"and says why, in the one shared sentence")

func test_the_same_oversized_map_is_playable_in_a_local_match():
	var rows: Array = MapRowBuilder.build_rows(
		[_entry("user://maps/huge.json", "Huge", MapRowBuilder.SOURCE_COMMUNITY)],
		false,
		func(_path: String) -> bool: return false)

	assert_false(bool(rows[0]["disabled"]),
		"hot-seat sends nothing to anybody, so size is not a reason to refuse a map")

func test_an_eligible_map_is_selectable_in_the_lobby():
	var rows: Array = MapRowBuilder.build_rows(
		[_entry("user://maps/small.json", "Small", MapRowBuilder.SOURCE_COMMUNITY)],
		true,
		func(_path: String) -> bool: return true)

	assert_false(bool(rows[0]["disabled"]), "a map that fits is votable")
	assert_true(String(rows[0]["tooltip"]).contains("Downloaded"),
		"and its tooltip says where it came from instead of a refusal")

func test_a_map_this_build_cannot_read_is_refused_before_the_size_rule():
	var entry: Dictionary = _entry("user://maps/broken.json", "Broken", MapRowBuilder.SOURCE_COMMUNITY)
	entry["loadable"] = false
	var rows: Array = MapRowBuilder.build_rows([entry], true, func(_path: String) -> bool: return false)

	assert_true(bool(rows[0]["disabled"]), "an unreadable map is not selectable")
	assert_eq(String(rows[0]["tooltip"]), MapRowBuilder.UNREADABLE_TOOLTIP,
		"and is not blamed on its size -- shrinking it would not help")


# --- metadata ----------------------------------------------------------------

func test_a_row_reports_the_size_of_the_map_it_already_loaded():
	var map_resource: MapResource = MapResource.new()
	map_resource.width = 12
	map_resource.height = 10
	var entry: Dictionary = _entry("user://maps/ridge.json", "Ridge", MapRowBuilder.SOURCE_CUSTOM)
	entry["resource"] = map_resource
	var rows: Array = MapRowBuilder.build_rows([entry], false)

	assert_eq(String(rows[0]["meta"]), "12x10",
		"the size comes off the row's OWN resource -- there is no second metadata source")

func test_a_row_with_nothing_loaded_reports_no_size():
	var rows: Array = MapRowBuilder.build_rows(
		[_entry("user://maps/ridge.json", "Ridge", MapRowBuilder.SOURCE_CUSTOM)], false)

	assert_eq(String(rows[0]["meta"]), "",
		"an unknown size is blank rather than an invented 0x0")


# --- the renderers -----------------------------------------------------------

func test_an_item_list_row_shows_the_badge_and_the_refusal():
	var list: ItemList = autofree(ItemList.new())
	var huge: Dictionary = _entry("user://maps/huge.json", "Huge", MapRowBuilder.SOURCE_COMMUNITY)
	var rows: Array = MapRowBuilder.build_rows(
		[_entry("res://a.tres", "Alpha", MapRowBuilder.SOURCE_BUILTIN), huge],
		true,
		func(path: String) -> bool: return not path.contains("huge"))

	MapRowBuilder.apply_to_item_list(list, rows)

	assert_eq(list.get_item_count(), 2, "both maps are listed")
	assert_eq(list.get_item_text(0), "Alpha", "the builtin row is unbadged")
	assert_eq(list.get_item_text(1), "Huge   [COMMUNITY]", "the download carries its badge")
	assert_false(list.is_item_disabled(0), "the builtin map is selectable")
	assert_true(list.is_item_disabled(1), "the oversized download is not")
	assert_eq(list.get_item_tooltip(1), "Too large to send to your opponent",
		"and hovering it says why")

func test_an_item_list_row_keeps_a_screens_own_suffix():
	var list: ItemList = autofree(ItemList.new())
	var rows: Array = MapRowBuilder.build_rows(
		[_entry("user://maps/wip.json", "Half Built", MapRowBuilder.SOURCE_CUSTOM)], false)

	MapRowBuilder.apply_to_item_list(list, rows, {"user://maps/wip.json": "  (draft)"})

	assert_eq(list.get_item_text(0), "Half Built  (draft)   [CUSTOM]",
		"the draft tail sits with the name, the badge stays at the end of the row")

func test_a_button_row_carries_a_real_chip():
	var rows: Array = MapRowBuilder.build_rows(
		[_entry("user://maps/ridge.json", "Ridge", MapRowBuilder.SOURCE_CUSTOM)], false)
	var button: Button = autofree(MapRowBuilder.build_row_button(rows[0]))

	assert_false(button.disabled, "an ordinary row is pressable")
	assert_true(_chip_text(button).contains("CUSTOM"), "and shows its source as a chip")

func test_a_refused_button_row_is_disabled_with_the_sentence():
	var rows: Array = MapRowBuilder.build_rows(
		[_entry("user://maps/huge.json", "Huge", MapRowBuilder.SOURCE_COMMUNITY)],
		true,
		func(_path: String) -> bool: return false)
	var button: Button = autofree(MapRowBuilder.build_row_button(rows[0]))

	assert_true(button.disabled, "the row cannot be voted for")
	assert_eq(button.tooltip_text, "Too large to send to your opponent", "and says why on hover")

func test_the_list_reports_an_empty_library_rather_than_nothing():
	# The stub is what keeps this off the real library: with a catalog injected, build_list
	# never reaches MapLoader or the disk.
	MapRowBuilder.set_catalog(StubCatalog.new())

	var card: Control = autofree(MapRowBuilder.build_list(false, Callable()))

	assert_true(_chip_text(card).contains("No maps"),
		"an empty library says so instead of rendering a blank panel")

func test_the_list_reads_the_catalog_and_refuses_what_it_says_is_too_big():
	# Real shipped .tres paths with invented sources: versus_rows LOADS each map to decide
	# whether it is readable at all, so a made-up path would be refused as unreadable before
	# the size rule ever ran (which is exactly what the previous test pins).
	var catalog := StubCatalog.new()
	catalog.maps = [
		{"path": BIG_MAP, "name": "Huge", "source": MapRowBuilder.SOURCE_COMMUNITY},
		{"path": SMALL_MAP, "name": "Small", "source": MapRowBuilder.SOURCE_CUSTOM},
	]
	catalog.ineligible = [BIG_MAP]
	MapRowBuilder.set_catalog(catalog)

	var rows: Array = MapRowBuilder.versus_rows(true)

	assert_eq(rows.size(), 2, "both catalog entries became rows")
	assert_eq(String(rows[0]["name"]), "Small", "the player's own creation is listed before the download")
	assert_false(bool(rows[0]["disabled"]), "the small map is votable")
	assert_true(bool(rows[1]["disabled"]), "the one the catalog called too big is not")
	assert_eq(String(rows[1]["tooltip"]), "Too large to send to your opponent",
		"with the shared sentence")


## Every Label's text under [param root], flattened.
func _chip_text(root: Node) -> String:
	var out: String = ""
	if root is Label:
		out += (root as Label).text + "\n"
	for child in root.get_children():
		out += _chip_text(child)
	return out
