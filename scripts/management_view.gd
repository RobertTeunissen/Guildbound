extends RefCounted

const Campaign = preload("res://scripts/campaign.gd")
const Characters = preload("res://scripts/characters.gd")
const GOLD := Color("#e5c083")
const MUTED := Color("#b8b3a2")
const GREEN := Color("#bfcea4")
const RUST := Color("#edab98")

var ui: Control
var rules: Campaign
var charter_draft := {}
var founders: Array[String] = []
var character_id := ""
var scout_id := ""
var shop_open := false


func _init(host: Control, campaign: Campaign) -> void:
	ui = host
	rules = campaign


func render(screen: String, state: Dictionary, main: VBoxContainer, aside: VBoxContainer) -> void:
	match screen:
		"founding":
			_founding(state, main, aside)
		"guild":
			_guild(state, main, aside)
		"armory":
			_armory(state, main, aside)
		"character":
			_character(state, main, aside)
		"recruit":
			_recruit(state, main, aside)


func reset() -> void:
	charter_draft.clear()
	founders.clear()
	character_id = ""
	scout_id = ""
	shop_open = false


func _founding(state: Dictionary, main: VBoxContainer, aside: VBoxContainer) -> void:
	ui._heading(main, "New campaign", "Found your guild", "Choose three founders. The first is Captain, the second Scout. You can change both assignments later.")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	main.add_child(grid)
	for id: String in rules.founding_ids:
		var member: Dictionary = rules.members[id]
		var card: VBoxContainer = ui._panel(grid)
		ui._panel_frame(card).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ui._add_portrait(card, id, 70)
		ui._text(card, member.name, 22)
		ui._text(card, "%s · Level %d" % [member.className, member.level], 13, GOLD)
		ui._text(card, member.specialty, 12, MUTED)
		var index := founders.find(id)
		var role: String = ["Captain", "Scout", "Support"][index] if index >= 0 else ""
		var button: Button = ui._button(card, "Select %s" % member.name if role == "" else "%s · Remove" % role, _toggle_founder.bind(id), role != "")
		button.disabled = index < 0 and founders.size() >= int(rules.scenario.partySize)
	_charter_form(state, aside, true)


func _guild(state: Dictionary, main: VBoxContainer, aside: VBoxContainer) -> void:
	var motto: String = state.charter.motto
	ui._heading(main, "Guildhall", state.charter.name, motto if not motto.is_empty() else "Alderford")
	var standing: VBoxContainer = ui._panel(main)
	ui._text(standing, "Patron standings", 25)
	for site: Dictionary in rules.board.world.sites:
		var value := int(state.patron_standings.get(site.patron, 0))
		ui._check_line(standing, site.patron, ui._signed(value))
	var lines: VBoxContainer = ui._panel(main)
	ui._text(lines, "Quest lines", 25)
	for line: Dictionary in rules.board.stories:
		var progress: Dictionary = state.questlines.get(line.id, {})
		var step: int = progress.get("step", 0)
		var count: int = line.chapters.size()
		ui._check_line(lines, line.title, "Completed" if step >= count else "%d / %d chapters" % [step, count])
	_charter_form(state, aside, false)
	ui._button(aside, "Start a new playthrough", ui._confirm_reset)


func _charter_form(state: Dictionary, parent: VBoxContainer, founding: bool) -> void:
	if charter_draft.is_empty():
		charter_draft = state.charter.duplicate()
	var panel: VBoxContainer = ui._panel(parent)
	ui._text(panel, "Guild charter", 24)
	_field(panel, "Guild name", "name", 40)
	_field(panel, "Motto", "motto", 80)
	ui._text(panel, "Purpose and terms", 13, MUTED)
	var terms := TextEdit.new()
	terms.text = charter_draft.terms
	terms.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	terms.placeholder_text = "What will this guild stand for?"
	terms.custom_minimum_size.y = 112
	terms.text_changed.connect(_edit_terms.bind(terms))
	panel.add_child(terms)
	var feedback: Label = ui._text(panel, "", 13, RUST)
	if founding:
		ui._text(panel, "%d / %d founders selected" % [founders.size(), int(rules.scenario.partySize)], 13, GOLD)
	var button: Button = ui._button(panel, "Sign charter and begin" if founding else "Save charter", _sign.bind(founding, feedback), true)
	button.disabled = founding and founders.size() != int(rules.scenario.partySize)


