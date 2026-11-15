"""Master studies for Etherlords I: linked decisions and response plans.

All cards, accumulated enchantment values, and starting wounds are ordinary
combat state. Final-condition requirements are declared in objective metadata.
"""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end


def puzzles():
    game = "el1"
    out = []

    out.append(puzzle(
        game, "two_lives_one_reset", "Two Lives, One Reset", "Reanimation, regeneration and a health reset", 3, 1,
        state(game, hero("Blue", ["WTLK", "WTLK", "PLMR", "RIFT"], mana=8, health=1),
              hero("Green", [], mana=1, health=30),
              [unit("GRTN", 2, 1), unit("FREL", 3, 1)]),
        "Clear the enemy army this turn, finishing with at least two creatures and eight hero health. "
        "You begin without an army. The enemy has one ether for regeneration.",
        ["Removing an enemy can also recruit it, but a regeneration is not a death.",
         "Use the removal that forbids regeneration on the Treant. Polymorph sets your health instead of adding to it.",
         "Water Link the Treant and Polymorph it first. Then Water Link the Fire Elemental and destroy it with Rift."],
        "Linking the Treant before Polymorph brings it back under your control. Polymorph bypasses "
        "regeneration and sets your health to the Treant's three toughness, overriding the link's healing. "
        "Link the Elemental next and Rift it: its return gives the second ally and adds five health, "
        "finishing at eight. Reversing the two removals ends at three health. Rifting the Treant instead "
        "allows regeneration, spending the removal without recruiting or clearing that creature.",
        [cast("WTLK", 2), cast("PLMR", 2), cast("WTLK", 3), cast("RIFT", 3)],
        objective={"type": "clear", "finish_health": 8, "min_allies": 2},
        refutations=[
            {"label": "Use Rift on the regenerating Treant", "commands": [cast("WTLK", 2), cast("RIFT", 2)]},
            {"label": "Collect the Elemental's healing before the health reset", "commands": [cast("WTLK", 3), cast("RIFT", 3)]},
            {"label": "Polymorph the Treant before linking it", "commands": [cast("PLMR", 2)]},
        ],
        title_ru="Две жизни и один сброс", category_ru="Возвращение, регенерация и смена здоровья",
        briefing_ru="За этот ход уберите вражескую армию, закончив хотя бы с двумя существами и восемью "
        "единицами здоровья героя. Своих существ пока нет. У врага один эфир для регенерации.",
        hints_ru=["Убрать врага можно так, чтобы он стал союзником, но регенерация не считается смертью.",
                  "Древню нужно заклинание, запрещающее регенерацию. Превращение устанавливает здоровье героя, а не прибавляет его.",
                  "Сначала свяжите Древня Водной Связью и примените Превращение. Затем свяжите Элементаля огня и уничтожьте его Разломом."],
        explanation_ru="Водная Связь возвращает Древня под ваш контроль после Превращения. Регенерация "
        "запрещена, а здоровье героя становится равным трём — стойкости Древня; это перекрывает исцеление "
        "от связи. Затем свяжите Элементаля и примените Разлом. Его возвращение даёт второго союзника "
        "и ещё пять здоровья: итог — восемь. Обратный порядок убийств оставляет лишь три здоровья. "
        "Разлом на Древне вызывает регенерацию: заклинание потрачено, а враг не убит и не перешёл к вам.",
    ))

    out.append(puzzle(
        game, "census_of_eyes", "A Census of Eyes", "Racial counts and two removal thresholds", 3, 1,
        state(game, hero("Green", ["CLON", "WEAK", "SPWR"], mana=6), hero("Blue", [], health=30),
              [unit("BEHD", 2), unit("BHWR", 3), unit("WLBR", 4, 1), unit("GRDG", 5, 1)]),
        "Clear the enemy army this turn. Your two Evil Eyes measure different attributes. "
        "A newly created creature may matter before it is ready to act.",
        ["Both gaze thresholds depend on how many Evil Eyes you control.",
         "A clone counts immediately, although it cannot use its own gaze yet. The Warrior's gaze measures power and refuses Walls.",
         "Clone either Evil Eye, Weaken the Green Dragon, use the ordinary Eye on the wall and the Warrior on the Dragon."],
        "Cloning either Eye raises the count from two to three. The original Evil Eye can now destroy "
        "the three-toughness Wall of Burning Rock. Weaken lowers the Dragon's power from seven to three, "
        "so the Warrior's different gaze can destroy it. The new clone's summoning sickness is irrelevant "
        "to the racial count. A cloned Dragon or Wall contributes no Eye, and an early Spirit of War "
        "leaves too little ether for both the count increase and the necessary debuff.",
        [cast("CLON", 2), cast("WEAK", 5), ability(2, "gaze", 4), ability(3, "gaze", 5)],
        objective={"type": "clear"},
        refutations=[
            {"label": "Clone the impressive enemy Dragon", "commands": [cast("CLON", 5)]},
            {"label": "Weaken the wall to lower its toughness", "commands": [cast("WEAK", 4)]},
            {"label": "Buy an extra action before improving either threshold", "commands": [cast("SPWR", 2)]},
        ],
        title_ru="Перепись злобоглазов", category_ru="Численность расы и разные пороги уничтожения",
        briefing_ru="Уберите вражескую армию за этот ход. Ваши два злобоглаза оценивают разные характеристики. "
        "Новое существо может принести пользу ещё до готовности к действию.",
        hints_ru=["Порог обоих взглядов зависит от числа ваших злобоглазов.",
                  "Клон сразу входит в это число, хотя сам пока не может смотреть. Взгляд Воина проверяет силу и не действует на стены.",
                  "Клонируйте любого злобоглаза, ослабьте Зелёного дракона, обычным Злобоглазом уничтожьте стену, а Воином — Дракона."],
        explanation_ru="Клон любого злобоглаза увеличивает их число с двух до трёх. Исходный Злобоглаз "
        "теперь уничтожает Стену горящего камня со стойкостью три. Слабость снижает силу Дракона с семи "
        "до трёх, позволяя уничтожить его взглядом Воина. Неготовность клона не мешает учитывать его "
        "в численности расы. Клон Дракона или стены злобоглазом не считается, а ранний Дух Войны тратит "
        "эфир, необходимый и для увеличения числа существ, и для ослабления цели.",
    ))

    out.append(puzzle(
        game, "gift_too_generous", "A Gift Too Generous", "Private income and a defensive reserve", 3, 2,
        state(game,
              hero("Red", ["VOLC", "GEYS", "GEYS", "MNST", "SNRG"], mana=8, channels=0, health=1),
              hero("Red", ["RIFT"], mana=1, channels=1, health=30),
              [unit("RKWL", 2), unit("TNSA", 3), unit("GROG", 4, 1), unit("TIWR", 5, 1)]),
        "Survive two enemy turns, preserve both creatures, and finish with at least five ether. "
        "You begin with no ether channels. The enemy's only card is Rift, currently beyond its one-channel income.",
        ["The largest channel spell improves both heroes' future budgets.",
         "You need five channels of your own and one ether left for the first defence. A reserve blocker is more valuable than a one-point attack.",
         "Cast Volcano and both Geysers, keeping one ether. Block the Ogre with Rock Wall and the Tick with the Sapling whenever they attack. Your five channels refill for the later defence and the finish."],
        "Volcano adds three private channels; the two Geysers add one each. Their seven-ether cost "
        "leaves the one ether needed for the Sapling to regenerate through the Tick's first attack. "
        "The Wall holds the Ogre. Subsequent refills provide five ether, including the refill at the "
        "successful second enemy-turn boundary. Ether Storm looks efficient but gives the enemy four "
        "channels too, making its Rift affordable and destroying a protected defender. Stone Ring "
        "spends too much of the opening budget for too little future income.",
        [cast("VOLC"), cast("GEYS"), cast("GEYS"), end(),
         attack(4, side=1), attack(5, side=1), end(side=1), block(2, 4), block(3, 5), end(), end(),
         attack(4, side=1), attack(5, side=1), end(side=1), block(2, 4), block(3, 5), end()],
        objective={"type": "survive", "enemy_turns": 2, "protect": [2, 3], "finish_mana": 5},
        refutations=[
            {"label": "Use the larger shared channel increase", "commands": [cast("MNST")]},
            {"label": "Invest in the inefficient Stone Ring", "commands": [cast("SNRG")]},
            {"label": "Send the future blocker into an unnecessary attack", "commands": [cast("VOLC"), cast("GEYS"), cast("GEYS"), attack(3), end()]},
        ],
        title_ru="Слишком щедрый дар", category_ru="Собственный доход и запас на защиту",
        briefing_ru="Переживите два хода врага, сохраните обоих существ и закончите хотя бы с пятью единицами "
        "эфира. У вас пока нет эфирных каналов. Единственная карта врага — Разлом; дохода от одного канала ему пока не хватает.",
        hints_ru=["Самое большое увеличение каналов улучшит будущие возможности обоих героев.",
                  "Вам нужны пять своих каналов и единица эфира на первую защиту. Будущий защитник важнее атаки на один урон.",
                  "Примените Вулкан и оба Гейзера, оставив один эфир. При атаках блокируйте Людоеда стеной, Клеща — Древнем. Пять каналов дадут эфир для следующей защиты и завершения задачи."],
        explanation_ru="Вулкан даёт три канала только вам, два Гейзера — ещё по одному. Семь потраченных "
        "единиц эфира оставляют одну для регенерации Древня при первой атаке Клеща. Стена держит Людоеда. "
        "Дальнейшие пополнения дают пять эфира, включая пополнение на границе после второго хода врага. "
        "Эфирный Шторм кажется выгоднее, но добавляет четыре канала и врагу: тот сможет применить Разлом "
        "к защищаемому существу. Кольцо Камней слишком дорого обходится для столь малого будущего дохода.",
    ))

    out.append(puzzle(
        game, "every_coin_draws_blood", "Every Coin Draws Blood", "Payment damage and an enemy resource reserve", 4, 1,
        state(game,
              hero("Blue", ["FRBL"], mana=3, health=2,
                   enchantments=[enchant("FRBL", id=1), enchant("FRBL", id=2), enchant("COPL", id=3)]),
              hero("Green", [], mana=3, health=4, enchantments=[enchant("MNTH", id=4)]),
              [unit("RVHL", 2), unit("SEHL", 3, enchantments=[enchant("FAIL", id=5)]),
               unit("ORSH", 4), unit("TNSA", 5, 1), unit("WLFC", 6, 1)]),
        "Win this turn. Ether Thorns damages either hero for every ether spent. Two Fireballs and Life Channel "
        "are already active; a third Fireball is in hand. Your two Halos steal different amounts.",
        ["The enemy needs to keep one ether long enough to do something useful for you.",
         "Regeneration can trigger your Life Channel. Emptying the enemy's pool first prevents that healing, while installing the third Fireball before healing kills you.",
         "Use the River Halo to take two ether and the Shaman for one. Fireball the Sapling so it regenerates, then install the third Fireball and use the two unused shots on the hero."],
        "River Halo leaves one enemy ether for the Sapling's automatic regeneration. With the Shaman, "
        "you have six ether in total. The first Fireball costs one health through Thorns, then regeneration "
        "triggers five healing from Life Channel. You can now afford the three-ether installation and "
        "the two remaining shots: six ether spent overall leaves one health. The enemy also loses one "
        "health paying to regenerate; two shots finish it. Sea Halo is safe only after that regeneration "
        "has happened. Stealing all three ether first disables the healing route. The weakened Sea Halo "
        "cannot replace the final shot with combat damage.",
        [ability(2, "siphon"), ability(4, "ether"), ability(0, "fireball:1", 5),
         cast("FRBL"), ability(0, "fireball:2", 1), ability(0, "fireball:6", 1)],
        refutations=[
            {"label": "Empty the enemy pool with the larger Halo first", "commands": [ability(3, "siphon")]},
            {"label": "Install the third Fireball before healing", "commands": [cast("FRBL")]},
            {"label": "Take the apparent immediate kill with both existing shots", "commands": [ability(0, "fireball:1", 1), ability(0, "fireball:2", 1)]},
        ],
        title_ru="Каждый квант оплачен кровью", category_ru="Урон за оплату и резерв эфира врага",
        briefing_ru="Победите за этот ход. Колючий Эфир ранит любого героя за каждую потраченную единицу эфира. "
        "Два Огненных Шара и Канал Жизни уже действуют; третий Шар в руке. Два ваших нимба крадут разное количество эфира.",
        hints_ru=["Врагу нужно ненадолго оставить единицу эфира: она позволит ему сделать нечто полезное для вас.",
                  "Регенерация активирует ваш Канал Жизни. Полное опустошение вражеского запаса запрещает это исцеление, а установка третьего Шара до исцеления убивает героя.",
                  "Речным нимбом заберите два эфира, Шаманом получите ещё один. Шаром заставьте Древня регенерировать, затем установите третий Шар и двумя неиспользованными выстрелами добейте героя."],
        explanation_ru="Речной нимб оставляет врагу один эфир для автоматической регенерации Древня. "
        "Вместе со способностью Шамана вы получаете шесть эфира. Первый выстрел отнимает здоровье из-за "
        "Колючего Эфира, затем регенерация активирует Канал Жизни и восстанавливает пять здоровья. Теперь "
        "можно заплатить три за установку Шара и ещё два за последние выстрелы: всего потрачено шесть, "
        "у героя остаётся одно здоровье. Враг также теряет здоровье при оплате регенерации; двух выстрелов "
        "достаточно. Морского нимба можно использовать после регенерации, но его большой первоначальный "
        "захват отключает лечение. Ослабленный Морской нимб не заменит последний выстрел атакой.",
    ))

    out.append(puzzle(
        game, "wall_after_battle", "The Wall After the Battle", "Temporary toughness, recovery and final health", 4, 1,
        state(game,
              hero("Blue", ["PLMR", "ENAL"], mana=3, health=1, grave=["STRT", "TIWR", "ORSH", "CAFG"]),
              hero("Blue", [], mana=2, health=30, enchantments=[enchant("FTDS", id=1)]),
              [unit("WLIL", 2, damage=2, enchantments=[enchant("SHSK", id=2)]), unit("PTRS", 3), unit("RVHL", 4),
               unit("GROG", 5, 1), unit("BUDG", 6, 1)], phase=1, attacker=1, attacks=[5, 6]),
        "Survive this attack, preserve all three creatures, and finish with at least eight hero health. "
        "The Wall of Illusion is already wounded. Enemy Fatal Disease prevents your wounds from recovering.",
        ["The wall has to survive both combat and the disappearance of its temporary toughness.",
         "Removing Fatal Disease restores the normal cleanup, but does not erase existing wounds immediately. The Halo must finance all three jobs: a dispel, an illusion and a transformation.",
         "Steal two ether with the Halo. Dispel Fatal Disease with the Pteros, Polymorph the Blue Dragon, and activate the wall's illusion. Block the Ogre with the wall."],
        "The Halo raises your pool from three to five. The Pteros pays three to remove Fatal Disease; "
        "Polymorph costs one and sets your hero to the Dragon's eight toughness. The wall's one-ether "
        "ability replaces its printed three toughness with five, because four creatures lie in your "
        "graveyard. Shell Skin remains, making nine toughness. Its two old wounds plus the Ogre's six "
        "damage leave it barely alive. Normal cleanup now erases those wounds before the temporary "
        "illusion ends. Keeping Fatal Disease would kill the wall when it falls back to seven toughness. "
        "Letting the Ogre through misses the final health requirement.",
        [ability(4, "siphon"), ability(3, "dispel", 1, choice=1), cast("PLMR", 6),
         ability(2, "illusion"), block(2, 5), end()],
        objective={"type": "survive", "enemy_turns": 1, "protect": [2, 3, 4], "finish_health": 8},
        refutations=[
            {"label": "Dispel the wall's Shell Skin rather than Fatal Disease", "commands": [ability(3, "dispel", 2, choice=2)]},
            {"label": "Polymorph the ground attacker", "commands": [cast("PLMR", 5)]},
            {"label": "Spend the opening pool on Energize All", "commands": [cast("ENAL")]},
            {"label": "Remove disease but block without raising the wounded wall's toughness", "commands": [ability(4, "siphon"), ability(3, "dispel", 1, choice=1), cast("PLMR", 6), block(2, 5), end()]},
        ],
        title_ru="Стена после боя", category_ru="Временная стойкость, восстановление и итоговое здоровье",
        briefing_ru="Переживите атаку, сохраните всех троих существ и закончите хотя бы с восемью единицами "
        "здоровья героя. Стена иллюзии уже ранена. Вражеская Роковая Болезнь мешает вашим ранам заживать.",
        hints_ru=["Стена должна пережить и сам бой, и исчезновение временной стойкости.",
                  "Снятие Роковой Болезни возвращает обычное восстановление, но не убирает раны немедленно. Нимб должен оплатить три задачи: рассеивание, иллюзию и превращение.",
                  "Украдите Нимбом два эфира. Птеросом снимите Роковую Болезнь, Превращением уберите Синего дракона и активируйте иллюзию стены. Стеной блокируйте Людоеда."],
        explanation_ru="Нимб увеличивает запас эфира с трёх до пяти. Птерос за три снимает Роковую Болезнь; "
        "Превращение за один устанавливает герою восемь здоровья — стойкость Дракона. Последний эфир "
        "оплачивает способность стены: четыре карты в могильнике заменяют её исходную стойкость три "
        "на пять. Ледяной Панцирь остаётся, давая итоговые девять. Две старые раны и шесть урона Людоеда "
        "оставляют стену в живых. Теперь обычное восстановление убирает раны до окончания иллюзии. "
        "С Роковой Болезнью стена погибла бы при возврате к семи стойкости. Пропуск Людоеда нарушает "
        "требование к итоговому здоровью.",
    ))

    capture = [cast("SHSK", 4), cast("CHCM", 4), end()]
    enemy_attack = [attack(5, side=1), attack(6, side=1), end(side=1)]
    out.append(puzzle(
        game, "borrowed_armour", "Borrowed Armour", "Enchantment ageing and a conditional defence", 4, 1,
        state(game,
              hero("Blue", ["CHCM", "SHSK", "SCSK"], mana=9, health=1),
              hero("Green", ["CLIG"], mana=1, channels=1, health=30),
              [unit("RKWL", 2), unit("TNSA", 3),
               unit("GROG", 4, 1, enchantments=[enchant("TWEN", id=1, power=-4, toughness=-4, born=4), enchant("BLSS", id=2, born=14)]),
               unit("GRTN", 5, 1), unit("BRMC", 6, 1)]),
        "Control the Gray Ogre after the enemy's next turn, preserving your Wall and Sapling. "
        "Its aged Twisted Enhancement is already at −4/−4; Bless masks that weakness. The enemy holds one Call Lightning.",
        ["The Ogre's displayed toughness will not survive the turn change unchanged. Capture and protection must be planned together.",
         "Shell Skin leaves the captured Ogre at four toughness after decay and Bless expiry. Save one ether for the Sapling, then inspect where the enemy spends Lightning.",
         "Give the Ogre Shell Skin and capture it. Keep Rock Wall for the Mechos. If Lightning hits the Ogre, block the Treant with your Sapling; if it hits the Sapling and spends your regeneration ether, block the Treant with the Ogre."],
        "The temporary Bless expires at the end of your turn because the Ogre originally belongs to the "
        "enemy. Its aged Enhancement also decays to −5/−5. Shell Skin leaves four toughness; Scale Skin "
        "would leave only two and lose to Lightning. Nine ether pays for capture and Shell Skin with one "
        "left for regeneration. If Lightning wounds the Ogre, reserve it and regenerate the Sapling "
        "through the Treant. If Lightning instead consumes the Sapling's regeneration ether, the unwounded "
        "Ogre can absorb the Treant's three damage. Rock Wall blocks the Bronze Mechos: Walls resist its "
        "post-combat execution. The goal is checked after the next enemy turn counted from this snapshot.",
        capture + [cast("CLIG", 4, side=1)] + enemy_attack + [block(2, 6), block(3, 5), end()],
        objective={"type": "control", "targets": [4], "enemy_turns": 1, "protect": [2, 3]},
        refutations=[
            {"label": "Use the cheaper Scale Skin on the captive", "commands": [cast("SCSK", 4)]},
            {"label": "Protect the Sapling with Shell Skin instead", "commands": [cast("SHSK", 3)]},
            {"label": "Capture and pass while the temporary Bless is the only protection", "commands": [cast("CHCM", 4), end()]},
            {"label": "Keep the same Sapling block after Lightning spends its regeneration reserve", "commands": capture + [cast("CLIG", 3, side=1)] + enemy_attack + [block(2, 6), block(3, 5), end()]},
        ],
        alternative_solutions=[{"label": "Lightning hits the Sapling", "commands": capture + [cast("CLIG", 3, side=1)] + enemy_attack + [block(2, 6), block(4, 5), end()]}],
        title_ru="Одолженная броня", category_ru="Старение чар и защита по ответу противника",
        briefing_ru="После ближайшего хода врага контролируйте Серого людоеда, сохранив свою стену и Древня. "
        "Его старое Искажённое Улучшение уже даёт −4/−4; Благословение скрывает слабость. У врага одна Молния.",
        hints_ru=["Показанная стойкость Людоеда изменится на границе хода. Захват и защиту нужно спланировать вместе.",
                  "После ослабления чар и окончания Благословения Ледяной Панцирь оставит Людоеду четыре стойкости. Сохраните один эфир для Древня, затем посмотрите, куда враг направит Молнию.",
                  "Дайте Людоеду Ледяной Панцирь и подчините его. Стеной держите Мехоса. Если Молния ранит Людоеда, блокируйте Старого древня Молодым; если она расходует эфир регенерации Молодого древня — блокируйте Людоедом."],
        explanation_ru="Благословение закончится в конце вашего хода: исходный владелец Людоеда — враг. "
        "Старое Улучшение также ослабеет до −5/−5. Панцирь оставит четыре стойкости, а Чешуя — лишь две, "
        "недостаточные против Молнии. Из девяти эфира захват и Панцирь оставляют один для регенерации. "
        "Если Молния ранит Людоеда, берегите его и блокируйте Старого древня Молодым с регенерацией. "
        "Если же Молния потратит резерв на регенерацию Молодого древня, невредимый Людоед выдержит три "
        "урона Старого. Каменная стена блокирует Бронзового мехоса: его добивание после боя не действует "
        "на стены. Цель проверяется после ближайшего хода врага, отсчитываемого от начальной позиции.",
    ))
    # Six ordinary enemy end steps aged an Enhancement cast on enemy turn two
    # from +2/+2 to -4/-4; the Bless was applied on the latest enemy turn.
    aged_position = out[-1]["state"]
    aged_position["round"] = 8
    aged_position["turn_serial"] = 15
    aged_position["heroes"][0]["turns"] = 8
    aged_position["heroes"][1]["turns"] = 7
    return out
