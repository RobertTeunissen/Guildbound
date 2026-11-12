extends Control

const Campaign = preload("res://scripts/campaign.gd")
const GuildSave = preload("res://scripts/guild_save.gd")
const QuestWriter = preload("res://scripts/quest_writer.gd")
const RegionMap = preload("res://scripts/region_map.gd")
const CANVAS := Color("#171814")
const RAIL := Color("#11120f")
const SURFACE := Color("#22231c")
const LINE := Color("#403f33")
const INK := Color("#eee9db")
const MUTED := Color("#b8b3a2")
const GOLD := Color("#e5c083")
const GREEN := Color("#bfcea4")
const RUST := Color("#edab98")
const CLASS_COLORS := {
	"amber": Color("#e5c083"), "green": Color("#c3cfaa"), "blue": Color("#b8c9e3"),
	"plum": Color("#e2b6c6"), "teal": Color("#a9cfbf"), "ochre": Color("#e5c083"),
}

var rules := Campaign.new()
var state: Dictionary
var screen := "map"
var selected_quest := ""
var inspected := {}
var requested := {}
var journal_index := 0
var comparison := ""
var expanded_scores := {}
var save_failed := false
var save_path := GuildSave.PATH
var serif := SystemFont.new()
var shell: HBoxContainer
var scroll: ScrollContainer
var clock := Timer.new()
var writer := QuestWriter.new()
var use_local_ai := true


func _ready() -> void:
	serif.font_names = PackedStringArray(["Baskerville", "Palatino Linotype", "Liberation Serif", "Georgia"])
	get_window().min_size = Vector2i(1024, 680)
	state = GuildSave.read(rules, save_path)
	var legacy_debrief: bool = state.expedition.has("choice") and not state.expedition.has("quest") and state.expedition.choice != ""
	rules.open_session(state)
	if not state.expedition.is_empty():
		screen = "contract"
	elif legacy_debrief:
		screen = "journal"
	clock.wait_time = Campaign.DAY_SECONDS
	clock.timeout.connect(_day_passed)
	add_child(clock)
	clock.start()
	clock.paused = true
	add_child(writer)
	use_local_ai = use_local_ai and not OS.get_cmdline_user_args().has("--no-local-ai")
	if not use_local_ai:
		writer.status = "Procedural contracts"
	writer.status_changed.connect(_writer_status_changed)
	writer.stories_ready.connect(_apply_stories)
	_save_and_render(false)
	if use_local_ai:
		writer.discover()


func _render(preserve_scroll := false) -> void:
	var previous_scroll := scroll.scroll_vertical if preserve_scroll and is_instance_valid(scroll) else 0
	if is_instance_valid(shell):
		remove_child(shell)
		shell.queue_free()

	shell = HBoxContainer.new()
	add_child(shell)
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_constant_override("separation", 0)

	var sidebar := _panel(shell, RAIL, LINE, 16)
	_panel_frame(sidebar).custom_minimum_size.x = 177
	_text(sidebar, "GUILDBOUND", 22, GOLD, true)
	_text(sidebar, "The Alder Company", 13, MUTED)
	_space(sidebar, 15)
	for entry: Array in [["map", "Quest map"], ["roster", "Roster"], ["contract", "Expedition"], ["journal", "Journal"]]:
		var nav := _button(sidebar, entry[1], _navigate.bind(entry[0]), screen == entry[0])
		nav.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var rail_spacer := Control.new()
	rail_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(rail_spacer)
	_text(sidebar, "Alderford Guildhall", 13, MUTED)

	var workspace := _panel(shell, CANVAS, CANVAS, 0)
	_panel_frame(workspace).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := _panel(workspace, RAIL, LINE, 13)
	var top_row := _row(top)
	var place := _text(top_row, "Alderford  /  Guildhall", 14, MUTED)
	place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text(top_row, "%d gp treasury" % state.treasury, 14, GOLD)
	_text(top_row, "%s standing" % _signed(state.standing), 14, INK)
	_text(top_row, "Day %d" % state.day, 16, GOLD)
	var time_button := _button(top_row, "Resume" if state.paused else "Pause", _toggle_time, state.paused)
	time_button.tooltip_text = "One game day passes every %d seconds while time is running." % int(Campaign.DAY_SECONDS)
	if save_failed:
		_text(workspace, "Could not save guild progress to disk.", 14, RUST)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	workspace.add_child(scroll)
	var padding := MarginContainer.new()
	_padding(padding, 26)
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(padding)
	var board := _row(padding, 22)
	var main := _column(board, 13)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var aside := _column(board, 13)
	aside.custom_minimum_size.x = 284

	match screen:
		"map":
			_map_screen(main, aside)
		"roster":
			_roster(main)
			_party_panel(aside)
		"contract":
			_contract(main)
			if not state.expedition.is_empty():
				_contract_brief(aside, rules.contract(state))
			_party_panel(aside)
		"journal":
			_journal(main, aside)
	if previous_scroll > 0:
		scroll.set_deferred("scroll_vertical", previous_scroll)


