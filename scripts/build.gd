class_name Build
## Static helpers for procedural mesh construction.

static func hex(h: int) -> Color:
	return Color(((h >> 16) & 0xFF) / 255.0, ((h >> 8) & 0xFF) / 255.0, (h & 0xFF) / 255.0)

static var _mat_cache: Dictionary = {}
static var _surface_cache: Dictionary = {}

static func mat(color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

## Shared cached material — one instance per unique (color, rough, metal).
## Callers must treat the result as immutable; use mat() for a private copy.
static func cmat(color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var key := color.to_rgba32() * 1000003 + int(rough * 100.0) * 101 + int(metal * 100.0)
	if not _mat_cache.has(key):
		_mat_cache[key] = mat(color, rough, metal)
	return _mat_cache[key]

static func emissive(color: Color, emit: Color, energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = emit
	m.emission_energy_multiplier = energy
	return m


## Lightweight procedural surface materials. They provide visible scale and
## breakup without shipping another large texture pack, and tile consistently
## across procedural meshes instead of stretching one bitmap per building.
static func pbr(asset: String, tint := Color.WHITE, scale_m := 0.8) -> StandardMaterial3D:
	var key := "pbr:"+asset+":"+str(tint.to_rgba32())+":"+str(scale_m)
	if _surface_cache.has(key): return _surface_cache[key]
	var material := mat(tint, 0.9)
	var path := "res://assets/textures/architecture/"+asset+"_1K-JPG_"
	material.albedo_texture = load(path+"Color.jpg")
	material.normal_enabled = true
	material.normal_texture = load(path+"NormalGL.jpg")
	material.normal_scale = 0.3 if asset == "Concrete034" else 0.65
	material.roughness_texture = load(path+"Roughness.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE*scale_m
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_surface_cache[key] = material
	return material

static func facade(color: Color, style := "stucco") -> Material:
	if style == "brick":
		return pbr("Bricks051", Color.WHITE.lerp(color, 0.2), 0.8)
	return pbr("Concrete034", color, 0.65)

static func roof_tiles(color: Color) -> Material:
	return pbr("RoofingTiles010", Color.WHITE.lerp(color, 0.25), 0.55)


static func water() -> ShaderMaterial:
	if _surface_cache.has("water"):
		return _surface_cache.water
	var shader := Shader.new()
	# Long, gentle swells in world space. The previous high-frequency local-vertex
	# waves on a 24×24 grid made each face a random height, so land under the
	# bay punched through as diamond tiles from altitude.
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
varying float wave;
varying vec3 water_world;
uniform bool carve_canal = false;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	water_world = wp;
	wave = sin(wp.x * 0.08 + TIME * 1.2) * 0.035
		+ cos(wp.z * 0.06 - TIME * 0.9) * 0.025;
	VERTEX.y += wave;
}
void fragment() {
	if (carve_canal && abs(water_world.x + 64.0) < 26.0 && abs(water_world.z) < 220.0) { discard; }
	float fade = 1.0 / (1.0 + length(fwidth(water_world.xz)) * 2.5);
	float sx = (cos(water_world.x * 0.72 + water_world.z * 0.53 + TIME * 1.7)
		+ sin(water_world.x * 1.13 - water_world.z * 0.81 + TIME)) * 0.025 * fade;
	float sz = (sin(water_world.z * 0.91 + water_world.x * 0.43 - TIME * 1.3)
		+ cos(water_world.x * 0.87 - water_world.z * 1.31 + TIME)) * 0.025 * fade;
	NORMAL = normalize((VIEW_MATRIX * vec4(-sx, 1.0, -sz, 0.0)).xyz);
	float variation = 0.3;
	ALBEDO = mix(vec3(0.018, 0.12, 0.17), vec3(0.035, 0.25, 0.29), variation);
	ROUGHNESS = 0.22;
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	_surface_cache.water = material
	return material


static func water_plane(w: float, d: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	# Keep faces ~10 units so swells read as continuous water, not diamond tiles.
	# Cap at 96 so the 16 km horizon sea stays cheap.
	pm.subdivide_width = clampi(int(w / 10.0), 16, 96)
	pm.subdivide_depth = clampi(int(d / 10.0), 16, 96)
	mi.mesh = pm
	mi.material_override = water()
	return mi

static func box(w: float, h: float, d: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	if material:
		mi.material_override = material
	return mi

static func cyl(top: float, bot: float, h: float, sides: int, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bot
	cm.height = h
	cm.radial_segments = sides
	mi.mesh = cm
	if material:
		mi.material_override = material
	return mi

static func sphere(r: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	if material:
		mi.material_override = material
	return mi

static func plane(w: float, d: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	mi.mesh = pm
	if material:
		mi.material_override = material
	return mi
