extends Node

## The player's persistent PROGRESSION record -- points, derived rank, unlocked achievements,
## lifetime stats, and owned/equipped cosmetic skins -- saved to user://profile.json and kept
## across every scene change. Registered as an autoload (like ArenaController / CampaignController)
## so it survives scene reloads and can quietly earn points off the same battle signals the
## controllers already trust, WITHOUT editing GameWorldManager, MapLoader or any controller.
##
## EARNING -- what is live now vs. what waits on a hook:
##   * LIVE: it listens to PlayerManager.player_eliminated and re-derives a human win/loss the
##     exact way GameWorldManager does (no enemy left => win; no human left => loss), granting
##     a flat win amount ONCE per battle. It reads ArenaController.is_active() to award the
##     arena round rate; every other live win is scored as a generic skirmish win. It also
##     tallies units defeated + friendly losses off GameEvents.unit_eliminated.
##   * HOOK (for a later pass -- the mode controllers are READ-ONLY for this work): precise
##     mode-specific awards (campaign first-clear 150, arena run clear, challenge score/10,
##     "perfect" runs) come through [method notify_mode_win] / [method notify_battle_result],
##     which the controllers can call once wired. Calling a hook latches the battle so the
##     generic auto-detector never double-grants. [method notify_map_saved] is the map-editor hook.
##
## Achievements are evaluated RETROACTIVELY on load (reading campaign.json, the challenge
## results file, user://maps and owned skins) so deeds done before this system shipped still
## unlock, and again on every relevant event. An unlock fires [signal achievement_unlocked]
## and a bottom-centre toast (mounted on this autoload's own CanvasLayer, so it shows in any
## scene; skipped on headless).
##
## The skins economy (a parallel agent) codes against the public points/skin API below -- the
## method names + signatures here are a fixed contract; do not rename them.

signal points_changed(balance: int)
signal achievement_unlocked(id: String)

const DEFAULT_PROFILE_PATH := "user://profile.json"
const TOAST_SCRIPT := "res://game/profile/AchievementToast.gd"

# External data the retroactive achievement sweep reads (result-file formats owned by the
# campaign / challenge controllers -- read-only here).
const CAMPAIGN_PROGRESS_PATH := "user://campaign.json"
const CHALLENGE_RESULTS_PATH := "user://challenges/results.json"
const CUSTOM_MAPS_DIR := "user://maps/"

# --- Point awards by mode ---------------------------------------------------
# Skirmish is the generic live default; arena is per-round; campaign/challenge come through
# the hook methods with precise amounts (campaign first-clear, challenge = score / 10).
const POINTS_SKIRMISH_WIN := 50
const POINTS_ARENA_ROUND := 30
const POINTS_CAMPAIGN_CHAPTER := 150

var _path: String = DEFAULT_PROFILE_PATH

# Where the RETROACTIVE sweep reads its outside evidence from. Defaults to the real files
# above; tests redirect them with [method set_source_paths] so a sweep never reads (or is
# polluted by) the player's actual campaign / challenge / map data.
var _campaign_path: String = CAMPAIGN_PROGRESS_PATH
var _challenge_path: String = CHALLENGE_RESULTS_PATH
var _maps_dir: String = CUSTOM_MAPS_DIR

# The whole persisted record. Kept as a Dictionary so save/load is a straight JSON round-trip.
var _data: Dictionary = {}

# Per-battle latches, reset when a new battle's units spawn (GameEvents.unit_spawned, initial
# load pass). _battle_decided stops a win/loss recording twice; _friendly_losses feeds the
# "perfect" notion a challenge hook can consult.
var _battle_decided: bool = false
var _friendly_losses_this_battle: int = 0

var _toast: CanvasLayer = null

# Debounced save bookkeeping.
var _save_pending: bool = false


func _ready() -> void:
	name = "PlayerProfile"
	# Outlive scene changes + the pause the end screen applies (mirrors the controllers).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_connect_signals()
	_mount_toast()
	# Retroactive sweep: unlock anything already earned (silently on the very first load is
	# fine -- toasts still fire, which is a nice "here's what you've done" welcome).
	_evaluate_achievements()


