extends RefCounted

const Expedition = preload("res://scripts/expedition.gd")
const PATH := "user://alder-company.cfg"


static func read(rules: Expedition, path: String = PATH) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path) == OK:
		var saved: Variant = config.get_value("guild", "state", null)
		if rules.valid_state(saved):
			return saved
	return rules.fresh()


static func write(state: Dictionary, path: String = PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("guild", "state", state)
	var pending := path + ".tmp"
	var error := config.save(pending)
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(pending), ProjectSettings.globalize_path(path))
