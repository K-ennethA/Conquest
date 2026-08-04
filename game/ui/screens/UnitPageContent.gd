extends RefCounted
class_name UnitPageContent

## Shared builder for the FULL unit page -- identity tags, the stat table, one card per
## move and one per ability -- used by BOTH surfaces that show one:
##
##   * the Compendium's [UnitGallery] (browse the roster out of battle), and
##   * the in-battle [UnitDetailPage] (the DETAILS overlay on a selected unit).
##
## It was EXTRACTED from UnitGallery rather than written beside it, so there is exactly
## one place that decides how a move card reads. The gallery keeps its browsing shell
## (search / filter / sort / pager / 3D turntable); everything below the "what does this
## unit actually do" line lives here and the gallery now calls in.
##
## Two things the gallery never needed, both OPTIONAL and both inert when the caller
## passes nothing -- which is why the compendium's output is unchanged by the move:
##
##   * LIVE state. [param live] on a card carries the running battle's numbers (a move's
##     remaining cooldown and uses, an ability's remaining activations), so the same card
##     reads "Ready in 2 turns" in battle and stays clean in the compendium.
##   * EFFECTIVE stats. [method build_stat_table] takes an optional live unit and renders
##     `base → effective` through [MoveStatVisuals] -- the same helper pair gameplay reads
##     -- so a buffed unit's page can never disagree with the combat forecast.
##
## Dark [MenuTheme] register throughout: both callers are full-screen pages that step out
## of the amber battle HUD, exactly as [PauseMenu] does.

# --- Card accents -------------------------------------------------------------
# Move cards are colour-coded by damage category so a moveset is scannable at a glance;
# the element (when authored) is named in the small type tag on the card.
const CAT_PHYSICAL := Color("c9cbd6")   # steel grey
const CAT_MAGICAL := Color("a860e0")    # arcane violet
const CAT_TRUE := Color("f0913c")       # piercing orange
const ABILITY_ACCENT := Color("5fb84e") # passives read as "nature" green

const MUTED := Color(0.72, 0.70, 0.78)

# --- The `live` dictionary -----------------------------------------------------
#
# Keys are named constants rather than bare strings so a caller that mistypes one gets a
# compile-time symbol error instead of a silently missing readout. EVERY key is optional;
# an absent key means "nothing live to say", which is precisely the compendium's case.
const LIVE_COOLDOWN_REMAINING := "cooldown_remaining"
const LIVE_COOLDOWN_TOTAL := "cooldown_total"
const LIVE_USES_LEFT := "uses_left"
const LIVE_ACTIVATIONS_LEFT := "activations_left"


# ---------------------------------------------------------------------------
# Live state, read off a unit
# ---------------------------------------------------------------------------

## The battle-time state of [param move] on [param unit]:
## [code]{ cooldown_remaining, cooldown_total, uses_left }[/code].
##
## Empty for a null/freed unit or one with no [MovesetController] -- so a caller can hand
## the result straight to [method build_move_card] and get the compendium's static card.
## Every access is duck-typed: this is read from a battle overlay that must survive a unit
## whose combat components were never built (a stripped test harness, a preview).
static func live_move_state(unit, move) -> Dictionary:
	var out: Dictionary = {}
	if unit == null or move == null or typeof(unit) != TYPE_OBJECT or not is_instance_valid(unit):
		return out
	if not unit.has_method("get_moveset_controller"):
		return out
	var controller = unit.get_moveset_controller()
	if controller == null or not is_instance_valid(controller):
		return out
	if controller.has_method("remaining"):
		out[LIVE_COOLDOWN_REMAINING] = int(controller.remaining(move))
	if "cooldown" in move:
		out[LIVE_COOLDOWN_TOTAL] = int(move.cooldown)
	if controller.has_method("uses_left"):
		out[LIVE_USES_LEFT] = int(controller.uses_left(move))
	return out


