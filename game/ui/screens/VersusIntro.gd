extends CanvasLayer

class_name VersusIntro

## POKEMON-STYLE PRE-BATTLE **VS CLASH** INTRO for a versus match.
##
## Two player cards slam in from opposite screen edges with an overshoot, meet either side of
## an angled centre divide, land on an impact FLASH + a short screen shake, hold for a beat
## behind a big "VS" emblem, then part vertically and fade as the battle is revealed
## underneath. ~[constant TOTAL_SECONDS] end to end. Any input skips instantly to the end
## state. Emits [signal finished] exactly once, always.
##
## PURELY PRESENTATIONAL. It mutates no game state, issues no command, and is NEVER
## synchronised: in a networked match each machine plays its OWN copy off its own local data,
## so the two can start a few frames apart and it does not matter. Lockstep is untouched --
## the only thing this overlay touches is the moment the first turn starts (see below).
##
## THE FIRST-TURN HOLD. [GameWorldManager] mounts this after the board is built and AWAITS
## [signal finished] immediately before its `_start_game()` call. `_start_game()` is what calls
## `PlayerManager.start_game()`, which is what emits `game_state_changed(IN_PROGRESS)`, which is
## what makes [TurnSystemManager] activate a turn system -- so awaiting here IS the hold: no
## turn system exists, and therefore nothing ticks, until the intro finishes or is skipped.
## Nothing new had to be invented for it; the hold is the existing boot ordering, additively.
##
## INPUT BLOCKING. While the intro is up the tree is PAUSED (this node is
## [constant Node.PROCESS_MODE_ALWAYS] and the tweens are [constant Tween.TWEEN_PAUSE_PROCESS]),
## which is the same technique [GameOverScreen] uses -- a paused node receives no input at all,
## so the board cursor and every HUD panel are inert for the duration without this overlay
## having to out-race them for events. The pause is ALWAYS lifted in [method _end], including
## on a skip and on an early tree exit.
##
## ELIGIBILITY is a pure static decision -- see [method should_show]. It plays for a local
## hotseat versus match and for a networked versus match, and for nothing else: solo /
## skirmish-vs-AI, arena, challenge, king-of-the-hill-vs-AI, campaign, a resumed mid-battle
## save and replay playback all suppress it.
##
## DATA is assembled by another pure static -- see [method assemble_cards]. The load-bearing
## rule there: a rank chip is only ever shown where a REAL profile backs it. A hotseat guest
## ("Player 2") has no profile, so their card carries NO chip rather than a borrowed or
## invented rank, and a networked opponent on an older build that never announced a
## [MatchPeerInfo] card degrades to name-only rather than blocking the match.

## Emitted when the intro has finished playing, has been skipped, or the node left the tree
## mid-play. ALWAYS fires exactly once per [method play], so the awaiting boot can never hang.
signal finished

# --- Layer / discovery -------------------------------------------------------
## Above the TurnTransition wipe (128) and the ultimate cut-in (124): nothing may draw over
## the pre-battle reveal.
const OVERLAY_LAYER: int = 136
const GROUP_NAME: StringName = &"versus_intro"

# --- Sides -------------------------------------------------------------------
## Left card: the LOCAL player, from this machine's slot perspective.
const SIDE_LOCAL: int = 0
## Right card: the opponent.
const SIDE_OPPONENT: int = 1

# --- Timing (seconds, before Battle-Speed scaling) ---------------------------
## Cards fly in from the screen edges and overshoot into place.
const SLAM_IN: float = 0.55
## Impact beat: flash + shake + the "VS" emblem popping in.
const IMPACT: float = 0.18
## The readable hold with both cards on screen.
const HOLD: float = 1.05
## Cards part vertically and the whole overlay fades out.
const PART_OUT: float = 0.42
## Authored total. SLAM_IN + IMPACT + HOLD + PART_OUT.
const TOTAL_SECONDS: float = 2.20
## Animations-OFF path: the cards are simply THERE for this long, then it ends. Never skipped
## outright, because the boot is awaiting `finished` and must always be released.
const STATIC_HOLD: float = 0.35

# --- Geometry ----------------------------------------------------------------
const CARD_WIDTH: float = 320.0
const CARD_HEIGHT: float = 300.0
## Gap between the two cards -- the angled divide sits in it.
const CARD_GAP: float = 56.0
const DIVIDE_ANGLE_DEG: float = -14.0
const DIVIDE_WIDTH: float = 10.0
## Peak screen-shake displacement, in pixels.
const SHAKE_PX: float = 9.0
## Square edge of a card's portrait / monogram plate.
const PORTRAIT_PX: float = 132.0

# --- Type --------------------------------------------------------------------
const NAME_FONT_SIZE: int = 24
const CHIP_FONT_SIZE: int = 12
const POINTS_FONT_SIZE: int = 12
const EMBLEM_FONT_SIZE: int = 96
const MONOGRAM_FONT_SIZE: int = 56

