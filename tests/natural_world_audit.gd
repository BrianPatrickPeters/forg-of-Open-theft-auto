extends Node
var failures: Array[String] = []
func _ready() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
func run() -> void:
	seed(24680)
	var world := CityWorld.new()
	add_child(world)
	world.generate()
	for rect in world.road_segments:
		var horizontal := rect.size.x > rect.size.y
		var length := rect.size.x if horizontal else rect.size.y
		for i in range(2, int(length)-2, 2):
			var point := rect.position + (Vector2(i, rect.size.y/2) if horizontal else Vector2(rect.size.x/2, i))
			# Canal crossing is deliberately a raised bridge.
			var height := world.surface_height(point.x, point.y)
			check(not world.collides_at(point.x, point.y, 0.4, height), "Rendered road blocked: %s" % point)
	check(world.terrain_height(600, -400) > 1, "Countryside has no relief")
	check(world.on_water(900, -200), "West/east sea classified as land")
	check(not world.on_water(172, 507), "Runway classified as water")
	check(absf(world.surface_height(300, -650)) < 0.01, "Launch pad not level")
	check(world.camera_clearance(Vector3(112, 2, 64), Vector3(128, 2, 64)).x < 125, "Camera passes through villa")
	check(world.swept_collision(Vector3(112, 0, 64), Vector3(142, 0, 64), 0.4), "Fast motion tunnels through villa")
	# Verify actual rendered terrain top uses upward normals.
	var natural := world.get_node("NaturalCoastTerrain") as MeshInstance3D
	var arrays := natural.mesh.surface_get_arrays(0)
	for normal in arrays[Mesh.ARRAY_NORMAL]:
		if normal.y <= 0:
			failures.append("Terrain normal points below the surface")
			break
	if failures.is_empty():
		print("NATURAL_WORLD_AUDIT_OK roads=%d" % world.road_segments.size())
		get_tree().quit(0)
	else:
		for failure in failures.slice(0, 30):
			push_error(failure)
		get_tree().quit(1)
