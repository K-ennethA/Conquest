extends Control

class_name UILayoutManager

# Comprehensive UI Layout Manager
# Manages all UI components with proper container-based layout to prevent overlapping

# UI Component References
@onready var margin_container: MarginContainer = $MarginContainer
@onready var main_container: VBoxContainer = $MarginContainer/MainContainer
@onready var top_bar: HBoxContainer = $MarginContainer/MainContainer/TopBar
@onready var center_top_container: VBoxContainer = $MarginContainer/MainContainer/TopBar/CenterTopContainer
@onready var middle_area: HBoxContainer = $MarginContainer/MainContainer/MiddleArea
@onready var left_sidebar: VBoxContainer = $MarginContainer/MainContainer/MiddleArea/LeftSidebar
@onready var game_area: Control = $MarginContainer/MainContainer/MiddleArea/GameArea
@onready var right_sidebar: VBoxContainer = $MarginContainer/MainContainer/MiddleArea/RightSidebar

# UI Panel References
@onready var turn_queue: Control = $MarginContainer/MainContainer/TopBar/CenterTopContainer/TurnQueue
@onready var turn_indicator: Control = $MarginContainer/MainContainer/TopBar/CenterTopContainer/TurnIndicator
@onready var unit_actions_panel: Control = $MarginContainer/MainContainer/MiddleArea/RightSidebar/UnitActionsPanel
# Persistent selected-unit stat card in the (previously empty) left column. It
# self-shows/hides off GameEvents.unit_selected; kept here so is_mouse_over_ui can
# treat it as HUD chrome while it is on screen.
@onready var unit_info_panel: Control = $MarginContainer/MainContainer/MiddleArea/LeftSidebar/UnitInfoPanel

# --- Left-column budget (1280x720) -------------------------------------------
#
# The left column is a real VBox stack, not a pile of overlapping anchored panels. Every
# row has a fixed claim except ONE flexible region (the UnitInfoPanel's two scrolling
# lists), and the claims add up to the column height exactly:
#
#   720   window height
#   - 15  MarginContainer top margin
#   - 56  TopBar (compact turn chip -- see _show_traditional_layout)
#   - 10  MainContainer separation
#   = 81  MiddleArea / left column TOP
#
#   - 30  BattleLog chip           (owns the column's first row)
#   - 10  LeftSidebar separation
#   = 121 UnitInfoPanel TOP
#
#   720 - 121 - 176 = 423px budget for the UnitInfoPanel, against a MEASURED fixed-content
#   floor of 358px (title 26 + portrait row 56 + stat block 132 + two section headers, plus
#   separations and the 24px of MarginContainer chrome) -- so the stat rows ALWAYS fit and
#   only the ability / effect lists scroll. The 176 is the bottom-left reserve owned by the
#   floating TerrainInfoPanel: a 16px window margin + its 152px height cap + an 8px gap
#   (UnitInfoPanel.BOTTOM_RESERVE == TerrainInfoPanel.MARGIN + MAX_HEIGHT + 8).
#
# An EXPANDED log (158px) does not fit alongside the card's 358px floor in the 463px of
# usable column -- 463 - 358 - 10 leaves 95px -- so the log is handed that leftover as its
# budget and falls back to its chip because it is under BattleLog.MIN_EXPANDED_HEIGHT.
# With no unit selected the card is hidden and the whole 463px goes to the log, which then
# expands in full.
const LEFT_COLUMN_WIDTH: float = 260.0
const COLUMN_SEPARATION: float = 10.0
## Mirror of UnitInfoPanel.BOTTOM_RESERVE, the window-bottom band the terrain card owns.
const BOTTOM_RESERVE: float = 176.0

# Layout state
var current_turn_system_type: TurnSystemBase.TurnSystemType = TurnSystemBase.TurnSystemType.TRADITIONAL
var is_layout_initialized: bool = false

# In-game Settings/Options overlay + the HUD button that opens it. Created in
# code so GameUILayout.tscn's existing node paths stay untouched.
var settings_panel: SettingsPanel = null
var settings_button: Button = null