## The battle-time state of [param ability] on [param unit]:
## [code]{ cooldown_remaining, activations_left }[/code]. Same contract as
## [method live_move_state] -- empty means "render the static card".
static func live_ability_state(unit, ability) -> Dictionary:
	var out: Dictionary = {}
	if unit == null or ability == null or typeof(unit) != TYPE_OBJECT or not is_instance_valid(unit):
		return out
	if not unit.has_method("get_ability_system"):
		return out
	var system = unit.get_ability_system()
	if system == null or not is_instance_valid(system):
		return out
	if system.has_method("cooldown_remaining"):
		out[LIVE_COOLDOWN_REMAINING] = int(system.cooldown_remaining(ability))
	if "cooldown" in ability:
		out[LIVE_COOLDOWN_TOTAL] = int(ability.cooldown)
	if system.has_method("activations_left"):
		out[LIVE_ACTIVATIONS_LEFT] = int(system.activations_left(ability))
	return out


## The abilities to show for [param unit]: the live [AbilitySystem]'s list when it has one
## (that is the runtime truth -- an Arena draft can grant abilities the character resource
## never declared), else the authored [member CharacterResource.abilities].
static func abilities_of(unit) -> Array:
	if unit == null or typeof(unit) != TYPE_OBJECT or not is_instance_valid(unit):
		return []
	if unit.has_method("get_ability_system"):
		var system = unit.get_ability_system()
		if system != null and is_instance_valid(system) and "abilities" in system:
			var live: Array = system.abilities
			if not live.is_empty():
				return live
	if "character_resource" in unit and unit.character_resource != null:
		return unit.character_resource.abilities
	return []


# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

## The one-line tag strip under a unit's name: its id, boss/standard, a non-1x1
## footprint, and the move / ability counts. Empty in -> empty out.
static func identity_tags(character) -> String:
	if character == null:
		return ""
	var tags: Array[String] = []
	var id_text: String = String(character.character_id)
	if not id_text.is_empty():
		tags.append(id_text)
	tags.append("Boss" if character.is_boss else "Standard")
	var footprint: Vector2i = character.get_footprint()
	if footprint != Vector2i.ONE:
		tags.append("%dx%d" % [footprint.x, footprint.y])
	tags.append("%d moves" % character.move_count())
	tags.append("%d abilities" % character.ability_count())
	return "  -  ".join(tags)


# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------

## One row per stat: [code]{ label, base, effective, modified }[/code].
##
## With [param unit] null every row is unmodified and reads the character's authored base
## -- the compendium's case. With a live unit each row is read through
## [method MoveStatVisuals.stat_info], i.e. the unit's own `get_stat` / `get_base_stat`
## pair, so every timed buff, item and status shows up with no per-source knowledge here.
static func stat_rows(character, unit = null) -> Array:
	var specs: Array = [
		["Attack", "attack", "base_attack"],
		["Defense", "defense", "base_defense"],
		["Magic", "magic", "base_magic"],
		["Magic Def", "magic_defense", "base_magic_defense"],
		["Speed", "speed", "base_speed"],
		["Movement", "movement", "base_movement"],
		["Range", "range", "attack_range"],
	]
	var rows: Array = []
	for spec in specs:
		var label: String = String(spec[0])
		var authored: int = 0
		if character != null and String(spec[2]) in character:
			authored = int(character.get(String(spec[2])))
		if unit != null and typeof(unit) == TYPE_OBJECT and is_instance_valid(unit):
			var info: Dictionary = MoveStatVisuals.stat_info(unit, String(spec[1]), label)
			rows.append({
				"label": label,
				"base": int(info.get("base", authored)),
				"effective": int(info.get("effective", authored)),
				"modified": bool(info.get("modified", false)),
			})
		else:
			rows.append({"label": label, "base": authored, "effective": authored, "modified": false})
	return rows


