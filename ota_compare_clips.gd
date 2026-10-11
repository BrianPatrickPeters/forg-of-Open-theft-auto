extends SceneTree
func _initialize():
    for path in ['res://assets/characters/Brian/Strut Walking.fbx','res://assets/characters/Brian/Rigged_BrianModell_T_Pose.fbx']:
        var scene = load(path) as PackedScene
        print('FILE: ', path)
        if scene == null:
            print('LOAD FAILED')
            continue
        var root = scene.instantiate()
        inspect(root)
        root.free()
    quit()
func inspect(n):
    if n is AnimationPlayer:
        for a in n.get_animation_list():
            var anim = n.get_animation(a)
            print('CLIP: ', a, ' LENGTH: ', anim.length, ' TRACKS: ', anim.get_track_count())
    for c in n.get_children(): inspect(c)
