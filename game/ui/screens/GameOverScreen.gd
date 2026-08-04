extends Control

class_name GameOverScreen

# POST-MATCH SUMMARY PAGE: a full-screen VICTORY / DEFEAT card that drops in when the
# battle is decided, and then reports what actually happened -- who you lost, who you
# killed, what you earned, and (in a networked versus match) who you beat. Offers
# Rematch (reload the battle), Main Menu, and Quit.
#
# Code-built like TerrainInfoPanel / CombatForecastPanel: the .tscn is just a full-rect
# Control shell with this script attached, and _ready() builds the backdrop, result card,
# banner, summary sections and buttons, then themes them with the amber battle HUD look
# (ConquestTheme). Hidden by default; GameWorldManager decides the outcome and calls
# show_victory()/show_defeat() (or show_result()).
#
# Idempotent: once shown it ignores further calls (`_shown`), so multiple elimination
# signals arriving in the same frame never restack the reveal.
#
# Runs while the tree is paused: the whole node is PROCESS_MODE_ALWAYS and the reveal
# Tween is TWEEN_PAUSE_PROCESS, so pausing gameplay on game over does not freeze the
# animation or block the buttons.
#
# ---------------------------------------------------------------------------------
# PAGE STRUCTURE (banner header, then a dark gold-headed plate, 24/16 type rhythm)
# ---------------------------------------------------------------------------------
#   VICTORY / DEFEAT          -- the animated banner + subtitle (unchanged header)
#   BATTLE    rounds | lost | defeated | dealt | taken
#             > lost-unit rows (portrait + name), enemies-defeated names
#   REWARDS   points gained this match | balance | challenge score (+PERFECT)
#             > ITEMS FOUND rows (glyph + name), capped at 3 with a "+N more" tail;
#               absent entirely when the battle dropped nothing
#   VERSUS    (networked matches only) opponent name + rank chip + their lifetime
#             points, your rank progress bar
#
# WHERE EACH FIGURE COMES FROM -- real vs. hooked:
#   * rounds            REAL. TurnSystemManager's active turn system's current_turn.
#   * lost / defeated   REAL, latched HERE off GameEvents.unit_eliminated all battle (this
#                       screen is mounted, hidden, from battle start, so it hears every
#                       death as it happens rather than reconstructing history at reveal).
#                       Names + character ids are captured in the same handler, off the
#                       live unit, so a freed unit is never read later.
#   * damage dealt/taken REAL, latched off GameEvents.damage_dealt, whose payload is
#                       (attacker, defender, damage) -- both sides are Units with an owner,
#                       so "did the human deal or take this" is unambiguous. ONE honest
#                       caveat, documented on the handler: a friendly-fire hit counts on
#                       BOTH lines, because it genuinely is both.
#   * points gained     REAL, as a DIFF: the lifetime points total is latched at battle
#                       start (see _latch_battle_start) and subtracted at reveal.
#                       PlayerProfile has no "what did the last battle pay" accessor, so a
#                       diff is the honest read; lifetime total is used rather than the
#                       spendable balance because a spend must never read as a loss.
#   * challenge score   REAL but CONDITIONAL -- see _challenge_result(). ChallengeController
#                       still exposes no "the run just ended, here is its result" accessor;
#                       what it does expose is is_capturing() + active_challenge() +
#                       capture_counters() + result_for(id). The row is shown only when a
#                       challenge is live AND the persisted record's turn count matches the
#                       live one, which is what proves the record is THIS attempt's rather
#                       than a stale earlier one.
#   * item drops        REAL, and no longer a hook gap: ItemSystem now keeps a per-battle
#                       drop latch (cleared in its setup(), appended by its single award()
#                       entry point) and answers ItemSystem.drops_this_battle() with the ids
#                       it granted. Resolved to names/glyphs through ItemLibrary at reveal.
#                       A battle that dropped nothing -- the usual case, ~65% -- renders NO
#                       row at all rather than an empty heading.
#   * opponent card     REAL, but exchanged at MATCH START, not read at match end: see
#                       [MatchPeerInfo]. By the time a versus match ends the opponent may
#                       have forfeited or dropped, so there would be nobody left to ask.
#
# ARENA SUPPRESSION (absolute): this screen must NEVER appear between arena rounds -- the
# run's own ArenaResultsScreen is arena's summary. GameWorldManager already routes an arena
# battle-end into ArenaController.notify_round_ended and returns before touching this screen
# (see its _evaluate_game_end), and that is still the primary gate. show_result() ALSO
# early-returns on a battle-start latch of ArenaController.is_active() -- see
# _arena_suppressed() -- so a future caller that does not know the rule cannot break it.
#
# INPUT: ESC (ui_cancel) goes to the Main Menu while the screen is shown -- Enter/Space
# already "press" the focused Rematch button via Godot's built-in ui_accept handling on a
# focused Button, so no extra wiring is needed for that.

# --- Tunables ---------------------------------------------------------------
const CARD_WIDTH := 600.0
const REVEAL_SCALE_FROM := 0.6   # banner/card starts small then pops to 1.0
const REVEAL_SLIDE_PX := 26.0    # card starts this many px high and settles down

## Type rhythm for the summary plate: 24px values under 16px gold headers.
const HEADER_FONT_SIZE := 16
const VALUE_FONT_SIZE := 24
const ROW_FONT_SIZE := 14

## At most this many fallen-unit rows are listed; the rest collapse into "+N more", so a
## wipe on a big map can never grow the card taller than the viewport.
const MAX_LOST_ROWS := 3
## Square edge (px) of a lost-unit row's portrait / monogram badge.
const PORTRAIT_PX := 26.0

## At most this many item-drop rows are listed, with the same "+N more" tail the casualty
## rows use. Same number and same discipline on purpose: the card's height budget does not
## care which section grew, and a REWARDS block that could run long would push the buttons
## off a small viewport exactly as an unbounded casualty list would.
const MAX_DROP_ROWS := 3

# Banner accents: bright gold for a win, desaturated red for a loss.
const VICTORY_GOLD := Color("f5c95a")
const DEFEAT_RED := Color("c15a48")

# Outcome tags (also used by GameWorldManager for the neutral versus banner).
const OUTCOME_VICTORY := &"victory"
const OUTCOME_DEFEAT := &"defeat"

## Subtitle shown instead of the caller's when the opponent quit rather than lost.
const SUBTITLE_FORFEIT := "Opponent forfeited."

# Idempotency guard -- true once the screen has been revealed.
var _shown: bool = false