# --- Palette -----------------------------------------------------------------
## Backdrop behind the cards. Deliberately near-opaque: the reveal is the moment the board
## comes out from BEHIND it, so the board must not be readable before then.
const BACKDROP: Color = Color(0.043, 0.027, 0.012, 0.88)

# --- Mode discriminator ------------------------------------------------------
## Mirror of [code]GameSettings.GameMode.VERSUS[/code]. Spelled as a literal because a `const`
## must be a constant expression and an autoload's enum is not one; pinned against the real
## enum by this file's test suite so the two can never drift.
const MODE_VERSUS: int = 1

# --- Nodes -------------------------------------------------------------------
var _root: Control = null
var _backdrop: ColorRect = null
var _shaker: Control = null
var _divide: ColorRect = null
var _flash: ColorRect = null
var _emblem: Label = null
var _left_card: PanelContainer = null
var _right_card: PanelContainer = null

## side -> { "name": Label, "chip": Label, "points": Label, "portrait": TextureRect,
## "monogram": Label }.
var _card_parts: Dictionary = {}
## side -> the assembled card Dictionary currently rendered for it.
var _cards: Dictionary = {}

# --- Playback state ----------------------------------------------------------
var _tween: Tween = null
var _flash_tween: Tween = null
var _shake_tween: Tween = null
## True between [method play] and [method _end]; guards re-entry and gates input.
var _playing: bool = false
## True once [signal finished] has been emitted for the current play, so it can never fire twice.
var _finished_emitted: bool = true
## Whether THIS node is the one that paused the tree (so an already-paused tree is left alone).
var _paused_tree: bool = false
## Rest positions, recomputed per play from the live viewport.
var _left_rest: Vector2 = Vector2.ZERO
var _right_rest: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = OVERLAY_LAYER
	add_to_group(GROUP_NAME)
	# Animate + hear input while the tree is paused (see the class doc's INPUT BLOCKING note).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_set_idle()


# =====================================================================================
#  ELIGIBILITY -- the pure gate
# =====================================================================================

## Does a versus intro play for this battle?
##
## [param ctx] keys (all optional, all defaulting to "no"):
##   "replay"         : bool -- this battle is a recording being watched
##   "resumed"        : bool -- this battle is a mid-battle save being restored
##   "arena"          : bool -- an arena run owns this battle
##   "challenge"      : bool -- a challenge attempt owns this battle
##   "campaign"       : bool -- a campaign chapter owns this battle
##   "king_of_hill"   : bool -- a king-of-the-hill runtime owns this battle
##   "networked"      : bool -- a live networked match (NetSession.is_networked_match())
##   "game_mode"      : int  -- GameSettings.game_mode
##   "opponent_is_ai" : bool -- any non-local participant is bot-controlled
##
## Static and side-effect free, so every combination is testable without a scene, an autoload
## or a socket.
##
## THE RULE, in the order it is applied:
##   1. A mode CONTROLLER owning the battle always wins -- arena, challenge, campaign,
##      king-of-the-hill and a restored save are not "a versus match starting", and a replay is
##      a recording of one that already happened.
##   2. A live NETWORKED match always shows: that is the headline case, and each machine plays
##      its own copy.
##   3. Otherwise it is the LOCAL modes' turn, and only VERSUS qualifies -- solo/skirmish is
##      GameMode.SINGLE_PLAYER and never shows.
##   4. ...and a local versus match against a BOT is not a versus intro. This is what keeps
##      "king-of-the-hill vs AI" and any other AI opponent booted through the versus mode from
##      getting a two-human clash card.
static func should_show(ctx: Dictionary) -> bool:
	if bool(ctx.get("replay", false)):
		return false
	if bool(ctx.get("resumed", false)):
		return false
	if bool(ctx.get("arena", false)):
		return false
	if bool(ctx.get("challenge", false)):
		return false
	if bool(ctx.get("campaign", false)):
		return false
	if bool(ctx.get("king_of_hill", false)):
		return false
	if bool(ctx.get("networked", false)):
		return true
	if int(ctx.get("game_mode", -1)) != MODE_VERSUS:
		return false
	return not bool(ctx.get("opponent_is_ai", false))


## The live [method should_show] context, read off the autoloads. Every read is guarded, so a
## bare harness scores an all-false context (which shows nothing) rather than erroring.
##
## "resumed" is NOT filled in here: only [GameWorldManager] knows whether this battle is being
## restored from a snapshot, so it stamps that key on the result before scoring it.
static func live_context() -> Dictionary:
	var ctx: Dictionary = {
		"replay": ReplayPlayback.is_playing(),
		"resumed": false,
		"arena": _controller_says("ArenaController", "is_active"),
		"challenge": _controller_says("ChallengeController", "is_capturing"),
		"campaign": _controller_says("CampaignController", "is_capturing"),
		"king_of_hill": _controller_says("KingOfTheHillController", "is_active"),
		"networked": false,
		"game_mode": -1,
		"opponent_is_ai": false,
	}

	var net: Node = _autoload("NetSession")
	if net != null and net.has_method("is_networked_match"):
		ctx["networked"] = bool(net.is_networked_match())

	var settings: Node = _autoload("GameSettings")
	if settings != null and "game_mode" in settings:
		ctx["game_mode"] = int(settings.game_mode)

	ctx["opponent_is_ai"] = _any_ai_participant()
	return ctx


