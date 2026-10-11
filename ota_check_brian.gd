extends SceneTree
func _initialize():
    var p = load('res://assets/characters/Brian/Rigged_BrianModell_T_Pose.fbx') as PackedScene
    if p == null:
        print('SCENE LOAD FAILED')
    else:
        var n = p.instantiate()
        inspect(n)
        n.free()
    quit()
func inspect(n):
    print(n.name, ' :: ', n.get_class())
    if n is AnimationPlayer: print('CLIPS=', n.get_animation_list())
    if n is Skeleton3D:
        print('BONES=', n.get_bone_count())
        for i in range(mini(n.get_bone_count(), 25)): print(n.get_bone_name(i))
    for c in n.get_children(): inspect(c)

