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
## Element-coloured monogram plate (replaces the old grey ColorRect placeholder):
## a rounded panel filled with the unit's element colour, holding its initial.
@onready var unit_portrait: PanelContainer = $MarginContainer/VBoxContainer/PortraitContainer/UnitPortrait
@onready var portrait_monogram: Label = $MarginContainer/VBoxContainer/PortraitContainer/UnitPortrait/Monogram

## The real captured portrait (game/ui/PortraitCache.gd), stacked over portrait_monogram
## inside the same PanelContainer -- PanelContainer sizes every child to its full content
## rect, so this simply covers the monogram once a texture is available. Built in CODE in
## _ready() (the .tscn stays untouched, same reasoning as the abilities/effects sections
## below). unit_portrait's rounded, element-coloured stylebox (set in _update_portrait)
## keeps acting as the "rounded frame" around whichever of the two is showing.
var _portrait_texture_rect: TextureRect = null

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

## "Abilities" section, built in CODE for the same reason as the effects section
## above (the .tscn stays untouched). Sits between the stats and the active
## effects, and hides ENTIRELY -- separator, header and list -- for a unit with no
## character or no abilities, so nothing empty is ever left on screen.
var _abilities_separator: HSeparator = null
var _abilities_header: Label = null
var _abilities_container: VBoxContainer = null
var _abilities_scroll: ScrollContainer = null

## The panel's authored height in UnitInfoPanel.tscn. The effects list grows the
## content, so _fit_height() expands the panel past this but never shrinks it
## below -- a unit with no statuses keeps exactly the panel size it always had.
const _BASE_HEIGHT := 280.0

## Tallest the effects list may grow before it starts scrolling. Also clamped to a
## fraction of the viewport height in _fit_height so it shrinks on short windows.
const EFFECTS_MAX_HEIGHT := 150.0

## Same cap for the ability list. Kept a little tighter than the effects cap so a
## unit with both a long ability list and many statuses still fits a 1280x720 window.
const ABILITIES_MAX_HEIGHT := 140.0

## Vertical space reserved at the BOTTOM of the window that this (top-anchored) card
## must never grow into. The bottom-left corner is owned by the floating
## TerrainInfoPanel (see game/ui/panels/TerrainInfoPanel.gd): a 16px margin + a
## terrain card capped at TerrainInfoPanel.MAX_HEIGHT (152px) + an 8px breathing gap.
## _fit_height caps the card's bottom edge to `vp_height - BOTTOM_RESERVE` so the Active
## Effects list scrolls inside the card instead of sliding down under the terrain card
## (the reported overlap bug).
const BOTTOM_RESERVE := 176.0

## The MarginContainer's 12px top + 12px bottom margins. The card's height is always the
## inner VBox's height plus this, so it is named rather than repeated as a magic +24.
const CHROME_HEIGHT := 24.0

## Widest any row inside the card may DEMAND: the 260px left column
## (UILayoutManager.LEFT_COLUMN_WIDTH) minus the MarginContainer's 12px each side.
const CONTENT_WIDTH := 236.0

## Floor width an autowrapping label is measured at, so its reported minimum HEIGHT is a
## stable line count rather than whatever narrow width it last saw. Leaves room for the
## 56px portrait plate + the 8px row separation inside CONTENT_WIDTH.
const WRAP_MIN_WIDTH := 150.0

## Same, for labels inside an ability / status chip: CONTENT_WIDTH minus the chip's 6px
## content margins each side and the scroll's ~12px vertical scrollbar.
const CHIP_WRAP_WIDTH := 190.0

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
	# Death is the OTHER way the panel's subject can go away; without this, current_unit
	# outlives the unit it points at (see _on_unit_eliminated).
	GameEvents.unit_eliminated.connect(_on_unit_eliminated)

	# Append the code-built sections BEFORE theming, so the new controls pick up the
	# amber theme along with the scene-authored ones. Order of the calls is the order
	# they appear under the stats: abilities (what the unit always has), then the
	# active effects (what is true right now).
	_build_abilities_section()
	_build_effects_section()
	_build_portrait_texture_rect()
	_apply_width_discipline()

	# Match the amber HUD look (lives outside GameUILayout, so themes itself).
	ConquestTheme.apply_to(self)

	# Hide panel initially
	_hide_panel()

