extends Node3D
var world: CityWorld
var output_dir := "user://visual-audit"
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output_dir = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	seed(24680)
	world = CityWorld.new()
	add_child(world)
	world.generate()
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("7593b5")
	sky_material.sky_horizon_color = Color("b6c5ce")
	sky.sky_material = sky_material
	env.sky = sky
	env.background_color = Color(0.52, 0.69, 0.81)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.8, 0.9)
	env.ambient_light_energy = 0.35
	env.ssr_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var camera := Camera3D.new()
	camera.far = 6000
	camera.current = true
	add_child(camera)
	var shots := [
		["city", Vector3(110, 65, 130), Vector3(0, 16, 0)],
		["coast", Vector3(950, 630, 1050), Vector3(0, 0, 40)],
		["street", Vector3(112, 2.5, 80), Vector3(129, 9, 64)],
		["facade", Vector3(46, 5, 15), Vector3(32, 12, 34)],
		["moon", Vector3(90, 4045, 110), Vector3(0, 4000, 0)]]
	for shot in shots:
		env.background_mode = Environment.BG_COLOR if shot[0] == "moon" else Environment.BG_SKY
		env.background_color = Color(0.003, 0.004, 0.008) if shot[0] == "moon" else Color(0.52, 0.69, 0.81)
		camera.position = shot[1]
		camera.look_at(shot[2])
		await get_tree().process_frame
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(output_dir.path_join(shot[0] + ".png"))
	print("VISUAL_AUDIT_OK")
	get_tree().quit()
