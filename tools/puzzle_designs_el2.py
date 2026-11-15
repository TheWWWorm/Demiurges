"""Etherlords II studies: card economy, response windows and unusual targets."""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end


def puzzles():
    game = "el2"
    out = []
    out.append(puzzle(game, "repair_by_breaking", "Repair by Breaking", "Graveyard conversion", 1, 1,
        state(game, hero("Black", ["PRFY", "REPR"], mana=5, health=7), hero("Blue", [], health=5), [
            unit("MCWY", 2, enchantments=[enchant("QKFX", id=1), enchant("TWEN", id=2)]),
            unit("WLBZ", 3, 1), unit("WLBZ", 4, 1)]),
        "Two walls stop your Wyrm. Find a win this turn without depending on combat. Inspect both enchantments on your creature.",
        ["The graveyard can be a firing position.", "One of your creature's enchantments is keeping it alive. Removing it does more than change its stats.", "Purify Quick Fix on your own Mech Wyrm, then Repair the Wyrm from your graveyard."],
        "Removing Quick Fix destroys its creature. Repair then returns the Wyrm and deals its printed 5 power to the enemy. Removing Twisted Enhancement merely weakens the Wyrm; attacking into two walls does not win.",
        [cast("PRFY", 2, grave=1), cast("REPR", 0, grave=0)],
        refutations=[{"label": "Remove the visible stat bonus instead of Quick Fix", "commands": [cast("PRFY", 2, grave=2)]}]))

    out.append(puzzle(game, "other_reservoir", "The Other Reservoir", "Redirection and resources", 2, 1,
        state(game, hero("Black", ["PWTP", "FDBK", "BRRL"], mana=7, health=3), hero("Blue", [], mana=3, health=4), []),
        "Both ether pools are within reach. Find a lethal line that leaves your fragile hero alive. Stealing ether also takes away the obvious damage source.",
        ["A damaging spell does not always need an enemy target.", "After Powertap and Feedback, compare the ether in the two pools. Remember that Broken Reality pays its own cost first.", "Use Powertap, put Feedback on yourself, then cast Broken Reality on your own hero."],
        "Powertap costs 1 and transfers the enemy's 3 ether, leaving pools of 9 and 0. Feedback costs 4. Broken Reality costs 1 before emptying your remaining 4 ether; Feedback redirects those 4 damage. Burning the enemy at the start deals only 3, and burning your own pool without protection is fatal.",
        [cast("PWTP"), cast("FDBK"), cast("BRRL", 0)],
        refutations=[{"label": "Burn the enemy pool immediately", "commands": [cast("BRRL", 1)]},
                     {"label": "Steal, then burn the enemy pool", "commands": [cast("PWTP"), cast("BRRL", 1)]},
                     {"label": "Burn yourself without Feedback", "commands": [cast("BRRL", 0)]}]))

    out.append(puzzle(game, "shield_elsewhere", "The Shield Belongs Elsewhere", "Defensive role assignment", 2, 1,
        state(game, hero("Blue", ["LFGR"], mana=4, health=3), hero("Red", [], health=20), [
            unit("AVMK", 2), unit("STRT", 3), unit("GRDG", 4, 1), unit("MNTS", 5, 1), unit("STRT", 6, 1)],
            phase=1, attacker=1, attacks=[4, 5, 6]),
        "The enemy attack is already committed. Survive it without losing any hero health, and keep your Aviak Marksman alive. One ally may be sacrificed.",
        ["Your Marksman is useful even without blocking. A shield only stops one damage event.", "Remove the smallest attacker, block the middle one, and find a different answer to the dragon.", "Shoot the enemy Stink Rat with your Marksman; put Lifeguard on your hero; block the Mantis with your Stink Rat, then resolve combat."],
        "The free Marksman shot removes the small attack. Your Stink Rat absorbs the Mantis, while Lifeguard on the hero cancels the dragon's single unblocked hit. Shielding the Marksman instead leaves damage reaching the hero and fails the health requirement.",
        [ability(2, "shoot", 6), cast("LFGR", 0), block(3, 5), end()],
        objective={"type": "survive", "enemy_turns": 1, "protect": [2], "min_health": 3},
        refutations=[{"label": "Shield the precious Marksman instead of the hero", "commands": [cast("LFGR", 2)]},
                     {"label": "Spend the Marksman's shot on the Mantis", "commands": [ability(2, "shoot", 5)]}]))

    out.append(puzzle(game, "invitation_to_discard", "An Invitation to Discard", "Opponent-triggered summons", 2, 1,
        state(game, hero("Blue", ["MALS", "GROG", "OGKN"], mana=3, health=1),
            hero("Red", ["CLIG"], mana=0, channels=0, health=30), [unit("FREL", 2, 1), unit("GRTN", 3, 1)]),
        "Survive the enemy's next turn. Their only card is Call Lightning. Your two Ogres cost more ether than you have. The current edition's discard responses are the key.",
        ["You do not have to pay to summon an Ogre if the enemy makes you discard it.", "Call Lightning retaliates against forced discard by making the other hero discard three cards.", "Cast Malison on the enemy. Its discarded Lightning makes you discard both Ogres, summoning them for free. End the turn; the Ogre King can block Fire Elemental and Gray Ogre can block Great Treant."],
        "Malison discards the enemy's only card. Lightning's discard response now makes you discard both remaining cards; both Ogres enter the battlefield. They lose summoning sickness at the end of your turn, ready to defend. The King survives Fire Elemental's first strike; Gray Ogre handles the Treant. No random draw is involved, and every remaining card is discarded regardless of order.",
        [cast("MALS", 1), end(), attack(2, side=1), attack(3, side=1), end(side=1), block(5, 2), block(4, 3), end()],
        objective={"type": "survive", "enemy_turns": 1},
        refutations=[{"label": "Cast Malison on yourself", "commands": [cast("MALS", 0)]},
                     {"label": "Pass without triggering the enemy's response", "commands": [end()]}]))

    out.append(puzzle(game, "last_ether", "The Last Ether", "Regeneration reserve", 2, 1,
        state(game, hero("Red", ["SHSK", "SNOV", "WEAK"], mana=9, channels=1, health=4), hero("Green", [], mana=0, health=15), [
            unit("TNSA", 2), unit("AVMK", 3), unit("GRTN", 4, 1), unit("STRT", 5, 1)]),
        "Clear the enemy army this turn. Both of your creatures must remain alive. Supernova hurts every creature and both heroes, and spends one ether channel.",
        ["There are two ways for your creatures to survive the same blast, but they do not cost the same resources.", "The Treant regenerates automatically only if you leave enough ether. The Marksman needs a different protection.", "Put Shell Skin on the Marksman, then cast Supernova with X = 3. Leave the final ether for the Treant's regeneration."],
        "Shell Skin lets the Marksman endure 3 damage. Supernova costs 3 plus X and one channel: after the 2-cost enchantment, X=3 leaves exactly 1 ether for the Treant. It clears both enemies and leaves the hero at 1 health. More power kills the hero; shielding the Treant leaves the Marksman exposed.",
        [cast("SHSK", 3), cast("SNOV", power=3)],
        objective={"type": "clear", "protect": [2, 3]},
        refutations=[{"label": "Give Shell Skin to the regenerating Treant", "commands": [cast("SHSK", 2)]},
                     {"label": "Try the blast before protecting the Marksman", "commands": [cast("SNOV", power=3)]}]))

    out.append(puzzle(game, "exact_price", "The Exact Price", "Life as a resource", 2, 1,
        state(game, hero("Blue", ["CHNL", "CLIG", "BRGR"], mana=2, health=6),
            hero("Red", [], health=5, grave=["STRT", "DRAT"]), [unit("STRT", 2, 1)]),
        "Your opening ether can pay for Ether Trade and nothing else. A larger loan also heals the enemy. Find a precise lethal sequence this turn.",
        ["Work backwards from the final graveyard, not from the largest spell value you can afford.", "A third enemy corpse makes Burning Graves deal 9. You need 4 ether for the two remaining spells, while the enemy starts at 5 health.", "Cast Ether Trade with X = 4, kill the Stink Rat with Call Lightning, then cast Burning Graves."],
        "The 4-health loan produces exactly 4 ether and raises enemy health from 5 to 9. Lightning adds the third corpse for 1 ether, and Burning Graves spends the other 3 to deal exactly 9 damage. Borrowing 3 leaves too little ether; borrowing 5 heals the enemy above lethal; borrowing 6 kills you.",
        [cast("CHNL", power=4), cast("CLIG", 2), cast("BRGR")],
        refutations=[{"label": "Take the smaller loan", "commands": [cast("CHNL", power=3)]},
                     {"label": "Take the larger survivable loan", "commands": [cast("CHNL", power=5)]},
                     {"label": "Kill the rat before borrowing", "commands": [cast("CLIG", 2)]}]))

    out.append(puzzle(game, "second_attack", "Plan the Second Attack", "Recovery and counterplay", 3, 2,
        state(game, hero("Blue", ["MGHT", "SPWR", "SHSK", "WEAK"], mana=6, channels=0, health=4),
            hero("Red", [], mana=1, channels=1, health=9), [unit("GBIN", 2), unit("HOPR", 3),
                unit("KBSH", 4, 1), unit("GRTN", 5, 1)]),
        "Win in two turns. Your channels are empty, so any ether left over will be lost when your next turn begins. The Gibberling cannot recover normally, and the Shaman can shoot during defence.",
        ["The opening attack needs three different kinds of preparation: enough damage, a second attack, and a living attacker.", "A larger attack fails if the Shaman kills it; a protected attack fails if it rests forever. Commit the ether before your pool refills to zero.", "Put Might, Spirit of War, and Shell Skin on the Gibberling Instigator. Attack with it on both turns. Keep the Hopper back to block the Great Treant if it attacks."],
        "Might gives the unblockable Instigator 6 power, Shell Skin keeps it safe from the Shaman, and Spirit of War prevents it resting after its first attack despite its inability to recover. All 6 ether must be spent in advance: the next refill is zero. The Hopper is a reserve defender; losing it is preferable to losing the two-turn plan.",
        [cast("MGHT", 2), cast("SHSK", 2), cast("SPWR", 2), attack(2), end(),
         ability(4, "sting", 2, side=1), end(side=1),
         attack(5, side=1), end(side=1), block(3, 5), end(), attack(2), end(), end(side=1)],
        refutations=[{"label": "Give the damage bonus to the Hopper", "commands": [cast("MGHT", 3)]},
                     {"label": "Spend protection ether weakening the Treant", "commands": [cast("WEAK", 5)]},
                     {"label": "Attack before investing in the second turn", "commands": [attack(2), end()]}]))

    return out