## Keep every row inside the card's 260px column.
##
## MEASURED FAILURE: the card sat in a 260px column while its MarginContainer reported a
## 293px minimum, and a full-rect anchored child with the default GROW_DIRECTION_BOTH
## resolves an over-wide minimum by growing HALF THE EXCESS OFF EACH SIDE -- the container
## landed at x = -1.5 with width 293 inside a card at x = 15 width 260. That is both
## reported symptoms at once: the stat labels ran off the left edge of the screen and the
## HP bar ran past the card's right edge. Two rules fix it for good:
##
##   * nothing may declare a minimum wider than the column (see discipline_label), and
##   * the MarginContainer grows RIGHT only, so it can never reach off-screen even if some
##     future row does demand more.
func _apply_width_discipline() -> void:
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin != null:
		margin.grow_horizontal = Control.GROW_DIRECTION_END

	discipline_subtree(self, WRAP_MIN_WIDTH)

	if health_bar != null and is_instance_valid(health_bar):
		health_bar.custom_minimum_size.x = 0.0
		health_bar.size_flags_horizontal = Control.SIZE_FILL


## Bound one label's contribution to its row's minimum size.
##
## A NON-wrapping Label reports its whole text width as a minimum, so a long name or a
## four-digit stat widens the row past the card. Clipping with an ellipsis drops that
## minimum to 1 and trims on screen instead.
##
## An AUTOWRAPPING Label is the opposite and much nastier: Godot reports its minimum WIDTH
## as 1 and its minimum HEIGHT for whatever width it was last laid out at. A label that was
## ever ~20px wide therefore reports a THIRTEEN-line minimum height from then on -- which is
## how the portrait row came to demand 260px of the card's height budget and push the whole
## card past its budget into the squeeze. Pinning a floor width pins the line count with it.
static func discipline_label(label: Label, wrap_width: float) -> void:
	if label == null or not is_instance_valid(label):
		return
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = 0.0
	else:
		var w: float = minf(wrap_width, CONTENT_WIDTH)
		label.custom_minimum_size.x = w
		label.size.x = maxf(label.size.x, w)
		# Force a re-shape AT that width. A Label shapes its lines lazily and only when
		# something marks them dirty; a CODE-BUILT label is first shaped at width 0, where
		# it wraps to one character per line, and setting custom_minimum_size afterwards
		# invalidates the Control's cached minimum but NOT the Label's line cache. Measured,
		# TerrainInfoPanel's one-word "Terrain" heading reported a nine-line, 229px minimum
		# height forever from that initial zero-width shape -- which is what drove the
		# terrain card to 315px and off the bottom of the screen. Round-tripping the text
		# is what marks the lines dirty, so the next measurement is taken honestly.
		var text: String = label.text
		if text != "":
			label.text = ""
			label.text = text


## Apply [method discipline_label] to every Label under [param node]. Static so the chip
## builders can call it on a freshly built chip, which is the only way rows created at
## runtime get the same treatment as the scene-authored ones.
static func discipline_subtree(node: Node, wrap_width: float) -> void:
	for child in node.get_children():
		if child is Label:
			discipline_label(child, wrap_width)
		discipline_subtree(child, wrap_width)


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

func _on_unit_eliminated(unit: Unit, _eliminator: Unit) -> void:
	"""A unit died: drop it as the panel's selection.

	current_unit was only ever cleared on an explicit deselect, so killing the selected
	unit left this holding a reference that is freed a frame later -- and because
	_on_unit_hover_started gates on `if not current_unit` (true for a freed instance),
	that also permanently suppressed hover info for the rest of the match."""
	if unit != null and unit == current_unit:
		current_unit = null
		_hide_panel()