# Nodes built in _create_ui().
var _backdrop: ColorRect
var _card: PanelContainer
var _banner_label: Label
var _subtitle_label: Label
var _summary_card: PanelContainer
## Every gold section/stat header, recoloured after ConquestTheme.apply_to() strips overrides.
var _summary_headers: Array[Label] = []
## Every cream value label, same reason.
var _summary_values: Array[Label] = []
## Every dim caption/row label, same reason.
var _summary_captions: Array[Label] = []

var _rounds_value: Label
var _lost_value: Label
var _defeated_value: Label
var _dealt_value: Label
var _taken_value: Label
var _lost_rows_box: VBoxContainer
var _defeated_names_label: Label

var _gained_value: Label
var _balance_value: Label
var _challenge_row: HBoxContainer
var _challenge_value: Label
var _perfect_badge: Label
## Holder for the item-drop rows. Contains ONLY runtime-built children (see
## [method _populate_drop_rows]), so it can be cleared wholesale without freeing anything
## the one-time colour pass still points at.
var _drop_rows_box: VBoxContainer

var _versus_box: VBoxContainer
var _opponent_name_label: Label
var _rank_chip: Label
var _opponent_points_label: Label
var _rank_bar: ProgressBar
var _rank_caption: Label

var _button_box: VBoxContainer
var _rematch_button: Button
var _menu_button: Button
var _quit_button: Button
var _reveal_tween: Tween

# --- Results tally (latched off GameEvents all battle) ------------------------
var _friendlies_lost: int = 0
var _enemies_defeated: int = 0
## Fallen HUMAN units, in the order they died: [{ "name": String, "character_id": String }].
var _lost_units: Array[Dictionary] = []
## Fallen ENEMY units, same shape.
var _defeated_units: Array[Dictionary] = []
# instance_id -> true, so a duplicate elimination signal for the same unit
# (documented elsewhere in this codebase, e.g. player_eliminated) never counts twice.
var _counted_unit_ids: Dictionary = {}
var _damage_dealt: int = 0
var _damage_taken: int = 0

# --- Battle-start latches ------------------------------------------------------
# Sampled ONCE, at battle start, never re-queried at reveal time: by the time the match
# ends the opponent may have left (so is_networked_match() would read false) and the win
# points have already been granted (so the starting balance would be unrecoverable).
var _start_points_total: int = 0
var _was_networked_match: bool = false
var _local_slot: int = -1
var _arena_run_at_start: bool = false
## True once the initial (non-runtime) spawn pass re-latched -- the authoritative
## "the battle is actually starting now" moment; _ready seeds the same values earlier so a
## battle that never emits a spawn pass (e.g. a restored snapshot) is still covered.
var _spawn_latched: bool = false

## Set when NetSession reports the opponent forfeited or vanished from a live match. Drives
## the "Opponent forfeited." subtitle -- leaving a live match is a loss either way, which is
## why the disconnect signal is treated identically (see NetSession.opponent_left).
var _opponent_forfeited: bool = false


func _ready() -> void:
	name = "GameOverScreen"

	# Animate + accept clicks even when gameplay pauses on game over (see file note).
	process_mode = Node.PROCESS_MODE_ALWAYS

	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Swallow clicks once shown so the board underneath can't be commanded. While
	# hidden (visible = false) a Control receives no input, so this never blocks
	# the board during normal play or at boot.
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Draw above every HUD panel in the shared "UI" CanvasLayer.
	z_as_relative = false
	z_index = 4096

	_create_ui()
	visible = false

	# Tally subscription: this screen exists (hidden) for the whole battle, so it
	# hears every elimination as it happens rather than reconstructing history later.
	_connect_tally()
	_connect_session_signals()

	# Seed the battle-start latches now. GameWorldManager mounts this screen BEFORE the map
	# loads (see its _ready), so this runs ahead of the spawn pass, which then re-latches at
	# the exact battle-start moment. Seeding here as well is what covers a battle that never
	# emits an initial spawn pass at all.
	_latch_battle_start()


func _create_ui() -> void:
	# Dimmed backdrop covering the whole viewport; fades in with the reveal and,
	# with mouse_filter STOP, catches any click outside the card.
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.04, 0.02, 0.0, 0.72)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	# Centered result card. Anchors pinned to the viewport centre with grow BOTH
	# means it is sized to its content's minimum and centred, no CenterContainer
	# needed -- leaving its transform (scale/position) free for the pop animation.
	_card = PanelContainer.new()
	_card.name = "ResultCard"
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	# Keep the scale pivot at the card's centre as it lays out, so the pop scales
	# from the middle rather than the top-left corner.
	_card.resized.connect(_recenter_pivot)
	add_child(_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_card.add_child(vb)

	_banner_label = Label.new()
	_banner_label.name = "BannerLabel"
	_banner_label.text = "VICTORY"
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 56)
	vb.add_child(_banner_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.text = "All enemies defeated!"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 20)
	vb.add_child(_subtitle_label)

	# The summary PAGE: BATTLE / REWARDS / VERSUS sections on one dark plate.
	# Structure only here -- colours and the dark plate stylebox are applied in
	# _style_summary_card() AFTER ConquestTheme.apply_to() below, because apply_to's
	# recursive _restyle() would otherwise strip a Label colour override set before it
	# and repaint any PanelContainer back to the bright amber panel_box() (see that
	# method's own banner/subtitle colours, set the same way, for precedent).
	_summary_card = _build_summary_card()
	vb.add_child(_summary_card)

	var sep := HSeparator.new()
	vb.add_child(sep)

	_button_box = VBoxContainer.new()
	_button_box.name = "Buttons"
	_button_box.add_theme_constant_override("separation", 8)
	vb.add_child(_button_box)

	_rematch_button = _make_button("Rematch")
	_rematch_button.pressed.connect(_on_rematch_pressed)
	_button_box.add_child(_rematch_button)

	_menu_button = _make_button("Main Menu")
	_menu_button.pressed.connect(_on_main_menu_pressed)
	_button_box.add_child(_menu_button)

	_quit_button = _make_button("Quit")
	_quit_button.pressed.connect(_on_quit_pressed)
	_button_box.add_child(_quit_button)

	# Amber HUD look. apply_to strips baked font_color overrides, so the banner
	# outline / subtitle tint / per-outcome banner colour are all set AFTER it so
	# they survive.
	ConquestTheme.apply_to(self)

	# Punchy dark outline on the big banner, and a muted subtitle.
	_banner_label.add_theme_constant_override("outline_size", 8)
	_banner_label.add_theme_color_override("font_outline_color", ConquestTheme.BROWN_DK)
	_subtitle_label.add_theme_color_override("font_color", ConquestTheme.INK_SOFT)

	_style_summary_card()


