extends Control

class_name UnitInfoPanel

# UI panel that displays information about the selected unit
# Updated to work with separate Unit Actions Panel

@onready var unit_name_label: Label = $MarginContainer/VBoxContainer/PortraitContainer/BasicInfoContainer/UnitNameLabel
@onready var unit_type_label: Label = $MarginContainer/VBoxContainer/PortraitContainer/BasicInfoContainer/UnitTypeLabel
@onready var health_label: Label = $MarginContainer/VBoxContainer/StatsContainer/HealthLabel
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/StatsContainer/HealthBar
@onready var attack_label: Label = $MarginContainer/VBoxContainer/StatsContainer/AttackLabel
@onready var defense_label: Label = $MarginContainer/VBoxContainer/StatsContainer/DefenseLabel
@onready var speed_label: Label = $MarginContainer/VBoxContainer/StatsContainer/SpeedLabel
@onready var movement_label: Label = $MarginContainer/VBoxContainer/StatsContainer/MovementLabel
@onready var range_label: Label = $MarginContainer/VBoxContainer/StatsContainer/RangeLabel
@onready var unit_portrait: ColorRect = $MarginContainer/VBoxContainer/PortraitContainer/UnitPortrait

var current_unit: Unit = null

## "Active Effects" section, built in CODE rather than in UnitInfoPanel.tscn so
## the scene file is untouched: the header, the chip list, and the separator above
## them are appended to the existing MarginContainer/VBoxContainer in _ready.
## Null when that container could not be resolved (a stripped test harness), in
## which case every effects path below no-ops and the panel behaves as before.
var _effects_header: Label = null
var _effects_container: VBoxContainer = null
## ScrollContainer wrapping _effects_container. When a unit has more statuses than
## fit in EFFECTS_MAX_HEIGHT, the list scrolls instead of growing the card off the
## bottom of the screen. Null in a stripped harness (same guard as the container).
var _effects_scroll: ScrollContainer = null

## The panel's authored height in UnitInfoPanel.tscn. The effects list grows the
## content, so _fit_height() expands the panel past this but never shrinks it
## below -- a unit with no statuses keeps exactly the panel size it always had.
const _BASE_HEIGHT := 280.0

## Tallest the effects list may grow before it starts scrolling. Also clamped to a
## fraction of the viewport height in _fit_height so it shrinks on short windows.
const EFFECTS_MAX_HEIGHT := 150.0

## Turn a snake_case id ("vineweave") into a display string
## ("Torvald Ironhide"). Empty in -> empty out.
func _humanize_id(id: String) -> String:
	if id == "":
		return ""
	var out: PackedStringArray = []
	for w in id.replace("_", " ").split(" ", false):
		if w.length() > 0:
			out.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(out)

func _ready() -> void:
	# Connect to game events
	GameEvents.unit_selected.connect(_on_unit_selected)
	GameEvents.unit_deselected.connect(_on_unit_deselected)
	GameEvents.unit_hover_started.connect(_on_unit_hover_started)
	GameEvents.unit_hover_ended.connect(_on_unit_hover_ended)

	# Append the effects section BEFORE theming, so the new controls pick up the
	# amber theme along with the scene-authored ones.
	_build_effects_section()

	# Match the amber HUD look (lives outside GameUILayout, so themes itself).
	ConquestTheme.apply_to(self)

	# Hide panel initially
	_hide_panel()

func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	"""Handle unit selection"""
	current_unit = unit
	_update_unit_info(unit)
	_show_panel()

func _on_unit_deselected(unit: Unit) -> void:
	"""Handle unit deselection"""
	if current_unit == unit:
		current_unit = null
		_hide_panel()

func _on_unit_hover_started(unit: Unit) -> void:
	"""Handle unit hover start - show preview info"""
	if not current_unit:  # Only show hover info if no unit is selected
		_update_unit_info(unit)
		_show_panel()

func _on_unit_hover_ended(unit: Unit) -> void:
	"""Handle unit hover end"""
	if not current_unit:  # Only hide if no unit is selected
		_hide_panel()