## The full stat table: HP first (live current/max when there is a unit), then every row
## from [method stat_rows] as `base → effective` with the [MoveStatVisuals] arrow and
## tint, then the character's power budget and movement profile.
static func build_stat_table(character, unit = null) -> Control:
	var box := VBoxContainer.new()
	box.name = "StatTable"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)

	var grid := GridContainer.new()
	grid.name = "StatGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)

	# Health is deliberately NOT one of stat_rows(): out of battle it is a single authored
	# maximum, in battle it is "how much is left", and those are different questions.
	var hp_text: String = ""
	if unit != null and typeof(unit) == TYPE_OBJECT and is_instance_valid(unit) \
			and "current_health" in unit:
		hp_text = "%d / %d" % [int(unit.current_health), int(unit.max_health)]
	elif character != null:
		hp_text = str(character.base_health)
	if hp_text != "":
		_stat_pair(grid, "Health", hp_text, MenuTheme.CREAM)

	for row in stat_rows(character, unit):
		var base: int = int(row["base"])
		var effective: int = int(row["effective"])
		var value_text: String = str(base)
		if MoveStatVisuals.is_modified(base, effective):
			value_text = "%d → %d%s" % [base, effective,
					MoveStatVisuals.delta_suffix(base, effective)]
		_stat_pair(grid, String(row["label"]), value_text,
				MoveStatVisuals.delta_color(base, effective, MenuTheme.CREAM))

	if character != null:
		_stat_pair(grid, "Power", str(character.power_budget()), MenuTheme.CREAM)
		var profile: MovementProfile = character.get_movement_profile()
		if profile != null:
			var profile_row := Label.new()
			profile_row.text = "Movement profile: %s" % profile.display_name
			profile_row.modulate = MUTED
			profile_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(profile_row)

	return box


static func _stat_pair(grid: GridContainer, key: String, value: String, color: Color) -> void:
	var key_label := Label.new()
	key_label.text = key + ":"
	key_label.modulate = MUTED
	grid.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_color_override("font_color", color)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value_label)


# ---------------------------------------------------------------------------
# Moves
# ---------------------------------------------------------------------------

## One card for [param move]: name + element/category tag, description, the scannable
## stat line, its effect list, and -- only when [param live] carries them -- the running
## battle's cooldown / uses.
static func build_move_card(move: MoveResource, live: Dictionary = {}) -> PanelContainer:
	var accent: Color = category_color(move.category)

	var card := PanelContainer.new()
	# Named per MOVE, not just "MoveCard". Sibling names must be unique, so a second plain
	# "MoveCard" is silently mangled by the engine into "@MoveCard@<n>" -- which makes the
	# node tree unreadable in the remote inspector and makes any name query over the page
	# quietly return one card per section instead of all of them.
	card.name = _card_name("MoveCard", move.move_id)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", MenuTheme.card_box(accent))

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(body)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(header)

	var move_name: String = move.display_name
	if move_name.is_empty():
		move_name = String(move.move_id)
	if move_name.is_empty():
		move_name = "(Unnamed move)"

	var name_label := Label.new()
	name_label.text = move_name
	name_label.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	header.add_child(MenuTheme.make_chip(move_tag_text(move), accent))

	var desc_text: String = move.description.strip_edges()
	if desc_text.is_empty():
		desc_text = "No description."
	body.add_child(wrapped_label(desc_text))

	var stats := Label.new()
	stats.text = move_stats_text(move)
	stats.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	stats.modulate = MUTED
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(stats)

	var effect_text: String = join_effects(move.effects)
	if not effect_text.is_empty():
		var effects_label := wrapped_label("Effect: " + effect_text)
		effects_label.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
		body.add_child(effects_label)

	var state: String = live_move_text(live)
	if state != "":
		body.add_child(_live_label(state))

	return card


## The live line for a move card ("Recharging: 2 turns left (of 3)  ·  1 use left"), or
## "" when the move is ready and unlimited -- so a ready move renders exactly as the
## compendium's static card rather than carrying a blank badge.
static func live_move_text(live: Dictionary) -> String:
	var parts: PackedStringArray = []
	var remaining: int = int(live.get(LIVE_COOLDOWN_REMAINING, 0))
	if remaining > 0:
		var total: int = int(live.get(LIVE_COOLDOWN_TOTAL, 0))
		if total > 0:
			parts.append("Recharging: %s left (of %d)"
					% [MoveStatVisuals.cooldown_label(remaining), total])
		else:
			parts.append("Recharging: %s left" % MoveStatVisuals.cooldown_label(remaining))
	# -1 is the unlimited sentinel; only a CAPPED move is worth reporting.
	var uses: int = int(live.get(LIVE_USES_LEFT, -1))
	if uses == 0:
		parts.append("Used up")
	elif uses > 0:
		parts.append("%d use%s left" % [uses, "" if uses == 1 else "s"])
	return "  ·  ".join(parts)