func _on_unit_hover_started(unit: Unit) -> void:
	"""Handle unit hover start - show preview info"""
	# is_instance_valid, not truthiness: a freed current_unit is still "truthy".
	if not is_instance_valid(current_unit):
		current_unit = null
	if not current_unit:  # Only show hover info if no unit is selected
		_update_unit_info(unit)
		_show_panel()

func _on_unit_hover_ended(unit: Unit) -> void:
	"""Handle unit hover end"""
	if not current_unit:  # Only hide if no unit is selected
		_hide_panel()

func _update_unit_info(unit: Unit) -> void:
	"""Update the panel with unit information"""
	# is_instance_valid, not truthiness: reached from _on_unit_selected / hover with a unit
	# that may already be freed, and every line below dereferences it.
	if not is_instance_valid(unit):
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

	# The character's passive / triggered powers -- otherwise invisible.
	_update_abilities(unit)

	# Active status conditions (immobilise, slows, buffs) -- otherwise invisible.
	_update_effects(unit)

	# Set portrait color based on unit type and player
	_update_portrait(unit)


# --- Abilities section --------------------------------------------------------

## Short human-readable label for the moment an ability fires ("Passive",
## "On kill", ...). Static + int-typed so it can be reused from other panels and
## survives an unrecognised value in an old .tres.
static func trigger_label(trigger: int) -> String:
	match trigger:
		AbilityTrigger.Trigger.PASSIVE: return "Passive"
		AbilityTrigger.Trigger.ON_TURN_START: return "Each turn"
		AbilityTrigger.Trigger.ON_TURN_END: return "Turn end"
		AbilityTrigger.Trigger.ON_MOVE: return "On move"
		AbilityTrigger.Trigger.ON_TILE_ENTER: return "On entering a tile"
		AbilityTrigger.Trigger.ON_ATTACK: return "On attack"
		AbilityTrigger.Trigger.ON_DAMAGED: return "When hit"
		AbilityTrigger.Trigger.ON_KILL: return "On kill"
		AbilityTrigger.Trigger.ON_DEATH: return "On death"
	return "Triggered"


## Append the "Abilities" header + chip list to the scene's stat VBox. Mirrors
## _build_effects_section (same separator / centered 14px header / capped scroll),
## and silently does nothing if the container is missing.
func _build_abilities_section() -> void:
	var vb := get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vb == null:
		return

	_abilities_separator = HSeparator.new()
	_abilities_separator.name = "AbilitiesSeparator"
	vb.add_child(_abilities_separator)

	_abilities_header = Label.new()
	_abilities_header.name = "AbilitiesLabel"
	_abilities_header.text = "Abilities"
	_abilities_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_abilities_header.add_theme_font_size_override("font_size", ConquestTheme.FONT_HEADER)
	vb.add_child(_abilities_header)

	# Same containment as the effects list: descriptions are full sentences, so the
	# list scrolls rather than pushing the card off the bottom of the screen.
	_abilities_scroll = ScrollContainer.new()
	_abilities_scroll.name = "AbilitiesScroll"
	_abilities_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_abilities_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_abilities_scroll)

	_abilities_container = VBoxContainer.new()
	_abilities_container.name = "AbilitiesContainer"
	_abilities_container.add_theme_constant_override("separation", 3)
	_abilities_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_abilities_scroll.add_child(_abilities_container)


