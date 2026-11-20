#!/usr/bin/env python3
"""Source/package consistency checks for the v5 spell-repertoire extension.

Not a Godot compiler or proof of a playable puzzle. Run the existing
puzzle_generator_check.py and puzzle_variety_check.py against a complete game
checkout with Godot for combat-level certification.
"""
from __future__ import annotations
import ast
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
FILES=[
    'game/src/duel/puzzle_spell_recipes.gd',
    'game/src/duel/puzzle_recipes.gd',
    'game/src/duel/puzzle_generator.gd',
    'game/src/content/remake_text.gd',
    'tools/puzzle_generator_check.gd',
    'tools/puzzle_generator_ui_check.gd',
]

def balanced(path: Path) -> None:
    """Lex delimiters and GDScript comments, including quoted strings.

    This detects a class of copy/edit errors; it is intentionally not
    presented as a semantic syntax check or a Godot parse.
    """
    text=path.read_text(encoding='utf-8')
    stack=[]; quoted=''; escape=False; comment=False
    openers='([{'; closers=')]}'; pairs=dict(zip(closers,openers))
    for i,ch in enumerate(text):
        if ch=='\n': comment=False
        if comment: continue
        if quoted:
            if escape: escape=False
            elif ch=='\\': escape=True
            elif ch==quoted: quoted=''
            continue
        if ch=='#': comment=True; continue
        if ch in "'\"": quoted=ch; continue
        if ch in openers: stack.append((ch,i)); continue
        if ch in closers:
            assert stack and stack[-1][0]==pairs[ch], f'{path}:{text.count(chr(10),0,i)+1} unmatched {ch}'
            stack.pop()
    assert not quoted and not stack, f'{path}: unclosed quote/delimiter'
    assert '\r' not in text
    assert not any(line.startswith(' ') and line.lstrip().startswith(('func ','static func ','class_name ','extends ')) for line in text.splitlines()), f'{path}: mixed leading indentation'


def checks() -> None:
    for rel in FILES:
        balanced(ROOT/rel)
    for path in (ROOT/'tools').glob('puzzle_*.py'):
        ast.parse(path.read_text(), filename=str(path))
    recipes=(ROOT/'game/src/duel/puzzle_recipes.gd').read_text()
    spells=(ROOT/'game/src/duel/puzzle_spell_recipes.gd').read_text()
    generator=(ROOT/'game/src/duel/puzzle_generator.gd').read_text()
    lab=(ROOT/'tools/puzzle_lab.py').read_text()
    expect={'comet_split','trade_compensation','carnivore_choice'}
    for family in expect:
        assert recipes.count('"'+family+'"') >= 1, family
        assert spells.count('"'+family+'"') >= 2, family
    assert '"duel/puzzle_spell_recipes.gd"' in lab
    assert 'ELPuzzleSpellRecipes.build' in recipes and 'ELPuzzleSpellRecipes.supports' in recipes
    assert 'const VERSION := 5' in generator and 'const VERSION := 5' in recipes
    assert 'spell_inventory' in generator and 'new_roles * 120' in generator
    assert 'entry.id = "spell_recipe_candidate"' in spells
    assert 'ELPuzzleProof.apply(duel, raw)' in spells
    assert 'ELPuzzleGenerator.replay_line(profile, entry, solution)' in spells
    assert 'ELP5' in (ROOT/'tools/puzzle_generator_ui_check.gd').read_text()
    assert 'ELP5' in (ROOT/'game/src/content/remake_text.gd').read_text()
    assert 'ELP4:el1:3:1' in (ROOT/'tools/puzzle_generator_check.gd').read_text()  # old code explicitly rejected
    # Every proposed mechanic must be present in the earlier v4 logic or its
    # view event commentary; do not invent card identifiers.
    references='\n'.join((ROOT/p).read_text() for p in [
       'game/src/duel/view.gd','game/src/duel/puzzle_recipes.gd',
       'tools/puzzle_proof_check.gd','game/src/duel/puzzle_zone_recipes.gd'])
    for card in ['TPLF','COMT','TRAD','CANV','CLIG','STRG','MGHT','ZAPP']:
        assert '"'+card+'"' in references, f'no prior evidence for {card}'
    counts={
       'el1': (21,18,19,5),
       'el2': (23,20,21,5),
    }
    old_families=re.search(r'const FAMILY_IDS := \[([^\n]+)\]', recipes)
    assert old_families
    family_ids=re.findall(r'"([a-z_]+)"', old_families.group(1))
    assert len(family_ids)==23 and len(set(family_ids))==23
    assert 'aspect_toll' in family_ids
    assert counts['el1'][0]==len(family_ids)-2  # aspect_toll, carnivore_choice unavailable in EL1
    print('PASS: 6 GDScript delimiter/indentation checks')
    print('PASS: Python tool parsing; 23 unique registered families; version/UID-independent routing')
    print('PASS: spell references, seed-code safeguards, proof/replay gate, and diversity inventory wiring')
    print('UNTESTED: Godot compilation, actual card legality, solver acceptance, UI and performance')

if __name__=='__main__':
    checks()
