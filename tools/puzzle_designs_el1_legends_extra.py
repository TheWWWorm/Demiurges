"""Additional Etherlords I hero studies: capacities and creature-specific rules.

Hero levels and appearances belong to the real snapshot. Maximum health is an
explicit scenario value; neither role labels nor puzzle difficulty change it.
"""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end


def puzzles():
    game = "el1"
    out = []

    out.append(puzzle(
        game, "crowded_return", "The Crowded Return", "Mass return, hand counts and health capacity", 2, 1,
        state(game,
              hero("Green", ["GRHE", "GRUN", "MDBL", "UNSM", "BRMZ", "STAB"], mana=14,
                   health=1, maximum=22, level=5, template="GreenFemale2"),
              hero("Blue", ["LMWA", "IRAB", "STAB", "WTEL", "WLDG"], mana=0,
                   health=6, maximum=67, level=20, template="BlueWingedFemale1"),
              [unit("BRAB", 2, resting=True), unit("SLWL", 3, resting=True), unit("WLBZ", 4, resting=True),
               unit("STAB", 5, 1), unit("IRAB", 6, 1), unit("LMWA", 7, 1), unit("STMZ", 8, 1)]),
        "Win this turn with at least 20 health. Your wounded hero's maximum is 22; the opponent's is 67. "
        "Your three creatures are exhausted. Read both hands and the two steel creatures' different protections before spending fourteen ether.",
        ["The battlefield and the hands are two different ways to count the same creatures. Count your own cards as carefully as the enemy's.",
         "Greater Unsummoning can return the Steel Abomination without targeting it, but the Steel Mechozaurus is unaffected. Mind Blast is removed from your hand before it counts the remaining cards.",
         "Cast Greater Healing before the lethal spell. Greater Unsummoning returns three creatures to each hand; then Mind Blast counts six cards in your hand and eight in the enemy hand, dealing two and six damage."],
        "Greater Healing restores your maximum of 22. Greater Unsummoning returns all three of your creatures "
        "and three enemy creatures: protection from targeting does not stop this global spell, while the Steel Mechozaurus's "
        "complete spell immunity does. After Mind Blast leaves your hand, you hold six cards and the enemy holds eight. The resulting two and six damage "
        "kill the opponent and leave you at exactly 20. Healing and the mass return may trade order, but both must precede "
        "Mind Blast. Spending even one ether on a separate Unsummon breaks the fourteen-ether budget; healing after lethal "
        "would be too late to meet the finishing condition. Waiting for the enemy's parasitic upkeep deals only five, leaving it alive.",
        [cast("GRHE"), cast("GRUN"), cast("MDBL")],
        objective={"type": "win", "finish_health": 20},
        refutations=[
            {"label": "Spend one ether separately returning the Iron Abomination", "commands": [cast("UNSM", 6)]},
            {"label": "Heal, then blast before returning the armies", "commands": [cast("GRHE"), cast("MDBL")]},
            {"label": "Return the armies and blast before restoring health", "commands": [cast("GRUN"), cast("MDBL")]},
        ],
        hero_names=["Vital healer", "Kinet matriarch"],
        hero_names_ru=["Целительница виталов", "Наставница кинетов"],
        title_ru="Переполненные руки", category_ru="Массовое возвращение, карты и запас здоровья",
        briefing_ru="Победите за этот ход, сохранив хотя бы 20 здоровья. Максимум вашего раненого героя — 22, "
        "противника — 67. Трое ваших существ устали. Изучите обе руки и разную защиту двух стальных существ, прежде чем тратить четырнадцать эфира.",
        hints_ru=["Поле и рука — два способа посчитать одних и тех же существ. Считайте свои карты так же внимательно, как вражеские.",
                  "Великое Развоплощение возвращает Стальное исчадие, не выбирая его целью, но не действует на Стального мехозавра. Удар по Разуму покидает вашу руку до подсчёта карт.",
                  "Исцеление нужно до смертельного заклинания. Великое Развоплощение возвращает по три существа в каждую руку; затем Удар по Разуму считает шесть карт у вас и восемь у врага, нанося два и шесть урона."],
        explanation_ru="Исцеление восстанавливает заданный максимум — 22 здоровья. Великое Развоплощение возвращает "
        "всех троих ваших существ и троих вражеских: защита от выбора целью не мешает общему заклинанию, "
        "а полная невосприимчивость Стального мехозавра мешает. Когда Удар по Разуму покидает руку, "
        "у вас остаётся шесть карт, а у врага — восемь. Два и шесть урона убивают противника и оставляют вам ровно 20 здоровья. "
        "Исцеление и массовое возвращение можно переставить, но оба нужны до Удара по Разуму. Даже отдельное "
        "Развоплощение за один эфир нарушает бюджет. Исцелиться после смертельного удара уже нельзя: "
        "условие конечного здоровья проверяется сразу. Паразит в конце хода наносит врагу лишь пять урона и оставляет его в живых.",
    ))


    return out
