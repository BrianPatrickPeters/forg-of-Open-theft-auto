extends SceneTree
func _initialize():
    var packed = load("res://assets/characters/Brian/Basic Shooter Pack/FERTIGES BRIANmodell.fbx")
    if packed == null:
        print("FEHLER: FBX konnte nicht geladen werden")
        quit()
        return
    var root = packed.instantiate()
    get_root().add_child(root)
    await process_frame
    print("--- MODELLSTRUKTUR ---")
    inspect(root, 0)
    root.queue_free()
    await process_frame
    quit()
func inspect(node: Node, depth: int):
    var info = ""
    if node is Node3D:
        info = " Position=" + str(node.position) + " Skalierung=" + str(node.scale)
    print("  ".repeat(depth), node.name, " [", node.get_class(), "]", info)
    for child in node.get_children():
        inspect(child, depth + 1)

