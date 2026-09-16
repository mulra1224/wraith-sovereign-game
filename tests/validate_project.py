from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
required = [
    "project.godot", "Main.tscn", "scripts/main.gd", "export_presets.cfg",
    ".github/workflows/android-apk.yml",
]
for relative in required:
    path = ROOT / relative
    assert path.is_file() and path.stat().st_size > 0, f"missing: {relative}"

project = (ROOT / "project.godot").read_text(encoding="utf-8")
scene = (ROOT / "Main.tscn").read_text(encoding="utf-8")
script = (ROOT / "scripts/main.gd").read_text(encoding="utf-8")
preset = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")

assert 'run/main_scene="res://Main.tscn"' in project
assert 'res://scripts/main.gd' in scene
for feature in ["바포메트", "데스나이트", "강화", "_update_bots", "_save_game"]:
    assert feature in script, f"feature missing: {feature}"
assert 'name="Android"' in preset
assert 'include_filter=""' in preset and 'exclude_filter=""' in preset
print("Project structure and first-playable feature gates: PASS")

