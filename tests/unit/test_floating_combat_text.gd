extends GutTest

## Floating combat text (game/visuals/FloatingCombatText.gd): the pure pairing logic
## (CombatTextPairer), the popup wording, the battle-log wording, and that EVERY
## HP-changing source emits a GameEvents.combat_text_annotated context event.

# --- Mocks -------------------------------------------------------------------

class CUnit:
	var team: int
	var element: StringName
	var stats: Dictionary
	var hp: int
	var max_health: int
	var tags: Array = []
	var character_resource = null
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
	func is_alive() -> bool:
		return hp > 0
	func take_damage(n: int) -> void:
		hp = maxi(0, hp - n)
	func heal(n: int) -> void:
		hp = mini(max_health, hp + n)
	func add_stat_modifier(stat: String, amount: int, _duration: int = -1) -> int:
		stats[stat] = int(stats.get(stat, 0)) + amount
		return 0


class CBoard:
	var cells: Dictionary = {}
	var effects: Dictionary = {}
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


var _events: Array = []


func before_each() -> void:
	CombatServices.clear()
	_events.clear()
	GameEvents.combat_text_annotated.connect(_record)


func after_each() -> void:
	if GameEvents.combat_text_annotated.is_connected(_record):
		GameEvents.combat_text_annotated.disconnect(_record)
	CombatServices.clear()


func _record(unit, info) -> void:
	_events.append({ "unit": unit, "info": info })


func _events_for(unit) -> Array:
	return _events.filter(func(e): return e["unit"] == unit).map(func(e): return e["info"])


func _set_weather(id: StringName) -> void:
	CombatServices.weather.configure({ "mode": "fixed", "weather": String(id) }, 0)


func _move(accuracy: float = 1.0, crit: float = 0.0, lifesteal: float = 0.0) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_strike"
	m.display_name = "Test Strike"
	m.accuracy = accuracy
	m.crit_chance = crit
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 1
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	var d := DamageEffect.new()
	d.power = 20
	d.scaling_stat = ""
	d.lifesteal = lifesteal
	m.effects = [d]
	return m


func _duel() -> Array:
	var board := CBoard.new()
	var caster := CUnit.new(0)
	var target := CUnit.new(1)
	board.place(caster, Vector3i(0, 0, 0))
	board.place(target, Vector3i(1, 0, 0))
	return [board, caster, target]


