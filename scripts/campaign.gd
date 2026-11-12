extends "res://scripts/expedition.gd"

const QuestBoard = preload("res://scripts/quest_board.gd")
const DAY_SECONDS := 10.0
const RIVALS := ["the Copper Lanterns", "the Briar Company"]
const CAMPAIGN_VERSION := 2

var board := QuestBoard.new()


func fresh() -> Dictionary:
	var state := super.fresh()
	state.version = CAMPAIGN_VERSION
	state.merge({
		"day": 1, "paused": true, "offers": [], "journal": [], "notices": [],
		"treasury": 120, "standing": 0, "trust": {}, "next_offer": 1,
		"next_site": 0, "site_visits": {}, "seen_titles": {},
	})
	return state


func restore(saved: Variant) -> Dictionary:
	if valid_state(saved):
		var migrated: Dictionary = saved
		migrated.merge(fresh())
		migrated.version = CAMPAIGN_VERSION
		return migrated
	if not valid_state(saved, CAMPAIGN_VERSION):
		return fresh()
	return saved


func open_session(state: Dictionary) -> void:
	state.paused = true
	state.offers.clear()
	# The first prototype saved a fixed Ashford expedition without calendar phases.
	if not state.expedition.is_empty() and not state.expedition.has("quest"):
		state.expedition.phase = "decision"
		if state.expedition.choice != "":
			_archive(state)
	board.fill(state)


func accept(state: Dictionary, id: String, roll: int) -> bool:
	var quest := board.by_id(state, id)
	if quest.is_empty() or state.day >= quest.deadline or not depart(state, roll):
		return false
	state.offers.erase(quest)
	state.expedition.merge({
		"quest": quest, "departed_day": state.day,
		"phase": "outbound", "due_day": state.day + quest.travel,
	})
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
	if state.paused:
		return false
	state.day += 1
	_expire_offers(state)
	var trip: Dictionary = state.expedition
	if trip.is_empty() or trip.phase == "decision" or state.day < trip.due_day:
		return true
	match trip.phase:
		"outbound":
			trip.phase = "decision"
			state.paused = true
		"work":
			trip.phase = "return"
			trip.due_day = state.day + trip.quest.travel
		"return":
			_archive(state)
			state.paused = true
	return true


func _expire_offers(state: Dictionary) -> void:
	for offer: Dictionary in state.offers.duplicate():
		if state.day < offer.deadline:
			continue
		state.offers.erase(offer)
		var number := int(offer.id)
		var note := "%s completed the job." % RIVALS[number % RIVALS.size()]
		if number % 3 == 0:
			note = "%s withdrew the request." % offer.patron
		state.notices.push_front({"day": state.day, "title": offer.title, "note": note})
		if state.notices.size() > 12:
			state.notices.pop_back()
	board.fill(state)


func _archive(state: Dictionary) -> void:
	var run := {
		"party": state.party.duplicate(), "roles": state.roles.duplicate(),
		"trust": state.trust.duplicate(true), "expedition": state.expedition.duplicate(true),
	}
	var result := debrief(run)
	state.journal.push_front({"day": state.day, "run": run})
	state.treasury += result.gold
	state.standing += result.standing
	for bond: Dictionary in result.bonds:
		if bond.change != 0:
			state.trust[bond_key(bond.pair)] = {"value": bond.after, "history": "Last worked together on %s." % contract(run).title}
	state.expedition = {}


func contract(state: Dictionary) -> Dictionary:
	return state.expedition.get("quest", scenario.contract)


func plans(state: Dictionary) -> Array:
	return contract(state).get("responses", scenario.responses)