# The battle PAUSE menu (quit / save & quit / forfeit) and the HUD button that opens it
# for mouse+touch players. The menu is a self-contained CanvasLayer that pauses the tree
# itself; this layout only owns WHERE it is mounted and WHEN Escape should open it.
var pause_menu: PauseMenu = null
var pause_button: Button = null

# Full-screen cinematic turn-transition wipe (fade-to-black + turn name). Mounted
# on its own high CanvasLayer so it draws above every HUD panel. Starts hidden and
# only blocks input while it is actually on screen.
var turn_transition: TurnTransition = null
var battle_log: BattleLog = null
# Upper-centre action banner ("Eldroot used Forest Barrage!") that flashes when any unit
# acts, so the enemy/AI turn is legible before per-move VFX exist. Its own high CanvasLayer.
var action_announcer: ActionAnnouncer = null
# Brief amber notice banner for NETWORK feedback the player would otherwise never see --
# today, a command the server refused (NetSession.intent_rejected). Its own CanvasLayer,
# above the action banner; self-wires to the session and dismisses itself.
var net_toast: NetToast = null
# Speed First per-unit move clock chip, mounted next to the TurnQueue. Self-shows only
# while a HUMAN unit's clock is armed (see TurnTimer / SpeedFirstTurnSystem).
var turn_timer: TurnTimer = null
# Replay transport bar (play/pause, speed, step, turn counter, exit). Its own CanvasLayer,
# mounted in every battle and self-hidden unless a replay is being watched -- see ReplayHUD.
var replay_hud: ReplayHUD = null
# "Skip enemy turn" fast-forward control. Its own CanvasLayer, mounted in every battle and
# self-hidden except during an AI turn (and never in a networked match) -- see
# SkipEnemyTurnButton.
## Typed as the base CanvasLayer, and built from SKIP_ENEMY_TURN_BUTTON_SCRIPT below rather than
## from its global class_name -- see that const for why.
var skip_enemy_turn_button: CanvasLayer = null

## The fast-forward control's script (see [SkipEnemyTurnButton]). Preloaded by PATH rather than
## referenced by its global class_name, exactly as [GameWorldManager] preloads its juice layers:
## a global class only resolves once the editor/engine has rescanned, so a fresh checkout (or a
## headless run against a stale class cache) would otherwise fail to compile this whole HUD.
const SKIP_ENEMY_TURN_BUTTON_SCRIPT = preload("res://game/ui/hud/SkipEnemyTurnButton.gd")

func _ready() -> void:
	# CRITICAL: Set mouse filter to IGNORE so clicks pass through to game area
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Connect to turn system events
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
	
	# Initialize layout
	_initialize_layout()
	_update_layout_for_turn_system()

	# Build the Settings button (top-right of the HUD) + the overlay panel before
	# theming so both pick up the amber ConquestTheme cascade below.
	_build_settings_ui()

	# Apply the Conquest "Fire Emblem amber" theme to the whole HUD subtree, and
	# give every panel background the amber card look so text reads on a single
	# consistent ground (children have already run _ready, so this wins).
	_apply_theme()

	# Push the HUD in from notches / punch holes / gesture bars on mobile. AFTER theming,
	# like every other self-styled piece below: _apply_theme sweeps the subtree and must
	# not be able to clobber the margin constants the inset writes. Exact no-op on
	# desktop -- see _apply_safe_area.
	_apply_safe_area()

	# Mount the turn-transition overlay AFTER theming: it is a CanvasLayer that
	# self-styles with explicit ConquestTheme colours, so it must not be swept by
	# _apply_theme's font-override stripping. It draws above everything on its own
	# high layer and starts hidden.
	_build_turn_transition()

	# Bottom-left scrolling combat log. Self-styled (dark plate), so mounted AFTER
	# theming to avoid the font-override sweep; anchors to this full-screen HUD root.
	_build_battle_log()

	# Upper-centre action banner. Self-styled CanvasLayer (like the turn wipe), mounted
	# AFTER theming so its explicit fonts/colours survive the font-override sweep.
	_build_action_announcer()

	# Network notice toast (refused commands). Self-styled CanvasLayer like the banner above,
	# so it is mounted AFTER theming to keep its explicit ConquestTheme colours.
	_build_net_toast()

	# Speed First move-clock chip, next to the TurnQueue in the top-centre column.
	# Self-styled, so mounted AFTER theming to keep its explicit font size / colours.
	_build_turn_timer()

	# Replay transport bar. Self-styled CanvasLayer like the toast above, and self-hidden
	# unless a replay is being watched, so a normal battle never sees it.
	_build_replay_hud()

	# "Skip enemy turn" fast-forward control. Same deal as the two above: self-styled
	# CanvasLayer, mounted after theming, and self-hidden outside an AI turn.
	_build_skip_enemy_turn_button()

	# The pause menu overlay. Mounted AFTER theming like the other self-styled
	# CanvasLayers -- it carries the DARK MenuTheme on purpose and must not be swept
	# into the amber HUD cascade.
	_build_pause_menu()

	# A leaver/forfeiter has to LOSE, not just vanish. Wired here because this HUD is
	# alive for exactly the lifetime of a battle.
	_wire_net_session()

	# Give the command buttons a click sound (they were silent). Reuses the existing
	# sfx_ui_click slot at low volume. Runs after everything above is mounted so the
	# gear button + battle log are present.
	_wire_button_sfx()

	# Keep the left column's two panels sharing one budget for the rest of the battle
	# (the card shows/hides with the selection, and the window can be resized).
	_wire_left_column_budget()

	is_layout_initialized = true

