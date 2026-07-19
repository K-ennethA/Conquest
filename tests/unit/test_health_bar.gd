extends GutTest

# The 3D map health bar's render logic: the fill must SHRINK as HP drops (the
# "still shows green/full while losing health" report) and recolour green ->
# amber -> red, and the depleted track must be fully opaque (so terrain never
# shows through the empty part -- the "shows the map colour when clear" report).

func _bar():
	var bar = preload("res://game/visuals/HealthBar.tscn").instantiate()
	add_child_autofree(bar)  # entering the tree runs _ready -> materials + meshes
	return bar


func _fill_width(bar) -> float:
	var fill = bar.get_node("HealthFill")
	return (fill.mesh as QuadMesh).size.x


func test_full_hp_is_full_width_and_green() -> void:
	var bar = _bar()
	bar.update_health(1.0, 100, 100)
	assert_almost_eq(_fill_width(bar), bar.FILL_MAX_WIDTH, 0.001, "full HP fills the bar")
	assert_eq(bar._health_material.albedo_color, bar.COLOR_HIGH)


func test_losing_health_shrinks_the_fill() -> void:
	var bar = _bar()
	bar.update_health(0.6, 60, 100)
	assert_almost_eq(_fill_width(bar), bar.FILL_MAX_WIDTH * 0.6, 0.001, "fill tracks percentage")


func test_colour_tiers_green_amber_red() -> void:
	var bar = _bar()
	bar.update_health(0.6, 60, 100)
	assert_eq(bar._health_material.albedo_color, bar.COLOR_HIGH, "60% -> green")
	bar.update_health(0.4, 40, 100)
	assert_eq(bar._health_material.albedo_color, bar.COLOR_MID, "40% -> amber")
	bar.update_health(0.1, 10, 100)
	assert_eq(bar._health_material.albedo_color, bar.COLOR_LOW, "10% -> red")


func test_depleted_track_is_opaque() -> void:
	var bar = _bar()
	assert_eq(bar._background_material.albedo_color.a, 1.0, "track must be opaque, not see-through")


func test_zero_hp_empties_the_fill() -> void:
	var bar = _bar()
	bar.update_health(0.0, 0, 100)
	assert_almost_eq(_fill_width(bar), 0.0, 0.001, "dead unit shows no fill")
