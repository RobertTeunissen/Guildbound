extends Control

signal camera_changed(zoom: float, focus: Vector2)

const PARCHMENT := Color("#d6c59a")
const BASE := Color("#d0bc8d")
const INK := Color("#51432d")
const ROAD := Color("#9d7950")
const RIVER := Color("#668b84")
const FOREST := Color("#78845b")
const GUILD := Vector2(0.44, 0.45)
const RIVER_POINTS := [Vector2(0.58, 0), Vector2(0.60, 0.11), Vector2(0.68, 0.20), Vector2(0.72, 0.27), Vector2(0.70, 0.34), Vector2(0.61, 0.41), Vector2(0.54, 0.53), Vector2(0.57, 0.59), Vector2(0.65, 0.64), Vector2(0.72, 0.73), Vector2(0.74, 0.84), Vector2(0.67, 1.0)]
const WAYPOINTS := {
	"north_road": [Vector2(0.43, 0.35), Vector2(0.36, 0.27)],
	"rookbridge": [Vector2(0.51, 0.43), Vector2(0.60, 0.33), Vector2(0.68, 0.29)],
	"ashford": [Vector2(0.48, 0.54), Vector2(0.54, 0.59), Vector2(0.60, 0.63)],
	"south_wall": [Vector2(0.40, 0.54), Vector2(0.30, 0.60)],
}

var sites: Array
var active_site := ""
var font: Font
var markers: Dictionary = {}
var route_step := 0.0
var zoom := 1.0
var focus := Vector2(0.5, 0.5)
var dragging := false
var terrain := Control.new()


func _ready() -> void:
	custom_minimum_size = Vector2(385, 338)
	clip_contents = true
	terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(terrain)
	terrain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	terrain.draw.connect(_draw_terrain)
	resized.connect(_layout_markers)


func change_zoom(factor: float, anchor := Vector2.INF) -> void:
	if size.x < 18.0 or size.y < 18.0:
		return
	var local_anchor := size * 0.5 if anchor == Vector2.INF else anchor
	var distance := (local_anchor - size * 0.5) / size
	var new_zoom := clampf(zoom * factor, 1.0, 3.0)
	focus += distance / zoom - distance / new_zoom
	zoom = new_zoom
	_camera_changed()


func reset_camera() -> void:
	zoom = 1.0
	focus = Vector2(0.5, 0.5)
	_camera_changed()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			change_zoom(1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8, event.position)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			dragging = event.pressed and zoom > 1.0
			mouse_default_cursor_shape = Control.CURSOR_DRAG if dragging else Control.CURSOR_ARROW
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		focus -= event.relative / (size * zoom)
		_camera_changed()
		accept_event()


func _camera_changed() -> void:
	var margin := 0.5 / zoom
	focus = focus.clamp(Vector2(margin, margin), Vector2(1.0 - margin, 1.0 - margin))
	_layout_markers()
	camera_changed.emit(zoom, focus)


func _project(point: Vector2) -> Vector2:
	return (point - focus) * size * zoom + size * 0.5


func add_marker(site_id: String, point: Vector2, button: Button) -> void:
	markers[site_id] = [point, button]
	_layout_markers()


func _layout_markers() -> void:
	if size.x < 18.0:
		return
	for marker: Array in markers.values():
		var button: Button = marker[1]
		button.size = Vector2(minf(button.get_combined_minimum_size().x, size.x - 18.0), 32)
		var anchor := _project(marker[0])
		button.visible = Rect2(Vector2.ZERO, size).has_point(anchor)
		button.position = Vector2(clampf(anchor.x - button.size.x / 2, 9, size.x - button.size.x - 9), anchor.y + 10)
	terrain.queue_redraw()