# =====================================================================================
#  PUBLIC POINTS + SKIN API  (fixed contract -- the skins economy codes against these)
# =====================================================================================

## Spendable balance: everything earned minus everything spent. Never negative.
func get_points() -> int:
	return maxi(0, _points_total() - _points_spent())


## Lifetime points earned (drives the rank ladder; never decreases on a spend).
func get_points_total() -> int:
	return _points_total()


## Add [param amount] earned points (no-op for <= 0). [param source] is a short tag for
## debugging / future analytics. Emits [signal points_changed] and re-checks achievements.
func grant_points(amount: int, source: String) -> void:
	if amount <= 0:
		return
	_data["points_total"] = _points_total() + amount
	_schedule_save()
	points_changed.emit(get_points())
	_evaluate_achievements()


## Try to spend [param amount] points. Returns false (changing nothing) when the balance is
## insufficient or the amount is not positive; the balance can never go negative. [param reason]
## is a short tag (e.g. a skin id) for debugging.
func spend_points(amount: int, reason: String) -> bool:
	if amount <= 0:
		return false
	if get_points() < amount:
		return false
	_data["points_spent"] = _points_spent() + amount
	_schedule_save()
	points_changed.emit(get_points())
	return true


func owns_skin(skin_id: String) -> bool:
	return skin_id in _owned_skins()


## Grant ownership of [param skin_id] (idempotent). Re-checks the collector achievement.
func add_skin(skin_id: String) -> void:
	if skin_id.is_empty():
		return
	var owned: Array = _owned_skins()
	if skin_id in owned:
		return
	owned.append(skin_id)
	_data["owned_skins"] = owned
	_schedule_save()
	_evaluate_achievements()


## Equip [param skin_id] on [param character_id]. Pass "" to clear back to the default look.
func equip_skin(character_id: String, skin_id: String) -> void:
	if character_id.is_empty():
		return
	var equipped: Dictionary = _equipped_skins()
	if skin_id.is_empty():
		equipped.erase(character_id)
	else:
		equipped[character_id] = skin_id
	_data["equipped_skins"] = equipped
	_schedule_save()


## The skin equipped on [param character_id], or "" (the default) when none.
func get_equipped_skin(character_id: String) -> String:
	return String(_equipped_skins().get(character_id, ""))


## A copy of the owned-skin id list (mutating it does not touch the profile).
func get_owned_skins() -> Array:
	return _owned_skins().duplicate()


# =====================================================================================
#  RANK + STAT READ HELPERS  (used by the profile screen)
# =====================================================================================

func get_rank_name() -> String:
	return RankLadder.rank_for(_points_total())


func get_rank_progress() -> float:
	return RankLadder.progress_in_rank(_points_total())


## The record for one stat key (0 when unset). See [method _default_data] for the keys.
func get_stat(key: String) -> int:
	return int(_stats().get(key, 0))


## True when achievement [param id] has been unlocked.
func has_achievement(id: String) -> bool:
	return _achievements().has(id)


## The ISO timestamp an achievement was unlocked, or "" when still locked.
func achievement_date(id: String) -> String:
	return String(_achievements().get(id, ""))


func unlocked_achievement_count() -> int:
	return _achievements().size()


# =====================================================================================
#  EARNING -- live battle signals
# =====================================================================================

func _connect_signals() -> void:
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null:
		if GameEvents.has_signal("unit_eliminated"):
			GameEvents.unit_eliminated.connect(_on_unit_eliminated)
		if GameEvents.has_signal("unit_spawned"):
			GameEvents.unit_spawned.connect(_on_unit_spawned)
	if PlayerManager != null and PlayerManager.has_signal("player_eliminated"):
		PlayerManager.player_eliminated.connect(_on_player_eliminated)


## A fresh battle is loading (initial, non-runtime spawn pass): clear the per-battle latches
## so this battle's win/loss records once and its friendly-loss tally starts clean.
func _on_unit_spawned(_unit, runtime: bool) -> void:
	if runtime:
		return
	begin_battle()


