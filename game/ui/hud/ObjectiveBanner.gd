extends PanelContainer

class_name ObjectiveBanner

## The persistent "what does WINNING mean here?" line in the battle HUD.
##
## Maps have had modular, per-map win conditions for a long time ([WinCondition] +
## [WinConditionLibrary], compiled from [member MapResource.victory_conditions]) and the
## HUD said NOTHING about them: a player mid-battle could see whose turn it was and how
## many units were left to act, but not whether they were meant to kill a boss, flatten a
## base, or simply outlast a timer. This is that missing line -- one row, always on
## screen, reading the SAME resources the engine scores.
##
## PLACEMENT IS STRUCTURAL, NOT TUNED. This is a row of the HUD's own
## [code]CenterTopContainer[/code] VBox, directly under the [TurnIndicator] chip
## ([code]UILayoutManager._build_objective_banner[/code]). Two consequences, both free:
##
##   * it CANNOT overlap the turn chip -- they are siblings in a BoxContainer, so the
##     container owns the arithmetic rather than a hand-picked offset; and
##   * it cannot overlap the [ActionAnnouncer] either, because adding this row grows the
##     TopBar and the announcer already parks itself below the LIVE top bar
##     ([method ActionAnnouncer.banner_top] of the measured bar bottom). The banner
##     follows the taller bar with no change on its side.
##
## Kept at [constant ROW_HEIGHT] for exactly that reason: the row's height is what the
## rest of the top band budgets against (see the top-bar arithmetic block in
## [UILayoutManager]), so it is a declared constant rather than whatever the font
## happens to measure.
##
## REPLAYS KEEP IT. Unlike the transport-only chrome ([ReplayHUD]) this is not a control
## -- it is context, and "what was this player trying to do?" is exactly what a watcher
## needs. It is never hidden.
##
## LIVE, AND OFF THE RIGHT SIGNAL. The line is re-derived on the ACTIVE turn system's
## turn_started / turn_ended (CONQUEST.md convention 2 -- PlayerManager's turn signals do
## not fire on AI turns, so a countdown wired to them would freeze the moment the enemy
## started acting) and on roster changes, so "Survive 6 more turns" really counts down and
## "Defeat Eldroot the Hollow Crown" really names the boss standing in front of you.

# --- Geometry ----------------------------------------------------------------

## The row's declared height. See the class note: the top band's arithmetic spends this.
const ROW_HEIGHT: float = 24.0
## Widest the line may grow before it starts eliding, so a wordy multi-objective map
## cannot stretch the top bar across the whole screen.
const MAX_WIDTH: float = 560.0

# --- Wording -----------------------------------------------------------------

## Objective mark. A right-pointing guillemet reads as "here is the thing to do" and --
## the part that actually decides it -- the theme font CAN DRAW IT. The pennant this
## started as (⚑ U+2691) is tofu in Godot's default font, i.e. an empty box on every
## battle HUD in the game; so is every Geometric-Shapes arrow. See the probe table in
## `unit/test_status_feedback.gd` for the measured drawable set, and
## [code]test_every_character_the_banner_can_emit_is_one_the_font_can_draw[/code] in
## `unit/test_objective_banner.gd` for the pin that keeps this honest.
const PREFIX: String = "» "
## Shown when nothing at all resolves -- no map, no rules, no challenge. Every shipped map
## can at minimum be won by clearing the field, so this is the honest floor rather than a
## blank row.
const FALLBACK_TEXT: String = "Defeat all enemies"
## Suffix naming the objectives that did not fit. The rest are in the tooltip.
const MORE_SUFFIX: String = "   +%d more"

const LABEL_NAME: String = "ObjectiveLabel"

# --- Colours (explicit, like every other self-styled HUD layer) --------------

const TEXT_COLOR: Color = ConquestTheme.CREAM
const FRAME_COLOR: Color = ConquestTheme.BORDER_SOFT
## The gold objective gem's colour (the grove HUD's "this is the thing to do" accent).
const MARK_COLOR: Color = ConquestTheme.GOLD
## The "Danger zone" tag's colour: the enemy-threat overlay's violet
## (DangerZoneOverlay.ZONE_COLOR, opaque, lightened 0.4) so it reads as text on navy.
const DANGER_COLOR: Color = Color(0.772, 0.472, 0.97)

