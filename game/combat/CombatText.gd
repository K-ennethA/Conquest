extends RefCounted
class_name CombatText

## Annotation seam for FLOATING COMBAT TEXT and the battle log (presentation only).
##
## Every code path that changes a unit's HP (a move's hit, a burning tile, a status
## tick, a weather rule, a crawling hazard, lifesteal, a heal) calls [method annotate]
## JUST BEFORE it changes the HP, describing WHY: crit, type effectiveness, the
## source ("Fire", "Poisoned", "Scouring Sand" under Desert Storm, ...), or that the
## attack missed. [FloatingCombatText] pairs each annotation with the unit's next
## [signal UnitStats.health_changed] in the same frame; an HP change nobody annotated
## still shows as a plain number, and an annotation that never meets an HP change
## (a miss, a hit a shield soaked completely, an invulnerable target) is shown on its
## own at the end of the frame.
##
## NOTHING here feeds back into gameplay: no RNG is consumed, no state is written, the
## signal is fire-and-forget. So it cannot perturb network determinism.
##
## Info dictionary keys (all optional):
##   kind          : KIND_DAMAGE / KIND_HEAL / KIND_MISS / KIND_NEGATED
##   amount        : int, HP the source intends to remove / restore
##   crit          : bool
##   effectiveness : float, the move-element vs target-type multiplier (1.5 / 0.75)
##   source        : String, player-facing source name ("" = a normal attack)
##   source_kind   : SRC_* below
##   source_id     : StringName of the tile effect / status / ability
##   weather       : String, the weather's display name when a weather rule caused it
##   weather_fx    : StringName, the weather's fx_kind (drives the WeatherIcon glyph)
##   color         : Color, the source's accent (tile / status / weather colour)
##   attacker      : the acting unit for a normal attack (may be null)

const KIND_DAMAGE := &"damage"
const KIND_HEAL := &"heal"
const KIND_MISS := &"miss"
const KIND_NEGATED := &"negated"

const SRC_ATTACK := &"attack"
const SRC_TILE := &"tile"
const SRC_STATUS := &"status"
const SRC_WEATHER := &"weather"
const SRC_ABILITY := &"ability"
const SRC_HAZARD := &"hazard"
const SRC_LIFESTEAL := &"lifesteal"

const SIGNAL := &"combat_text_annotated"


## Emit one annotation for [param target]. Routed through [param bus] when it carries
## the signal (tests inject a mock bus), else the GameEvents autoload. Null-safe: no
## bus, no signal or a null target simply no-op.
static func annotate(target, info: Dictionary, bus = null) -> void:
	if target == null or not (target is Object):
		return
	if bus == null or not (bus is Object) or not bus.has_signal(SIGNAL):
		bus = _game_events()
	if bus == null or not bus.has_signal(SIGNAL):
		return
	bus.emit_signal(SIGNAL, target, info)


## The source block a [MoveContext] carries ([member MoveContext.source]), copied so
## the caller can add hit-specific keys. Empty for a normal move (an attack).
static func source_of(ctx) -> Dictionary:
	if ctx == null or not ("source" in ctx):
		return {}
	var s = ctx.source
	if s is Dictionary:
		return (s as Dictionary).duplicate()
	return {}


## Build the info block for one effect resolved in [param ctx] against a target.
static func info_for(ctx, kind: StringName, amount: int, extra: Dictionary = {}) -> Dictionary:
	var info := source_of(ctx)
	info["kind"] = kind
	info["amount"] = amount
	if not info.has("source_kind"):
		info["source_kind"] = SRC_ATTACK
		if ctx != null and "caster" in ctx:
			info["attacker"] = ctx.caster
	for k in extra:
		info[k] = extra[k]
	return info


## A source block for [MoveContext.source] ("Fire", "Poisoned", ...).
static func make_source(kind: StringName, label: String, id: StringName = &"", color = null) -> Dictionary:
	var d := { "source_kind": kind, "source": label, "source_id": id }
	if color is Color:
		d["color"] = color
	return d


static func _game_events():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("GameEvents")
	return null