# --- Left column budget ------------------------------------------------------

func _wire_left_column_budget() -> void:
	"""Re-share the left column whenever the unit card appears, disappears, changes its
	own minimum, or the window resizes."""
	if unit_info_panel != null:
		if not unit_info_panel.visibility_changed.is_connected(_on_left_column_changed):
			unit_info_panel.visibility_changed.connect(_on_left_column_changed)
		if not unit_info_panel.minimum_size_changed.is_connected(_on_left_column_changed):
			unit_info_panel.minimum_size_changed.connect(_on_left_column_changed)
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_left_column_changed):
		vp.size_changed.connect(_on_left_column_changed)
	_on_left_column_changed()

func _on_left_column_changed() -> void:
	# Deferred: this fires from inside a layout pass (visibility / minimum-size
	# notifications), and re-budgeting writes minimum sizes back into that same pass.
	call_deferred("_rebudget_left_column")

## Split the left column between the battle log (top row) and the unit info card.
##
## ONE flexible region, and a strict claim order: the terrain card's bottom reserve is
## untouchable, the info card's FIXED rows (title / portrait / stats / section headers)
## have the next claim, and the battle log is handed whatever is left. See the
## LEFT_COLUMN_WIDTH comment block at the top of this file for the 720p arithmetic --
## 463px usable, 402px of which the card cannot give up, so an expanded log falls back to
## its chip while a unit is selected and takes the full 158px when none is.
func _rebudget_left_column() -> void:
	if battle_log == null or not is_instance_valid(battle_log):
		return
	if not battle_log.has_method("set_height_budget"):
		return

	var vp := get_viewport()
	var vp_height: float = vp.get_visible_rect().size.y if vp != null else 720.0
	var column_top: float = left_sidebar.global_position.y if left_sidebar != null else 81.0
	var usable: float = vp_height - BOTTOM_RESERVE - column_top

	var card_claim: float = 0.0
	if unit_info_panel != null and is_instance_valid(unit_info_panel) and unit_info_panel.visible:
		card_claim = COLUMN_SEPARATION
		if unit_info_panel.has_method("fixed_content_height"):
			card_claim += float(unit_info_panel.call("fixed_content_height"))
		else:
			card_claim += unit_info_panel.get_combined_minimum_size().y

	battle_log.set_height_budget(usable - card_claim)

	# The log's row height just moved the card's top edge, so the card re-runs its own
	# fit against the new top. Deferred inside refit(); converges because both writes are
	# no-ops once the sizes stop changing.
	if unit_info_panel != null and is_instance_valid(unit_info_panel) \
			and unit_info_panel.has_method("refit"):
		unit_info_panel.call("refit")