## Tally units for the lifetime stats: an AI-owned unit falling counts toward units_defeated
## (a proxy for "the player's kills"); a human-owned unit falling counts as a friendly loss
## for the current battle (a challenge "perfect" hook can consult it).
func _on_unit_eliminated(unit, _eliminator) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	# NOT named "owner" -- that would shadow Node.owner on this autoload.
	var unit_owner: Variant = null
	if "owner_player" in unit:
		unit_owner = unit.owner_player
	if unit_owner == null:
		return
	var is_ai: bool = "is_ai" in unit_owner and bool(unit_owner.is_ai)
	var is_neutral: bool = "is_neutral" in unit_owner and bool(unit_owner.is_neutral)
	if is_neutral:
		return
	if is_ai:
		_stats()["units_defeated"] = get_stat("units_defeated") + 1
		_schedule_save()
		_evaluate_achievements()
	else:
		_friendly_losses_this_battle += 1


## A player was wiped: decide the battle the same way GameWorldManager does and, once per
## battle, record the human's win or loss (and, on a win, grant points by detected mode).
func _on_player_eliminated(_player) -> void:
	if _battle_decided:
		return
	if PlayerManager == null:
		return

	var human_alive: bool = false
	var enemy_alive: bool = false
	for ap in PlayerManager.players:
		if ap == null or not ap.has_units_remaining():
			continue
		if "is_neutral" in ap and bool(ap.is_neutral):
			continue
		if "is_ai" in ap and bool(ap.is_ai):
			enemy_alive = true
		else:
			human_alive = true

	if not enemy_alive:
		_record_battle_win(_detect_live_mode(), {})
	elif not human_alive:
		_record_battle_loss(_detect_live_mode())


## Which mode a live win belongs to, using only public autoload state. Arena rounds are the
## one mode we can positively identify (ArenaController.is_active()); campaign + challenge
## battles are scored generically as skirmish for now and get precise awards once their
## controllers call [method notify_mode_win].
func _detect_live_mode() -> String:
	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("is_active") and arena.is_active():
		return "arena"
	return "skirmish"


# =====================================================================================
#  EARNING -- hook methods for the mode controllers (later pass; do not call from here)
# =====================================================================================

## Precise per-mode win award, for a controller to call the moment it confirms a win. Latches
## the battle so the generic auto-detector will not also grant. [param meta] carries mode
## extras: campaign {first_clear:bool, chapter_id:String}; arena {run_complete:bool};
## challenge {score:int, perfect:bool}.
func notify_mode_win(mode: String, meta: Dictionary = {}) -> void:
	_record_battle_win(mode, meta)


## General battle-result hook: record a win or a loss for [param mode]. Mirrors
## [method notify_mode_win] on the win side; records a loss otherwise.
func notify_battle_result(mode: String, won: bool, meta: Dictionary = {}) -> void:
	if won:
		_record_battle_win(mode, meta)
	else:
		_record_battle_loss(mode)


## Explicitly start a new battle: clears the per-battle latches so the next result records.
## Normally this rides GameEvents.unit_spawned automatically -- a controller only needs to
## call it when it stages a battle without a fresh spawn pass (and tests use it to simulate
## a sequence of separate battles).
func begin_battle() -> void:
	_battle_decided = false
	_friendly_losses_this_battle = 0


## The map editor calls this after a custom map is saved (Cartographer achievement + stat).
##
## maps_created counts DISTINCT maps, not save presses -- re-saving the same map ten times
## must not read as ten maps. So the count is re-derived from what is actually on disk under
## [member _maps_dir] and only ever moves UP; a save that overwrites an existing file leaves
## it unchanged. The floor of 1 covers the case where the editor writes somewhere this class
## cannot see: a save just happened, so at least one custom map exists.
func notify_map_saved() -> void:
	var counted: int = maxi(_count_custom_maps(), 1)
	if counted > get_stat("maps_created"):
		_stats()["maps_created"] = counted
		_schedule_save()
	_evaluate_achievements()


# --- Recording -------------------------------------------------------------

