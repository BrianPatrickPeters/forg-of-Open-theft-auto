extends Node3D

var selected_kind := "House"
var placed_objects: Array[Node3D] = []
var world_root: Node3D
var camera: Camera3D
var status_label: Label
var camera_target := Vector3.ZERO
var camera_distance := 24.0
var camera_yaw := deg_to_rad(45.0)
var camera_pitch := deg_to_rad(-48.0)
var dragging := false
var last_mouse := Vector2.ZERO
var tool_mode := "place"
var selected_object: Node3D = null

func _ready() -> void:
	_build_world()
	_build_camera()
	_build_ui()
	_update_camera()

func _build_world() -> void:
	world_root = Node3D.new()
	world_root.name = "PlacedObjects"
	add_child(world_root)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.30, 0.27)
	floor.material_override = material
	add_child(floor)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	add_child(light)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	environment.environment = env
	add_child(environment)

	var lines := Node3D.new()
	lines.name = "GridLines"
	add_child(lines)
	var grid_mat := StandardMaterial3D.new()
	grid_mat.albedo_color = Color(0.42, 0.47, 0.44)
	for i in range(-20, 21):
		_grid_line(lines, Vector3(float(i), 0.02, 0), Vector3(0.02, 0.02, 40), grid_mat)
		_grid_line(lines, Vector3(0, 0.02, float(i)), Vector3(40, 0.02, 0.02), grid_mat)

func _grid_line(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = mat
	parent.add_child(mesh)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(15, 15)
	panel.custom_minimum_size = Vector2(245, 0)
	layer.add_child(panel)
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var title := Label.new()
	title.text = "MEIN STADT-EDITOR"
	layout.add_child(title)
	var info := Label.new()
	info.text = "Werkzeug wählen, dann in die Welt klicken."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(info)

	_add_button(layout, "Platzieren", "TOOL_PLACE")
	_add_button(layout, "Auswählen", "TOOL_SELECT")
	_add_button(layout, "Ausgewähltes verschieben", "TOOL_MOVE")
	_add_button(layout, "Größe +", "SCALE_UP")
	_add_button(layout, "Größe −", "SCALE_DOWN")
	_add_button(layout, "Ausgewähltes löschen", "DELETE_SELECTED")
	_add_button(layout, "Kleines Gebäude", "House")
	_add_button(layout, "Mittleres Gebäude", "Medium")
	_add_button(layout, "Grosses Gebäude", "Large")
	_add_button(layout, "2-spurige Strasse", "Road")
	_add_button(layout, "4-spurige Strasse", "Road4")
	_add_button(layout, "Vierwegekreuzung", "Crossroad")
	_add_button(layout, "T-Kreuzung", "TJunction")
	_add_button(layout, "Baum", "Tree")
	_add_button(layout, "Lampe", "Lamp")
	_add_button(layout, "Letztes Objekt löschen", "DELETE_LAST")
	_add_button(layout, "Stadt speichern", "SAVE")
	_add_button(layout, "Stadt laden", "LOAD")
	status_label = Label.new()
	status_label.text = "Werkzeug: Platzieren | Objekt: Haus"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status_label)
	var help := Label.new()
	help.text = "Rechte Maustaste ziehen: Ansicht drehen\nMausrad: Zoom\nAuswählen: Objekt anklicken\nVerschieben: Zielpunkt anklicken"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(help)

func _add_button(parent: VBoxContainer, text: String, action: String) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func(): _button_action(action))
	parent.add_child(button)

func _button_action(action: String) -> void:
	match action:
		"TOOL_PLACE":
			tool_mode = "place"
			status_label.text = "Werkzeug: Platzieren"
		"TOOL_SELECT":
			tool_mode = "select"
			status_label.text = "Werkzeug: Auswählen"
		"TOOL_MOVE":
			tool_mode = "move"
			status_label.text = "Werkzeug: Verschieben – Zielpunkt anklicken"
		"SCALE_UP":
			_scale_selected(1.1)
		"SCALE_DOWN":
			_scale_selected(0.9)
		"DELETE_SELECTED":
			_delete_selected()
		"DELETE_LAST":
			_delete_last()
		"SAVE":
			_save_city()
		"LOAD":
			_load_city()
		_:
			selected_kind = action
			tool_mode = "place"
			status_label.text = "Objekt: " + action + " – zum Platzieren klicken"