func _wire_button_sfx() -> void:
	"""Attach the shared UI-click SFX to the command surfaces this HUD owns.

	Scoped deliberately: MiddleArea (the right-sidebar action menu + left stat card),
	the top-right gear, and the battle-log header. The TurnQueue (rebuilt every turn,
	would tick noisily) and the menus-owned SettingsPanel overlay are left out.
	UnitActionsPanel rebuilds its command buttons on selection, so it can re-attach on
	its own rebuilds; the meta flag in UIFeedback keeps this from double-connecting."""
	if middle_area:
		UIFeedback.attach_sfx(middle_area)
	if settings_button:
		UIFeedback.attach_sfx(settings_button)
	if pause_button:
		UIFeedback.attach_sfx(pause_button)
	if battle_log:
		UIFeedback.attach_sfx(battle_log)

func _build_turn_transition() -> void:
	"""Create and mount the full-screen turn-transition wipe on its own CanvasLayer."""
	turn_transition = TurnTransition.new()
	turn_transition.name = "TurnTransition"
	add_child(turn_transition)

func _build_battle_log() -> void:
	"""Create and mount the battle log as the TOP ROW of the left column.

	It used to be a free-floating panel anchored to the window's top-left, which put it in
	the same band as the container-placed UnitInfoPanel: expanded, the log's 158px reached
	y~171 while the card starts at y~81, so the chip drew straight over the card's "Unit
	Information" title. Mounted as the LeftSidebar VBox's first child it OWNS its row and
	the card stacks under it with the column's 10px separation -- overlap is now
	structurally impossible rather than a matter of tuned offsets."""
	battle_log = BattleLog.new()
	battle_log.name = "BattleLog"
	if left_sidebar != null:
		left_sidebar.add_child(battle_log)
		left_sidebar.move_child(battle_log, 0)
	else:
		add_child(battle_log)
	_rebudget_left_column()

func _build_action_announcer() -> void:
	"""Create and mount the upper-centre action banner (flashes when a unit acts)."""
	action_announcer = ActionAnnouncer.new()
	action_announcer.name = "ActionAnnouncer"
	add_child(action_announcer)

func _build_net_toast() -> void:
	"""Create and mount the network notice toast.

	It wires itself to NetSession.intent_rejected in its own _ready (and unhooks in
	_exit_tree), so there is nothing to connect here -- this only owns WHERE it lives. In a
	solo battle the session never rejects anything, so it stays invisible for free."""
	net_toast = NetToast.new()
	net_toast.name = "NetToast"
	add_child(net_toast)

func _build_turn_timer() -> void:
	"""Create and mount the Speed First move-clock chip beneath the TurnQueue.

	Placed in the top-centre column (with the queue) so it reads as part of the Speed
	First HUD. It self-hides whenever no human clock is armed and only ever hooks the
	SpeedFirstTurnSystem, so it stays invisible in Traditional mode / when the clock is
	off -- no per-turn-system layout toggling needed here."""
	turn_timer = TurnTimer.new()
	turn_timer.name = "TurnTimer"
	turn_timer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if center_top_container:
		center_top_container.add_child(turn_timer)
	else:
		add_child(turn_timer)

func _build_replay_hud() -> void:
	"""Create and mount the replay transport bar.

	Exactly the NetToast deal: this only owns WHERE it lives. The bar hides itself unless
	ReplayPlayback.is_playing(), and it finds the ReplayDriver (mounted later, by the battle
	boot) from its own _ready -- so a normal battle mounts one hidden CanvasLayer and nothing
	else happens."""
	replay_hud = ReplayHUD.new()
	replay_hud.name = "ReplayHUD"
	add_child(replay_hud)

func _build_skip_enemy_turn_button() -> void:
	"""Create and mount the enemy-turn fast-forward control.

	Same one-call deal as NetToast / ReplayHUD: this only owns WHERE it lives. The control
	subscribes to the ACTIVE turn system in its own _ready, shows itself only during an AI turn
	(and never in a networked match or a replay), and disarms the fast-forward on teardown -- so
	a normal player turn mounts one hidden CanvasLayer and nothing else happens."""
	skip_enemy_turn_button = SKIP_ENEMY_TURN_BUTTON_SCRIPT.new()
	skip_enemy_turn_button.name = "SkipEnemyTurnButton"
	add_child(skip_enemy_turn_button)

