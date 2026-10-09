#!/usr/bin/env python3
"""Register an installed game folder, or extract a player-supplied GOG installer.

The original installer is read as data, never executed. innoextract is an
optional external dependency for installer input; folder input needs only Python.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def default_config():
    if sys.platform == "win32":
        base = Path(os.environ["APPDATA"]) / "Godot"
    elif sys.platform == "darwin":
        base = Path.home() / "Library/Application Support/Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "godot"
    return base / "app_userdata/Etherlords Duel/profiles.json"


def game_root(source, edition):
    required = {"resources/figures.res", "resources/crfigures.res",
                "resources/textures.res", "resources/regs.res", "resources/text.res",
                "campaigns/good.cpg" if edition == "el1" else "campaigns/white.cpg"}
    # Both a normal installation and innoextract's app/ wrapper are accepted.
    for candidate in (source, source / "app"):
        if not candidate.is_dir():
            continue
        files = {p.relative_to(candidate).as_posix().lower()
                 for p in candidate.rglob("*") if p.is_file()}
        if required <= files:
            return candidate.resolve()
    raise ValueError(f"No complete {edition} installation found in {source}; select the folder containing Resources and Campaigns")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("edition", choices=("el1", "el2"))
    parser.add_argument("source", type=Path, help="Installed game folder or GOG setup EXE")
    parser.add_argument("--dest", type=Path, help="New or empty private extraction folder; required for installer input")
    parser.add_argument("--extractor", help="Path to innoextract, otherwise found on PATH")
    parser.add_argument("--config", type=Path, default=default_config(), help="Profile JSON to update; defaults to Godot user data")
    args = parser.parse_args()
    source = args.source.expanduser().resolve()
    try:
        if source.is_file():
            if args.dest is None:
                raise ValueError("Installer input requires --dest; keep it outside the public engine folder")
            extractor = args.extractor or shutil.which("innoextract")
            if not extractor:
                raise ValueError("innoextract is required for setup EXEs; install it or pass --extractor, or select an installed game folder")
            destination = args.dest.expanduser().resolve()
            if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
                raise ValueError("Extraction destination must be new or empty; existing game data will not be overwritten")
            destination.mkdir(parents=True, exist_ok=True)
            subprocess.run([extractor, "--extract", "--output-dir", str(destination), str(source)], check=True)
            source = destination
        root = game_root(source, args.edition)
        config = args.config.expanduser().resolve()
        data = json.loads(config.read_text()) if config.exists() else {}
        if not isinstance(data, dict):
            raise ValueError("Profile configuration must be a JSON object")
        data[args.edition] = str(root)
        config.parent.mkdir(parents=True, exist_ok=True)
        temporary = config.with_name(config.name + ".tmp")
        temporary.write_text(json.dumps(data, indent=2) + "\n")
        temporary.replace(config)
        print(f"Registered {args.edition}: {root}\nConfiguration: {config}\nRestart the engine to load this profile.")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Import failed: {error}\n")


if __name__ == "__main__":
    main()
