extends SceneTree
func _initialize():
    var ws = load('res://assets/characters/Brian/Strut Walking.fbx') as PackedScene
    var bs = load('res://assets/characters/Brian/Rigged_BrianModell_T_Pose.fbx') as PackedScene
    if ws == null or bs == null: print('SCENE LOAD FAILED'); quit(); return
    var walk = ws.instantiate()
    var brian = bs.instantiate()
    var wa = find_player(walk)
    var ba = find_player(brian)
    var sk = find_skeleton(brian)
    if wa == null or ba == null or sk == null: print('MISSING PLAYER OR SKELETON'); quit(); return
    var source = wa.get_animation('mixamo_com')
    var lib = ba.get_animation_library('')
    if lib == null: lib = AnimationLibrary.new(); ba.add_animation_library('', lib)
    var err = lib.add_animation('test_walk', source.duplicate(true))
    print('COPY RESULT: ', err)
    print('ROOT PATH: ', ba.root_node, ' FIRST TRACK: ', source.track_get_path(0))
    if err == OK:
        ba.play('test_walk')
        ba.seek(0.0, true)
        var r0 = sk.get_bone_pose_rotation(1)
        ba.seek(0.35, true)
        var r1 = sk.get_bone_pose_rotation(1)
        print('BONE 1 ROTATION AT START: ', r0)
        print('BONE 1 ROTATION AT 0.35s: ', r1)
        print('POSE CHANGED: ', not r0.is_equal_approx(r1))
    walk.free()
    brian.free()
    quit()
func find_player(n):
    if n is AnimationPlayer: return n
    for c in n.get_children():
        var x = find_player(c)
        if x != null: return x
    return null
func find_skeleton(n):
    if n is Skeleton3D: return n
    for c in n.get_children():
        var x = find_skeleton(c)
        if x != null: return x
    return null