# =====================================================================================
#  SUMMARY PAGE CONSTRUCTION
# =====================================================================================

## The whole dark plate: BATTLE, REWARDS and (conditionally) VERSUS sections stacked on one
## ConquestTheme.plate_box() with a 16px inner margin. Values start blank/zero and are filled
## in by [method _populate_summary] right before the reveal.
func _build_summary_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "SummaryCard"

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "SummaryColumn"
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	_build_battle_section(col)
	col.add_child(_thin_rule())
	_build_rewards_section(col)
	_versus_box = _build_versus_section()
	col.add_child(_versus_box)

	return card


## BATTLE: the five-figure stat row, then the named casualty rows and the enemy roll-call.
func _build_battle_section(col: VBoxContainer) -> void:
	col.add_child(_section_header("BATTLE"))

	var row := HBoxContainer.new()
	row.name = "StatRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)

	_rounds_value = _add_stat_block(row, "ROUNDS")
	_lost_value = _add_stat_block(row, "LOST")
	_defeated_value = _add_stat_block(row, "DEFEATED")
	_dealt_value = _add_stat_block(row, "DEALT")
	_taken_value = _add_stat_block(row, "TAKEN")

	_lost_rows_box = VBoxContainer.new()
	_lost_rows_box.name = "LostUnitRows"
	_lost_rows_box.add_theme_constant_override("separation", 4)
	_lost_rows_box.visible = false
	col.add_child(_lost_rows_box)

	_defeated_names_label = _caption_label("")
	_defeated_names_label.name = "DefeatedNames"
	_defeated_names_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_defeated_names_label.visible = false
	col.add_child(_defeated_names_label)


## REWARDS: points earned by THIS match, the resulting balance, and -- only when a challenge
## attempt is provably the one that just finished -- its score and perfect badge.
func _build_rewards_section(col: VBoxContainer) -> void:
	col.add_child(_section_header("REWARDS"))

	var row := HBoxContainer.new()
	row.name = "RewardRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	col.add_child(row)

	_gained_value = _add_stat_block(row, "POINTS EARNED")
	_balance_value = _add_stat_block(row, "BALANCE")

	_challenge_row = HBoxContainer.new()
	_challenge_row.name = "ChallengeRow"
	_challenge_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_challenge_row.add_theme_constant_override("separation", 8)
	_challenge_row.visible = false
	col.add_child(_challenge_row)

	var challenge_header := _caption_label("CHALLENGE SCORE")
	_challenge_row.add_child(challenge_header)

	_challenge_value = Label.new()
	_challenge_value.text = "0"
	_challenge_value.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	_summary_values.append(_challenge_value)
	_challenge_row.add_child(_challenge_value)

	_perfect_badge = Label.new()
	_perfect_badge.text = "PERFECT"
	_perfect_badge.add_theme_font_size_override("font_size", 12)
	_perfect_badge.visible = false
	_challenge_row.add_child(_perfect_badge)

	# ITEM DROPS. Built empty and hidden; filled at reveal from the per-battle latch. Nothing
	# persistent lives inside it (not even the heading) because _populate_drop_rows frees
	# every child -- the same reason _populate_lost_rows builds its "+N more" inline.
	_drop_rows_box = VBoxContainer.new()
	_drop_rows_box.name = "DropRows"
	_drop_rows_box.add_theme_constant_override("separation", 4)
	_drop_rows_box.visible = false
	col.add_child(_drop_rows_box)


## VERSUS: built ALWAYS (so the node references are never null) but hidden unless
## [method should_show_versus_block] says this was a networked match -- see
## [method _populate_versus].
func _build_versus_section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "VersusBlock"
	box.add_theme_constant_override("separation", 8)
	box.visible = false

	box.add_child(_thin_rule())
	box.add_child(_section_header("VERSUS"))

	var row := HBoxContainer.new()
	row.name = "OpponentRow"
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_opponent_name_label = Label.new()
	_opponent_name_label.text = MatchPeerInfo.DEFAULT_NAME
	_opponent_name_label.add_theme_font_size_override("font_size", 18)
	_opponent_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opponent_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_summary_values.append(_opponent_name_label)
	row.add_child(_opponent_name_label)

	_rank_chip = Label.new()
	_rank_chip.name = "RankChip"
	_rank_chip.text = ""
	_rank_chip.add_theme_font_size_override("font_size", 12)
	_rank_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_chip.visible = false
	row.add_child(_rank_chip)

	_opponent_points_label = _caption_label("")
	_opponent_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_opponent_points_label)

	_rank_bar = ProgressBar.new()
	_rank_bar.name = "RankProgress"
	_rank_bar.min_value = 0.0
	_rank_bar.max_value = 1.0
	_rank_bar.step = 0.001
	_rank_bar.value = 0.0
	_rank_bar.show_percentage = false
	_rank_bar.custom_minimum_size = Vector2(0.0, 8.0)
	box.add_child(_rank_bar)

	_rank_caption = _caption_label("")
	box.add_child(_rank_caption)

	return box


## A gold section header ("BATTLE" / "REWARDS" / "VERSUS"), left-aligned above its block.
func _section_header(text: String) -> Label:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	_summary_headers.append(header)
	return header


## One stat block: a centred 16px header label over a centred 24px value label.
## Returns the value label (callers keep that reference; headers/values are collected for
## the post-apply_to colour pass).
func _add_stat_block(row: HBoxContainer, header_text: String) -> Label:
	var block := VBoxContainer.new()
	block.alignment = BoxContainer.ALIGNMENT_CENTER
	block.add_theme_constant_override("separation", 2)
	row.add_child(block)

	var header := Label.new()
	header.text = header_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	block.add_child(header)
	_summary_headers.append(header)

	var value := Label.new()
	value.text = "0"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", VALUE_FONT_SIZE)
	block.add_child(value)
	_summary_values.append(value)

	return value


## A dim small-caps-ish caption line (the row/roll-call type size).
func _caption_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	_summary_captions.append(label)
	return label


func _thin_rule() -> HSeparator:
	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 2)
	return rule


