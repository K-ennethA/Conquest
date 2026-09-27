extends Resource
class_name WeatherResource

## One kind of battlefield weather, authored as data (see docs/WEATHER.md).
##
## Every gameplay rule is expressed with the EXISTING pipeline vocabulary so a new
## weather is a new .tres in game/weather/resources/ -- no code:
##   - [member element_damage_scale]  -- move element -> damage multiplier
##     (Bright Sun: fire x1.3, water x0.8). Folded into [DamageEffect] and the
##     forecast ([method MoveExecutor.preview_vs]) at the same step, via [Weather].
##   - [member ranged_hit_modifier]   -- accuracy points added to moves whose
##     targeting reaches [member ranged_min_range]+ (Desert Storm: -15).
##   - [member stat_rules]            -- PASSIVE [AbilityResource]s whose
##     rule_modifiers "stat_<name>": int grant a COMBAT-TIME stat bonus while their
##     condition holds (Desert Storm: earth units +defense). Read like terrain avoid
##     ([TerrainStats]): summed when a hit is forecast/resolved, never stored.
##   - [member turn_start_rules]      -- ON_TURN_START [AbilityResource]s every unit
##     runs at its own turn start while this weather is active (sand chip damage,
##     Overbloom healing). Conditions gate who is affected.
##   - [member suppressed_tile_effects] -- tile effect ids that do not trigger while
##     this weather is active (Rain douses fire); runtime-applied ones are removed.
##
## The visual block is read by [WeatherFX] only (never by gameplay).

@export var id: StringName = &""
@export var display_name: String = "Weather"
## Short glyph for HUD chips / the forecast ("☀", "☂", ...).
@export var icon: String = ""
## Accent colour for chips and banners.
@export var color: Color = Color(0.85, 0.85, 0.85)
@export_multiline var description: String = ""

@export_group("Combat")
## Move element (StringName, e.g. &"fire") -> damage multiplier. Missing = 1.0.
@export var element_damage_scale: Dictionary = {}
## Hit-chance points added to RANGED moves (targeting max_range >= ranged_min_range).
@export var ranged_hit_modifier: int = 0
@export var ranged_min_range: int = 2
## PASSIVE abilities: rule_modifiers {"stat_defense": 3, "stat_evasion": -5, ...}
## gated by their condition. Combat-time bonus only (see [method Weather.stat_bonus_for]).
@export var stat_rules: Array[AbilityResource] = []
## ON_TURN_START abilities run on every unit at its own turn start (condition-gated).
@export var turn_start_rules: Array[AbilityResource] = []
## [member TileEffectResource.id]s that are inert while this weather is active.
@export var suppressed_tile_effects: Array[StringName] = []

@export_group("Visuals")
## Which particle rig [WeatherFX] builds: &"clear", &"sun", &"rain", &"sand", &"bloom".
@export var fx_kind: StringName = &"clear"
## Key light (the scene's "Sun") colour and energy multiplier.
@export var sun_color: Color = Color(1.0, 0.96, 0.88)
@export var sun_energy_scale: float = 1.0
## Ambient light multiplier and tint (tint multiplies the ambient colour).
@export var ambient_scale: float = 1.0
@export var ambient_tint: Color = Color(1, 1, 1)
## Depth fog: 0 density = off.
@export var fog_color: Color = Color(0.7, 0.75, 0.8)
@export_range(0.0, 0.2, 0.001) var fog_density: float = 0.0
## Multiplies the environment glow intensity / bloom.
@export var glow_scale: float = 1.0
@export var glow_bloom: float = 0.0
## Colour grading (adjustments): 1 = unchanged.
@export var saturation: float = 1.0
@export var brightness: float = 1.0
@export var contrast: float = 1.0
## Sky tint (multiplies the procedural sky's top / horizon colours).
@export var sky_tint: Color = Color(1, 1, 1)
## Global shader uniforms (world art pass), 0..1. Only pushed if declared.
@export_range(0.0, 1.0) var shader_wetness: float = 0.0
@export_range(0.0, 1.0) var shader_dust: float = 0.0
@export_range(0.0, 1.0) var shader_bloom: float = 0.0
@export_range(0.0, 1.0) var shader_sun: float = 0.0
@export var wind_strength: float = 1.0


## Damage multiplier this weather applies to a move of [param element] (1.0 = none).
func damage_scale_for_element(element: StringName) -> float:
	if element == &"":
		return 1.0
	if element_damage_scale.has(element):
		return float(element_damage_scale[element])
	# Tolerate String keys written by hand / JSON.
	if element_damage_scale.has(String(element)):
		return float(element_damage_scale[String(element)])
	return 1.0


## True when [param tile_effect_id] is inert under this weather.
func suppresses(tile_effect_id: StringName) -> bool:
	if tile_effect_id == &"":
		return false
	for s in suppressed_tile_effects:
		if StringName(s) == tile_effect_id:
			return true
	return false


## True when this weather changes nothing in combat (Clear).
func is_neutral() -> bool:
	return element_damage_scale.is_empty() and ranged_hit_modifier == 0 \
		and stat_rules.is_empty() and turn_start_rules.is_empty() \
		and suppressed_tile_effects.is_empty()


func _to_string() -> String:
	return "%s %s" % [icon, display_name]