func _exec(move: MoveResource, d: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	MoveExecutor.execute(move, d[1], d[0], Vector3i(1, 0, 0), rng)


# --- Pairing logic ---------------------------------------------------------------

func test_annotated_damage_pairs_with_the_hp_change() -> void:
	var p := CombatTextPairer.new()
	var u := CUnit.new(0)
	p.annotate(u, { "kind": CombatText.KIND_DAMAGE, "amount": 12, "crit": true,
		"effectiveness": 1.5, "source_kind": CombatText.SRC_ATTACK })
	var e := p.on_health_changed(u, 100, 88)
	assert_eq(e["kind"], CombatTextPairer.ENTRY_DAMAGE)
	assert_eq(e["amount"], 12)
	assert_true(e["crit"], "crit carried over")
	assert_eq(e["effectiveness"], 1.5)
	assert_false(e["plain"])
	assert_false(p.has_pending(), "annotation consumed")
	assert_eq(p.flush().size(), 0, "nothing left for end of frame")


func test_unannotated_hp_change_is_a_plain_number() -> void:
	var p := CombatTextPairer.new()
	var u := CUnit.new(0)
	var e := p.on_health_changed(u, 50, 43)
	assert_eq(e["kind"], CombatTextPairer.ENTRY_DAMAGE)
	assert_eq(e["amount"], 7)
	assert_true(e["plain"])
	var h := p.on_health_changed(u, 43, 48)
	assert_eq(h["kind"], CombatTextPairer.ENTRY_HEAL)
	assert_eq(h["amount"], 5)
	assert_true(p.on_health_changed(u, 48, 48).is_empty(), "no change, no entry")


func test_miss_is_shown_at_end_of_frame() -> void:
	var p := CombatTextPairer.new()
	var u := CUnit.new(0)
	p.annotate(u, { "kind": CombatText.KIND_MISS, "amount": 0 })
	var out := p.flush()
	assert_eq(out.size(), 1)
	assert_eq(out[0]["kind"], CombatTextPairer.ENTRY_MISS)
	assert_false(p.has_pending())


func test_heal_pairs_with_heal_and_keeps_its_source() -> void:
	var p := CombatTextPairer.new()
	var u := CUnit.new(0)
	p.annotate(u, { "kind": CombatText.KIND_HEAL, "amount": 16, "source": "Regrowth",
		"source_kind": CombatText.SRC_WEATHER, "weather": "Overbloom", "weather_fx": &"bloom" })
	var e := p.on_health_changed(u, 100, 110)  # clamped at max: shows what was restored
	assert_eq(e["kind"], CombatTextPairer.ENTRY_HEAL)
	assert_eq(e["amount"], 10)
	assert_eq(e["source"], "Regrowth")
	assert_eq(e["weather_fx"], &"bloom")
	# A heal into full HP never changes HP: nothing is shown for it.
	p.annotate(u, { "kind": CombatText.KIND_HEAL, "amount": 16 })
	assert_eq(p.flush().size(), 0)


func test_shield_partial_and_full_block() -> void:
	var p := CombatTextPairer.new()
	var u := CUnit.new(0)
	# 20 incoming, 15 shield: 5 reaches HP.
	p.annotate(u, { "kind": CombatText.KIND_DAMAGE, "amount": 20 }, 15)
	var e := p.on_health_changed(u, 100, 95, 0)
	assert_eq(e["amount"], 5)
	assert_eq(e["blocked"], 15)
	# 8 incoming, 15 shield: nothing reaches HP -> "Blocked 8" at end of frame.
	p.annotate(u, { "kind": CombatText.KIND_DAMAGE, "amount": 8 }, 15)
	var out := p.flush(func(_u): return 7)
	assert_eq(out.size(), 1)
	assert_eq(out[0]["kind"], CombatTextPairer.ENTRY_BLOCKED)
	assert_eq(out[0]["blocked"], 8)


func test_multiple_hits_in_one_frame_pair_in_order() -> void:
	var p := CombatTextPairer.new()
	var a := CUnit.new(0)
	var b := CUnit.new(1)
	p.annotate(a, { "kind": CombatText.KIND_DAMAGE, "amount": 5, "source": "Fire" })
	p.annotate(a, { "kind": CombatText.KIND_DAMAGE, "amount": 9, "source": "Poisoned" })
	p.annotate(b, { "kind": CombatText.KIND_MISS })
	p.annotate(a, { "kind": CombatText.KIND_HEAL, "amount": 3, "source": "Rain Bath" })
	assert_eq(p.on_health_changed(a, 100, 95)["source"], "Fire")
	assert_eq(p.on_health_changed(a, 95, 86)["source"], "Poisoned")
	assert_eq(p.on_health_changed(a, 86, 89)["source"], "Rain Bath")
	var out := p.flush()
	assert_eq(out.size(), 1, "only b's miss is left")
	assert_eq(out[0]["unit"], b)


func test_invulnerable_is_immune() -> void:
	var p := CombatTextPairer.new()
	var u := CUnit.new(0)
	p.annotate(u, { "kind": CombatText.KIND_NEGATED })
	assert_eq(p.flush()[0]["kind"], CombatTextPairer.ENTRY_IMMUNE)


# --- Wording -----------------------------------------------------------------------

func test_popup_texts() -> void:
	var crit := FloatingCombatText.texts_for({ "kind": &"damage", "amount": 31, "crit": true })
	assert_eq(crit["main"], "31")
	assert_eq(crit["tag"], "CRIT!")
	var eff := FloatingCombatText.texts_for({ "kind": &"damage", "amount": 9, "effectiveness": 1.5 })
	assert_string_contains(eff["tag"], "Effective")
	var res := FloatingCombatText.texts_for({ "kind": &"damage", "amount": 9, "effectiveness": 0.75 })
	assert_string_contains(res["tag"], "Resisted")
	assert_eq(FloatingCombatText.texts_for({ "kind": &"heal", "amount": 4 })["main"], "+4")
	assert_eq(FloatingCombatText.texts_for({ "kind": &"miss" })["main"], "MISS")
	assert_eq(FloatingCombatText.texts_for({ "kind": &"blocked", "blocked": 6 })["main"], "Blocked 6")
	var fire := FloatingCombatText.texts_for({ "kind": &"damage", "amount": 15, "source": "Fire",
		"source_kind": CombatText.SRC_TILE, "source_id": &"fire" })
	assert_eq(fire["source"], "Fire")


func test_battle_log_names_non_attack_sources() -> void:
	assert_eq(BattleLog.damage_line("Barkling", 15, { "source": "Fire", "source_id": &"fire",
		"source_kind": CombatText.SRC_TILE }), "Barkling burned for 15")
	assert_eq(BattleLog.damage_line("Vineweave", 7, { "source": "Scouring Sand",
		"weather": "Desert Storm", "source_kind": CombatText.SRC_WEATHER }),
		"Vineweave took 7 from Scouring Sand (Desert Storm)")
	assert_eq(BattleLog.damage_line("Torvald", 4, { "source": "Poisoned",
		"source_kind": CombatText.SRC_STATUS, "source_id": &"poisoned" }), "Torvald took 4 from Poisoned")


# --- Every damage / heal source annotates -----------------------------------------

func test_attack_annotates_damage_and_crit() -> void:
	var d := _duel()
	_exec(_move(1.0, 1.0), d)
	var ev := _events_for(d[2])
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["kind"], CombatText.KIND_DAMAGE)
	assert_eq(ev[0]["source_kind"], CombatText.SRC_ATTACK)
	assert_true(ev[0]["crit"])
	assert_eq(ev[0]["amount"], d[2].max_health - d[2].hp, "annotated amount == HP lost")


