from pathlib import Path
import re

src = Path("scripts/human.gd")
backup = Path("scripts/human.gd.before_brian_walk_integration.bak")
text = src.read_text(encoding="utf-8")
assert backup.is_file() and src.read_bytes() == backup.read_bytes(), "Original differs from backup; aborting."
assert text.count('const BRIAN_SCENE: PackedScene = preload("res://assets/characters/Brian/Rigged_BrianModell_T_Pose.fbx")') == 1
assert text.count('if kind == "nathan":') == 1

old_const = 'const BRIAN_SCENE: PackedScene = preload("res://assets/characters/Brian/Rigged_BrianModell_T_Pose.fbx")'
new_const = old_const + '\nconst BRIAN_WALK_SCENE: PackedScene = preload("res://assets/characters/Brian/Strut Walking.fbx")'

pattern = re.compile(
    r'(?m)^([ \t]*)if kind == "nathan":\n'
    r'\1[ \t]+var ap := _find\(model, "AnimationPlayer"\) as AnimationPlayer\n'
    r'\1[ \t]+var clips: PackedStringArray = \(ap\.get_animation_list\(\) if ap != null else PackedStringArray\(\)\)\n'
    r'\1[ \t]+if ap != null and clips\.size\(\) > 0:\n'
    r'\1[ \t]+[ \t]+var clip_name: String = clips\[0\]\n'
    r'\1[ \t]+[ \t]+ap\.play\(clip_name\)\n'
    r'\1[ \t]+[ \t]+ap\.pause\(\)\n'
    r'\1[ \t]+[ \t]+ap\.seek\(0\.0, true\)\n'
    r'\1[ \t]+[ \t]+g\.set_meta\("anim_player", ap\)\n'
    r'\1[ \t]+[ \t]+g\.set_meta\("anim_length", ap\.get_animation\(clip_name\)\.length\)'
)
m = pattern.search(text)
assert m, "Expected Nathan animation block not found exactly; no changes made."
indent = m.group(1)
unit = "    "
replacement = (
    indent + 'if kind == "nathan" or kind == "brian":\n'
    + indent + unit + 'var ap := _find(model, "AnimationPlayer") as AnimationPlayer\n'
    + indent + unit + 'if ap != null and kind == "brian":\n'
    + indent + unit + unit + 'var walk_root := BRIAN_WALK_SCENE.instantiate()\n'
    + indent + unit + unit + 'var walk_ap := _find(walk_root, "AnimationPlayer") as AnimationPlayer\n'
    + indent + unit + unit + unit + 'if walk_ap != null and walk_ap.has_animation("mixamo_com"):\n'
    + indent + unit + unit + unit + 'var walk_anim: Animation = walk_ap.get_animation("mixamo_com").duplicate()\n'
    + indent + unit + unit + unit + 'var lib := ap.get_animation_library("")\n'
    + indent + unit + unit + unit + 'if lib != null and not lib.has_animation("nrian_walk"):\n'
    + indent + unit + unit + unit + unit + 'lib.add_animation("brian_walk", walk_anim)\n'
    + indent + unit + unit + 'walk_root.free()\n'
    + indent + unit + 'var clips: PackedStringArray = (ap.get_animation_list() if ap != null else PackedStringArray())\n'
    + indent + unit + 'if ap != null and clips.size() > 0:\n'
    + indent + unit + unit + 'var clip_name: String = ("brian_walk" if kind == "brian" and ap.has_animation("nrian_walk") else clips[0])\n'
    + indent + unit + unit + 'ap.play(clip_name)\n'
    + indent + unit + unit + 'ap.pause()\n'
    + indent + unit + unit + 'ap.seek(0.0, true)\n'
    + indent + unit + unit + 'g.set_meta("anim_player", ap)\n'
    + indent + unit + unit + 'g.set_meta("anim_length", ap.get_animation(clip_name).length)')
updated = text.replace(old_const, new_const, 1)
updated, count = pattern.subn(lambda _: replacement, updated, count=1)
assert count == 1 and updated.count("BRIAN_WALK_SCENE") == 2
assert updated.count('if kind == "nathan" or kind == "brian":') == 1
# Only write after all checks have passed.
src.write_text(updated, encoding="utf-8", newline="\n")
print("PATCH APPLIED")
print("Backup preserved:", backup)
print("New Brian walk scene constant added.")
print("Nathan animation block retained; Brian now uses brian_walk.")