## True when the autoload named [param autoload_name] exists, answers [param method_name], and
## says yes. The one shape every mode-controller probe in this file uses.
static func _controller_says(autoload_name: String, method_name: String) -> bool:
	var node: Node = _autoload(autoload_name)
	if node == null or not node.has_method(method_name):
		return false
	return bool(node.call(method_name))


## True when any registered participant is bot-controlled. Read off the live roster rather than
## GameSettings, because "is this side a human" is decided during setup (see
## GameWorldManager._setup_players), not by the menu that launched the match.
static func _any_ai_participant() -> bool:
	var pm: Node = _autoload("PlayerManager")
	if pm == null or not ("players" in pm):
		return false
	for player in pm.players:
		if player == null:
			continue
		if "is_ai" in player and bool(player.is_ai):
			return true
	return false


## An autoload by name, or null when it is not registered / there is no tree at all.
static func _autoload(autoload_name: String) -> Node:
	var loop: Object = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null(NodePath(autoload_name))


# =====================================================================================
#  DATA -- the pure assembler
# =====================================================================================

## Turn the raw per-side facts in [param sources] into the two CARDS this overlay renders.
##
## [param sources] keys (all optional):
##   "networked"           : bool
##   "local_name"          : String  -- this machine's player name
##   "local_rank"          : String  -- PlayerProfile.get_rank_name()
##   "local_points"        : int     -- PlayerProfile.get_points_total()
##   "local_character_id"  : String  -- first squad character on our side
##   "peer_card"           : Dictionary -- the opponent's MatchPeerInfo card, or {}
##   "roster_name"         : String  -- NetSession roster name for the opponent (the degraded
##                                      fallback when no card was announced)
##   "opponent_name"       : String  -- the LOCAL-play opponent's name (hotseat "Player 2")
##   "opponent_character_id": String
##
## Returns { "local": card, "opponent": card } where a card is
## { "name": String, "rank_name": String, "show_points": bool, "lifetime_points": int,
##   "character_id": String }. "rank_name" == "" means NO CHIP.
##
## THE TWO RULES THIS PINS:
##   * NEVER FABRICATE A RANK. A rank chip is rendered only where a real profile backs it --
##     the local player always, a networked opponent only from their announced card. A hotseat
##     guest gets no chip at all, because there is no second profile on this machine and
##     borrowing the local player's rank would be a lie about who is sitting there.
##   * MISSING COSMETIC DATA NEVER BLOCKS THE MATCH. A networked opponent whose card never
##     arrived (an older peer, a dropped lobby message) degrades to name-only -- the roster
##     name the server owns, or [constant MatchPeerInfo.DEFAULT_NAME] -- and the intro plays.
static func assemble_cards(sources: Dictionary) -> Dictionary:
	var networked: bool = bool(sources.get("networked", false))

	var local_name: String = String(sources.get("local_name", "")).strip_edges()
	if local_name.is_empty():
		local_name = "Player 1"
	var local: Dictionary = {
		"name": local_name,
		"rank_name": String(sources.get("local_rank", "")).strip_edges(),
		"show_points": true,
		"lifetime_points": maxi(0, int(sources.get("local_points", 0))),
		"character_id": String(sources.get("local_character_id", "")),
	}

	var opponent: Dictionary = {
		"name": "",
		"rank_name": "",
		"show_points": false,
		"lifetime_points": 0,
		"character_id": String(sources.get("opponent_character_id", "")),
	}

	if networked:
		var peer: Variant = sources.get("peer_card", {})
		var card: Dictionary = peer if peer is Dictionary else {}
		var peer_name: String = String(card.get("name", "")).strip_edges()
		if not peer_name.is_empty():
			opponent["name"] = peer_name
			opponent["rank_name"] = String(card.get("rank_name", "")).strip_edges()
			# The points LINE is shown only when the card actually carried the figure -- an
			# absent field must not render as a confident "0 lifetime pts".
			opponent["show_points"] = card.has("lifetime_points")
			opponent["lifetime_points"] = maxi(0, int(card.get("lifetime_points", 0)))
		else:
			# Degraded: name-only, from the roster the SERVER owns. No chip, no points.
			var roster_name: String = String(sources.get("roster_name", "")).strip_edges()
			opponent["name"] = roster_name if not roster_name.is_empty() else MatchPeerInfo.DEFAULT_NAME
	else:
		var hotseat_name: String = String(sources.get("opponent_name", "")).strip_edges()
		opponent["name"] = hotseat_name if not hotseat_name.is_empty() else "Player 2"
		# rank_name stays "" and show_points stays false -- see the NEVER FABRICATE rule above.

	return { "local": local, "opponent": opponent }