## Node names of the row's pieces (tests / screenshots look them up by name).
const ROW_NAME: String = "Row"
const TAG_NAME: String = "ObjectiveTag"
const DANGER_NAME: String = "DangerTag"

# --- State -------------------------------------------------------------------

var _label: Label = null
var _row: HBoxContainer = null
var _tag: Label = null
## The violet "Danger zone" tag, shown while the enemy-threat overlay is on
## ([signal GameEvents.danger_zone_changed]). Folded in from the cloud ObjectiveChip.
var _danger_chip: PanelContainer = null
var _danger_on: bool = false

## The objectives currently on screen, as [WinCondition] resources.
var _conditions: Array = []

## False once a caller has handed us objectives explicitly ([method set_objectives]), so a
## later turn tick re-scores THOSE rather than silently reverting to the map's.
var _auto_resolve: bool = true

## Turn ENDS observed since the active turn system was (re)wired. This is what feeds the
## neutral state's "turn" key, and therefore what a [SurviveTurns] objective counts down
## against. Counted here rather than read off the turn system's own `current_turn` because
## that field is a running player-switch counter, not "turns elapsed since the battle
## started", which is the quantity [WinCondition] documents.
var _turns_elapsed: int = 0

var _watched_system: TurnSystemBase = null


# ===========================================================================
# Pure text assembly (statics, so the wording is pinned without a scene)
# ===========================================================================

## The single line drawn for [param lines] (each an objective's own phrasing).
##
## The FIRST objective is the one shown -- "primary" is the order the map authored, which
## is also the order [WinConditionLibrary] compiles -- and the rest are counted, never
## crammed in. The full list lives in the tooltip ([method tooltip_text_for]).
static func banner_text(lines: Array) -> String:
	var kept: Array = _non_empty(lines)
	if kept.is_empty():
		return PREFIX + FALLBACK_TEXT
	var text: String = PREFIX + String(kept[0])
	if kept.size() > 1:
		text += MORE_SUFFIX % (kept.size() - 1)
	return text


## Hover text listing EVERY objective, one per row. "" when there is at most one, so a
## single-objective map shows no tooltip rather than a tooltip repeating the line above it.
static func tooltip_text_for(lines: Array) -> String:
	var kept: Array = _non_empty(lines)
	if kept.size() <= 1:
		return ""
	var rows: Array[String] = []
	for line in kept:
		rows.append("• " + String(line))
	return "\n".join(rows)


static func _non_empty(lines: Array) -> Array:
	var out: Array = []
	for line in lines:
		var s: String = String(line).strip_edges()
		if s != "":
			out.append(s)
	return out


# ===========================================================================
# Construction
# ===========================================================================

func _ready() -> void:
	# PASS, not IGNORE: a control the hit test never returns can never show a tooltip, and
	# the tooltip is where a multi-objective map lists the objectives that did not fit.
	# PASS still lets the press through to whatever is underneath.
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(0.0, ROW_HEIGHT)

	_build_ui()
	_wire_turn_system()
	_wire_roster()

	if _auto_resolve:
		_resolve_objectives()
	refresh()


## The row, in the grove HUD register (the look the cloud ObjectiveChip had):
##   [gold gem] OBJECTIVE  » Defeat the boss   [Danger zone]
## a gold cut gem (drawn, not a glyph -- the Geometric Shapes block is tofu in the engine
## font), a gold Cinzel "OBJECTIVE" section tag, the cream objective line, and the violet
## danger-zone tag while that overlay is on.
func _build_ui() -> void:
	# Self-styled: keep the HUD-wide ConquestTheme.apply_to() sweep from swapping this
	# slim strip for the full card frame.
	ConquestTheme.keep_style(self)
	add_theme_stylebox_override("panel", _row_box())

	_row = HBoxContainer.new()
	_row.name = ROW_NAME
	_row.add_theme_constant_override("separation", 8)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)

	var gem := GroveGem.new()
	gem.name = "ObjectiveGem"
	gem.color = MARK_COLOR
	gem.custom_minimum_size = Vector2(10, 14)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(gem)

	_tag = Label.new()
	_tag.name = TAG_NAME
	_tag.text = "OBJECTIVE"
	_tag.theme_type_variation = &"SectionLabel"
	# Stated explicitly as well, so the tag reads right with or without the HUD theme.
	_tag.add_theme_font_override("font", MenuTheme.heading_font(2))
	_tag.add_theme_font_size_override("font_size", ConquestTheme.FS_CAPTION)
	_tag.add_theme_color_override("font_color", ConquestTheme.GOLD)
	_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_tag)

	_label = Label.new()
	_label.name = LABEL_NAME
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_label)

	_danger_chip = ConquestTheme.chip("Danger zone", DANGER_COLOR, ConquestTheme.FS_CAPTION)
	_danger_chip.name = DANGER_NAME
	_danger_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var danger_box := ConquestTheme.chip_style(DANGER_COLOR)
	danger_box.content_margin_top = 0
	danger_box.content_margin_bottom = 0
	_danger_chip.add_theme_stylebox_override("panel", danger_box)
	_danger_chip.visible = false
	_row.add_child(_danger_chip)