func _draw_terrain() -> void:
	terrain.draw_rect(Rect2(Vector2.ZERO, size), BASE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 641
	for index in 235:
		var point := _project(Vector2(rng.randf(), rng.randf()))
		var radius := rng.randf_range(0.6, 2.3)
		terrain.draw_circle(point, radius, Color(0.27, 0.19, 0.09, 0.09), true, -1.0, true)
	for patch: Vector4 in [Vector4(0.13, 0.20, 0.13, 0.15), Vector4(0.90, 0.47, 0.08, 0.17), Vector4(0.41, 0.79, 0.10, 0.11)]:
		for index in 24:
			var angle := rng.randf_range(0, TAU)
			var extent := sqrt(rng.randf())
			var tree := _project(Vector2(patch.x + cos(angle) * extent * patch.z, patch.y + sin(angle) * extent * patch.w))
			_draw_tree(tree, rng.randf_range(4, 7))
	for index in 12:
		var center := _project(Vector2(0.13 + index * 0.038, 0.07 + rng.randf_range(-0.035, 0.035)))
		var height := rng.randf_range(6, 17)
		terrain.draw_polyline(PackedVector2Array([center + Vector2(-height, 0), center - Vector2(0, height), center + Vector2(height, 0)]), Color("#a7936f"), 1.1, true)
	var river := _points(RIVER_POINTS)
	terrain.draw_polyline(river, Color("#b3b59b"), 19, true)
	terrain.draw_polyline(river, RIVER, 12, true)
	terrain.draw_polyline(river, RIVER.lightened(0.22), 2, true)
	for site: Dictionary in sites:
		var target := Vector2(site.map[0], site.map[1])
		var active: bool = site.id == active_site
		if site.id != "alderford":
			var waypoints: Array = [GUILD]
			waypoints.append_array(WAYPOINTS[site.id])
			waypoints.append(target)
			var road := _points(waypoints)
			terrain.draw_polyline(road, Color("#9a4d32") if active else ROAD, 3.4 if active else 1.5, true)
			if active:
				_draw_party(road)
		var pin := _project(target)
		if site.id == "alderford":
			_draw_town(pin, active)
			continue
		if markers.has(site.id):
			terrain.draw_circle(pin, 7, INK, true, -1.0, true)
			terrain.draw_circle(pin, 4, Color("#a04e34") if active else PARCHMENT, true, -1.0, true)
		else:
			terrain.draw_circle(pin, 3, ROAD, true, -1.0, true)
			_map_label(site.name, pin + Vector2(0, 20), 13)
	var compass := Vector2(size.x - 26, 42)
	_map_label("N", compass - Vector2(0, 18), 15)
	terrain.draw_colored_polygon(PackedVector2Array([compass + Vector2(0, -12), compass + Vector2(5, 7), compass, compass + Vector2(-5, 7)]), INK)
	terrain.draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), Color("#a59169"), false, 1.0)


func _draw_town(home: Vector2, active: bool) -> void:
	var color := Color("#9a4d32") if active else INK
	terrain.draw_colored_polygon(PackedVector2Array([home + Vector2(0, -10), home + Vector2(8, -2), home + Vector2(8, 7), home + Vector2(-8, 7), home + Vector2(-8, -2)]), color)
	terrain.draw_rect(Rect2(home + Vector2(-2, 0), Vector2(4, 7)), PARCHMENT)
	if not markers.has("alderford"):
		_map_label("Alderford", home + Vector2(0, 23), 15)


func _draw_party(road: PackedVector2Array) -> void:
	var path := Curve2D.new()
	for point: Vector2 in road:
		path.add_point(point)
	var position_on_road := path.sample_baked(path.get_baked_length() * route_step)
	terrain.draw_circle(position_on_road, 6, PARCHMENT, true, -1.0, true)
	terrain.draw_circle(position_on_road, 3.5, Color("#9a4d32"), true, -1.0, true)


func _draw_tree(point: Vector2, height: float) -> void:
	terrain.draw_colored_polygon(PackedVector2Array([point - Vector2(0, height), point + Vector2(height * 0.55, 0), point - Vector2(height * 0.55, 0)]), FOREST)
	terrain.draw_line(point, point + Vector2(0, 2), INK, 1.0, true)


func _points(coordinates: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in coordinates:
		points.append(_project(point))
	return points


func _map_label(value: String, anchor: Vector2, font_size: int) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	terrain.draw_string(font, anchor - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