func _update_camera() -> void:
	var offset := Vector3(
		sin(camera_yaw) * cos(camera_pitch),
		-sin(camera_pitch),
		cos(camera_yaw) * cos(camera_pitch)
	) * camera_distance
	camera.position = camera_target + offset
	camera.look_at(camera_target, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = max(7.0, camera_distance - 2.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = min(80.0, camera_distance + 2.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if event.position.x < 280.0 and event.position.y < 900.0:
				return
			_handle_world_click(event.position)
	elif event is InputEventMouseMotion and dragging:
		var delta: Vector2 = event.position - last_mouse
		last_mouse = event.position
		camera_yaw -= delta.x * 0.008
		camera_pitch = clamp(camera_pitch - delta.y * 0.006, deg_to_rad(-78), deg_to_rad(-18))
		_update_camera()

func _handle_world_click(screen_pos: Vector2) -> void:
	if tool_mode == "select":
		_select_nearest_object(screen_pos)
	elif tool_mode == "move":
		if selected_object == null or not is_instance_valid(selected_object):
			status_label.text = "Bitte zuerst Auswählen und ein Objekt anklicken."
			return
		var point = _ground_point(screen_pos)
		if point != null:
			selected_object.position = Vector3(round(point.x), selected_object.position.y, round(point.z))
			status_label.text = "Objekt verschoben."
	else:
		_place_object(screen_pos)

func _ground_point(screen_pos: Vector2):
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if abs(direction.y) < 0.001:
		return null
	var distance := -origin.y / direction.y
	if distance < 0:
		return null
	return origin + direction * distance

func _select_nearest_object(screen_pos: Vector2) -> void:
	var nearest: Node3D = null
	var nearest_distance := 75.0
	for obj in placed_objects:
		if not is_instance_valid(obj):
			continue
		var screen_point := camera.unproject_position(obj.global_position)
		var d := screen_point.distance_to(screen_pos)
		if d < nearest_distance:
			nearest_distance = d
			nearest = obj
	selected_object = nearest
	if selected_object != null:
		status_label.text = "Ausgewählt: " + selected_object.name
	else:
		status_label.text = "Kein Objekt nahe dem Klick gefunden. Näher heranzoomen."

func _scale_selected(factor: float) -> void:
	if selected_object == null or not is_instance_valid(selected_object):
		status_label.text = "Bitte zuerst ein Objekt auswählen."
		return
	selected_object.scale = selected_object.scale * factor
	status_label.text = "Größe geändert: " + selected_object.name

func _place_object(screen_pos: Vector2) -> void:
	var point = _ground_point(screen_pos)
	if point == null:
		return
	var position := Vector3(round(point.x), 0, round(point.z))
	var obj := _make_object(selected_kind)
	obj.position = position
	world_root.add_child(obj)
	placed_objects.append(obj)
	selected_object = obj
	status_label.text = selected_kind + " platziert."

func _make_object(kind: String) -> Node3D:
	var asset_path := ""
	match kind:
		"House": asset_path = "res://assets/city_kit/Building_Small_1.gltf"
		"Medium": asset_path = "res://assets/city_kit/Building_Medium_2_001.gltf"
		"Large": asset_path = "res://assets/city_kit/Building_Large_2.gltf"
		"Road": asset_path = "res://assets/city_kit/Street_2Lane.gltf"
		"Road4": asset_path = "res://assets/city_kit/Street_4Lane.gltf"
		"Crossroad": asset_path = "res://assets/city_kit/Street_4WayIntersection.gltf"
		"TJunction": asset_path = "res://assets/city_kit/Street_TIntersection.gltf"
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var packed := load(asset_path) as PackedScene
		if packed != null:
			var instance := packed.instantiate() as Node3D
			if instance != null:
				instance.name = kind
				return instance
	var root := Node3D.new()
	root.name = kind
	match kind:
		"House":
			_box(root, Vector3(2.8, 3.2, 2.8), Vector3(0, 1.6, 0), Color(0.68, 0.56, 0.43))
		"Tree":
			_box(root, Vector3(0.45, 2, 0.45), Vector3(0, 1, 0), Color(0.35, 0.22, 0.12))
			var crown := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 1.05
			sphere.height = 2.1
			crown.mesh = sphere
			crown.position.y = 2.55
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.15, 0.42, 0.2)
			crown.material_override = mat
			root.add_child(crown)
		"Lamp":
			_box(root, Vector3(0.12, 3.2, 0.12), Vector3(0, 1.6, 0), Color(0.18, 0.19, 0.2))
		"Road":
			_box(root, Vector3(8, 0.08, 3), Vector3(0, 0.04, 0), Color(0.12, 0.13, 0.14))
	return root

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material_override = mat
	parent.add_child(mesh)

func _delete_selected() -> void:
	if selected_object == null or not is_instance_valid(selected_object):
		status_label.text = "Bitte zuerst ein Objekt auswählen."
		return
	placed_objects.erase(selected_object)
	selected_object.queue_free()
	selected_object = null
	status_label.text = "Ausgewähltes Objekt gelöscht."

func _delete_last() -> void:
	if placed_objects.is_empty():
		status_label.text = "Keine Objekte zum Löschen."
		return
	var obj: Node3D = placed_objects.pop_back()
	if obj == selected_object:
		selected_object = null
	obj.queue_free()
	status_label.text = "Letztes Objekt gelöscht."

func _save_city() -> void:
	var data: Array[Dictionary] = []
	for obj in placed_objects:
		if is_instance_valid(obj):
			data.append({"kind": str(obj.name), "position": [obj.position.x, obj.position.y, obj.position.z], "scale": [obj.scale.x, obj.scale.y, obj.scale.z]})
	var file := FileAccess.open("user://city_layout.json", FileAccess.WRITE)
	if file == null:
		status_label.text = "Speichern fehlgeschlagen."
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	status_label.text = "Stadt gespeichert."

func _load_city() -> void:
	var file := FileAccess.open("user://city_layout.json", FileAccess.READ)
	if file == null:
		status_label.text = "Noch keine gespeicherte Stadt gefunden."
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Array:
		status_label.text = "Speicherdatei ungültig."
		return
	for obj in placed_objects:
		if is_instance_valid(obj):
			obj.queue_free()
	placed_objects.clear()
	selected_object = null
	for entry in data:
		if not entry is Dictionary or not entry.has("kind") or not entry.has("position"):
			continue
		var pos: Array = entry["position"]
		if pos.size() < 3:
			continue
		var obj := _make_object(str(entry["kind"]))
		obj.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if entry.has("scale") and entry["scale"] is Array and entry["scale"].size() >= 3:
			var s: Array = entry["scale"]
			obj.scale = Vector3(float(s[0]), float(s[1]), float(s[2]))
		world_root.add_child(obj)
		placed_objects.append(obj)
	status_label.text = "Stadt geladen: " + str(placed_objects.size()) + " Objekte."