## Read the live [method assemble_cards] sources off the autoloads. Every read is guarded, so
## a bare harness yields a usable (if sparse) pair of cards rather than erroring.
static func collect_sources() -> Dictionary:
	var networked: bool = false
	var local_slot: int = 0
	var net: Node = _autoload("NetSession")
	if net != null and net.has_method("is_networked_match"):
		networked = bool(net.is_networked_match())
	if networked and net.has_method("local_slot"):
		local_slot = maxi(0, int(net.local_slot()))
	var opponent_slot: int = 1 if local_slot == 0 else 0

	var sources: Dictionary = {
		"networked": networked,
		"local_name": _name_for_slot(local_slot),
		"local_rank": "",
		"local_points": 0,
		"local_character_id": _character_id_for_slot(local_slot, true),
		"peer_card": {},
		"roster_name": "",
		"opponent_name": _name_for_slot(opponent_slot),
		"opponent_character_id": _character_id_for_slot(opponent_slot, false),
	}

	var profile: Node = _autoload("PlayerProfile")
	if profile != null:
		if profile.has_method("get_rank_name"):
			sources["local_rank"] = String(profile.get_rank_name())
		if profile.has_method("get_points_total"):
			sources["local_points"] = int(profile.get_points_total())

	if networked:
		sources["peer_card"] = MatchPeerInfo.get_any_peer_info(local_slot)
		sources["roster_name"] = _roster_name_excluding(local_slot)

	return sources


## The display name for roster slot [param slot]: the live [Player] first (it is what the turn
## banner and the end screen say), then the configured player-name list, then "".
static func _name_for_slot(slot: int) -> String:
	var pm: Node = _autoload("PlayerManager")
	if pm != null and ("players" in pm):
		for player in pm.players:
			if player == null or not ("player_id" in player):
				continue
			if int(player.player_id) != slot:
				continue
			if player.has_method("get_display_name"):
				return String(player.get_display_name())
			if "player_name" in player:
				return String(player.player_name)

	var settings: Node = _autoload("GameSettings")
	if settings != null and ("player_names" in settings):
		var names: Array = settings.player_names
		if slot >= 0 and slot < names.size():
			return String(names[slot])
	return ""


## The character whose portrait fronts slot [param slot]'s card: the first unit that side
## actually fielded on the live board (the honest read -- it is what the player is about to
## see), falling back to the first id of the announced/selected squad for that slot.
static func _character_id_for_slot(slot: int, is_local: bool) -> String:
	var pm: Node = _autoload("PlayerManager")
	if pm != null and ("players" in pm):
		for player in pm.players:
			if player == null or not ("player_id" in player):
				continue
			if int(player.player_id) != slot or not ("owned_units" in player):
				continue
			for unit in player.owned_units:
				var id: String = _character_id_of(unit)
				if not id.is_empty():
					return id

	if is_local:
		var settings: Node = _autoload("GameSettings")
		if settings != null and settings.has_method("get_selected_squad"):
			var squad: Array = settings.get_selected_squad()
			if not squad.is_empty():
				return String(squad[0])
		return ""

	var peer_squad: Array = MatchLoadouts.squad_for(slot)
	return String(peer_squad[0]) if not peer_squad.is_empty() else ""


## [param unit]'s character id, read defensively -- the resource first, the unit-type mirror
## second. Mirrors GameOverScreen._identify_unit.
static func _character_id_of(unit) -> String:
	if unit == null or not is_instance_valid(unit):
		return ""
	if "character_resource" in unit and unit.character_resource != null \
			and "character_id" in unit.character_resource:
		return String(unit.character_resource.character_id)
	if unit.has_method("get_unit_type"):
		return String(unit.get_unit_type())
	return ""


## The first roster name belonging to someone other than [param exclude_slot]. This is the
## SERVER-owned name, used when the opponent never announced a profile card.
static func _roster_name_excluding(exclude_slot: int) -> String:
	var net: Node = _autoload("NetSession")
	if net == null or not net.has_method("get_roster"):
		return ""
	var roster: Dictionary = net.get_roster()
	for peer_id in roster:
		var entry: Variant = roster[peer_id]
		if not (entry is Dictionary):
			continue
		if int((entry as Dictionary).get("slot", -1)) == exclude_slot:
			continue
		return String((entry as Dictionary).get("name", ""))
	return ""


