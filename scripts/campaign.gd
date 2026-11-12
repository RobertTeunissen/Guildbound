extends "res://scripts/expedition.gd"

const QuestBoard = preload("res://scripts/quest_board.gd")
const Characters = preload("res://scripts/characters.gd")
const DAY_SECONDS := 10.0
const SCOUT_DAYS := 2
const RIVALS := ["the Copper Lanterns", "the Briar Company"]
const CAMPAIGN_VERSION := 3
const DEFAULT_CHARTER := {"name": "The Alder Company", "motto": "", "terms": ""}

var board := QuestBoard.new()
var characters := Characters.new()
var founding_ids: Array[String] = []


func _init() -> void:
	super()
	for member: Dictionary in scenario.adventurers:
		founding_ids.append(member.id)
	for member: Dictionary in characters.data.recruits:
		members[member.id] = member


func fresh() -> Dictionary:
	var state := super.fresh()
	state.version = CAMPAIGN_VERSION
	state.party = []
	state.roles = {"captain": "", "scout": ""}
	state.merge({
		"day": 1, "paused": true, "offers": [], "journal": [], "notices": [],
		"treasury": 120, "standing": 0, "trust": {}, "next_offer": 1,
		"next_site": 0, "site_visits": {}, "seen_titles": {}, "chartered": false,
		"charter": DEFAULT_CHARTER.duplicate(), "guild_roster": [],
		"character_progress": {}, "stash": {}, "patron_standings": {}, "questlines": {},
		"scouting": {}, "candidates": [],
	})
	return state


func restore(saved: Variant) -> Dictionary:
	if valid_state(saved, CAMPAIGN_VERSION):
		return saved
	if not valid_state(saved) and not valid_state(saved, 2):
		return fresh()
	var migrated: Dictionary = saved
	migrated.merge(fresh())
	migrated.version = CAMPAIGN_VERSION
	migrated.chartered = true
	for id: String in founding_ids:
		_add_member(migrated, id)
	for entry: Dictionary in migrated.journal:
		var patron: String = contract(entry.run).get("patron", "")
		if patron != "":
			_add_standing(migrated, patron, int(debrief(entry.run).get("standing", 0)))
	return migrated


func save_charter(state: Dictionary, draft: Dictionary) -> bool:
	var guild_name: String = draft.name.strip_edges()
	if guild_name.is_empty() or guild_name.length() > 40:
		return false
	state.charter = {"name": guild_name, "motto": draft.motto.strip_edges().left(80), "terms": draft.terms.strip_edges().left(800)}
	return true


func found_guild(state: Dictionary, draft: Dictionary, founders: Array) -> bool:
	if state.chartered or founders.size() != int(scenario.partySize):
		return false
	var seen := {}
	for id: String in founders:
		if not founding_ids.has(id) or seen.has(id):
			return false
		seen[id] = true
	if not save_charter(state, draft):
		return false
	for id: String in founders:
		_add_member(state, id)
	state.party = founders.duplicate()
	state.roles = {"captain": founders[0], "scout": founders[1]}
	state.chartered = true
	board.fill(state)
	return true


func _add_member(state: Dictionary, id: String) -> void:
	state.guild_roster.append(id)
	state.character_progress[id] = characters.new_progress(members[id])


func open_session(state: Dictionary) -> void:
	state.paused = true
	state.offers.clear()
	if not state.chartered:
		return
	# The first prototype saved a fixed Ashford expedition without calendar phases.
	if not state.expedition.is_empty() and not state.expedition.has("quest"):
		state.expedition.phase = "decision"
		if state.expedition.choice != "":
			_archive(state)
	board.fill(state)


func toggle_member(state: Dictionary, id: String) -> bool:
	return state.guild_roster.has(id) and super.toggle_member(state, id)


func can_leave(state: Dictionary) -> bool:
	return state.chartered and ready(state) and state.expedition.is_empty() and not state.party.has(state.scouting.get("member", ""))


func accept(state: Dictionary, id: String, roll: int) -> bool:
	var quest := board.by_id(state, id)
	if not can_leave(state) or quest.is_empty() or state.day >= quest.deadline or not depart(state, roll):
		return false
	state.offers.erase(quest)
	var loadout := {}
	for member_id: String in state.party:
		loadout[member_id] = state.character_progress[member_id].duplicate(true)
	var local: bool = quest.travel == 0
	state.expedition.merge({
		"quest": quest, "departed_day": state.day, "loadout": loadout,
		"phase": "decision" if local else "outbound", "due_day": state.day + quest.travel,
	})
	if local:
		state.paused = true
	board.fill(state)
	return true