func _roster(parent: VBoxContainer) -> void:
	var subtitle := "Choose three adventurers, then assign a Captain and a Scout."
	if not state.expedition.is_empty():
		subtitle = "This party is in the field at %s." % rules.contract(state).location
	_heading(parent, "Guild roster", "Assemble the party", subtitle)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 11)
	grid.add_theme_constant_override("v_separation", 11)
	parent.add_child(grid)
	for member: Dictionary in rules.scenario.adventurers:
		_member_card(grid, member)
	_bonds(parent)


func _member_card(grid: GridContainer, member: Dictionary) -> void:
	var selected: bool = state.party.has(member.id)
	var card := _panel(grid, SURFACE, GOLD.darkened(0.42) if selected else LINE, 10)
	_panel_frame(card).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var portrait := TextureRect.new()
	portrait.texture = load("res://assets/%s.jpg" % member.id)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.custom_minimum_size = Vector2(116, 108)
	card.add_child(portrait)
	var role := ""
	if state.roles.captain == member.id:
		role = "Captain"
	elif state.roles.scout == member.id:
		role = "Scout"
	elif rules.support_id(state) == member.id:
		role = "Support"
	var details := "%s · Level %d" % [member.className, member.level]
	if member.get("prospect", false):
		details += " · Prospect"
	_text(card, details, 12, CLASS_COLORS[member.tone])
	_text(card, member.name, 23, INK, true)
	if role != "":
		_text(card, role, 13, GOLD)
	else:
		_text(card, "Selected" if selected else "Available", 13, MUTED)
	_text(card, member.specialty, 12, MUTED)
	var show_scores: bool = expanded_scores.get(member.id, false)
	_button(card, "Hide ability scores" if show_scores else "View ability scores", _toggle_scores.bind(member.id))
	if show_scores:
		var scores := PackedStringArray()
		for key: String in member.scores:
			scores.append("%s %d" % [key.to_upper(), member.scores[key]])
		_text(card, "  ".join(scores), 12, MUTED)
	if state.expedition.is_empty():
		var action := _button(card, "✓  In party" if selected else "+  Add to party", _toggle_member.bind(member.id), selected)
		action.disabled = not selected and state.party.size() >= int(rules.scenario.partySize)
		action.tooltip_text = "Remove %s from the party" % member.name if selected else "Add %s to the party" % member.name