# =====================================================================================
#  UI CONSTRUCTION
# =====================================================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "IntroRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallow clicks that reach the GUI layer. The tree pause is the primary block (see the
	# class doc); this is the belt to those braces for anything that runs while paused.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = BACKDROP
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	# Everything that SHAKES on impact lives under here; the flash does not, so the whole
	# screen does not appear to wobble with it.
	_shaker = Control.new()
	_shaker.name = "Shaker"
	_shaker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shaker)

	_divide = ColorRect.new()
	_divide.name = "Divide"
	_divide.color = ConquestTheme.AMBER_LITE
	_divide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shaker.add_child(_divide)

	_left_card = _build_card("LeftCard", SIDE_LOCAL)
	_shaker.add_child(_left_card)
	_right_card = _build_card("RightCard", SIDE_OPPONENT)
	_shaker.add_child(_right_card)

	_emblem = Label.new()
	_emblem.name = "Emblem"
	_emblem.text = "VS"
	_emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emblem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_emblem.add_theme_font_size_override("font_size", EMBLEM_FONT_SIZE)
	_emblem.add_theme_color_override("font_color", ConquestTheme.AMBER_LITE)
	_emblem.add_theme_color_override("font_outline_color", ConquestTheme.BROWN_DK)
	_emblem.add_theme_constant_override("outline_size", 12)
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shaker.add_child(_emblem)

	# Impact flash: additive white, full rect, outside the shaker.
	_flash = ColorRect.new()
	_flash.name = "ImpactFlash"
	_flash.color = ConquestTheme.CREAM
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash.material = mat
	_root.add_child(_flash)


## One player card: portrait plate over name, rank chip and lifetime-points line.
##
## Sized EXPLICITLY (not by a container) because its position is animated -- a card inside a
## layout container cannot be flown in from off-screen. The stable node path a test reads is
## `IntroRoot/Shaker/<LeftCard|RightCard>/Margin/Column/<NameLabel|RankRow/RankChip|PointsLabel>`.
func _build_card(card_name: String, side: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = card_name
	card.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", ConquestTheme.plate_box())

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# --- Portrait plate. A TextureRect and a monogram Label are BOTH built; exactly one is
	# visible at a time, so a portrait resolving asynchronously (PortraitCache captures over
	# several frames) is a visibility flip rather than a mid-animation node insertion.
	var frame := PanelContainer.new()
	frame.name = "PortraitFrame"
	frame.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _portrait_box())
	column.add_child(frame)

	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.clip_contents = true
	portrait.visible = false
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(portrait)

	var monogram := Label.new()
	monogram.name = "Monogram"
	monogram.text = "?"
	monogram.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	monogram.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	monogram.add_theme_font_size_override("font_size", MONOGRAM_FONT_SIZE)
	monogram.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
	monogram.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(monogram)

	# --- Name.
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = ""
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	name_label.add_theme_color_override("font_outline_color", ConquestTheme.BROWN_DK)
	name_label.add_theme_constant_override("outline_size", 5)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	# --- Rank chip. The gold-bordered chip vocabulary is GameOverScreen's versus block,
	# reproduced here (see _chip_box) so the pre-match and post-match cards read as one family.
	# An HBox with CENTER alignment does the centring: a bare Label would stretch full width
	# and its stylebox with it, which is what makes a chip stop looking like a chip.
	var rank_row := HBoxContainer.new()
	rank_row.name = "RankRow"
	rank_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rank_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rank_row)

	var chip := Label.new()
	chip.name = "RankChip"
	chip.text = ""
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_theme_font_size_override("font_size", CHIP_FONT_SIZE)
	chip.add_theme_color_override("font_color", ConquestTheme.EL_HOLY)
	chip.add_theme_stylebox_override("normal", _chip_box())
	chip.visible = false
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_row.add_child(chip)

	# --- Lifetime points.
	var points := Label.new()
	points.name = "PointsLabel"
	points.text = ""
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points.add_theme_font_size_override("font_size", POINTS_FONT_SIZE)
	points.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
	points.visible = false
	points.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(points)

	_card_parts[side] = {
		"card": card,
		"name": name_label,
		"chip": chip,
		"points": points,
		"portrait": portrait,
		"monogram": monogram,
	}
	return card


## The dark inset plate a portrait / monogram sits on.
func _portrait_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ConquestTheme.HP_TRACK
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = ConquestTheme.BROWN
	return sb


## The gold-bordered rank chip, same vocabulary as GameOverScreen's versus block.
func _chip_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ConquestTheme.PLATE_BG.r, ConquestTheme.PLATE_BG.g, ConquestTheme.PLATE_BG.b, 0.9)
	sb.border_color = ConquestTheme.EL_HOLY
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	return sb


# =====================================================================================
#  PUBLIC API
# =====================================================================================

## True while the intro is on screen.
func is_playing() -> bool:
	return _playing


