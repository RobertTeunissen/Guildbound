extends RefCounted

const ROLES := ["captain", "scout"]
const SAVE_VERSION := 1

var scenario: Dictionary
var members: Dictionary = {}
var orders: Dictionary = {}


func _init() -> void:
	scenario = JSON.parse_string(FileAccess.get_file_as_string("res://data/ashford.json"))
	for member: Dictionary in scenario.adventurers:
		members[member.id] = member
	for order: Dictionary in scenario.responses:
		orders[order.id] = order


func fresh() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"party": ["mara", "rowan"],
		"roles": {"captain": "mara", "scout": "rowan"},
		"expedition": {},
	}


func restore(saved: Variant) -> Dictionary:
	return saved if valid_state(saved) else fresh()


func valid_state(state: Variant, version := SAVE_VERSION) -> bool:
	if not state is Dictionary or state.get("version") != version:
		return false
	var party: Variant = state.get("party")
	var roles: Variant = state.get("roles")
	var expedition: Variant = state.get("expedition")
	if not party is Array or party.size() > int(scenario.partySize) or not roles is Dictionary or not expedition is Dictionary:
		return false
	var seen := {}
	for id: Variant in party:
		if not id is String or not members.has(id) or seen.has(id):
			return false
		seen[id] = true
	for role: String in ROLES:
		if not roles.has(role) or (roles[role] != "" and not seen.has(roles[role])):
			return false
	if roles.captain != "" and roles.captain == roles.scout:
		return false
	if expedition.is_empty():
		return true
	var roll: Variant = expedition.get("roll")
	var choice: Variant = expedition.get("choice")
	return ready(state) and roll is int and roll >= 1 and roll <= 20 and choice is String and (choice == "" or not _order(state, choice).is_empty())


func toggle_member(state: Dictionary, id: String) -> bool:
	if not state.expedition.is_empty() or not members.has(id):
		return false
	if state.party.has(id):
		state.party.erase(id)
		for role: String in ROLES:
			if state.roles[role] == id:
				state.roles[role] = ""
		return true
	if state.party.size() == int(scenario.partySize):
		return false
	state.party.append(id)
	return true


func assign(state: Dictionary, role: String, id: String) -> bool:
	if not state.expedition.is_empty() or not ROLES.has(role) or (id != "" and not state.party.has(id)):
		return false
	var other := "scout" if role == "captain" else "captain"
	if id != "" and state.roles[other] == id:
		state.roles[other] = state.roles[role]
	state.roles[role] = id
	return true


func ready(state: Dictionary) -> bool:
	return state.party.size() == int(scenario.partySize) and state.roles.captain != "" and state.roles.scout != ""


func support_id(state: Dictionary) -> String:
	if ready(state):
		for id: String in state.party:
			if id != state.roles.captain and id != state.roles.scout:
				return id
	return ""


func depart(state: Dictionary, roll: int) -> bool:
	if not ready(state) or not state.expedition.is_empty() or roll < 1 or roll > 20:
		return false
	state.expedition = {"roll": roll, "choice": ""}
	return true


func record(state: Dictionary, order_id: String) -> bool:
	if state.expedition.is_empty() or state.expedition.choice != "" or _order(state, order_id).is_empty():
		return false
	state.expedition.choice = order_id
	return true


func bonds(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for first_index in state.party.size():
		for second_index in range(first_index + 1, state.party.size()):
			var pair := [state.party[first_index], state.party[second_index]]
			var bond := {"pair": pair, "trust": 0, "history": "No shared field experience yet."}
			for known: Dictionary in scenario.initialBonds:
				if known.pair.has(pair[0]) and known.pair.has(pair[1]):
					bond.trust = int(known.trust)
					bond.history = known.history
					break
			var key := bond_key(pair)
			var learned: Dictionary = state.get("trust", {}).get(key, {})
			if not learned.is_empty():
				bond.trust = learned.value
				bond.history = learned.history
			result.append(bond)
	return result


func bond_key(pair: Array) -> String:
	var sorted := pair.duplicate()
	sorted.sort()
	return "%s/%s" % [sorted[0], sorted[1]]


func _lead_pair(state: Dictionary, pair: Array) -> bool:
	return pair.has(state.roles.captain) and pair.has(state.roles.scout)


func chemistry(state: Dictionary) -> int:
	var shared := 0
	var lead_bonus := 0
	for bond in bonds(state):
		shared += int(bond.trust)
		if _lead_pair(state, bond.pair) and bond.trust >= 3:
			lead_bonus = 1
	return floori(shared / 3.0) + lead_bonus


func _order(state: Dictionary, order_id: String) -> Dictionary:
	if not state.expedition.has("quest"):
		return orders.get(order_id, {})
	var quest: Variant = state.expedition.quest
	if not quest is Dictionary or not quest.get("responses") is Array:
		return {}
	for order: Variant in quest.responses:
		if order is Dictionary and order.get("id") == order_id:
			return order
	return {}


func check(state: Dictionary, order_id: String) -> Dictionary:
	return check_plan(state, _order(state, order_id))


func check_plan(state: Dictionary, order: Dictionary) -> Dictionary:
	var roles := [
		["Captain", state.roles.captain, order.leadAbility],
		["Scout", state.roles.scout, order.scoutAbility],
		["Support", support_id(state), order.supportAbility],
	]
	var bond_bonus := chemistry(state)
	var bonus := bond_bonus
	var contributions: Array[Dictionary] = []
	for role: Array in roles:
		var member: Dictionary = members[role[1]]
		var ability: String = role[2]
		var modifier := _ability_modifier(state, member, ability)
		contributions.append({"role": role[0], "name": member.name, "ability": ability, "modifier": modifier})
		bonus += modifier
	return {"contributions": contributions, "chemistry": bond_bonus, "bonus": bonus, "dc": int(order.dc)}


func _ability_modifier(_state: Dictionary, member: Dictionary, ability: String) -> int:
	return floori((float(member.scores[ability]) - 10.0) / 2.0)


func success_chance(state: Dictionary, order: Dictionary) -> int:
	var plan := check_plan(state, order)
	return clampi(21 + int(plan.bonus) - int(plan.dc), 0, 20) * 5


func debrief(state: Dictionary, order_id: String = "") -> Dictionary:
	if state.expedition.is_empty():
		return {}
	var choice: String = order_id if order_id != "" else state.expedition.choice
	var order := _order(state, choice)
	if order.is_empty():
		return {}
	var resolution := check_plan(state, order)
	var roll: int = state.expedition.roll
	var total := roll + int(resolution.bonus)
	var success := total >= int(resolution.dc)
	var outcome := 0 if success else 1
	var relationships := bonds(state)
	for bond in relationships:
		var change := int(order.trust[outcome]) if _lead_pair(state, bond.pair) else int(success)
		bond.after = clampi(int(bond.trust) + change, -3, 5)
		bond.change = bond.after - bond.trust
	var prospects: Array[String] = []
	for id: String in state.party:
		if members[id].get("prospect", false):
			prospects.append(members[id].name)
	return {
		"order": order, "roll": roll, "check": resolution, "total": total, "success": success,
		"bonds": relationships, "story": order.success if success else order.failure,
		"gold": int(order.gold[outcome]), "standing": int(order.standing[outcome]), "prospects": prospects,
	}
