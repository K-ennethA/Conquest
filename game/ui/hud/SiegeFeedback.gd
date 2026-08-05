extends PanelContainer

class_name SiegeFeedback

## The two things SIEGE has to say that no other HUD surface already says:
##
##   1. THE COMEBACK. A squad unit that dies in Siege is not gone -- [SiegeController]
##      walks it back out of your base after [member SiegeRuleset.respawn_delay_rounds].
##      Without a readout, losing a unit reads exactly like losing it in Skirmish, which is
##      the wrong emotion for a push mode. This is a compact row that names the fallen and
##      counts down.
##   2. THE ALARM. A capture STARTING is the most urgent event in the mode, and it begins on
##      the enemy's turn while the player is watching the board. One [ActionAnnouncer] line
##      fires on that transition -- through the banner the game already flashes every move
##      on, not a second toast layer.
##
## WHAT THIS DELIBERATELY DOES NOT DO
##
## It does not draw capture PROGRESS. [CaptureBase.describe_progress] already phrases every
## state of it -- "Capturing - survive 1 turn!", "Enemy is capturing your base!", "Your base
## has fallen" -- and [ObjectiveBanner] re-derives that line on the ACTIVE turn system's
## turn_started / turn_ended and on roster changes, so it is live on screen with nothing
## added here, for BOTH sides. Restating it would put one sentence in two places that can
## disagree. The alarm below is not a second copy: it is a one-shot EVENT, at a size the
## player cannot miss, for the beat the state changes on.
##
## It also owns no respawn bookkeeping. [method SiegeController.respawn_queue] is the
## authority on who is down and [method SiegeController.rounds_elapsed] on how long they
## have been -- this row reads them and renders. A HUD that kept its own count would
## eventually disagree with the mode putting units back on the board, which is the exact
## class of bug a readout exists to prevent.
##
## MOUNTING + THE 720p BUDGET
##
## Mounted by [UILayoutManager] as a ROW of the HUD's LeftSidebar VBox, directly under the
## battle log (one call, `_build_siege_feedback`). A row, not an overlay, for the reason the
## objective banner is a row: siblings in a BoxContainer cannot overlap, so the container
## owns the arithmetic instead of a tuned offset.
##
## Its claim is a CONSTANT, and it is spent out of slack the column already had:
##
##     720  viewport                     102  left-column top (15 margin + 77 TopBar + 10)
##   - 176  terrain card's bottom reserve
##   - 102  column top
##   = 442  usable column
##
##   battle log  158  (BattleLog.PANEL_HEIGHT, fully expanded -- the worst case)
##   + sep        10
##   + THIS ROW   24  (ROW_HEIGHT)
##   + sep        10
##   + unit card 228  (UnitInfoPanel.CARD_HEIGHT)
##   = 430   ->  column bottom 102 + 430 = 532, against the 544 (720 - 176) the terrain
##               card leaves free.  12px clear.
##
## Before this row the same worst case was 498 with 46px of slack (see the block at the top
## of [UILayoutManager]); this spends 34 of those 46 and leaves 12. That is why the row is
## PINNED at [constant ROW_HEIGHT] and elides rather than wrapping: a second line would be
## another 24px and would put the column 12px INTO the terrain card's band.
##
## [UILayoutManager._rebudget_left_column] is untouched on purpose -- it hands the battle log
## `usable - card_claim` (204px), the log takes its 158, and the 46px of headroom above is
## exactly what was left over. Nothing here re-budgets anything.
##
## While there is nothing to report the row is HIDDEN, and a hidden child of a BoxContainer
## contributes neither height nor separation -- so a Skirmish, a Campaign battle or a Siege
## with a full squad standing is the column it always was, to the pixel.
##
## LIVE, AND OFF THE RIGHT SIGNAL. The row re-reads on the ACTIVE turn system's turn_started
## / turn_ended (CONQUEST.md convention 2 -- PlayerManager's turn signals do not fire on AI
## turns, so a respawn clock wired to them would freeze the moment the enemy started acting,
## which in a push mode is most of the battle).

# --- Geometry ----------------------------------------------------------------

## The row's declared height. The column's arithmetic above spends exactly this.
const ROW_HEIGHT: float = 24.0

# --- Wording -----------------------------------------------------------------
#
# EVERY CHARACTER BELOW IS ONE THE THEME FONT CAN ACTUALLY DRAW. Godot's default font has
# no glyph for most symbol-block marks, and this project has already shipped HUD elements
# rendering as empty tofu boxes. The measured drawable set is the probe table in
# `tests/unit/test_status_feedback.gd`; "†" (Latin-1 supplement, probed drawable) is the
# fallen mark, and everything else here is ASCII.

