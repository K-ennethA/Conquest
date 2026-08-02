extends GutTest

## Safe-area inset maths: the platform's safe rect + the window rect in, per-edge UI-pixel
## margins out. Pure static function -- no DisplayServer, no Control, no autoload -- so the
## script is preloaded directly rather than reached through the MobileDisplay singleton.

const MD := preload("res://game/mobile/MobileDisplay.gd")

## A 20:9 phone held portrait, with a 96px status-bar/notch strip at the top and a 48px
## gesture bar at the bottom.
const PHONE_WINDOW := Rect2i(0, 0, 1080, 2400)
const PHONE_SAFE := Rect2i(0, 96, 1080, 2256)


func _assert_margins(got: Dictionary, left: int, top: int, right: int, bottom: int,
		msg: String) -> void:
	assert_eq(int(got["left"]), left, "%s -- left" % msg)
	assert_eq(int(got["top"]), top, "%s -- top" % msg)
	assert_eq(int(got["right"]), right, "%s -- right" % msg)
	assert_eq(int(got["bottom"]), bottom, "%s -- bottom" % msg)


# --- Desktop: the whole feature must vanish ---------------------------------

func test_an_empty_safe_rect_insets_nothing() -> void:
	# Every desktop platform reports an empty safe area. This is exactly why desktop needs
	# no special-casing anywhere downstream -- the maths already answers "no insets".
	_assert_margins(MD.safe_area_margins(Rect2i(0, 0, 0, 0), PHONE_WINDOW),
		0, 0, 0, 0, "an unsupported/empty safe area covers nothing")


func test_a_safe_area_matching_the_window_insets_nothing() -> void:
	_assert_margins(MD.safe_area_margins(PHONE_WINDOW, PHONE_WINDOW),
		0, 0, 0, 0, "a screen with no notch or gesture bar needs no margins")


func test_a_zero_sized_window_insets_nothing() -> void:
	_assert_margins(MD.safe_area_margins(PHONE_SAFE, Rect2i(0, 0, 0, 0)),
		0, 0, 0, 0, "a window with no area cannot be inset")


# --- The actual insets ------------------------------------------------------

func test_a_notch_and_gesture_bar_become_top_and_bottom_margins() -> void:
	_assert_margins(MD.safe_area_margins(PHONE_SAFE, PHONE_WINDOW),
		0, 96, 0, 48,
		"the covered strips at each end become margins, the untouched sides stay 0")


func test_a_landscape_notch_becomes_a_side_margin() -> void:
	# The same phone rotated: the notch is now on the left, the gesture bar on the right.
	var window := Rect2i(0, 0, 2400, 1080)
	var safe := Rect2i(96, 0, 2256, 1080)
	_assert_margins(MD.safe_area_margins(safe, window),
		96, 0, 48, 0, "rotation moves the insets to the sides, same maths")


func test_a_punch_hole_inset_on_all_four_edges() -> void:
	var window := Rect2i(0, 0, 1000, 2000)
	var safe := Rect2i(10, 20, 960, 1950)
	_assert_margins(MD.safe_area_margins(safe, window),
		10, 20, 30, 30, "each edge is measured independently")


func test_a_windowed_position_offset_is_accounted_for() -> void:
	# The safe rect is reported in SCREEN coordinates, so a window that is not at the
	# origin must not read its own offset as an inset.
	var window := Rect2i(100, 50, 800, 600)
	var safe := Rect2i(100, 80, 800, 570)
	_assert_margins(MD.safe_area_margins(safe, window),
		0, 30, 0, 0, "the window's own screen position is not a notch")


func test_a_safe_area_larger_than_the_window_never_produces_negative_margins() -> void:
	# Some platforms report the full display as safe even for a smaller window. That means
	# "nothing is covered", never "expand the HUD out into the bezel".
	var window := Rect2i(100, 100, 800, 600)
	var safe := Rect2i(0, 0, 1080, 2400)
	_assert_margins(MD.safe_area_margins(safe, window),
		0, 0, 0, 0, "an oversized safe area clamps to no inset rather than going negative")


# --- Content-scale conversion ------------------------------------------------

func test_margins_are_converted_from_physical_pixels_to_ui_pixels() -> void:
	# The safe area is reported in real device pixels, but a Control is laid out in the
	# scaled canvas -- dividing by the content scale is what keeps the HUD flush with the
	# notch instead of over-inset by the scale factor.
	_assert_margins(MD.safe_area_margins(PHONE_SAFE, PHONE_WINDOW, 1.5),
		0, 64, 0, 32, "96 and 48 physical pixels are 64 and 32 UI pixels at 1.5x")


func test_conversion_rounds_up_so_no_pixel_hides_under_the_notch() -> void:
	var window := Rect2i(0, 0, 1080, 2400)
	var safe := Rect2i(0, 100, 1080, 2250)  # 100 top, 50 bottom
	_assert_margins(MD.safe_area_margins(safe, window, 1.5),
		0, 67, 0, 34,
		"66.67 and 33.33 round UP -- rounding down would leave content under the notch")


func test_an_invalid_scale_falls_back_to_one_to_one() -> void:
	_assert_margins(MD.safe_area_margins(PHONE_SAFE, PHONE_WINDOW, 0.0),
		0, 96, 0, 48, "a zero scale would divide by zero, so it is treated as 1:1")
	_assert_margins(MD.safe_area_margins(PHONE_SAFE, PHONE_WINDOW, -2.0),
		0, 96, 0, 48, "a negative scale is nonsense and is treated as 1:1")


func test_every_edge_is_reported_even_when_zero() -> void:
	var m: Dictionary = MD.safe_area_margins(PHONE_SAFE, PHONE_WINDOW)
	assert_true(m.has("left") and m.has("top") and m.has("right") and m.has("bottom"),
		"callers index all four edges unconditionally, so all four must always be present")