## Repopulate the ability list for [param unit]. Unlike the effects list there is
## no "none" placeholder: a unit with no character / no abilities hides the whole
## section (separator + header + list) so the card looks exactly as it always did.
func _update_abilities(unit) -> void:
	if _abilities_container == null or not is_instance_valid(_abilities_container):
		return

	# remove_child BEFORE queue_free, for the same reason as _update_effects: a
	# queued-but-still-parented chip would keep contributing to the minimum size
	# _fit_height measures below.
	for child in _abilities_container.get_children():
		_abilities_container.remove_child(child)
		child.queue_free()

	var abilities: Array = _abilities_of(unit)
	var has_any := not abilities.is_empty()
	for node in [_abilities_separator, _abilities_header, _abilities_scroll]:
		if node != null and is_instance_valid(node):
			node.visible = has_any

	if has_any:
		for ability in abilities:
			if ability == null:
				continue
			_abilities_container.add_child(_build_ability_chip(unit, ability))

	# Content changed height; resize after this layout pass rather than during it.
	call_deferred("_fit_height")


## The abilities to show for [param unit]. Prefers the live [AbilitySystem]'s list
## -- that is the runtime truth, and an arena draft can grant abilities the
## character resource never declared -- and falls back to the authored
## [member CharacterResource.abilities]. Empty for a null/freed unit, a unit with
## no character, or a character with no abilities.
func _abilities_of(unit) -> Array:
	if unit == null or not is_instance_valid(unit):
		return []
	if unit.has_method("get_ability_system"):
		var system = unit.get_ability_system()
		if system != null and is_instance_valid(system) and "abilities" in system:
			var live: Array = system.abilities
			if not live.is_empty():
				return live
	if "character_resource" in unit:
		var character = unit.character_resource
		if character != null and "abilities" in character:
			return character.abilities
	return []


## Live per-unit ability state as one line ("Ready in 2 turns", "1 use left"), or
## "" when the unit has no [AbilitySystem] (nothing is tracked yet) or the ability
## is ready and unlimited. Never touches gameplay state -- both accessors are reads.
func _ability_state_text(unit, ability) -> String:
	if unit == null or ability == null or not is_instance_valid(unit):
		return ""
	if not unit.has_method("get_ability_system"):
		return ""
	var system = unit.get_ability_system()
	if system == null or not is_instance_valid(system):
		return ""
	var parts: PackedStringArray = []
	if system.has_method("cooldown_remaining"):
		var cd: int = int(system.cooldown_remaining(ability))
		if cd > 0:
			parts.append("Ready in %d turn%s" % [cd, "" if cd == 1 else "s"])
	if system.has_method("activations_left"):
		# -1 means unlimited; only a capped ability is worth reporting.
		var left: int = int(system.activations_left(ability))
		if left == 0:
			parts.append("Used up")
		elif left > 0:
			parts.append("%d use%s left" % [left, "" if left == 1 else "s"])
	return "  ·  ".join(parts)