## Fallen mark, prefixing the named unit.
const PREFIX: String = "† "
## Suffix counting the fallen who did not fit on the one row. Same shape (and same reason)
## as [constant ObjectiveBanner.MORE_SUFFIX]: the row is a fixed height, so extras are
## COUNTED, never crammed in. The full list is in the tooltip.
const MORE_SUFFIX: String = "   +%d more"

## The alarm lines. Enemy first because it is the one that matters.
const ANNOUNCE_ENEMY_CAPTURE: String = "Enemy capturing your base!"
const ANNOUNCE_ALLY_CAPTURE: String = "Capturing the enemy base!"
const ANNOUNCE_ENEMY_SUB: String = "Break the capture or lose the match."
const ANNOUNCE_ALLY_SUB: String = "Hold it and the base is yours."

## The stem a capture-in-progress objective line carries, used ONLY as the fallback source
## when the mode controller cannot be asked (see [method _capture_status]). Both of
## CaptureBase's in-flight phrasings contain it ("Capturing - survive 1 turn!", "Enemy is
## capturing your base!"), matched case-insensitively on the stem so a re-worded tail cannot
## break it.
const CAPTURE_MARK: String = "capturing"

const LABEL_NAME: String = "RespawnLabel"

# --- Colours (explicit, like every other self-styled HUD layer) --------------

const TEXT_COLOR: Color = ConquestTheme.CREAM_DIM
const FRAME_COLOR: Color = ConquestTheme.AMBER_DK
const PLATE_COLOR: Color = ConquestTheme.PLATE_BG
## The announcer plate's tint for each alarm, reusing the announcer's own side scheme.
const ENEMY_TINT: Color = ActionAnnouncer.ENEMY_COLOR
const ALLY_TINT: Color = ActionAnnouncer.ALLY_COLOR

# --- Discovery ---------------------------------------------------------------

## Where [SiegeController] installs itself -- a lazily-created child of the scene-tree root
## named [constant SiegeController.NODE_NAME], which is also how [CaptureBase] finds it. The
## GROUP is the second probe (and the seam a HUD test drives). Both are resolved at RUNTIME
## with a has-method guard on every call, the "never hard-name a class this build may not
## ship" discipline [MapRowBuilder] uses for the map catalog -- so this HUD mounts and runs
## in a build with no Siege mode at all, and simply never shows the row.
const CONTROLLER_NODE_PATH: String = "/root/SiegeController"
const CONTROLLER_GROUP: StringName = &"siege_controller"

## Fallback respawn delay, used only when the controller cannot be asked for its ruleset's.
## Mirrors [member SiegeRuleset.respawn_delay_rounds]; the controller is always asked first.
const FALLBACK_RESPAWN_DELAY: int = 2

# --- State -------------------------------------------------------------------

var _label: Label = null

## What is drawn right now, oldest death first. Each entry: {"name": String, "turns": int}.
## Derived from the controller's queue on every beat -- never accumulated here.
var _fallen: Array[Dictionary] = []

## True while a capture was in progress as of the last beat, so the alarm fires ONCE per
## capture rather than every turn for as long as it lasts. Re-armed when the capture stops.
var _capture_armed: bool = false

var _watched_system: TurnSystemBase = null


# ===========================================================================
# Pure text assembly (statics, so the wording is pinned without a scene)
# ===========================================================================

## The one line drawn for [param entries] (each {"name", "turns"}), or "" when there is
## nothing to report -- which is what hides the row.
static func row_text(entries: Array) -> String:
	if entries.is_empty():
		return ""
	var first: Dictionary = entries[0]
	var text: String = PREFIX + String(first.get("name", "A unit")) + " " \
			+ respawn_phrase(int(first.get("turns", 0)))
	if entries.size() > 1:
		text += MORE_SUFFIX % (entries.size() - 1)
	return text


## "respawns in 2 turns" / "respawns in 1 turn" / "respawns now". Singular is not a nicety
## here: "respawns in 1 turns" on the beat before a unit walks back out is the one frame a
## player is guaranteed to be reading this row.
static func respawn_phrase(turns: int) -> String:
	if turns <= 0:
		return "respawns now"
	if turns == 1:
		return "respawns in 1 turn"
	return "respawns in %d turns" % turns


## Hover text listing EVERY fallen unit, one per row. "" when at most one is down, so the
## usual case shows no tooltip repeating the line above it. Mirrors
## [method ObjectiveBanner.tooltip_text_for].
static func tooltip_text_for(entries: Array) -> String:
	if entries.size() <= 1:
		return ""
	var rows: Array[String] = []
	for entry in entries:
		var e: Dictionary = entry
		rows.append("• %s %s" % [String(e.get("name", "A unit")),
				respawn_phrase(int(e.get("turns", 0)))])
	return "\n".join(rows)


