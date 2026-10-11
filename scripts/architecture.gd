class_name Architecture
extends Node3D
## Modular facades, batched by material and neighbourhood for inexpensive culling.
var batches: Dictionary = {}
var window_material: ShaderMaterial
var component_count := 0

func _init() -> void:
	window_material = ShaderMaterial.new()
	window_material.shader = preload("res://assets/shaders/architectural_glass.gdshader")

func box(size: Vector3, pos: Vector3, material: Material, yaw := 0.0) -> void:
	var cell := Vector2i(floori(pos.x/64), floori(pos.z/64))
	var key := str(material.get_instance_id()) + ":" + str(cell)
	if not batches.has(key): batches[key] = {"material": material, "transforms": []}
	batches[key].transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled_local(size), pos))
	component_count += 1

func finish() -> void:
	for key in batches:
		var batch: Dictionary = batches[key]
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = batch.material
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = batch.transforms.size()
		mm.mesh = mesh
		for i in mm.instance_count: mm.set_instance_transform(i, batch.transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = mm
		add_child(instance)
	batches.clear()

func building(x: float, z: float, w: float, d: float, h: float, style: int, color: Color, base_y := 0.0) -> void:
	var masonry := Build.pbr("Bricks051" if style == 1 else "Concrete034", color, 0.8 if style == 1 else 0.65)
	var frame := Build.cmat(Color("292f32"), 0.38, 0.65)
	var coping := Build.pbr("Concrete034", Color("a0a09a"), 0.65)
	var roof := Build.pbr("Concrete034", Color("454947"), 0.4)
	var floors := maxi(2, roundi((h-4.0)/3.3))
	var floor_h := (h-4.0)/floors
	# Recessed core ensures the glazing has a visible reveal, never floating stickers.
	box(Vector3(w-0.42, h, d-0.42), Vector3(x, base_y+h/2.0, z), masonry)
	for side in 4:
		var yaw := side * PI/2.0
		var outward := Vector3(sin(yaw), 0, cos(yaw))
		var tangent := Vector3(cos(yaw), 0, -sin(yaw))
		var width := w if side % 2 == 0 else d
		var depth := d if side % 2 == 0 else w
		var face := Vector3(x, base_y, z) + outward*depth/2.0
		var bays := maxi(2, floori(width/2.7))
		var bay := width/bays
		# Shopfront/lobby with full-height glazing and a substantial lintel.
		box(Vector3(width, 0.5, 0.38), face+Vector3.UP*3.8, coping, yaw)
		for b in bays:
			var at := face + tangent*(-width/2+(b+0.5)*bay)
			box(Vector3(bay-0.12, 3.25, 0.12), at+Vector3.UP*1.8-outward*0.08, window_material, yaw)
			box(Vector3(0.12, 3.8, 0.24), at-tangent*bay/2+Vector3.UP*1.9, frame, yaw)
		for f in floors:
			var fy := 4.0+f*floor_h
			var glass_h := floor_h-0.45 if style == 0 else floor_h-1.15
			var sill := floor_h-glass_h
			box(Vector3(width, sill, 0.42), face+Vector3.UP*(fy+sill/2), frame if style == 0 else masonry, yaw)
			for b in bays:
				var at := face+tangent*(-width/2+(b+0.5)*bay)+Vector3.UP*(fy+sill+glass_h/2)
				var pier := 0.085 if style == 0 else 0.55
				box(Vector3(bay-pier, glass_h, 0.09), at-outward*0.09, window_material, yaw)
				box(Vector3(pier, glass_h, 0.42), at-tangent*bay/2, frame if style == 0 else masonry, yaw)
				if style != 0:
					box(Vector3(bay-pier+0.14, 0.13, 0.56), at-Vector3.UP*glass_h/2, coping, yaw)
					box(Vector3(0.045, glass_h, 0.15), at, frame, yaw)
			# Shallow sun-control fins and selected balconies cast architectural shadows.
			if style == 0 and side % 2 == 0:
				box(Vector3(width, 0.065, 0.48), face+Vector3.UP*(fy+floor_h-0.1)+outward*0.1, frame, yaw)
			if style == 2 and side == 0 and f > 0 and f % 2 == 1:
				var balcony := face+Vector3.UP*(fy+0.1)+outward*0.35
				box(Vector3(width*0.55, 0.16, 0.8), balcony, coping, yaw)
				box(Vector3(width*0.55, 0.045, 0.045), balcony+Vector3.UP*1.05+outward*0.35, frame, yaw)
				for post in 9:
					box(Vector3(0.035, 1.0, 0.035), balcony+tangent*(float(post)/8.0-0.5)*width*0.55+Vector3.UP*0.55+outward*0.35, frame, yaw)
			# Continuous fine transom between storeys.
			box(Vector3(width, 0.06, 0.18), face+Vector3.UP*(fy+floor_h), frame, yaw)
		box(Vector3(width+0.15, 0.7, 0.28), face+Vector3.UP*(h+0.35), coping, yaw)
	# Flat roof sits inside a real parapet, with lift overrun, ducts and AC grilles.
	box(Vector3(w, 0.2, d), Vector3(x, base_y+h, z), roof)
	box(Vector3(w*0.32, 2.2, d*0.3), Vector3(x-w*0.2, base_y+h+1.1, z+d*0.2), masonry)
	for unit in 2:
		var at := Vector3(x+w*0.2, base_y+h+0.65, z-d*0.22+unit*2.4)
		box(Vector3(2.0, 1.1, 1.7), at, Build.cmat(Color("757a78"), 0.6, 0.45))
		for slat in 7:
			box(Vector3(1.75, 0.04, 0.07), at+Vector3(0, -0.38+slat*0.12, 0.88), frame)
		box(Vector3(1.25, 0.07, 1.1), at+Vector3.UP*0.59, frame)
	# Entrance canopy and slender supports are aligned to the front facade.
	var entrance := Vector3(x, base_y+3.25, z-d/2.0-0.4)
	box(Vector3(minf(w*0.5, 5.5), 0.16, 1.25), entrance, frame)
	# Proper double doors, a transom, slim pull handles, and a stone threshold.
	var front_z := z-d/2.0-0.14
	for side in [-1.0, 1.0]:
		box(Vector3(0.075, 2.7, 0.1), Vector3(x+side*1.1, base_y+1.35, front_z), frame)
		box(Vector3(0.035, 0.8, 0.13), Vector3(x+side*0.18, base_y+1.3, front_z-0.07), Build.cmat(Color("969c9c"), 0.25, 0.8))
	box(Vector3(0.06, 2.7, 0.1), Vector3(x, base_y+1.35, front_z), frame)
	box(Vector3(2.3, 0.075, 0.1), Vector3(x, base_y+2.7, front_z), frame)
	box(Vector3(2.6, 0.1, 0.55), Vector3(x, base_y+0.05, front_z-0.05), coping)
	# A service door and vertical rainwater pipes add scale to rear elevations.
	box(Vector3(1.05, 2.2, 0.08), Vector3(x+w*0.25, base_y+1.1, z+d/2.0+0.06), frame)
	box(Vector3(0.09, h, 0.1), Vector3(x+w/2.0-0.32, base_y+h/2.0, z+d/2.0+0.08), frame)