func test_attack_miss_annotates_miss() -> void:
	var d := _duel()
	_exec(_move(0.0), d)
	var ev := _events_for(d[2])
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["kind"], CombatText.KIND_MISS)
	assert_eq(d[2].hp, d[2].max_health)


func test_lifesteal_annotates_a_heal_on_the_caster() -> void:
	var d := _duel()
	d[1].hp = 100
	_exec(_move(1.0, 0.0, 0.5), d)
	var ev := _events_for(d[1])
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["kind"], CombatText.KIND_HEAL)
	assert_eq(ev[0]["source_kind"], CombatText.SRC_LIFESTEAL)


func test_fire_tile_annotates_with_its_source() -> void:
	var board := CBoard.new()
	var u := CUnit.new(0)
	var cell := Vector3i(2, 2, 0)
	board.place(u, cell)
	board.effects[cell] = [load("res://game/tiles/effects/resources/fire.tres")]
	var sys := TileEffectSystem.new()
	sys.on_turn_start(u, board)
	sys.free()
	var ev := _events_for(u)
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["kind"], CombatText.KIND_DAMAGE)
	assert_eq(ev[0]["source_kind"], CombatText.SRC_TILE)
	assert_eq(ev[0]["source"], "Fire")
	assert_eq(ev[0]["source_id"], &"fire")


func test_sandstorm_chip_annotates_with_weather() -> void:
	_set_weather(&"desert_storm")
	var board := CBoard.new()
	var u := CUnit.new(0, &"nature")
	board.place(u, Vector3i(0, 0, 0))
	Weather.run_turn_start(u, board)
	var ev := _events_for(u)
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["kind"], CombatText.KIND_DAMAGE)
	assert_eq(ev[0]["source_kind"], CombatText.SRC_WEATHER)
	assert_eq(ev[0]["weather"], "Desert Storm")
	assert_eq(ev[0]["amount"], 10, "1/16 of 160")


func test_overbloom_regrowth_annotates_a_heal() -> void:
	_set_weather(&"overbloom")
	var board := CBoard.new()
	var u := CUnit.new(0, &"nature")
	u.hp = 50
	board.place(u, Vector3i(0, 0, 0))
	Weather.run_turn_start(u, board)
	var ev := _events_for(u)
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["kind"], CombatText.KIND_HEAL)
	assert_eq(ev[0]["source"], "Regrowth")
	assert_eq(ev[0]["weather"], "Overbloom")


func test_rain_bath_annotates_a_heal_with_the_ability_name() -> void:
	var board := CBoard.new()
	var u := CUnit.new(0)
	u.hp = 40
	board.place(u, Vector3i(0, 0, 0))
	var ability: AbilityResource = load("res://game/abilities/rain_bath.tres")
	ability.run_effects(u, board)
	var ev := _events_for(u)
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["kind"], CombatText.KIND_HEAL)
	assert_eq(ev[0]["source_kind"], CombatText.SRC_ABILITY)
	assert_eq(ev[0]["source"], "Rain Bath")


func test_poison_tick_annotates_with_the_status() -> void:
	var board := CBoard.new()
	var u := CUnit.new(0)
	board.place(u, Vector3i(0, 0, 0))
	var poison: StatusCondition = load("res://game/combat/status/poisoned.tres")
	poison.tick(u, board)
	var ev := _events_for(u)
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["source_kind"], CombatText.SRC_STATUS)
	assert_eq(ev[0]["source"], "Poisoned")
	assert_eq(u.max_health - u.hp, int(ev[0]["amount"]))


func test_traveling_hazard_annotates_with_the_move_name() -> void:
	var board := CBoard.new()
	var caster := CUnit.new(0)
	var victim := CUnit.new(1)
	board.place(caster, Vector3i(0, 0, 0))
	board.place(victim, Vector3i(1, 0, 0))
	var hz := TravelingHazard.new(Vector3i(0, 0, 0), Vector3i(1, 0, 0), 2, 2, 6, 12,
		CombatTypes.DamageCategory.PHYSICAL, CombatTypes.TargetKind.ENEMY, caster)
	hz.label = "Forest Barrage"
	hz.advance(board)
	var ev := _events_for(victim)
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["source_kind"], CombatText.SRC_HAZARD)
	assert_eq(ev[0]["source"], "Forest Barrage")
	assert_eq(ev[0]["amount"], 12)


func test_floating_text_node_pairs_a_live_unit_hp_change() -> void:
	var fct := FloatingCombatText.new()
	add_child_autofree(fct)
	var shown: Array = []
	# Intercept entries through the pairer directly (no camera in the headless test).
	var u := CUnit.new(0)
	fct._on_annotated(u, { "kind": CombatText.KIND_DAMAGE, "amount": 6, "source": "Fire",
		"source_kind": CombatText.SRC_TILE, "source_id": &"fire" })
	shown.append(fct.pairer.on_health_changed(u, 30, 24))
	assert_eq(shown[0]["source"], "Fire")
	assert_eq(shown[0]["amount"], 6)
