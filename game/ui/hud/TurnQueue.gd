extends Control

class_name TurnQueue

# Unified UI component for Speed First turn system
# Combines turn indicator and queue display into one cohesive interface

@onready var main_container: VBoxContainer = $MainContainer
@onready var current_unit_container: VBoxContainer = $MainContainer/CurrentUnitContainer
@onready var current_unit_label: Label = $MainContainer/CurrentUnitContainer/CurrentUnitLabel
@onready var round_info_label: Label = $MainContainer/CurrentUnitContainer/RoundInfoLabel
@onready var queue_section: VBoxContainer = $MainContainer/QueueSection
@onready var queue_title_label: Label = $MainContainer/QueueSection/QueueTitle
@onready var queue_controls: HBoxContainer = $MainContainer/QueueSection/QueueControls
@onready var scroll_left_button: Button = $MainContainer/QueueSection/QueueControls/ScrollLeftButton
@onready var queue_container: HBoxContainer = $MainContainer/QueueSection/QueueControls/QueueContainer
@onready var scroll_right_button: Button = $MainContainer/QueueSection/QueueControls/ScrollRightButton

var turn_system: SpeedFirstTurnSystem = null
var unit_portraits: Array[Control] = []

# Chip settings -- compact so the strip stays a slim top bar, not a screen-eater.
# Row budget: 8 chips * 66 + 7 * 4 separation = ~556px + paging buttons ~= 640px, so the
# whole queue occupies barely half the top instead of spanning the screen.
const PORTRAIT_SIZE := Vector2(66, 50)
const PORTRAIT_MARGIN := 4
const PORTRAITS_PER_PAGE := 8  # Slim strip; paging reaches the rest of a big roster

# Warm/cool side colors (the amber theme is warm-only, so ally/enemy tints live here).
const COLOR_ALLY_BG := Color(0.16, 0.30, 0.52, 0.92)      # cool blue
const COLOR_ALLY_BORDER := Color(0.45, 0.66, 0.92, 1.0)
const COLOR_ENEMY_BG := Color(0.52, 0.18, 0.16, 0.92)     # warm red
const COLOR_ENEMY_BORDER := Color(0.92, 0.50, 0.45, 1.0)
const COLOR_NEUTRAL_BG := Color(0.28, 0.26, 0.22, 0.92)
const COLOR_NEUTRAL_BORDER := Color(0.6, 0.58, 0.52, 1.0)

# Scroll state
var scroll_offset: int = 0
var total_units: int = 0

# Signals for interaction
signal unit_portrait_clicked(unit: Unit)
signal unit_portrait_hovered(unit: Unit)
signal unit_portrait_unhovered(unit: Unit)

func _ready() -> void:
	# Set proper mouse filtering - only capture events over actual UI elements
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let clicks pass through empty areas

	visible = true

	# Connect scroll buttons
	if scroll_left_button:
		scroll_left_button.pressed.connect(_on_scroll_left_pressed)
	if scroll_right_button:
		scroll_right_button.pressed.connect(_on_scroll_right_pressed)

	# Connect to turn system events
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
	else:
		push_warning("TurnQueue: TurnSystemManager not found!")

	# Initial setup
	_update_display()

func _on_turn_system_activated(system: TurnSystemBase) -> void:
	"""Handle turn system activation"""
	if system is SpeedFirstTurnSystem:
		turn_system = system as SpeedFirstTurnSystem

		# Connect to turn system events
		if turn_system.turn_started.is_connected(_on_turn_started):
			turn_system.turn_started.disconnect(_on_turn_started)
		if turn_system.turn_ended.is_connected(_on_turn_ended):
			turn_system.turn_ended.disconnect(_on_turn_ended)

		turn_system.turn_started.connect(_on_turn_started)
		turn_system.turn_ended.connect(_on_turn_ended)

		_update_display()
		visible = true
	else:
		# Hide for non-speed-first systems
		turn_system = null
		visible = false