func _record_battle_win(mode: String, meta: Dictionary) -> void:
	# One result per battle: whoever gets here first (a controller hook or the generic
	# auto-detector) latches it, so a double call -- or a hook followed by the elimination
	# signal -- can never grant twice.
	if _battle_decided:
		return
	_battle_decided = true
	_stats()["battles_won"] = get_stat("battles_won") + 1
	_bump_mode_stat("wins_by_mode", mode)

	match mode:
		"arena":
			_stats()["arena_rounds_won"] = get_stat("arena_rounds_won") + 1
			if bool(meta.get("run_complete", false)):
				_stats()["arena_runs_cleared"] = get_stat("arena_runs_cleared") + 1
			grant_points(POINTS_ARENA_ROUND, "arena_round")
		"campaign":
			# Chapter clears are counted (and paid) once each -- a replay is not a new chapter.
			if bool(meta.get("first_clear", true)):
				_stats()["campaign_chapters_cleared"] = get_stat("campaign_chapters_cleared") + 1
				grant_points(POINTS_CAMPAIGN_CHAPTER, "campaign_chapter")
		"challenge":
			_stats()["challenges_won"] = get_stat("challenges_won") + 1
			if bool(meta.get("perfect", _friendly_losses_this_battle == 0)):
				_stats()["perfect_challenges"] = get_stat("perfect_challenges") + 1
			var score: int = int(meta.get("score", 0))
			grant_points(maxi(0, score / 10), "challenge_win")
		_:
			grant_points(POINTS_SKIRMISH_WIN, "skirmish_win")

	_schedule_save()
	_evaluate_achievements()


func _record_battle_loss(mode: String) -> void:
	if _battle_decided:
		return
	_battle_decided = true
	_stats()["battles_lost"] = get_stat("battles_lost") + 1
	_bump_mode_stat("losses_by_mode", mode)
	_schedule_save()
	_evaluate_achievements()


func _bump_mode_stat(bucket_key: String, mode: String) -> void:
	var bucket: Dictionary = _stats().get(bucket_key, {})
	bucket[mode] = int(bucket.get(mode, 0)) + 1
	_stats()[bucket_key] = bucket


# =====================================================================================
#  ACHIEVEMENTS
# =====================================================================================

## Score every achievement against a fresh context and unlock any newly-earned ones. Idempotent
## -- an already-unlocked achievement is skipped, so this is safe to call on every event + load.
func _evaluate_achievements() -> void:
	var ctx: Dictionary = _build_achievement_context()
	var newly: Array = []
	for id in AchievementData.ids():
		if _achievements().has(id):
			continue
		if AchievementData.is_satisfied(id, ctx):
			_achievements()[id] = Time.get_datetime_string_from_system()
			newly.append(id)
	if newly.is_empty():
		return
	_schedule_save()
	for id in newly:
		achievement_unlocked.emit(id)
		_toast_achievement(id)


