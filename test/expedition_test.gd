extends SceneTree

const Expedition = preload("res://scripts/expedition.gd")
const GuildSave = preload("res://scripts/guild_save.gd")

var rules := Expedition.new()
var failures := 0


func _initialize() -> void:
	_test_lineup()
	_test_outcomes()
	_test_save()
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


func _expect(condition: bool, failure: String) -> void:
	if not condition:
		failures += 1
		push_error(failure)