func _on_turn_started(_player_or_unit) -> void:
	"""Handle turn start"""
	_update_display()

func _on_turn_ended(_player_or_unit) -> void:
	"""Handle turn end"""
	_update_display()

func _update_display() -> void:
	"""Update the unified turn display"""
	if not queue_container:
		return

	# Clear existing portraits (but preserve scroll_offset)
	_clear_portraits()

	if not turn_system:
		_show_inactive_state()
		return

	# Get current turn information
	var current_unit = turn_system.get_current_acting_unit()
	var progress = turn_system.get_current_round_progress()
	var queue = turn_system.get_turn_queue()

	# Update current unit display
	_update_current_unit_display(current_unit, progress)

	# Update queue display
	_update_queue_display(queue, current_unit)

func _show_inactive_state() -> void:
	"""Show inactive state when no turn system is active"""
	if current_unit_label:
		current_unit_label.text = "No Active Turn System"
	if round_info_label:
		round_info_label.text = "Waiting for game to start..."
	if queue_title_label:
		queue_title_label.text = "Turn Queue (Inactive)"

func _update_current_unit_display(current_unit: Unit, progress: Dictionary) -> void:
	"""Update the current unit information display"""
	if not current_unit_label or not round_info_label:
		return

	if current_unit and is_instance_valid(current_unit):
		# Show current acting unit with player info
		var player = current_unit.get_owner_player()
		var player_name = player.get_display_name() if player else "Unknown"
		current_unit_label.text = current_unit.get_display_name() + " Acting (" + player_name + ")"

		# Show detailed round and speed info (simplified for center display)
		var round_num = progress.get("round_number", 1)
		var current_speed = progress.get("current_unit_speed", 0)
		var units_remaining = progress.get("units_remaining", 0)

		round_info_label.text = "Round " + str(round_num) + " • Speed: " + str(current_speed) + " • " + str(units_remaining) + " units left"
	else:
		current_unit_label.text = "No Acting Unit"
		round_info_label.text = "Round " + str(progress.get("round_number", 1))

func _update_queue_display(queue: Array, current_unit: Unit) -> void:
	"""Update the turn queue display with scroll functionality"""
	if not queue_title_label:
		return

	total_units = queue.size()

	# Ensure scroll_offset is within valid bounds
	var max_scroll: int = maxi(0, total_units - PORTRAITS_PER_PAGE)
	scroll_offset = clampi(scroll_offset, 0, max_scroll)

	# Update queue title with scroll info
	var visible_count: int = mini(PORTRAITS_PER_PAGE, total_units)
	var page_info := ""
	if total_units > PORTRAITS_PER_PAGE:
		var current_page: int = (scroll_offset / PORTRAITS_PER_PAGE) + 1
		var total_pages: int = (total_units + PORTRAITS_PER_PAGE - 1) / PORTRAITS_PER_PAGE
		page_info = " (Page " + str(current_page) + "/" + str(total_pages) + ")"

	queue_title_label.text = "Upcoming Turns (" + str(visible_count) + "/" + str(total_units) + " shown)" + page_info

	# Update scroll button states
	_update_scroll_buttons()

	# Create portraits for visible units
	var start_index: int = scroll_offset
	var end_index: int = mini(start_index + PORTRAITS_PER_PAGE, total_units)

	for i in range(start_index, end_index):
		var unit = queue[i]
		# Skip a unit that died and was freed since the queue was built (Speed mode frees
		# units mid-round). Calling get_display_name/get_stat on it crashes ("previously
		# freed"), which is exactly the "enemy attacked then crashed" report.
		if unit == null or not is_instance_valid(unit):
			continue
		var is_current: bool = (unit == current_unit)
		var portrait = _create_unit_portrait(unit, is_current, i)
		queue_container.add_child(portrait)
		unit_portraits.append(portrait)

