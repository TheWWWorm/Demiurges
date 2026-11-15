"""Small, deterministic authoring helpers for the tactical puzzle collection.

Card values come from the repository's published encyclopedia. The headless
puzzle lab subsequently restores every position through ELMatchSave and checks
it using the real battle implementation. No original game assets are bundled.
"""
from __future__ import annotations

from copy import deepcopy
from functools import lru_cache
from pathlib import Path
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
HEROES = {"Red": "RedMaleWarrior2", "Green": "GreenMale1", "Black": "BlackMale1", "Blue": "BlueWingedMale1", "White": "White Lord I"}
FACTIONS = {"Chaot": "Red", "Vital": "Green", "Synthet": "Black", "Kinet": "Blue", "Colourless": "White", "Pale": "White"}
FLAGS = {"Flying": "Fly", "Cannot attack": "NoAttack", "First Strike": "FS", "Haste": "NSS", "Poisonous": "Destroy", "Creature cannot get up": "NoUntap", "Unblockable": "UB", "Team attacker": "TeamAttack", "Ether Defense": "NoTarget", "Unaffected": "NoAffect", "Pale": "Outerplanar"}
BUFFS = {"LSST": (1, 1), "TWEN": (2, 2), "SHCL": (2, 0), "STAT": (1, 0), "TGSK": (0, 1), "UPGD": (2, 2), "FAIL": (-2, 0), "DISM": (-6, 0), "SCSK": (0, 2), "BLSS": (4, 4), "MGHT": (3, 0), "STRG": (4, 0), "WEAK": (-4, -4), "SHSK": (0, 4), "QKFX": (-1, -1)}
AURAS = {"TIWK": ("Tick", 1, 1, False), "TIQN": ("Tick", 0, 2, False), "BEWK": ("Bee", 1, 0, False), "BEQN": ("Bee", 1, 1, False), "KBWR": ("Kobold", 1, 0, False), "SLWL": ("Wall", 0, 1, True), "AVEL": ("Aviak", 1, 1, False), "ORWR": ("Orc", 1, 1, False), "GRFG": ("Fingus", 1, 1, False)}


@lru_cache(maxsize=1)
def catalog():
    out = {}
    document = json.loads((ROOT / "wiki/catalog/en.json").read_text())
    for page in document["pages"]:
        if not page.get("card"):
            continue
        table = re.search(r"<table[^>]*>(.*?)</table>", page["html"], re.S)
        if not table:
            continue
        rows = []
        for row in re.findall(r"<tr>(.*?)</tr>", table[1], re.S):
            rows.append([html.unescape(re.sub(r"<[^>]*>", "", value)).strip() for value in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)])
        has_header = bool(re.search(r"<th[\s>]", table[1]))
        games = ["el2" if "II" in label else "el1" for label in rows[0][1:]] if has_header else page["games"]
        for index, game in enumerate(games, 1):
            values = {row[0]: row[index] for row in (rows[1:] if has_header else rows) if len(row) > index}
            if values.get("Type", "—") == "—":
                continue
            flags = []
            for value in values.get("Abilities", "").split(", "):
                if value in ("", "—"):
                    continue
                flag = FLAGS.get(value, value)
                flag = re.sub(r"Regeneration\s*\((\d+)\)", r"Regen(\1)", flag)
                flag = re.sub(r"Discard\s*\((\d+)\)", r"Discard(\1)", flag)
                flags.append(flag)
            out[game, page["card"]] = dict(values, flags=flags, title=page["title"])
    return out


def card(game, code):
    return catalog()[game, code]


def hero(faction, hand, mana=0, health=20, channels=0, grave=None, enchantments=None, deck=None,
         level=4, template=None, turns=None, **extras):
    if not isinstance(level, int) or isinstance(level, bool) or not 1 <= level <= 20:
        raise ValueError("Hero level must be an integer from 1 through 20")
    if turns is not None and (not isinstance(turns, int) or isinstance(turns, bool) or turns < 1):
        raise ValueError("A supplied hero turn count must be a positive integer")
    value = dict(faction=faction, template=template or HEROES[faction], hand=list(hand), mana=mana, health=health, maximum=max(health, 20), channels=channels, grave=list(grave or []), enchantments=deepcopy(enchantments or []), deck=list(deck) if deck is not None else ["STRT"], level=level, turns=4 if turns is None else turns, kind="hero", skills={}, spec="NONE", spec_level=level, luck=0, suppression=0, artifacts=[], artifact_uses=0)
    # Authoring-only markers disappear in state(); old default snapshots stay
    # byte-equivalent in gameplay, while explicit appearances/clocks survive.
    value["_explicit_template"] = template is not None
    value["_explicit_turns"] = turns is not None
    value.update(extras)
    return value