## e.g. "Nature / Physical", or just "Physical" when no element is authored.
static func move_tag_text(move: MoveResource) -> String:
	var name_text: String = category_name(move.category)
	var element_text: String = String(move.element).strip_edges()
	if element_text.is_empty():
		return name_text
	return "%s / %s" % [element_text.capitalize(), name_text]


## Cooldown, uses, cost, accuracy, crit and range as one scannable line.
static func move_stats_text(move: MoveResource) -> String:
	var parts: Array[String] = []

	if move.cooldown > 0:
		parts.append("Cooldown %d turn%s" % [move.cooldown, "" if move.cooldown == 1 else "s"])
	else:
		parts.append("No cooldown")

	if move.max_uses == 1:
		parts.append("Once per battle")
	elif move.max_uses > 1:
		parts.append("%d uses per battle" % move.max_uses)

	if move.energy_cost > 0:
		parts.append("Cost %d" % move.energy_cost)

	parts.append("Accuracy %d%%" % as_percent(move.accuracy))
	parts.append("Crit %d%%" % as_percent(move.crit_chance))

	var targeting: TargetingPattern = move.targeting
	if targeting != null:
		if targeting.min_range == targeting.max_range:
			parts.append("Range %d" % targeting.max_range)
		else:
			parts.append("Range %d-%d" % [targeting.min_range, targeting.max_range])
		parts.append("Targets %s" % target_kind_name(targeting.target_kind))
		if targeting.area_shape != CombatTypes.AreaShape.SINGLE:
			parts.append("Area %s %d" % [area_shape_name(targeting.area_shape), targeting.area_size])
	else:
		parts.append("No targeting pattern")

	return "   -   ".join(parts)


# ---------------------------------------------------------------------------
# Abilities
# ---------------------------------------------------------------------------

## One card for [param ability]: name + trigger chip, description, the stat line, its
## effect list, its action-economy rules, and the live cooldown / activations from
## [param live] when there are any.
static func build_ability_card(ability: AbilityResource, live: Dictionary = {}) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = _card_name("AbilityCard", ability.id)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", MenuTheme.card_box(ABILITY_ACCENT))

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(body)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(header)

	var ability_name: String = ability.display_name
	if ability_name.is_empty():
		ability_name = String(ability.id)
	if ability_name.is_empty():
		ability_name = "(Unnamed ability)"

	var name_label := Label.new()
	name_label.text = ability_name
	name_label.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	header.add_child(MenuTheme.make_chip(trigger_label(ability.trigger), ABILITY_ACCENT))

	var desc_text: String = ability.description.strip_edges()
	if desc_text.is_empty():
		desc_text = "No description."
	body.add_child(wrapped_label(desc_text))

	var stats := Label.new()
	stats.text = ability_stats_text(ability)
	stats.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	stats.modulate = MUTED
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(stats)

	var effect_text: String = join_effects(ability.effects)
	if not effect_text.is_empty():
		var effects_label := wrapped_label("Effect: " + effect_text)
		effects_label.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
		body.add_child(effects_label)

	var rules_text: String = rule_modifiers_text(ability)
	if not rules_text.is_empty():
		var rules_label := wrapped_label("Rules: " + rules_text)
		rules_label.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
		body.add_child(rules_label)

	var state: String = live_ability_text(live)
	if state != "":
		body.add_child(_live_label(state))

	return card


## The live line for an ability card ("Ready in 2 turns  ·  1 use left"), or "" when it is
## ready and unlimited.
static func live_ability_text(live: Dictionary) -> String:
	var parts: PackedStringArray = []
	var remaining: int = int(live.get(LIVE_COOLDOWN_REMAINING, 0))
	if remaining > 0:
		parts.append("Ready in %d turn%s" % [remaining, "" if remaining == 1 else "s"])
	var left: int = int(live.get(LIVE_ACTIVATIONS_LEFT, -1))
	if left == 0:
		parts.append("Used up")
	elif left > 0:
		parts.append("%d use%s left" % [left, "" if left == 1 else "s"])
	return "  ·  ".join(parts)


