"""Hand-authored Etherlords I tactical studies.

Each study isolates a different rules interaction. Its reference line is a
replay of ordinary combat commands, not a special puzzle-script solution.
"""
from puzzle_authoring import hero, unit, state, puzzle, enchant, cast, ability, attack, block, end


def puzzles():
    game = "el1"
    out = []

    out.append(puzzle(
        game, "empty_battlements", "Empty Battlements", "Evasion and enemy counterplay", 1, 1,
        state(game,
              hero("Blue", ["DELS", "MGHT", "ENFL"], mana=3),
              hero("Blue", [], health=2),
              [unit("AVAS", 2), unit("WLFC", 3, 1), unit("BUDG", 4, 1)]),
        "Win this turn. The Assassin can evade the dragon as a blocker, but the dragon's breath is still a threat.",
        ["The wall is a legal blocker; the dragon threatens an ability during defence.",
         "You need to remove one obstacle and rest the other, using only three ether.",
         "Enfeeble the Blue Dragon, invert the zero-power Wall of Force with Delusion, then attack with the Assassin."],
        "Enfeeble the Blue Dragon so it cannot use its readying-dependent breath ability during "
        "defence. Cast Delusion on the Wall of Force: swapping its 0/12 stats leaves it at 12/0, so "
        "it dies. The Dragon is not a Wall and cannot block the Aviak Assassin. Its two damage is "
        "lethal. Tapping only the wall looks cheaper, but leaves the Dragon able to kill the Assassin "
        "with its breath. The two preparation spells may be cast in either order.",
        [cast("ENFL", 4), cast("DELS", 3), attack(2), end(), end(side=1)],
        refutations=[
            {"label": "Spend the budget increasing the Assassin's damage", "commands": [cast("MGHT", 2)]},
            {"label": "Rest only the wall and leave the Dragon ready", "commands": [cast("ENFL", 3)]},
            {"label": "Clear the wall and attack without disabling the breath", "commands": [cast("DELS", 3), attack(2), end()]},
        ],
    ))

    out.append(puzzle(
        game, "count_the_ashes", "Count the Ashes", "Graveyard arithmetic", 1, 1,
        state(game,
              hero("Red", ["BRGR", "ZAPP"], mana=4, health=3, grave=["STRT", "TIWR"]),
              hero("Red", [], health=4, grave=["STRT", "TIWR"]),
              [unit("DRAT", 2), unit("RKWL", 3, 1)]),
        "Win this turn and remain alive. Both graveyards contain two creatures.",
        ["A spell that burns both graveyards is dangerous at three health.",
         "The Disease Rat can remove a card from either hero's graveyard.",
         "Gnaw one creature from your own graveyard, then cast Burning Graves."],
        "Use the Disease Rat's Ghoul ability on your own graveyard for one ether. Burning Graves then "
        "deals two damage to you and four to the enemy. You survive on one health. Burning first is a draw; "
        "clearing the enemy's graveyard saves the wrong hero.",
        [ability(2, "gnaw", 0, choice=0), cast("BRGR")],
        refutations=[
            {"label": "Burn before making the graveyards asymmetric", "commands": [cast("BRGR")]},
            {"label": "Gnaw the enemy's graveyard", "commands": [ability(2, "gnaw", 1, choice=0)]},
        ],
    ))

    out.append(puzzle(
        game, "dangerous_promotion", "A Dangerous Promotion", "Target thresholds", 1, 1,
        state(game,
              hero("Black", ["TWEN", "SPWR", "ZAPP"], mana=3),
              hero("Green", [], health=20),
              [unit("WNHR", 2), unit("TIWR", 3, 1), unit("GROG", 4, 1)]),
        "Clear the enemy army this turn and keep the Huntress alive. Her shot only accepts creatures with at least four power.",
        ["A harmful spell is not always the best way to remove an enemy.",
         "One enemy is too weak for the Huntress to target. You can change that.",
         "Enhance the enemy Tick, shoot it, ready the Huntress with Spirit of War, then shoot the Ogre."],
        "Twisted Enhancement raises the enemy Tick Warrior from two to four power, making it a legal "
        "Huntress target. Shoot it, use Spirit of War to ready the Huntress, and shoot the Gray Ogre. "
        "Shooting the Ogre first is also valid if you keep the readying spell and the Tick's enhancement. "
        "The puzzle tests the two-target plan, not an arbitrary order between independent preparations.",
        [cast("TWEN", 3), ability(2, "hunt", 3), cast("SPWR", 2), ability(2, "hunt", 4)],
        objective={"type": "clear", "protect": [2]},
        refutations=[{"label": "Use the only enhancement on your own Huntress", "commands": [cast("TWEN", 2)]}],
    ))

    out.append(puzzle(
        game, "one_open_lane", "One Open Lane", "Defensive assignment", 2, 1,
        state(game,
              hero("Black", ["ENAL", "TWEN"], mana=3, health=3),
              hero("Red", [], health=20),
              [unit("RKWL", 2, resting=True), unit("WLFC", 3, resting=True), unit("MCWO", 4),
               unit("SHWL", 5, 1), unit("AVAS", 6, 1), unit("TIWR", 7, 1)],
              phase=1, attacker=1, attacks=[5, 6, 7]),
        "Survive this enemy attack and preserve your Mech Worm. The two walls are resting; one attacker must get through.",
        ["Both evasive attackers require Walls, and one of them also flies.",
         "Your ground Wall must take the Shadow Wolf. The flying Wall is needed elsewhere.",
         "Cast Energize All, block the Wolf with Rock Wall and the Assassin with Wall of Force. Let the Tick hit your hero."],
        "Energize All readies both walls during defence. Rock Wall blocks Shadow Wolf, while Wall of "
        "Force blocks the flying Aviak Assassin. Leave the Tick Warrior unblocked: two damage leaves one "
        "health. Blocking the Tick with the protected Mech Worm would kill it, and spending ether on "
        "another spell loses the only way to ready both essential blockers.",
        [cast("ENAL"), block(2, 5), block(3, 6), end()],
        objective={"type": "survive", "enemy_turns": 1, "protect": [4]},
        refutations=[
            {"label": "Put the flying wall in the ground lane", "commands": [cast("ENAL"), block(3, 5), end()]},
            {"label": "Save all hero damage by sacrificing the protected Worm", "commands": [cast("ENAL"), block(2, 5), block(3, 6), block(4, 7), end()]},
        ],
    ))

    out.append(puzzle(
        game, "two_locked_gates", "Two Locked Gates", "Reusing an active creature", 2, 1,
        state(game,
              hero("Blue", ["SPWR", "SPWR", "MGHT"], mana=2),
              hero("Blue", [], health=7),
              [unit("GRDG", 2), unit("AVAS", 3), unit("WLFC", 4, 1), unit("WLFC", 5, 1)]),
        "Win this turn. Two flying walls stand between the Green Dragon and a seven-health hero.",
        ["The Dragon has to work more than once, and it still needs to attack.",
         "Spirit of War readies its target immediately; merely having Restless does not stop an ability from resting it.",
         "Break a wall, ready the Dragon, break the other wall, ready it again, and attack."],
        "Use Wall Breaker on either Wall of Force, cast Spirit of War on the Dragon, break the second "
        "wall, then use the second Spirit of War. Attack with the now-ready Dragon for seven. Ready too "
        "early and the last ability leaves it resting. Removing just one wall lets the defender stop "
        "the Dragon and survive any Assassin damage.",
        [ability(2, "wall_break", 4), cast("SPWR", 2), ability(2, "wall_break", 5), cast("SPWR", 2), attack(2), end(), end(side=1)],
        refutations=[
            {"label": "Spend one readying effect before the first ability", "commands": [cast("SPWR", 2)]},
            {"label": "Ready the Assassin instead of the Dragon", "commands": [cast("SPWR", 3)]},
        ],
    ))

    out.append(puzzle(
        game, "borrowed_life", "Borrowed Life", "Sacrifice and resource conversion", 2, 1,
        state(game,
              hero("Green", ["CANV", "BRGR", "RIFT"], mana=1, health=1, enchantments=[enchant("SACR", id=1)]),
              hero("Red", [], health=8, grave=["STRT", "TIWR"]),
              [unit("CAFG", 2), unit("MTPT", 3), unit("RKWL", 4, 1)]),
        "Win this turn. You have one ether and one health. Dissolution is already active, but choosing its sacrifice determines what remains possible.",
        ["You need ether, damage, and enough health to survive your own final spell.",
         "The two creatures have the same toughness, but only one can supply the damage you need later.",
         "Dissolve the Fingus, use Force of Sacrifice on the Patriarch, then burn the graveyards."],
        "Dissolve the 0/6 Carnivorous Fingus: the first game's Dissolution adds power plus toughness "
        "minus one, taking ether from one to six. Force of Sacrifice on the 6/6 Mantis Patriarch costs "
        "two, heals you from one to seven, and damages the enemy from eight to two. Burning Graves "
        "then deals four to each hero. Sacrificing the Patriarch for ether instead removes the damage "
        "source. Casting the graveyard burn before healing kills you.",
        [ability(0, "sacrifice:1", 2), cast("CANV", 3), cast("BRGR")],
        refutations=[
            {"label": "Dissolve the largest attacker for more ether", "commands": [ability(0, "sacrifice:1", 3)]},
            {"label": "Burn the graves before gaining health", "commands": [ability(0, "sacrifice:1", 2), cast("BRGR")]},
        ],
    ))

    out.append(puzzle(
        game, "late_arrival", "The Late Arrival", "Grave selection and summoning sickness", 2, 1,
        state(game,
              hero("Black", ["BDEX", "BLSS", "ALST"], mana=7, health=10, grave=["GROG", "HOPR"]),
              hero("Green", [], health=6),
              [unit("MCWO", 2), unit("TIWR", 3, 1)]),
        "Win this turn. The graveyard offers a powerful Ogre and a smaller Hopper; there is no time to wait for a new creature to recover.",
        ["Printed power is not the only thing that matters when a creature returns this turn.",
         "The Hopper ignores summoning sickness. Its final attack must trample through the Tick.",
         "Exchange the Worm for the Hopper, Bless the Hopper, give it Alpha Strike, and attack."],
        "Body Exchange sacrifices the Mech Worm and summons the Hopper from grave slot one. Unlike "
        "the larger Ogre, the Hopper can attack immediately. Bless adds four power; Alpha Strike adds "
        "its printed two and grants First Strike plus Trample. Its eight power kills the 2/2 Tick and "
        "tramples for six. Buffing the original Worm reaches only six power, leaving four after the block.",
        [cast("BDEX", 2, grave=1), cast("BLSS", 4), cast("ALST", 4), attack(4), end(), block(3, 4, side=1), end(side=1)],
        refutations=[
            {"label": "Revive the stronger Ogre", "commands": [cast("BDEX", 2, grave=0)]},
            {"label": "Spend Bless on the creature you begin with", "commands": [cast("BLSS", 2)]},
        ],
    ))

    out.append(puzzle(
        game, "fall_of_the_crown", "Fall of the Crown", "Shared auras and cascading deaths", 3, 1,
        state(game,
              hero("Green", ["BLSS", "CANV", "TWEN"], mana=4, health=5),
              hero("Green", [], health=20),
              [unit("TIQN", 2), unit("TIWR", 3, damage=2), unit("TIWK", 4, 1, damage=3),
               unit("TIWR", 5, 1, damage=3), unit("TIWR", 6, 1, damage=3)]),
        "Clear the enemy army this turn and preserve your injured Tick Warrior. Tick auras strengthen both sides, and existing wounds remain.",
        ["The enemy's apparent health comes from two different aura sources.",
         "Removing your Queen will start a chain reaction, including a dangerous change to your own injured Tick.",
         "Bless your injured Tick first, then sacrifice your Queen with Force of Sacrifice."],
        "Bless the friendly Tick Warrior before sacrificing the Tick Queen. Losing the Queen's +2 "
        "toughness makes the injured enemy Worker die. That removes its global +1/+1 aura, collapsing "
        "both injured enemy Warriors. Your own Warrior would also die at its unmodified two toughness, "
        "so it must be protected before the cascade starts. Twisted Enhancement on the survivor is a "
        "valid alternate protection; the important dependency is protection before removing the Queen.",
        [cast("BLSS", 3), cast("CANV", 2)],
        objective={"type": "clear", "protect": [3]},
        refutations=[
            {"label": "Start the cascade before protecting your injured Tick", "commands": [cast("CANV", 2)]},
            {"label": "Protect the aura source instead of the survivor", "commands": [cast("BLSS", 2)]},
        ],
    ))

    out.append(puzzle(
        game, "keep_the_spark", "Keep the Spark", "Two-turn maintenance and defence", 3, 2,
        state(game,
              hero("Black", ["ZAPP", "CLFR", "ENFL"], mana=3, health=3),
              hero("Red", [], health=8),
              [unit("BGVL", 2), unit("RKWL", 3), unit("RKWL", 4, 1), unit("GROG", 5, 1)]),
        "Win within two turns and preserve your Rock Wall. The Big Velos is your only lasting damage source, if you can keep it alive.",
        ["A creature may need to receive damage in order to survive.",
         "The Velos must bypass the enemy wall twice. Your Rock Wall can absorb the Ogre's counterattack.",
         "Zap your own Velos, give it Cloak of Fear, attack, block the Ogre with Rock Wall, and attack again next turn."],
        "Zap your own Big Velos, leaving it alive and marked as having taken damage. Cloak of Fear "
        "lets its four power bypass all blockers. Its damage mark keeps it from destroying itself at "
        "the first turn end. Block a Gray Ogre counterattack with Rock Wall, then attack again for the "
        "remaining four. The opponent can also decline to attack; that does not stop your second hit. "
        "Zapping the enemy hero instead improves immediate damage but loses the Velos at turn end.",
        [cast("ZAPP", 2), cast("CLFR", 2), attack(2), end(), end(side=1),
         attack(5, side=1), end(side=1), block(3, 5), end(), attack(2), end(), end(side=1)],
        objective={"type": "win", "protect": [3]},
        refutations=[
            {"label": "Use the direct damage on the enemy hero", "commands": [cast("ZAPP", 1)]},
            {"label": "Spend ether resting the Ogre instead of protecting the Velos", "commands": [cast("ENFL", 5)]},
        ],
    ))

    out.append(puzzle(
        game, "balanced_destruction", "Balanced Destruction", "Two-sided damage accounting", 2, 1,
        state(game,
              hero("Red", ["BLSS", "WEAK", "ANHL", "ZAPP"], mana=8, health=5),
              hero("Red", [], health=10),
              [unit("MCWY", 2), unit("STRT", 3), unit("GROG", 4, 1), unit("TIWR", 5, 1)]),
        "Win this turn. Annihilation can reach the enemy hero, but it measures both armies before destroying them.",
        ["Count your army's total power and the enemy army's total power separately.",
         "You need at least ten power on your side and less than five on theirs.",
         "Bless one of your creatures, Weaken the enemy Ogre, then cast Annihilation."],
        "Your army begins with six power and the enemy with eight. Bless adds four to your total. "
        "Weaken on the Gray Ogre removes four enemy power, bringing its army to four. Annihilation "
        "therefore deals ten to the enemy and four to you, leaving one health. The two preparations "
        "may be done in either order. Buffing the enemy or weakening your own army solves the wrong "
        "half of the equation; casting Annihilation before both preparations is fatal or insufficient.",
        [cast("BLSS", 2), cast("WEAK", 4), cast("ANHL")],
        refutations=[
            {"label": "Annihilate immediately", "commands": [cast("ANHL")]},
            {"label": "Prepare only your own damage total", "commands": [cast("BLSS", 2), cast("ANHL")]},
            {"label": "Weaken the smaller enemy", "commands": [cast("WEAK", 5)]},
        ],
    ))

    out.append(puzzle(
        game, "cracked_mirror", "The Cracked Mirror", "Inversion with retained damage", 3, 1,
        state(game,
              hero("Black", ["TWEN", "MGHT", "DELS", "SHSK"], mana=7, health=4),
              hero("Blue", [], health=8),
              [unit("CAFG", 2, damage=2), unit("SPFG", 3), unit("WLFC", 4, 1)]),
        "Win this turn. The Carnivorous Fingus has already taken two damage; its spores deal its current power to their target.",
        ["The displayed toughness after an inversion still has to survive the damage already on the creature.",
         "Shell Skin promises a larger attack value, but it does not create enough toughness after the swap.",
         "Give the wounded Fingus Might and Twisted Enhancement, then Delusion. Its eight-power spores finish the hero."],
        "Might plus Twisted Enhancement turns the Fingus into 5/8. Delusion then makes it 8/5, safely "
        "above its two existing damage. Sacrifice it with Stinging Spores for eight damage. A Shell "
        "Skin line can produce a larger nominal power, but if only Twisted Enhancement supplied its "
        "pre-swap power, the resulting two toughness is already lethal. The small Spitting Fingus "
        "cannot compensate for a six-damage shortcut.",
        [cast("MGHT", 2), cast("TWEN", 2), cast("DELS", 2), ability(2, "spores", 1)],
        refutations=[
            {"label": "Chase the largest nominal post-swap power", "commands": [cast("SHSK", 2), cast("TWEN", 2), cast("DELS", 2)]},
            {"label": "Invert before providing a safe toughness", "commands": [cast("DELS", 2)]},
            {"label": "Spend Twisted Enhancement on the smaller Fingus", "commands": [cast("TWEN", 3)]},
        ],
    ))

    return out