## Assemble the snapshot [AchievementData] scores against: the profile's own stats plus a few
## counts derived RETROACTIVELY from the campaign / challenge / map files on disk, so a deed
## done before this system existed still unlocks on the next load.
func _build_achievement_context() -> Dictionary:
	# Only chapters that actually EXIST in the campaign table count toward a clear, and the
	# final chapter's id is read from the table rather than hard-coded -- a renamed or
	# reordered campaign must not silently break "Blightbreaker" / "Heartwood's End".
	var chapter_ids: Array = _campaign_chapter_ids()
	var campaign_total: int = chapter_ids.size()
	var final_chapter_id: String = String(chapter_ids[campaign_total - 1]) if campaign_total > 0 else ""

	# DISTINCT cleared chapters, read from the campaign progress file (its keys are chapter
	# ids, so a chapter replayed ten times still counts once). This -- not the battles-won
	# tally -- is the authority for "cleared the whole campaign".
	var campaign_cleared: int = 0
	var eldroot_done: bool = false
	var progress: Dictionary = _read_json_dict(_campaign_path)
	for chapter_id in progress.keys():
		var rec: Variant = progress[chapter_id]
		if not (rec is Dictionary) or not bool(rec.get("cleared", false)):
			continue
		var cid: String = String(chapter_id)
		if not (cid in chapter_ids):
			continue  # stale id from an older campaign layout
		campaign_cleared += 1
		if cid == final_chapter_id:
			eldroot_done = true

	var challenge_won: bool = false
	var results: Dictionary = _read_json_dict(_challenge_path)
	for cid2 in results.keys():
		var r: Variant = results[cid2]
		if r is Dictionary and bool(r.get("won", false)):
			challenge_won = true
			break

	# Keep the mirrored stat in step so the stats card reads consistently even before a hook
	# fires (the retroactive count is authoritative when it is higher).
	if campaign_cleared > get_stat("campaign_chapters_cleared"):
		_stats()["campaign_chapters_cleared"] = campaign_cleared
		_schedule_save()

	var maps_created: int = maxi(get_stat("maps_created"), _count_custom_maps())

	return {
		"battles_won": get_stat("battles_won"),
		# The hook-fed stat can lead the file (a controller may award before it persists), so
		# "have you cleared ANY chapter" takes whichever is higher...
		"campaign_cleared_count": maxi(campaign_cleared, get_stat("campaign_chapters_cleared")),
		# ...but "cleared EVERY chapter" only trusts the distinct on-disk record, so replaying
		# chapter 1 four times can never masquerade as a full clear.
		"campaign_complete": campaign_total > 0 and campaign_cleared >= campaign_total,
		"eldroot_defeated": eldroot_done,
		"arena_rounds_won": get_stat("arena_rounds_won"),
		"arena_runs_cleared": get_stat("arena_runs_cleared"),
		"challenge_won": challenge_won or get_stat("challenges_won") > 0,
		"perfect_challenges": get_stat("perfect_challenges"),
		"maps_created": maps_created,
		"owned_skins_count": _owned_skins().size(),
	}


## The campaign's chapter ids, in play order. [CampaignData] is a project-global
## [code]class_name[/code] script (like [RankLadder] here), so it is always resolvable --
## no runtime existence probe is needed or meaningful. The result is defensive only about
## the SHAPE of the table (an empty campaign yields an empty list, which switches the
## "clear every chapter" achievement off rather than unlocking it for free).
func _campaign_chapter_ids() -> Array:
	var out: Array = []
	for chapter in CampaignData.chapters():
		if not (chapter is Dictionary):
			continue
		var cid: String = String(chapter.get("id", ""))
		if not cid.is_empty():
			out.append(cid)
	return out


func _toast_achievement(id: String) -> void:
	if _toast == null:
		return
	var row: Dictionary = AchievementData.get_row(id)
	if row.is_empty():
		return
	_toast.enqueue(String(row.get("name", id)), String(row.get("icon", "★")))


func _mount_toast() -> void:
	# Only build the visual layer when there is a real windowed viewport (never headless / tests).
	if DisplayServer.get_name() == "headless":
		return
	if not is_inside_tree():
		return
	var script: GDScript = load(TOAST_SCRIPT) as GDScript
	if script == null:
		return
	var layer := CanvasLayer.new()
	layer.name = "AchievementToastLayer"
	layer.set_script(script)
	add_child(layer)
	_toast = layer


# =====================================================================================
#  PERSISTENCE
# =====================================================================================

## Override the save path (tests point this at a temp file). Does NOT auto-load; call
## [method load_profile] after.
func set_profile_path(path: String) -> void:
	_path = path if not path.is_empty() else DEFAULT_PROFILE_PATH


## Redirect where the RETROACTIVE sweep looks for outside evidence (campaign progress,
## challenge results, custom maps). Tests point these at temp paths so a sweep is
## reproducible; production leaves the defaults. Empty strings keep the current value.
func set_source_paths(campaign_path: String, challenge_path: String, maps_dir: String) -> void:
	if not campaign_path.is_empty():
		_campaign_path = campaign_path
	if not challenge_path.is_empty():
		_challenge_path = challenge_path
	if not maps_dir.is_empty():
		_maps_dir = maps_dir


