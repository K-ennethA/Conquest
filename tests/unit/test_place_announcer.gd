extends GutTest

## PlaceAnnouncer: the classic-Pokemon rule for WHEN the location popup names a place -- a different
## named place, never a building's interior, never again for where you already stand, and never
## for a place that was named a moment ago (hopping back and forth over an area edge).

const T0 := 100000


func test_a_new_place_is_named() -> void:
	var p := PlaceAnnouncer.new()
	assert_true(p.announce("Oakvale", false, T0), "the first place is named")
	assert_true(p.announce("The Mossway", false, T0 + 5000), "a different place is named")


func test_an_interior_is_never_named() -> void:
	var p := PlaceAnnouncer.new()
	assert_false(p.announce("The Royal Workshop", true, T0), "a room is not a place")
	assert_true(p.announce("Crownhaven", false, T0 + 1000), "and it does not use up the town's popup")
	assert_false(p.announce("The Royal Workshop", true, T0 + 2000), "going in again names nothing")
	assert_false(p.announce("Crownhaven", false, T0 + 3000), "coming back out names nothing: you never left")


func test_the_same_place_twice_in_a_row_is_named_once() -> void:
	var p := PlaceAnnouncer.new()
	assert_true(p.announce("Oakvale", false, T0))
	assert_false(p.announce("Oakvale", false, T0 + 60000), "a reload of the same place, however late")


func test_hopping_back_and_forth_does_not_name_the_places_again() -> void:
	var p := PlaceAnnouncer.new()
	assert_true(p.announce("Oakvale", false, T0))
	assert_true(p.announce("The Mossway", false, T0 + 2000))
	assert_false(p.announce("Oakvale", false, T0 + 4000), "back to Oakvale within seconds")
	assert_false(p.announce("The Mossway", false, T0 + 6000), "and over again")
	assert_true(p.announce("River Crossing", false, T0 + 8000), "a place not yet named is")
	assert_true(p.announce("Oakvale", false, T0 + PlaceAnnouncer.REPEAT_COOLDOWN_MSEC + 10000),
		"a place not named for a while is named again")


func test_reset_forgets_everything() -> void:
	var p := PlaceAnnouncer.new()
	p.announce("Oakvale", false, T0)
	p.reset()
	assert_true(p.announce("Oakvale", false, T0 + 1), "a fresh journey names its first place")


func test_an_unnamed_place_is_skipped() -> void:
	assert_false(PlaceAnnouncer.new().announce("", false, T0))
