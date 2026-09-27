extends GutTest

## Weather system (docs/WEATHER.md): the authored weathers' combat rules, the
## schedule / dynamic maths, weather-conditioned abilities, SetWeatherEffect, map
## serialization and the forecast chip. Headless, against mocks + the live
## CombatServices.weather state (reset around every test).

# --- Mocks -------------------------------------------------------------------

class WUnit:
	var team: int
	var element: StringName
	var stats: Dictionary
	var hp: int
	var max_health: int
	var character_resource = null
	var tags: Array = []
	func _init(p_team: int, p_element: StringName = &"", p_stats: Dictionary = {}) -> void:
		team = p_team
		element = p_element
		stats = p_stats
		max_health = int(stats.get("health", 160))
		hp = max_health
	func get_stat(n: String) -> int:
		if n == "health":
			return hp
		return int(stats.get(n, 0))
	func get_base_stat(n: String) -> int:
		if n == "health":
			return max_health
		return int(stats.get(n, 0))
	func get_element() -> StringName:
		return element
	func get_hp() -> int:
		return hp
	func is_alive() -> bool:
		return hp > 0
	func take_damage(n: int) -> void:
		hp = maxi(0, hp - n)
	func heal(n: int) -> void:
		hp = mini(max_health, hp + n)
	func add_stat_modifier(stat: String, amount: int, _duration: int = -1) -> int:
		stats[stat] = int(stats.get(stat, 0)) + amount
		return 0


class WBoard:
	var cells: Dictionary = {}   # unit -> Vector3i
	var effects: Dictionary = {} # Vector3i -> Array
	func place(u, c: Vector3i) -> void:
		cells[u] = c
	func cell_of(u) -> Vector3i:
		return cells.get(u, Vector3i(-99, -99, 0))
	func units_at(c: Vector3i) -> Array:
		var out: Array = []
		for u in cells:
			if cells[u] == c:
				out.append(u)
		return out
	func are_enemies(a, b) -> bool:
		return a != null and b != null and a.team != b.team
	func are_allies(a, b) -> bool:
		return a != null and b != null and a.team == b.team
	func tile_effects_at(c: Vector3i) -> Array:
		return effects.get(c, [])


func before_each() -> void:
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()


func _set_weather(id: StringName) -> void:
	CombatServices.weather.configure({ "mode": "fixed", "weather": String(id) }, 0)


func _move(element: StringName, max_range: int = 1, power: int = 20) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_move"
	m.element = element
	m.accuracy = 1.0
	m.crit_chance = 0.0
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = max_range
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	var d := DamageEffect.new()
	d.power = power
	d.scaling_stat = ""
	d.category = CombatTypes.DamageCategory.PHYSICAL
	m.effects = [d]
	return m


## Resolve [param move] from a fresh caster into a fresh neutral target; returns
## [dealt, forecast damage].
func _hit(move: MoveResource, target_element: StringName = &"", defense: int = 0) -> Array:
	var board := WBoard.new()
	var caster := WUnit.new(0)
	var target := WUnit.new(1, target_element, { "defense": defense })
	board.place(caster, Vector3i(0, 0, 0))
	board.place(target, Vector3i(1, 0, 0))
	var preview := MoveExecutor.preview_vs(move, caster, target, board)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var res := MoveExecutor.execute(move, caster, board, Vector3i(1, 0, 0), rng)
	assert_true(res["success"], "move resolved")
	return [target.max_health - target.hp, int(preview["damage"])]


# --- Catalog -------------------------------------------------------------------

func test_catalog_lists_the_authored_weathers_clear_first() -> void:
	var ids := Weather.all_ids()
	assert_eq(ids[0], Weather.CLEAR)
	for id in [&"bright_sun", &"rain", &"desert_storm", &"overbloom"]:
		assert_true(id in ids, "%s is authored" % id)
		assert_eq(Weather.get_weather(id).id, id)
	assert_eq(Weather.get_weather(&"no_such_weather").id, Weather.CLEAR, "unknown -> Clear")
	assert_true(Weather.get_weather(&"clear").is_neutral())


func test_default_battle_weather_is_clear_and_neutral() -> void:
	assert_eq(Weather.current_id(), Weather.CLEAR)
	var r := _hit(_move(&"fire"))
	assert_eq(r[0], 20, "no scaling on Clear")


# --- Damage scaling ------------------------------------------------------------