## Dark plate + gold headers / cream values / dim captions. Called AFTER
## ConquestTheme.apply_to() -- see the comment where _summary_card is built in _create_ui().
func _style_summary_card() -> void:
	if _summary_card == null:
		return
	_summary_card.add_theme_stylebox_override("panel", ConquestTheme.plate_box())
	for header in _summary_headers:
		header.add_theme_color_override("font_color", ConquestTheme.EL_HOLY)
	for value in _summary_values:
		value.add_theme_color_override("font_color", ConquestTheme.CREAM)
	for caption in _summary_captions:
		caption.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)

	if _perfect_badge != null:
		_perfect_badge.add_theme_color_override("font_color", ConquestTheme.EL_HOLY)

	# Gold-bordered rank chip (the one bit of chrome in the versus row).
	if _rank_chip != null:
		var chip := StyleBoxFlat.new()
		chip.bg_color = Color(ConquestTheme.PLATE_BG.r, ConquestTheme.PLATE_BG.g, ConquestTheme.PLATE_BG.b, 0.9)
		chip.border_color = ConquestTheme.EL_HOLY
		chip.set_border_width_all(1)
		chip.set_corner_radius_all(4)
		chip.content_margin_left = 8.0
		chip.content_margin_right = 8.0
		chip.content_margin_top = 2.0
		chip.content_margin_bottom = 2.0
		_rank_chip.add_theme_stylebox_override("normal", chip)
		_rank_chip.add_theme_color_override("font_color", ConquestTheme.EL_HOLY)

	if _rank_bar != null:
		_rank_bar.add_theme_stylebox_override("background", _bar_box(ConquestTheme.HP_TRACK))
		_rank_bar.add_theme_stylebox_override("fill", _bar_box(ConquestTheme.EL_HOLY))


func _bar_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(3)
	return box


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.focus_mode = Control.FOCUS_ALL
	return b


# --- Public API --------------------------------------------------------------

## True once the screen has been revealed (used by callers to avoid re-triggering).
func is_shown() -> bool:
	return _shown


## Reveal a win for the local human ("VICTORY", gold).
func show_victory() -> void:
	show_result(OUTCOME_VICTORY, "VICTORY", "All enemies defeated!")


## Reveal a loss for the local human ("DEFEAT", red).
func show_defeat() -> void:
	show_result(OUTCOME_DEFEAT, "DEFEAT", "Your forces have fallen.")


## Reveal the end screen with an explicit banner. Idempotent -- the first call
## wins and later calls are ignored, so repeated elimination signals never
## restack the animation. Pauses gameplay while the (pause-immune) reveal runs.
##
## ARENA: returns without showing anything when this battle was an arena round (see
## [method _arena_suppressed]). The arena run's own results screen is arena's summary.
func show_result(outcome: StringName, title: String, subtitle: String) -> void:
	if _shown:
		return
	if _arena_suppressed():
		return
	_shown = true

	_banner_label.text = title
	# A forfeit / disconnect win is NOT "all enemies defeated" -- say what actually happened.
	_subtitle_label.text = SUBTITLE_FORFEIT if _opponent_forfeited else subtitle

	var accent: Color = VICTORY_GOLD if outcome == OUTCOME_VICTORY else DEFEAT_RED
	_banner_label.add_theme_color_override("font_color", accent)

	_populate_summary()

	visible = true

	# Freeze gameplay. Safe because this node is PROCESS_MODE_ALWAYS and the reveal
	# tween is TWEEN_PAUSE_PROCESS, so the screen keeps animating and its buttons
	# keep working while the tree is paused.
	get_tree().paused = true

	_play_reveal_animation()
	_play_sting(outcome)

	# Give the primary action keyboard/controller focus.
	_rematch_button.grab_focus()


## PURE decision helper: does the post-match summary carry a VERSUS block?
##
## [param ctx] keys (all optional, all defaulting to "no"):
##   "networked" : bool -- was this battle a live networked match at BATTLE START
##   "arena"     : bool -- was this battle an arena round
##
## Static and side-effect free so the rule is testable without a scene, an autoload or a
## socket. The versus block is the networked-match block and nothing else: a hotseat or
## versus-on-one-box match has no remote opponent to report, and an arena round never
## reaches this screen at all (belt and braces -- see [method _arena_suppressed]).
static func should_show_versus_block(ctx: Dictionary) -> bool:
	if bool(ctx.get("arena", false)):
		return false
	return bool(ctx.get("networked", false))


# --- Reveal animation --------------------------------------------------------

func _recenter_pivot() -> void:
	if _card != null:
		_card.pivot_offset = _card.size / 2.0