## One chip per ability: name + trigger badge on the first row, the description
## underneath, and the live cooldown / activation line when there is one.
##
## Same construction as _build_status_chip (rounded panel, dim fill, coloured
## border, CREAM/CREAM_DIM text) so an ability chip and a status chip read as
## members of one family -- the amber here standing in for the status colour.
func _build_ability_chip(unit, ability) -> PanelContainer:
	var color: Color = ConquestTheme.AMBER

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

	# Row 1: "Grass Cutter" + "Passive"
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	rows.add_child(head)

	# Blank display_name falls back to the humanized id, so an in-progress .tres
	# still shows something recognizable rather than "New Ability" or nothing.
	var title: String = String(ability.display_name).strip_edges()
	if title == "":
		title = _humanize_id(String(ability.id))
	if title == "":
		title = "Ability"

	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", ConquestTheme.FONT_BODY)
	name_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Wraps instead of widening the chip past the 300px card on a long name.
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(name_label)

	var trigger_badge := Label.new()
	trigger_badge.text = trigger_label(int(ability.trigger))
	trigger_badge.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
	trigger_badge.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
	trigger_badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(trigger_badge)

	# Row 2: the authored description sentence. Omitted when blank, so an
	# undescribed ability shows a one-line chip instead of a blank second row.
	var description: String = String(ability.description).strip_edges()
	if description != "":
		var desc_label := Label.new()
		desc_label.text = description
		desc_label.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
		desc_label.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(desc_label)

	# Row 3: live state, only when the AbilitySystem has something to report.
	var state: String = _ability_state_text(unit, ability)
	if state != "":
		var state_label := Label.new()
		state_label.text = state
		state_label.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
		state_label.add_theme_color_override("font_color", ConquestTheme.AMBER_LITE)
		state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(state_label)

	# Same width contract as the scene-authored rows: nothing in a chip may demand more
	# than the column, and every wrapping line is measured at a fixed width.
	discipline_subtree(chip, CHIP_WRAP_WIDTH)
	return chip


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
	_effects_header.add_theme_font_size_override("font_size", ConquestTheme.FONT_HEADER)
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
		none_label.add_theme_font_size_override("font_size", ConquestTheme.FONT_BODY)
		# Muted so "nothing here" reads as secondary, not as a real effect --
		# mirrors TerrainInfoPanel's "No special effects" row.
		none_label.add_theme_color_override("font_color", ConquestTheme.INK_SOFT)
		discipline_label(none_label, CHIP_WRAP_WIDTH)
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
	name_label.add_theme_font_size_override("font_size", ConquestTheme.FONT_BODY)
	# CREAM reads on the dim chip fill; the theme's default INK is tuned for the
	# light amber panel background instead.
	name_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)

	var turns_label := Label.new()
	turns_label.text = StatusVisuals.turns_label(StatusVisuals.turns_left_of(condition))
	turns_label.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
	turns_label.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
	head.add_child(turns_label)

	# Row 2: what it actually does ("Cannot move", "-2 movement for 1 turns", …).
	# Omitted entirely when the condition has nothing describable, so a bare
	# marker status shows a one-line chip instead of a blank second row.
	var detail: String = StatusVisuals.describe_condition(condition)
	if detail != "":
		var detail_label := Label.new()
		detail_label.text = detail
		detail_label.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
		detail_label.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(detail_label)

	discipline_subtree(chip, CHIP_WRAP_WIDTH)
	return chip


## The height this card can NEVER give up: the title, the portrait row, every stat row
## and the two section headers -- i.e. the inner VBox's minimum with both scrolling lists
## collapsed to zero, plus the MarginContainer's chrome.
##
## THIS IS THE FIX FOR THE REPORTED LEFT-COLUMN MESS. `_fit_height` used to clamp the
## card's height to a bottom-reserve budget WITHOUT this floor, so on any short column
## (a taller top bar, a shorter window) the card was handed less height than its own
## content minimum. A BoxContainer that is given less than its minimum distributes
## NEGATIVE space -- which is exactly what stacked the portrait plate on top of the
## Statistics rows and left the stat labels reading "th: 8" from under it. The card may
## overflow its reserve; it may never be squeezed below this.
func fixed_content_height() -> float:
	var vb := get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vb == null:
		return _BASE_HEIGHT
	var elastic: float = 0.0
	for scroll in [_abilities_scroll, _effects_scroll]:
		if scroll != null and is_instance_valid(scroll) and scroll.visible:
			elastic += scroll.custom_minimum_size.y
	return maxf(_BASE_HEIGHT, vb.get_combined_minimum_size().y - elastic + CHROME_HEIGHT)


## Tallest this top-anchored card may be, given a window [param viewport_height], a top
## edge at [param top_y], and the card's own irreducible [param floor_h].
##
## Pure arithmetic so the 720p budget can be pinned by a test:
##   720 (window) - 121 (top: 15 margin + 56 top bar + 10 sep + 30 log chip + 10 sep)
##       - 176 (bottom reserve: 16 margin + 152 terrain card + 8 gap)  =  423px
## against a measured floor of 358px -- so the stat rows always fit and only the two
## scrolling lists absorb the difference. Never returns less than [param floor_h]: a
## budget that cannot hold the fixed rows is not a budget, it is a squeeze.
static func height_budget(viewport_height: float, top_y: float, floor_h: float) -> float:
	return maxf(floor_h, viewport_height - top_y - BOTTOM_RESERVE)


