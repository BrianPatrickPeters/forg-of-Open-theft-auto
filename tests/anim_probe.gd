extends Node
## Read-only diagnostic probe: dumps Brian's real skeleton bone names and the
## animation clip names / track paths inside the Universal Animation Library
## GLBs, so the retarget map is built from measured data instead of guesses.
## Nothing is modified; it only prints and quits.

func _ready() -> void:
	print("=== ANIM PROBE START ===")
	_probe_rig("BRIAN", "res://assets/characters/Brian/Rigged_BrianModell_T_Pose.fbx")
	_probe_lib("UAL1", "res://assets/animations/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb")
	_probe_lib("UAL2", "res://assets/animations2/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb")
	print("=== ANIM PROBE END ===")
	get_tree().quit(0)


func _join(arr: Array) -> String:
	var s := ""
	for i in arr.size():
		if i > 0:
			s += ", "
		s += str(arr[i])
	return s


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _probe_rig(label: String, path: String) -> void:
	print("--- RIG ", label, " path=", path)
	var ps := load(path) as PackedScene
	if ps == null:
		print(label, "_LOAD_FAILED")
		return
	var inst := ps.instantiate()
	if inst == null:
		print(label, "_INSTANTIATE_FAILED")
		return
	add_child(inst)
	var sk := _find_skel(inst)
	if sk == null:
		print(label, "_NO_SKELETON")
		return
	print(label, "_BONE_COUNT=", sk.get_bone_count())
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		var pn: String = sk.get_bone_name(p) if p >= 0 else "-"
		print(label, "_BONE ", i, " name=", sk.get_bone_name(i), " parent=", pn)
	for key in ["pelvis", "thigh", "upperarm", "spine", "head", "leg", "arm"]:
		var found := ""
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).to_lower().contains(key):
				found = sk.get_bone_name(i)
				break
		if found == "":
			continue
		var idx := sk.find_bone(found)
		var t := sk.get_bone_rest(idx)
		print(label, "_REST ", key, " -> ", found,
			" origin=", t.origin,
			" bx=", t.basis.x, " by=", t.basis.y, " bz=", t.basis.z)
	var ap := _find_anim(inst)
	print(label, "_HAS_ANIM_PLAYER=", ap != null)


func _probe_lib(label: String, path: String) -> void:
	print("--- LIB ", label, " path=", path)
	var ps := load(path) as PackedScene
	if ps == null:
		print(label, "_LOAD_FAILED")
		return
	var inst := ps.instantiate()
	if inst == null:
		print(label, "_INSTANTIATE_FAILED")
		return
	add_child(inst)
	var sk := _find_skel(inst)
	if sk != null:
		var names: Array = []
		for i in sk.get_bone_count():
			names.append(sk.get_bone_name(i))
		print(label, "_BONE_COUNT=", sk.get_bone_count())
		print(label, "_BONES=", _join(names))
	else:
		print(label, "_NO_SKELETON")
	var ap := _find_anim(inst)
	if ap == null:
		print(label, "_NO_ANIM_PLAYER")
		return
	var clips: Array = []
	for c in ap.get_animation_list():
		clips.append(c)
	print(label, "_CLIP_COUNT=", clips.size())
	print(label, "_CLIPS=", _join(clips))
	for want in ["Walk_Loop", "Idle_Loop", "Jog_Fwd_Loop"]:
		if ap.has_animation(want):
			var a: Animation = ap.get_animation(want)
			print(label, "_TRACKCOUNT_", want, "=", a.get_track_count())
			for t in a.get_track_count():
				print(label, "_TRACK ", want, " ", t,
					" type=", a.track_get_type(t), " path=", a.track_get_path(t))
			break
