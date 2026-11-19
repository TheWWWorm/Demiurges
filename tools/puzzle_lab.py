#!/usr/bin/env python3
"""Run authored puzzles against the real GDScript battle rules, without game art.

The isolated test project copies the repository's battle implementation.
On Godot 4.6, explicit typed-array coercions provide 4.7 return-type behavior;
they do not alter the battle logic.
Only file/asset/campaign services are replaced with deliberately narrow fixtures.
Printed card data is read from the checked-in English wiki, separately per edition.
This is a content test, not an original-game installation or a rendering test.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CORE = [
    "duel/state.gd", "duel/catalog.gd", "duel/match_save.gd",
    "duel/specs.gd", "duel/spell_charges.gd", "duel/hero_effects.gd",
    "duel/combat_search.gd", "duel/combat_brain.gd", "duel/puzzles.gd",
    "content/runes.gd", "content/hero_skills.gd", "content/hero_progression.gd",
    "content/safe_file.gd",
]
CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.M)
CLASS_USE = re.compile(r"\bEL[A-Z]\w*")
FLAGS = {
    "Flying": "Fly", "First Strike": "FS", "Unblockable": "UB",
    "Cannot attack": "NoAttack", "Cannot get up": "NoUntap",
    "Unaffected": "NoAffect", "Cannot be targeted": "NoTarget",
    "Team Attack": "TeamAttack", "Outerplanar": "Outerplanar",
    "Team attacker": "TeamAttack", "Creature cannot get up": "NoUntap",
    "Ether Defense": "NoTarget", "Poisonous": "Destroy", "Haste": "NSS",
    "Pale": "Outerplanar",
}


def plain(value: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", value)).strip()


def hero_template_sources() -> dict:
    """Known template references, not fabricated original hero-stat rows.

    Story gallery entries are explicitly HeroTemplates keys (wiki_screen.gd).
    Edition-specific references catch spelling errors and cross-edition forms
    before the offline fixture synthesizes the minimal restore-only row.
    """
    known = {"el1": {}, "el2": {}}

    def add(edition, name, source):
        known[edition].setdefault(name, []).append(source)

    path = "game/src/duel/catalog.gd"
    source = (ROOT / path).read_text()
    defaults = json.loads(re.search(r"const HEROES := (\{[^\n]+\})", source).group(1))
    for edition in known:
        for faction, name in defaults.items():
            # default_hero has this explicit edition override.
            add(edition, "RedMale4" if edition == "el2" and faction == "Red" else name, path)
    white = re.search(r'if faction == "White" and profile.id == "el2": return "([^"]+)"', source)
    if white:
        add("el2", white.group(1), path)
    path = "game/src/duel/duel_presets.gd"
    source = (ROOT / path).read_text()
    defaults = json.loads(re.search(r"const DEFAULT_HEROES := (\{[^\n]+\})", source).group(1))
    for edition in known:
        for name in defaults.values():
            add(edition, name, path)
    for page in sorted((ROOT / "wiki/en").glob("*.md")):
        match = re.search(r"^heroes: (.+)$", page.read_text(), re.M)
        if not match:
            continue
        for item in match.group(1).split(" | "):
            identity = item.partition(" = ")[0].strip()
            edition, _, name = identity.partition("/")
            if edition in known and name:
                add(edition, name, page.relative_to(ROOT).as_posix())
    return known


def card_tables() -> dict:
    result = {edition: {"CombatSpells": {}, "CombatCreatures": {}, "HeroesSkills": {}, "texts": {}}
              for edition in ("el1", "el2")}
    catalog = json.loads((ROOT / "wiki/catalog/en.json").read_text())
    known_heroes = hero_template_sources()
    for edition in result:
        result[edition]["HeroTemplateSources"] = known_heroes[edition]
    unknown = set()
    for page in catalog["pages"]:
        # Registration rows come from the checked-in skill reference. Effects
        # and rank validation still run through the real game classes below.
        # Do not fabricate specialization/luck tables or campaign skill offers.
        if page.get("kind") == "skill" and page.get("key") in ("skill-regn", "skill-cnlg"):
            code = page["key"].removeprefix("skill-").upper()
            sections = re.findall(r"<h2>(Etherlords(?: II)?)</h2>\s*<table[^>]*>(.*?)</table>", page["html"], re.S)
            for heading, skill_table in sections:
                edition = "el2" if heading == "Etherlords II" else "el1"
                for row in re.findall(r"<tr>(.*?)</tr>", skill_table, re.S):
                    cells = [plain(v) for v in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)]
                    if cells and cells[0] in ("1", "2", "3"):
                        result[edition]["HeroesSkills"][code + cells[0]] = {"Code": code, "Level": int(cells[0]), "Name": code + "Nm"}
                result[edition]["texts"][code + "Nm"] = page["title"]
            continue
        if not page.get("card"):
            continue
        card = page["card"]
        table = re.search(r"<table[^>]*>(.*?)</table>", page["html"], re.S)
        if not table:
            continue
        rows = re.findall(r"<tr>(.*?)</tr>", table.group(1), re.S)
        headers = [plain(v) for v in re.findall(r"<th[^>]*>(.*?)</th>", rows[0])]
        columns = [(i, "el2" if name == "Etherlords II" else "el1")
                   for i, name in enumerate(headers) if name in ("Etherlords", "Etherlords II")]
        if not columns and len(page.get("games", [])) == 1:
            columns = [(1, page["games"][0])]
        values = {}
        for row in rows[1:] if headers else rows:
            cells = [plain(v) for v in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)]
            if cells:
                values[cells[0]] = cells
        for col, edition in columns:
            def get(key, default=""):
                cells = values.get(key, [])
                return cells[col] if len(cells) > col else default
            if get("Type") in ("", "—"):
                continue
            kind = "Creature" if get("Type") == "Summoning" else get("Type")
            cost = get("Ether cost", "0")
            # X is supplied independently by the battle's variable-power rules.
            cost = int(cost) if cost.isdigit() else int(re.match(r"\d+", cost).group(0)) if re.match(r"\d+", cost) else 0
            spell = {"Class": kind, "Cost": cost, "Color": {
                "Chaot": "Red", "Vital": "Green", "Synthet": "Black", "Kinet": "Blue",
                "Colourless": "White", "Colorless": "White", "Neutral": "White"}.get(get("Faction"), "White"),
                "Rarity": get("Rarity", "Common"), "Name": card + "Nm", "UseIn": "Both"}
            if kind == "Creature":
                flags = []
                for flag in get("Abilities").split(", "):
                    if flag in ("", "—"):
                        continue
                    if flag.startswith("Regeneration ("):
                        flag = "Regen(" + flag.split("(")[1]
                    elif flag.startswith("Discard ("):
                        flag = "Discard(" + flag.split("(")[1]
                    else:
                        flag = FLAGS.get(flag, flag)
                    flags.append(flag)
                creature = {"Power": int(get("Power", "0")), "Toughness": int(get("Toughness", "1")),
                            "Race": get("Race"), "Flags": flags}
                result[edition]["CombatCreatures"][card] = creature
            result[edition]["CombatSpells"][card] = spell
            result[edition]["texts"][card + "Nm"] = page["title"]
    return result


PROFILE = '''class_name ELProfile
extends RefCounted
var id := ""
var title := ""
var error := ""
var tables: Dictionary = {}
var texts: Dictionary = {}
func mount(_edition: String, _path: String) -> bool:
    error = "Use the game project directly for --installed, not the isolated offline fixture."
    return false
func table(key: String) -> Dictionary:
    return tables.get(key, {})
func text(key: String) -> String:
    return texts.get(key, key)
'''

STUBS = {
"lua_save.gd": '''class_name ELLuaSave
extends RefCounted
static func _integer(value: Variant, low: int, high: int) -> bool:
    return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high
''',
"resources.gd": '''class_name ELResources
extends RefCounted
const MAX_AMOUNT := 2147483647
''',
"first_monsters.gd": '''class_name ELFirstMonsters
extends RefCounted
static func appearance(_p: ELProfile, _name: String, _difficulty: int) -> Dictionary:
    return {}
''',
"strategy.gd": '''class_name ELStrategy
extends RefCounted
static func recalculate(_hero: Dictionary) -> void:
    assert(false, "Campaign skill progression is not supported in puzzle fixtures")
''',
"duel_costs.gd": '''class_name ELDuelCosts
extends RefCounted
static func sandbox(p: ELProfile, level: int) -> bool:
    return p.id == "el2" and level == 6
static func spell_allowed(p: ELProfile, card: String, faction: String, level: int) -> bool:
    return sandbox(p, level) or p.table("CombatSpells").get(card, {}).get("Color", "") in [faction, "White"]
''',
"second_artifacts.gd": '''class_name ELSecondArtifacts
extends RefCounted
const BLANK_SPELL := "BLNK"
static func custom_definition(_p: ELProfile, _custom: Variant) -> Dictionary:
    assert(false, "Artifact fixtures are not supported")
    return {}
static func max_charges(_p: ELProfile, _item: Dictionary) -> int:
    assert(false, "Artifact fixtures are not supported")
    return 0
static func title(_p: ELProfile, _item: Dictionary) -> String:
    return "Unsupported artifact"
''',
"battle_scripts.gd": '''class_name ELBattleScripts
extends RefCounted
var search_only := true
var local_variables := {}
var difficulty := 1
var draining := false
var queue: Array = []
func _init(_duel: Variant = null) -> void:
    pass
static func valid(_profile: ELProfile, _state: Variant) -> bool:
    return false
func close() -> void:
    pass
func load_all(_list: Array) -> void:
    assert(false, "Campaign scripts are not supported in puzzle fixtures")
func dispatch(_name: String, _args: Array) -> void:
    assert(false, "Campaign scripts are not supported in puzzle fixtures")
func turn_start(_side: int, _turn: int) -> void:
    assert(false, "Campaign scripts are not supported in puzzle fixtures")
func bind(_duel: Variant) -> void:
    pass
func summoned(_side: int, _card: String, _id: int) -> void:
    assert(false, "Campaign scripts are not supported in puzzle fixtures")
func drain() -> void:
    assert(false, "Campaign scripts are not supported in puzzle fixtures")
func search_layer(_duel: Variant) -> ELBattleScripts:
    return null
func snapshot() -> Dictionary:
    return {}
func restore(_state: Dictionary) -> String:
    return "Campaign scripts are not supported in puzzle fixtures"
''',
"duel_match.gd": '''class_name ELDuelMatch
extends RefCounted
static func arenas(_p: ELProfile) -> Array:
    return []
''',
"remake_text.gd": '''class_name ELRemakeText
extends RefCounted
static func language(_p: ELProfile) -> String:
    return "en"
''',
}


def typed_array_compat(source: str) -> str:
    """4.7 infers a typed conditional array return; 4.6 needs assign()."""
    output, helpers = [], {}
    current = None
    indent = 0
    lambda_indent = None
    for line in source.splitlines():
        lead = len(line) - len(line.lstrip("\t"))
        if lambda_indent is not None and line.strip() and lead <= lambda_indent:
            lambda_indent = None
        if line.strip() and not line.lstrip().startswith("#"):
            if current is not None and lead <= indent:
                current = None
        found = re.match(r"(\t*)(?:static )?func .* -> Array\[([^]]+)\]:", line)
        if found:
            current = found.group(2)
            indent = len(found.group(1))
            helpers[current] = "_lab_array_" + re.sub(r"\W", "_", current)
        elif current and "func(" in line:
            if line.rstrip().endswith(":"):
                lambda_indent = lead
        elif current and lambda_indent is None:
            found = re.search(r"\breturn (.+)", line)
            if found:
                expression = found.group(1)
                line = line[:found.start(1)] + helpers[current] + "(" + expression + ")"
        output.append(line)
    for kind, helper in helpers.items():
        output += ["", f"static func {helper}(value: Array) -> Array[{kind}]:",
                   f"\tvar out: Array[{kind}] = []", "\tout.assign(value)", "\treturn out"]
    return "\n".join(output) + "\n"


def _code(source: str) -> str:
    """GDScript without its comments and string literals (where a class name
    is only mentioned)."""
    source = re.sub(r'"""(.|\n)*?"""|\'\'\'(.|\n)*?\'\'\'', "", source)
    source = re.sub(r'"(\\.|[^"\\\n])*"|\'(\\.|[^\'\\\n])*\'', '""', source)
    return re.sub(r"#.*", "", source)


def missing_classes(destination: Path) -> dict:
    """Engine classes (EL...) the lab's scripts use but no lab script declares:
    {class: (the scripts using it, the game file that declares it or None)}."""
    declared, used = set(), {}
    for script in sorted(destination.glob("*.gd")):
        source = script.read_text(encoding="utf-8")
        declared.update(CLASS_NAME.findall(source))
        for name in set(CLASS_USE.findall(_code(source))):
            used.setdefault(name, []).append(script.name)
    game = {}
    for script in (ROOT / "game/src").rglob("*.gd"):
        for name in CLASS_NAME.findall(script.read_text(encoding="utf-8")):
            game[name] = script.relative_to(ROOT / "game/src").as_posix()
    # Inner classes and constants (ELPathTracing.Effect) are reached through
    # their outer class, which is what has to be declared.
    return {name: (users, game.get(name)) for name, users in used.items() if name not in declared and name in game}


def prepare(destination: Path, compatibility: bool = True) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Demiurges Puzzle Lab"\nrun/flush_stdout_on_print=true\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    for source in CORE:
        content = (ROOT / "game/src" / source).read_text()
        (destination / Path(source).name).write_text(typed_array_compat(content) if compatibility else content)
    (destination / "profile.gd").write_text(PROFILE)
    for name, source in STUBS.items():
        (destination / name).write_text(source)
    shutil.copy2(ROOT / "tools/puzzle_lab.gd", destination / "puzzle_lab.gd")
    shutil.copy2(ROOT / "tools/puzzle_lab_checks.gd", destination / "puzzle_lab_checks.gd")
    (destination / "fixture.json").write_text(json.dumps(card_tables(), ensure_ascii=False))
    # The native bridge is optional. Its model code is compiled unchanged; only
    # transport uses files because the shipped extension binds to Godot 4.7.
    compiler = shutil.which("cc")
    if compiler:
        bridge = destination / "native_bridge.c"
        bridge.write_text('#include <stdio.h>\n#include "' + str(ROOT / "game/native/el_duel_brain.c") + '"\n'
            'int main(int argc,char **argv){if(argc!=3)return 2; FILE *f=fopen(argv[1],"rb");if(!f)return 3; '
            'fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);int32_t *in=malloc(n), out[4096]={0}; '
            'if(!in||fread(in,1,n,f)!=(size_t)n)return 4;fclose(f);int k=run_search(in,n/4,out);free(in); '
            'f=fopen(argv[2],"wb");if(!f)return 5;fwrite(out,4,k,f);fclose(f);return 0;}\n')
        binary = destination / "native_bridge"
        command = [compiler, "-O2", "-D_POSIX_C_SOURCE=200809L", "-std=c11", str(bridge), "-o", str(binary)]
        # A copied lab can contain a newer binary compiled from another
        # checkout. Timestamps cannot certify which rules that binary uses.
        # Bind the cache to the actual wrapper, model, header and compiler.
        digest = hashlib.sha256()
        for data in (bridge.read_bytes(), (ROOT / "game/native/el_duel_brain.c").read_bytes(),
                     (ROOT / "game/native/include/gdextension_interface.h").read_bytes(),
                     "\0".join(command).encode(),
                     subprocess.run([compiler, "--version"], capture_output=True, check=True).stdout):
            digest.update(len(data).to_bytes(8, "big"))
            digest.update(data)
        fingerprint = digest.hexdigest()
        stamp = destination / "native_bridge.sha256"
        if not binary.exists() or not stamp.exists() or stamp.read_text().strip() != fingerprint:
            staged_binary = destination / "native_bridge.build"
            try:
                subprocess.run(command[:-1] + [str(staged_binary)], check=True)
                staged_binary.replace(binary)
                stamp.write_text(fingerprint + "\n")
            finally:
                staged_binary.unlink(missing_ok=True)
        brain = destination / "combat_brain.gd"
        source = brain.read_text()
        source = source.replace('static var available := ClassDB.class_exists(&"ELNativeDuelBrain")', 'static var available := true')
        source = source.replace('ClassDB.class_call_static(&"ELNativeDuelBrain", &"search", bytes)', '_lab_native(bytes)')
        source += '''
static func _lab_native(bytes: PackedByteArray) -> PackedByteArray:
	var root := ProjectSettings.globalize_path("res://")
	var input := root.path_join("native-in.bin")
	var output := root.path_join("native-out.bin")
	var file := FileAccess.open(input, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var result := OS.execute(root.path_join("native_bridge"), [input, output])
	if result != 0: return PackedByteArray()
	return FileAccess.get_file_as_bytes(output)
'''
        brain.write_text(source)
    # A battle file that starts using another engine class needs it copied
    # (CORE) or stubbed (STUBS); say which instead of a parse error later.
    missing = missing_classes(destination)
    if missing:
        lines = [f"  {name} (game/src/{source}), used by {', '.join(users)}" for name, (users, source) in sorted(missing.items())]
        raise SystemExit("puzzle lab: these classes are not in the lab; add their files to CORE or a stub to STUBS in tools/puzzle_lab.py:\n" + "\n".join(lines))
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--prepare", action="store_true", help="Prepare an isolated lab and print its path.")
    args, forward = parser.parse_known_args()
    destination = args.workspace or Path(tempfile.mkdtemp(prefix="demiurges-puzzle-lab-"))
    version = subprocess.run([args.godot, "--version"], capture_output=True, text=True, check=True).stdout
    prepare(destination, compatibility=version.startswith("4.6"))
    scanned = subprocess.run([args.godot, "--headless", "--editor", "--path", str(destination), "--quit"], text=True, capture_output=True)
    if "SCRIPT ERROR" in scanned.stdout + scanned.stderr or scanned.returncode:
        print(scanned.stdout + scanned.stderr)
        return 1
    parsed = subprocess.run([args.godot, "--headless", "--path", str(destination), "--script", "puzzle_lab.gd", "--check-only"], text=True, capture_output=True)
    if "SCRIPT ERROR" in parsed.stdout + parsed.stderr or parsed.returncode:
        print(parsed.stdout + parsed.stderr)
        return 1
    if args.prepare:
        print(destination)
        return 0
    process = subprocess.Popen([args.godot, "--headless", "--path", str(destination), "--script", "puzzle_lab.gd", "--", *forward], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=1)
    runtime_error = False
    for line in process.stdout:
        print(line, end="", flush=True)
        runtime_error = runtime_error or "SCRIPT ERROR" in line or line.startswith("ERROR:")
    status = process.wait()
    return 1 if runtime_error else status


if __name__ == "__main__":
    raise SystemExit(main())