func _apply_theme() -> void:
	"""Apply the amber ConquestTheme to this HUD subtree (panels, buttons, text)."""
	ConquestTheme.apply_to(self)

func _apply_safe_area() -> void:
	"""Inset the HUD from notches / punch holes / gesture bars on mobile.

	Every HUD panel is laid out inside the single outermost MarginContainer, so adding
	the platform's safe-area insets to THAT container's margins moves the whole HUD
	inward at once -- no per-panel anchoring changes, and the authored 15px margins are
	preserved and added to rather than replaced.

	MobileDisplay.apply_safe_area() is the one shared implementation (the menus get the
	same insets automatically via its scene-root hook). It returns before touching
	anything unless OS.has_feature("mobile"), so on desktop this is a guaranteed no-op --
	and it is null-guarded so a scene loaded without the autoload (headless tests) is
	unaffected either way."""
	if margin_container == null:
		return
	if typeof(MobileDisplay) != TYPE_OBJECT or MobileDisplay == null:
		return
	MobileDisplay.apply_safe_area(margin_container)

func _build_settings_ui() -> void:
	"""Create the gear button (top-right) and the SettingsPanel overlay.

	The button lives at the far right of the TopBar; the panel is mounted as the
	last child of this layout root so it draws above the board and every other
	HUD panel. Both start ready-to-theme."""
	# Pause button, immediately LEFT of the gear. Escape opens the same menu, but a
	# touch/mouse player has no Escape key -- 44px is the project's touch-target floor.
	if top_bar:
		pause_button = Button.new()
		pause_button.name = "PauseButton"
		pause_button.text = "⏸"
		pause_button.tooltip_text = "Pause (Esc)"
		pause_button.custom_minimum_size = Vector2(44, 44)
		pause_button.mouse_filter = Control.MOUSE_FILTER_STOP
		pause_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		pause_button.add_theme_font_size_override("font_size", 22)
		pause_button.pressed.connect(_toggle_pause_menu)
		top_bar.add_child(pause_button)

	# Gear/Settings button, added at the end of the TopBar so it sits top-right.
	if top_bar:
		settings_button = Button.new()
		settings_button.name = "SettingsButton"
		settings_button.text = "⚙"  # gear glyph
		settings_button.tooltip_text = "Settings"
		settings_button.custom_minimum_size = Vector2(44, 44)
		settings_button.mouse_filter = Control.MOUSE_FILTER_STOP
		settings_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		settings_button.add_theme_font_size_override("font_size", 22)
		settings_button.pressed.connect(_toggle_settings)
		top_bar.add_child(settings_button)

	# Overlay panel: full-screen, starts hidden, mounted on top of everything.
	settings_panel = SettingsPanel.new()
	settings_panel.name = "SettingsPanel"
	add_child(settings_panel)

func _toggle_settings() -> void:
	if settings_panel:
		settings_panel.toggle()

func _build_pause_menu() -> void:
	"""Create and mount the battle pause menu on its own high CanvasLayer."""
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)

func _toggle_pause_menu() -> void:
	if pause_menu:
		pause_menu.toggle()

func _unhandled_input(event: InputEvent) -> void:
	# Escape (ui_cancel) closes the Settings overlay when it is open, and consumes
	# the event so the board cursor's own ui_cancel handler (unit deselect) does
	# not ALSO fire underneath. The gear button is the opener.
	if event.is_action_pressed("ui_cancel") and settings_panel and settings_panel.is_open():
		settings_panel.close()
		get_viewport().set_input_as_handled()
		return

	# --- ESC ordering in battle -------------------------------------------------
	# Escape has two jobs, and the STAGED one always wins:
	#   1. Something is staged (move popup open, aiming a move, a tentative move,
	#      movement mode, or just a selection): UnitActionsPanel's own `_input` handler
	#      backs out ONE stage and consumes the event. `_input` runs before every
	#      `_unhandled_input`, so in that case we never see the press at all.
	#   2. Nothing is staged (the command state is IDLE): the press falls through to
	#      here and opens the pause menu.
	# So this branch only has to answer "is the panel idle?", which the panel already
	# exposes as has_active_interaction(). Once open, the pause menu handles Escape in
	# its OWN `_input`, so the press that closes it can never re-open it here.
	if event.is_action_pressed("ui_cancel") and _can_open_pause_menu():
		pause_menu.open()
		get_viewport().set_input_as_handled()

