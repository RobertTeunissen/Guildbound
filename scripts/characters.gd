extends RefCounted

const XP := [0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000, 85000, 100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000]
const ASI_LEVELS := [4, 8, 12, 16, 19]
const SLOTS := {
	"weapon": "Weapon", "armor": "Armor", "offhand": "Off hand", "kit": "Field kit",
}
const SKILLS := {
	"Acrobatics": "dex", "Animal Handling": "wis", "Arcana": "int", "Athletics": "str",
	"Deception": "cha", "History": "int", "Insight": "wis", "Intimidation": "cha",
	"Investigation": "int", "Medicine": "wis", "Nature": "int", "Perception": "wis",
	"Performance": "cha", "Persuasion": "cha", "Religion": "int", "Sleight of Hand": "dex",
	"Stealth": "dex", "Survival": "wis",
}
const SPELL_SLOTS := [
	[], [2], [3], [4, 2], [4, 3], [4, 3, 2], [4, 3, 3], [4, 3, 3, 1], [4, 3, 3, 2],
	[4, 3, 3, 3, 1], [4, 3, 3, 3, 2], [4, 3, 3, 3, 2, 1], [4, 3, 3, 3, 2, 1],
	[4, 3, 3, 3, 2, 1, 1], [4, 3, 3, 3, 2, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1],
	[4, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1, 1],
	[4, 3, 3, 3, 3, 1, 1, 1, 1], [4, 3, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 3, 2, 2, 1, 1],
]
const ANCESTRY_TRAITS := {
	"Human": "Versatile upbringing",
	"Wood Elf": "Darkvision 60 ft., Fey Ancestry, Trance, Keen Senses, Fleet of Foot, Mask of the Wild",
	"High Elf": "Darkvision 60 ft., Fey Ancestry, Trance, Keen Senses, Elf Weapon Training",
	"Lightfoot Halfling": "Lucky, Brave, Halfling Nimbleness, Naturally Stealthy",
	"Dwarf (Hill)": "Darkvision 60 ft., Dwarven Resilience, Stonecunning, Dwarven Toughness",
}

var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
var items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))


func new_progress(member: Dictionary) -> Dictionary:
	var profile: Dictionary = data.profiles[member.id]
	var equipped := {}
	for id: String in profile.gear:
		equipped[items[id].slot] = id
	return {"xp": XP[int(member.level) - 1], "increases": {}, "gear": equipped}


func level(xp: int) -> int:
	for index in range(XP.size() - 1, 0, -1):
		if xp >= XP[index]:
			return index + 1
	return 1


func ability_mod(score: int) -> int:
	return floori((score - 10) / 2.0)


func ability_score(member: Dictionary, progress: Dictionary, ability: String) -> int:
	return int(member.scores[ability]) + int(progress.increases.get(ability, 0))


func proficiency(at_level: int) -> int:
	return 2 + floori((at_level - 1) / 4.0)


func remaining_increases(member: Dictionary, progress: Dictionary) -> int:
	var levels := ASI_LEVELS.duplicate()
	levels.append_array(data.classes[member.className].get("extra_asi", []))
	var current := level(progress.xp)
	var points := 0
	for threshold: int in levels:
		if current >= threshold:
			points += 2
	for used: int in progress.increases.values():
		points -= used
	return points


func check_modifier(member: Dictionary, progress: Dictionary, ability: String) -> int:
	var modifier := ability_mod(ability_score(member, progress, ability))
	for item_id: String in progress.gear.values():
		var item: Dictionary = items[item_id]
		if item.get("check", "") == ability:
			modifier += int(item.bonus)
	return modifier


func skill_bonus(member: Dictionary, progress: Dictionary, skill: String) -> int:
	var profile: Dictionary = data.profiles[member.id]
	var current := level(progress.xp)
	var proficient: bool = profile.skills.has(skill)
	var expertise: bool = profile.expertise.has(skill) or (
		member.className == "Rogue" and current >= 6 and skill in ["Investigation", "Perception"]
	)
	return ability_mod(ability_score(member, progress, SKILLS[skill])) + proficiency(current) * (2 if expertise else int(proficient))


