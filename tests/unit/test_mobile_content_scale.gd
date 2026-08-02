extends GutTest

## The mobile content-scale picker: DPI + screen resolution in, Window.content_scale_factor
## out. Pure static maths -- no DisplayServer, no Window, no autoload -- so the script is
## preloaded directly rather than reached through the MobileDisplay singleton.

const MD := preload("res://game/mobile/MobileDisplay.gd")

const EPSILON := 0.0001


# --- stretch_scale: what canvas_items already does ---------------------------

func test_design_resolution_needs_no_stretch() -> void:
	assert_almost_eq(MD.stretch_scale(Vector2i(1280, 720)), 1.0, EPSILON,
		"the authored 1280x720 canvas maps 1:1 onto a 1280x720 screen")


func test_stretch_uses_the_smaller_axis_ratio() -> void:
	# aspect="expand" scales by the tighter axis and reveals more world on the other, so a
	# 20:9 phone is bounded by its HEIGHT, not its very wide width.
	assert_almost_eq(MD.stretch_scale(Vector2i(2400, 1080)), 1.5, EPSILON,
		"a 2400x1080 phone stretches by 1080/720, not 2400/1280")
	assert_almost_eq(MD.stretch_scale(Vector2i(2560, 1440)), 2.0, EPSILON,
		"a 16:9 screen at double the design size stretches by exactly 2")


func test_degenerate_screen_size_is_neutral() -> void:
	assert_almost_eq(MD.stretch_scale(Vector2i(0, 0)), 1.0, EPSILON,
		"a zero screen size cannot produce a ratio, so it reports no stretch")


# --- pick_content_scale_factor ----------------------------------------------

func test_unknown_dpi_leaves_the_ui_exactly_as_authored() -> void:
	# Platforms that cannot report density return 0 (or worse). Guessing from a bad number
	# would resize the whole HUD, so the answer is "change nothing".
	assert_almost_eq(MD.pick_content_scale_factor(0, Vector2i(1080, 2400)),
		1.0, EPSILON, "DPI 0 means unknown density, not a tiny screen")
	assert_almost_eq(MD.pick_content_scale_factor(-1, Vector2i(1080, 2400)),
		1.0, EPSILON, "a negative DPI is nonsense and must not scale anything")


func test_empty_resolution_leaves_the_ui_exactly_as_authored() -> void:
	assert_almost_eq(MD.pick_content_scale_factor(440, Vector2i(0, 0)),
		1.0, EPSILON, "with no resolution there is no stretch to correct for")


func test_a_desktop_monitor_is_never_scaled_up() -> void:
	assert_almost_eq(MD.pick_content_scale_factor(96, Vector2i(1920, 1080)),
		1.0, EPSILON, "a 96 DPI monitor IS the reference -- it needs no correction")
	assert_almost_eq(MD.pick_content_scale_factor(96, Vector2i(3840, 2160)),
		1.0, EPSILON,
		"a big low-density screen already stretches the UI up; the clamp stops it shrinking")


func test_a_tablet_needs_no_correction() -> void:
	# 2560x1600 @ 264 DPI: the 2x stretch already covers the density, so the raw factor
	# lands below 1 and the lower clamp keeps the authored look.
	assert_almost_eq(MD.pick_content_scale_factor(264, Vector2i(2560, 1600)),
		1.0, EPSILON, "a tablet's stretch already compensates for its density")


func test_a_typical_phone_gets_a_moderate_bump() -> void:
	# 2400x1080 @ 440 DPI: stretch 1.5, so (440/96)/1.5*0.5 = 1.5278, snapped to 1.55.
	assert_almost_eq(MD.pick_content_scale_factor(440, Vector2i(2400, 1080)),
		1.55, EPSILON, "a 440 DPI phone enlarges the UI by about half again")


func test_a_low_resolution_high_density_phone_gets_the_largest_bump() -> void:
	# 1280x720 @ 300 DPI: no stretch at all, so the density correction lands in full.
	assert_almost_eq(MD.pick_content_scale_factor(300, Vector2i(1280, 720)),
		1.55, EPSILON,
		"a 720p phone gets no help from stretch, so density drives the whole factor")


func test_an_extreme_density_is_clamped_not_trusted() -> void:
	assert_almost_eq(MD.pick_content_scale_factor(700, Vector2i(3200, 1440)),
		1.75, EPSILON,
		"the upper clamp stops a very dense screen from leaving no room for the board")


func test_the_result_is_snapped_so_near_identical_devices_agree() -> void:
	var a: float = MD.pick_content_scale_factor(440, Vector2i(2400, 1080))
	var b: float = MD.pick_content_scale_factor(441, Vector2i(2400, 1080))
	assert_almost_eq(a, b, EPSILON,
		"a 1 DPI reporting difference must not produce a different UI size")
	assert_almost_eq(a, snappedf(a, MD.SCALE_STEP), EPSILON,
		"the factor lands exactly on a 0.05 step")


func test_every_plausible_device_stays_inside_the_clamp() -> void:
	var resolutions: Array[Vector2i] = [
		Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(2400, 1080),
		Vector2i(3200, 1440), Vector2i(2560, 1600), Vector2i(3840, 2160),
	]
	for res in resolutions:
		for dpi in range(1, 1001, 7):
			var f: float = MD.pick_content_scale_factor(dpi, res)
			assert_between(f, MD.SCALE_MIN, MD.SCALE_MAX,
				"no DPI/resolution pair may escape the clamp (dpi=%d res=%s)" % [dpi, res])


func test_denser_screens_never_scale_down_relative_to_sparser_ones() -> void:
	var res := Vector2i(2400, 1080)
	var previous: float = 0.0
	for dpi in range(50, 800, 25):
		var f: float = MD.pick_content_scale_factor(dpi, res)
		assert_true(f >= previous,
			"the factor must rise monotonically with density (dpi=%d)" % dpi)
		previous = f
