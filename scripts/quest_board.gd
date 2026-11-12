extends RefCounted

const OFFER_COUNT := 3
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
var sites := {}


func _init() -> void:
	for site: Dictionary in world.sites:
		sites[site.id] = site


func fill(state: Dictionary) -> void:
	var occupied := {}
	if not state.expedition.is_empty():
		var active: Dictionary = state.expedition.get("quest", {})
		occupied[active.get("site", "ashford")] = true
	for offer: Dictionary in state.offers:
		occupied[offer.site] = true
	while state.offers.size() < OFFER_COUNT:
		var site: Dictionary = world.sites[state.next_site % world.sites.size()]
		state.next_site += 1
		if occupied.has(site.id):
			continue
		var offer := _offer(state, site)
		state.offers.append(offer)
		occupied[site.id] = true


func _offer(state: Dictionary, site: Dictionary) -> Dictionary:
	var number: int = state.next_offer
	state.next_offer += 1
	var visit: int = state.site_visits.get(site.id, 0)
	state.site_visits[site.id] = visit + 1
	var job: Array = site.jobs[visit % site.jobs.size()]
	var incident := int(visit / float(site.jobs.size()))
	var complication: String = site.complications[incident % site.complications.size()]
	var title: String = job[0]
	if incident > 0:
		title += " · Dispatch %d" % (incident + 1)
	while state.seen_titles.has(title.to_lower()):
		title += " #%d" % number
	var difficulty := (number - 1) % 3
	var dc: int = [12, 16, 20][difficulty]
	var fee: int = [45, 75, 115][difficulty] + (int(site.travel) - 1) * 10
	var responses: Array = APPROACHES[(visit + int(site.travel)) % APPROACHES.size()].duplicate(true)
	for index in responses.size():
		var order: Dictionary = responses[index]
		order.merge({
			"id": ["first", "second"][index], "dc": dc + index,
			"gold": [fee, 0], "standing": [1 + difficulty, -1], "trust": [1, -1],
			"success": "The party completed the assignment at %s. %s paid the agreed fee." % [site.name, site.patron],
			"failure": "The party returned from %s with the assignment unfinished. %s withheld the fee." % [site.name, site.patron],
		})
	state.seen_titles[title.to_lower()] = true
	return {
		"id": str(number), "site": site.id, "title": title, "brief": job[1], "report": complication,
		"location": site.name, "patron": site.patron, "affiliation": site.affiliation,
		"fee": fee, "travel": int(site.travel), "work": 1 + difficulty,
		"deadline": state.day + 3 + (number % 4), "responses": responses, "source": "procedural",
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
	if state.seen_titles.has(title_key):
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