func _update_scroll_buttons() -> void:
	"""Update scroll button enabled states"""
	if not scroll_left_button or not scroll_right_button:
		return

	# Left button: enabled if we can scroll left
	scroll_left_button.disabled = (scroll_offset <= 0)

	# Right button: enabled if we can scroll right
	var max_scroll: int = maxi(0, total_units - PORTRAITS_PER_PAGE)
	scroll_right_button.disabled = (scroll_offset >= max_scroll)

	# Hide buttons if not needed
	var needs_scrolling: bool = total_units > PORTRAITS_PER_PAGE
	scroll_left_button.visible = needs_scrolling
	scroll_right_button.visible = needs_scrolling

func _on_scroll_left_pressed() -> void:
	"""Handle left scroll button press"""
	if scroll_offset > 0:
		scroll_offset = maxi(0, scroll_offset - PORTRAITS_PER_PAGE)
		_update_display()

func _on_scroll_right_pressed() -> void:
	"""Handle right scroll button press"""
	var max_scroll: int = maxi(0, total_units - PORTRAITS_PER_PAGE)
	if scroll_offset < max_scroll:
		scroll_offset = mini(max_scroll, scroll_offset + PORTRAITS_PER_PAGE)
		_update_display()

func _clear_portraits() -> void:
	"""Clear all unit portraits"""
	for portrait in unit_portraits:
		if portrait and is_instance_valid(portrait):
			portrait.queue_free()
	unit_portraits.clear()

	# Also clear any remaining children
	if queue_container:
		for child in queue_container.get_children():
			child.queue_free()

	# Note: Don't reset scroll_offset here - it should persist across updates