## A slim grove chip (notched navy plate, fine grain, gold filigree): the same register as
## the [TurnIndicator] chip it hangs under, so it reads as that chip's second line rather
## than as a competing card. The tight vertical margins keep the declared
## [constant ROW_HEIGHT].
func _row_box() -> OrnateStyleBox:
	var sb := ConquestTheme.chip_box(FRAME_COLOR, 0.9)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


## True while the violet "Danger zone" tag is showing.
func is_danger_zone_shown() -> bool:
	return _danger_on


# ===========================================================================
# Public interface
# ===========================================================================

## Show [param conditions] (an [Array] of [WinCondition]) instead of whatever this battle's
## map declares. Pins the banner to them: later turn ticks re-score THESE.
func set_objectives(conditions: Array) -> void:
	_auto_resolve = false
	_conditions = []
	for c in conditions:
		if c != null:
			_conditions.append(c)
	refresh()


## Show the objectives compiled from [param condition_strings] -- the same authored
## strings a map carries in [member MapResource.victory_conditions].
func set_objective_strings(condition_strings: Array) -> void:
	set_objectives(WinConditionLibrary.build_win_conditions(
			condition_strings, WinConditionLibrary.HUMAN_FACTION))


## The objectives currently on screen.
func objectives() -> Array:
	return _conditions.duplicate()


## Turn ENDS counted since the active turn system was wired -- what a survive objective
## counts down against.
func turns_elapsed() -> int:
	return _turns_elapsed


## The line as it is drawn right now.
func text() -> String:
	return _label.text if _label != null and is_instance_valid(_label) else ""


## The per-objective lines behind [method text], each already refined by live state.
func objective_lines() -> Array:
	var state: Dictionary = _live_state()
	var out: Array = []
	for c in _conditions:
		if c == null:
			continue
		var line: String = ""
		if c.has_method("describe_progress"):
			line = String(c.describe_progress(state))
		elif c.has_method("describe"):
			line = String(c.describe())
		if line.strip_edges() != "":
			out.append(line)
	return out


## Re-derive the line from the live board and repaint. Cheap enough to run on every turn
## boundary and every roster change.
func refresh() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	var lines: Array = objective_lines()
	_label.text = banner_text(lines)
	tooltip_text = tooltip_text_for(lines)
	if _danger_chip != null and is_instance_valid(_danger_chip):
		_danger_chip.visible = _danger_on
	_fit_width()


## Keep the plate wide enough for the line it currently draws, capped at
## [constant MAX_WIDTH]. Mirrors [code]TurnIndicator._fit_chip_width[/code]: a clipped
## Label reports a 1px minimum, so without this the row would be drawn as a stub.
##
## The row's other pieces (gem, tag, danger tag) and the frame's side margins come off the
## cap first, so the whole strip -- not just its text -- stays inside MAX_WIDTH.
func _fit_width() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	var chrome: float = _chrome_width()
	var needed: float = ElementVisuals.fit_label(_label, maxf(48.0, MAX_WIDTH - chrome))
	custom_minimum_size = Vector2(minf(needed + chrome, MAX_WIDTH), ROW_HEIGHT)


## Width the strip spends on everything but the objective text: the frame's side margins
## plus every other visible row piece and the gaps between them.
func _chrome_width() -> float:
	var w: float = 0.0
	var box: StyleBox = get_theme_stylebox("panel")
	if box != null:
		w += box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
	if _row == null or not is_instance_valid(_row):
		return w + 24.0
	var sep: int = _row.get_theme_constant("separation")
	var shown: int = 0
	for c in _row.get_children():
		if not (c is Control) or not (c as Control).visible:
			continue
		shown += 1
		if c != _label:
			w += (c as Control).get_combined_minimum_size().x
	return w + float(maxi(0, shown - 1) * sep)


