"""Turns the duel lines of tools/first_spell_rating.gd into the ratings table
game/src/content/first_spell_ratings.gd, or summarises its paired runs.

    python tools/first_spell_rating.py <output of the duels>... [--write]

DUEL lines (the default design): every duel pits two random books, each a
starting book with several random shop spells in place of its cheapest
copies. A card's rating is its logistic-regression coefficient times 25,
which is the slope of the win chance at 50%: an approximation of the change
in percentage points near an even duel, smaller for lopsided ones. The
cards are measured against the other shop spells bought beside them and
against the opponent's, so a rating is relative worth among shop spells,
not what the card adds to a bare starting book. Each card has its own term,
held towards what its rarity, ether cost and kind predict (it is seen in
only a hundred or so duels); the printed +- is 1.96 standard errors from
the fit. A drawn duel counts as half a win for each side.

PAIR lines (--paired): the same book with and without the card against the
same opponent and seeds, from both seats. A card's worth is the mean change
in the hero's score (a win 1, a draw 1/2) in percentage points, +- 1.96
standard errors over the trials.

Without --write the table is only printed; --write needs DUEL lines.
"""
import math
import sys
from pathlib import Path

import numpy as np

RARITIES = ["Common", "Rare", "Unique"]
TARGET = Path(__file__).resolve().parent.parent / "game/src/content/first_spell_ratings.gd"


def paired(lines: list[str], cards: dict[str, dict]) -> None:
    by_card: dict[str, list[float]] = {}
    draws = 0
    total = 0
    for line in lines:
        head = line.split("|")[0].split()
        card = head[1]
        fields = dict(part.split("=") for part in head[2:])
        before = [int(v) for v in fields["before"].split(",")]
        after = [int(v) for v in fields["after"].split(",")]
        games = max(1, sum(before))
        score = lambda t: (t[0] + 0.5 * t[1]) / games
        by_card.setdefault(card, []).append(100.0 * (score(after) - score(before)))
        draws += before[1] + after[1]
        total += sum(before) + sum(after)
    print(f"{sum(len(v) for v in by_card.values())} paired trials, {total} duels, {draws} drawn ({100.0 * draws / max(1, total):.1f}%)")
    rows = []
    for card, values in by_card.items():
        mean = sum(values) / len(values)
        spread = math.sqrt(sum((v - mean) ** 2 for v in values) / max(1, len(values) - 1)) if len(values) > 1 else float("nan")
        rows.append((mean, card, 1.96 * spread / math.sqrt(len(values)), len(values)))
    for mean, card, margin, count in sorted(rows, reverse=True):
        name = cards.get(card, {}).get("name", "")
        print(f"{card} {name}: {mean:+.1f} +- {margin:.1f} points over {count} trials")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    paths = [a for a in sys.argv[1:] if not a.startswith("--")]
    cards: dict[str, dict] = {}
    duels = []
    pairs: list[str] = []
    for path in paths:
        for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("CARD "):
                _, code, colour, rarity, cost, creature, name = line.split(" ", 6)
                cards[code] = {"colour": colour, "rarity": rarity, "cost": int(cost), "creature": int(creature), "name": name.replace("_", " ")}
            elif line.startswith("PAIR "):
                pairs.append(line)
            elif line.startswith("DUEL "):
                head, first, second = [part.strip() for part in line.split("|")]
                winner = int(head.split("winner=")[1].split()[0])
                sides = []
                for part in (first, second):
                    colour, _, listed = part.partition(" ")
                    sides.append((colour, [c for c in listed.split(",") if c]))
                duels.append((winner, sides))
    if pairs:
        paired(pairs, cards)
    if not duels:
        return
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
        # A draw is half a win for each side.
        y[n] = 0.5 if winner < 0 else (1.0 if winner == 0 else 0.0)
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
    hessian = np.diag(penalty + 1e-9)
    for _ in range(60):
        p = 1.0 / (1.0 + np.exp(-x @ w))
        gradient = x.T @ (p - y) + penalty * w
        hessian = (x * (p * (1 - p))[:, None]).T @ x + np.diag(penalty + 1e-9)
        step = np.linalg.solve(hessian, gradient)
        w -= step
        if np.abs(step).max() < 1e-7:
            break
    # Standard errors of each card's rating (own term plus its shared prior).
    covariance = np.linalg.inv(hessian)
    design = np.zeros((len(codes), width))
    design[:, :len(codes)] = np.eye(len(codes))
    design[:, len(codes):len(codes) + shared] = table
    errors = 25.0 * np.sqrt(np.einsum("ij,jk,ik->i", design, covariance, design))
    own = w[:len(codes)]
    prior = table @ w[len(codes):len(codes) + shared]
    points = 25.0 * (own + prior)
    first = sum(1 for winner, _ in duels if winner == 0)
    drawn = sum(1 for winner, _ in duels if winner < 0)
    print(f"{len(duels)} duels ({drawn} drawn), first seat won {100.0 * first / max(1, len(duels)):.1f}%, {len(codes)} cards, seen {seen.min():.0f}-{seen.max():.0f} times (mean {seen.mean():.0f}), typical margin +-{1.96 * float(np.median(errors)):.1f} points")
    print("colours:", {c: round(float(25.0 * w[len(codes) + shared + i]), 1) for i, c in enumerate(colours)})
    print("shared :", [round(float(25.0 * v), 1) for v in w[len(codes):len(codes) + shared]])
    for colour in colours:
        ranked = sorted((c for c in codes if cards[c]["colour"] == colour), key=lambda c: -points[index[c]])
        print(colour, "best :", ", ".join(f"{c} {cards[c]['name']} {points[index[c]]:+.1f}+-{1.96 * errors[index[c]]:.1f}" for c in ranked[:8]))
        print(colour, "worst:", ", ".join(f"{c} {cards[c]['name']} {points[index[c]]:+.1f}+-{1.96 * errors[index[c]]:.1f}" for c in ranked[-6:]))
    if "--write" not in sys.argv:
        return
    lines = [
        "class_name ELFirstSpellRatings",
        "extends RefCounted",
        "## Relative worth of each first-game shop spell to a computer hero, in",
        "## tenths of a point: 25 times the card's logistic-regression coefficient",
        "## over %d computer-vs-computer duels between random books (starting" % len(duels),
        "## books with several random shop spells), which approximates the change",
        "## in win chance in percentage points near an even duel only. The cards",
        "## are measured against the other shop spells, so the numbers rank them;",
        "## they are not what a card adds to a bare starting book. Written by",
        "## tools/first_spell_rating.py from the output of tools/first_spell_rating.gd",
        "## (its paired mode measures single replacements). Do not edit by hand.",
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
