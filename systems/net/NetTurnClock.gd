extends RefCounted
class_name NetTurnClock

## ONLINE TURN CLOCK -- the presets, budgets and wording of the host-authoritative turn timer
## every online match runs (Conquest map battles, Traditional and Speed First, and online
## duels). Pure statics: no networking, no tree. [NetSession] owns the live clock (deadlines,
## broadcasts, expiry, the anti-AFK strike count); the rules object ([NetGameRules] /
## [DuelNetRules]) says what a "timed turn" is and what a timeout does; the HUD ([TurnTimer])
## renders the countdown the host broadcast.
##
## THE OWNER'S RULE: every online mode has a clock -- there is no "Off" preset online.
##
## KINDS (which budget a timed turn draws):
##   [constant KIND_SIDE]    Traditional: a whole side's turn. Budget = side seconds + a small
##                           per-unit allowance for every living unit the side fields when its
##                           turn opens (a bigger army gets a little longer).
##   [constant KIND_UNIT]    Speed First: ONE unit's turn -- the tight "I go, you go" clock.
##   [constant KIND_ACTION]  Online duel: one combatant's action (a voluntary SWITCH is an action).
##   [constant KIND_PICK]    Online PARTY duel: a KO replacement pick -- its own short clock,
##                           opened when the fainted side must pick (before anyone acts).
##
## TIMEOUTS are played as a normal ACCEPTED action through the NetSession pipeline (identical
## on every peer, recorded, replayable), stamped [constant NetProtocol.KEY_TIMEOUT]:
##   Traditional -> END_TURN for the seat; Speed First -> WAIT for the active unit (END_TURN
##   when it cannot wait); duel -> the acting combatant PASSES (a WAIT: no damage, no roll for
##   the idle seat, the opponent simply gets the tempo); a pending KO replacement pick -> the
##   host AUTO-PICKS the seat's first healthy benched member in team order (a SWITCH).
## [constant DEFAULT_AFK_LIMIT] consecutive expiries for the same seat = that seat FORFEITS.

const PRESET_RAPID := "rapid"
const PRESET_STANDARD := "standard"
const PRESET_RELAXED := "relaxed"
## Display order (lobby pickers).
const PRESET_IDS: Array[String] = [PRESET_RAPID, PRESET_STANDARD, PRESET_RELAXED]
const DEFAULT_PRESET := PRESET_STANDARD

const KIND_SIDE := "side"
const KIND_UNIT := "unit"
const KIND_ACTION := "action"
const KIND_PICK := "pick"

## Seconds per kind. side = Traditional per-side base, per_unit = Traditional allowance per
## living unit at turn start, unit = Speed First per-unit clock, action = duel per-action clock,
## pick = a party duel's KO replacement pick (a single choice from the bench: half-ish an action).
const PRESETS := {
	PRESET_RAPID: {"label": "Rapid", "side": 45, "per_unit": 3, "unit": 10, "action": 15, "pick": 10},
	PRESET_STANDARD: {"label": "Standard", "side": 90, "per_unit": 5, "unit": 20, "action": 30, "pick": 15},
	PRESET_RELAXED: {"label": "Relaxed", "side": 150, "per_unit": 8, "unit": 35, "action": 50, "pick": 25},
}

## Consecutive expiries (same seat, no own action in between) that forfeit the match. The
## Nth expiry is not played out: the seat forfeits instead. 0 disables the anti-AFK rule.
const DEFAULT_AFK_LIMIT := 3
const MAX_AFK_LIMIT := 10

## Match-config keys (host-stamped at the start; a lobby / dedicated server sets the preset).
const CONFIG_PRESET := "turn_clock"
const CONFIG_AFK_LIMIT := "afk_limit"

## Below this many seconds the HUD turns urgent (red pulse + tick).
const WARNING_SECONDS := 5.0


## [param preset] as a known preset id ([constant DEFAULT_PRESET] for anything else).
static func normalise_preset(preset) -> String:
	if preset is String or preset is StringName:
		var p := String(preset).strip_edges().to_lower()
		if PRESETS.has(p):
			return p
	return DEFAULT_PRESET


## True when [param preset] names a known preset exactly.
static func is_preset(preset) -> bool:
	return (preset is String or preset is StringName) and PRESETS.has(String(preset))


## [param limit] clamped to 0..[constant MAX_AFK_LIMIT] (anything unreadable -> the default).
static func normalise_afk_limit(limit) -> int:
	if typeof(limit) != TYPE_INT and typeof(limit) != TYPE_FLOAT:
		return DEFAULT_AFK_LIMIT
	return clampi(int(limit), 0, MAX_AFK_LIMIT)


## "Rapid" / "Standard" / "Relaxed".
static func label(preset) -> String:
	return String(PRESETS[normalise_preset(preset)]["label"])


## Seconds a [param kind] turn gets under [param preset] (the side kind before the per-unit
## allowance -- see [method budget_ms]).
static func seconds_for(preset, kind: String) -> int:
	var p: Dictionary = PRESETS[normalise_preset(preset)]
	match kind:
		KIND_UNIT:
			return int(p["unit"])
		KIND_ACTION:
			return int(p["action"])
		KIND_PICK:
			return int(p["pick"])
	return int(p["side"])


## The budget (ms) of one timed turn. [param units] is the side's living unit count when a
## [constant KIND_SIDE] turn opens (ignored for the other kinds). [param override_ms] > 0
## replaces every budget (a test / dev knob: [code]--turn-clock-ms[/code]).
static func budget_ms(preset, kind: String, units: int = 0, override_ms: int = 0) -> int:
	if override_ms > 0:
		return override_ms
	var s: int = seconds_for(preset, kind)
	if kind == KIND_SIDE:
		s += int(PRESETS[normalise_preset(preset)]["per_unit"]) * maxi(0, units)
	return s * 1000


## One line for a lobby / tooltip: "90s per side (+5s per unit), 20s per unit in Speed First,
## 30s per duel action (15s per KO pick)".
static func describe(preset) -> String:
	var p: Dictionary = PRESETS[normalise_preset(preset)]
	return "%ds per side (+%ds per unit), %ds per unit in Speed First, %ds per duel action (%ds per KO pick)" % [
		int(p["side"]), int(p["per_unit"]), int(p["unit"]), int(p["action"]), int(p["pick"])]


## The picker's items: [[id, "Rapid"], ...] in display order.
static func picker_items() -> Array:
	var out: Array = []
	for id in PRESET_IDS:
		out.append([id, label(id)])
	return out


## "1:05" / "0:09" for [param ms] remaining (rounded UP, so 0.2s left still reads 0:01).
static func format_ms(ms: int) -> String:
	var total: int = int(ceil(maxf(0.0, float(ms)) / 1000.0))
	return "%d:%02d" % [total / 60, total % 60]


## The player-facing line for an applied timeout [param action]. [param mine]: it hit THIS
## seat. [param strikes] / [param limit]: the seat's consecutive expiries and the forfeit limit
## (a warning is added while the next expiry would forfeit).
static func describe_timeout(action: Variant, mine: bool, strikes: int = 0, limit: int = 0) -> String:
	var what := "turn ended"
	var t: int = int((action as Dictionary).get(NetProtocol.KEY_TYPE, -1)) if action is Dictionary else -1
	if t == NetProtocol.Action.WAIT:
		what = "unit waits"
	elif t == NetProtocol.Action.SWITCH:
		what = "replacement was auto-picked"
	var line := "Time's up — %s %s" % ["your" if mine else "opponent's", what]
	if mine and limit > 0 and strikes > 0 and strikes >= limit - 1:
		line += " (one more and you forfeit)"
	return line
