extends GutTest

## SHOPS AND MERCHANTS in story mode (docs/design/DECISIONS.md #28), booted for real (the shipped
## Crownhaven / Mossway content on OverworldScene.tscn): talk to the Crownhaven merchant across her
## stall -> the shop screen -> buy tonics (gold drops, the bag gains them, "Not enough gold" for
## the dear ones) -> leave (the journey is saved) -> use a tonic from Journey -> Bag on a hurt
## member (HP rises; the button is disabled on a full-HP member) -> sell the other one back. Also:
## the travelling merchant on the Mossway only after the opening, and an old save with no shop
## bookkeeping continuing. Animations off; scene changes off; saves to a temp dir.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const TEMP_DIR := "user://test_story_shops/"

var _guard
var _world: Node = null
var _prev_scene: Node = null


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()
	StoryController.scene_changes_enabled = false


func after_each() -> void:
	_teardown()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


func _boot(area: String, cell: Vector3i, facing: String) -> OverworldController:
	if not StoryController.has_session():
		StoryController.new_journey(1)
		StoryFixture.past_opening(StoryController.state())
	var s: StoryState = StoryController.state()
	if area != s.location_area():
		s.on_area_changed()
	s.set_location(area, cell, facing)
	_teardown()
	var w: Node = OVERWORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(w)
	get_tree().current_scene = w
	_world = w
	await get_tree().process_frame
	await get_tree().process_frame
	return w as OverworldController


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = _prev_scene
		_world.get_parent().remove_child(_world)
		_world.free()
	_world = null


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## Talk to whoever is across the counter and read the greeting through, until the shop is up.
func _open_shop(ow: OverworldController) -> ShopScreen:
	assert_true(ow.interact(), "Confirm talks to the merchant")
	for i in range(300):
		await get_tree().process_frame
		if ow.shop_screen != null and ow.shop_screen.is_open():
			return ow.shop_screen
		var d: StoryDialogue = ow.dialogue()
		if d != null and d.root_control().visible:
			d.skip()
	return null


func _leave(ow: OverworldController, shop: ShopScreen) -> void:
	shop.close()
	for i in range(60):
		await get_tree().process_frame
		if not StoryController.is_script_running():
			return


func test_buy_use_and_sell_back_at_the_crownhaven_merchant() -> void:
	# In front of the merchant at the end of the green-awning stall.
	var ow := await _boot("crownhaven", Vector3i(20, 13, 0), "north")
	var s: StoryState = StoryController.state()
	assert_eq(s.gold, 100, "a new journey's purse")
	var target: OverworldEntity = ow.entity_at(ow.faced_cell())
	assert_true(target is ShopEntity, "the hero faces the merchant")
	assert_eq(String(target.id), "merchant", "the Crownhaven merchant")
	assert_true(ow.hud.prompt_text().ends_with("Shop"), "the prompt says Shop (%s)" % ow.hud.prompt_text())

	var shop := await _open_shop(ow)
	assert_not_null(shop, "talking opens the shop screen")
	if shop == null:
		return
	assert_true(ow.is_input_blocked(), "the overworld is paused while the shop is open")
	assert_true(get_tree().get_nodes_in_group(InputActions.OVERLAY_GROUP).size() > 0, "a modal overlay")
	assert_not_null(shop.row("mossleaf_tonic"), "tonics are for sale")
	assert_null(shop.row("sunstone"), "no evolution items (DECISIONS.md #28 revision)")

	# Too dear first.
	assert_true(shop.select("dawnpetal_draught"), "the revive is listed")
	var r: Dictionary = shop.confirm()
	assert_eq(String(r["reason"]), ShopLedger.REASON_NOT_ENOUGH_GOLD, "250 gold on a 100-gold purse")
	assert_eq(shop.message(), "Not enough gold.", "the screen says so")
	assert_eq(s.gold, 100, "nothing spent")

	# Two tonics: the quantity picker (keyboard right on the row), then confirm.
	shop.select("mossleaf_tonic")
	shop.row("mossleaf_tonic").grab_focus()
	var right := InputEventAction.new()
	right.action = &"ui_right"
	right.pressed = true
	get_viewport().push_input(right)
	await _frames(1)
	assert_eq(shop.quantity, 2, "right raises the quantity")
	r = shop.confirm()
	assert_true(bool(r["ok"]), "bought")
	assert_eq(s.gold, 20, "gold drops by 2 x 40")
	assert_eq(s.item_count("mossleaf_tonic"), 2, "the bag gains two tonics")
	assert_true(shop.message().begins_with("Bought Mossleaf Tonic"), "a receipt line")
	await _leave(ow, shop)
	assert_false(StoryController.is_script_running(), "leaving the shop ends the merchant's script")
	assert_false(ow.is_input_blocked(), "the overworld takes input again")
	assert_eq(int(StorySaveManager.peek(1)["gold"]), 20, "leaving saved the journey")

	# Use one from Journey -> Bag on a hurt member.
	var vine: StoryPartyMember = s.member("vineweave")
	var blight: StoryPartyMember = s.member("blightcap")
	vine.current_hp = 50
	ow.open_journey_menu()
	var jm: JourneyMenu = ow.journey
	jm.show_bag()
	var card: Node = jm.find_child("Item_mossleaf_tonic", true, false)
	assert_not_null(card, "the tonic is in the bag")
	var on_blight := card.find_child("Use_blightcap", true, false) as Button
	assert_true(on_blight.disabled, "a full-HP member's button is disabled: a heal is never wasted")
	var on_vine := card.find_child("Use_vineweave", true, false) as Button
	assert_false(on_vine.disabled, "the hurt member's is not")
	on_vine.pressed.emit()
	await _frames(2)
	assert_eq(vine.current_hp, 75, "HP rises by 25")
	assert_eq(s.item_count("mossleaf_tonic"), 1, "one tonic spent")
	assert_true(blight.is_full_hp(), "the other member untouched")
	var direct: Dictionary = await StoryController.use_item_on_member("mossleaf_tonic", "blightcap")
	assert_eq(String(direct["reason"]), "full_hp", "the one use-an-item flow refuses a wasted heal")
	assert_eq(s.item_count("mossleaf_tonic"), 1, "and keeps the tonic")
	jm.close()
	await _frames(1)

	# Sell the other back.
	shop = await _open_shop(ow)
	assert_not_null(shop, "the shop opens again")
	if shop == null:
		return
	shop.switch_tab(ShopScreen.TAB_SELL)
	assert_true(shop.select("mossleaf_tonic"), "the tonic is on the sell list")
	r = shop.confirm()
	assert_true(bool(r["ok"]), "sold")
	assert_eq(s.gold, 40, "at half price: 20 + 20")
	assert_eq(s.item_count("mossleaf_tonic"), 0, "the bag is empty of tonics")
	await _leave(ow, shop)