# ===========================================================================
# Where the objectives come from
# ===========================================================================

## Populate [member _conditions] from whatever this battle actually is.
##
## Order matters. A CHALLENGE in survive mode is scored by [ChallengeController] against
## the author's turn target, NOT by the map's own compiled rules (the map keeps running
## its own objective underneath -- see ChallengeController._maybe_latch_survive_win), so
## the challenge's target is what the player must be told. Everything else reads the
## loaded map's authored [member MapResource.victory_conditions] through the same
## [WinConditionLibrary] the runtime scores, so the banner can never drift from the rules.
func _resolve_objectives() -> void:
	_conditions = []

	var survive: WinCondition = _challenge_survive_objective()
	if survive != null:
		_conditions.append(survive)
		return

	var map_resource = _current_map()
	if map_resource == null:
		return
	var authored = map_resource.get("victory_conditions")
	if authored == null or not (authored is Array) or (authored as Array).is_empty():
		return
	for c in WinConditionLibrary.build_win_conditions(
			authored as Array, WinConditionLibrary.HUMAN_FACTION):
		_conditions.append(c)


## A [SurviveTurns] standing in for the live challenge's "hold out N rounds" rule, or null
## when this is not a survive challenge. Synthesised rather than read off the map because
## the target lives in the challenge blob, not in the map.
func _challenge_survive_objective() -> WinCondition:
	var ctrl := get_node_or_null("/root/ChallengeController")
	if ctrl == null or not ctrl.has_method("is_capturing") or not bool(ctrl.is_capturing()):
		return null
	if not ctrl.has_method("active_challenge"):
		return null
	var challenge: Dictionary = ctrl.active_challenge()
	if ChallengeCodec.rules_mode(challenge) != ChallengeCodec.MODE_SURVIVE:
		return null
	var st := SurviveTurns.new()
	st.turns = ChallengeCodec.rules_survive_turns(challenge)
	st.faction = WinConditionLibrary.HUMAN_FACTION
	# The banner never decides anything; require_survivor would only make evaluate() report
	# FAILED, which nothing here reads.
	st.require_survivor = false
	return st


## The [MapResource] this battle loaded, via the battle's own [GameWorldManager] (found by
## its group, exactly as the campaign/challenge controllers reach the runtime without
## editing it). Null outside a battle.
func _current_map():
	var gwm := get_tree().get_first_node_in_group("game_world_manager") if get_tree() != null else null
	if gwm == null or not is_instance_valid(gwm):
		return null
	var loader = gwm.get("map_loader")
	if loader == null or not is_instance_valid(loader):
		return null
	if loader.has_method("get_current_map"):
		return loader.get_current_map()
	return null


# ===========================================================================
# The state the objectives are scored against
# ===========================================================================

## The neutral state dictionary a [WinCondition] reads (schema: WinCondition.gd).
##
## Deliberately the same shape [code]GameWorldManager._build_win_state[/code] assembles,
## minus the just-removed unit (which only matters on the death tick, and this is a
## readout rather than a decision). "turn" is the count of turn ENDS observed, which is
## the quantity a survive objective counts down.
func _live_state() -> Dictionary:
	var units: Array = []
	var board = null
	if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null \
			and CombatServices.has_method("board"):
		board = CombatServices.board()
	if board != null and board.has_method("all_units"):
		for u in board.all_units():
			if u != null and is_instance_valid(u):
				units.append(u)
	return {"units": units, "board": board, "turn": _elapsed_for_state()}


## Turns elapsed, from whichever source owns the count for this battle. A survive
## CHALLENGE is scored on the CHALLENGER's own turns (ChallengeController's tally), so the
## countdown on screen must match the tally that will end the run -- not this node's
## both-sides count, which would run out roughly twice as fast.
func _elapsed_for_state() -> int:
	var ctrl := get_node_or_null("/root/ChallengeController")
	if ctrl != null and ctrl.has_method("is_capturing") and bool(ctrl.is_capturing()) \
			and ctrl.has_method("capture_counters"):
		var counters: Dictionary = ctrl.capture_counters()
		return int(counters.get("turns", 0))
	return _turns_elapsed