func test_bright_sun_scales_fire_up_and_water_down() -> void:
	_set_weather(&"bright_sun")
	var fire := _hit(_move(&"fire"))
	assert_eq(fire[0], 26, "fire x1.3")
	assert_eq(fire[1], fire[0], "forecast == hit")
	var water := _hit(_move(&"water"))
	assert_eq(water[0], 16, "water x0.8")
	assert_eq(water[1], water[0])
	assert_eq(_hit(_move(&"nature"))[0], 20, "other elements untouched")


func test_rain_scales_water_up_and_fire_down() -> void:
	_set_weather(&"rain")
	assert_eq(_hit(_move(&"water"))[0], 26, "water x1.3")
	assert_eq(_hit(_move(&"fire"))[0], 14, "fire x0.7")
	assert_eq(_hit(_move(&""))[0], 20, "unelemented untouched")


func test_overbloom_boosts_nature_moves() -> void:
	_set_weather(&"overbloom")
	var r := _hit(_move(&"nature"))
	assert_eq(r[0], 23, "nature x1.15")
	assert_eq(r[1], 23)


# --- Desert storm ----------------------------------------------------------------

func test_desert_storm_penalises_ranged_hit_only() -> void:
	_set_weather(&"desert_storm")
	var caster := WUnit.new(0)
	var target := WUnit.new(1)
	var board := WBoard.new()
	board.place(caster, Vector3i(0, 0, 0))
	board.place(target, Vector3i(2, 0, 0))
	var ranged := _move(&"", 3)
	var melee := _move(&"", 1)
	assert_eq(MoveExecutor.preview_vs(ranged, caster, target, board)["hit_pct"], 85.0, "range 3: -15")
	assert_eq(MoveExecutor.preview_vs(melee, caster, target, board)["hit_pct"], 100.0, "melee untouched")
	var ctx := MoveContext.new(caster, board, ranged, Vector3i(2, 0, 0), [Vector3i(2, 0, 0)] as Array[Vector3i])
	assert_eq(ctx.hit_chance(target), 85.0, "roll path agrees with the forecast")


func test_desert_storm_gives_earth_units_defense() -> void:
	_set_weather(&"desert_storm")
	assert_eq(Weather.stat_bonus_for(WUnit.new(0, &"earth"), "defense"), 3)
	assert_eq(Weather.stat_bonus_for(WUnit.new(0, &"fire"), "defense"), 0)
	var r := _hit(_move(&""), &"earth", 5)
	assert_eq(r[0], 12, "20 - (5 + 3)")
	assert_eq(r[1], 12, "forecast includes the weather defense")


func test_desert_storm_chip_damage_and_immunity() -> void:
	_set_weather(&"desert_storm")
	var board := WBoard.new()
	var plain := WUnit.new(0, &"nature", { "health": 160 })
	var earth := WUnit.new(0, &"earth", { "health": 160 })
	var proof := WUnit.new(1, &"fire", { "health": 160 })
	proof.tags = [&"sand_proof"]
	var tiny := WUnit.new(1, &"dark", { "health": 5 })
	for u in [plain, earth, proof, tiny]:
		board.place(u, Vector3i(board.cells.size(), 0, 0))
		Weather.run_turn_start(u, board)
	assert_eq(plain.hp, 150, "1/16 of 160")
	assert_eq(earth.hp, 160, "earth is immune")
	assert_eq(proof.hp, 160, "sand_proof tag is immune")
	assert_eq(tiny.hp, 4, "minimum 1")


# --- Overbloom -----------------------------------------------------------------

func test_overbloom_heals_nature_units_and_pollen_hits_others() -> void:
	_set_weather(&"overbloom")
	var board := WBoard.new()
	var leaf := WUnit.new(0, &"nature", { "health": 100 })
	var rock := WUnit.new(0, &"earth", { "health": 100 })
	leaf.hp = 50
	rock.hp = 50
	board.place(leaf, Vector3i(0, 0, 0))
	board.place(rock, Vector3i(1, 0, 0))
	Weather.run_turn_start(leaf, board)
	Weather.run_turn_start(rock, board)
	assert_eq(leaf.hp, 60, "nature heals 1/10 max")
	assert_eq(rock.hp, 50, "non-nature does not")
	assert_eq(Weather.stat_bonus_for(rock, "evasion"), -5, "pollen")
	assert_eq(Weather.stat_bonus_for(leaf, "evasion"), 0)


# --- Rain douses fire ---------------------------------------------------------------

