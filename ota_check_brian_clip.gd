extends SceneTree
func _initialize():
    var scene = load('res://assets/characters/Brian/Rigged_BrianModell_T_Pose.fbx') as PackedScene
    var root = scene.instantiate()
    inspect(root)
    root.free()
    quit()
func inspect(n):
    if n is AnimationPlayer:
        var anim = n.get_animation('mixamo_com')
        print('Brian clip length=', anim.length, ' tracks=', anim.get_track_count())
        for i in range(anim.get_track_count()): print(anim.track_get_type(i), ' | ', anim.track_get_path(i))
    for c in n.get_children(): inspect(c)
