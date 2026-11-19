#!/usr/bin/env python3
"""Check authored expansions, preservation and exact runtime evidence.

  python tools/curiosities_check.py
  python tools/curiosities_check.py --runtime --baselines --godot /path/to/godot

Replays, losing examples and native AI failure are not forced-win proofs,
uniqueness certificates or human difficulty ratings. A failure_line is a
complete legal losing example from the initial state, beginning with commands.
"""
from __future__ import annotations

import argparse
from collections import Counter
import importlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from puzzle_authoring import ROOT, card
from puzzle_lab import prepare

BASE_REVISION = "1933bc4a303c3369657accb5c29475810089653a"
CRUCIBLE_BASE_REVISION = "5d39ca49b07b0fd65adc7eaca4ce89d70c704c6c"


def definition(entry):
    return {key: entry.get(key, {"type": "win"} if key == "objective" else [])
            for key in ("state", "turns", "objective", "solution", "refutations")}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def whole(value, low, high):
    # Godot's JSON encoder writes normalized integer values as e.g. 4.0.
    return isinstance(value, (int, float)) and not isinstance(value, bool) and low <= value <= high and value == int(value)


def completed_native(proof, status, turns):
    """Accept only a completed native-model verdict, never a budget timeout."""
    if proof.get("status") != status or any(proof.get(flag) is not False for flag in ("aborted", "unknown", "incomplete")):
        return False
    if status == "proven":
        return whole(proof.get("turns"), 1, turns)
    return whole(proof.get("settled"), turns, 12)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack-dir", type=Path, default=ROOT / "game/puzzles")
    parser.add_argument("--base-ref", help="Preservation baseline; defaults to the release before the selected expansion")
    parser.add_argument("--base-dir", type=Path, help="Original catalog directory, instead of git show")
    parser.add_argument("--edition", choices=("el1", "el2", "both"), default="both")
    parser.add_argument("--collection", choices=("all", "crucible", "curiosities-v1", "paradoxes", "crossroads"), default="all",
                        help="Check all expansions or only one named collection")
    parser.add_argument("--report-dir", type=Path, default=ROOT / "build/curiosities-validation")
    parser.add_argument("--runtime", action="store_true")
    parser.add_argument("--baselines", action="store_true", help="No-action and attack-everyone policies versus real AI")
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--proof-dir", type=Path, help="Directory with exact-definition puzzle_lab --search reports named el1.json and el2.json")
    parser.add_argument("--native-proof-dir", type=Path, help="Optional exact-definition crucible_audit reports; native-model evidence is counted separately from GDScript")
    parser.add_argument("--require-proofs", action="store_true", help="Require a completed matching GDScript or native-model proof for every root and wrong-plan prefix")
    args = parser.parse_args()
    if args.require_proofs and (not args.runtime or not (args.proof_dir or args.native_proof_dir)):
        parser.error("--require-proofs needs --runtime and at least one proof directory")
    args.base_ref = args.base_ref or (CRUCIBLE_BASE_REVISION if args.collection == "crucible" else BASE_REVISION)
    editions = ("el1", "el2") if args.edition == "both" else (args.edition,)
    errors, warnings, summaries = [], [], {}
    args.report_dir.mkdir(parents=True, exist_ok=True)

    def check(ok, message):
        if not ok:
            errors.append(message)
            print("FAIL " + message)

    for edition in editions:
        document = json.loads((args.pack_dir / (edition + ".json")).read_text(encoding="utf-8"))
        entries = document["puzzles"]
        by_id = {entry["id"]: entry for entry in entries}
        check(len(entries) == len(by_id), edition + ": duplicate IDs")
        check(document.get("format") == "etherlords-puzzles" and document.get("game") == edition,
              edition + ": invalid catalog identity")
        groups = {"curiosities-v1": "curiosities", "curiosities-v2": "paradoxes", "curiosities-v3": "crossroads", "crucible-v1": "crucible"}
        selected = "curiosities" if args.collection == "curiosities-v1" else args.collection
        chosen_groups = {key: suffix for key, suffix in groups.items() if args.collection == "all" or suffix == selected}
        authored, expected_expansion = [], {}
        for expansion, suffix in chosen_groups.items():
            group = importlib.import_module("puzzle_designs_" + edition + "_" + suffix).puzzles()
            authored.extend(group)
            expected_expansion.update({entry["id"]: expansion for entry in group})
        new_ids = {entry["id"] for entry in authored}
        check(len(new_ids) == len(authored) and bool(new_ids), edition + ": repeated/empty expansion IDs")
        check(new_ids <= by_id.keys(), edition + ": expansion missing from catalog: " + ", ".join(sorted(new_ids - by_id.keys())))
        try:
            if args.base_dir:
                baseline = json.loads((args.base_dir / (edition + ".json")).read_text(encoding="utf-8"))
            else:
                raw = subprocess.run(["git", "show", args.base_ref + ":game/puzzles/" + edition + ".json"],
                                     cwd=ROOT, text=True, capture_output=True, check=True).stdout
                baseline = json.loads(raw)
            old = {entry["id"]: entry for entry in baseline["puzzles"]}
            check(not (old.keys() & new_ids), edition + ": expansion reuses an existing ID")
            for identity, original in old.items():
                check(identity in by_id, identity + ": original puzzle was removed")
                if identity in by_id:
                    check(by_id[identity] == original, identity + ": original definition or presentation changed")
            preserved = len(old)
        except (OSError, subprocess.CalledProcessError, ValueError, KeyError) as exc:
            errors.append(edition + ": preservation unavailable; provide --base-dir with original catalogs: " + str(exc))
            preserved = 0

        new = [entry for entry in entries if entry["id"] in new_ids]
        states = {canonical({key: entry.get(key) for key in ("state", "turns", "objective")}): entry["id"]
                  for entry in entries if entry["id"] not in new_ids}
        mechanics = {}
        for entry in new:
            identity = entry["id"]
            check(entry.get("expansion") == expected_expansion[identity], identity + ": missing expansion identity")
            prefixes = {
                "curiosities-v1": ("Curiosities · ", "Курьёзы · "),
                "curiosities-v2": ("Curiosities · Paradoxes · ", "Курьёзы · Парадоксы · "),
                "curiosities-v3": ("Curiosities · Crossroads · ", "Курьёзы · Развилки · "),
                "crucible-v1": ("Crucible · ", "Горнило · "),
            }[expected_expansion[identity]]
            check(entry.get("category", "").startswith(prefixes[0]) and entry.get("category_ru", "").startswith(prefixes[1]),
                  identity + ": expansion is not searchable by its English and Russian collection names")
            for key in ("title", "category", "briefing", "explanation"):
                for suffix in ("", "_ru"):
                    value = entry.get(key + suffix)
                    check(isinstance(value, str) and bool(value.strip()), identity + ": missing " + key + suffix)
            for suffix in ("", "_ru"):
                hints = entry.get("hints" + suffix, [])
                check(isinstance(hints, list) and len(hints) == 3 and all(isinstance(item, str) and item.strip() for item in hints),
                      identity + ": expected three nonempty hints" + suffix)
                check(len({canonical(item) for item in hints}) == len(hints), identity + ": repeated hint" + suffix)
                names = entry.get("hero_names" + suffix, [])
                check(isinstance(names, list) and len(names) == 2 and all(isinstance(item, str) and item.strip() for item in names),
                      identity + ": missing combatant names" + suffix)
            check(whole(entry.get("level"), 1, 4), identity + ": invalid difficulty")
            check(whole(entry.get("turns"), 1, 12), identity + ": invalid turn allowance")
            if expected_expansion[identity] == "crucible-v1":
                check(entry.get("level") == 4, identity + ": Crucible must remain Expert difficulty")
                check(whole(entry.get("turns"), 1, 3), identity + ": Crucible exceeds its three-turn limit")
                check(entry.get("objective") == {"type": "win"}, identity + ": Crucible requires an ordinary victory objective")
            state = entry["state"]
            check(state.get("profile") == edition, identity + ": wrong edition")
            check(state.get("setup", {}).get("puzzle_fixed_hands") is True and state.get("setup", {}).get("puzzle_fixed_channels") is True,
                  identity + ": missing fixed-supply rules")
            for hero in state["heroes"]:
                check(whole(hero.get("level"), 1, 20), identity + ": invalid hero level")
            check(bool(entry.get("solution")), identity + ": missing reference solution")
            alternatives = entry.get("alternative_solutions", [])
            check(isinstance(alternatives, list), identity + ": alternative solutions must be a list")
            for alternative in alternatives if isinstance(alternatives, list) else []:
                check(isinstance(alternative, dict) and bool(alternative.get("label")) and bool(alternative.get("commands")),
                      identity + ": alternative solution needs a label and commands")
                if not isinstance(alternative, dict):
                    continue
                check(alternative.get("commands") != entry.get("solution"), identity + ": alternative repeats the reference line")
            refs = entry.get("refutations", [])
            check(bool(refs), identity + ": missing tempting alternative")
            if expected_expansion[identity] == "crucible-v1":
                check(len(refs) >= 2, identity + ": Crucible needs at least two tested wrong-plan prefixes")
            for branch in refs:
                prefix = branch.get("commands", [])
                check(bool(branch.get("label")) and bool(prefix), identity + ": empty refutation")
                check(prefix != entry.get("solution"), identity + ": failure duplicates solution")
                if "failure_line" in branch:
                    line = branch["failure_line"]
                    check(isinstance(line, list) and line[:len(prefix)] == prefix, identity + ": losing example does not begin with its named prefix")
            fingerprint = canonical({key: entry.get(key) for key in ("state", "turns", "objective")})
            check(fingerprint not in states, identity + ": exact duplicate tactical definition of " + states.get(fingerprint, ""))
            states[fingerprint] = identity
            signature = canonical({"objective": entry.get("objective"), "phase": state.get("phase"),
                                   "attacker": state.get("attacker"), "hands": [h["hand"] for h in state["heroes"]],
                                   "units": sorted((c["card"], c["owner"]) for c in state["creatures"].values())})
            if signature in mechanics:
                warnings.append(identity + ": same card/objective skeleton as " + mechanics[signature] + "; review distinction")
            mechanics[signature] = identity

        runtime = None
        if args.runtime and new:
            workspace = args.report_dir / (edition + "-lab")
            version = subprocess.run([args.godot, "--version"], capture_output=True, text=True, check=True).stdout.strip()
            prepare(workspace, compatibility=version.startswith("4.6"))
            shutil.copy2(ROOT / "tools/curiosities_check.gd", workspace / "curiosities_check.gd")
            selected_path = args.report_dir / (edition + "-curiosities.json")
            selected_path.write_text(json.dumps({**document, "puzzles": new}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            runtime_path = args.report_dir / (edition + "-runtime.json")
            runtime_path.unlink(missing_ok=True)
            for command in ([args.godot, "--headless", "--editor", "--path", str(workspace.resolve()), "--quit"],
                            [args.godot, "--headless", "--path", str(workspace.resolve()), "--script", "curiosities_check.gd", "--check-only"]):
                scan = subprocess.run(command, capture_output=True, text=True)
                check(scan.returncode == 0 and "SCRIPT ERROR" not in scan.stdout + scan.stderr,
                      edition + ": Godot parse failed: " + scan.stdout + scan.stderr)
                if scan.returncode or "SCRIPT ERROR" in scan.stdout + scan.stderr:
                    break
            else:
                command = [args.godot, "--headless", "--path", str(workspace.resolve()), "--script", "curiosities_check.gd", "--",
                           "--file=" + str(selected_path.resolve()), "--report=" + str(runtime_path.resolve())]
                if args.baselines:
                    command.append("--baselines")
                run = subprocess.run(command, capture_output=True, text=True)
                print(run.stdout)
                check(run.returncode == 0 and "SCRIPT ERROR" not in run.stdout + run.stderr,
                      edition + ": runtime checks failed: " + run.stderr)
                if runtime_path.exists():
                    runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
        if args.runtime and new:
            check(runtime is not None, edition + ": requested runtime check did not produce a fresh report")

        proof_rows = {}
        if args.proof_dir and (args.proof_dir / (edition + ".json")).is_file():
            proof_rows = {item["id"]: item for item in json.loads((args.proof_dir / (edition + ".json")).read_text())["results"]}
        native_rows = {}
        if args.native_proof_dir and (args.native_proof_dir / (edition + ".json")).is_file():
            native_rows = {item["id"]: item for item in json.loads((args.native_proof_dir / (edition + ".json")).read_text())["results"]}
        evidence_counts = Counter(dict.fromkeys((
            "reference_replays_solved", "initial_positions_live", "reference_action_coverage_passed",
            "reference_actions_checked", "naive_attempts_tested", "naive_attempts_failed",
            "alternatives_tested", "terminal_losing_replays", "live_prefixes_bounded_refuted",
            "bounded_refutations_total", "bounded_root_forced", "unverified_alternatives",
            "native_root_forced", "native_refutations_total", "live_prefixes_native_refuted",
        ), 0))
        if runtime:
            check(runtime["count"] == len(new), edition + ": runtime report coverage differs from catalog")
            check(len(runtime["results"]) == len(new) and {row.get("id") for row in runtime["results"]} == new_ids,
                  edition + ": runtime result identities differ from selected puzzles")
            for result in runtime["results"]:
                entry = by_id[result["id"]]
                check(result.get("definition") == definition(entry), entry["id"] + ": report does not match shipped definition")
                demonstrated = 0
                proof = proof_rows.get(entry["id"], {})
                bound = proof.get("definition") == definition(entry)
                native = native_rows.get(entry["id"], {})
                native_bound = (native.get("definition") == definition(entry)
                                and entry.get("objective") == {"type": "win"}
                                and native.get("reference", {}).get("ok") is True
                                and native.get("reference", {}).get("terminal") == 1
                                and native.get("native_parity", {}).get("ok") is True
                                and native.get("native_parity", {}).get("actions") == len(entry["solution"]))
                native_roots = [row.get("proof", {}) for row in native.get("native_horizons", [])
                                if row.get("turns") == entry["turns"]] if native_bound else []
                native_won = any(completed_native(row, "proven", int(entry["turns"])) for row in native_roots)
                if args.native_proof_dir:
                    check(native_bound, entry["id"] + ": missing, stale or incomplete native audit binding")
                if native_bound:
                    check(not any(completed_native(row, "no_forced_win", int(entry["turns"])) for row in native_roots),
                          entry["id"] + ": native model refutes the initial position")
                if args.proof_dir:
                    check(bool(proof), entry["id"] + ": no search report supplied")
                    check(bound, entry["id"] + ": search report does not match shipped definition")
                if bound:
                    check(proof.get("proof", {}).get("result") != "refuted",
                          entry["id"] + ": bounded search found that the opponent can refute the initial position")
                    if args.require_proofs:
                        check(len(proof.get("refutations", [])) == len(entry.get("refutations", [])),
                              entry["id"] + ": incomplete wrong-plan proof coverage")
                if args.require_proofs:
                    check((bound and proof.get("proof", {}).get("result") == "forced") or native_won,
                          entry["id"] + ": no completed root proof in either backend")
                evidence_counts["native_root_forced"] += native_won
                evidence_counts["reference_replays_solved"] += bool(result.get("solution", {}).get("ok") and result["solution"].get("terminal") == 1)
                actual_alternatives = result.get("alternative_solutions", [])
                declared_alternatives = entry.get("alternative_solutions", [])
                check(len(actual_alternatives) == len(declared_alternatives), entry["id"] + ": alternative-solution report coverage differs")
                for index, alternative in enumerate(actual_alternatives):
                    check(index < len(declared_alternatives) and alternative.get("commands") == declared_alternatives[index].get("commands"),
                          entry["id"] + ": alternate winning line evidence does not match input")
                    evidence_counts["alternative_replays_solved"] += bool(alternative.get("replay", {}).get("ok") and alternative["replay"].get("terminal") == 1)
                evidence_counts["initial_positions_live"] += result.get("initial_terminal") == 0
                evidence_counts["reference_action_coverage_passed"] += bool(result.get("action_coverage", {}).get("ok"))
                evidence_counts["reference_actions_checked"] += int(result.get("action_coverage", {}).get("checked_actions", 0))
                for baseline in result.get("baselines", {}).values():
                    evidence_counts["naive_attempts_tested"] += 1
                    evidence_counts["naive_attempts_failed"] += baseline.get("outcome") == "failed"
                result["correlated_evidence"] = {
                    "proof_definition_matches": bound,
                    "native_definition_and_reference_parity_match": native_bound,
                    "scope": "Exact-input bounded GDScript search and, when requested, separately identified native-model proofs. Reference ordering only changes search order; reference parity does not certify every native branch or human difficulty.",
                    "alternatives": [],
                }
                if native_bound:
                    result["correlated_evidence"]["native_root_search"] = native_roots
                if bound:
                    result["correlated_evidence"]["root_search"] = proof.get("proof", {})
                    evidence_counts["bounded_root_forced"] += proof.get("proof", {}).get("result") == "forced"
                for index, branch in enumerate(result.get("refutations", [])):
                    evidence_counts["alternatives_tested"] += 1
                    losing = branch.get("failure_line", branch.get("prefix", {}))
                    searched = proof["refutations"][index].get("proof", {}) if bound and index < len(proof.get("refutations", [])) else {}
                    native_branch = native["native_refutations"][index] if native_bound and index < len(native.get("native_refutations", [])) else {}
                    native_prefix = native_branch.get("prefix", {})
                    native_loss = (native_prefix.get("ok") is True
                                   and native_branch.get("label") == branch.get("label")
                                   and native_prefix.get("trace") == branch.get("prefix", {}).get("trace")
                                   and native_prefix.get("terminal") == branch.get("prefix", {}).get("terminal")
                                   and (native_prefix.get("terminal") == -1
                                        or completed_native(native_branch.get("proof", {}), "no_forced_win", int(entry["turns"]))))
                    check(searched.get("result") != "forced",
                          entry["id"] + ": GDScript search finds a win after a claimed wrong plan: " + branch.get("label", ""))
                    if native_prefix.get("ok") is True:
                        check(not completed_native(native_branch.get("proof", {}), "proven", int(entry["turns"])),
                              entry["id"] + ": native model finds a win after a claimed wrong plan: " + branch.get("label", ""))
                    evidence_counts["native_refutations_total"] += native_loss
                    if searched.get("result") == "refuted":
                        evidence_counts["bounded_refutations_total"] += 1
                    if args.require_proofs:
                        check(searched.get("result") == "refuted" or native_loss or (branch.get("prefix", {}).get("ok") and branch["prefix"].get("terminal") == -1),
                              entry["id"] + ": wrong-plan proof is missing or inconclusive: " + branch.get("label", ""))
                    evidence = {"label": branch.get("label", ""), "prefix_terminal": branch.get("prefix", {}).get("terminal")}
                    if searched:
                        evidence["prefix_search"] = searched
                    if native_branch:
                        evidence["native_prefix_search"] = native_branch.get("proof", {})
                    if losing.get("ok") and losing.get("terminal") == -1:
                        demonstrated += 1
                        evidence_counts["terminal_losing_replays"] += 1
                        evidence["kind"] = "terminal_losing_replay"
                        evidence["scope"] = "This complete legal alternative ends in failure; a shorter prefix may still be recoverable."
                    elif searched.get("result") == "refuted":
                        demonstrated += 1
                        evidence_counts["live_prefixes_bounded_refuted"] += 1
                        evidence["kind"] = "live_prefix_bounded_refuted"
                        evidence["scope"] = "The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline."
                    elif native_loss:
                        demonstrated += 1
                        evidence_counts["live_prefixes_native_refuted"] += 1
                        evidence["kind"] = "live_prefix_native_model_refuted"
                        evidence["scope"] = "The legal prefix remains live in the actual runtime; the separately bound native model completes a no-forced-win proof. This is not a completed GDScript search."
                    else:
                        evidence_counts["unverified_alternatives"] += 1
                        evidence["kind"] = "unverified_live_prefix"
                        warnings.append(entry["id"] + ": only a live prefix for " + branch.get("label", ""))
                    result["correlated_evidence"]["alternatives"].append(evidence)
                check(demonstrated >= 1, entry["id"] + ": no separately validated losing alternative")
            runtime["evidence_counts"] = dict(evidence_counts)
            runtime_path.write_text(json.dumps(runtime, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        summaries[edition] = {"old_entries_preserved": preserved, "new_entries": len(new),
                              "objectives": dict(Counter(e.get("objective", {}).get("type", "win") for e in new)),
                              "difficulty": dict(Counter(e["level"] for e in new)),
                              "player_factions": dict(Counter(e["state"]["heroes"][0]["faction"] for e in new)),
                              "hero_levels": sorted({h["level"] for e in new for h in e["state"]["heroes"]}),
                              "creature_races": sorted({card(edition, c["card"]).get("Race", "") for e in new for c in e["state"]["creatures"].values()}),
                              "runtime_checked": runtime is not None, "baselines_checked": bool(runtime and args.baselines),
                              "evidence_counts": dict(evidence_counts)}
    report = {"base_revision": args.base_ref, "collection": args.collection, "editions": summaries, "errors": errors, "warnings": warnings,
              "scope": "Preservation, content structure, exact replays and optional naive policies; not a human difficulty or exhaustive proof certificate"}
    (args.report_dir / "quality-summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for warning in warnings:
        print("NOTE " + warning)
    print(json.dumps(summaries, ensure_ascii=False, indent=2))
    print(f"EXPANSION QUALITY: {len(errors)} failure(s), {len(warnings)} review note(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