func test_rain_suppresses_fire_tile_effects() -> void:
	var fire: TileEffectResource = load("res://game/tiles/effects/resources/fire.tres")
	var board := WBoard.new()
	var u := WUnit.new(0, &"", { "health": 100 })
	board.place(u, Vector3i(0, 0, 0))
	board.effects[Vector3i(0, 0, 0)] = [fire]
	var sys := TileEffectSystem.new()
	autofree(sys)
	sys.on_turn_start(u, board)
	var burned := 100 - u.hp
	assert_gt(burned, 0, "fire burns on Clear")
	_set_weather(&"rain")
	sys.on_turn_start(u, board)
	assert_eq(100 - u.hp, burned, "no further burn while it rains")


func test_rain_removes_runtime_fire_from_cells() -> void:
	var fire: TileEffectResource = load("res://game/tiles/effects/resources/fire.tres")
	var trap: TileEffectResource = load("res://game/tiles/effects/resources/vine_trap.tres")
	CombatServices.add_tile_effect(Vector3i(2, 2, 0), fire)
	CombatServices.add_tile_effect(Vector3i(3, 2, 0), trap)
	_set_weather(&"rain")
	assert_eq(CombatServices.applied_tile_effects_at(Vector3i(2, 2, 0)).size(), 0, "the lit fire is doused")
	assert_eq(CombatServices.applied_tile_effects_at(Vector3i(3, 2, 0)).size(), 1, "other effects stay")


# --- Weather-conditioned abilities ---------------------------------------------------

func test_weather_condition() -> void:
	var c := WeatherCondition.new()
	c.weathers = [&"rain"]
	assert_false(c.is_met(null, null), "Clear")
	_set_weather(&"rain")
	assert_true(c.is_met(null, null))
	_set_weather(&"bright_sun")
	assert_false(c.is_met(null, null))


func test_rain_bath_heals_only_in_rain() -> void:
	var rain_bath: AbilityResource = load("res://game/abilities/rain_bath.tres")
	var sys := AbilitySystem.new()
	autofree(sys)
	sys.add_ability(rain_bath)
	var board := WBoard.new()
	var u := WUnit.new(0, &"nature", { "health": 80 })
	u.hp = 40
	board.place(u, Vector3i(0, 0, 0))
	sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, u, board)
	assert_eq(u.hp, 40, "dry: nothing")
	_set_weather(&"rain")
	sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, u, board)
	assert_eq(u.hp, 50, "rain: +1/8 of 80")


func test_sand_veil_and_sunlit_buff_in_their_weather() -> void:
	var veil: AbilityResource = load("res://game/abilities/sand_veil.tres")
	var sunlit: AbilityResource = load("res://game/abilities/sunlit.tres")
	var sys := AbilitySystem.new()
	autofree(sys)
	sys.add_ability(veil)
	sys.add_ability(sunlit)
	var board := WBoard.new()
	var u := WUnit.new(0, &"earth")
	board.place(u, Vector3i(0, 0, 0))
	_set_weather(&"desert_storm")
	sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, u, board)
	assert_eq(u.get_stat("evasion"), 15, "Sand Veil")
	assert_eq(u.get_stat("speed"), 0, "no Sunlit in a storm")
	_set_weather(&"bright_sun")
	sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, u, board)
	assert_eq(u.get_stat("speed"), 4, "Sunlit speed")
	assert_eq(u.get_stat("movement"), 1, "Sunlit movement")


func test_roster_units_carry_their_weather_abilities() -> void:
	var ids := func(path: String) -> Array:
		var out: Array = []
		for a in (load(path) as CharacterResource).abilities:
			out.append(a.id)
		return out
	assert_true(&"rain_bath" in ids.call("res://game/characters/roster/mycothrall.tres"))
	assert_true(&"sunlit" in ids.call("res://game/characters/roster/petalfang.tres"))
	assert_true(&"sand_veil" in ids.call("res://game/characters/roster/gem_knight.tres"))
	var grunt := load("res://game/characters/roster/tree_grunt.tres") as CharacterResource
	assert_eq(grunt.get_move(2).move_id, &"verdant_call")


# --- SetWeatherEffect -------------------------------------------------------------

