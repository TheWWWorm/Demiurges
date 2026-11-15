"""A full army, a wounded veteran, and the distinction between casting and creation."""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability


def puzzles():
    game = "el1"
    return [puzzle(
        game, "room_for_two", "Room for Two", "Army capacity, spell income and a reflected finish", 3, 1,
        state(game,
              hero("Blue", ["BEWK", "BRAB", "DRAT", "GRHE"], template="BlueWingedFemale1", level=20, maximum=67, health=1, mana=3,
                   enchantments=[enchant("MNTX", id=1), enchant("MNTX", id=2)]),
              hero("Red", [], template="RedMale4", level=5, maximum=22, health=1, enchantments=[enchant("ETCH", id=3)]),
              [unit("CCLP", 2), unit("SPFG", 3), unit("MOBE", 4, granted=["FS"]), unit("FMFI", 5, resting=True),
               unit("LMWK", 6, resting=True), unit("DMRT", 7, resting=True), unit("SWHL", 8, resting=True),
               unit("WTEL", 9, resting=True), unit("GBAT", 10, resting=True)]),
        "Win this turn with at least 64 hero health. Your level-twenty veteran has a maximum of 67 but only one health remains. Two Ether Harvest enchantments are active, and your nine-creature army has one free slot. The enemy mirrors damage through Ethereal Resonance.",
        ["Both heroes are at one health, so an immediate attack or shot loses the required healthy finish. You first need nine ether for Greater Healing.",
         "Each actual creature-card cast triggers both Ether Harvest enchantments. Mother Bee's brood is not a cast. Two one-cost summons produce the required income, but you need room for both.",
         "Sacrifice the Spitting Fingus into a sturdy friendly creature, cast Bee Worker and Bronze Abomination, and use Greater Healing. Then shoot the enemy with the Cyclops. The mirrored three damage leaves you at 64."],
        "The Fingus opens a second army slot without spending ether. Each one-cost summon spends one and receives four from the two Ether Harvest enchantments, so the pool rises from three to six to nine. Greater Healing restores the veteran's maximum of 67. The Cyclops's three-point shot also hurts you through Resonance, leaving 64 when the enemy dies. Mother Bee creates a creature without casting its card, so it gives no Harvest income and consumes a needed slot. Starting with the two-cost Disease Rat misses the budget. An alternative can sacrifice the newly summoned Worker with the Cyclops and save the Fingus for the final one-point hit; that healthy finish is also accepted.",
        [ability(3, "spores", 2), cast("BEWK"), cast("BRAB"), cast("GRHE"), ability(2, "sting", 1)],
        objective={"type": "win", "finish_health": 64},
        refutations=[
            {"label": "Use the Mother's brood as a cheap source of Harvest income", "commands": [ability(4, "brood")]},
            {"label": "Start with the more substantial Disease Rat", "commands": [cast("DRAT")]},
            {"label": "Take the apparent immediate kill with the Fingus", "commands": [ability(3, "spores", 1)]},
        ],
        alternative_solutions=[{"label": "Recycle the new Worker and retain the Fingus finisher", "commands": [cast("BEWK"), ability(2, "sting", 11), cast("BRAB"), cast("GRHE"), ability(3, "spores", 1)]}],
        hero_names=["Kinet Archmage", "Chaot Adept"], hero_names_ru=["Архимаг Кинетов", "Адепт Хаотов"],
        title_ru="Место для двоих", category_ru="Предел армии, доход от призыва и отражённый удар",
        briefing_ru="Победите за этот ход, сохранив хотя бы 64 здоровья героя. Максимум вашего ветерана двадцатого уровня — 67, но осталось лишь одно здоровье. Действуют два Эфирных Урожая, а в армии из девяти существ одно свободное место. Враг отражает урон Эфирным Резонансом.",
        hints_ru=["У обоих героев по одному здоровью. Немедленная атака или выстрел нарушают условие здорового завершения. Сначала нужны девять эфира для Исцеления.",
                  "Оба Урожая срабатывают при розыгрыше карты существа. Потомство Матки — не розыгрыш карты. Два призыва ценой по одному дадут нужный доход, но обоим требуется место.",
                  "Пожертвуйте Плюющимся фингусом, выбрав крепкого союзника. Призовите Рабочую пчелу и Бронзовое исчадие, затем примените Исцеление. Выстрел Циклопа убьёт врага, а отражённые три урона оставят вам 64 здоровья."],
        explanation_ru="Фингус освобождает второе место без затрат эфира. Каждый призыв ценой один тратит единицу и получает четыре от двух Урожаев: запас растёт с трёх до шести, затем до девяти. Исцеление возвращает ветерану максимум в 67 здоровья. Выстрел Циклопа наносит три урона и вам через Резонанс: при смерти врага остаётся 64. Матка создаёт существо без розыгрыша карты, поэтому не даёт дохода и занимает нужное место. Начало с более дорогой Заразной крысы нарушает расчёт эфира. Допустим и другой путь: уничтожить новую Рабочую пчелу Циклопом, а Фингуса сохранить для последнего удара на единицу.",
    )]
