#!/usr/bin/env python3
"""Check random-puzzle controls and geometry without original game assets.

Copies the real puzzle UI, menu kit and translations into the existing duel
laboratory. Only missing asset/audio services are replaced; generated-job
completion is controlled by the GDScript test so it can test cancellation.
Use --screenshots=/path with a running X11 display for rendered PNG evidence.
The ordinary headless run still measures actual Control geometry in EN/RU.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import puzzle_lab


def prepare(destination: Path, compatibility: bool) -> None:
    puzzle_lab.prepare(destination, compatibility=compatibility)
    for relative in (
        "render/puzzle_mode.gd",
        "render/menu_kit.gd",
        "content/remake_text.gd",
        "content/remake_translation.gd",
    ):
        content = (puzzle_lab.ROOT / "game/src" / relative).read_text()
        if compatibility:
            content = puzzle_lab.typed_array_compat(content)
        (destination / Path(relative).name).write_text(content)
    profile = destination / "profile.gd"
    profile.write_text(profile.read_text() + '''
var root := ""
func texture(_path: String) -> Texture2D:
    return null
''')
    (destination / "ui_sounds.gd").write_text('''class_name ELUiSounds
extends RefCounted
static func bind(_button: BaseButton, _profile: ELProfile, _control: String) -> void:
    pass
''')
    (destination / "icon_upscale.gd").write_text('''class_name ELIconUpscale
extends RefCounted
static func image_of(texture: Texture2D) -> Image:
    return texture.get_image()
''')
    # Run the exact small view helpers that make advice targets inspectable.
    # The full battle renderer needs installed assets and unrelated 4.7 APIs.
    view = (puzzle_lab.ROOT / "game/src/duel/view.gd").read_text()
    helpers = []
    for name in ("_creature_damage_facts", "_puzzle_piece_reference", "_puzzle_enchantment_reference"):
        start = view.index("\nfunc " + name + "(") + 1
        end = view.index("\nfunc ", start)
        helpers.append(view[start:end])
    (destination / "puzzle_view_facts.gd").write_text('''class_name ELPuzzleViewFacts
extends RefCounted
var puzzle_mode: ELPuzzleMode
var duel: ELDuel
var profile: ELProfile
func _t(value: String) -> String:
	return ELRemakeText.t(value, profile)
''' + "\n".join(helpers))
    shutil.copy2(puzzle_lab.ROOT / "tools/puzzle_generator_ui_check.gd", destination)
    with (destination / "project.godot").open("a") as project:
        project.write('\n[display]\nwindow/size/viewport_width=800\nwindow/size/viewport_height=600\n')
    missing = puzzle_lab.missing_classes(destination)
    if missing:
        raise SystemExit("UI laboratory is missing classes: " + repr(missing))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--screenshots", type=Path)
    args = parser.parse_args()
    if args.screenshots and not os.environ.get("DISPLAY"):
        parser.error("--screenshots requires a running X11 display (DISPLAY).")
    destination = args.workspace or Path(tempfile.mkdtemp(prefix="demiurges-puzzle-ui-"))
    version = subprocess.run([args.godot, "--version"], capture_output=True, text=True, check=True).stdout
    prepare(destination, compatibility=version.startswith("4.6"))
    environment = dict(os.environ, XDG_DATA_HOME=str(destination / "user_data"))
    imported = subprocess.run(
        [args.godot, "--headless", "--editor", "--path", str(destination), "--quit"],
        text=True, capture_output=True, env=environment, timeout=120,
    )
    if imported.returncode or "SCRIPT ERROR" in imported.stdout + imported.stderr:
        print(imported.stdout + imported.stderr)
        return 1
    command = [args.godot]
    if not args.screenshots:
        command.append("--headless")
    command += ["--path", str(destination), "--script", "puzzle_generator_ui_check.gd"]
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
        command += ["--", "--screenshots=" + str(args.screenshots.resolve())]
    result = subprocess.run(command, env=environment, text=True, capture_output=True, timeout=120)
    print(result.stdout + result.stderr)
    return 1 if result.returncode or "SCRIPT ERROR" in result.stdout + result.stderr else 0


if __name__ == "__main__":
    raise SystemExit(main())
