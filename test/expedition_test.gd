extends SceneTree

const Expedition = preload("res://scripts/expedition.gd")
const GuildSave = preload("res://scripts/guild_save.gd")
const Campaign = preload("res://scripts/campaign.gd")
const QuestWriter = preload("res://scripts/quest_writer.gd")
const Guildhall = preload("res://scenes/guildhall.tscn")

var rules := Expedition.new()
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_lineup()
	_test_outcomes()
	_test_save()
	_test_campaign()
	_test_writer()
	_test_guildhall()
	if failures == 0:
		print("Expedition tests passed.")
	quit(0 if failures == 0 else 1)


func _test_lineup() -> void:
	var state := rules.fresh()
	_expect(not rules.depart(state, 6), "An incomplete lineup cannot depart.")
	_expect(rules.toggle_member(state, "ilya"), "A third adventurer can join.")
	_expect(not rules.toggle_member(state, "nyra"), "A full party cannot add a fourth member.")
	rules.assign(state, "captain", "rowan")
	_expect(state.roles.scout == "mara", "Assigning the Scout to Captain swaps their roles.")
	rules.toggle_member(state, "rowan")
	_expect(state.roles.captain == "", "Removing an adventurer clears their assignment.")
	rules.toggle_member(state, "tess")
	_expect(not rules.ready(state), "A full party still needs both assignments.")


func _test_outcomes() -> void:
	var original := _lineup("ilya")
	var different_captain := original.duplicate(true)
	rules.assign(different_captain, "captain", "ilya")
	_expect(rules.chemistry(original) == 2, "Shared history and lead trust grant two chemistry.")
	_expect(rules.chemistry(different_captain) == 1, "Changing Captain can change chemistry.")
	rules.depart(original, 6)
	rules.depart(different_captain, 6)
	var with_prospect := _lineup("tess")
	rules.depart(with_prospect, 6)
	_expect(rules.debrief(original, "split").success, "The starting pair and Wizard can execute the split.")
	_expect(not rules.debrief(different_captain, "split").success, "The same roll can fail with a different Captain.")
	_expect(not rules.debrief(with_prospect, "split").success, "The same roll can fail with a different lineup.")
	_expect(not rules.toggle_member(with_prospect, "mara"), "The lineup is locked after departure.")
	_expect(rules.record(with_prospect, "orders"), "An expedition accepts one order.")
	var result := rules.debrief(with_prospect)
	var alternative := rules.debrief(with_prospect, "rescue")
	_expect(result.roll == alternative.roll and result.gold == 90 and alternative.gold == 45, "Comparisons use the same roll and can change the payout.")
	_expect(result.bonds[0].after == 2 and alternative.bonds[0].after == 5, "Orders have different relationship consequences.")
	_expect(result.prospects == ["Tess Reed"], "Field experience records the prospect.")
	_expect(not rules.record(with_prospect, "rescue"), "A recorded order cannot be overwritten.")
	_expect(rules.debrief(with_prospect) == result, "Comparison leaves the saved decision intact.")