func _play_reveal_animation() -> void:
	_recenter_pivot()

	# Defensive: show_result is idempotent so there is normally no prior tween.
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()

	# Initial hidden pose: dim backdrop, small/transparent card lifted slightly,
	# invisible buttons.
	_backdrop.modulate.a = 0.0
	_card.modulate.a = 0.0
	_card.scale = Vector2(REVEAL_SCALE_FROM, REVEAL_SCALE_FROM)
	var rest_y: float = _card.position.y
	_card.position.y = rest_y - REVEAL_SLIDE_PX
	for child in _button_box.get_children():
		var ctl := child as Control
		if ctl != null:
			ctl.modulate.a = 0.0

	_reveal_tween = create_tween()
	# Keep animating while gameplay is paused (see show_result).
	_reveal_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_reveal_tween.set_parallel(true)

	# Backdrop dims in.
	_reveal_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.28) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Card pops: scale overshoot (TRANS_BACK) + fade + gentle slide down to rest.
	_reveal_tween.tween_property(_card, "modulate:a", 1.0, 0.26) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_reveal_summary_card()
	_reveal_tween.tween_property(_card, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(_card, "position:y", rest_y, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Buttons fade in staggered after the card has mostly landed. Total reveal
	# stays under ~0.75s so it reads snappy (reduced-motion friendly).
	var delay: float = 0.30
	for child in _button_box.get_children():
		var ctl := child as Control
		if ctl == null:
			continue
		_reveal_tween.tween_property(ctl, "modulate:a", 1.0, 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(delay)
		delay += 0.08


## The summary card's own entrance, gated on [member GameSettings.animations_enabled]
## (see [method _animations_on]). Animations ON: fades in once the card has mostly
## landed, just ahead of the button stagger. Animations OFF: snaps straight to fully
## visible with NO tween ever created for it -- the rule every animating system in
## this codebase follows (see e.g. [ItemToast._animations_on]).
func _reveal_summary_card() -> void:
	if _summary_card == null:
		return
	if not _animations_on():
		_summary_card.modulate.a = 1.0
		return
	_summary_card.modulate.a = 0.0
	_reveal_tween.tween_property(_summary_card, "modulate:a", 1.0, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.26)


## True when the player has animations enabled (defaults to on when GameSettings is
## absent, e.g. a bare test harness) -- mirrors [method ItemToast._animations_on].
func _animations_on() -> bool:
	if typeof(GameSettings) != TYPE_OBJECT or GameSettings == null:
		return true
	if not GameSettings.has_method("animations_on"):
		return true
	return bool(GameSettings.animations_on())


func _play_sting(outcome: StringName) -> void:
	# Optional audio: play a victory/defeat sting if AudioManager exposes play_sfx.
	# Unknown/unassigned events no-op inside the manager, so this is always safe.
	var audio = _autoload("AudioManager")   # untyped on purpose -- see _challenge_result
	if audio == null or not audio.has_method("play_sfx"):
		return
	var event_name: StringName = &"sfx_victory" if outcome == OUTCOME_VICTORY else &"sfx_defeat"
	audio.play_sfx(event_name)


# --- Button handlers ---------------------------------------------------------
# Every handler unpauses the tree first: get_tree().paused persists across a
# scene change, so leaving it true would freeze the reloaded battle / the menu.

func _on_rematch_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


# --- Input --------------------------------------------------------------------

## ESC goes to the Main Menu while the screen is shown. Enter/Space already
## "press" the focused Rematch button through Godot's own ui_accept handling on a
## focused Button (see show_result -> grab_focus), so nothing else is needed for
## that. Mirrors UILayoutManager's ui_cancel handling: consume the event so it
## cannot also fall through to a board handler underneath (harmless here since
## gameplay is paused, but consuming it is the established pattern).
func _unhandled_input(event: InputEvent) -> void:
	if not _shown or not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_main_menu_pressed()


# =====================================================================================
#  RESULTS DATA
# =====================================================================================

## Fill every section from the latched tallies + battle-start latches.
## Safe to call more than once (show_result already guards re-entry via _shown).
func _populate_summary() -> void:
	if _rounds_value != null:
		_rounds_value.text = str(_rounds_taken())
	if _lost_value != null:
		_lost_value.text = str(_friendlies_lost)
	if _defeated_value != null:
		_defeated_value.text = str(_enemies_defeated)
	if _dealt_value != null:
		_dealt_value.text = str(_damage_dealt)
	if _taken_value != null:
		_taken_value.text = str(_damage_taken)

	_populate_lost_rows()
	_populate_defeated_names()
	_populate_rewards()
	_populate_versus()


## One row per fallen human unit (portrait when PortraitCache already holds one, monogram
## otherwise), capped at [constant MAX_LOST_ROWS] with a "+N more" tail.
func _populate_lost_rows() -> void:
	if _lost_rows_box == null:
		return
	for child in _lost_rows_box.get_children():
		child.queue_free()

	if _lost_units.is_empty():
		_lost_rows_box.visible = false
		return
	_lost_rows_box.visible = true

	var shown: int = mini(_lost_units.size(), MAX_LOST_ROWS)
	for i in range(shown):
		_lost_rows_box.add_child(_build_lost_row(_lost_units[i]))

	var remaining: int = _lost_units.size() - shown
	if remaining > 0:
		# Built inline, NOT through _caption_label: that helper registers the label for the
		# one-time post-apply_to colour pass, and a runtime row would leave a freed pointer
		# in that array. Runtime rows colour themselves.
		var more := Label.new()
		more.text = "+%d more" % remaining
		more.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		more.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
		_lost_rows_box.add_child(more)


## One casualty row: a portrait/monogram badge and the unit's display name.
##
## PORTRAIT: only [method PortraitCache.get_cached] is consulted -- never get_portrait().
## An async capture started here would land after the reveal (and, in a paused tree, after
## the player has already moved on), so the summary shows whatever the battle HUD already
## warmed and falls back to the element-style monogram badge otherwise. Same null-safe
## cached-first pattern as TurnQueue / UnitInfoPanel.
func _build_lost_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var unit_name: String = String(entry.get("name", "Unknown Unit"))
	var character_id: String = String(entry.get("character_id", ""))

	var portrait: Texture2D = null
	if not character_id.is_empty():
		portrait = PortraitCache.get_cached(character_id)

	if portrait != null:
		var tex := TextureRect.new()
		tex.texture = portrait
		tex.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.clip_contents = true
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tex)
	else:
		var mono := Label.new()
		mono.text = unit_name.substr(0, 1).to_upper() if not unit_name.is_empty() else "?"
		mono.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
		mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mono.add_theme_font_size_override("font_size", 13)
		mono.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
		row.add_child(mono)

	var label := Label.new()
	label.text = unit_name
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	return row


## The enemy roll-call, as one wrapped comma-separated caption ("Defeated: Blightcap,
## Mycothrall, ..."). Names repeat when two of the same character fell -- that is the
## honest report, not a bug.
func _populate_defeated_names() -> void:
	if _defeated_names_label == null:
		return
	if _defeated_units.is_empty():
		_defeated_names_label.visible = false
		_defeated_names_label.text = ""
		return
	var names: Array[String] = []
	for entry in _defeated_units:
		names.append(String(entry.get("name", "Unknown Unit")))
	_defeated_names_label.text = "Defeated: %s" % ", ".join(names)
	_defeated_names_label.visible = true


func _populate_rewards() -> void:
	if _gained_value != null:
		_gained_value.text = "+%d" % points_gained()
	if _balance_value != null:
		_balance_value.text = str(_points_balance())

	_populate_drop_rows()

	if _challenge_row == null:
		return
	var result: Dictionary = _challenge_result()
	if result.is_empty():
		_challenge_row.visible = false
		return
	_challenge_row.visible = true
	if _challenge_value != null:
		_challenge_value.text = str(int(result.get("score", 0)))
	if _perfect_badge != null:
		_perfect_badge.visible = bool(result.get("perfect", false))


## The LOOT the battle just paid out: one chip row per item, capped at
## [constant MAX_DROP_ROWS] with the same "+N more" tail the casualty rows use.
##
## SILENT ON ZERO. Most battles drop nothing (the odds are ~65% nothing), so an empty latch
## renders no heading, no placeholder and no row -- the block simply is not there. "Nothing
## dropped" is not news; printing it every match would make the one match that DID pay out
## harder to spot, not easier.
##
## The latch is [method ItemSystem.drops_this_battle] -- ids only, because the summary reads
## it after the grant has already been persisted and an id is what survives. Names and
## glyphs are resolved through [ItemLibrary], the same lookup the loadout screen's team chips
## use, so an item reads identically wherever it appears.
func _populate_drop_rows() -> void:
	if _drop_rows_box == null:
		return
	for child in _drop_rows_box.get_children():
		child.queue_free()

	var drops: Array[String] = _drops_this_battle()
	if drops.is_empty():
		_drop_rows_box.visible = false
		return
	_drop_rows_box.visible = true

	# Built inline rather than through _section_header / _caption_label: those helpers
	# register the label for the ONE-TIME post-apply_to colour pass, and a runtime row would
	# leave a freed pointer in those arrays. Runtime rows colour themselves.
	var heading := Label.new()
	heading.name = "DropsHeading"
	heading.text = "ITEMS FOUND"
	heading.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	heading.add_theme_color_override("font_color", ConquestTheme.EL_HOLY)
	_drop_rows_box.add_child(heading)

	var shown: int = mini(drops.size(), MAX_DROP_ROWS)
	for i in range(shown):
		_drop_rows_box.add_child(_build_drop_row(drops[i]))

	var remaining: int = drops.size() - shown
	if remaining > 0:
		var more := Label.new()
		more.text = "+%d more" % remaining
		more.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		more.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
		_drop_rows_box.add_child(more)


## One drop row: the item's glyph badge and its display name, in the
## "[icon_hint] [display_name]" vocabulary the loadout screen's item chips already use
## ([code]CharacterSelect._refresh_team_chips[/code]).
##
## An id [ItemLibrary] cannot resolve (a shipped item later removed from the content dir)
## is still LISTED, under its raw id and the default glyph. The player earned it and it is
## in their inventory; hiding the row would under-report a real reward, and inventing a name
## for it would be worse.
func _build_drop_row(item_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var item: ItemResource = ItemLibrary.get_item(item_id)
	var glyph: String = "*"
	var label_text: String = item_id
	if item != null:
		label_text = item.display_name
		if not item.icon_hint.strip_edges().is_empty():
			glyph = item.icon_hint

	var badge := Label.new()
	badge.text = glyph
	badge.custom_minimum_size = Vector2(PORTRAIT_PX, 0.0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	badge.add_theme_color_override("font_color", ConquestTheme.EL_HOLY)
	row.add_child(badge)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	return row


## What dropped this battle, from [ItemSystem]'s per-battle latch.
##
## Unguarded, unlike this screen's autoload reads: the latch is STATIC state on a class this
## script already links against, so there is no tree, no autoload and no live battle for it
## to be missing from. A bare harness reads an empty latch, which is the correct answer.
func _drops_this_battle() -> Array[String]:
	return ItemSystem.drops_this_battle()


## The VERSUS block: the opponent's card (name, rank chip, their lifetime points) and YOUR
## rank progress, before -> after, over the points this match earned.
func _populate_versus() -> void:
	if _versus_box == null:
		return
	if not should_show_versus_block(versus_context()):
		_versus_box.visible = false
		return
	_versus_box.visible = true

	var peer: Dictionary = _opponent_info()
	var peer_name: String = String(peer.get("name", "")).strip_edges()
	if _opponent_name_label != null:
		_opponent_name_label.text = peer_name if not peer_name.is_empty() else MatchPeerInfo.DEFAULT_NAME

	var rank_name: String = String(peer.get("rank_name", "")).strip_edges()
	if _rank_chip != null:
		_rank_chip.text = rank_name.to_upper()
		# No chip at all rather than an empty gold box when the peer's build predates the
		# profile_info exchange (or it never arrived).
		_rank_chip.visible = not rank_name.is_empty()

	if _opponent_points_label != null:
		if peer.has("lifetime_points"):
			_opponent_points_label.text = "%d lifetime pts" % int(peer.get("lifetime_points", 0))
			_opponent_points_label.visible = true
		else:
			_opponent_points_label.text = ""
			_opponent_points_label.visible = false

	# YOUR side of the block: rank progress before -> after this match's earnings.
	var after_total: int = _points_total()
	var before_total: int = _start_points_total
	if _rank_bar != null:
		_rank_bar.value = RankLadder.progress_in_rank(after_total)
	if _rank_caption != null:
		_rank_caption.text = _rank_progress_caption(before_total, after_total)


## The "you earned N, here is where that leaves you" line under the rank bar. Calls out a
## rank-UP explicitly when this match crossed a tier threshold.
func _rank_progress_caption(before_total: int, after_total: int) -> String:
	var gained: int = maxi(0, after_total - before_total)
	var rank_now: String = RankLadder.rank_for(after_total)
	if RankLadder.rank_index(after_total) > RankLadder.rank_index(before_total):
		return "+%d pts  •  RANK UP: %s" % [gained, rank_now]
	var to_next: int = RankLadder.points_to_next(after_total)
	if RankLadder.next_threshold(after_total) < 0:
		return "+%d pts  •  %s (top rank)" % [gained, rank_now]
	return "+%d pts  •  %s  •  %d to next rank" % [gained, rank_now, to_next]


## Rounds taken so far, read off the ACTIVE turn system (both TraditionalTurnSystem
## and SpeedFirstTurnSystem keep TurnSystemBase.current_turn in sync with their own
## round counter -- see each system's advance_turn -- so this one field covers
## either mode). Null-safe: 0 before any system has activated (also covers a bare
## test harness with no live battle).
func _rounds_taken() -> int:
	if typeof(TurnSystemManager) != TYPE_OBJECT or TurnSystemManager == null:
		return 0
	var active: TurnSystemBase = TurnSystemManager.active_turn_system
	if active == null:
		return 0
	return int(active.current_turn)


## The player's current spendable balance (PlayerProfile.get_points()). REAL data --
## PlayerProfile grants a battle's win points off PlayerManager.player_eliminated
## before this screen's own reveal runs (that autoload connects in its _ready, this
## screen's host connects during battle scene setup, so the grant lands first). Note
## for future work: that grant only fires on a player-eliminated win; a map-objective
## win (e.g. "defeat the boss" while grunts remain) does not eliminate a player and so
## is not yet paid -- a PlayerProfile-side gap, out of scope here. Null-safe: 0 when
## the autoload or the method is unexpectedly missing.
func _points_balance() -> int:
	if typeof(PlayerProfile) != TYPE_OBJECT or PlayerProfile == null:
		return 0
	if not PlayerProfile.has_method("get_points"):
		return 0
	return int(PlayerProfile.get_points())


## LIFETIME points earned. Deliberately not the spendable balance: buying a skin mid-session
## must never make a match look like it cost points, and the rank ladder is derived from the
## lifetime figure too (see [RankLadder]). Null-safe (0) in a bare harness.
func _points_total() -> int:
	if typeof(PlayerProfile) != TYPE_OBJECT or PlayerProfile == null:
		return 0
	if not PlayerProfile.has_method("get_points_total"):
		return 0
	return int(PlayerProfile.get_points_total())


## Points THIS match earned, as a diff against the lifetime total latched at battle start.
##
## HONESTY NOTE: PlayerProfile exposes no "what did the last battle pay" accessor, so a
## before/after diff is the only real read available -- and it is a faithful one, because
## lifetime points only ever go UP (a spend moves points_spent, not points_total). Clamped
## at 0 so an unexpected profile reset can never render as a negative reward.
func points_gained() -> int:
	return maxi(0, _points_total() - _start_points_total)


## The challenge score + perfect flag for the run that JUST finished, or {} when there is
## none to show.
##
## ChallengeController still has no "here is the armed result" accessor, so this is
## assembled from what IS public: is_capturing() proves a challenge battle is live,
## active_challenge() names it, result_for(id) reads the persisted record, and
## capture_counters() gives the live turn count. The FRESHNESS CHECK is that last pair --
## the record is only trusted when its last_turns equals the live tally, which is what
## distinguishes "this attempt was just recorded" from "an older attempt is still on disk"
## (a map-objective win that eliminates no player never reaches _record_result at all).
## Everything is has_method-guarded, so a harness without the autoload gets {}.
func _challenge_result() -> Dictionary:
	# Deliberately UNTYPED (`var x =`, not `:=`): a statically-typed Node would make the
	# static analyser reject every has_method-guarded call below as "not found in base Node".
	# Same reason PlayerProfile._detect_live_mode / GameWorldManager keep their arena probe
	# untyped.
	var controller = _autoload("ChallengeController")
	if controller == null:
		return {}
	if not (controller.has_method("is_capturing") and controller.has_method("active_challenge") \
			and controller.has_method("result_for") and controller.has_method("capture_counters")):
		return {}
	if not bool(controller.is_capturing()):
		return {}

	var challenge: Dictionary = controller.active_challenge()
	var id: String = ChallengeCodec.challenge_id(challenge)
	if id.is_empty():
		return {}

	var record: Dictionary = controller.result_for(id)
	if record.is_empty():
		return {}

	var counters: Dictionary = controller.capture_counters()
	if int(record.get("last_turns", -1)) != int(counters.get("turns", -2)):
		return {}   # stale record from an earlier attempt -- do not pass it off as this one

	return {
		"score": int(record.get("last_score", 0)),
		"perfect": bool(record.get("last_perfect", false)),
	}


## The context [method should_show_versus_block] scores, built from the BATTLE-START latches
## (never a live query -- see the latch block's comment).
func versus_context() -> Dictionary:
	return { "networked": _was_networked_match, "arena": _arena_run_at_start }


## The opponent's announced profile card, or {} when none arrived. Prefers the card recorded
## for a slot other than ours; falls back to NetSession's own roster name so a peer on an
## older build (no profile_info) still gets a named row rather than a blank one.
func _opponent_info() -> Dictionary:
	var peer: Dictionary = MatchPeerInfo.get_any_peer_info(_local_slot)
	if not peer.is_empty():
		return peer
	return _roster_fallback_info()


## Name-only card derived from NetSession's roster (which the SERVER owns), for a peer that
## never sent a profile_info. Returns {} when there is no roster to read.
func _roster_fallback_info() -> Dictionary:
	if typeof(NetSession) != TYPE_OBJECT or NetSession == null:
		return {}
	if not NetSession.has_method("get_roster"):
		return {}
	var roster: Dictionary = NetSession.get_roster()
	for peer_id in roster:
		var entry: Variant = roster[peer_id]
		if not (entry is Dictionary):
			continue
		if int((entry as Dictionary).get("slot", -1)) == _local_slot:
			continue
		return { "name": String((entry as Dictionary).get("name", MatchPeerInfo.DEFAULT_NAME)) }
	return {}


# =====================================================================================
#  BATTLE-START LATCHES
# =====================================================================================

## Sample everything that is only knowable while the battle is STARTING:
##   * the lifetime points total, so the reward diff has a "before" to subtract
##   * whether this is a live networked match, and which slot we hold -- by the time the
##     match ends the opponent may have left, at which point is_networked_match() flips to
##     false and local_slot() to -1, and the versus block would silently vanish exactly in
##     the case (a forfeit win) where it matters most
##   * whether an ARENA run owns this battle, which is the suppression rule below
## Every read is null-/has_method-guarded so a bare harness latches zeros rather than erroring.
func _latch_battle_start() -> void:
	_start_points_total = _points_total()

	_was_networked_match = false
	_local_slot = -1
	if typeof(NetSession) == TYPE_OBJECT and NetSession != null:
		if NetSession.has_method("is_networked_match"):
			_was_networked_match = bool(NetSession.is_networked_match())
		if NetSession.has_method("local_slot"):
			_local_slot = int(NetSession.local_slot())

	_arena_run_at_start = false
	var arena = _autoload("ArenaController")   # untyped on purpose -- see _challenge_result
	if arena != null and arena.has_method("is_active"):
		_arena_run_at_start = bool(arena.is_active())


## An autoload by name, or null when this node is not (yet) in a tree -- an absolute
## get_node() path is only resolvable from inside one, and this screen is constructed
## bare in its unit suite. Mirrors the get_node_or_null("/root/...") probe the rest of
## this file (and PlayerProfile._detect_live_mode) uses, with the out-of-tree case made
## explicit rather than relying on it.
func _autoload(autoload_name: String) -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/%s" % autoload_name)


## The initial (non-runtime) spawn pass is the exact moment a battle starts -- the same
## signal PlayerProfile resets its per-battle latches on. Re-latch once there; _ready's
## earlier seeding stays as the fallback for a battle that never emits this pass.
func _on_unit_spawned_latch(_unit, runtime: bool) -> void:
	if runtime or _spawn_latched:
		return
	_spawn_latched = true
	_latch_battle_start()


## ARENA SUPPRESSION, the defensive half. GameWorldManager is the primary gate: it routes an
## arena battle-end into ArenaController.notify_round_ended and RETURNS, never calling this
## screen (see its _evaluate_game_end). This latch is the belt to that braces -- an arena
## round's summary is the run's ArenaResultsScreen, shown once at RUN end, and a mid-run
## VICTORY/DEFEAT card would both spoil the loop and pause a tree that is about to change
## scene. Reads the BATTLE-START latch rather than a live query, because ArenaController
## stays in its FINISHED phase (is_active() still true) right through the last round's
## teardown.
func _arena_suppressed() -> bool:
	return _arena_run_at_start


# =====================================================================================
#  RESULTS TALLY
# =====================================================================================

## Subscribe to the battle-long GameEvents this screen tallies (eliminations, damage, the
## initial spawn pass) for the WHOLE battle -- this screen is mounted hidden from battle
## start, so the tally is built from events as they happen rather than reconstructed at
## reveal time. Every connect is guarded so a second _ready (should never happen for a
## scene-instantiated node, but mirrors every other GameEvents subscriber in this codebase)
## can never double-connect.
func _connect_tally() -> void:
	if typeof(GameEvents) != TYPE_OBJECT or GameEvents == null:
		return
	if GameEvents.has_signal("unit_eliminated") \
			and not GameEvents.unit_eliminated.is_connected(_on_unit_eliminated_tally):
		GameEvents.unit_eliminated.connect(_on_unit_eliminated_tally)
	if GameEvents.has_signal("damage_dealt") \
			and not GameEvents.damage_dealt.is_connected(_on_damage_dealt_tally):
		GameEvents.damage_dealt.connect(_on_damage_dealt_tally)
	if GameEvents.has_signal("unit_spawned") \
			and not GameEvents.unit_spawned.is_connected(_on_unit_spawned_latch):
		GameEvents.unit_spawned.connect(_on_unit_spawned_latch)


## Subscribe to the session-level "the opponent is gone" signals. Both are has_signal-guarded
## because they are newer than some of this screen's callers; a build without them simply
## never sets the forfeit subtitle.
func _connect_session_signals() -> void:
	if typeof(NetSession) != TYPE_OBJECT or NetSession == null:
		return
	if NetSession.has_signal("opponent_forfeited") \
			and not NetSession.opponent_forfeited.is_connected(_on_opponent_forfeited):
		NetSession.opponent_forfeited.connect(_on_opponent_forfeited)
	if NetSession.has_signal("opponent_left") \
			and not NetSession.opponent_left.is_connected(_on_opponent_left):
		NetSession.opponent_left.connect(_on_opponent_left)


func _on_opponent_forfeited(_slot: int) -> void:
	_opponent_forfeited = true


## A peer vanishing from a live match is a loss for them exactly like a forfeit (see
## NetSession.opponent_left), so it reads the same on the summary.
func _on_opponent_left() -> void:
	_opponent_forfeited = true


## Tally one elimination. FREED-SAFE: everything this needs (the owner's player_id /
## is_neutral, the unit's display name and character id) is read out of the live objects
## right here, in the same call the signal handed them to us in -- nothing is stored but
## plain ints and Strings, so a unit or Player freed later can never be touched through a
## stale reference.
##
## Side is determined by the dying unit's owner: player_id == 0 is the human, every
## other id is an enemy. A neutral owner (a dormant wild camp) counts toward
## NEITHER tally, mirroring PlayerProfile._on_unit_eliminated and
## ChallengeController's own neutral guards elsewhere in this file's siblings.
##
## Idempotent per unit via [member _counted_unit_ids] (an instance-id latch): the
## same elimination signal firing twice for one unit (unit.gd's own _is_dead guard
## should prevent that in production, but a mocked/duplicated event in a test, or a
## future call site, must not double-count) tallies once.
func _on_unit_eliminated_tally(unit, _eliminator) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var uid: int = unit.get_instance_id()
	if _counted_unit_ids.has(uid):
		return

	var owner = null
	if unit.has_method("get_owner_player"):
		owner = unit.get_owner_player()
	elif "owner_player" in unit:
		owner = unit.owner_player
	if owner == null or not ("player_id" in owner):
		return
	if "is_neutral" in owner and bool(owner.is_neutral):
		return

	_counted_unit_ids[uid] = true
	var entry: Dictionary = _identify_unit(unit)
	if int(owner.player_id) == 0:
		_friendlies_lost += 1
		_lost_units.append(entry)
	else:
		_enemies_defeated += 1
		_defeated_units.append(entry)


## The two plain-String facts the summary needs about a fallen unit: what to CALL it and
## which character's portrait to look up. Both are read defensively -- get_display_name()
## is Unit's accessor but a duck-typed double may only carry a field, and character_id
## lives on the unit's CharacterResource (Unit.get_unit_type() mirrors it for units built
## from a character, which is the case for every roster unit).
func _identify_unit(unit) -> Dictionary:
	var unit_name: String = "Unknown Unit"
	if unit.has_method("get_display_name"):
		unit_name = String(unit.get_display_name())
	elif "unit_name" in unit:
		unit_name = String(unit.unit_name)

	var character_id: String = ""
	if "character_resource" in unit and unit.character_resource != null \
			and "character_id" in unit.character_resource:
		character_id = String(unit.character_resource.character_id)
	elif unit.has_method("get_unit_type"):
		character_id = String(unit.get_unit_type())

	return { "name": unit_name, "character_id": character_id }


## Tally one damage event onto the human's dealt/taken lines.
##
## The payload -- (attacker, defender, damage) -- makes the SIDES unambiguous: both ends are
## units with an owning Player, so "player 0 swung it" is dealt and "player 0 wore it" is
## taken. ONE honest caveat: a friendly-fire hit (a line attack clipping your own unit)
## counts on BOTH lines, because it genuinely is both damage you dealt and damage you took.
## A neutral-owned unit is excluded from both, mirroring the elimination tally.
func _on_damage_dealt_tally(attacker, defender, damage: int) -> void:
	if damage <= 0:
		return
	if _is_human_owned(attacker):
		_damage_dealt += damage
	if _is_human_owned(defender):
		_damage_taken += damage


## True when [param unit] is alive, valid, and owned by the human (player_id 0, not neutral).
func _is_human_owned(unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var owner = null
	if unit.has_method("get_owner_player"):
		owner = unit.get_owner_player()
	elif "owner_player" in unit:
		owner = unit.owner_player
	if owner == null or not ("player_id" in owner):
		return false
	if "is_neutral" in owner and bool(owner.is_neutral):
		return false
	return int(owner.player_id) == 0