func sheet(member: Dictionary, progress: Dictionary) -> Dictionary:
	var profile: Dictionary = data.profiles[member.id]
	var track: Dictionary = data.classes[member.className]
	var current := level(progress.xp)
	var trained := proficiency(current)
	var dex := ability_mod(ability_score(member, progress, "dex"))
	var con := ability_mod(ability_score(member, progress, "con"))
	var hit_die: int = track.hit_die
	var hp := hit_die + con + (current - 1) * maxi(1, floori(hit_die / 2.0) + 1 + con)
	if profile.ancestry == "Dwarf (Hill)":
		hp += current
	var armor: Dictionary = items.get(progress.gear.get("armor", ""), {})
	var armor_class := int(armor.get("ac", 10))
	match armor.get("category", ""):
		"heavy":
			pass
		"medium":
			armor_class += mini(2, dex)
		_:
			armor_class += dex
	if progress.gear.has("offhand"):
		armor_class += int(items[progress.gear.offhand].ac)
	if not armor.is_empty() and member.className == "Fighter":
		armor_class += 1
	var speed: int = profile.speed
	if not profile.ancestry.begins_with("Dwarf") and ability_score(member, progress, "str") < int(armor.get("strength", 0)):
		speed -= 10
	var abilities := {}
	for ability: String in member.scores:
		var score := ability_score(member, progress, ability)
		var saves: bool = track.saves.has(ability) or (member.className == "Rogue" and current >= 15 and ability == "wis")
		abilities[ability] = {"score": score, "modifier": ability_mod(score), "save": ability_mod(score) + trained * int(saves), "save_trained": saves}
	var features: Array[String] = []
	for at_level in range(1, current + 1):
		if track.features.has(str(at_level)):
			features.append("Lv %d · %s" % [at_level, track.features[str(at_level)]])
	var casting := {}
	if track.has("casting"):
		var caster_level := current
		if track.get("half", false):
			caster_level = 0 if current < 2 else ceili(current / 2.0)
		var slots: Array = SPELL_SLOTS[caster_level]
		if not slots.is_empty():
			var modifier: int = abilities[track.casting].modifier
			casting = {"slots": slots, "spells": track.spells.slice(0, slots.size() + 1), "attack": trained + modifier, "dc": 8 + trained + modifier}
	return {
		"level": current, "xp": progress.xp, "next_xp": XP[current] if current < XP.size() else 0,
		"profile": profile, "ancestry_traits": ANCESTRY_TRAITS[profile.ancestry], "abilities": abilities,
		"hp": hp, "ac": armor_class, "speed": speed, "hit_die": hit_die,
		"proficiency": trained, "initiative": dex, "passive_perception": 10 + skill_bonus(member, progress, "Perception"),
		"armor": track.armor, "weapons": _weapon_proficiencies(member), "features": features, "casting": casting,
		"attack": _attack(member, progress, abilities, trained, current),
		"stealth_disadvantage": armor.get("noisy", false),
	}


func _attack(member: Dictionary, progress: Dictionary, abilities: Dictionary, trained: int, current: int) -> Dictionary:
	var item_id: String = progress.gear.get("weapon", "")
	var strength: int = abilities.str.modifier
	if item_id == "":
		return {"name": "Unarmed strike", "to_hit": strength + trained, "damage": "%d bludgeoning" % maxi(0, 1 + strength)}
	var weapon: Dictionary = items[item_id]
	var dexterity: int = abilities.dex.modifier
	var modifier := strength
	if weapon.get("ranged", false):
		modifier = dexterity
	elif weapon.get("finesse", false):
		modifier = maxi(strength, dexterity)
	var weapons := _weapon_proficiencies(member)
	var to_hit := modifier + trained * int(weapons.has(weapon.category) or weapons.has(item_id))
	var magic := int(weapon.get("magic", 0))
	var damage := modifier + magic
	if current >= 2 and member.className == "Ranger" and weapon.get("ranged", false):
		to_hit += 2
	if not weapon.get("ranged", false) and not weapon.get("two_handed", false) and (
		(member.className == "Paladin" and current >= 2) or (member.className == "Fighter" and current >= 10)
	):
		damage += 2
	var dice: String = weapon.damage
	return {"name": weapon.name, "to_hit": to_hit + magic, "damage": "%s%+d %s" % [dice, damage, weapon.damage_type]}


func _weapon_proficiencies(member: Dictionary) -> Array:
	var weapons: Array = data.classes[member.className].weapons.duplicate()
	var ancestry: String = data.profiles[member.id].ancestry
	if not weapons.has("martial") and ancestry in ["Wood Elf", "High Elf"]:
		weapons.append_array(["longsword", "shortsword", "shortbow", "longbow"])
	return weapons


func can_equip(member: Dictionary, progress: Dictionary, item_id: String) -> bool:
	if not items.has(item_id):
		return false
	var item: Dictionary = items[item_id]
	var gear: Dictionary = progress.gear
	match item.slot:
		"weapon":
			return not item.get("two_handed", false) or not gear.has("offhand")
		"armor", "offhand":
			var current_weapon: Dictionary = items.get(gear.get("weapon", ""), {})
			var armor: Array = data.classes[member.className].armor
			return armor.has(item.category) and (item.slot == "armor" or not current_weapon.get("two_handed", false))
		_:
			return true
