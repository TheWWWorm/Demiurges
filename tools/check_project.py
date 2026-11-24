#!/usr/bin/env python3
"""Run the headless smoke suite or compare both editions' combat engines."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SMOKE = (
    "battle_hud_check.gd",
    "blazon_check.gd",
    "combat_presentation_check.gd",
    "effects_presentation_check.gd",
    "lighting_presentation_check.gd",
    "arena_presentation_check.gd",
)


def run(godot, *args, timeout=240):
    result = subprocess.run(
        [godot, "--headless", "--path", "game", *args],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        encoding="utf-8", errors="replace", timeout=timeout,
    )
    print(result.stdout, end="", flush=True)
    return result.returncode == 0 and not re.search(r"SCRIPT ERROR:|Failed to load script", result.stdout)


def run_scripts(godot, cases):
    passed = True
    for script, args in cases:
        print(f"\n{script} {' '.join(args)}", flush=True)
        if not run(godot, "--script", "../tools/" + script, "--", *args):
            passed = False
    return passed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suite", choices=("smoke", "combat"))
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--installed", action="store_true", help="Run the full combat parity cases using installed originals.")
    parser.add_argument("--el1", type=Path, help="Installed Etherlords folder, if it is not registered in Godot.")
    parser.add_argument("--el2", type=Path, help="Installed Etherlords II folder, if it is not registered in Godot.")
    opts = parser.parse_args()
    if (opts.installed or opts.el1 or opts.el2) and opts.suite != "combat":
        parser.error("installed game options are only used by the combat suite")
    try:
        if not run(opts.godot, "--editor", "--import", "--quit"):
            return 1
        if opts.suite == "smoke":
            return 0 if run_scripts(opts.godot, ((name, ()) for name in SMOKE)) else 1
        with tempfile.TemporaryDirectory(prefix="demiurges-check-") as folder:
            if opts.installed or opts.el1 or opts.el2:
                args = ["--parity"]
                args += [f"--{game}={path.resolve()}" for game, path in (("el1", opts.el1), ("el2", opts.el2)) if path]
            else:
                from puzzle_lab import card_tables

                fixture = Path(folder) / "cards.json"
                fixture.write_text(json.dumps(card_tables()), encoding="utf-8")
                args = [f"--checked-in-cards={fixture}", "--cases=64", "--seed=295", "--quiet"]
            cases = (("duel_rules_check.gd", [f"--game={game}", *args]) for game in ("el1", "el2"))
            return 0 if run_scripts(opts.godot, cases) else 1
    except (OSError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
