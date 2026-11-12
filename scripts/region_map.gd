extends Control

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


func _ready() -> void:
	custom_minimum_size = Vector2(385, 338)
	clip_contents = true
	resized.connect(_layout_markers)


func add_marker(site_id: String, point: Vector2, button: Button) -> void:
	markers[site_id] = [point, button]
	_layout_markers()


func _layout_markers() -> void:
	if size.x < 18.0:
		return
	for marker: Array in markers.values():
		var button: Button = marker[1]
		button.size = Vector2(minf(button.get_combined_minimum_size().x, size.x - 18.0), 32)
		var anchor: Vector2 = marker[0] * size
		button.position = Vector2(clampf(anchor.x - button.size.x / 2, 9, size.x - button.size.x - 9), anchor.y + 10)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BASE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 641
	for index in 235:
		var point := Vector2(rng.randf(), rng.randf()) * size
		var radius := rng.randf_range(0.6, 2.3)
		draw_circle(point, radius, Color(0.27, 0.19, 0.09, 0.09), true, -1.0, true)
	for patch: Vector4 in [Vector4(0.13, 0.20, 0.13, 0.15), Vector4(0.90, 0.47, 0.08, 0.17), Vector4(0.41, 0.79, 0.10, 0.11)]:
		for index in 24:
			var angle := rng.randf_range(0, TAU)
			var extent := sqrt(rng.randf())
			var tree := Vector2(patch.x + cos(angle) * extent * patch.z, patch.y + sin(angle) * extent * patch.w) * size
			_draw_tree(tree, rng.randf_range(4, 7))
	for index in 12:
		var center := Vector2(0.13 + index * 0.038, 0.07 + rng.randf_range(-0.035, 0.035)) * size
		var height := rng.randf_range(6, 17)
		draw_polyline(PackedVector2Array([center + Vector2(-height, 0), center - Vector2(0, height), center + Vector2(height, 0)]), Color("#a7936f"), 1.1, true)
	var river := _points(RIVER_POINTS)
	draw_polyline(river, Color("#b3b59b"), 19, true)
	draw_polyline(river, RIVER, 12, true)
	draw_polyline(river, RIVER.lightened(0.22), 2, true)
	for site: Dictionary in sites:
		var target := Vector2(site.map[0], site.map[1])
		var waypoints: Array = [GUILD]
		waypoints.append_array(WAYPOINTS[site.id])
		waypoints.append(target)
		var road := _points(waypoints)
		var active: bool = site.id == active_site
		draw_polyline(road, Color("#9a4d32") if active else ROAD, 3.4 if active else 1.5, true)
		if active:
			_draw_party(road)
		var pin := target * size
		if markers.has(site.id):
			draw_circle(pin, 7, INK, true, -1.0, true)
			draw_circle(pin, 4, Color("#a04e34") if active else PARCHMENT, true, -1.0, true)
		else:
			draw_circle(pin, 3, ROAD, true, -1.0, true)
			_map_label(site.name, pin + Vector2(0, 20), 13)
	var home := GUILD * size
	draw_colored_polygon(PackedVector2Array([home + Vector2(0, -10), home + Vector2(8, -2), home + Vector2(8, 7), home + Vector2(-8, 7), home + Vector2(-8, -2)]), INK)
	draw_rect(Rect2(home + Vector2(-2, 0), Vector2(4, 7)), PARCHMENT)
	_map_label("Alderford", home + Vector2(0, 23), 15)
	var compass := Vector2(size.x - 26, 42)
	_map_label("N", compass - Vector2(0, 18), 15)
	draw_colored_polygon(PackedVector2Array([compass + Vector2(0, -12), compass + Vector2(5, 7), compass, compass + Vector2(-5, 7)]), INK)
	draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), Color("#a59169"), false, 1.0)


func _draw_party(road: PackedVector2Array) -> void:
	var path := Curve2D.new()
	for point: Vector2 in road:
		path.add_point(point)
	var position_on_road := path.sample_baked(path.get_baked_length() * route_step)
	draw_circle(position_on_road, 6, PARCHMENT, true, -1.0, true)
	draw_circle(position_on_road, 3.5, Color("#9a4d32"), true, -1.0, true)


func _draw_tree(point: Vector2, height: float) -> void:
	draw_colored_polygon(PackedVector2Array([point - Vector2(0, height), point + Vector2(height * 0.55, 0), point - Vector2(height * 0.55, 0)]), FOREST)
	draw_line(point, point + Vector2(0, 2), INK, 1.0, true)


func _points(coordinates: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in coordinates:
		points.append(point * size)
	return points


func _map_label(value: String, anchor: Vector2, font_size: int) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, anchor - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
