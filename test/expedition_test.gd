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
	_test_town_and_questlines()
	_test_armory_and_recruitment()
	_test_previous_campaign()
	_test_writer()
	await _test_guildhall()
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
	var state := _chartered(campaign)
	campaign.open_session(state)
	var initial_offers: Array = state.offers.duplicate(true)
	_expect(state.offers.size() == 5, "The map has three standalone offers and two story openings at launch.")
	_expect(not campaign.advance_day(state) and state.day == 1, "A paused calendar does not tick.")
	campaign.open_session(state)
	for offer: Dictionary in state.offers:
		for old: Dictionary in initial_offers:
			_expect(offer.id != old.id and (offer.has("line") or offer.title != old.title), "Reopening the map offers different quests.")
	var quest: Dictionary = state.offers[0]
	campaign.toggle_member(state, "tess")
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


func _chartered(campaign: Campaign) -> Dictionary:
	var state := campaign.fresh()
	var charter := {"name": "The Third Lock", "motto": "Stand together", "terms": "Bring the party home."}
	_expect(not campaign.found_guild(state, charter, ["mara", "mara", "tess"]), "Founders must be distinct.")
	_expect(campaign.found_guild(state, charter, ["mara", "rowan", "tess"]), "Signing a valid charter starts the campaign.")
	return state


func _test_town_and_questlines() -> void:
	var campaign := Campaign.new()
	var state := _chartered(campaign)
	var start := _line_offer(state, "ledger")
	_expect(start.travel == 0 and start.patron == "", "The quest line starts in Alderford as an independent lead.")
	_expect(campaign.accept(state, start.id, 1) and state.expedition.phase == "decision", "Town quests open at the site with no travel.")
	_expect(not campaign.unequip(state, "tess", "weapon"), "The active party's equipment is locked.")
	_expect(campaign.choose_plan(state, "first"), "The party can act on the town lead.")
	_tick(campaign, state, start.work)
	_expect(state.day == 2 and state.expedition.is_empty(), "The town quest advances only its work days.")
	_expect(state.questlines.ledger.step == 0 and _line_offer(state, "ledger").is_empty(), "Failure leaves the chapter open for a future retry.")
	_tick(campaign, state, 1)
	start = _line_offer(state, "ledger")
	_expect(not start.is_empty(), "A failed chapter returns to the board.")
	campaign.accept(state, start.id, 20)
	campaign.choose_plan(state, "first")
	_tick(campaign, state, start.work)
	_expect(state.questlines.ledger.step == 1 and state.patron_standings.is_empty(), "An independent lead unlocks its next chapter without paying patron standing.")
	_expect(state.stash.get(start.loot, 0) == 1 and state.treasury == 120, "An independent lead yields loot without a patron payment.")
	var follow_up := _line_offer(state, "ledger")
	_expect(follow_up.site == "rookbridge" and follow_up.patron != "", "The follow-up leads to Rookbridge and a patron.")
	_expect(campaign.accept(state, follow_up.id, 20), "The party can accept the second chapter.")
	_tick(campaign, state, follow_up.travel)
	campaign.choose_plan(state, "first")
	_tick(campaign, state, follow_up.work + follow_up.travel)
	_expect(state.patron_standings.get(follow_up.patron, 0) > 0 and state.patron_standings.size() == 1, "Commission success changes the issuing patron's standing.")
	_expect(campaign.characters.level(state.character_progress.tess.xp) == 2, "Accumulated expedition XP advances the adventurer's level.")
	_expect(state.journal[0].rewards.levels.get("tess") == 2 and _line_offer(state, "ledger").chapter == 2, "The journal records a level-up and the quest line advances.")
	var historic := campaign.debrief(state.journal[0].run)
	campaign.unequip(state, "tess", "kit")
	_expect(campaign.debrief(state.journal[0].run) == historic, "Later gear changes preserve the original debrief.")
	var finale := _line_offer(state, "ledger")
	_expect(campaign.accept(state, finale.id, 20), "The party can accept the final chapter.")
	_tick(campaign, state, finale.travel)
	campaign.choose_plan(state, "first")
	_tick(campaign, state, finale.work + finale.travel)
	_expect(state.questlines.ledger.step == 3 and state.stash.lockwarden_blade == 1, "Finishing the quest line awards its unique equipment.")
	campaign.open_session(state)
	_expect(_line_offer(state, "ledger").is_empty(), "A completed story stays completed after reopening.")


func _line_offer(state: Dictionary, id: String) -> Dictionary:
	for offer: Dictionary in state.offers:
		if offer.get("line") == id:
			return offer
	return {}


func _tick(campaign: Campaign, state: Dictionary, days: int) -> void:
	state.paused = false
	for day in days:
		campaign.advance_day(state)