func _field(parent: VBoxContainer, label: String, key: String, max_length: int) -> void:
	ui._text(parent, label, 13, MUTED)
	var field := LineEdit.new()
	field.name = "Charter_" + key
	field.max_length = max_length
	field.text = charter_draft[key]
	field.text_changed.connect(_edit_charter.bind(key))
	parent.add_child(field)


func _edit_charter(value: String, key: String) -> void:
	charter_draft[key] = value


func _edit_terms(terms: TextEdit) -> void:
	charter_draft.terms = terms.text


func _toggle_founder(id: String) -> void:
	if founders.has(id):
		founders.erase(id)
	elif founders.size() < int(rules.scenario.partySize):
		founders.append(id)
	ui._render(true)


func _sign(founding: bool, feedback: Label) -> void:
	var state: Dictionary = ui.state
	var saved := rules.found_guild(state, charter_draft, founders) if founding else rules.save_charter(state, charter_draft)
	if not saved:
		feedback.text = "Enter a guild name to sign the charter."
		return
	charter_draft.clear()
	if founding:
		ui.screen = "map"
	ui._save_and_render(false)
	ui._generate_open_offers()


func _armory(state: Dictionary, main: VBoxContainer, aside: VBoxContainer) -> void:
	ui._heading(main, "Equipment", "Armory", "The guild stash holds purchases, quest loot, and unequipped gear.")
	var tabs: HBoxContainer = ui._row(main)
	ui._button(tabs, "Guild stash", _show_shop.bind(false), not shop_open)
	ui._button(tabs, "Town shop", _show_shop.bind(true), shop_open)
	if not shop_open and state.stash.is_empty():
		ui._text(ui._panel(main), "The stash is empty.", 15, MUTED)
	for id: String in rules.characters.items:
		var item: Dictionary = rules.characters.items[id]
		var quantity := int(state.stash.get(id, 0))
		if (shop_open and item.get("reward_only", false)) or (not shop_open and quantity == 0):
			continue
		var card: VBoxContainer = ui._panel(main)
		var header: HBoxContainer = ui._row(card)
		var label: Label = ui._text(header, item.name if shop_open else "%s ×%d" % [item.name, quantity], 18)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button: Button
		if shop_open:
			button = ui._button(header, "Buy · %d gp" % item.price, _trade.bind(id, true))
			button.disabled = state.treasury < item.price
		else:
			button = ui._button(header, "Sell · %d gp" % rules.sale_price(id), _trade.bind(id, false))
		ui._text(card, item.description, 13, MUTED)
	var roster: VBoxContainer = ui._panel(aside)
	ui._text(roster, "Manage loadouts", 23)
	for id: String in state.guild_roster:
		ui._button(roster, rules.members[id].name, _open_character.bind(id))


func _show_shop(value: bool) -> void:
	shop_open = value
	ui._render()


func _trade(item_id: String, purchase: bool) -> void:
	var changed := rules.buy(ui.state, item_id) if purchase else rules.sell(ui.state, item_id)
	if changed:
		ui._save_and_render()


func _open_character(id: String) -> void:
	character_id = id
	ui._navigate("character")


func _character(state: Dictionary, main: VBoxContainer, aside: VBoxContainer) -> void:
	var member: Dictionary = rules.members[character_id]
	var progress: Dictionary = state.character_progress[character_id]
	var sheet := rules.characters.sheet(member, progress)
	var profile: Dictionary = sheet.profile
	var available := rules.available_member(state, character_id)
	ui._heading(main, "Character sheet", member.name, "%s · Level %d %s · %s · %s" % [profile.ancestry, sheet.level, member.className, profile.background, profile.alignment])
	var core: VBoxContainer = ui._panel(main)
	var metrics: HBoxContainer = ui._row(core)
	ui._metric(metrics, "Hit points", "%d / %d" % [sheet.hp, sheet.hp])
	ui._metric(metrics, "Armor class", str(sheet.ac))
	ui._metric(metrics, "Speed", "%d ft." % sheet.speed)
	ui._check_line(core, "Proficiency bonus", ui._signed(sheet.proficiency))
	ui._check_line(core, "Initiative", ui._signed(sheet.initiative))
	ui._check_line(core, "Hit dice", "%dd%d" % [sheet.level, sheet.hit_die])
	ui._check_line(core, "Passive Perception", str(sheet.passive_perception))
	ui._check_line(core, "Experience", "%d / %d XP" % [sheet.xp, sheet.next_xp] if sheet.next_xp > 0 else "%d XP · Maximum level" % sheet.xp)
	var points := rules.characters.remaining_increases(member, progress)
	_abilities(main, sheet, points, available)
	_skills(main, member, progress, sheet.stealth_disadvantage)
	_traits(main, profile, sheet)
	_loadout(aside, state, member, progress, sheet, available)