def unit(card, id, side=0, **overrides):
    value = dict(card=card, id=id, owner=side, damage=0, resting=False, sick=False, regenerated=False, enchantments=[])
    value.update(overrides)
    return value


def enchant(card, **overrides):
    power, toughness = BUFFS.get(card, (0, 0))
    value = dict(card=card, power=power, toughness=toughness)
    value.update(overrides)
    return value


def state(game, own, enemy, units, phase=0, attacker=0, attacks=None, blocks=None, **extras):
    heroes = deepcopy([own, enemy])
    creatures = {str(c["id"]): deepcopy(c) for c in units}
    for side, h in enumerate(heroes):
        h["id"] = side
        explicit_template = h.pop("_explicit_template", False)
        explicit_turns = h.pop("_explicit_turns", False)
        if h["faction"] == "Red" and game == "el2" and not explicit_template: h["template"] = "RedMale4"
        if not explicit_turns: h["turns"] = 4 if side == 0 or attacker == 1 else 3
        h.setdefault("hand_slots", [-1] * len(h["hand"]))
        h.setdefault("hand_view", list(range(len(h["hand"]))))
        h.setdefault("drawn", [])
        h.setdefault("spell_uses", [-1 if game == "el1" and card(game, c).get("Rarity") == "Cantrip" else 1 for c in h["deck"]])
    serial = sum(h["turns"] for h in heroes)
    next_enchantment = 1
    for entity in heroes + list(creatures.values()):
        normalized = []
        for mark in entity.get("enchantments", []):
            e = enchant(mark) if isinstance(mark, str) else deepcopy(mark)
            e.setdefault("id", next_enchantment)
            next_enchantment = max(next_enchantment, e["id"] + 1)
            e.setdefault("power", 0)
            e.setdefault("toughness", 0)
            e.setdefault("owner", entity.get("owner", entity.get("id", 0)))
            e.setdefault("born", serial)
            e.setdefault("used", False)
            normalized.append(e)
        entity["enchantments"] = normalized
    for c in creatures.values():
        row = card(game, c["card"])
        c.setdefault("flags", list(row["flags"]))
        c.setdefault("flying", "Fly" in c["flags"])
        power, toughness = int(row["Power"]), int(row["Toughness"])
        for e in c["enchantments"]:
            power += e["power"]
            toughness += e["toughness"]
        for source in creatures.values():
            aura = AURAS.get(source["card"])
            if aura and row.get("Race") == aura[0] and (not aura[3] or source["owner"] == c["owner"]):
                power += aura[1]
                toughness += aura[2]
            if c["card"] == "WRSP":
                if source["card"] == "WZSP": power += 2
                if source["card"] == "SHSP": toughness += 1
                if source["card"] == "CLSP": power, toughness = power + 1, toughness + 1
        power, toughness = max(0, power), max(1, toughness)
        if sum(e["card"] == "DELS" for e in c["enchantments"]) % 2: power, toughness = toughness, power
        c.setdefault("power", power)
        c.setdefault("toughness", toughness)
    value = dict(profile=game, charge_version=2, payment_version=1, round=max(h["turns"] for h in heroes), phase=phase, attacker=attacker, heroes=heroes, creatures=creatures, attacks=list(attacks or []), blocks={str(k): v for k, v in (blocks or {}).items()}, winner=-1, rng=712367, next_id=max([1] + [c["id"] for c in creatures.values()]) + 1, next_enchantment=next_enchantment, turn_serial=serial, setup={"puzzle_fixed_hands": True, "puzzle_fixed_channels": True, "players": [{"faction": h["faction"], "level": h["level"]} for h in heroes]})
    value.update(extras)
    return value


def puzzle(game, slug, title, category, level, turns, position, briefing, hints, explanation, solution, objective=None, **extras):
    value = dict(id=f"{game}_tactical_v2_{slug}", title=title, category=category, level=level, turns=turns, state=position, briefing=briefing, hints=list(hints), explanation=explanation, solution=deepcopy(solution), objective=objective or {"type": "win"}, authored=True)
    value.update(extras)
    return value


def cast(card, target=-1, **extra): return dict(kind="cast", card=card, target=target, **extra)
def ability(id, key, target=-1, **extra): return dict(kind="ability", id=id, key=key, target=target, **extra)
def attack(id, **extra): return dict(kind="attack", id=id, **extra)
def block(id, target, **extra): return dict(kind="block", id=id, target=target, **extra)
def end(**extra): return dict(kind="end_phase", **extra)