## The live card dictionary currently rendered for [param side] (what [method assemble_cards]
## returned), or {} before [method play].
func card_for(side: int) -> Dictionary:
	var card: Variant = _cards.get(side, {})
	return card if card is Dictionary else {}


## Play the intro for the two sides described by [param sources] (the shape
## [method collect_sources] returns; it is run through [method assemble_cards] here so a
## caller never has to). Re-entrant calls are DROPPED without raising a second
## [signal finished] -- the running play still owns that signal.
func play(sources: Dictionary = {}) -> void:
	if _playing:
		return
	_playing = true
	_finished_emitted = false

	var cards: Dictionary = assemble_cards(sources)
	_apply_card(SIDE_LOCAL, cards.get("local", {}))
	_apply_card(SIDE_OPPONENT, cards.get("opponent", {}))
	_cards = { SIDE_LOCAL: cards.get("local", {}), SIDE_OPPONENT: cards.get("opponent", {}) }

	_layout()
	_pause_tree()

	if not _animations_on():
		_play_static()
		return
	_play_clash()


## Jump straight to the end state: kill every tween, hide the overlay, release the first-turn
## hold. Idempotent and safe to call before [method play] (it simply does nothing). This is
## what ANY input does -- see [method _input].
func skip() -> void:
	if not _playing:
		return
	_end()


# =====================================================================================
#  ANIMATION
# =====================================================================================

## Position the cards, the divide and the emblem for the CURRENT viewport, and stash the rest
## positions the slam animates toward.
func _layout() -> void:
	var screen: Vector2 = _screen_size()
	var cx: float = screen.x * 0.5
	var cy: float = screen.y * 0.5

	_left_rest = Vector2(cx - CARD_GAP * 0.5 - CARD_WIDTH, cy - CARD_HEIGHT * 0.5)
	_right_rest = Vector2(cx + CARD_GAP * 0.5, cy - CARD_HEIGHT * 0.5)

	if _left_card != null:
		_left_card.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
		_left_card.position = _left_rest
	if _right_card != null:
		_right_card.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
		_right_card.position = _right_rest

	# The angled centre divide: a tall thin stripe through the gap, rotated about its middle
	# and overshooting the viewport height so the rotation leaves no gap at top or bottom.
	if _divide != null:
		var divide_h: float = screen.y * 1.6
		_divide.size = Vector2(DIVIDE_WIDTH, divide_h)
		_divide.pivot_offset = _divide.size * 0.5
		_divide.position = Vector2(cx - DIVIDE_WIDTH * 0.5, cy - divide_h * 0.5)
		_divide.rotation = deg_to_rad(DIVIDE_ANGLE_DEG)

	if _emblem != null:
		var emblem_size := Vector2(220.0, 140.0)
		_emblem.size = emblem_size
		_emblem.pivot_offset = emblem_size * 0.5
		_emblem.position = Vector2(cx - emblem_size.x * 0.5, cy - emblem_size.y * 0.5)


