extends RefCounted

const REGIONAL_OFFERS := 2
const LOOT := ["trail_map", "spear", "leather", "climbers_kit", "dagger", "chain_shirt"]
const APPROACHES := [
	[
		{"title": "Organize local help", "focus": "Coordination", "description": "Have the Captain organize the people on site while the Scout reads the situation and Support does the heavy work.", "leadAbility": "cha", "scoutAbility": "wis", "supportAbility": "str"},
		{"title": "Take a quiet route", "focus": "Reconnaissance", "description": "Read the ground first. Send the Scout ahead and have Support work out a way past the obstacle.", "leadAbility": "wis", "scoutAbility": "dex", "supportAbility": "int"},
	],
	[
		{"title": "Survey the site", "focus": "Investigation", "description": "Compare what you find on site with the patron’s account, then work through the problem with the old plans in hand.", "leadAbility": "int", "scoutAbility": "wis", "supportAbility": "int"},
		{"title": "Secure the approach", "focus": "Fieldwork", "description": "Set an anchor and clear a path. Use a stable approach to reach the objective before conditions change.", "leadAbility": "str", "scoutAbility": "dex", "supportAbility": "con"},
	],
	[
		{"title": "Work with the witnesses", "focus": "Negotiation", "description": "Hear the witnesses separately, then ask them to agree on a plan they can carry out with the party.", "leadAbility": "cha", "scoutAbility": "wis", "supportAbility": "cha"},
		{"title": "Follow the physical clues", "focus": "Tracking", "description": "Look for evidence along the approach, follow the trail and test your theory before committing the party.", "leadAbility": "wis", "scoutAbility": "dex", "supportAbility": "int"},
	],
]
const AI_FIELDS := {"title": 48, "brief": 350, "report": 350, "first_success": 240, "first_failure": 240, "second_success": 240, "second_failure": 240}

var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/alderford.json"))
var stories: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/questlines.json"))
var sites := {}
var region_sites: Array[Dictionary] = []


func _init() -> void:
	for site: Dictionary in world.sites:
		sites[site.id] = site
		if site.travel > 0:
			region_sites.append(site)


func fill(state: Dictionary) -> void:
	var occupied := {}
	var open_lines := {}
	var active: Dictionary = state.expedition.get("quest", {})
	if not state.expedition.is_empty():
		occupied[active.get("site", "ashford")] = true
		open_lines[active.get("line", "")] = true
	var regional := 0
	var has_town := false
	for offer: Dictionary in state.offers:
		if offer.has("line"):
			open_lines[offer.line] = true
		elif offer.site == "alderford":
			has_town = true
		else:
			occupied[offer.site] = true
			regional += 1
	while regional < REGIONAL_OFFERS:
		var site: Dictionary = region_sites[state.next_site % region_sites.size()]
		state.next_site += 1
		if occupied.has(site.id):
			continue
		state.offers.append(_offer(state, site))
		occupied[site.id] = true
		regional += 1
	if not has_town:
		state.offers.append(_offer(state, sites.alderford))
	for line: Dictionary in stories:
		var progress: Dictionary = state.questlines.get(line.id, {})
		var step: int = progress.get("step", 0)
		if not open_lines.has(line.id) and step < line.chapters.size() and state.day >= int(progress.get("available", 1)):
			state.offers.append(_chapter_offer(state, line, step))