## Which alarm [param status] calls for, or "" for none. [param status] is the shape
## [method _capture_status] resolves: {"capturing": bool, "by_enemy": bool}.
static func alarm_text(status: Dictionary) -> String:
	if not bool(status.get("capturing", false)):
		return ""
	return ANNOUNCE_ENEMY_CAPTURE if bool(status.get("by_enemy", false)) \
			else ANNOUNCE_ALLY_CAPTURE


## PURE: turns still to wait for a queue entry recorded on [param death_round], given the
## mode's [param delay] and the [param elapsed] rounds so far. Floored at 1 while the entry
## is still queued -- an entry the mode has not yet returned is not back, whatever the
## arithmetic says, and "respawns in 0 turns" beside a unit that is still gone is a lie.
static func turns_remaining(death_round: int, elapsed: int, delay: int) -> int:
	return maxi(1, delay - (elapsed - death_round))


# ===========================================================================
# Construction
# ===========================================================================

func _ready() -> void:
	name = "SiegeFeedback"
	# PASS, not IGNORE: a control the hit test never returns can never show a tooltip, and
	# the tooltip is where the fallen who did not fit on the row are listed. PASS still lets
	# the press through to whatever is underneath.
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(0.0, ROW_HEIGHT)

	_build_ui()
	_wire_turn_system()
	_wire_roster()
	sync()


func _build_ui() -> void:
	add_theme_stylebox_override("panel", _row_box())

	_label = Label.new()
	_label.name = LABEL_NAME
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Clip + ellipsis rather than wrap: the row is a fixed ROW_HEIGHT and a second line
	# would spend 24px the column does not have (see the budget block above).
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	add_child(_label)


## A slim dark plate with an amber edge -- the [ObjectiveBanner] register, so the two read
## as the same class of persistent one-line readout.
func _row_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PLATE_COLOR
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = FRAME_COLOR
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


# ===========================================================================
# Public interface
# ===========================================================================

## The fallen currently drawn, oldest first (a copy -- callers cannot mutate the row).
func fallen() -> Array:
	return _fallen.duplicate(true)


## The line as it is drawn right now ("" while the row is hidden).
func text() -> String:
	return _label.text if _label != null and is_instance_valid(_label) else ""


## Re-read the mode's respawn queue and repaint. Cheap enough to run on every turn boundary
## and every roster change, which is exactly when it runs.
func sync() -> void:
	_fallen = _read_queue()
	_refresh()


## Repaint from [member _fallen], and show or hide the whole row with it. Hiding rather than
## blanking is the point: a hidden BoxContainer child costs neither height nor separation,
## so a battle with nobody down is the column it always was.
func _refresh() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	var line: String = row_text(_fallen)
	_label.text = line
	tooltip_text = tooltip_text_for(_fallen)
	visible = line != ""


# ===========================================================================
# Reading the mode's respawn queue
# ===========================================================================

## The LOCAL side's pending respawns, as {"name", "turns"} rows in the order they died.
##
## The controller's entries are {player_id, character_id, round}; the display name is
## resolved through [CharacterLibrary] (the same roster the rest of the UI names units
## from) and the clock is arithmetic over the controller's own round counter -- so this
## reads the mode rather than shadowing it.
##
## Only OUR side is listed. The enemy's losses are not the player's comeback, and a row that
## mixed the two would make "who is coming back" the one question it could not answer.
func _read_queue() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ctrl = _controller()
	if ctrl == null or not _is_active(ctrl):
		return out
	if not ctrl.has_method("respawn_queue"):
		return out
	var queue = ctrl.respawn_queue()
	if not (queue is Array):
		return out

	var elapsed: int = int(ctrl.rounds_elapsed()) if ctrl.has_method("rounds_elapsed") else 0
	var delay: int = _respawn_delay(ctrl)
	var slot: int = _local_slot()
	for entry in queue as Array:
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry
		if int(e.get("player_id", -1)) != slot:
			continue
		# Respawn delays ESCALATE with the round a unit died on, and each queue entry is
		# stamped with its own frozen numbers (SiegeController: "delay" at death,
		# "rounds_remaining" live). Prefer those -- they are what the mode actually runs
		# on -- and only fall back to the mode-wide opening delay for a bare entry.
		var turns: int = int(e.get("rounds_remaining", -1))
		if turns < 0:
			turns = turns_remaining(int(e.get("round", 0)), elapsed, int(e.get("delay", delay)))
		out.append({
			"name": _display_name_for(String(e.get("character_id", ""))),
			"turns": maxi(1, turns),
		})
	return out