func _test_armory_and_recruitment() -> void:
	var campaign := Campaign.new()
	var state := _chartered(campaign)
	var progress: Dictionary = state.character_progress.mara
	var sheet := campaign.characters.sheet(campaign.members.mara, progress)
	_expect(sheet.hp == 28 and sheet.ac == 18 and sheet.proficiency == 2, "Paladin sheet calculates hit points, armor and proficiency.")
	_expect(campaign.buy(state, "greatsword") and state.treasury == 70, "Purchases spend guild gold and enter the stash.")
	_expect(not campaign.equip(state, "mara", "greatsword") and state.stash.greatsword == 1, "A shield blocks a two-handed weapon without changing inventory.")
	_expect(campaign.unequip(state, "mara", "offhand") and campaign.equip(state, "mara", "greatsword"), "Returning the shield to the stash allows the new weapon.")
	_expect(state.stash.longsword == 1 and not state.stash.has("greatsword"), "The replaced weapon returns to the stash.")
	_expect(campaign.sell(state, "longsword") and state.treasury == 77, "The shop buys a stashed item at resale price.")
	_expect(not campaign.buy(state, "lockwarden_blade"), "Quest rewards are unavailable at the shop.")
	progress.xp = 2700
	_expect(campaign.improve(state, "mara", "str") and campaign.improve(state, "mara", "str") and not campaign.improve(state, "mara", "str"), "Level four grants two assignable ability points.")
	_expect(campaign.characters.ability_score(campaign.members.mara, progress, "str") == 18, "Ability improvements affect the character sheet.")
	_expect(campaign.start_scouting(state, "rowan") and not campaign.can_leave(state), "A scouting party member is unavailable for expeditions.")
	_tick(campaign, state, Campaign.SCOUT_DAYS)
	_expect(state.candidates.size() == 2 and campaign.can_leave(state), "A skilled Scout returns with two candidates.")
	var id: String = state.candidates[0]
	var before: int = state.treasury
	_expect(campaign.hire(state, id) and state.guild_roster.has(id) and state.character_progress.has(id), "Hiring adds the candidate and starting equipment to the roster.")
	_expect(state.treasury == before - campaign.recruit_fee(id) and not campaign.hire(state, id), "Recruit fees are charged once.")
	var path := "user://test-progression-%d.cfg" % OS.get_process_id()
	_expect(GuildSave.write(state, path) == OK and GuildSave.read(campaign, path) == state, "The charter, roster, scouting and inventory survive saving.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_previous_campaign() -> void:
	var campaign := Campaign.new()
	var previous := _lineup("tess")
	previous.version = 2
	previous.treasury = 210
	rules.depart(previous, 6)
	rules.record(previous, "orders")
	previous.journal = [{"day": 7, "run": previous.duplicate(true)}]
	previous.expedition = {}
	previous.day = 7
	var migrated := campaign.restore(previous)
	campaign.open_session(migrated)
	_expect(migrated.day == 7 and migrated.treasury == 210 and migrated.chartered, "Version two saves reopen on the same day with their treasury.")
	_expect(migrated.party == ["mara", "rowan", "tess"] and migrated.guild_roster.size() == 6, "The previous roster and expedition lineup carry forward.")
	_expect(campaign.debrief(migrated.journal[0].run).gold == 90 and migrated.patron_standings["Warden Elspeth Vale"] == 2, "Journal outcomes stay intact and initialize individual patron standings.")


func _test_writer() -> void:
	var campaign := Campaign.new()
	var state := _chartered(campaign)
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
	_expect(guildhall.get("screen") == "founding", "A new campaign opens the founding charter.")
	_press(guildhall, "Select Mara")
	_press(guildhall, "Select Rowan")
	_press(guildhall, "Select Tess")
	_press(guildhall, "Sign charter and begin")
	var state: Dictionary = guildhall.get("state")
	var offer: Dictionary = state.offers[0]
	_press(guildhall, "Roster")
	_press(guildhall, "Character sheet")
	_expect(guildhall.get("screen") == "character", "The roster opens a character sheet.")
	_press(guildhall, "Open armory")
	_press(guildhall, "Town shop")
	_expect(guildhall.get("screen") == "armory", "The character sheet leads to the shop.")
	_press(guildhall, "Quest map")
	await process_frame
	await process_frame
	_press(guildhall, "Zoom in", true)
	_expect(guildhall.get("map_zoom") > 1.0, "The map zoom button changes the camera.")
	_press(guildhall, "Alderford")
	_expect(guildhall.get("selected_site") == "alderford" and guildhall.get("map_zoom") > 1.0, "The town marker opens its quests and preserves zoom.")
	await process_frame
	await process_frame
	_press(guildhall, "Reset view")
	_expect(guildhall.get("map_zoom") == 1.0, "Reset view restores the default zoom.")
	_press(guildhall, offer.location)
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
