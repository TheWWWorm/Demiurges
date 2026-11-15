"""EL2 legends studies: asymmetric heroes and underused creature families."""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end


def puzzles():
    game = "el2"
    out = []

    out.append(puzzle(game, "keep_gift_alive", "Keep the Gift Alive", "A hostile gift between veterans", 4, 2,
        state(game,
            hero("Green", ["GIFT", "MALS", "WEAK"], mana=5, health=2, maximum=67, level=20, turns=31, template="Diamanda4Green"),
            hero("Red", ["CANV"], health=10, maximum=61, channels=2, level=18, turns=30, template="RedMale4", skills={"REGN": 2}),
            [unit("NWLF", 2), unit("SMVL", 3, resting=True), unit("WLAR", 4), unit("WLBL", 5), unit("OGKN", 6, 1)]),
        "Win within two turns. The level-18 opponent has Regeneration III, two channels and Force of Sacrifice. You have two health and two walls. Your level-20 hero will take one disturbance damage at the next turn; the opponent's next two natural disturbances deal two and three.",
        ["Gift changes more than ownership. Its bearer advances the receiving hero's disturbance clock by two turns.",
         "The recipient must stay alive, even if it attacks you. Remove the opponent's way to sacrifice it, and choose the body that will last.",
         "Discard Force of Sacrifice with Malison and give away the Night Wolf. Let the Wall of Air stop that Wolf without killing it; keep the Wall of Blades for the Ogre. Pass again to the next enemy turn."],
        "The gifted Wolf advances the opponent's next disturbance from two damage to five. Ten health becomes five, then Regeneration restores one. The following accelerated disturbance deals seven and kills the six-health hero before regeneration can trigger. A nonlethal block keeps the clock's carrier alive. Gifting the Small Velos fails because it dies at the end of its controller's turn: the next natural disturbance deals only three, which the opponent survives even if the elusive Wolf has attacked twice. Diamanda's level twenty is the exact survival margin: her next turn deals one damage; level nineteen would take two and die before the final pass.",
        [cast("MALS", 1), cast("GIFT", 2), end(), attack(2, side=1), attack(6, side=1), end(side=1), block(4, 2), block(5, 6), end(), end()],
        refutations=[
            {"label": "Give away the expiring Small Velos", "commands": [cast("GIFT", 3)]},
            {"label": "Weaken the Ogre before preparing the clock", "commands": [cast("WEAK", 6)]},
            {"label": "Kill the gifted Wolf with the sharp wall", "commands": [cast("MALS", 1), cast("GIFT", 2), end(), attack(2, side=1), end(side=1), block(5, 2), end()]},
        ], hero_names=["Diamanda, Last Form", "The Crimson Regent"], hero_names_ru=["Диаманда, последняя форма", "Багровый регент"]))

    out.append(puzzle(game, "midnight_census", "Midnight Census", "Bat drain before disturbance", 3, 1,
        state(game,
            hero("Red", ["BATT", "SHSK", "SMVL"], mana=8, health=1, maximum=16, level=3, turns=15, template="RedMale4", skills={"REGN": 2}),
            hero("Green", [], health=20, maximum=34, level=9, turns=14, template="GreenFemale2"),
            [unit("VBAT", 2), unit("BATT", 3), unit("GBAT", 4), unit("LMWA", 5, 1)]),
        "Survive one enemy turn and finish with at least four health and four creatures. Your level-3 hero faces two disturbance damage at the next turn, followed by Regeneration III. The enemy Lamia Warrior has trample.",
        ["Drain counts Bats that have just arrived, so the order of summoning and draining matters immediately.",
         "The Vampire must rest to drain. Keep another creature ready and tough enough to stop all seven combat damage.",
         "Summon the fourth Bat before using Vampire Bat's drain. Give Shell Skin to the Giant Bat and have it block the Lamia Warrior. The next disturbance and regeneration leave exactly four health."],
        "The fourth Bat increases the drain from three to four, raising your one health to five. Shell Skin makes the Giant Bat 5/8, so it can absorb the Warrior's seven damage without losing a body or allowing trample through. At the next turn, the level-three disturbance deals two before Regeneration III heals one: five becomes four. Draining before summoning misses the finishing threshold. The ordinary Bat reaches only six toughness with Shell Skin; it cannot preserve the required four creatures against the Warrior.",
        [cast("BATT"), ability(2, "bat_drain", 1), cast("SHSK", 4), end(), attack(5, side=1), end(side=1), block(4, 5), end()],
        objective={"type": "survive", "enemy_turns": 1, "finish_health": 4, "min_allies": 4},
        refutations=[
            {"label": "Drain before the fourth Bat arrives", "commands": [ability(2, "bat_drain", 1)]},
            {"label": "Spend one ether on the Small Velos", "commands": [cast("SMVL")]},
            {"label": "Give Shell Skin to the ordinary Bat", "commands": [cast("SHSK", 3)]},
        ], hero_names=["The Crimson Keeper", "The Emerald Huntress"], hero_names_ru=["Багровый хранитель", "Изумрудная охотница"]))

    out.append(puzzle(game, "smaller_well", "The Smaller Well", "Siphoning without losing the defender", 2, 1,
        state(game,
            hero("Blue", ["HEAL", "ENBR"], health=2, maximum=31, level=8, template="BlueWingedMale1"),
            hero("Blue", [], mana=6, health=30, maximum=43, level=12, template="BlueWingedFemale1"),
            [unit("SEHL", 2), unit("SWHL", 3), unit("GBAT", 4, 1)]),
        "Survive one enemy turn, preserve both Halos, and finish with at least fifteen health. Your level-8 hero's maximum is 31; Healing restores health to half that maximum. The enemy has six ether but no channels.",
        ["Taking the larger amount of ether is not free: the siphoning Halo must rest.",
         "Only one of your two flyers can take a five-power hit and stay alive. Healing needs just four ether.",
         "Siphon with the Sea Halo and spend its four ether on Healing. Keep the Swamp Halo ready to block the Giant Bat."],
        "The Sea Halo draws four of the enemy's six ether. Healing sets your health to floor(31/2), which is fifteen. The ready Swamp Halo survives the Giant Bat's five damage and preserves that total. Siphoning with the Swamp Halo gives more ether but leaves the fragile Sea Halo as the only blocker. Energy Barrier reduces non-combat damage, so it cannot save that Halo or preserve your finishing health against this attack.",
        [ability(2, "siphon", 1), cast("HEAL", 0), end(), attack(4, side=1), end(side=1), block(3, 4), end()],
        objective={"type": "survive", "enemy_turns": 1, "finish_health": 15, "protect": [2, 3]},
        refutations=[
            {"label": "Take six ether with the Swamp Halo", "commands": [ability(3, "siphon", 1)]},
            {"label": "Spend the smaller siphon's ether on Energy Barrier", "commands": [ability(2, "siphon", 1), cast("ENBR", 0)]},
        ], hero_names=["The Azure Adept", "The Winged Regent"], hero_names_ru=["Лазурный адепт", "Крылатая правительница"]))

    out.append(puzzle(game, "bank_discount", "Bank the Discount", "A foreign Warlord and a recovery investment", 3, 2,
        state(game,
            hero("Blue", ["CLFR", "CLFR", "CLFR"], mana=6, health=43, maximum=43, channels=6, grave=["LMWD", "LMWA", "LMMN"], level=12, template="BlueWingedMale1"),
            hero("Red", [], health=19, maximum=19, level=4, template="RedMale4"),
            [unit("LMMN", 2), unit("LMWA", 3, resting=True), unit("LMWD", 4, 1, resting=True, enchantments=[enchant("ALST", power=8)]),
             unit("LMWK", 5, 1), unit("LMWA", 6, 1), unit("MLFI", 7, 1), unit("CCLP", 8, 1)]),
        "Win within two turns and preserve your Lamia Monk and Warrior. The enemy Warlord carries Alpha Strike and will expire at the end of this turn. Your level-12 hero has its full 43 health; the opponent's scenario maximum is nineteen. You have six ether now and six channels.",
        ["A Lamia Warlord reduces summoning costs for both armies. Its discount will disappear before your next refill.",
         "The Monk returns a Lamia to your hand rather than putting it into play. Your health can pay for a turn spent preparing a new attacker.",
         "Recover the Warlord and summon it for six while the enemy discount is present. Absorb the enemy attack, then spend the next six ether on three Cloaks of Fear. The Monk, Warrior and new Warlord attack for nineteen."],
        "The foreign Warlord makes your recovered Warlord cost six instead of eight. The Monk and existing Warrior are resting, but the new Warlord becomes available to block after turn cleanup. The reference accepts all thirty-three enemy damage, using the level-twelve hero's full forty-three health to preserve every attacker. A safe Warlord block can reduce that payment. At the next refill, three Cloaks of Fear make four, seven and eight power unblockable: exactly nineteen. Recovering another Warrior produces only eighteen power. Spending on an early Cloak loses the temporary summoning window.",
        [ability(2, "recall_lamia", 0, choice=0), cast("LMWD"), end(), attack(5, side=1), attack(6, side=1), attack(7, side=1), attack(8, side=1), end(side=1), end(), cast("CLFR", 2), cast("CLFR", 3), cast("CLFR", 9), attack(2), attack(3), attack(9), end(), end(side=1)],
        objective={"type": "win", "protect": [2, 3]},
        refutations=[
            {"label": "Recover another Warrior instead of the Warlord", "commands": [ability(2, "recall_lamia", 0, choice=1)]},
            {"label": "Buy a Cloak for the Monk before banking the discount", "commands": [cast("CLFR", 2)]},
        ], hero_names=["The Sapphire Veteran", "The Red Warlord"], hero_names_ru=["Сапфировый ветеран", "Красный воевода"]))

    out.append(puzzle(game, "queens_shadow", "The Queen's Shadow", "A shared Bee aura and a one-sided rally", 3, 1,
        state(game,
            hero("Green", ["HEAL", "CANV", "HAST", "SHSK"], mana=8, health=1, maximum=25, level=6, template="GreenFemale2"),
            hero("Red", [], health=10, maximum=10, level=1, template="RedMale4"),
            [unit("MOBE", 2), unit("BEQN", 3), unit("BEWK", 4), unit("FMFI", 5), unit("BEWR", 6, 1, enchantments=[enchant("STRG")])]),
        "Win this turn, preserve your Female Fighter, and finish with at least fifteen health. The enemy Bee Warrior shares your Mother's first-strike aura and your other Bees' strength bonuses. Scenario maximums are 25 for your level-6 hero and 10 for the level-1 opponent.",
        ["Healing sets health to half the maximum. Any sacrifice healing that needs to exceed that floor must happen afterwards.",
         "Mother Bee helps both armies while alive. Her death rallies only her own surviving Bees, and removes the enemy's first strike.",
         "Heal first, then sacrifice Mother Bee. Give your army Haste for first strike and trample, and add the Female Fighter to the Bees' forced attack."],
        "Healing raises one health to twelve. The Queen and Worker make Mother Bee 2/3, so sacrificing her deals two and heals three: you reach fifteen while the enemy drops to eight. Mother's death removes the hostile Bee's first strike and sends your Queen and Worker into the attack. Haste restores first strike only to your side and grants trample. The Queen and Worker die when they hit the enemy hero, changing every remaining Bee's stats. If the enemy blocks the Fighter, the Queen deals two and dies, the Worker deals one and dies, then the Fighter tramples over the now one-toughness blocker for five: exactly eight. Blocking either Bee also lets eight through. Sacrificing before Healing ends at twelve health.",
        [cast("HEAL", 0), cast("CANV", 2), cast("HAST"), attack(5), end(), block(6, 5, side=1), end(side=1)],
        objective={"type": "win", "finish_health": 15, "protect": [5]},
        refutations=[
            {"label": "Sacrifice Mother Bee before Healing", "commands": [cast("CANV", 2)]},
            {"label": "Sacrifice the Queen instead of the Mother", "commands": [cast("CANV", 3)]},
            {"label": "Armor the Fighter before funding the attack", "commands": [cast("SHSK", 5)]},
        ], hero_names=["The Verdant Matriarch", "The Scarlet Poacher"], hero_names_ru=["Зелёная матриарх", "Алый браконьер"]))

    out.append(puzzle(game, "behind_magic_screen", "Behind the Magic Screen", "Global magic and a regeneration reserve", 3, 2,
        state(game,
            hero("Black", ["DOMN", "SHSK", "ENBR"], mana=5, health=4, maximum=37, level=10, turns=23, template="StartBlackMale", enchantments=[enchant("HAST"), enchant("FURY")]),
            hero("Red", [], health=55, maximum=55, level=16, turns=22, template="RedMale4"),
            [unit("STAB", 2), unit("IRAB", 3, enchantments=[enchant("SHSK")]), unit("STMC", 4, 1), unit("ORWR", 5, 1, enchantments=[enchant("SPBA")])]),
        "Clear the enemy army within two turns and preserve both Abominations. Haste and Fury already cover your hero; your Iron Abomination has Shell Skin. Your level-10 hero's next disturbance deals three damage.",
        ["The Steel Abomination cannot receive an ordinary targeted spell, but an army-wide enchantment can still strengthen it.",
         "The Iron Abomination must survive the poisoned Orc's first strike and still have ether available for the later lethal effect.",
         "Cast Dominance and save the last ether. Let Fury force the attack. Block the Mechos with Steel and the Orc with Iron; Iron regenerates after poison, and the next disturbance leaves your hero on one health."],
        "Dominance reaches the screened Steel Abomination and raises it to six power. Haste lets it kill the six-toughness Steel Mechos before receiving a hit. The armored Iron Abomination becomes 4/9: it survives the Orc's five-point first strike, kills the three-toughness Orc, then spends the reserved ether to regenerate through poison. Both enemies are gone. The level-ten disturbance deals three to your four-health hero at the next turn. Spending on a targeted defensive spell cannot supply Steel's missing power and removes the required combination of global enhancement and regeneration reserve.",
        [cast("DOMN"), end(), end(side=1), block(2, 4), block(3, 5), end()],
        objective={"type": "clear", "protect": [2, 3]},
        refutations=[
            {"label": "Add a second Shell Skin to Iron", "commands": [cast("SHSK", 3)]},
            {"label": "Buy an Energy Barrier for the disturbance", "commands": [cast("ENBR", 0)]},
            {"label": "Reverse the two defensive assignments", "commands": [cast("DOMN"), end(), end(side=1), block(2, 5), block(3, 4), end()]},
        ], hero_names=["The Iron Exile", "The Ashen Marshal"], hero_names_ru=["Железный изгнанник", "Пепельный маршал"]))
    for entry in out:
        entry.update(_LOCALIZED[entry["id"].removeprefix("el2_tactical_v2_")])
    return out