func _update_unit_info(unit: Unit) -> void:
	"""Update the panel with unit information"""
	if not unit:
		return
	
	# Basic info - with null checks
	if unit_name_label:
		unit_name_label.text = unit.get_display_name()
		
		# Add player ownership info
		var owner = unit.get_owner_player()
		if owner:
			unit_name_label.text += " (" + owner.get_display_name() + ")"
	
	if unit_type_label:
		# get_unit_type() returns a String (character id) post-migration.
		var unit_type: String = unit.get_unit_type()
		unit_type_label.text = _humanize_id(unit_type) if unit_type != "" else "Unknown"
	
	# Stats - with null checks
	if health_label:
		health_label.text = "Health: " + str(unit.current_health) + "/" + str(unit.max_health)
	if health_bar:
		health_bar.max_value = maxf(1.0, float(unit.max_health))
		health_bar.value = clampf(float(unit.current_health), 0.0, health_bar.max_value)
	if attack_label:
		attack_label.text = "Attack: " + str(unit.get_stat("attack"))
	if defense_label:
		defense_label.text = "Defense: " + str(unit.get_stat("defense"))
	if speed_label:
		speed_label.text = "Speed: " + str(unit.get_stat("speed"))
	if movement_label:
		movement_label.text = "Movement: " + str(unit.get_stat("movement"))
	if range_label:
		range_label.text = "Range: " + str(unit.get_stat("range"))

	# Active status conditions (immobilise, slows, buffs) -- otherwise invisible.
	_update_effects(unit)

	# Set portrait color based on unit type and player
	_update_portrait(unit)


# --- Active effects section ---------------------------------------------------

## Append the "Active Effects" header + chip list to the scene's stat VBox.
## Silently does nothing if the container is missing, leaving the panel exactly
## as authored.
func _build_effects_section() -> void:
	var vb := get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vb == null:
		return

	var sep := HSeparator.new()
	sep.name = "EffectsSeparator"
	vb.add_child(sep)

	_effects_header = Label.new()
	_effects_header.name = "EffectsLabel"
	_effects_header.text = "Active Effects"
	_effects_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_effects_header.add_theme_font_size_override("font_size", 14)
	vb.add_child(_effects_header)

	# The chip list lives inside a ScrollContainer so a unit with many statuses
	# scrolls rather than pushing the card past the bottom of the screen. Horizontal
	# scrolling is disabled so chips wrap/ellipsize to the card width instead.
	_effects_scroll = ScrollContainer.new()
	_effects_scroll.name = "EffectsScroll"
	_effects_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_effects_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_effects_scroll)

	_effects_container = VBoxContainer.new()
	_effects_container.name = "EffectsContainer"
	_effects_container.add_theme_constant_override("separation", 3)
	_effects_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effects_scroll.add_child(_effects_container)


## Repopulate the chip list for [param unit]. Always leaves exactly one of two
## states on screen: one chip per active condition, or a single muted
## "No active effects" line -- never an empty gap.
func _update_effects(unit) -> void:
	if _effects_container == null or not is_instance_valid(_effects_container):
		return

	# remove_child BEFORE queue_free: a queued-but-still-parented chip would keep
	# contributing to get_combined_minimum_size(), so _fit_height() below would
	# size the panel against the OLD unit's chips as well as the new one's.
	for child in _effects_container.get_children():
		_effects_container.remove_child(child)
		child.queue_free()

	# Empty for a null/freed unit, a unit with no StatusController, or no statuses.
	var conditions: Array = StatusVisuals.active_conditions(unit)

	if conditions.is_empty():
		var none_label := Label.new()
		none_label.text = "No active effects"
		none_label.add_theme_font_size_override("font_size", 12)
		# Muted so "nothing here" reads as secondary, not as a real effect --
		# mirrors TerrainInfoPanel's "No special effects" row.
		none_label.add_theme_color_override("font_color", ConquestTheme.INK_SOFT)
		_effects_container.add_child(none_label)
	else:
		for condition in conditions:
			if condition == null:
				continue
			_effects_container.add_child(_build_status_chip(condition))

	# Content changed height; resize after this layout pass rather than during it.
	call_deferred("_fit_height")