func _test_save() -> void:
	var path := "user://test-guildbound-%d.cfg" % OS.get_process_id()
	var state := _lineup("ilya")
	rules.depart(state, 6)
	_expect(GuildSave.write(state, path) == OK, "The game can write a pending expedition.")
	_expect(GuildSave.read(rules, path) == state, "The pending expedition and roll survive a reload.")
	rules.record(state, "split")
	_expect(GuildSave.write(state, path) == OK, "The resolved expedition replaces its pending save.")
	var loaded := GuildSave.read(rules, path)
	_expect(loaded == state and rules.debrief(loaded) == rules.debrief(state), "The decision and debrief survive a reload.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_expect(GuildSave.read(rules, path) == rules.fresh(), "A missing save starts a fresh game.")


func _lineup(third: String) -> Dictionary:
	var state := rules.fresh()
	rules.toggle_member(state, third)
	return state


func _test_campaign() -> void:
	var campaign := Campaign.new()
	var state := campaign.fresh()
	campaign.open_session(state)
	var initial_offers: Array = state.offers.duplicate(true)
	_expect(state.offers.size() == 3, "The map has three offers at launch.")
	_expect(not campaign.advance_day(state) and state.day == 1, "A paused calendar does not tick.")
	campaign.open_session(state)
	for offer: Dictionary in state.offers:
		for old: Dictionary in initial_offers:
			_expect(offer.id != old.id and offer.title != old.title, "Reopening the map offers different quests.")
	var quest: Dictionary = state.offers[0]
	_expect(not campaign.accept(state, quest.id, 20), "A quest needs a full party.")
	campaign.toggle_member(state, "tess")
	var plans := quest.responses as Array
	var chance := campaign.success_chance(state, plans[0])
	var weaker_plan: Dictionary = plans[0].duplicate()
	weaker_plan.dc += 2
	_expect(campaign.success_chance(state, weaker_plan) < chance, "Difficulty changes success odds.")
	var deadline: int = quest.deadline
	var departure: int = state.day
	_expect(campaign.accept(state, quest.id, 20), "A ready party can accept a map offer.")
	_expect(campaign.board.by_id(state, quest.id).is_empty(), "Accepted offers leave the public board.")
	_expect(not campaign.choose_plan(state, "first"), "The party needs to reach the site before choosing a plan.")
	state.paused = false
	for day in quest.travel:
		campaign.advance_day(state)
	_expect(state.day == departure + quest.travel and state.expedition.phase == "decision" and state.paused, "The party arrives after the outbound travel days and pauses for its report.")
	_expect(campaign.choose_plan(state, "first"), "An arrived party can take a decision.")
	var path := "user://test-campaign-%d.cfg" % OS.get_process_id()
	_expect(GuildSave.write(state, path) == OK, "The calendar and field expedition can be saved.")
	state = GuildSave.read(campaign, path)
	_expect(state.expedition.phase == "work" and state.expedition.choice == "first", "Reloading preserves the accepted quest and selected plan.")
	campaign.open_session(state)
	_expect(state.expedition.quest == quest and state.paused, "New offers do not replace the accepted quest.")
	state.paused = false
	for day in quest.work + quest.travel:
		campaign.advance_day(state)
	_expect(state.day == departure + quest.travel * 2 + quest.work, "Time on site and return travel both count.")
	_expect(state.expedition.is_empty() and state.journal.size() == 1 and state.paused, "Returning archives the expedition and pauses the calendar.")
	_expect(state.treasury == 120 + quest.fee and not state.trust.is_empty(), "The payout and trust changes carry forward.")
	_expect(campaign.toggle_member(state, "tess"), "The roster unlocks after return.")
	state.paused = false
	var expired: Dictionary = state.offers[0]
	while state.day <= maxi(deadline, expired.deadline):
		campaign.advance_day(state)
	_expect(state.journal.size() == 1 and state.treasury == 120 + quest.fee, "Later ticks cannot award the quest twice.")
	_expect(campaign.board.by_id(state, expired.id).is_empty() and not state.notices.is_empty(), "Expired offers leave the board and a notice is recorded.")
	_expect(not campaign.accept(state, expired.id, 20), "An expired offer cannot be accepted.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_writer() -> void:
	var campaign := Campaign.new()
	var state := campaign.fresh()
	campaign.open_session(state)
	var offer: Dictionary = state.offers[0]
	var story := {
		"id": offer.id, "title": "The Salt Marker", "brief": "A carter needs a lost marker recovered.",
		"report": "The marker was taken to the old watchtower.",
		"first_success": "The carters helped carry the stone home.", "first_failure": "The carters left before it was found.",
		"second_success": "The party hauled it back before dawn.", "second_failure": "The ground fell away under it.",
	}
	var writer := QuestWriter.new()
	writer.operation = "discover"
	writer._receive(HTTPRequest.RESULT_SUCCESS, 200, [], '{"models":[{"name":"test-cloud"},{"name":"test-local"}]}'.to_utf8_buffer())
	_expect(writer.model == "test-local", "Ollama discovery selects a local model.")
	var stories: Array = []
	writer.stories_ready.connect(func(batch: Array) -> void: stories.append_array(batch))
	writer.operation = "write"
	var payload := JSON.stringify({"response": JSON.stringify({"quests": [story]})})
	writer._receive(HTTPRequest.RESULT_SUCCESS, 200, [], payload.to_utf8_buffer())
	_expect(stories.size() == 1, "A nonstreaming Ollama response delivers the structured story.")
	var original := offer.duplicate(true)
	_expect(campaign.board.apply_story(state, offer, story), "A valid AI story is applied.")
	_expect(offer.source == "ai" and offer.title == story.title and offer.responses[1].failure == story.second_failure, "The AI writes the title, complication and plan outcomes.")
	_expect(offer.travel == original.travel and offer.fee == original.fee and offer.responses[0].dc == original.responses[0].dc, "The author cannot change calendar or game balance.")
	_expect(not campaign.board.apply_story(state, state.offers[1], story), "Repeated titles are rejected.")
	story.title = ""
	_expect(not campaign.board.apply_story(state, state.offers[1], story), "Malformed AI stories leave a procedural offer available.")
	root.add_child(writer)
	writer.free()


func _test_guildhall() -> void:
	var path := "user://test-guildhall-%d.cfg" % OS.get_process_id()
	var guildhall := Guildhall.instantiate()
	guildhall.set("save_path", path)
	guildhall.set("use_local_ai", false)
	root.add_child(guildhall)
	var state: Dictionary = guildhall.get("state")
	var offer: Dictionary = state.offers[0]
	_press(guildhall, offer.location)
	_press(guildhall, "Assemble the party")
	_press(guildhall, "Add Tess Reed to the party", true)
	_press(guildhall, "View the quest map")
	_press(guildhall, "Accept and depart")
	_expect(guildhall.get("screen") == "contract", "Accepting a map offer opens the expedition.")
	_press(guildhall, "Resume")
	for day in offer.travel:
		guildhall._day_passed()
	_press(guildhall, offer.responses[0].title)
	_press(guildhall, "Resume")
	for day in offer.work + offer.travel:
		guildhall._day_passed()
	_expect(guildhall.get("screen") == "journal", "Returning opens the expedition debrief.")
	_press(guildhall, offer.responses[1].title)
	_expect(guildhall.get("comparison") == "second", "The journal can compare another plan.")
	var saved := GuildSave.read(Campaign.new(), path)
	_expect(saved.journal[0].run.expedition.choice == "first", "Comparing a plan leaves the saved decision intact.")
	guildhall.free()
	var legacy := _lineup("tess")
	rules.depart(legacy, 6)
	rules.record(legacy, "orders")
	GuildSave.write(legacy, path)
	var reopened := Guildhall.instantiate()
	reopened.set("save_path", path)
	reopened.set("use_local_ai", false)
	root.add_child(reopened)
	_expect(reopened.get("screen") == "journal", "A first-prototype save restores its debrief.")
	_expect(reopened.get("state").treasury == 210, "A first-prototype save keeps its payout.")
	reopened.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _press(screen: Node, label: String, by_tooltip := false) -> void:
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		var text := button.tooltip_text if by_tooltip else button.text
		if text.begins_with(label):
			_expect(not button.disabled, "The button is enabled: " + label)
			if not button.disabled:
				button.pressed.emit()
			return
	_expect(false, "The screen has the button: " + label)


func _expect(condition: bool, failure: String) -> void:
	if not condition:
		failures += 1
		push_error(failure)
