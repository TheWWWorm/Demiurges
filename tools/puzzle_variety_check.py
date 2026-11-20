#!/usr/bin/env python3
"""Audit tactical variety and essential operations in generated puzzle packs.

Feed the el1-generated.json / el2-generated.json packs from the generator
checker. The audit replays real references, groups their decision structures
without recipe labels, and reports overlap between families. For entries with
development_requirements, it also asks whether a forced win remains when the
specified player operation is unavailable. Opposing choices remain unrestricted.
This is a development check; it changes neither generation nor the game rules.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

import puzzle_lab


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", action="append", required=True, type=Path,
                        help="Generated puzzle pack; may be supplied more than once")
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--report", type=Path, default=puzzle_lab.ROOT / "build/random-variety/report.json")
    parser.add_argument("--budget", type=int, default=24000, help="Per operation-removal proof node limit")
    parser.add_argument("--require-new-families", default="",
                        help="Comma-separated families that must have a decision structure absent from the original 16")
    args = parser.parse_args()
    if not 1 <= args.budget <= 120000:
        parser.error("Use a proof budget from 1 to 120000")
    files = [path.resolve() for path in args.file]
    for path in files:
        if not path.is_file():
            parser.error(f"Missing input pack: {path}")
    report = args.report.resolve()
    if report in files:
        parser.error("The audit report must not overwrite an input pack")
    report.parent.mkdir(parents=True, exist_ok=True)
    destination = args.workspace or Path(tempfile.mkdtemp(prefix="demiurges-variety-lab-"))
    version = subprocess.run([args.godot, "--version"], check=True, text=True, capture_output=True).stdout.strip()
    puzzle_lab.prepare(destination, compatibility=version.startswith("4.6"))
    for name in ["puzzle_generator_check.gd", "puzzle_proof_check.gd", "puzzle_variety_check.gd"]:
        source = (puzzle_lab.ROOT / "tools" / name).read_text()
        (destination / name).write_text(puzzle_lab.typed_array_compat(source) if version.startswith("4.6") else source)
    for command in (
        [args.godot, "--headless", "--editor", "--path", str(destination), "--quit"],
        [args.godot, "--headless", "--path", str(destination), "--script", "puzzle_variety_check.gd", "--check-only"],
    ):
        parsed = subprocess.run(command, text=True, capture_output=True)
        if parsed.returncode or "SCRIPT ERROR" in parsed.stdout + parsed.stderr:
            print(parsed.stdout + parsed.stderr)
            return 1
    report.unlink(missing_ok=True)
    command = [args.godot, "--headless", "--path", str(destination), "--script", "puzzle_variety_check.gd", "--",
               "--files=" + json.dumps([str(path) for path in files]), f"--report={report}",
               f"--budget={args.budget}", f"--require-new-families={args.require_new_families}"]
    runtime_error = False
    with subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=1) as process:
        for line in process.stdout:
            print(line, end="", flush=True)
            runtime_error |= "SCRIPT ERROR" in line or line.startswith("ERROR:")
        status = process.wait()
    if not report.exists():
        return 1
    data = json.loads(report.read_text())
    data["runtime"] = version
    data["fixture"] = "Actual repository combat and Run; checked-in per-edition card tables"
    data["inputs"] = [str(path) for path in files]
    report.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    return 1 if runtime_error else status


if __name__ == "__main__":
    raise SystemExit(main())