func _create_unit_portrait(unit: Unit, is_current: bool, queue_position: int) -> Control:
	"""Create a compact turn-order chip for a unit.

	Layout (non-overlapping fixed rects, top to bottom):
	  position/NOW  ->  unit name (elided)  ->  SPD:n
	Colors: ally = cool blue, enemy = warm red, current = bright amber highlight.
	"""
	var chip := Control.new()
	chip.custom_minimum_size = PORTRAIT_SIZE
	chip.mouse_filter = Control.MOUSE_FILTER_PASS

	# Store unit reference for interaction / highlight lookup
	chip.set_meta("unit", unit)

	var chip_w: float = PORTRAIT_SIZE.x
	var chip_h: float = PORTRAIT_SIZE.y

	# --- Background panel (must remain child index 0 for highlight_portrait) ---
	var background := Panel.new()
	background.size = PORTRAIT_SIZE
	background.position = Vector2.ZERO
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style_box := StyleBoxFlat.new()
	var amber: Color = _theme_color("AMBER", Color(0.90, 0.65, 0.29))
	var brown_dk: Color = _theme_color("BROWN_DK", Color(0.22, 0.13, 0.06))
	if is_current:
		style_box.bg_color = amber
		style_box.border_color = _theme_color("CREAM", Color(0.99, 0.94, 0.84))
		style_box.set_border_width_all(3)
	else:
		var player = unit.get_owner_player()
		if player and player.player_id == 0:
			style_box.bg_color = COLOR_ALLY_BG
			style_box.border_color = COLOR_ALLY_BORDER
		elif player and player.player_id == 1:
			style_box.bg_color = COLOR_ENEMY_BG
			style_box.border_color = COLOR_ENEMY_BORDER
		else:
			style_box.bg_color = COLOR_NEUTRAL_BG
			style_box.border_color = COLOR_NEUTRAL_BORDER
		style_box.set_border_width_all(2)

	style_box.set_corner_radius_all(7)
	background.add_theme_stylebox_override("panel", style_box)
	chip.add_child(background)

	# --- Real portrait (PortraitCache), inset so the background panel's border stays
	# visible all the way around it -- that border is exactly what carries the
	# current/ally/enemy state (and highlight_portrait's selection ring), so the portrait
	# must never cover it. A dim scrim sits between the photo and the text so the text's
	# colours (tuned for the flat background) keep reading over any portrait's own colours.
	var portrait_inset: float = 3.0
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.position = Vector2(portrait_inset, portrait_inset)
	portrait.size = Vector2(chip_w - portrait_inset * 2.0, chip_h - portrait_inset * 2.0)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.clip_contents = true
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.visible = false
	chip.add_child(portrait)

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.30)
	scrim.position = portrait.position
	scrim.size = portrait.size
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.visible = false
	chip.add_child(scrim)

	var character_id: String = unit.get_unit_type() if unit.has_method("get_unit_type") else ""
	if not character_id.is_empty():
		var cached_portrait: Texture2D = PortraitCache.get_cached(character_id)
		if cached_portrait != null:
			_apply_chip_portrait(portrait, scrim, cached_portrait)
		else:
			PortraitCache.get_portrait(character_id, _on_chip_portrait_resolved.bind(portrait, scrim))

	# --- Position / NOW label (top strip) ---
	var pos_label := Label.new()
	if is_current:
		pos_label.text = "NOW"
		pos_label.add_theme_color_override("font_color", brown_dk)
	else:
		pos_label.text = str(queue_position + 1)
		pos_label.add_theme_color_override("font_color", _theme_color("CREAM", Color.WHITE))
	pos_label.position = Vector2(0, 2)
	pos_label.size = Vector2(chip_w, 14)
	pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pos_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pos_label.add_theme_font_size_override("font_size", 11)
	pos_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	pos_label.add_theme_constant_override("shadow_offset_x", 1)
	pos_label.add_theme_constant_override("shadow_offset_y", 1)
	pos_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(pos_label)

	# --- Unit name label (elided if long) ---
	var name_label := Label.new()
	name_label.text = unit.get_display_name()
	name_label.position = Vector2(3, 17)
	name_label.size = Vector2(chip_w - 6, 16)
	name_label.custom_minimum_size = Vector2(chip_w - 6, 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", brown_dk if is_current else Color(0.99, 0.94, 0.84))
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(name_label)

	# --- Speed label (bottom strip) ---
	var speed_label := Label.new()
	var current_speed = turn_system.get_unit_current_speed(unit) if turn_system else unit.get_stat("speed")
	speed_label.text = "SPD:" + str(current_speed)
	speed_label.position = Vector2(0, chip_h - 16)
	speed_label.size = Vector2(chip_w, 14)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speed_label.add_theme_font_size_override("font_size", 10)
	speed_label.add_theme_color_override("font_color", brown_dk if is_current else Color(0.90, 0.90, 0.90))
	speed_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	speed_label.add_theme_constant_override("shadow_offset_x", 1)
	speed_label.add_theme_constant_override("shadow_offset_y", 1)
	speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(speed_label)

	# --- Invisible click overlay (on top, receives input, draws nothing) ---
	var button := Button.new()
	button.size = PORTRAIT_SIZE
	button.custom_minimum_size = PORTRAIT_SIZE
	button.position = Vector2.ZERO
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	# Fully transparent in every state so only the chip visuals show through.
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	button.add_theme_stylebox_override("disabled", empty)

	button.pressed.connect(_on_portrait_clicked.bind(unit))
	button.mouse_entered.connect(_on_portrait_hovered.bind(unit))
	button.mouse_exited.connect(_on_portrait_unhovered.bind(unit))

	chip.add_child(button)

	return chip

## Show [param tex] on a chip's portrait TextureRect and its readability scrim together --
## the two always toggle as a pair.
func _apply_chip_portrait(portrait: TextureRect, scrim: ColorRect, tex: Texture2D) -> void:
	portrait.texture = tex
	portrait.visible = true
	scrim.visible = true


## PortraitCache resolution callback for one chip. Chips are rebuilt wholesale on every
## _update_display, so by the time a slow first capture resolves the chip it was requested
## for may already be freed (turn advanced, queue rescrolled) -- is_instance_valid guards
## that; a stale-but-still-valid chip is harmless to update since it is about to be replaced
## anyway.
func _on_chip_portrait_resolved(tex: Texture2D, portrait: TextureRect, scrim: ColorRect) -> void:
	if tex == null:
		return
	if not is_instance_valid(portrait) or not is_instance_valid(scrim):
		return
	_apply_chip_portrait(portrait, scrim, tex)


func _theme_color(name: String, fallback: Color) -> Color:
	"""Fetch a ConquestTheme palette color by constant name.

	ConquestTheme is a global class_name in this project; we access its palette
	constants directly here and fall back to a tasteful warm color if a name is
	not mapped, so this HUD never depends on hardcoded magic numbers elsewhere.
	"""
	match name:
		"AMBER":
			return ConquestTheme.AMBER
		"CREAM":
			return ConquestTheme.CREAM
		"BROWN_DK":
			return ConquestTheme.BROWN_DK
		_:
			return fallback

func _on_portrait_clicked(unit: Unit) -> void:
	"""Handle portrait click - show unit details"""
	# `unit` was BOUND into this callback when the portrait row was built, so it can be a
	# unit that has since died -- global_position below would raise, and the emit would
	# hand a freed instance to every unit_selected listener at once.
	if not is_instance_valid(unit):
		return
	unit_portrait_clicked.emit(unit)

	# Also trigger unit info panel to show details
	GameEvents.unit_selected.emit(unit, unit.global_position)

func _on_portrait_hovered(unit: Unit) -> void:
	"""Handle portrait hover - show preview info"""
	unit_portrait_hovered.emit(unit)

func _on_portrait_unhovered(unit: Unit) -> void:
	"""Handle portrait unhover - hide preview info"""
	unit_portrait_unhovered.emit(unit)

# Public interface
func get_displayed_queue_size() -> int:
	"""Get the number of units currently displayed in the queue"""
	return unit_portraits.size()

func is_queue_visible() -> bool:
	"""Check if the turn queue is currently visible"""
	return visible and turn_system != null

func get_unit_at_queue_position(position: int) -> Unit:
	"""Get the unit at a specific position in the queue"""
	if turn_system and position >= 0:
		var queue = turn_system.get_turn_queue()
		if position < queue.size():
			return queue[position]
	return null

func scroll_to_unit(unit: Unit) -> bool:
	"""Scroll the queue to show a specific unit"""
	if not turn_system:
		return false

	var queue = turn_system.get_turn_queue()
	var unit_index: int = queue.find(unit)

	if unit_index >= 0:
		# Calculate which page this unit is on
		var target_page: int = unit_index / PORTRAITS_PER_PAGE
		scroll_offset = target_page * PORTRAITS_PER_PAGE
		_update_display()
		return true

	return false

func reset_scroll() -> void:
	"""Reset scroll to the beginning"""
	scroll_offset = 0
	_update_display()

func get_scroll_info() -> Dictionary:
	"""Get current scroll information"""
	return {
		"offset": scroll_offset,
		"total_units": total_units,
		"portraits_per_page": PORTRAITS_PER_PAGE,
		"current_page": (scroll_offset / PORTRAITS_PER_PAGE) + 1,
		"total_pages": (total_units + PORTRAITS_PER_PAGE - 1) / PORTRAITS_PER_PAGE if total_units > 0 else 1
	}

func highlight_portrait(unit: Unit, highlight: bool) -> void:
	"""Highlight a specific unit's portrait"""
	for portrait in unit_portraits:
		var portrait_unit = portrait.get_meta("unit", null)
		if portrait_unit == unit:
			var background = portrait.get_child(0)  # Background panel
			if background is Panel:
				var style_box = background.get_theme_stylebox("panel").duplicate()
				if highlight:
					style_box.border_color = Color.YELLOW
					style_box.set_border_width_all(3)
				else:
					style_box.border_color = Color(0.8, 0.8, 0.8, 0.8)
					style_box.set_border_width_all(1)
				background.add_theme_stylebox_override("panel", style_box)
			break