## The mode's authored respawn delay, via its ruleset. [constant FALLBACK_RESPAWN_DELAY]
## only when the controller cannot be asked at all.
func _respawn_delay(ctrl) -> int:
	if ctrl == null or not ctrl.has_method("ruleset"):
		return FALLBACK_RESPAWN_DELAY
	var rules = ctrl.ruleset()
	if rules == null or not rules.has_method("respawn_delay"):
		return FALLBACK_RESPAWN_DELAY
	var delay: int = int(rules.respawn_delay())
	return delay if delay > 0 else FALLBACK_RESPAWN_DELAY


## The roster display name for [param character_id], or a neutral stand-in. Never an error:
## a queue entry naming a character this build cannot load is expected data (a community
## map), not an impossible state.
func _display_name_for(character_id: String) -> String:
	if character_id.strip_edges().is_empty():
		return "A unit"
	var character = CharacterLibrary.get_character(StringName(character_id))
	if character != null and String(character.display_name).strip_edges() != "":
		return String(character.display_name)
	return "A unit"


## Which roster slot is "us". The networked local slot when there is one, else 0 -- which is
## the slot [WinConditionLibrary.HUMAN_FACTION] scores every authored objective for, so the
## row and the win condition always mean the same side by the same reckoning.
func _local_slot() -> int:
	if typeof(GameModeManager) == TYPE_OBJECT and GameModeManager != null \
			and GameModeManager.has_method("get_local_player_id"):
		var raw = GameModeManager.get_local_player_id()
		if raw != null and int(raw) >= 0:
			return int(raw)
	return WinConditionLibrary.HUMAN_FACTION


# ===========================================================================
# The capture alarm
# ===========================================================================

## Fire the alarm on the beat a capture STARTS, once. Called on every turn beat, which is
## the same cadence the objective banner re-derives its progress line on, so the alarm and
## the banner can never disagree about whether a capture is happening.
func _check_capture() -> void:
	var status: Dictionary = _capture_status()
	if not bool(status.get("capturing", false)):
		_capture_armed = false
		return
	if _capture_armed:
		return
	_capture_armed = true
	var line: String = alarm_text(status)
	if line == "":
		return
	var by_enemy: bool = bool(status.get("by_enemy", false))
	_announce(line,
			ANNOUNCE_ENEMY_SUB if by_enemy else ANNOUNCE_ALLY_SUB,
			ENEMY_TINT if by_enemy else ALLY_TINT)


## Is a capture in progress, and by whom? Shape: {"capturing": bool, "by_enemy": bool}.
##
## [method SiegeController.capturing_by] is the authority -- it is the same latch
## [CaptureBase] scores and it names the SIDE, which is the only way to tell "you are taking
## theirs" from "they are taking yours". The objective lines are the fallback for a build
## whose controller cannot be asked, and they can only ever report a capture, never whose:
## rather than guess, that path reports the friendly case, which is the one the banner it
## read is phrased for.
func _capture_status() -> Dictionary:
	var ctrl = _controller()
	if ctrl != null and _is_active(ctrl) and ctrl.has_method("capturing_by"):
		var side: int = int(ctrl.capturing_by())
		if side < 0:
			return {"capturing": false, "by_enemy": false}
		return {"capturing": true, "by_enemy": side != _local_slot()}
	for line in _objective_lines():
		if String(line).to_lower().contains(CAPTURE_MARK):
			return {"capturing": true, "by_enemy": false}
	return {"capturing": false, "by_enemy": false}


## The objective banner's OWN live lines, read through its public accessor. Nothing here
## re-derives an objective's phrasing -- that is the banner's job, and having two renderers
## for one sentence is exactly the duplication this class avoids.
func _objective_lines() -> Array:
	var banner := _hud_member("objective_banner")
	if banner == null or not banner.has_method("objective_lines"):
		return []
	var lines = banner.objective_lines()
	return lines if lines is Array else []


## Push a one-shot notice through the battle's EXISTING [ActionAnnouncer] -- the surface the
## player already reads every move on -- rather than inventing a second toast layer for the
## one event in the mode that most needs to land somewhere familiar.
func _announce(line: String, sub: String, tint: Color) -> void:
	var announcer := _hud_member("action_announcer")
	if announcer == null or not announcer.has_method("announce"):
		return
	announcer.announce(line, sub, tint)