func choose_plan(state: Dictionary, order_id: String) -> bool:
	if state.expedition.get("phase") != "decision" or not record(state, order_id):
		return false
	if not state.expedition.has("quest"):
		_archive(state)
		return true
	state.expedition.phase = "work"
	state.expedition.due_day = state.day + state.expedition.quest.work
	return true


func advance_day(state: Dictionary) -> bool:
	if state.paused or not state.chartered:
		return false
	state.day += 1
	_expire_offers(state)
	_finish_scouting(state)
	var trip: Dictionary = state.expedition
	if trip.is_empty() or trip.phase == "decision" or state.day < trip.due_day:
		return true
	match trip.phase:
		"outbound":
			trip.phase = "decision"
			state.paused = true
		"work":
			if trip.quest.travel == 0:
				_finish_expedition(state)
			else:
				trip.phase = "return"
				trip.due_day = state.day + trip.quest.travel
		"return":
			_finish_expedition(state)
	return true


func _finish_expedition(state: Dictionary) -> void:
	_archive(state)
	state.paused = true
	board.fill(state)


func _expire_offers(state: Dictionary) -> void:
	for offer: Dictionary in state.offers.duplicate():
		if state.day < offer.deadline:
			continue
		state.offers.erase(offer)
		var number := int(offer.id)
		var note := "%s completed the job." % RIVALS[number % RIVALS.size()]
		if offer.has("line"):
			note = "The lead went cold. Ask around again tomorrow."
			state.questlines[offer.line] = {"step": offer.chapter, "available": state.day + 1}
		elif number % 2 == 0 and offer.patron != "":
			note = "%s withdrew the request." % offer.patron
		_notice(state, offer.title, note)
	board.fill(state)


func _notice(state: Dictionary, title: String, note: String) -> void:
	state.notices.push_front({"day": state.day, "title": title, "note": note})
	if state.notices.size() > 12:
		state.notices.pop_back()


func _archive(state: Dictionary) -> void:
	var run := {
		"party": state.party.duplicate(), "roles": state.roles.duplicate(),
		"trust": state.trust.duplicate(true), "expedition": state.expedition.duplicate(true),
	}
	var result := debrief(run)
	var quest := contract(run)
	var rewards := _award_experience(state, run.party, quest, result.success)
	if result.success and quest.has("loot"):
		rewards.loot = quest.loot
		_move_stash(state, quest.loot, 1)
	if quest.has("line"):
		state.questlines[quest.line] = {
			"step": int(quest.chapter) + int(result.success),
			"available": state.day if result.success else state.day + 1,
		}
	state.journal.push_front({"day": state.day, "run": run, "rewards": rewards})
	state.treasury += result.gold
	state.standing += result.standing
	if quest.get("patron", "") != "":
		_add_standing(state, quest.patron, result.standing)
	for bond: Dictionary in result.bonds:
		if bond.change != 0:
			state.trust[bond_key(bond.pair)] = {"value": bond.after, "history": "Last worked together on %s." % quest.title}
	state.expedition = {}


func _award_experience(state: Dictionary, party: Array, quest: Dictionary, success: bool) -> Dictionary:
	var xp := int(quest.get("xp", 0))
	if not success:
		xp = floori(xp / 4.0)
	var levels := {}
	for id: String in party:
		var progress: Dictionary = state.character_progress[id]
		var before := characters.level(progress.xp)
		progress.xp += xp
		var after := characters.level(progress.xp)
		if after > before:
			levels[id] = after
	return {"xp": xp, "levels": levels, "loot": ""}


func _add_standing(state: Dictionary, patron: String, amount: int) -> void:
	state.patron_standings[patron] = int(state.patron_standings.get(patron, 0)) + amount


func _ability_modifier(state: Dictionary, member: Dictionary, ability: String) -> int:
	var progress_by_member: Dictionary = state.get("character_progress", {})
	if not state.expedition.is_empty():
		progress_by_member = state.expedition.get("loadout", {})
	var progress: Dictionary = progress_by_member.get(member.id, {})
	if progress.is_empty():
		return super._ability_modifier(state, member, ability)
	return characters.check_modifier(member, progress, ability)