## The full clash: slam in -> impact -> hold -> part. ONE chained tween owns the stages; the
## flash and the shake get their own tweens from [method _impact] so they overlap the hold
## instead of blocking it.
##
## Each stage's FIRST tweener is plain (it auto-chains after the previous stage) and any
## further tweeners in that stage are `.parallel()` -- the same discipline [UltimateCutIn]
## documents, and the reason the hold cannot race the part-out.
func _play_clash() -> void:
	_kill_tweens()

	var screen: Vector2 = _screen_size()
	var off: float = screen.x + CARD_WIDTH   # far enough that both cards start fully outside

	_root.visible = true
	_root.modulate.a = 1.0
	_backdrop.modulate.a = 0.0
	_flash.modulate.a = 0.0
	_left_card.position = Vector2(_left_rest.x - off, _left_rest.y)
	_right_card.position = Vector2(_right_rest.x + off, _right_rest.y)
	_shaker.position = Vector2.ZERO
	_divide.scale = Vector2(1.0, 0.0)
	_emblem.scale = Vector2.ZERO
	_emblem.modulate.a = 0.0

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	# --- Stage 1: SLAM IN, with overshoot (TRANS_BACK / EASE_OUT is the overshoot).
	_tween.tween_property(_left_card, "position:x", _left_rest.x, _scaled(SLAM_IN)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_right_card, "position:x", _right_rest.x, _scaled(SLAM_IN)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_backdrop, "modulate:a", 1.0, _scaled(SLAM_IN * 0.6)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_divide, "scale:y", 1.0, _scaled(SLAM_IN)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# --- Stage 2: IMPACT -- flash + shake (their own tweens) and the emblem popping in.
	_tween.tween_callback(_impact)
	_tween.tween_property(_emblem, "scale", Vector2.ONE, _scaled(IMPACT)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_emblem, "modulate:a", 1.0, _scaled(IMPACT * 0.6)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# --- Stage 3: the readable HOLD.
	_tween.tween_interval(_scaled(HOLD))

	# --- Stage 4: PART -- the cards separate vertically as the whole overlay fades, revealing
	# the battle underneath.
	var travel: float = screen.y * 0.85
	_tween.tween_property(_left_card, "position:y", _left_rest.y - travel, _scaled(PART_OUT)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_right_card, "position:y", _right_rest.y + travel, _scaled(PART_OUT)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_root, "modulate:a", 0.0, _scaled(PART_OUT)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	_tween.tween_callback(_end)


## The impact beat: a one-frame-ish white flash, a decaying screen shake, and the clash sting.
## Each gets its own tween so none of them holds up the main chain.
func _impact() -> void:
	_play_sting()
	_play_flash()
	_play_shake()


func _play_flash() -> void:
	if _flash == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.modulate.a = 0.0
	_flash_tween = create_tween()
	_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_flash_tween.tween_property(_flash, "modulate:a", 0.75, _scaled(0.05)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, _scaled(0.20)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## A short decaying shake of everything under [member _shaker]. Four halving swings, so it
## reads as a hit rather than a wobble.
func _play_shake() -> void:
	if _shaker == null:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shaker.position = Vector2.ZERO
	_shake_tween = create_tween()
	_shake_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var amount: float = SHAKE_PX
	var step: float = _scaled(0.045)
	for i in 4:
		var swing: float = 1.0 if i % 2 == 0 else -1.0
		_shake_tween.tween_property(_shaker, "position",
				Vector2(amount * swing, amount * swing * 0.4), step) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		amount *= 0.5
	_shake_tween.tween_property(_shaker, "position", Vector2.ZERO, step) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## ANIMATIONS OFF (or reduced motion): no slam, no shake, no flash. The cards are simply on
## screen, already met, for [constant STATIC_HOLD] -- long enough to READ who is playing --
## and then it ends. Never skipped outright: [GameWorldManager] is awaiting [signal finished]
## and must always be released. A SceneTreeTimer (not a tween) so the beat is a fixed real
## duration regardless of the Battle-Speed scale, which is 0 in this state.
func _play_static() -> void:
	_kill_tweens()
	_root.visible = true
	_root.modulate.a = 1.0
	_backdrop.modulate.a = 1.0
	_flash.modulate.a = 0.0
	_shaker.position = Vector2.ZERO
	_left_card.position = _left_rest
	_right_card.position = _right_rest
	_divide.scale = Vector2.ONE
	_emblem.scale = Vector2.ONE
	_emblem.modulate.a = 1.0

	var tree: SceneTree = get_tree()
	if tree == null:
		# No tree to time against -- release on the next idle rather than hanging the boot.
		call_deferred("_end")
		return
	var timer: SceneTreeTimer = tree.create_timer(STATIC_HOLD, true, false, true)
	timer.timeout.connect(_end)


# =====================================================================================
#  CONTENT
# =====================================================================================

## Render one assembled card. Portrait resolution is fired off asynchronously and lands (or
## does not) into the already-built TextureRect -- the monogram stays up until it does, so a
## headless run or an uncaptured character simply keeps the placeholder.
func _apply_card(side: int, card: Dictionary) -> void:
	var parts: Dictionary = _card_parts.get(side, {})
	if parts.is_empty():
		return

	var player_name: String = String(card.get("name", ""))
	var name_label: Label = parts["name"]
	name_label.text = player_name

	var chip: Label = parts["chip"]
	var rank_name: String = String(card.get("rank_name", "")).strip_edges()
	chip.text = rank_name.to_upper()
	# No chip at all rather than an empty gold box -- a hotseat guest has no rank, and a peer
	# that never announced one must not appear to have a blank rank.
	chip.visible = not rank_name.is_empty()

	var points: Label = parts["points"]
	if bool(card.get("show_points", false)):
		points.text = "%d lifetime pts" % maxi(0, int(card.get("lifetime_points", 0)))
		points.visible = true
	else:
		points.text = ""
		points.visible = false

	var monogram: Label = parts["monogram"]
	monogram.text = player_name.substr(0, 1).to_upper() if not player_name.is_empty() else "?"

	_request_portrait(side, String(card.get("character_id", "")))


## Ask [PortraitCache] for this side's portrait. Async by contract (a capture takes frames), so
## the callback re-validates everything it touches: the intro may have finished, been skipped
## or been freed by the time a capture lands, and swapping a texture into a freed node is the
## bug this guard exists for. Headless resolves to null through the ordinary callback path.
func _request_portrait(side: int, character_id: String) -> void:
	if character_id.is_empty():
		return
	var parts: Dictionary = _card_parts.get(side, {})
	if parts.is_empty():
		return

	# Already warmed by the battle HUD? Use it now, with no capture at all.
	var cached: Texture2D = PortraitCache.get_cached(character_id)
	if cached != null:
		_set_portrait(side, cached)
		return

	PortraitCache.get_portrait(character_id, func(tex: Texture2D) -> void:
		if not is_instance_valid(self):
			return
		_set_portrait(side, tex)
	)


func _set_portrait(side: int, tex: Texture2D) -> void:
	if tex == null:
		return
	var parts: Dictionary = _card_parts.get(side, {})
	if parts.is_empty():
		return
	var portrait: TextureRect = parts["portrait"]
	var monogram: Label = parts["monogram"]
	if portrait == null or not is_instance_valid(portrait):
		return
	portrait.texture = tex
	portrait.visible = true
	if monogram != null and is_instance_valid(monogram):
		monogram.visible = false


# =====================================================================================
#  INPUT
# =====================================================================================

## ANY input skips: a click, a tap, a key (space / ESC / anything). Handled in `_input` rather
## than `_unhandled_input` because the whole point is to beat every other handler to it -- and
## the event is consumed so a skip press can never also reach the board underneath.
func _input(event: InputEvent) -> void:
	if not _playing:
		return
	if not _is_skip_event(event):
		return
	get_viewport().set_input_as_handled()
	skip()


## True for a PRESS of any kind. Deliberately broad ("any input skips instantly"), but
## deliberately not motion: sliding the mouse across the screen must not cancel the reveal.
static func _is_skip_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false


# =====================================================================================
#  LIFECYCLE
# =====================================================================================

## End the intro, exactly once: kill the tweens, hide the overlay, lift the pause, release the
## awaiting boot. Every exit path (natural end, skip, tree exit) funnels through here, which is
## what guarantees the first-turn hold is always released and the tree is never left paused.
func _end() -> void:
	if not _playing and _finished_emitted:
		return
	_playing = false
	_set_idle()
	_unpause_tree()
	if _finished_emitted:
		return
	_finished_emitted = true
	finished.emit()


func _set_idle() -> void:
	_kill_tweens()
	if _shaker != null:
		_shaker.position = Vector2.ZERO
	if _flash != null:
		_flash.modulate.a = 0.0
	if _root != null:
		_root.modulate.a = 0.0
		_root.visible = false


func _kill_tweens() -> void:
	for tween in [_tween, _flash_tween, _shake_tween]:
		if tween != null and (tween as Tween).is_valid():
			(tween as Tween).kill()
	_tween = null
	_flash_tween = null
	_shake_tween = null


## A scene change (Main Menu, a rematch) can free this node mid-play. Releasing the signal here
## is what stops the awaiting boot -- or a test -- hanging on a `finished` that would never come,
## and it is also the last chance to lift a pause this node applied.
func _exit_tree() -> void:
	if _playing or not _finished_emitted:
		_end()


# --- Pause ------------------------------------------------------------------

## Freeze gameplay for the duration. Safe because this node is PROCESS_MODE_ALWAYS and every
## tween is TWEEN_PAUSE_PROCESS -- the intro keeps animating and keeps hearing input while
## nothing else in the tree does. Records whether WE paused, so an already-paused tree (a pause
## menu, another overlay) is handed back exactly as it was found.
func _pause_tree() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	tree.paused = true
	_paused_tree = true


func _unpause_tree() -> void:
	if not _paused_tree:
		return
	_paused_tree = false
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false


# --- Null-safe helpers -------------------------------------------------------

## True when the player has animations enabled -- the project's reduced-motion switch (see
## GameSettings.animations_on). Defaults to ON where GameSettings is absent (a bare harness),
## mirroring [UltimateCutIn._animations_on].
func _animations_on() -> bool:
	if typeof(GameSettings) != TYPE_OBJECT or GameSettings == null:
		return true
	if not GameSettings.has_method("animations_on"):
		return true
	return bool(GameSettings.animations_on())


## An authored duration scaled by the Battle-Speed setting, with a small floor so a zero can
## never stall the tween chain (the animations-off state is handled separately, in _play_static).
func _scaled(base_seconds: float) -> float:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null \
			and GameSettings.has_method("scaled_time"):
		return maxf(GameSettings.scaled_time(base_seconds), 0.01)
	return base_seconds


## The clash sting. Reuses the existing punchy &"sfx_attack" cue rather than shipping a new
## audio file -- the same choice (and the same reasoning) as [UltimateCutIn._play_sfx]: an
## unassigned or missing cue no-ops inside the manager, so this is silent and safe headless.
func _play_sting() -> void:
	if typeof(AudioManager) != TYPE_OBJECT or AudioManager == null:
		return
	if not AudioManager.has_method("play_sfx"):
		return
	AudioManager.play_sfx(&"sfx_attack")


func _screen_size() -> Vector2:
	var vp: Viewport = get_viewport()
	if vp != null:
		var s: Vector2 = vp.get_visible_rect().size
		if s.x > 0.0 and s.y > 0.0:
			return s
	return Vector2(1280.0, 720.0)