func test_set_weather_effect_lasts_n_rounds_then_map_weather_resumes() -> void:
	CombatServices.weather.configure({ "mode": "fixed", "weather": "bright_sun" }, 0)
	var eff := SetWeatherEffect.new()
	eff.weather = &"rain"
	eff.rounds = 2
	var board := WBoard.new()
	var u := WUnit.new(0)
	board.place(u, Vector3i(0, 0, 0))
	var changes: Array = []
	var record := func(now, _prev): changes.append(now.id)
	CombatServices.weather_changed.connect(record)
	var ctx := MoveContext.new(u, board, _move(&""), Vector3i.ZERO, [Vector3i.ZERO] as Array[Vector3i])
	eff.apply(ctx)
	assert_eq(Weather.current_id(), &"rain", "summoned")
	assert_eq(ctx.results[0]["effect"], "set_weather")
	assert_eq(CombatServices.weather.override_rounds_left(), 2)
	CombatServices.advance_weather(2)
	assert_eq(Weather.current_id(), &"rain", "still raining in round 2")
	CombatServices.advance_weather(3)
	assert_eq(Weather.current_id(), &"bright_sun", "map weather back at round 3")
	CombatServices.weather_changed.disconnect(record)
	assert_eq(changes, [&"rain", &"bright_sun"])


func test_verdant_call_summons_overbloom() -> void:
	var move: MoveResource = load("res://game/combat/moves/verdant_call.tres")
	var board := WBoard.new()
	var u := WUnit.new(0, &"nature")
	board.place(u, Vector3i(1, 1, 0))
	var res := MoveExecutor.execute(move, u, board, Vector3i(1, 1, 0))
	assert_true(res["success"])
	assert_eq(Weather.current_id(), &"overbloom")
	assert_eq(CombatServices.weather.override_rounds_left(), 3)


# --- Schedules / determinism -------------------------------------------------------

func test_schedule_loops() -> void:
	var s := { "mode": "schedule", "schedule": [{ "weather": "clear", "rounds": 2 }, { "weather": "rain", "rounds": 1 }] }
	var seq: Array = []
	for r in range(1, 8):
		seq.append(WeatherState.base_id_for_round(s, 0, r))
	assert_eq(seq, [&"clear", &"clear", &"rain", &"clear", &"clear", &"rain", &"clear"])


func test_dynamic_is_deterministic_per_seed() -> void:
	var s := { "mode": "dynamic", "weather": "overbloom", "pool": { "rain": 1, "clear": 1, "bright_sun": 1, "desert_storm": 1 }, "change_every": 2 }
	var seq_a: Array = []
	var seq_b: Array = []
	var seq_c: Array = []
	for r in range(1, 41):
		seq_a.append(WeatherState.base_id_for_round(s, 424242, r))
		seq_b.append(WeatherState.base_id_for_round(s, 424242, r))
		seq_c.append(WeatherState.base_id_for_round(s, 99, r))
	assert_eq(seq_a, seq_b, "same seed -> same sequence")
	assert_ne(seq_a, seq_c, "a different seed rolls differently")
	assert_eq(seq_a[0], &"overbloom", "round 1 is the map's starting weather")
	assert_eq(seq_a[1], &"overbloom", "held for change_every rounds")
	for r in range(0, 40, 2):
		assert_eq(seq_a[r], seq_a[r + 1], "changes only on period boundaries")
	var seen := {}
	for id in seq_a.slice(2):
		seen[id] = true
	assert_gt(seen.size(), 1, "the pool actually varies")


func test_state_advance_and_forecast() -> void:
	var st := WeatherState.new()
	st.configure({ "mode": "schedule", "schedule": [{ "weather": "clear", "rounds": 2 }, { "weather": "rain", "rounds": 2 }] }, 0)
	assert_eq(st.current_id(), &"clear")
	assert_eq(st.rounds_until_change(), 2)
	assert_eq(st.next_id(), &"rain")
	assert_false(st.advance_to_round(1), "same round: no-op")
	assert_false(st.advance_to_round(2))
	assert_true(st.advance_to_round(3), "rain begins")
	assert_eq(st.current_id(), &"rain")
	assert_false(st.advance_to_round(2), "never goes backwards")
	assert_eq(st.digest(), ["rain", 3, "", 0])
	var fixed := WeatherState.new()
	fixed.configure({ "mode": "fixed", "weather": "rain" }, 0)
	assert_eq(fixed.rounds_until_change(), -1, "fixed weather never changes")


func test_state_digest_feeds_the_net_digest() -> void:
	CombatServices.weather.configure({ "mode": "fixed", "weather": "rain" }, 7)
	assert_eq(NetGameRules.weather_digest(), ["rain", 1, "", 0])
	var rules := NetGameRules.new(func(): return null, func(): return null, 1)
	var d_rain := rules.state_digest()
	CombatServices.weather.configure({ "mode": "fixed", "weather": "bright_sun" }, 7)
	assert_ne(rules.state_digest(), d_rain, "a weather divergence changes the digest")


