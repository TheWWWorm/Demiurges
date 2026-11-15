"""Hero profiles and underused creature families for Etherlords I.

Profiles declare deterministic levels, turn counts and skills. Named templates
are documented game appearances; their scenario skills are not biographies.
"""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end


def puzzles():
    game = "el1"
    out = []
    out.append(puzzle(
        game, "empty_handed_standard", "The Empty-Handed Standard", "Kobold rally, attack partners and a deadline", 3, 1,
        state(game,
              hero("Red", [], level=16, turns=14, maximum=55, health=4),
              hero("Blue", ["GRHE"], level=2, turns=13, maximum=13, health=4, mana=9, channels=9),
              [unit("KBEL", 2), unit("KBSH", 3), unit("KBGD", 4, resting=True),
               unit("KBGD", 5, resting=True), unit("KBGD", 6, resting=True), unit("WLAR", 7, 1)]),
        "Win before the rival can use Greater Healing. On its next turn, the level-two rival takes one disturbance damage; your level-sixteen hero is still outside that clock. Three Guards are resting.",
        ["The Elder can restore several Kobolds, but cannot restore itself. A Guard still needs an attacking partner.",
         "One Shaman shot matters. Its second action must contribute an attack partner, even though it has zero power.",
         "Shoot the hero with the Shaman, rally with the Elder, then attack with the Shaman and all three Guards. The Wall can stop only one Guard; the next disturbance supplies the final point."],
        "The Shaman deals one damage before the Elder readies it and the three Guards. The resting Elder cannot lead the attack, so the zero-power Shaman must do so. Two Guards get past the single Wall and leave the rival at one health. Its level-two disturbance arrives at the start of turn fourteen, before Greater Healing is available. A second Shaman shot uses up the only ready non-Guard partner. Rallying before the first shot loses that extra point.",
        [ability(3, "sting", 1), ability(2, "rally"), attack(3), attack(4), attack(5), attack(6), end(), block(7, 4, side=1), end(side=1)],
        refutations=[
            {"label": "Rally before taking the Shaman's first shot", "commands": [ability(2, "rally")]},
            {"label": "Use the restored Shaman for a second shot", "commands": [ability(3, "sting", 1), ability(2, "rally"), ability(3, "sting", 1)]},
            {"label": "Commit the Elder instead of rallying the Guards", "commands": [attack(2), end()]},
        ],
        hero_names=["Chaot Marshal", "Kinet Novice"], hero_names_ru=["Маршал Хаотов", "Ученик Кинетов"],
        title_ru="Знамя без оружия", category_ru="Сбор кобольдов, напарник и предельный срок",
        briefing_ru="Победите до того, как соперник применит Исцеление. В начале следующего хода герой второго уровня получит единицу урона от эфирного возмущения; вашему герою шестнадцатого уровня оно пока не грозит. Трое Стражей отдыхают.",
        hints_ru=["Старейшина поднимает нескольких кобольдов, но не самого себя. Стражам всё равно нужен атакующий напарник.",
                  "Нужен один выстрел Шамана. Вторым действием он должен стать напарником для атаки, несмотря на нулевую силу.",
                  "Выстрелите Шаманом в героя, соберите кобольдов Старейшиной и атакуйте Шаманом со всеми тремя Стражами. Стена остановит лишь одного; последний урон нанесёт возмущение."],
        explanation_ru="Шаман наносит единицу урона, затем Старейшина поднимает его и трёх Стражей. Сам Старейшина уже отдыхает, поэтому атаку должен возглавить Шаман с нулевой силой. Два Стража проходят мимо единственной стены, оставляя врагу одно здоровье. Герой второго уровня получает урон от возмущения в начале четырнадцатого хода — раньше, чем сможет исцелиться. Второй выстрел Шамана тратит единственного готового напарника, а преждевременный сбор теряет первый выстрел.",
    ))

    out.append(puzzle(
        game, "two_venoms_before_dawn", "Two Venoms Before Dawn", "Poison, a forest threshold and a defensive reserve", 3, 1,
        state(game,
              hero("Blue", ["LSST", "FOGG"], template="Diamanda", level=8, turns=20, maximum=31, health=2, mana=6),
              hero("Green", [], template="White Lord I", level=20, turns=19, maximum=67, health=5, skills={"REGN": 2}, enchantments=[enchant("DNFR", id=1)]),
              [unit("TRSN", 2), unit("SWSN", 3), unit("MTPT", 4), unit("EREL", 5, 1), unit("AREL", 6, 1)]),
        "Win before your next turn begins: level-eight disturbance will deal two damage. The rival regenerates one health at its turn start and shelters behind Dense Forest. The two Elementals can attack back.",
        ["Direct combat damage is not the entire attack. Each Snake that reaches the hero leaves a separate venom.",
         "The weaker Snake cannot attack through Dense Forest yet. The Patriarch can rest both Elementals together, but that does not prevent their next-turn retaliation.",
         "Give Lesser Strength to the Tree Snake, tap the Elemental race, and attack with both Snakes. Reserve two ether for Fog against the counterattack. Two venoms overcome the rival's one-point regeneration at its turn end."],
        "Lesser Strength raises the Tree Snake above Dense Forest's one-power threshold. The Patriarch spends two ether to rest both Elementals, so the two Snakes deal four damage and attach two venoms. The rival starts its turn at one health, regenerates to two, and readies its Elementals. Fog stops that retaliation; the two end-of-turn venoms kill the rival before your own two-point disturbance. Buffing the stronger Snake leaves the Tree Snake trapped, and spending Fog before establishing the attack loses the required venom clock.",
        [cast("LSST", 2), ability(4, "tap_race", 5), attack(2), attack(3), end(), end(side=1),
         attack(5, side=1), attack(6, side=1), end(side=1), cast("FOGG"), end()],
        refutations=[
            {"label": "Improve the stronger Snake instead", "commands": [cast("LSST", 3)]},
            {"label": "Cover the battlefield with Fog before attacking", "commands": [cast("FOGG")]},
            {"label": "Commit the Patriarch to combat instead of opening both lanes", "commands": [cast("LSST", 2), attack(2), attack(3), attack(4), end()]},
        ],
        hero_names=["Diamanda", "The White Lord"], hero_names_ru=["Диаманда", "Белый Лорд"],
        title_ru="Два яда до рассвета", category_ru="Яд, предел леса и запас на защиту",
        briefing_ru="Победите до начала своего следующего хода: эфирное возмущение восьмого уровня нанесёт два урона. Соперник восстанавливает единицу здоровья в начале хода и укрыт Густым Лесом. Оба Элементаля способны контратаковать.",
        hints_ru=["Урон в бою — лишь часть атаки. Каждая Змея, добравшаяся до героя, оставляет отдельный яд.",
                  "Слабая Змея пока не может пройти через Густой Лес. Патриарх укладывает обоих Элементалей одной способностью, но на следующем ходу они поднимутся.",
                  "Дайте Боевой Дух Древесной змее, усыпите расу Элементалей и атакуйте обеими Змеями. Сохраните два эфира для Тумана при контратаке. Два яда в конце хода преодолеют единицу регенерации."],
        explanation_ru="Боевой Дух выводит Древесную змею выше предела Густого Леса — одной единицы силы. Патриарх за два эфира укладывает обоих Элементалей. Две Змеи наносят четыре урона и оставляют два яда. Враг начинает ход с одним здоровьем, восстанавливает его до двух и поднимает Элементалей. Туман останавливает ответную атаку; два яда убивают героя в конце его хода, раньше вашего возмущения на два урона. Усиление второй Змеи оставляет первую в лесу, а ранний Туман мешает нужной атаке.",
    ))

    out.append(puzzle(
        game, "enemy_grave_recruit", "Recruit from the Enemy Grave", "A free resurrection and two defensive jobs", 3, 2,
        state(game,
              hero("Black", ["ENAL", "SHSK", "LSST"], template='Omega-800D "Diamanda"', level=12, turns=24, maximum=43, health=3, mana=6, skills={"REGN": 2}, enchantments=[enchant("FURY", id=1)]),
              hero("Red", [], level=20, turns=23, maximum=67, health=30, grave=["MAHO", "GBAT", "MCWO"]),
              [unit("MLFI", 2), unit("STMC", 3, 1, granted=["Berserk"]), unit("GBAT", 4, 1, granted=["Berserk"], enchantments=[enchant("SHSK", id=2)])]),
        "Clear the enemy army within two turns, keeping the Fighter and another creature, with at least two hero health. Fury forces an attack; the Giant Bat has Shell Skin. You have six ether. Your next disturbance deals two before regeneration heals one.",
        ["The Fighter's necromancy can use either graveyard. The recruit's printed cost matters, and its combat abilities matter more than its power.",
         "The Fighter must be ready again for the ground attacker. Poison resolves after the flying victim has struck back, so the Hornet needs protection as well.",
         "Raise the Magic Hornet and give it Shell Skin. Reserve three ether for Energize All. Block Steel Mechos with the Fighter and the armored Giant Bat with the Hornet."],
        "The Fighter can raise the four-cost Hornet for no ether, but rests while doing it. Shell Skin lets the Hornet survive the Bat's five damage. After the turn change the recruit is no longer sick, and Fury forces both enemies forward. Energize All restores the Fighter, whose eight first-strike damage kills Steel Mechos before it hits back. The Hornet survives the Bat's return strike and its poison then finishes the eight-toughness flyer. Your level-twelve disturbance removes two health and expert Regeneration restores one, finishing at two. Another valid route lets the Hornet trade, then raises it again on your second turn to restore the required army size. The larger Giant Bat recruit cannot kill the armored enemy in one combat, and the Mech Worm cannot cover the flying lane.",
        [ability(2, "necromancy", 1, choice=0), cast("SHSK", 5), end(), end(side=1),
         cast("ENAL"), block(2, 3), block(5, 4), end()],
        objective={"type": "clear", "protect": [2], "min_allies": 2, "finish_health": 2},
        refutations=[
            {"label": "Raise the more powerful Giant Bat", "commands": [ability(2, "necromancy", 1, choice=1)]},
            {"label": "Raise the hasty Mech Worm", "commands": [ability(2, "necromancy", 1, choice=2)]},
            {"label": "Spend Energize All before using necromancy", "commands": [cast("ENAL")]},
        ],
        alternative_solutions=[{"label": "Trade the Hornet, then resurrect it again", "commands": [ability(2, "necromancy", 1, choice=0), end(), end(side=1), cast("ENAL"), block(2, 3), block(5, 4), end(), ability(2, "necromancy", 0, choice=0)]}],
        hero_names=["Omega-800D Diamanda", "Chaot Veteran"], hero_names_ru=["Омега-800D Диаманда", "Ветеран Хаотов"],
        title_ru="Новобранец из вражеской могилы", category_ru="Бесплатное воскрешение и два рубежа защиты",
        briefing_ru="Уничтожьте вражескую армию за два хода, сохранив Некроманта, ещё одно существо и хотя бы два здоровья героя. Бешенство вынуждает врага атаковать; Мышь защищена Панцирем. У вас шесть эфира. Следующее возмущение нанесёт два урона, затем регенерация восстановит один.",
        hints_ru=["Способность воскрешения работает с обоими могильниками. Важны печатная цена и способности новобранца, а не только его сила.",
                  "Некромант должен снова встать для наземного врага. Яд убивает после ответного удара жертвы, поэтому Шершню нужна и защита.",
                  "Поднимите Магического шершня и дайте ему Ледяной Панцирь. Сохраните три эфира для Общей Подзарядки. Некромантом блокируйте Стального мехоса, Шершнем — защищённую Летучую мышь."],
        explanation_ru="Некромант бесплатно поднимает Шершня с ценой четыре, но сам ложится. Ледяной Панцирь позволяет Шершню выдержать пять урона Мыши. После смены хода новобранец готов, а Бешенство заставляет обоих врагов атаковать. Общая Подзарядка поднимает Некроманта: его восемь урона первым ударом уничтожают Стального мехоса до ответа. Шершень переживает ответ Мыши, и его яд добивает летающего врага со стойкостью восемь. Возмущение двенадцатого уровня отнимает два здоровья, высшая Регенерация возвращает одно: итог — два. Допустим и размен Шершня с последующим воскрешением на втором ходу: так вы восстановите нужную численность армии. Более сильная Летучая мышь не убивает защищённого врага за один бой, а Мехочервь не закрывает воздушное направление.",
    ))

    out.append(puzzle(
        game, "spare_the_parasite", "Spare the Parasite", "A living enemy as the winning clock", 3, 1,
        state(game,
              hero("Black", ["ENAL", "PLMR"], level=2, turns=15, maximum=13, health=2, mana=3),
              hero("Black", [], template="White Lord I", level=20, turns=16, maximum=67, health=5),
              [unit("LMMN", 2, resting=True), unit("MAHO", 3), unit("STMZ", 4, 1)], phase=1, attacker=1, attacks=[4]),
        "Win during this defence. Steel Mechozaurus costs its controller five health at turn end, but its attack can drain life. If the duel continues, your level-two disturbance deals a lethal three before you can act.",
        ["You need the parasite alive at turn end and its owner still at five health.",
         "Prevent all trample damage without dealing enough combat damage to kill the Mechozaurus. Poison will not destroy an unaffected creature.",
         "Use Energize All, then block only with the Lamia Monk. It absorbs all eight damage and dies; its four damage leaves the parasite alive. Do not add the Hornet."],
        "The Monk's eight toughness absorbs the entire attack, so the enemy gains no life. Its four damage does not kill the six-toughness Mechozaurus. The parasite then drains its controller's last five health, ending the duel before your next disturbance. Adding the Hornet contributes two first-strike damage; that plus the Monk's four kills the parasite and removes the very upkeep that would win. With no enemy death at turn end, your own three-point disturbance arrives first and kills you. Polymorph cannot target the protected Mechozaurus; consuming your Monk for health removes the only adequate blocker.",
        [cast("ENAL"), block(2, 4), end()],
        refutations=[
            {"label": "Combine both blockers to kill the attacker", "commands": [cast("ENAL"), block(3, 4), block(2, 4), end()]},
            {"label": "Turn the resting Monk into eight hero health", "commands": [cast("PLMR", 2)]},
            {"label": "Use only the ready poisonous flyer", "commands": [block(3, 4), end()]},
        ],
        hero_names=["Synthet Novice", "The White Lord"], hero_names_ru=["Ученик Синтетов", "Белый Лорд"],
        title_ru="Пощадите паразита", category_ru="Живой враг как условие победы",
        briefing_ru="Победите во время этой защиты. Стальной мехозавр отнимает у хозяина пять здоровья в конце хода, но его атака может высосать жизнь. Если бой продолжится, ваше возмущение второго уровня нанесёт смертельные три урона до любого действия.",
        hints_ru=["К концу хода паразит должен остаться жив, а его хозяин — сохранить ровно пять здоровья.",
                  "Поглотите весь натиск, не нанеся достаточно урона для убийства Мехозавра. Яд не уничтожает невосприимчивое существо.",
                  "Примените Общую Подзарядку и блокируйте только Ламией-монахиней. Она поглотит восемь урона и погибнет, оставив паразита в живых. Не добавляйте Шершня."],
        explanation_ru="Восемь стойкости Монахини поглощают всю атаку: враг не получает жизни. Четыре ответных урона не убивают Мехозавра со стойкостью шесть. Паразит отнимает последние пять здоровья хозяина, завершая бой до вашего возмущения. Шершень добавил бы два урона первым ударом; вместе с четырьмя Монахини это убивает паразита и отменяет нужную плату в конце хода. Тогда первым погибнет ваш герой от возмущения на три урона. Превращение не может выбрать защищённого Мехозавра, а превращение своей Монахини в здоровье лишает вас подходящего защитника.",
    ))
    return out