func _can_open_pause_menu() -> bool:
	"""True when Escape should mean 'pause' rather than 'cancel one staged step'."""
	if pause_menu == null or pause_menu.is_open():
		return false
	if settings_panel != null and settings_panel.is_open():
		return false
	# A decided battle already owns the screen: GameOverScreen pauses the tree and takes
	# Escape for 'back to menu'. Never stack a pause menu on top of that.
	var tree := get_tree()
	if tree != null and tree.paused:
		return false
	# .call(): unit_actions_panel is declared as a plain Control here, so a direct
	# has_active_interaction() would not survive static analysis.
	if unit_actions_panel != null and unit_actions_panel.has_method("has_active_interaction") \
			and bool(unit_actions_panel.call("has_active_interaction")):
		return false
	return true

# --- Opponent left / forfeited = a loss for them ------------------------------
#
# NetSession only reports the SESSION event; something has to turn that into a battle
# OUTCOME. This HUD is the natural owner: it exists for exactly one battle and is already
# the node that mediates between session state and what ends up on screen.
#
# The path used is the public one a wipe takes -- mark the absent player ELIMINATED and
# announce it on PlayerManager.player_eliminated, which GameWorldManager's existing
# listener turns into the standard GameOverScreen victory for whoever is left standing.
# No new hook in GameWorldManager, and no bespoke "you win because they left" screen.

func _wire_net_session() -> void:
	if typeof(NetSession) != TYPE_OBJECT or NetSession == null:
		return
	if NetSession.has_signal("opponent_forfeited") \
			and not NetSession.opponent_forfeited.is_connected(_on_opponent_forfeited):
		NetSession.opponent_forfeited.connect(_on_opponent_forfeited)
	if NetSession.has_signal("opponent_left") \
			and not NetSession.opponent_left.is_connected(_on_opponent_left):
		NetSession.opponent_left.connect(_on_opponent_left)

func _exit_tree() -> void:
	# The autoload outlives this battle HUD, so drop the hooks -- a stale instance must
	# never be called after the battle scene is gone.
	if typeof(NetSession) != TYPE_OBJECT or NetSession == null:
		return
	if NetSession.has_signal("opponent_forfeited") \
			and NetSession.opponent_forfeited.is_connected(_on_opponent_forfeited):
		NetSession.opponent_forfeited.disconnect(_on_opponent_forfeited)
	if NetSession.has_signal("opponent_left") \
			and NetSession.opponent_left.is_connected(_on_opponent_left):
		NetSession.opponent_left.disconnect(_on_opponent_left)

func _on_opponent_forfeited(slot: int) -> void:
	_eliminate_absent_players(slot)

func _on_opponent_left() -> void:
	# No slot to name when a socket simply drops -- everyone who is not US is gone.
	_eliminate_absent_players(-1)

func _eliminate_absent_players(slot: int) -> void:
	"""Mark the absent player(s) defeated so the normal win evaluation resolves the battle.

	[param slot] >= 0 targets exactly that roster slot (player_id maps 1:1 onto it --
	host = player 0 = slot 0, the same alignment NetSession's turn bridge uses);
	[param slot] < 0 means "every non-local combatant". NEUTRAL camps are skipped -- they
	are not a side that can win or lose. Idempotent: an already ELIMINATED player is left
	alone, so a forfeit followed by the forfeiter's own disconnect still resolves the
	battle exactly once."""
	if typeof(PlayerManager) != TYPE_OBJECT or PlayerManager == null:
		return
	var local_slot: int = -1
	if typeof(NetSession) == TYPE_OBJECT and NetSession != null and NetSession.has_method("local_slot"):
		local_slot = NetSession.local_slot()
	for p in PlayerManager.players:
		if p == null:
			continue
		if "is_neutral" in p and bool(p.is_neutral):
			continue
		if p.current_state == Player.PlayerState.ELIMINATED:
			continue
		if slot >= 0:
			if p.player_id != slot:
				continue
		elif local_slot >= 0 and p.player_id == local_slot:
			continue
		p.set_state(Player.PlayerState.ELIMINATED)
		PlayerManager.player_eliminated.emit(p)