func _abilities(parent: VBoxContainer, sheet: Dictionary, points: int, available: bool) -> void:
	var panel: VBoxContainer = ui._panel(parent)
	ui._text(panel, "Abilities and saving throws", 24)
	if points > 0:
		ui._text(panel, "%d ability points to assign" % points, 13, GOLD)
	for ability: String in rules.scenario.abilities:
		var row: HBoxContainer = ui._row(panel)
		var stat: Dictionary = sheet.abilities[ability]
		var label: Label = ui._text(row, rules.scenario.abilities[ability], 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ui._text(row, "%d (%s) · Save %s" % [stat.score, ui._signed(stat.modifier), ui._signed(stat.save)], 14, GREEN if stat.save_trained else MUTED)
		if points > 0:
			var add: Button = ui._button(row, "+1", _improve.bind(ability))
			add.disabled = stat.score >= 20 or not available
			add.tooltip_text = "Increase " + rules.scenario.abilities[ability]


func _improve(ability: String) -> void:
	if rules.improve(ui.state, character_id, ability):
		ui._save_and_render()


func _skills(parent: VBoxContainer, member: Dictionary, progress: Dictionary, noisy: bool) -> void:
	var panel: VBoxContainer = ui._panel(parent)
	ui._text(panel, "Skills", 24)
	var pair: HBoxContainer = ui._row(panel, 18)
	var first: VBoxContainer = ui._column(pair, 3)
	var second: VBoxContainer = ui._column(pair, 3)
	first.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	second.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var index := 0
	for skill: String in Characters.SKILLS:
		var target := first if index < 9 else second
		ui._check_line(target, skill, ui._signed(rules.characters.skill_bonus(member, progress, skill)))
		index += 1
	if noisy:
		ui._text(panel, "Armor imposes disadvantage on Stealth checks.", 13, MUTED)


func _traits(parent: VBoxContainer, profile: Dictionary, sheet: Dictionary) -> void:
	var panel: VBoxContainer = ui._panel(parent)
	ui._text(panel, "Features and proficiencies", 24)
	ui._text(panel, sheet.ancestry_traits, 13, GOLD)
	for feature: String in sheet.features:
		ui._text(panel, feature, 13)
	ui._text(panel, "Armor · " + _joined_names(sheet.armor), 13, MUTED)
	ui._text(panel, "Weapons · " + _joined_names(sheet.weapons), 13, MUTED)
	ui._text(panel, "Tools · " + _joined_names(profile.tools), 13, MUTED)
	ui._text(panel, "Languages · " + ", ".join(PackedStringArray(profile.languages)), 13, MUTED)
	ui._text(panel, profile.traits, 14)
	if not sheet.casting.is_empty():
		var magic: VBoxContainer = ui._panel(parent)
		ui._text(magic, "Spellcasting", 24)
		ui._check_line(magic, "Spell attack", ui._signed(sheet.casting.attack))
		ui._check_line(magic, "Spell save DC", str(sheet.casting.dc))
		var index := 0
		for spells: Array in sheet.casting.spells:
			if not spells.is_empty():
				var label := "Cantrips" if index == 0 else "Level %d · %d slots" % [index, sheet.casting.slots[index - 1]]
				ui._text(magic, label, 13, GOLD)
				ui._text(magic, ", ".join(PackedStringArray(spells)), 13)
			index += 1


func _joined_names(values: Array) -> String:
	var titles: Array[String] = []
	for value: String in values:
		titles.append(value.replace("_", " ").capitalize())
	return ", ".join(titles) if not titles.is_empty() else "None"


func _loadout(parent: VBoxContainer, state: Dictionary, member: Dictionary, progress: Dictionary, sheet: Dictionary, available: bool) -> void:
	var panel: VBoxContainer = ui._panel(parent)
	ui._text(panel, "Equipment", 24)
	ui._text(panel, "%s · %s to hit · %s" % [sheet.attack.name, ui._signed(sheet.attack.to_hit), sheet.attack.damage], 13, GOLD)
	if not available:
		ui._text(panel, "Loadout locked while this member is away.", 13, MUTED)
	for slot: String in Characters.SLOTS:
		var current: String = progress.gear.get(slot, "")
		ui._text(panel, Characters.SLOTS[slot], 13, MUTED)
		var picker := OptionButton.new()
		picker.fit_to_longest_item = false
		picker.clip_text = true
		var ids: Array[String] = []
		if current != "":
			picker.add_item(rules.characters.items[current].name)
			ids.append(current)
		picker.add_item("Empty" if current == "" else "Return to stash")
		ids.append("")
		for id: String in state.stash:
			var item: Dictionary = rules.characters.items[id]
			if id == current or item.slot != slot:
				continue
			picker.add_item("%s ×%d" % [item.name, state.stash[id]])
			picker.set_item_disabled(picker.item_count - 1, not rules.characters.can_equip(member, progress, id))
			ids.append(id)
		picker.select(0)
		picker.disabled = not available or ids.size() == 1
		picker.item_selected.connect(_change_gear.bind(ids, slot))
		panel.add_child(picker)
	ui._button(panel, "Open armory", ui._navigate.bind("armory"))
	ui._button(panel, "Back to roster", ui._navigate.bind("roster"))


func _change_gear(index: int, ids: Array[String], slot: String) -> void:
	var id := ids[index]
	var changed := rules.unequip(ui.state, character_id, slot) if id == "" else rules.equip(ui.state, character_id, id)
	if changed:
		ui._save_and_render()


func _recruit(state: Dictionary, main: VBoxContainer, aside: VBoxContainer) -> void:
	ui._heading(main, "Recruitment", "Find new adventurers", "Assign a guild member to look for recruits in Alderford.")
	var mission: VBoxContainer = ui._panel(aside)
	ui._text(mission, "Scouting assignment", 23)
	if not state.scouting.is_empty():
		ui._text(mission, "%s returns on Day %d." % [rules.members[state.scouting.member].name, state.scouting.due_day], 14)
		if state.paused:
			ui._button(mission, "Resume time", ui._toggle_time, true)
	else:
		_scout_picker(state, mission)
	if state.candidates.is_empty():
		ui._text(ui._panel(main), "Recruitment leads will appear here when the scout returns.", 15, MUTED)
	for id: String in state.candidates:
		var member: Dictionary = rules.members[id]
		var profile: Dictionary = rules.characters.data.profiles[id]
		var card: VBoxContainer = ui._panel(main)
		ui._text(card, member.name, 24)
		ui._text(card, "%s · Level %d %s · %s" % [profile.ancestry, member.level, member.className, profile.background], 14, GOLD)
		ui._text(card, member.specialty, 14)
		var fee := rules.recruit_fee(id)
		var button: Button = ui._button(card, "Recruit · %d gp" % fee, _hire.bind(id), true)
		button.disabled = state.treasury < fee


func _scout_picker(state: Dictionary, panel: VBoxContainer) -> void:
	var ids: Array[String] = []
	for id: String in state.guild_roster:
		if rules.available_member(state, id):
			ids.append(id)
	if ids.is_empty() or rules.recruit_pool(state).is_empty():
		var message := "No guild members are available." if ids.is_empty() else "The scout has already found every available recruit."
		ui._text(panel, message, 13, MUTED)
		return
	if not ids.has(scout_id):
		scout_id = state.roles.scout if ids.has(state.roles.scout) else ids[0]
	var picker := OptionButton.new()
	for id: String in ids:
		var perception := rules.characters.skill_bonus(rules.members[id], state.character_progress[id], "Perception")
		picker.add_item("%s · Perception %s" % [rules.members[id].name, ui._signed(perception)])
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.select(ids.find(scout_id))
	picker.item_selected.connect(func(index: int) -> void: scout_id = ids[index])
	panel.add_child(picker)
	ui._text(panel, "Takes %d days. Assigned scouts are away from the expedition party until they return." % Campaign.SCOUT_DAYS, 13, MUTED)
	ui._button(panel, "Send scout", _send_scout, true)


func _send_scout() -> void:
	if rules.start_scouting(ui.state, scout_id):
		ui._save_and_render()


func _hire(id: String) -> void:
	if rules.hire(ui.state, id):
		ui._save_and_render()