func _map_screen(parent: VBoxContainer, aside: VBoxContainer) -> void:
	_heading(parent, "Quest map", rules.board.world.region, "Select a location to read its contract.")
	var map := RegionMap.new()
	map.sites = rules.board.world.sites
	map.font = serif
	parent.add_child(map)
	var trip: Dictionary = state.expedition
	if not trip.is_empty():
		var active: Dictionary = rules.contract(state)
		var site_id: String = active.get("site", "ashford")
		var site: Dictionary = rules.board.sites[site_id]
		map.active_site = site_id
		map.route_step = _route_step(trip)
		var marker := _button(map, site.name + " · Party", _navigate.bind("contract"), true)
		marker.tooltip_text = active.title
		map.add_marker(site_id, Vector2(site.map[0], site.map[1]), marker)
	for offer: Dictionary in state.offers:
		var site: Dictionary = rules.board.sites[offer.site]
		var marker := _button(map, "%s · %dd" % [site.name, offer.deadline - state.day], _inspect_quest.bind(offer.id), offer.id == selected_quest)
		marker.tooltip_text = offer.title
		map.add_marker(site.id, Vector2(site.map[0], site.map[1]), marker)
	var writer_row := _row(parent, 8)
	_text(writer_row, writer.status, 12, MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if use_local_ai and writer.model == "" and writer.operation == "":
		_button(writer_row, "Reconnect AI", _reconnect_ai)
	var notices := _panel(parent)
	_text(notices, "Patron notices", 22, INK, true)
	if state.notices.is_empty():
		_text(notices, "Expired contracts will appear here.", 13, MUTED)
	for notice: Dictionary in state.notices.slice(0, 3):
		_text(notices, "Day %d · %s" % [notice.day, notice.title], 14, INK)
		_text(notices, str(notice.note).left(1).to_upper() + str(notice.note).substr(1), 13, MUTED)
	var offer := rules.board.by_id(state, selected_quest)
	if offer.is_empty():
		var panel := _panel(aside)
		_text(panel, "Available contracts", 23, INK, true)
		for available: Dictionary in state.offers:
			_button(panel, available.location, _inspect_quest.bind(available.id))
	else:
		_quest_details(aside, offer)
	_party_panel(aside)


func _route_step(trip: Dictionary) -> float:
	var quest: Dictionary = trip.get("quest", {})
	if quest.is_empty() or trip.phase == "decision" or trip.phase == "work":
		return 1.0
	var remaining := float(trip.due_day - state.day) / float(quest.travel)
	return 1.0 - remaining if trip.phase == "outbound" else remaining


func _quest_details(parent: VBoxContainer, offer: Dictionary) -> void:
	var panel := _contract_brief(parent, offer)
	_text(panel, "AI-written contract" if offer.source == "ai" else "Procedural contract", 12, MUTED)
	_text(panel, "Closes in %s · Day %d" % [_days(offer.deadline - state.day), offer.deadline], 14, GOLD)
	_text(panel, "%s out · %s on site · %s back" % [_days(offer.travel), _days(offer.work), _days(offer.travel)], 13, INK)
	if rules.ready(state) and state.expedition.is_empty():
		var best := 0
		for plan: Dictionary in offer.responses:
			var chance := rules.success_chance(state, plan)
			best = maxi(best, chance)
			_text(panel, "%s · %d%%" % [plan.title, chance], 13, MUTED)
		var risk := "Favourable" if best >= 70 else ("Risky" if best < 40 else "Challenging")
		_text(panel, "%s for this party" % risk, 14, RUST if best < 40 else GOLD)
		_button(panel, "Accept and depart", _depart.bind(offer.id), true)
	elif not state.expedition.is_empty():
		_text(panel, "The party is already in the field.", 13, MUTED)
	else:
		_button(panel, "Assemble the party", _navigate.bind("roster"), true)


func _contract_brief(parent: VBoxContainer, brief: Dictionary) -> VBoxContainer:
	var panel := _panel(parent, Color("#2c271d"), Color("#63543b"))
	_text(panel, brief.title, 28, INK, true)
	_text(panel, brief.patron + " · " + brief.affiliation, 13, GOLD)
	_text(panel, brief.brief, 14, MUTED)
	_text(panel, "%s · %d gp fee" % [brief.location, brief.fee], 13, INK)
	return panel


func _days(amount: int) -> String:
	return "%d %s" % [amount, "day" if amount == 1 else "days"]


func _party_panel(parent: VBoxContainer) -> void:
	var panel := _panel(parent)
	var size := int(rules.scenario.partySize)
	_text(panel, "Expedition party   %d / %d" % [state.party.size(), size], 23, INK, true)
	for role: String in ["captain", "scout"]:
		var row := _row(panel)
		var label := _text(row, role.capitalize(), 13, MUTED)
		label.custom_minimum_size.x = 58
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.fit_to_longest_item = false
		picker.clip_text = true
		picker.tooltip_text = "Assign " + role.capitalize()
		picker.add_item("Unassigned")
		var ids: Array = [""]
		ids.append_array(state.party)
		for id: String in state.party:
			picker.add_item(rules.members[id].name)
		picker.select(ids.find(state.roles[role]))
		picker.disabled = not state.expedition.is_empty() or state.party.is_empty()
		picker.item_selected.connect(_assign_role.bind(role, ids))
		row.add_child(picker)
	var support := rules.support_id(state)
	_text(panel, "Support   " + (rules.members[support].name if support != "" else "—"), 13, MUTED)
	if state.expedition.is_empty():
		var missing: int = size - state.party.size()
		if missing > 0:
			_text(panel, "Choose %d more adventurer%s." % [missing, "" if missing == 1 else "s"], 12, MUTED)
		elif not rules.ready(state):
			_text(panel, "Assign both roles before departing.", 12, MUTED)
		if screen == "roster":
			_button(panel, "View the quest map", _navigate.bind("map"), rules.ready(state))
	elif screen != "contract":
		_button(panel, "View active expedition", _navigate.bind("contract"), true)

func _bonds(parent: VBoxContainer) -> void:
	var panel := _panel(parent)
	_text(panel, "Party relationships", 23, INK, true)
	var relationships := rules.bonds(state)
	if relationships.is_empty():
		_text(panel, "Choose at least two adventurers to see their shared history.", 13, MUTED)
		return
	var bonus := _text(panel, "%s chemistry" % _signed(rules.chemistry(state)), 13, GOLD)
	bonus.tooltip_text = "Every 3 points of shared trust give +1. A Captain and Scout with at least 3 trust give another +1."
	bonus.mouse_filter = Control.MOUSE_FILTER_PASS
	for bond: Dictionary in relationships:
		var trust: int = bond.trust
		var row := _row(panel)
		var names := _column(row, 2)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_text(names, _pair_name(bond.pair), 14, INK)
		_text(names, bond.history, 12, MUTED)
		_text(row, "%s · %s" % [_trust_name(trust), _signed(trust)], 13, GREEN if trust > 0 else MUTED)


func _contract(parent: VBoxContainer) -> void:
	var trip: Dictionary = state.expedition
	if trip.is_empty():
		_heading(parent, "Expedition", "The party is at the guildhall", "Choose a contract on the quest map to send the party out.")
		_button(parent, "Open quest map", _navigate.bind("map"), true)
		return
	var brief := rules.contract(state)
	_heading(parent, "Expedition", brief.title, brief.location)
	var progress := _panel(parent, SURFACE, Color("#63543b"))
	if trip.phase != "decision":
		var phase_title: String = {
			"outbound": "Travelling to %s" % brief.location,
			"work": "The party is working on site",
			"return": "Returning to Alderford",
		}[trip.phase]
		_text(progress, phase_title, 27, INK, true)
		_text(progress, "%s remaining · Day %d" % [_days(trip.due_day - state.day), trip.due_day], 15, GOLD)
		if state.paused:
			_button(progress, "Resume time", _toggle_time, true)
		return
	_kicker(progress, "Scout’s report")
	_text(progress, rules.members[state.roles.scout].name, 15, GOLD)
	_text(progress, "“" + brief.report + "”", 24, INK, true)
	_text(parent, "How should the Captain respond?", 25, INK, true)
	for order: Dictionary in rules.plans(state):
		var chance := rules.success_chance(state, order)
		var card := _panel(parent)
		_kicker(card, order.focus)
		_text(card, order.description, 14, MUTED)
		_button(card, "%s  ·  %d%% success chance" % [order.title, chance], _choose.bind(order.id), true)


func _journal(parent: VBoxContainer, aside: VBoxContainer) -> void:
	if state.journal.is_empty():
		_heading(parent, "Guild journal", "Expedition records", "Completed contracts and their consequences appear here.")
		_button(parent, "Open quest map", _navigate.bind("map"), true)
		return
	var records := _panel(aside)
	_text(records, "Expedition records", 23, INK, true)
	for index in state.journal.size():
		var record: Dictionary = state.journal[index]
		var button := _button(records, "Day %d · %s" % [record.day, rules.contract(record.run).title], _select_record.bind(index), index == journal_index)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var selected: Dictionary = state.journal[journal_index]
	var run: Dictionary = selected.run
	var result := rules.debrief(run)
	var contract := rules.contract(run)
	_heading(parent, "Guild journal", contract.title, "%s · Returned on day %d" % [contract.location, selected.day])
	_result_panel(parent, result)
	if not result.prospects.is_empty():
		var prospects := _panel(parent)
		for prospect: String in result.prospects:
			_text(prospects, "%s logged field experience as a guild prospect." % prospect, 13, GOLD)
	var compare := _panel(parent)
	_text(compare, "Compare a different response", 23, INK, true)
	_text(compare, "Use the same party and die roll to see what another order would have changed.", 13, MUTED)
	for order: Dictionary in rules.plans(run):
		if order.id != result.order.id:
			_button(compare, order.title, _compare.bind(order.id), comparison == order.id)
	if comparison != "":
		_result_panel(compare, rules.debrief(run, comparison))
	_button(records, "Start a new playthrough", _confirm_reset)


func _result_panel(parent: VBoxContainer, result: Dictionary) -> void:
	var panel := _panel(parent)
	_text(panel, "PLAN SUCCEEDED" if result.success else "PLAN FELL SHORT", 12, GREEN if result.success else RUST)
	_text(panel, result.order.title, 28, INK, true)
	_text(panel, result.story, 15, INK)
	var metrics := _row(panel, 8)
	_metric(metrics, "Check total", "%d / DC %d" % [result.total, result.check.dc])
	_metric(metrics, "Contract payout", "%d gp" % result.gold)
	_metric(metrics, "Patron standing", _signed(result.standing))
	_text(panel, "Check breakdown", 19, INK, true)
	_check_line(panel, "d20 roll", str(result.roll))
	for contribution: Dictionary in result.check.contributions:
		var name: String = rules.scenario.abilities[contribution.ability]
		_check_line(panel, "%s · %s · %s" % [contribution.role, contribution.name, name], _signed(contribution.modifier))
	_check_line(panel, "Party chemistry", _signed(result.check.chemistry))
	_text(panel, "Trust changes", 19, INK, true)
	for bond: Dictionary in result.bonds:
		_check_line(panel, _pair_name(bond.pair), "%s  (%s → %s)" % [_signed(bond.change), _signed(bond.trust), _signed(bond.after)])


func _metric(parent: HBoxContainer, label: String, value: String) -> void:
	var box := _panel(parent, Color("#2d2c22"), LINE, 8)
	_panel_frame(box).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text(box, label, 12, MUTED)
	_text(box, value, 20, GOLD)


func _check_line(parent: VBoxContainer, label: String, value: String) -> void:
	var row := _row(parent)
	_text(row, label, 13, MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text(row, value, 13, INK)


func _navigate(destination: String) -> void:
	screen = destination
	comparison = ""
	_render()


func _toggle_scores(id: String) -> void:
	expanded_scores[id] = not expanded_scores.get(id, false)
	_render(true)


func _toggle_member(id: String) -> void:
	if rules.toggle_member(state, id):
		_save_and_render()


func _assign_role(index: int, role: String, ids: Array) -> void:
	if rules.assign(state, role, ids[index]):
		_save_and_render()


func _inspect_quest(id: String) -> void:
	selected_quest = id
	inspected[id] = true
	_render(true)


func _depart(id: String) -> void:
	if rules.accept(state, id, randi_range(1, 20)):
		selected_quest = ""
		screen = "contract"
		_save_and_render(false)
		_generate_open_offers()


func _choose(id: String) -> void:
	if rules.choose_plan(state, id):
		if state.expedition.is_empty():
			_open_debrief()
		_save_and_render(false)


func _toggle_time() -> void:
	state.paused = not state.paused
	clock.paused = state.paused
	_save_and_render()


func _day_passed() -> void:
	if not rules.advance_day(state):
		return
	clock.paused = state.paused
	if state.paused:
		if state.expedition.is_empty():
			_open_debrief()
		else:
			screen = "contract"
	_save_and_render(not state.paused)
	_generate_open_offers()


func _open_debrief() -> void:
	screen = "journal"
	journal_index = 0
	comparison = ""


func _select_record(index: int) -> void:
	journal_index = index
	comparison = ""
	_render()


func _reconnect_ai() -> void:
	requested.clear()
	writer.discover()


func _writer_status_changed() -> void:
	if screen == "map":
		_render(true)
	# Allow the completed request to deliver its stories before queueing the next batch.
	_generate_open_offers.call_deferred()


func _generate_open_offers() -> void:
	if not use_local_ai or not writer.can_write():
		return
	var drafts: Array = []
	for offer: Dictionary in state.offers:
		if offer.source == "ai" or inspected.has(offer.id) or requested.has(offer.id):
			continue
		requested[offer.id] = true
		var site: Dictionary = rules.board.sites[offer.site]
		drafts.append({
			"id": offer.id, "location": site.name, "lore": site.lore,
			"patron": site.patron, "affiliation": site.affiliation, "seed_title": offer.title,
			"suggested_work": offer.brief, "possible_complication": offer.report,
			"approaches": [offer.responses[0].title, offer.responses[1].title],
		})
	if drafts.is_empty():
		return
	var context: Array = state.notices.slice(0, 3)
	for entry: Dictionary in state.journal.slice(0, 3):
		var result := rules.debrief(entry.run)
		context.append({"day": entry.day, "title": rules.contract(entry.run).title, "outcome": result.story})
	writer.write_stories(rules.board.world, state.day, context, drafts)


func _apply_stories(stories: Array) -> void:
	var changed := false
	for story: Variant in stories:
		if not story is Dictionary or not story.get("id") is String or inspected.has(story.id) or not requested.has(story.id):
			continue
		var offer := rules.board.by_id(state, story.id)
		if not offer.is_empty() and offer.source == "procedural" and rules.board.apply_story(state, offer, story):
			changed = true
	if changed:
		if screen == "map":
			_save_and_render()
		else:
			save_failed = GuildSave.write(state, save_path) != OK


func _compare(id: String) -> void:
	comparison = "" if comparison == id else id
	_render(true)


func _confirm_reset() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Start a new playthrough"
	dialog.dialog_text = "Clear guild progress, including the current expedition and journal?"
	dialog.get_ok_button().text = "Start over"
	dialog.confirmed.connect(_reset)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _reset() -> void:
	state = rules.fresh()
	rules.open_session(state)
	clock.start()
	clock.paused = true
	selected_quest = ""
	inspected.clear()
	requested.clear()
	journal_index = 0
	comparison = ""
	expanded_scores.clear()
	screen = "map"
	_save_and_render(false)
	if use_local_ai:
		writer.discover()


func _save_and_render(preserve_scroll := true) -> void:
	save_failed = GuildSave.write(state, save_path) != OK
	_render(preserve_scroll)


func _heading(parent: VBoxContainer, eyebrow: String, title: String, subtitle: String) -> void:
	_kicker(parent, eyebrow)
	_text(parent, title, 49, INK, true)
	_text(parent, subtitle, 16, MUTED)


func _kicker(parent: Control, value: String) -> void:
	_text(parent, value.to_upper(), 12, GOLD)


func _signed(number: int) -> String:
	if number > 0:
		return "+%d" % number
	return str(number)


func _trust_name(trust: int) -> String:
	if trust >= 3:
		return "Trusted"
	if trust >= 1:
		return "Familiar"
	return "Strained" if trust < 0 else "Unproven"


func _pair_name(pair: Array) -> String:
	return rules.members[pair[0]].name.get_slice(" ", 0) + " & " + rules.members[pair[1]].name.get_slice(" ", 0)


func _text(parent: Control, value: String, size := 14, tint := INK, use_serif := false) -> Label:
	var label := Label.new()
	label.text = value
	if not parent is HBoxContainer:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", tint)
	if use_serif:
		label.add_theme_font_override("font", serif)
	parent.add_child(label)
	return label


func _button(parent: Control, title: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 33
	button.add_theme_font_size_override("font_size", 13)
	var fill := GOLD if primary else Color("#302e24")
	var ink := RAIL if primary else INK
	for mode: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(mode, ink)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _box(fill, fill.lightened(0.1), 5, 8))
	button.add_theme_stylebox_override("hover", _box(fill.lightened(0.12), GOLD, 5, 8))
	button.add_theme_stylebox_override("pressed", _box(fill.darkened(0.08), GOLD, 5, 8))
	button.add_theme_stylebox_override("disabled", _box(Color("#25251e"), LINE, 5, 8))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _panel(parent: Control, fill := SURFACE, border := LINE, inset := 13) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(fill, border, 6, 0))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	_padding(margin, inset)
	panel.add_child(margin)
	return _column(margin)


func _panel_frame(content: VBoxContainer) -> PanelContainer:
	return content.get_parent().get_parent() as PanelContainer


func _box(fill: Color, border: Color, radius: int, inset: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = inset
	style.content_margin_right = inset
	return style


func _padding(margin: MarginContainer, amount: int) -> void:
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, amount)


func _column(parent: Control, gap := 7) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", gap)
	parent.add_child(column)
	return column


func _row(parent: Control, gap := 12) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", gap)
	parent.add_child(row)
	return row


func _space(parent: Control, height: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)