static func ability_stats_text(ability: AbilityResource) -> String:
	var parts: Array[String] = []

	parts.append("Trigger: %s" % trigger_label(ability.trigger))

	if ability.cooldown > 0:
		parts.append("Cooldown %d turn%s" % [ability.cooldown, "" if ability.cooldown == 1 else "s"])
	else:
		parts.append("No cooldown")

	if ability.max_activations == 1:
		parts.append("Once per battle")
	elif ability.max_activations > 1:
		parts.append("%d activations per battle" % ability.max_activations)
	else:
		parts.append("Unlimited activations")

	var condition: AbilityCondition = ability.condition
	if condition != null:
		parts.append("Condition: %s" % condition.describe())

	if ability.targets_triggering_unit:
		parts.append("Applies to the triggering unit")

	var targeting: TargetingPattern = ability.targeting
	if targeting != null:
		parts.append("Area %s (%s)" % [area_shape_name(targeting.area_shape), targeting.describe_range()])

	return "   -   ".join(parts)


## Action-economy tweaks ("extra_actions": 1 -> "Extra actions: 1").
static func rule_modifiers_text(ability: AbilityResource) -> String:
	var modifiers: Dictionary = ability.rule_modifiers
	if modifiers.is_empty():
		return ""
	var parts: Array[String] = []
	for key in modifiers.keys():
		parts.append("%s: %s" % [str(key).capitalize(), str(modifiers[key])])
	return ", ".join(parts)


# ---------------------------------------------------------------------------
# Statuses (battle-only -- the compendium browses the CATALOG, not a live unit)
# ---------------------------------------------------------------------------

## One card per ACTIVE status on [param unit], grouped by id so three stacked Poisoned
## instances read as one "Poisoned x3" card rather than three identical ones. Empty array
## for a unit with no [StatusController] or no statuses, so the caller can render its own
## "nothing on this unit" line.
static func build_status_cards(unit) -> Array:
	var out: Array = []
	for group in StatusVisuals.group_by_id(StatusVisuals.active_conditions(unit)):
		var condition = group.get("condition", null)
		if condition == null:
			continue
		out.append(_build_status_card(
				condition,
				int(group.get("count", 1)),
				int(group.get("turns_left", StatusVisuals.TURNS_FROM_CONDITION))))
	return out


static func _build_status_card(condition, count: int, turns_left: int) -> PanelContainer:
	var info: Dictionary = StatusVisuals.info_for(condition)
	var accent: Color = info.get("color", MenuTheme.GOLD)

	var card := PanelContainer.new()
	card.name = _card_name("StatusCard", condition.id if "id" in condition else &"")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", MenuTheme.card_box(accent))

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(body)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(header)

	# The SAME one-line vocabulary the compact battle card and the hover panel use:
	# "◆ Poisoned x3 · 2 turns". One phrasing across every surface that names a status.
	var name_label := Label.new()
	name_label.text = StatusVisuals.chip_text(condition, count, turns_left)
	name_label.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	header.add_child(MenuTheme.make_chip(String(info.get("kind", "neutral")).capitalize(), accent))

	var detail: String = StatusVisuals.describe_condition(condition)
	if detail == "":
		detail = "No further effect."
	body.add_child(wrapped_label(detail))

	return card


# ---------------------------------------------------------------------------
# Small shared helpers
# ---------------------------------------------------------------------------

## "MoveCard_root_slam" -- a card node name that is unique among its siblings and still
## begins with the card KIND, so a `find_children("MoveCard*")` over the page reaches every
## card of that kind. Godot's own uniquifier would produce "@MoveCard@41", which matches no
## readable pattern and reads as noise in the remote scene tree.
## Characters Node names forbid (`. : @ / " %`) are stripped from the id.
static func _card_name(kind: String, id: StringName) -> String:
	var suffix: String = String(id).validate_node_name().strip_edges()
	if suffix == "":
		return kind
	return "%s_%s" % [kind, suffix]