## Re-run the height fit after this frame's layout pass. Called by UILayoutManager when
## the battle log above this card changes row height (which moves this card's top edge and
## therefore its budget).
func refit() -> void:
	call_deferred("_fit_height")


## Grow the panel so the ability / effects lists are not clipped by the authored
## 300x280 rect, never shrinking below the fixed-content floor and never growing past
## the bottom-left corner reserved for the terrain card.
func _fit_height() -> void:
	var vb := get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vb == null:
		return

	var vp := get_viewport()
	var vp_height: float = vp.get_visible_rect().size.y if vp != null else 720.0

	# Cap each scroll: a short list sizes to its content (no scrollbar, no gap), a
	# long one is bounded so it scrolls. The caps also shrink on short windows.
	var abilities_h := _cap_scroll(_abilities_scroll, _abilities_container,
			minf(ABILITIES_MAX_HEIGHT, vp_height * 0.28))
	var effects_h := _cap_scroll(_effects_scroll, _effects_container,
			minf(EFFECTS_MAX_HEIGHT, vp_height * 0.35))

	var wanted: float = vb.get_combined_minimum_size().y + CHROME_HEIGHT
	var pool: float = abilities_h + effects_h
	# Everything that is NOT one of the two scrolling lists (see fixed_content_height).
	var floor_h: float = maxf(_BASE_HEIGHT, wanted - pool)

	# Backstop: never grow past the bottom-left corner reserved for the terrain card.
	# The card is TOP-anchored (in the LeftSidebar VBox, size_flags_vertical =
	# SHRINK_BEGIN), so its top edge is GLOBAL -- position.y is container-local (~0) and
	# would let the budget balloon to nearly the full window height, sliding the card down
	# under the bottom-left TerrainInfoPanel. Measure from global_position.y and stop
	# BOTTOM_RESERVE px short of the window bottom. Any overflow comes out of the two
	# SCROLLING lists (proportionally), never the stat rows -- the lists scroll sooner.
	var top_y: float = global_position.y
	var budget: float = height_budget(vp_height, top_y, floor_h)
	if wanted > budget and pool > 0.0:
		var scale: float = maxf(0.0, pool - (wanted - budget)) / pool
		var used: float = _cap_scroll(_abilities_scroll, _abilities_container, abilities_h * scale)
		used += _cap_scroll(_effects_scroll, _effects_container, effects_h * scale)
		# Recompute rather than assuming `budget`: the two lists round to their own
		# content heights, so the card ends up at the floor plus whatever they took.
		wanted = floor_h + used

	custom_minimum_size.y = maxf(floor_h, wanted)
	size.y = custom_minimum_size.y


## Size [param scroll] to its content, clamped to [param cap], and report the
## height it ended up using. 0 for a missing or hidden list, so callers budgeting
## vertical space do not reserve any for it.
func _cap_scroll(scroll: ScrollContainer, content: Control, cap: float) -> float:
	if scroll == null or not is_instance_valid(scroll) or not scroll.visible:
		return 0.0
	if content == null or not is_instance_valid(content):
		return 0.0
	var used: float = minf(content.get_combined_minimum_size().y, maxf(0.0, cap))
	scroll.custom_minimum_size.y = used
	return used

## Build the TextureRect that shows a real captured portrait, stacked over the monogram
## Label inside unit_portrait. Starts hidden -- _clear_portrait_texture (called from every
## _update_portrait) is what decides whether it or the monogram is showing.
func _build_portrait_texture_rect() -> void:
	if unit_portrait == null:
		return
	_portrait_texture_rect = TextureRect.new()
	_portrait_texture_rect.name = "PortraitTexture"
	_portrait_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# THE root cause of the reported left-column mess. A TextureRect's DEFAULT expand mode
	# is EXPAND_KEEP_SIZE, which reports the texture's own size as its minimum -- and
	# PortraitCache captures at 256x256. So the moment a real portrait resolved (from the
	# on-disk cache, i.e. immediately on any machine that had played before), this 56x56
	# plate demanded 256x256: measured, it drove the portrait ROW to 260x260, the card's
	# content to 418x538 inside a 260-wide, 423-tall card, and from there every reported
	# symptom followed at once -- the MarginContainer overflowed both side edges (stat
	# labels off the left of the screen, HP bar past the right) and the inner VBox was
	# handed less than its minimum, so it stacked the portrait on the Statistics rows.
	# IGNORE_SIZE lets the plate be whatever size the layout gives it.
	_portrait_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_texture_rect.visible = false
	unit_portrait.add_child(_portrait_texture_rect)