func test_limited_stock_is_saved_and_restocks_after_a_rest() -> void:
	var ow := await _boot("crownhaven", Vector3i(20, 13, 0), "north")
	var s: StoryState = StoryController.state()
	s.gold = 2000
	var shop := await _open_shop(ow)
	if shop == null:
		fail_test("the shop did not open")
		return
	shop.select("dawnpetal_draught")
	shop.set_quantity(5)
	assert_eq(shop.quantity, 2, "the quantity picker stops at the stock limit")
	assert_true(bool(shop.confirm()["ok"]), "both revives bought")
	shop.select("dawnpetal_draught")
	assert_eq(String(shop.confirm()["reason"]), ShopLedger.REASON_SOLD_OUT, "sold out")
	await _leave(ow, shop)
	var saved: Dictionary = StorySaveManager.peek(1)
	assert_eq(int(saved["shops"]["crownhaven_general"]["sold"]["dawnpetal_draught"]), 2,
		"the merchant's stock is in the save")
	var loaded: StoryState = StorySaveManager.load_state(1)["state"]
	var general := ShopResource.load_by_id("crownhaven_general")
	assert_eq(ShopLedger.remaining(general, loaded, general.entry("dawnpetal_draught")), 0, "still sold out after a reload")
	loaded.heal_party()
	assert_eq(ShopLedger.remaining(general, loaded, general.entry("dawnpetal_draught")), 2, "a Wayshrine rest restocks")


func test_the_travelling_merchant_waits_for_the_end_of_the_opening() -> void:
	var moss := StoryController.load_area("mossway")
	var pedlar := moss.entity("pedlar")
	assert_true(pedlar is ShopEntity, "the Mossway has a travelling merchant")
	assert_eq(String((pedlar as ShopEntity).shop.id), "mossway_pedlar", "selling from his cart")
	var s := StoryState.new()
	assert_false(pedlar.is_present(s), "not on the road during the opening")
	StoryFixture.past_opening(s)
	assert_true(pedlar.is_present(s), "there once the opening is over")
	for area_id in ["crownhaven", "mossway"]:
		var issues: Array[String] = StoryController.load_area(area_id).validate()
		assert_eq(issues.size(), 0, "%s validates: %s" % [area_id, str(issues)])


func test_an_old_save_without_shop_data_continues() -> void:
	StoryController.new_journey(1)
	StoryFixture.past_opening(StoryController.state())
	StoryController.state().add_item("mossleaf_tonic", 1)
	StoryController.save_game()
	var path: String = StorySaveManager.slot_path(1)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.erase("shops")
	data.erase("rests")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	StoryController.end_session()
	var r: Dictionary = StoryController.continue_journey(1)
	assert_true(bool(r["success"]), "the older save continues")
	var s: StoryState = StoryController.state()
	assert_true(s.shops.is_empty(), "no shop bookkeeping: every merchant fully stocked")
	assert_eq(s.rests, 0, "no rests counted")
	assert_eq(s.item_count("mossleaf_tonic"), 1, "the bag is intact")
