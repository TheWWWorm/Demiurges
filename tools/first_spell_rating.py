"""Turns the duel lines of tools/first_spell_rating.gd into the ratings table
game/src/content/first_spell_ratings.gd.

    python tools/first_spell_rating.py <output of the duels>... [--write]

A rating is the change in a starting book's chance to win a duel, in
percentage points, when one of its cheapest spells is replaced by the card.
It is fitted by logistic regression over all duels: each card has its own
term, held towards what its rarity, ether cost and kind predict, since a
card is seen in only a hundred or so duels. Without --write the table is
only printed.
"""
import math
import sys
from pathlib import Path

import numpy as np

RARITIES = ["Common", "Rare", "Unique"]
TARGET = Path(__file__).resolve().parent.parent / "game/src/content/first_spell_ratings.gd"


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    paths = [a for a in sys.argv[1:] if not a.startswith("--")]
    cards: dict[str, dict] = {}
    duels = []
    for path in paths:
        for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("CARD "):
                _, code, colour, rarity, cost, creature, name = line.split(" ", 6)
                cards[code] = {"colour": colour, "rarity": rarity, "cost": int(cost), "creature": int(creature), "name": name.replace("_", " ")}
            elif line.startswith("DUEL "):
                head, first, second = [part.strip() for part in line.split("|")]
                winner = int(head.split("winner=")[1].split()[0])
                if winner < 0:
                    continue
                sides = []
                for part in (first, second):
                    colour, _, listed = part.partition(" ")
                    sides.append((colour, [c for c in listed.split(",") if c]))
                duels.append((winner, sides))
    codes = sorted(cards)
    index = {code: i for i, code in enumerate(codes)}
    colours = sorted({c["colour"] for c in cards.values()})
    # Shared terms: rarity, ether cost per rarity, creature; then colour and the first seat.
    shared = len(RARITIES) * 2 + 1
    width = len(codes) + shared + len(colours) + 1

    def features(code: str) -> np.ndarray:
        row = np.zeros(shared)
        card = cards[code]
        r = RARITIES.index(card["rarity"])
        row[r] = 1.0
        row[len(RARITIES) + r] = (card["cost"] - 3) / 3.0
        row[-1] = card["creature"]
        return row

    table = np.array([features(code) for code in codes])
    x = np.zeros((len(duels), width))
    y = np.zeros(len(duels))
    seen = np.zeros(len(codes))
    for n, (winner, sides) in enumerate(duels):
        y[n] = 1.0 if winner == 0 else 0.0
        for side, (colour, listed) in enumerate(sides):
            sign = 1.0 if side == 0 else -1.0
            for code in listed:
                if code not in index:
                    continue
                x[n, index[code]] += sign
                x[n, len(codes):len(codes) + shared] += sign * table[index[code]]
                seen[index[code]] += 1
            x[n, len(codes) + shared + colours.index(colour)] += sign
        x[n, -1] = 1.0
    # Ridge: strong on each card's own term, weak on the shared ones.
    penalty = np.concatenate([np.full(len(codes), 12.0), np.full(shared, 0.5), np.full(len(colours), 0.5), [0.0]])
    w = np.zeros(width)
    for _ in range(60):
        p = 1.0 / (1.0 + np.exp(-x @ w))
        gradient = x.T @ (p - y) + penalty * w
        hessian = (x * (p * (1 - p))[:, None]).T @ x + np.diag(penalty + 1e-9)
        step = np.linalg.solve(hessian, gradient)
        w -= step
        if np.abs(step).max() < 1e-7:
            break
    own = w[:len(codes)]
    prior = table @ w[len(codes):len(codes) + shared]
    points = 25.0 * (own + prior)
    first = sum(1 for winner, _ in duels if winner == 0)
    print(f"{len(duels)} duels, first seat won {100.0 * first / max(1, len(duels)):.1f}%, {len(codes)} cards, seen {seen.min():.0f}-{seen.max():.0f} times (mean {seen.mean():.0f})")
    print("colours:", {c: round(float(25.0 * w[len(codes) + shared + i]), 1) for i, c in enumerate(colours)})
    print("shared :", [round(float(25.0 * v), 1) for v in w[len(codes):len(codes) + shared]])
    for colour in colours:
        ranked = sorted((c for c in codes if cards[c]["colour"] == colour), key=lambda c: -points[index[c]])
        print(colour, "best :", ", ".join(f"{c} {cards[c]['name']} {points[index[c]]:+.1f}" for c in ranked[:8]))
        print(colour, "worst:", ", ".join(f"{c} {cards[c]['name']} {points[index[c]]:+.1f}" for c in ranked[-6:]))
    if "--write" not in sys.argv:
        return
    lines = [
        "class_name ELFirstSpellRatings",
        "extends RefCounted",
        "## What a shop spell adds to a computer hero's starting book: the change in",
        "## its chance to win a duel, in tenths of a percentage point, when the card",
        "## replaces one of the book's cheapest spells. Measured over %d" % len(duels),
        "## computer-vs-computer duels; written by tools/first_spell_rating.py from",
        "## the output of tools/first_spell_rating.gd. Do not edit by hand.",
        "const POINTS := {",
    ]
    for colour in colours:
        row = ", ".join(f'"{c}": {int(round(10 * points[index[c]]))}' for c in codes if cards[c]["colour"] == colour)
        lines.append(f"\t# {colour}")
        lines.append(f"\t{row},")
    lines.append("}")
    lines.append("")
    TARGET.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print("written", TARGET)


if __name__ == "__main__":
    main()