# --- Map serialization -----------------------------------------------------------

func test_map_resource_weather_round_trips_through_json() -> void:
	var m := MapResource.new()
	m.map_name = "Wet"
	m.set_weather_settings({ "mode": "dynamic", "weather": "rain", "pool": { "rain": 3, "clear": 1 }, "change_every": 4 })
	var back := MapResource.import_from_json(m.export_to_json())
	assert_not_null(back)
	var s := back.get_weather_settings()
	assert_eq(s["mode"], "dynamic")
	assert_eq(s["weather"], "rain")
	assert_eq(float(s["pool"]["rain"]), 3.0)
	assert_eq(int(s["change_every"]), 4)
	m.set_weather_settings({ "mode": "schedule", "schedule": [{ "weather": "bright_sun", "rounds": 2 }] })
	back = MapResource.import_from_json(m.export_to_json())
	assert_eq(back.weather_mode, "schedule")
	assert_eq(back.weather_schedule[0]["weather"], "bright_sun")
	assert_eq(int(back.weather_schedule[0]["rounds"]), 2)


func test_old_json_without_weather_is_clear() -> void:
	var m := MapResource.new()
	var data: Dictionary = JSON.parse_string(m.export_to_json())
	data.erase("weather")
	var back := MapResource.import_from_json(JSON.stringify(data))
	assert_eq(back.weather_mode, "fixed")
	assert_eq(back.weather, "clear")


func test_map_maker_model_carries_weather() -> void:
	var m := MapResource.new()
	m.width = 3
	m.height = 3
	m.set_weather_settings({ "mode": "fixed", "weather": "desert_storm" })
	var model := MapMakerModel.from_map_resource(m)
	assert_eq(model.weather_settings["weather"], "desert_storm")
	var out := model.to_map_resource()
	assert_eq(out.weather, "desert_storm")


func test_shipped_maps_have_sensible_weather() -> void:
	var forest := load("res://game/maps/resources/forgotten_forest.tres") as MapResource
	assert_eq(forest.weather_mode, "dynamic")
	assert_eq(forest.weather, "overbloom")
	var river := load("res://game/maps/resources/river_crossing.tres") as MapResource
	assert_true(river.weather_pool.has("rain"))
	var cross := load("res://game/maps/resources/elemental_crossroads.tres") as MapResource
	assert_eq(cross.weather_mode, "schedule")
	for path in ["forgotten_forest", "river_crossing", "elemental_crossroads", "castle_siege", "proving_grounds", "skirmish_arena"]:
		var m := load("res://game/maps/resources/%s.tres" % path) as MapResource
		var s := WeatherState.normalize_settings(m.get_weather_settings())
		assert_true(Weather.has_weather(s["weather"]), "%s: known weather" % path)
		for id in s["pool"]:
			assert_true(Weather.has_weather(id), "%s: pool weather %s exists" % [path, id])
		for e in s["schedule"]:
			assert_true(Weather.has_weather(e["weather"]), "%s: schedule weather exists" % path)


# --- Forecast chip ------------------------------------------------------------------

func test_forecast_weather_chip() -> void:
	assert_eq(CombatForecastPanel.weather_chip(_move(&"fire"))[0], "", "Clear: no chip")
	_set_weather(&"bright_sun")
	var c := CombatForecastPanel.weather_chip(_move(&"fire"))
	assert_eq(c[0], "▲ Bright Sun ×1.3")
	assert_true(c[1])
	c = CombatForecastPanel.weather_chip(_move(&"water"))
	assert_eq(c[0], "▼ Bright Sun ×0.8")
	assert_false(c[1])
	_set_weather(&"desert_storm")
	c = CombatForecastPanel.weather_chip(_move(&"", 3))
	assert_eq(c[0], "▼ Desert Storm -15 hit")
	assert_eq(CombatForecastPanel.weather_chip(_move(&"", 1))[0], "", "melee in a storm: no chip")


func test_weather_chip_countdown_text() -> void:
	var st := WeatherState.new()
	st.configure({ "mode": "schedule", "schedule": [{ "weather": "rain", "rounds": 1 }, { "weather": "clear", "rounds": 3 }] }, 0)
	assert_eq(WeatherChip.countdown_text(st), "changes next round")
	st.set_override(&"bright_sun", 3)
	assert_eq(WeatherChip.countdown_text(st), "3 rounds left")
	var fixed := WeatherState.new()
	fixed.configure({ "weather": "rain" }, 0)
	assert_eq(WeatherChip.countdown_text(fixed), "")