func contract(state: Dictionary) -> Dictionary:
	return state.expedition.get("quest", scenario.contract)


func plans(state: Dictionary) -> Array:
	return contract(state).get("responses", scenario.responses)


func available_member(state: Dictionary, id: String) -> bool:
	return state.guild_roster.has(id) and (state.expedition.is_empty() or not state.party.has(id)) and state.scouting.get("member", "") != id


func improve(state: Dictionary, member_id: String, ability: String) -> bool:
	if not available_member(state, member_id) or not scenario.abilities.has(ability):
		return false
	var member: Dictionary = members[member_id]
	var progress: Dictionary = state.character_progress[member_id]
	if characters.remaining_increases(member, progress) <= 0 or characters.ability_score(member, progress, ability) >= 20:
		return false
	progress.increases[ability] = int(progress.increases.get(ability, 0)) + 1
	return true


func buy(state: Dictionary, item_id: String) -> bool:
	var item: Dictionary = characters.items.get(item_id, {})
	if not state.chartered or item.is_empty() or item.get("reward_only", false) or state.treasury < item.price:
		return false
	state.treasury -= int(item.price)
	_move_stash(state, item_id, 1)
	return true


func sell(state: Dictionary, item_id: String) -> bool:
	if not characters.items.has(item_id) or int(state.stash.get(item_id, 0)) < 1:
		return false
	state.treasury += sale_price(item_id)
	_move_stash(state, item_id, -1)
	return true


func sale_price(item_id: String) -> int:
	return floori(float(characters.items[item_id].price) / 2.0)


func equip(state: Dictionary, member_id: String, item_id: String) -> bool:
	if not available_member(state, member_id) or int(state.stash.get(item_id, 0)) < 1:
		return false
	var progress: Dictionary = state.character_progress[member_id]
	if not characters.can_equip(members[member_id], progress, item_id):
		return false
	var slot: String = characters.items[item_id].slot
	var previous: String = progress.gear.get(slot, "")
	if previous == item_id:
		return false
	if previous != "":
		_move_stash(state, previous, 1)
	progress.gear[slot] = item_id
	_move_stash(state, item_id, -1)
	return true


func unequip(state: Dictionary, member_id: String, slot: String) -> bool:
	if not available_member(state, member_id):
		return false
	var gear: Dictionary = state.character_progress[member_id].gear
	if not gear.has(slot):
		return false
	_move_stash(state, gear[slot], 1)
	gear.erase(slot)
	return true


func _move_stash(state: Dictionary, item_id: String, amount: int) -> void:
	var quantity := int(state.stash.get(item_id, 0)) + amount
	if quantity == 0:
		state.stash.erase(item_id)
	else:
		state.stash[item_id] = quantity


func recruit_pool(state: Dictionary) -> Array[String]:
	var pool: Array[String] = []
	for id: String in members:
		if not state.guild_roster.has(id) and not state.candidates.has(id):
			pool.append(id)
	return pool


func start_scouting(state: Dictionary, id: String) -> bool:
	if not state.scouting.is_empty() or not available_member(state, id) or recruit_pool(state).is_empty():
		return false
	state.scouting = {"member": id, "due_day": state.day + SCOUT_DAYS}
	return true


func _finish_scouting(state: Dictionary) -> void:
	if state.scouting.is_empty() or state.day < state.scouting.due_day:
		return
	var id: String = state.scouting.member
	var scout: Dictionary = members[id]
	var progress: Dictionary = state.character_progress[id]
	var number := 2 if characters.skill_bonus(scout, progress, "Perception") >= 4 else 1
	var leads := recruit_pool(state).slice(0, number)
	state.candidates.append_array(leads)
	state.scouting.clear()
	_notice(state, "Recruitment report", "%s found %d prospective %s in Alderford." % [scout.name, leads.size(), "recruit" if leads.size() == 1 else "recruits"])


func recruit_fee(id: String) -> int:
	return 15 + 5 * int(members[id].level)


func hire(state: Dictionary, id: String) -> bool:
	if not state.candidates.has(id) or state.treasury < recruit_fee(id):
		return false
	state.treasury -= recruit_fee(id)
	state.candidates.erase(id)
	_add_member(state, id)
	return true
