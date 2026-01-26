extends Node

# Simple script to test health bar updates by damaging units
# Attach this to the TestVisualSystem scene

func _ready():
	print("Visual damage test ready. Press keys to test:")
	print("1 - Damage Player1/Warrior1 by 20")
	print("2 - Damage Player1/Archer1 by 15") 
	print("3 - Heal Player1/Warrior1 by 10")
	print("4 - Heal Player1/Archer1 by 10")

func _input(event):
	if event.is_action_pressed("ui_accept"):
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_damage_unit("Player1/Warrior1", 20)
			KEY_2:
				_damage_unit("Player1/Archer1", 15)
			KEY_3:
				_heal_unit("Player1/Warrior1", 10)
			KEY_4:
				_heal_unit("Player1/Archer1", 10)

func _damage_unit(unit_path: String, amount: int):
	var unit = get_node("../" + unit_path)
	if unit and unit.has_method("take_damage"):
		print("Damaging " + unit_path + " for " + str(amount) + " damage")
		unit.take_damage(amount)
	else:
		print("Could not find unit: " + unit_path)

func _heal_unit(unit_path: String, amount: int):
	var unit = get_node("../" + unit_path)
	if unit and unit.has_method("heal"):
		print("Healing " + unit_path + " for " + str(amount) + " health")
		unit.heal(amount)
	else:
		print("Could not find unit: " + unit_path)