## (Re)load the profile from the current path, normalising missing keys to defaults, then
## re-run the retroactive achievement sweep against it.
func load_profile() -> void:
	_load()
	_evaluate_achievements()


func _load() -> void:
	var parsed: Dictionary = _read_json_dict(_path)
	_data = _normalise(parsed)


## Fill any missing top-level / stat keys so the rest of the code can read them unconditionally.
func _normalise(src: Dictionary) -> Dictionary:
	var d: Dictionary = _default_data()
	for k in src.keys():
		d[k] = src[k]
	# Deep-fill the stats sub-dictionary.
	var stats: Dictionary = d.get("stats", {})
	if not (stats is Dictionary):
		stats = {}
	var default_stats: Dictionary = _default_data()["stats"]
	for sk in default_stats.keys():
		if not stats.has(sk):
			stats[sk] = default_stats[sk]
	d["stats"] = stats
	if not (d.get("achievements", {}) is Dictionary):
		d["achievements"] = {}
	if not (d.get("equipped_skins", {}) is Dictionary):
		d["equipped_skins"] = {}
	if not (d.get("owned_skins", []) is Array):
		d["owned_skins"] = []
	return d


func _default_data() -> Dictionary:
	return {
		"points_total": 0,
		"points_spent": 0,
		"achievements": {},
		"stats": {
			"battles_won": 0,
			"battles_lost": 0,
			"units_defeated": 0,
			"perfect_challenges": 0,
			"campaign_chapters_cleared": 0,
			"arena_rounds_won": 0,
			"arena_runs_cleared": 0,
			"challenges_won": 0,
			"maps_created": 0,
			"wins_by_mode": {},
			"losses_by_mode": {},
		},
		"owned_skins": [],
		"equipped_skins": {},
	}


## Debounced save: coalesce a burst of changes into one write on the next idle frame. Falls back
## to an immediate write when not in the tree (tests using a bare instance), so a round-trip works.
func _schedule_save() -> void:
	if not is_inside_tree() or get_tree() == null:
		_save()
		return
	if _save_pending:
		return
	_save_pending = true
	call_deferred("_flush_save")


func _flush_save() -> void:
	_save_pending = false
	_save()


func _save() -> void:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_error("PlayerProfile: could not write profile to '%s'." % _path)
		return
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()


## Force an immediate write (used by tests).
func save_now() -> void:
	_save()


# =====================================================================================
#  INTERNAL ACCESSORS + HELPERS
# =====================================================================================

func _points_total() -> int:
	return int(_data.get("points_total", 0))


func _points_spent() -> int:
	return int(_data.get("points_spent", 0))


func _stats() -> Dictionary:
	var s = _data.get("stats", null)
	if not (s is Dictionary):
		s = _default_data()["stats"]
		_data["stats"] = s
	return s


func _achievements() -> Dictionary:
	var a = _data.get("achievements", null)
	if not (a is Dictionary):
		a = {}
		_data["achievements"] = a
	return a


func _owned_skins() -> Array:
	var o = _data.get("owned_skins", null)
	if not (o is Array):
		o = []
		_data["owned_skins"] = o
	return o


func _equipped_skins() -> Dictionary:
	var e = _data.get("equipped_skins", null)
	if not (e is Dictionary):
		e = {}
		_data["equipped_skins"] = e
	return e


func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	# Instance parse, NOT JSON.parse_string: the static helper logs an engine error on
	# malformed input, and "the save file is corrupt" is an EXPECTED case here (we
	# recover with a blank profile) - it should not spam the log or fail test gates.
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	return parsed if parsed is Dictionary else {}


## Count of custom maps the player has authored: the .json files under [member _maps_dir]
## (the format MapMakerScene / MapLoader use). Non-map sidecars (.import, .tmp, editor
## leftovers) are ignored so the Cartographer count reflects real maps.
func _count_custom_maps() -> int:
	if not DirAccess.dir_exists_absolute(_maps_dir):
		return 0
	var dir: DirAccess = DirAccess.open(_maps_dir)
	if dir == null:
		return 0
	var count: int = 0
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.get_extension().to_lower() == "json":
			count += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return count
