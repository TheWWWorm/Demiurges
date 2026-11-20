#!/usr/bin/env python3
"""Exercise in-game random challenges with actual combat rules, without art.

Examples:
  python3 tools/puzzle_generator_check.py --samples=2 --report-dir=build/random-check
  python3 tools/puzzle_generator_check.py --edition=el1 --difficulty=3 --family=crossfire

The isolated project uses the same checked-in card-data fixture and narrow
asset-service stubs as puzzle_lab.py. It does not replace combat, the generator,
the proof search, or the runtime puzzle observer. Reports contain the exact
generated entries and witnesses for independent replay with puzzle_lab.py.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import puzzle_lab


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--report-dir", type=Path, default=puzzle_lab.ROOT / "build/random-puzzle-validation")
    parser.add_argument("--samples", type=int, default=1, help="Seeds per edition, difficulty and family")
    parser.add_argument("--edition", choices=("el1", "el2", "both"), default="both")
    parser.add_argument("--difficulty", choices=("2", "3", "4", "5", "all"), default="all")
    parser.add_argument("--family", default="")
    parser.add_argument("--code", default="", help="Verify one exact challenge code; overrides edition, difficulty, family and sample selection")
    parser.add_argument("--offset", type=int, default=0, help="Different deterministic seed batch")
    parser.add_argument("--skip-invariants", action="store_true", help="For an additional diversity-only batch")
    parser.add_argument("--session-samples", type=int, default=0, help="Also generate this many fresh challenges per edition and selected tier")
    args = parser.parse_args()
    if args.samples < 1 or args.samples > 100 or args.offset < 0 or args.offset > 10000 or args.session_samples < 0 or args.session_samples > 100:
        parser.error("Use 1..100 samples, 0..100 session samples, and an offset from 0 to 10000")
    destination = args.workspace or Path(tempfile.mkdtemp(prefix="demiurges-random-lab-"))
    args.report_dir = args.report_dir.resolve()
    args.report_dir.mkdir(parents=True, exist_ok=True)
    for filename in ("report.json", "el1-generated.json", "el2-generated.json"):
        (args.report_dir / filename).unlink(missing_ok=True)
    version = subprocess.run([args.godot, "--version"], check=True, text=True, capture_output=True).stdout.strip()
    puzzle_lab.prepare(destination, compatibility=version.startswith("4.6"))
    source = (puzzle_lab.ROOT / "tools/puzzle_generator_check.gd").read_text()
    (destination / "puzzle_generator_check.gd").write_text(puzzle_lab.typed_array_compat(source) if version.startswith("4.6") else source)
    source = (puzzle_lab.ROOT / "tools/puzzle_proof_check.gd").read_text()
    (destination / "puzzle_proof_check.gd").write_text(puzzle_lab.typed_array_compat(source) if version.startswith("4.6") else source)
    for command in (
        [args.godot, "--headless", "--editor", "--path", str(destination), "--quit"],
        [args.godot, "--headless", "--path", str(destination), "--script", "puzzle_generator_check.gd", "--check-only"],
    ):
        parsed = subprocess.run(command, text=True, capture_output=True)
        if parsed.returncode or "SCRIPT ERROR" in parsed.stdout + parsed.stderr:
            print(parsed.stdout + parsed.stderr)
            return 1
    command = [args.godot, "--headless", "--path", str(destination), "--script", "puzzle_generator_check.gd", "--",
               f"--samples={args.samples}", f"--edition={args.edition}", f"--difficulty={args.difficulty}",
               f"--family={args.family}", f"--code={args.code}", f"--offset={args.offset}", f"--report-dir={args.report_dir}", f"--session-samples={args.session_samples}"]
    if args.skip_invariants:
        command.append("--skip-invariants")
    runtime_error = False
    with subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=1) as process:
        for line in process.stdout:
            print(line, end="", flush=True)
            runtime_error |= "SCRIPT ERROR" in line or line.startswith("ERROR:")
        status = process.wait()
    report_path = args.report_dir / "report.json"
    if report_path.exists():
        report = json.loads(report_path.read_text())
        report["runtime"] = version
        report["fixture"] = "Checked-in per-edition wiki card tables; actual ELDuel combat and puzzle Run"
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    return 1 if runtime_error else status


if __name__ == "__main__":
    sys.exit(main())