func _update_portrait(unit: Unit) -> void:
	"""Paint the monogram plate: the unit's initial on its element colour.

	A compact element-coded stand-in for real portrait art, and the fallback shown until
	(or whenever) PortraitCache has no real capture for this unit's character. Element
	comes from Unit.get_element() -> ConquestTheme.element_color; the letter is dark
	ink on light element colours and cream on dark ones so it always reads."""
	if not unit_portrait:
		return

	var element: String = String(unit.get_element()) if unit.has_method("get_element") else ""
	var base: Color = ConquestTheme.element_color(element)

	# Rounded, element-filled plate with a slightly darker warm border -- this frame stays
	# up (visible around / behind) whichever of the monogram or the real portrait is shown.
	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = base.darkened(0.35)
	unit_portrait.add_theme_stylebox_override("panel", sb)

	if portrait_monogram:
		var display: String = unit.get_display_name().strip_edges()
		portrait_monogram.text = display.substr(0, 1).to_upper() if display != "" else "?"
		var text_color: Color = ConquestTheme.INK if base.get_luminance() > 0.55 else ConquestTheme.CREAM
		portrait_monogram.add_theme_color_override("font_color", text_color)

	_refresh_portrait_texture(unit)


# --- Real portrait (PortraitCache) ------------------------------------------------------

## Show the real captured portrait for [param unit]'s character if PortraitCache already
## has it cached, and either way (re)issue a request so a not-yet-captured character swaps
## the monogram out the moment its portrait resolves. Never blocks -- the monogram plate
## from _update_portrait above stays visible until (if ever) a texture arrives.
func _refresh_portrait_texture(unit: Unit) -> void:
	if _portrait_texture_rect == null:
		return

	var character_id: String = unit.get_unit_type() if unit.has_method("get_unit_type") else ""
	if character_id.is_empty():
		_clear_portrait_texture()
		return

	var cached: Texture2D = PortraitCache.get_cached(character_id)
	if cached != null:
		_apply_portrait_texture(cached)
		return

	_clear_portrait_texture()
	PortraitCache.get_portrait(character_id, _on_portrait_resolved.bind(unit, character_id))


func _apply_portrait_texture(tex: Texture2D) -> void:
	if _portrait_texture_rect == null:
		return
	_portrait_texture_rect.texture = tex
	_portrait_texture_rect.visible = true
	if portrait_monogram:
		portrait_monogram.visible = false


func _clear_portrait_texture() -> void:
	if _portrait_texture_rect != null:
		_portrait_texture_rect.visible = false
	if portrait_monogram:
		portrait_monogram.visible = true


## PortraitCache resolution callback. [param unit] / [param character_id] are the unit and
## character id this request was made FOR, bound at request time -- a slow capture must
## never clobber the panel once the player has selected someone else (or the same unit's
## character somehow changed, e.g. a skin swap), so both are re-checked against the live
## current_unit before applying.
func _on_portrait_resolved(tex: Texture2D, unit: Unit, character_id: String) -> void:
	if tex == null:
		return
	if not is_instance_valid(unit) or current_unit != unit:
		return
	var live_id: String = unit.get_unit_type() if unit.has_method("get_unit_type") else ""
	if live_id != character_id:
		return
	_apply_portrait_texture(tex)

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