# ===========================================================================
# Live wiring
# ===========================================================================

func _wire_turn_system() -> void:
	if typeof(TurnSystemManager) != TYPE_OBJECT or TurnSystemManager == null:
		return
	if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
	# The HUD is routinely mounted AFTER the system activates, so the one-shot signal above
	# would be missed and the countdown would never tick.
	if TurnSystemManager.has_active_turn_system():
		_on_turn_system_activated(TurnSystemManager.get_active_turn_system())


func _wire_roster() -> void:
	if typeof(GameEvents) != TYPE_OBJECT or GameEvents == null:
		return
	# A boss dying or a wave spawning changes which objective line is true, and neither goes
	# through the turn system's signals.
	if GameEvents.has_signal("unit_eliminated") \
			and not GameEvents.unit_eliminated.is_connected(_on_roster_changed):
		GameEvents.unit_eliminated.connect(_on_roster_changed)
	if GameEvents.has_signal("unit_spawned") \
			and not GameEvents.unit_spawned.is_connected(_on_roster_changed):
		GameEvents.unit_spawned.connect(_on_roster_changed)
	# The enemy-threat overlay toggling on / off shows / hides the "Danger zone" tag.
	if GameEvents.has_signal("danger_zone_changed") \
			and not GameEvents.danger_zone_changed.is_connected(_on_danger_zone_changed):
		GameEvents.danger_zone_changed.connect(_on_danger_zone_changed)


## (Re)subscribe to the ACTIVE turn system. The previous one is dropped first so a
## mid-session switch can never leave two live subscriptions double-counting turns.
func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	if _watched_system == turn_system:
		return
	if _watched_system != null and is_instance_valid(_watched_system):
		if _watched_system.turn_started.is_connected(_on_turn_started):
			_watched_system.turn_started.disconnect(_on_turn_started)
		if _watched_system.turn_ended.is_connected(_on_turn_ended):
			_watched_system.turn_ended.disconnect(_on_turn_ended)
	_watched_system = turn_system
	# A fresh system is a fresh battle: the countdown starts over.
	_turns_elapsed = 0
	if turn_system != null and is_instance_valid(turn_system):
		if not turn_system.turn_started.is_connected(_on_turn_started):
			turn_system.turn_started.connect(_on_turn_started)
		if not turn_system.turn_ended.is_connected(_on_turn_ended):
			turn_system.turn_ended.connect(_on_turn_ended)
	if _auto_resolve:
		_resolve_objectives()
	refresh()


func _on_turn_started(_player = null) -> void:
	refresh()


func _on_turn_ended(_player = null) -> void:
	_turns_elapsed += 1
	refresh()


func _on_danger_zone_changed(active: bool, _cell_count: int = 0) -> void:
	_danger_on = active
	refresh()


func _on_roster_changed(_a = null, _b = null) -> void:
	# A death unregisters the unit inside the same emission; read the board after it unwinds.
	call_deferred("refresh")


func _exit_tree() -> void:
	# The autoloads outlive this battle HUD, so drop every hook -- a stale instance must
	# never be called after the battle scene is gone.
	if typeof(TurnSystemManager) == TYPE_OBJECT and TurnSystemManager != null \
			and TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.disconnect(_on_turn_system_activated)
	if _watched_system != null and is_instance_valid(_watched_system):
		if _watched_system.turn_started.is_connected(_on_turn_started):
			_watched_system.turn_started.disconnect(_on_turn_started)
		if _watched_system.turn_ended.is_connected(_on_turn_ended):
			_watched_system.turn_ended.disconnect(_on_turn_ended)
	_watched_system = null
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null:
		if GameEvents.has_signal("unit_eliminated") \
				and GameEvents.unit_eliminated.is_connected(_on_roster_changed):
			GameEvents.unit_eliminated.disconnect(_on_roster_changed)
		if GameEvents.has_signal("unit_spawned") \
				and GameEvents.unit_spawned.is_connected(_on_roster_changed):
			GameEvents.unit_spawned.disconnect(_on_roster_changed)
		if GameEvents.has_signal("danger_zone_changed") \
				and GameEvents.danger_zone_changed.is_connected(_on_danger_zone_changed):
			GameEvents.danger_zone_changed.disconnect(_on_danger_zone_changed)