## Summarise a move/ability by joining every effect's own describe().
static func join_effects(effects: Array) -> String:
	var parts: Array[String] = []
	for effect in effects:
		if effect == null:
			continue
		var described: String = str(effect.describe()).strip_edges()
		if not described.is_empty():
			parts.append(described)
	return "; ".join(parts)


static func wrapped_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


static func muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = MUTED
	return label


static func section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	label.add_theme_color_override("font_color", MenuTheme.GOLD)
	return label


## The amber "this is happening right now" line on a card. Named so both card builders
## produce an identically-styled live readout.
static func _live_label(text: String) -> Label:
	var label := Label.new()
	label.name = "LiveState"
	label.text = text
	label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	label.add_theme_color_override("font_color", MenuTheme.GOLD)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## Detach and free every child. Detaching FIRST matters because queue_free() is deferred:
## without it, paging would briefly stack the outgoing unit's cards under the incoming
## one's -- and the stale children would keep contributing to the container's minimum size.
static func clear_container(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## 0..1 -> 0..100, clamped so an odd authored value can't print nonsense.
static func as_percent(value: float) -> int:
	return roundi(clampf(value, 0.0, 1.0) * 100.0)


static func category_name(category: int) -> String:
	match category:
		CombatTypes.DamageCategory.PHYSICAL:
			return "Physical"
		CombatTypes.DamageCategory.MAGICAL:
			return "Magical"
		CombatTypes.DamageCategory.TRUE:
			return "True"
	return "Unknown"


static func category_color(category: int) -> Color:
	match category:
		CombatTypes.DamageCategory.MAGICAL:
			return CAT_MAGICAL
		CombatTypes.DamageCategory.TRUE:
			return CAT_TRUE
	return CAT_PHYSICAL


static func target_kind_name(kind: int) -> String:
	match kind:
		CombatTypes.TargetKind.SELF:
			return "self"
		CombatTypes.TargetKind.ALLY:
			return "allies"
		CombatTypes.TargetKind.ENEMY:
			return "enemies"
		CombatTypes.TargetKind.ANY_UNIT:
			return "any unit"
		CombatTypes.TargetKind.TILE:
			return "tiles"
		CombatTypes.TargetKind.EMPTY_TILE:
			return "empty tiles"
	return "unknown"


static func area_shape_name(shape: int) -> String:
	match shape:
		CombatTypes.AreaShape.SINGLE:
			return "single"
		CombatTypes.AreaShape.CROSS:
			return "cross"
		CombatTypes.AreaShape.SQUARE:
			return "square"
		CombatTypes.AreaShape.DIAMOND:
			return "diamond"
		CombatTypes.AreaShape.LINE:
			return "line"
		CombatTypes.AreaShape.ARC:
			return "arc"
	return "unknown"


## Readable label for an AbilityTrigger.Trigger value (ON_TURN_START -> "On turn start").
static func trigger_label(trigger: int) -> String:
	match trigger:
		AbilityTrigger.Trigger.PASSIVE:
			return "Passive"
		AbilityTrigger.Trigger.ON_TURN_START:
			return "On turn start"
		AbilityTrigger.Trigger.ON_TURN_END:
			return "On turn end"
		AbilityTrigger.Trigger.ON_MOVE:
			return "On move"
		AbilityTrigger.Trigger.ON_TILE_ENTER:
			return "On tile enter"
		AbilityTrigger.Trigger.ON_ATTACK:
			return "On attack"
		AbilityTrigger.Trigger.ON_DAMAGED:
			return "On damaged"
		AbilityTrigger.Trigger.ON_KILL:
			return "On kill"
		AbilityTrigger.Trigger.ON_DEATH:
			return "On death"
	return "Unknown trigger"


## Turn a snake_case id ("vineweave") into a display string ("Vineweave").
## Empty in -> empty out.
static func humanize_id(id: String) -> String:
	if id == "":
		return ""
	var out: PackedStringArray = []
	for w in id.replace("_", " ").split(" ", false):
		if w.length() > 0:
			out.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(out)
