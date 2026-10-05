class_name ProgressRows
extends RefCounted

## The XP / LEVEL-UP rows of a story battle's end screen (docs/design/PROGRESSION.md): one line per
## member that earned XP -- "Barkling +86 XP   Lv 6" or, on a level-up, "Barkling +312 XP   Lv 5 -> 7"
## with a gold "Level up!" -- plus a thin XP bar, under a gold "EXPERIENCE" heading. Shared by the
## tactical end screen (GameOverScreen) and the duel's results card (DuelHUD), the twin of
## [method GrowthGems.fill_result_rows]. Rows are [method StoryProgression.preview_rows]'s shape.


## Fill [param box] with [param rows]; hides it when there is nothing to show. Returns the row count.
static func fill_result_rows(box: VBoxContainer, rows: Array, font_size: int) -> int:
	if box == null:
		return 0
	for child in box.get_children():
		box.remove_child(child)
		child.free()
	var shown: Array = []
	for r in rows:
		if r is Dictionary and int(r.get("gained", 0)) > 0:
			shown.append(r)
	box.visible = not shown.is_empty()
	if shown.is_empty():
		return 0

	var heading := Label.new()
	heading.name = "ProgressHeading"
	heading.text = "EXPERIENCE"
	heading.add_theme_font_size_override("font_size", font_size)
	heading.add_theme_font_override("font", MenuTheme.heading_font(2))
	heading.add_theme_color_override("font_color", MenuTheme.GOLD)
	box.add_child(heading)

	for r in shown:
		var row := VBoxContainer.new()
		row.name = "Xp_" + String(r.get("uid", "")).validate_node_name()
		row.add_theme_constant_override("separation", 2)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		row.add_child(line)
		var label := Label.new()
		label.name = "Text"
		label.text = StoryProgression.result_line(r)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", MenuTheme.CREAM)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		if bool(r.get("leveled", false)):
			var up := Label.new()
			up.name = "LevelUp"
			up.text = "Level up!"
			up.add_theme_font_override("font", MenuTheme.heading_font(1))
			up.add_theme_font_size_override("font_size", font_size)
			up.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
			line.add_child(up)
		var bar := ProgressBar.new()
		bar.name = "XpBar"
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = clampf(float(r.get("progress", 0.0)), 0.0, 1.0)
		bar.custom_minimum_size = Vector2(0, 5)
		row.add_child(bar)
		box.add_child(row)
	return shown.size()