func _initialize_layout() -> void:
	"""Initialize the layout system with proper sizing and constraints"""
	
	# CRITICAL: Set mouse filters for all container elements to allow click passthrough
	if margin_container:
		margin_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if main_container:
		main_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if top_bar:
		top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center_top_container:
		center_top_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if middle_area:
		middle_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if left_sidebar:
		left_sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if game_area:
		game_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if right_sidebar:
		right_sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Set minimum sizes for main areas with proper spacing
	if top_bar:
		top_bar.custom_minimum_size = Vector2(0, 180)  # Taller to accommodate TurnQueue
	
	if middle_area:
		# This will expand to fill available space
		middle_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Left column: a FIXED 260px width, declared here rather than inferred from whichever
	# child happens to be visible. The column holds two panels that show and hide
	# independently (the battle log always, the unit card only while something is
	# selected), so an inferred width made the column -- and the battle log inside it --
	# collapse the moment the card was hidden.
	if left_sidebar:
		left_sidebar.custom_minimum_size = Vector2(LEFT_COLUMN_WIDTH, 0)
		left_sidebar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		left_sidebar.add_theme_constant_override("separation", int(COLUMN_SEPARATION))

	# The card FILLs that column instead of shrinking to its own minimum, so its inner
	# rows (and the HP bar) resolve against exactly the width the frame is drawn at.
	if unit_info_panel:
		unit_info_panel.size_flags_horizontal = Control.SIZE_FILL
		unit_info_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	if right_sidebar:
		right_sidebar.custom_minimum_size = Vector2(220, 0)
		right_sidebar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	# Game area should expand to fill remaining space
	if game_area:
		game_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game_area.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _update_layout_for_turn_system() -> void:
	"""Update layout based on current turn system"""
	
	if current_turn_system_type == TurnSystemBase.TurnSystemType.INITIATIVE:
		# Speed First mode: Show TurnQueue, hide TurnIndicator
		_show_speed_first_layout()
	else:
		# Traditional mode: Show TurnIndicator, hide TurnQueue
		_show_traditional_layout()

func _show_speed_first_layout() -> void:
	"""Configure layout for Speed First turn system"""
	
	if turn_queue:
		turn_queue.visible = true
		turn_queue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		turn_queue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	if turn_indicator:
		turn_indicator.visible = false
	
	# Adjust top bar height for Speed First display
	if top_bar:
		top_bar.custom_minimum_size = Vector2(0, 180)  # Taller for queue with proper spacing