## One colour-coded chip for a status: a rounded panel filled with a dim version
## of the status colour and framed in that colour, holding a swatch, the status
## name, its remaining turns, and a second line describing what it does.
##
## Same construction as TerrainInfoPanel._build_effect_chip, with [StatusVisuals]
## standing in for TileEffectVisuals -- so a status chip and a tile-effect chip
## read as members of one family.
func _build_status_chip(condition) -> PanelContainer:
	var info: Dictionary = StatusVisuals.info_for(condition)
	var color: Color = info.get("color", ConquestTheme.AMBER)
	var status_name: String = String(info.get("name", "Status"))

	var chip := PanelContainer.new()

	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.35)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = color
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 1)
	chip.add_child(rows)

	# Row 1: swatch + "Ensnared" + "1 turn"
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	rows.add_child(head)

	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(10, 10)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(swatch)

	var name_label := Label.new()
	name_label.text = status_name
	name_label.add_theme_font_size_override("font_size", 12)
	# CREAM reads on the dim chip fill; the theme's default INK is tuned for the
	# light amber panel background instead.
	name_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)

	var turns_label := Label.new()
	turns_label.text = StatusVisuals.turns_label(StatusVisuals.turns_left_of(condition))
	turns_label.add_theme_font_size_override("font_size", 11)
	turns_label.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
	head.add_child(turns_label)

	# Row 2: what it actually does ("Cannot move", "-2 movement for 1 turns", …).
	# Omitted entirely when the condition has nothing describable, so a bare
	# marker status shows a one-line chip instead of a blank second row.
	var detail: String = StatusVisuals.describe_condition(condition)
	if detail != "":
		var detail_label := Label.new()
		detail_label.text = detail
		detail_label.add_theme_font_size_override("font_size", 11)
		detail_label.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(detail_label)

	return chip


## Grow the panel so the effects list is not clipped by the authored 300x280 rect,
## never shrinking below the original height.
func _fit_height() -> void:
	var vb := get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vb == null:
		return

	# Cap the effects scroll: a short list sizes to its content (no scrollbar, no gap),
	# a long one is bounded so it scrolls. The cap also shrinks on short windows.
	if _effects_scroll != null and is_instance_valid(_effects_scroll) \
			and _effects_container != null and is_instance_valid(_effects_container):
		var content_h: float = _effects_container.get_combined_minimum_size().y
		var cap := EFFECTS_MAX_HEIGHT
		var vp := get_viewport()
		if vp != null:
			cap = minf(cap, vp.get_visible_rect().size.y * 0.35)
		_effects_scroll.custom_minimum_size.y = minf(content_h, maxf(0.0, cap))

	# +24 covers the MarginContainer's 12px top and bottom margins.
	var wanted: float = vb.get_combined_minimum_size().y + 24.0
	custom_minimum_size.y = maxf(_BASE_HEIGHT, wanted)
	size.y = custom_minimum_size.y

func _update_portrait(unit: Unit) -> void:
	"""Update unit portrait based on type and player"""
	if not unit_portrait:
		return
	
	# Determine player color from owner
	var player_color = Color.GRAY
	var owner = unit.get_owner_player()
	if owner:
		player_color = owner.get_team_color()
	else:
		# Fallback to old method if no owner set
		var parent = unit.get_parent()
		if parent:
			if parent.name.to_lower().contains("player1"):
				player_color = Color.BLUE
			elif parent.name.to_lower().contains("player2"):
				player_color = Color.RED
	
	# Tint the portrait per character (unit_type is a String id now), blended
	# toward the player's colour so team still reads at a glance.
	var unit_type: String = unit.get_unit_type()
	if unit_type != "":
		var tint := Color.from_hsv(float(absi(hash(unit_type)) % 360) / 360.0, 0.5, 0.9, 1.0)
		unit_portrait.color = player_color.lerp(tint, 0.35)
	else:
		unit_portrait.color = player_color

func _show_panel() -> void:
	"""Show the info panel"""
	visible = true
	modulate.a = 1.0

func _hide_panel() -> void:
	"""Hide the info panel"""
	visible = false

# Public interface
func get_current_unit() -> Unit:
	"""Get the currently displayed unit"""
	return current_unit

func is_showing_unit(unit: Unit) -> bool:
	"""Check if panel is showing specific unit"""
	return current_unit == unit
