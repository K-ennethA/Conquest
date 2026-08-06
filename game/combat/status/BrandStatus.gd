extends StatusCondition
class_name BrandStatus

## THE BRAND (Monster's Dread Brand): a one-shot VULNERABILITY that amplifies the very
## next damage instance its unit takes -- from anyone, by any means -- and is then
## CONSUMED.
##
## Two halves, both riding machinery that already exists:
##
##  1. THE AMPLIFICATION is a plain [member StatusCondition.damage_taken_scale] above
##     1.0 (1.3 in `branded.tres`). Every damage road already asks the defender for that
##     number exactly once -- [method DamageMath.apply_scales] step 3 for a move, a tile
##     or a status tick, and [method DamageMath.environment_damage] step 2 for a crawling
##     hazard -- so the brand deepens a sword, a bramble and a vine identically with no
##     new plumbing. It is also why the FORECAST shows the amplified number for free:
##     the panel and the blow share that one function (CONQUEST.md rule 9), so there is
##     no preview path to teach.
##
##  2. THE CONSUME is this script, and it is the only thing a plain .tres could not
##     express. It listens on the shared [code]damage_dealt[/code] bus for an
##     announcement naming ITS OWN unit as the defender and, on the first one that
##     actually removes HP, takes itself off the unit.
##
## WHY THE BUS AND NOT A QUERY. The obvious alternative -- consuming inside
## [method DamageMath.damage_taken_scale_for] -- is unusable: the FORECAST calls that
## same function, so merely hovering a target would eat the brand. The bus announcement
## is the one beat that fires only for damage that really happened, it fires for EVERY
## source (moves, tiles, status ticks and hazards all funnel through
## [method DamageEffect.announce_damage]), and it carries no RNG or wall-clock, so
## lockstep peers and replays consume the brand on the same instant.
##
## ANNOUNCE-BEFORE-APPLY IS WHAT MAKES THE ORDER RIGHT. The damage number is computed
## (brand folded in) and THEN announced, and only afterwards applied -- so by the time
## this handler runs the amplified hit is already decided and consuming cannot un-amplify
## it. The same ordering is why the hit that PLANTS the brand is never amplified by it:
## Dread Brand is an ON_ATTACK ability raised FROM that announcement, so the brand does
## not exist yet when the blow's scales were read, and (Godot snapshots a signal's
## connections before dispatch) this listener does not receive the emission it was
## created during.
##
## REFRESH, NEVER STACK (CONQUEST.md rule 6). Authored REFRESH, so a second brand on an
## already-branded victim resets the one instance rather than adding a second: two
## brands can never multiply into x1.69. [method bind] is idempotent for that reason --
## a refresh re-arms the existing instance instead of opening a second subscription.
##
## A NEGATED HIT DOES NOT SPEND IT. [DamageEffect] announces an invulnerable target's
## hit as a literal 0, so the brand ignores any announcement of 0 or less: a blow that
## took nothing off is not "the next damage the victim takes".

## True once this instance has spent itself on a damage instance. Runtime state, so
## [method Resource.duplicate] hands every fresh copy an unspent brand.
var _consumed: bool = false

## Weak handle on the branded unit -- the defender this instance answers for. Weak for
## the same reason [member StatusCondition._source_ref] is: a status can outlive the
## board it was standing on, and a strong reference from a Resource to a freed Node is a
## dangling-object crash mid-turn.
var _unit_ref: WeakRef = null

## The bus this instance listens on: the cast's injected
## [member MoveContext.event_bus] when there was one, else the GameEvents autoload.
## Carried from the cast exactly as [SpawnHazardEffect] carries one onto a vine, so a
## headless test can drive the whole consume with a mock bus and no autoloads.
var _bus = null


## Arm this live instance on [param unit], listening on [param bus] (null = the
## GameEvents autoload). Called by [DreadBrandEffect] on the instance
## [method StatusController.add_status] returns -- which is the EXISTING instance on a
## refresh, so this doubles as the re-arm and can never open a second subscription.
##
## Idempotent and null-safe: re-binding to the same bus only resets the spent flag.
func bind(unit, bus = null) -> void:
	if unit == null:
		return
	_unit_ref = weakref(unit)
	_consumed = false
	var wanted = bus if bus != null else _autoload_bus()
	if wanted == _bus:
		return
	_unbind_bus()
	_bus = wanted
	_bind_bus()


## True while this instance still has its one amplification to give. Test/inspection
## convenience; the live rule is simply whether the status is still on the unit.
func is_spent() -> bool:
	return _consumed


## Dropped off the unit (consumed, cleansed, or the whole controller cleared): stop
## listening. Also the sole disconnect point, so a brand can never outlive its
## subscription.
func on_expire(_target, _board) -> void:
	_unbind_bus()


## One damage instance landed somewhere on the board. Spend the brand if it landed on
## OUR unit and actually removed HP.
func _on_damage_dealt(_attacker, defender, amount) -> void:
	if _consumed or defender == null:
		return
	var me = _unit_ref.get_ref() if _unit_ref != null else null
	if me == null or defender != me:
		return
	if int(amount) <= 0:
		return  # a negated / zero hit is not "the next damage taken"
	# Latched BEFORE the removal, so the on_expire this triggers -- and anything it in
	# turn announces -- cannot re-enter and double-spend.
	_consumed = true
	var controller = _controller_of(me)
	if controller != null and controller.has_method("remove_status"):
		controller.remove_status(id)
	else:
		# No controller to remove us from (a direct-sink mock): at minimum stop listening,
		# so the amplification cannot apply twice.
		_unbind_bus()


func _bind_bus() -> void:
	if _bus == null or not is_instance_valid(_bus):
		return
	if not _bus.has_signal(&"damage_dealt"):
		_bus = null
		return
	if not _bus.is_connected(&"damage_dealt", _on_damage_dealt):
		_bus.connect(&"damage_dealt", _on_damage_dealt)


func _unbind_bus() -> void:
	if _bus != null and is_instance_valid(_bus) and _bus.has_signal(&"damage_dealt") \
			and _bus.is_connected(&"damage_dealt", _on_damage_dealt):
		_bus.disconnect(&"damage_dealt", _on_damage_dealt)
	_bus = null


## The GameEvents autoload, or null when there is none (headless suites). Guarded the
## same way [method StatusController._announce] guards it.
static func _autoload_bus():
	if typeof(GameEvents) != TYPE_OBJECT or GameEvents == null:
		return null
	return GameEvents


## [param unit]'s [StatusController] through whichever accessor it exposes, or null.
static func _controller_of(unit):
	if unit != null and unit.has_method("get_status_controller"):
		return unit.get_status_controller()
	return null