func _show_traditional_layout() -> void:
	"""Configure layout for Traditional turn system"""
	
	if turn_queue:
		turn_queue.visible = false
	
	if turn_indicator:
		turn_indicator.visible = true
		# Compact chip: shrink-center so it sits as a small strip in the top bar
		# instead of stretching into a big card across the whole center area.
		turn_indicator.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		turn_indicator.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Slim top bar height now that the turn is a compact chip (the cinematic
	# announcement is handled by the full-screen TurnTransition overlay).
	if top_bar:
		top_bar.custom_minimum_size = Vector2(0, 56)

func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	"""Handle turn system activation and update layout accordingly"""
	
	var new_type = turn_system.system_type
	if new_type != current_turn_system_type:
		current_turn_system_type = new_type
		_update_layout_for_turn_system()

# Public interface for layout management
func show_panel(panel_name: String, show: bool = true) -> void:
	"""Show or hide a specific UI panel"""
	match panel_name.to_lower():
		"unit_actions":
			if unit_actions_panel:
				unit_actions_panel.visible = show
		"turn_queue":
			if turn_queue:
				turn_queue.visible = show
		"turn_indicator":
			if turn_indicator:
				turn_indicator.visible = show
		_:
			pass

func get_game_area() -> Control:
	"""Get the game area control for 3D scene rendering"""
	return game_area

func get_panel(panel_name: String) -> Control:
	"""Get a reference to a specific UI panel"""
	match panel_name.to_lower():
		"unit_actions":
			return unit_actions_panel
		"turn_queue":
			return turn_queue
		"turn_indicator":
			return turn_indicator
		_:
			return null

func is_mouse_over_ui(mouse_position: Vector2) -> bool:
	"""Check if mouse position is over any UI element"""
	# The turn-transition wipe covers the whole screen while playing -- treat the
	# entire viewport as "over UI" so a click during the fade doesn't reach the board.
	if turn_transition and turn_transition.is_blocking_input():
		return true

	# The Settings overlay covers the whole screen while open, so any position is
	# "over UI" -- keep board/camera input from leaking through underneath it.
	if settings_panel and settings_panel.is_open():
		return true

	# Same for the pause menu: it is full-screen and modal while it is up.
	if pause_menu and pause_menu.is_open():
		return true

	# The Settings / Pause buttons are part of the HUD chrome.
	if settings_button and settings_button.visible:
		var btn_rect = Rect2(settings_button.global_position, settings_button.size)
		if btn_rect.has_point(mouse_position):
			return true

	if pause_button and pause_button.visible:
		var pause_rect = Rect2(pause_button.global_position, pause_button.size)
		if pause_rect.has_point(mouse_position):
			return true

	# Check if mouse is over any visible UI panel
	var panels = []
	
	# Always check right sidebar (unit actions panel)
	if unit_actions_panel and unit_actions_panel.visible:
		panels.append({"name": "unit_actions_panel", "panel": unit_actions_panel})

	# Left-column selected-unit stat card (only on screen while a unit is selected).
	if unit_info_panel and unit_info_panel.visible:
		panels.append({"name": "unit_info_panel", "panel": unit_info_panel})

	# Add turn system specific panels
	if current_turn_system_type == TurnSystemBase.TurnSystemType.INITIATIVE and turn_queue and turn_queue.visible:
		panels.append({"name": "turn_queue", "panel": turn_queue})
	elif turn_indicator and turn_indicator.visible:
		panels.append({"name": "turn_indicator", "panel": turn_indicator})
	
	for panel_info in panels:
		var panel = panel_info.panel
		if panel and panel.visible:
			var panel_rect = Rect2(panel.global_position, panel.size)
			if panel_rect.has_point(mouse_position):
				return true
	
	return false

func get_layout_info() -> Dictionary:
	"""Get information about current layout state"""
	return {
		"turn_system_type": TurnSystemBase.TurnSystemType.keys()[current_turn_system_type],
		"is_initialized": is_layout_initialized,
		"visible_panels": {
			"unit_actions": unit_actions_panel.visible if unit_actions_panel else false,
			"turn_queue": turn_queue.visible if turn_queue else false,
			"turn_indicator": turn_indicator.visible if turn_indicator else false
		},
		"layout_areas": {
			"top_bar_height": top_bar.custom_minimum_size.y if top_bar else 0,
			"left_sidebar_width": 0,  # No longer used
			"right_sidebar_width": right_sidebar.custom_minimum_size.x if right_sidebar else 0
		}
	}

# Responsive layout adjustments
func _on_viewport_size_changed() -> void:
	"""Handle viewport size changes for responsive layout"""
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Adjust sidebar visibility based on screen width - only right sidebar now
	if viewport_size.x < 1200:
		# On smaller screens, make right sidebar slightly smaller
		if right_sidebar:
			right_sidebar.custom_minimum_size.x = 180  # Slightly smaller
	else:
		# On larger screens, use full sidebar width
		if right_sidebar:
			right_sidebar.custom_minimum_size.x = 220

func force_layout_update() -> void:
	"""Force a complete layout update (useful for debugging)"""
	_initialize_layout()
	_update_layout_for_turn_system()
	
	# Force container updates
	if main_container:
		main_container.queue_sort()