## A sibling HUD layer, found by walking up to the layout node that holds [param member].
## Null outside a battle HUD, which is the normal case in a test that mounts this row alone.
func _hud_member(member: String) -> Node:
	var layout: Node = get_parent()
	while layout != null and not (member in layout):
		layout = layout.get_parent()
	if layout == null:
		return null
	var found = layout.get(member)
	return found if found is Node and is_instance_valid(found) else null


# ===========================================================================
# Mode discovery
# ===========================================================================

## The live Siege controller, or null. Scene-tree-root node first, then the group.
func _controller():
	var node := get_node_or_null(CONTROLLER_NODE_PATH)
	if node != null and is_instance_valid(node):
		return node
	var tree := get_tree()
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(CONTROLLER_GROUP)
	return found if found != null and is_instance_valid(found) else null


## True only while a Siege is actually being played. A controller that cannot answer
## is_active() is treated as NOT active: the controller is installed for the whole app run
## and silenced on every other map, so trusting mere existence would put a respawn row on a
## Skirmish.
func _is_active(ctrl) -> bool:
	if ctrl == null or not ctrl.has_method("is_active"):
		return false
	return bool(ctrl.is_active())


# ===========================================================================
# Live wiring
# ===========================================================================

func _wire_turn_system() -> void:
	if typeof(TurnSystemManager) != TYPE_OBJECT or TurnSystemManager == null:
		return
	if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
	# The HUD is routinely mounted AFTER the system activates, so the one-shot signal above
	# would be missed and the row would never tick.
	if TurnSystemManager.has_active_turn_system():
		_on_turn_system_activated(TurnSystemManager.get_active_turn_system())


func _wire_roster() -> void:
	if typeof(GameEvents) != TYPE_OBJECT or GameEvents == null:
		return
	if GameEvents.has_signal("unit_eliminated") \
			and not GameEvents.unit_eliminated.is_connected(_on_roster_changed):
		GameEvents.unit_eliminated.connect(_on_roster_changed)
	if GameEvents.has_signal("unit_spawned") \
			and not GameEvents.unit_spawned.is_connected(_on_roster_changed):
		GameEvents.unit_spawned.connect(_on_roster_changed)


## A death or a return changes the queue, and neither goes through the turn system's
## signals. DEFERRED because the controller is on this same bus: read the queue after the
## emission has finished unwinding, so the death that just happened is already in it.
func _on_roster_changed(_a = null, _b = null) -> void:
	call_deferred("sync")


## (Re)subscribe to the ACTIVE turn system. The previous one is dropped first so a mid-
## session switch can never leave two live subscriptions double-ticking the row.
func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	if _watched_system == turn_system:
		return
	_drop_watched_system()
	_watched_system = turn_system
	# A fresh system is a fresh battle: no capture is in flight to have been announced.
	_capture_armed = false
	if turn_system != null and is_instance_valid(turn_system):
		if not turn_system.turn_started.is_connected(_on_turn_started):
			turn_system.turn_started.connect(_on_turn_started)
		if not turn_system.turn_ended.is_connected(_on_turn_ended):
			turn_system.turn_ended.connect(_on_turn_ended)
	sync()


func _on_turn_started(_player = null) -> void:
	# The alarm is checked on BOTH beats: a capture that begins as the enemy's turn ends must
	# be announced then, not one beat later when the player is already looking at the result.
	sync()
	_check_capture()


func _on_turn_ended(_player = null) -> void:
	sync()
	_check_capture()


func _drop_watched_system() -> void:
	if _watched_system == null or not is_instance_valid(_watched_system):
		_watched_system = null
		return
	if _watched_system.turn_started.is_connected(_on_turn_started):
		_watched_system.turn_started.disconnect(_on_turn_started)
	if _watched_system.turn_ended.is_connected(_on_turn_ended):
		_watched_system.turn_ended.disconnect(_on_turn_ended)
	_watched_system = null


func _exit_tree() -> void:
	# The autoloads outlive this battle HUD, so drop every hook -- a stale instance must
	# never be called after the battle scene is gone.
	if typeof(TurnSystemManager) == TYPE_OBJECT and TurnSystemManager != null \
			and TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.disconnect(_on_turn_system_activated)
	_drop_watched_system()
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null:
		if GameEvents.has_signal("unit_eliminated") \
				and GameEvents.unit_eliminated.is_connected(_on_roster_changed):
			GameEvents.unit_eliminated.disconnect(_on_roster_changed)
		if GameEvents.has_signal("unit_spawned") \
				and GameEvents.unit_spawned.is_connected(_on_roster_changed):
			GameEvents.unit_spawned.disconnect(_on_roster_changed)
