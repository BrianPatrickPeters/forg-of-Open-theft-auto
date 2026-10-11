extends SceneTree
func _initialize():
    var walk_scene = load('res://assets/characters/Brian/Strut Walking.fbx') as PackedScene
    var brian_scene = load('res://assets/characters/Brian/Rigged_BrianModell_T_Pose.fbx') as PackedScene
    if walk_scene == null or brian_scene == null:
        print('LOAD FAILED')
        quit()
        return
    var walk = walk_scene.instantiate()
    var brian = brian_scene.instantiate()
    var walk_ap = find_player(walk)
    var brian_ap = find_player(brian)
    print('WALK PLAYER: ', walk_ap != null, ' BRIAN PLAYER: ', brian_ap != null)
    if walk_ap != null and brian_ap != null:
        var anim = walk_ap.get_animation('mixamo_com')
        print('WALK LENGTH: ', anim.length, ' TRACKS: ', anim.get_track_count())
        print('BRIAN CLIP LENGTH: ', brian_ap.get_animation('mixamo_com').length)
    walk.free()
    brian.free()
    quit()
func find_player(n):
    if n is AnimationPlayer: return n
    for c in n.get_children():
        var found = find_player(c)
        if found != null: return found
    return null