_LOCALIZED = {
    "keep_gift_alive": {
        "title_ru": "Берегите подарочек",
        "category_ru": "Враждебный подарок между ветеранами",
        "briefing_ru": "Победите за два хода. У противника 18-го уровня есть Регенерация III, два канала и Сила жертвоприношения. У вас две жизни и две стены. В начале следующего хода ваш герой 20-го уровня получит один урон от эфирного возмущения; два следующих возмущения противника без ускорения нанесут два и три.",
        "hints_ru": [
            "Подарочек не просто меняет владельца. Пока подаренное создание живо, возмущение получателя опережает обычный срок на два хода.",
            "Получатель должен остаться в живых, даже если нападёт на вас. Уберите возможность принести его в жертву и выберите создание, которое не исчезнет само.",
            "Проклятием сбросьте Силу жертвоприношения и подарите Ночного волка. Стеной воздуха остановите его, не убивая; Стену лезвий оставьте для Вождя людоедов. Затем снова передайте ход противнику.",
        ],
        "explanation_ru": "Подаренный Волк усиливает ближайшее возмущение противника с двух до пяти урона. Из десяти жизней остаётся пять, затем Регенерация возвращает одну. Следующее ускоренное возмущение наносит семь и убивает героя с шестью жизнями до срабатывания лечения. Поэтому носителя подарка нужно блокировать без смертельного урона. Малый колесник исчезает в конце своего хода: без него следующее возмущение нанесёт лишь три, и противник выживет даже после двух ударов неуловимого Волка. Двадцатый уровень Диаманды даёт точный запас: её ближайшее возмущение наносит один урон; на девятнадцатом уровне два урона убили бы её до последней передачи хода.",
    },
    "midnight_census": {
        "title_ru": "Полуночная перепись",
        "category_ru": "Летучие мыши против возмущения",
        "briefing_ru": "Переживите один вражеский ход и завершите задачу хотя бы с четырьмя жизнями и четырьмя созданиями. В начале следующего хода герой 3-го уровня получит два урона от возмущения, а затем сработает Регенерация III. Вражеская Ламия-воительница обладает пробивным ударом.",
        "hints_ru": [
            "Способность вампира считает и только что призванных летучих мышей: порядок призыва и высасывания сразу меняет результат.",
            "После способности вампир начнёт отдыхать. Сохраните другого готового защитника, способного принять все семь единиц урона.",
            "Сначала призовите четвёртую Летучую мышь, затем используйте способность вампира. Наложите Ледяной Панцирь на Гигантскую летучую мышь и заблокируйте ею Ламию. После возмущения и регенерации останутся ровно четыре жизни.",
        ],
        "explanation_ru": "Четвёртая мышь усиливает высасывание с трёх до четырёх: одна жизнь превращается в пять. Ледяной Панцирь делает Гигантскую летучую мышь созданием 5/8, которое принимает семь урона, сохраняет жизнь и не пропускает пробивной удар. В начале следующего хода возмущение на третьем уровне сначала отнимает две жизни, затем Регенерация III возвращает одну: остаётся четыре. Если использовать вампира до призыва, нужного здоровья не хватит. Стойкость обычной мыши даже с Панцирем достигает лишь шести, поэтому сохранить четыре создания таким блоком не получится.",
    },
    "smaller_well": {
        "title_ru": "Меньший источник",
        "category_ru": "Отбор эфира с сохранением защитника",
        "briefing_ru": "Переживите один вражеский ход, сохраните обоих нимбов и завершите задачу хотя бы с пятнадцатью жизнями. Максимум героя 8-го уровня — 31; Лечение восстанавливает здоровье до половины этого значения. У врага шесть единиц эфира и ни одного канала.",
        "hints_ru": [
            "Больший запас эфира имеет цену: использовавший способность нимб должен отдыхать.",
            "Только один из ваших двух летающих защитников переживёт удар силой пять. Для Лечения достаточно четырёх единиц эфира.",
            "Заберите четыре эфира Морским нимбом и потратьте их на Лечение. Болотного нимба оставьте готовым для блока Гигантской летучей мыши.",
        ],
        "explanation_ru": "Морской нимб забирает четыре из шести единиц вражеского эфира. Лечение поднимает здоровье до половины 31 с округлением вниз — пятнадцати. Готовый Болотный нимб выдерживает пять урона от Гигантской летучей мыши и сохраняет здоровье героя. Его собственная способность даст больше эфира, но оставит в защите лишь хрупкого Морского нимба. Энергетический Барьер уменьшает только небоевой урон: в этом бою он не спасёт ни нимба, ни требуемый запас здоровья.",
    },
    "bank_discount": {
        "title_ru": "Успеть купить со скидкой",
        "category_ru": "Чужая повелительница и вложение в армию",
        "briefing_ru": "Победите за два хода, сохранив своих Ламию-монахиню и Ламию-воительницу. На вражеской Повелительнице лежит Альфа-удар: она погибнет в конце этого хода. У вашего героя 12-го уровня полный запас в 43 жизни; у врага девятнадцать. Сейчас у вас шесть эфира и шесть каналов.",
        "hints_ru": [
            "Ламия-повелительница удешевляет призыв для обеих армий. Её скидка исчезнет раньше вашего следующего пополнения эфира.",
            "Монахиня возвращает Ламию в руку, а не сразу на поле. Запас здоровья позволяет посвятить ход подготовке нового бойца.",
            "Верните Повелительницу и призовите её за шесть, пока действует чужая скидка. Примите вражескую атаку героем, затем потратьте следующие шесть эфира на три Маски Ужаса. Монахиня, Воительница и новая Повелительница нанесут девятнадцать урона.",
        ],
        "explanation_ru": "Чужая Повелительница снижает стоимость вашей возвращённой карты с восьми до шести. Монахиня и прежняя Воительница отдыхают, но новая Повелительница сможет блокировать после завершения хода. Приведённое решение принимает все тридцать три урона героем: полный запас двенадцатого уровня в сорок три жизни позволяет сохранить каждого будущего атакующего. Безопасный блок Повелительницей может уменьшить эту плату. После пополнения три Маски Ужаса делают четыре, семь и восемь силы неблокируемыми — ровно девятнадцать. Ещё одна Воительница вместо Повелительницы даст лишь восемнадцать. Ранняя Маска отнимет эфир, необходимый для покупки в короткое окно скидки.",
    },
    "queens_shadow": {
        "title_ru": "Тень королевы",
        "category_ru": "Общая аура и ярость своих пчёл",
        "briefing_ru": "Победите за этот ход, сохраните Серого некроманта и завершите задачу хотя бы с пятнадцатью жизнями. Вражеская Пчела-воин получает первый удар от вашей Матки и усиление от остальных ваших пчёл. В этой позиции максимум героя 6-го уровня равен 25, а у противника 1-го уровня десять жизней.",
        "hints_ru": [
            "Лечение доводит здоровье до половины максимума. Лечение жертвой, которое должно поднять его выше этого порога, применяйте позже.",
            "Живая Матка помогает обеим армиям. После её смерти в ярость приходят только свои пчёлы, а вражеская теряет первый удар.",
            "Сначала примените Лечение, затем принесите Матку в жертву. Спешкой дайте своей армии первый и пробивной удары; к вынужденной атаке пчёл добавьте Серого некроманта.",
        ],
        "explanation_ru": "Лечение поднимает одну жизнь до двенадцати. Королева и Рабочая пчела делают Матку созданием 2/3: её жертва наносит два урона и лечит на три. У вас пятнадцать жизней, у врага восемь. Смерть Матки убирает первый удар врага и отправляет ваших Королеву и Рабочую пчелу в атаку. Спешка даёт первый и пробивной удары лишь вашей армии. Пчёлы погибают после удара по герою, меняя характеристики оставшихся пчёл. Если враг блокирует некроманта, Королева наносит два и погибает, Рабочая — один и погибает, а некромант пробивает оставшуюся единицу стойкости блокирующего создания ещё на пять: ровно восемь. Блок любой пчелы также пропускает восемь. Жертва до Лечения оставит лишь двенадцать жизней.",
    },
    "behind_magic_screen": {
        "title_ru": "За магическим щитом",
        "category_ru": "Общая магия и запас на регенерацию",
        "briefing_ru": "Уничтожьте вражескую армию за два хода и сохраните обоих исчадий. На вашем герое уже действуют Спешка и Бешенство, на Железном исчадии — Ледяной Панцирь. Ближайшее возмущение нанесёт вашему герою 10-го уровня три урона.",
        "hints_ru": [
            "Стальное исчадие не принимает обычные направленные заклинания, но чары на всю армию всё равно могут его усилить.",
            "Железное исчадие должно пережить первый удар ядовитого Орка; после этого ему ещё понадобится эфир против смертельного эффекта.",
            "Примените Господство и сохраните последний эфир. Бешенство заставит врагов атаковать. Стальным исчадием блокируйте мехоса, Железным — Орка. Железное регенерирует после яда, а возмущение оставит герою одну жизнь.",
        ],
        "explanation_ru": "Господство проходит сквозь магический щит Стального исчадия и поднимает его силу до шести. Благодаря Спешке оно убивает Стального мехоса со стойкостью шесть раньше ответного удара. Закованное в Панцирь Железное исчадие становится 4/9: выдерживает первый удар Орка на пять, убивает его с тремя единицами стойкости и затем тратит сохранённый эфир на регенерацию после яда. Оба врага уничтожены. В начале следующего хода возмущение на десятом уровне отнимает три из четырёх жизней героя. Направленное защитное заклинание не даст Стальному исчадию недостающей силы и лишит вас сочетания общего усиления с запасом на регенерацию.",
    },
}