func _offer(state: Dictionary, site: Dictionary) -> Dictionary:
	var number: int = state.next_offer
	state.next_offer += 1
	var visit: int = state.site_visits.get(site.id, 0)
	state.site_visits[site.id] = visit + 1
	var job: Array = site.jobs[visit % site.jobs.size()]
	var incident := floori(visit / float(site.jobs.size()))
	var complication: String = site.complications[incident % site.complications.size()]
	var title: String = job[0]
	if incident > 0:
		title += " · Dispatch %d" % (incident + 1)
	while state.seen_titles.has(title.to_lower()):
		title += " #%d" % number
	var town: bool = site.travel == 0
	var difficulty := visit % 2 if town else (number - 1) % 3
	var commission := number % 3 != 0 and (not town or visit % 2 == 1)
	var dc: int = [12, 16, 20][difficulty]
	var fee: int = ([45, 75, 115][difficulty] + maxi(0, int(site.travel) - 1) * 10) if commission else 0
	var responses: Array = APPROACHES[(visit + int(site.travel)) % APPROACHES.size()].duplicate(true)
	for index in responses.size():
		var order: Dictionary = responses[index]
		order.merge({
			"id": ["first", "second"][index], "dc": dc + index,
			"gold": [fee, 0], "standing": [1 + difficulty, -1] if commission else [0, 0], "trust": [1, -1],
			"success": "The party completed the assignment at %s. %s paid the agreed fee." % [site.name, site.patron] if commission else "The party resolved the matter at %s and recovered useful gear." % site.name,
			"failure": "The party returned from %s with the matter still unresolved." % site.name,
		})
	state.seen_titles[title.to_lower()] = true
	return {
		"id": str(number), "site": site.id, "title": title, "brief": job[1], "report": complication,
		"location": site.name, "patron": site.patron if commission else "", "affiliation": site.affiliation if commission else "",
		"fee": fee, "travel": int(site.travel), "work": 1 + difficulty,
		"deadline": state.day + 3 + (number % 4), "responses": responses, "source": "procedural",
		"xp": [200, 340, 520][difficulty], "loot": LOOT[(number + visit) % LOOT.size()],
	}


func _chapter_offer(state: Dictionary, line: Dictionary, step: int) -> Dictionary:
	var chapter: Dictionary = line.chapters[step]
	var site: Dictionary = sites[chapter.site]
	var number: int = state.next_offer
	state.next_offer += 1
	var responses: Array = []
	for index in chapter.plans.size():
		var plan: Array = chapter.plans[index]
		responses.append({
			"id": ["first", "second"][index], "title": plan[0], "focus": plan[0], "description": plan[1],
			"leadAbility": plan[2], "scoutAbility": plan[3], "supportAbility": plan[4],
			"dc": int(chapter.dc) + index, "gold": [int(chapter.fee), 0], "trust": [1, -1],
			"standing": [2 + step, -1] if chapter.commission else [0, 0],
			"success": plan[5], "failure": plan[6],
		})
	return {
		"id": str(number), "site": site.id, "title": chapter.title, "brief": chapter.brief, "report": chapter.report,
		"location": site.name, "patron": site.patron if chapter.commission else "", "affiliation": site.affiliation if chapter.commission else "",
		"fee": int(chapter.fee), "travel": int(site.travel), "work": int(chapter.work),
		"deadline": state.day + 7, "responses": responses, "source": "story",
		"line": line.id, "line_title": line.title, "chapter": step, "chapters": line.chapters.size(),
		"xp": int(chapter.xp), "loot": chapter.loot,
	}


func by_id(state: Dictionary, id: String) -> Dictionary:
	for offer: Dictionary in state.offers:
		if offer.id == id:
			return offer
	return {}


func apply_story(state: Dictionary, offer: Dictionary, story: Variant) -> bool:
	if not story is Dictionary:
		return false
	var fields := {}
	for key: String in AI_FIELDS:
		var raw: Variant = story.get(key)
		if not raw is String:
			return false
		var clean: String = raw.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
		if clean.is_empty() or clean.length() > int(AI_FIELDS[key]):
			return false
		fields[key] = clean
	var title_key: String = fields.title.to_lower()
	if state.seen_titles.has(title_key) or _is_story_title(title_key):
		return false
	state.seen_titles[title_key] = true
	offer.title = fields.title
	offer.brief = fields.brief
	offer.report = fields.report
	offer.responses[0].success = fields.first_success
	offer.responses[0].failure = fields.first_failure
	offer.responses[1].success = fields.second_success
	offer.responses[1].failure = fields.second_failure
	offer.source = "ai"
	return true


func _is_story_title(title: String) -> bool:
	for line: Dictionary in stories:
		for chapter: Dictionary in line.chapters:
			if chapter.title.to_lower() == title:
				return true
	return false
