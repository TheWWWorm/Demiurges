"""Crucible: five short Expert victories for Etherlords II.

Every objective is a normal hero victory. No protected-unit or finishing-stat
requirements are added. Reference moves, genuine failed openings, bilingual
hints and explanations are checked against the real duel implementation.
"""
from puzzle_authoring import (
    hero, unit, state, enchant, puzzle, cast, ability, attack, block, end,
)


def _study(slug, position, solution, refutations):
    text = _TEXT[slug]
    return puzzle(
        "el2", "crucible_" + slug, text["title"], text["category"], 4, 2,
        position, text["briefing"], text["hints"], text["explanation"], solution,
        objective={"type": "win"}, refutations=refutations,
        **{key: value for key, value in text.items()
           if key not in ("title", "category", "briefing", "hints", "explanation")},
    )


def puzzles():
    g = "el2"
    out = []
    out.append(_study(
        "right_corpse",
        state(g,
            hero("Black", ["QKFX", "ALST", "REPR", "CLON", "CANV"],
                 mana=5, channels=1, health=1, grave=["WKHR", "RZMN"],
                 enchantments=[enchant("BROT", id=1)]),
            hero("Red", [], health=28),
            [unit("GBAT", 2, 1), unit("GROG", 3, 1)]),
        [cast("QKFX", 0, grave=0), cast("ALST", 4),
         ability(0, "burnout:1", 4, choice=1), end(), end(side=1),
         cast("REPR", 0, grave=0)],
        [{"label": "Revive the stronger Razor Man",
          "commands": [cast("QKFX", 0, grave=1)]},
         {"label": "Repair the Razor Man immediately",
          "commands": [cast("REPR", 0, grave=1)]}],
    ))
    out.append(_study(
        "glass_furnace",
        state(g,
            hero("Red", ["DELS", "SHFR", "CANV", "REPR"],
                 mana=6, channels=3, health=1,
                 enchantments=[enchant("BROT", id=1)]),
            hero("Red", [], health=17),
            [unit("CAFG", 2, enchantments=[enchant("STAT", id=2)]),
             unit("WLLV", 3),
             unit("GBAT", 4, 1, enchantments=[enchant("STRG", id=3)])]),
        [cast("SHFR", 3, power=3), cast("DELS", 2), ability(2, "spores", 1),
         end(), attack(4, side=1), end(side=1), block(3, 4), end(),
         cast("DELS", 3), ability(0, "burnout:1", 3, choice=1)],
        [{"label": "Spend the shield on the Fingus",
          "commands": [cast("SHFR", 2, power=3)]},
         {"label": "Turn the wall into the first projectile",
          "commands": [cast("DELS", 3), ability(0, "burnout:1", 3, choice=1)]}],
    ))
    out.append(_study(
        "last_funeral",
        state(g,
            hero("Black", ["ALST", "STRG", "HAST", "REPR", "BRGR"],
                 mana=4, channels=4, health=3,
                 enchantments=[enchant("FURY", id=1)]),
            hero("Red", [], health=28),
            [unit("WLBL", 2), unit("GRTN", 3), unit("FREL", 4),
             unit("RFPT", 5, 1, enchantments=[enchant("SHSK", id=2)]),
             unit("GROG", 6, 1), unit("TIWR", 7, 1)]),
        [cast("ALST", 2), cast("STRG", 3), end(), end(side=1),
         block(2, 5), block(3, 7), block(4, 6), end(),
         cast("REPR", 0, grave=0), cast("BRGR"),
         attack(3), attack(4), end(), end(side=1)],
        [{"label": "Buy first strike for everyone",
          "commands": [cast("HAST")]},
         {"label": "Give Alpha Strike to the Treant",
          "commands": [cast("ALST", 3)]},
         {"label": "Burn the graves before returning the Wall",
          "commands": [cast("ALST", 2), cast("STRG", 3), end(), end(side=1),
                       block(2, 5), block(3, 7), block(4, 6), end(), cast("BRGR")]}],
    ))
    out.append(_study(
        "two_doors",
        state(g,
            hero("White", ["PLMR", "ALST", "CLFR"], mana=2, channels=3,
                 health=1, enchantments=[enchant("OEXC", id=1)]),
            hero("Black", ["PLMR"], mana=0, channels=1, health=11),
            [unit("SMWB", 2, sick=True), unit("OUS2", 3, plane=True),
             unit("SMWB", 4, 1, plane=True), unit("RKWL", 5, 1),
             unit("STMC", 6, 1)]),
        [ability(0, "recycle:1", 4, choice=2), cast("PLMR", 4), end(),
         attack(6, side=1), end(side=1), end(), ability(3, "ether_plea", 1),
         ability(0, "recycle:1", 2, choice=5), cast("ALST", 2),
         attack(2), end(), end(side=1)],
        [{"label": "Hide the enemy Mechos instead of your sick Knight",
          "commands": [ability(0, "recycle:1", 4, choice=6)]},
         {"label": "Polymorph the Mechos instead of the Knight",
          "commands": [cast("PLMR", 6)]},
         {"label": "Buy Alpha Strike before the escape",
          "commands": [cast("ALST", 2)]}],
    ))
    venom = _study(
        "venom_clock",
        state(g,
            hero("Green", ["CLFR", "CMBN", "OVRL", "SHSK"],
                 mana=5, channels=0, health=1),
            hero("Blue", ["HAST"], mana=0, channels=2, health=9),
            [unit("TRSN", 2), unit("WLAR", 3), unit("WLBL", 4),
             unit("GBAT", 5, 1, enchantments=[enchant("SPBA", id=1)]),
             unit("LMWD", 6, 1), unit("GROG", 7, resting=True)]),
        [cast("CLFR", 2), cast("SHSK", 3), attack(2), end(), end(side=1),
         cast("HAST", side=1), attack(6, side=1), end(side=1), block(4, 6), end(),
         attack(2), end(), end(side=1), attack(5, side=1), attack(6, side=1),
         end(side=1), block(4, 5), block(3, 6), block(7, 6), end(),
         attack(2), attack(7), end(), end(side=1)],
        [{"label": "Commit to a six-point Snake attack without the required defence",
          "commands": [cast("CLFR", 2), cast("OVRL", 2), attack(2), end(),
                       end(side=1), cast("HAST", side=1), attack(5, side=1),
                       attack(6, side=1), end(side=1)]},
         {"label": "Combine into the larger wall and face both tramplers",
          "commands": [cast("CLFR", 2), cast("CMBN"),
                       ability(0, "combine:3", 7, choice=4), attack(2), end(),
                       end(side=1), cast("HAST", side=1), attack(5, side=1),
                       attack(6, side=1), end(side=1)]}],
    )
    venom["turns"] = 3
    out.append(venom)
    return out


_TEXT = {'right_corpse': {'title': 'Borrowed Violence',
                  'title_ru': 'Заёмная сила',
                  'category': 'Reanimation, lethal pressure and an exact reserve',
                  'category_ru': 'Возвращение из могилы, натиск и точный запас',
                  'briefing': 'Win within two turns. Burnout is already active. You have five '
                              'ether now, but only one channel; the enemy army can kill your '
                              'one-health hero on its next attack. Both graveyard creatures are '
                              'available to your spells.',
                  'briefing_ru': 'Победите за два хода. На вас уже действует Сожжение. Сейчас есть '
                                 'пять единиц эфира, но только один канал; следующая атака врага '
                                 'смертельна для героя с одной жизнью. Оба существа в могильнике '
                                 'доступны вашим заклинаниям.',
                  'hints': ['The largest printed attack is not enough. Your opening must also '
                            'remove both attackers before they get a turn.',
                            'The Walking Horror damages the other creatures both when it arrives '
                            'and when it leaves. These enemies survive one three-point wave. Alpha '
                            'Strike adds printed power to the reanimated creature.',
                            'Quick Fix the Walking Horror, give it Alpha Strike, and use Burnout '
                            'on it against the enemy hero. Its two waves clear the enemy army. On '
                            'your second turn, use the only ether to Repair the Razor Man.'],
                  'hints_ru': ['Одной большой силы недостаточно. Начальный план должен убрать '
                               'обоих врагов до их хода.',
                               'Ходячий ужас ранит остальных существ и при появлении, и при '
                               'гибели. Эти враги переживут одну волну на три. Альфа-удар '
                               'прибавляет печатную силу возвращённого существа.',
                               'Верните Ходячий ужас Быстрой Починкой, примените к нему Альфа-удар '
                               'и принесите его в жертву Сожжением против героя. Две волны '
                               'уничтожат вражескую армию. На втором ходу потратьте единственный '
                               'эфир на Ремонт Потрошителя.'],
                  'explanation': 'Quick Fix brings the Horror back as 8/8 and its arrival deals '
                                 'three to each enemy. Alpha Strike adds its printed nine power, '
                                 'making seventeen. Burnout spends the fifth ether, deals '
                                 'seventeen to the hero and releases the second three-point wave, '
                                 'killing both attackers. The Horror returns to the grave and '
                                 'Quick Fix returns to hand, but the next refill is only one '
                                 'ether. Repair the other corpse, the Razor Man: its printed '
                                 'eleven power supplies the exact remaining damage. Reviving the '
                                 'Razor Man first cannot combine a sufficiently large finish with '
                                 'both Horror waves before the lethal reply.',
                  'explanation_ru': 'Быстрая Починка возвращает Ходячий ужас существом 8/8; его '
                                    'появление наносит каждому врагу три урона. Альфа-удар '
                                    'добавляет девять печатной силы: получается семнадцать. '
                                    'Сожжение расходует пятый эфир, наносит герою семнадцать и '
                                    'запускает вторую волну на три, убивая обоих врагов. Ужас '
                                    'возвращается в могильник, а Быстрая Починка — в руку, но '
                                    'следующее пополнение даёт лишь один эфир. Примените Ремонт к '
                                    'другому телу, Потрошителю: его одиннадцать печатной силы дают '
                                    'ровно недостающий урон. Начав с Потрошителя, нельзя '
                                    'совместить достаточный урон герою и обе волны Ужаса до '
                                    'смертельного ответа.',
                  'hero_names': ['The Last Mechanist', 'The Winged Executioner'],
                  'hero_names_ru': ['Последний механик', 'Крылатый палач']},
 'glass_furnace': {'title': 'Glass Furnace',
                   'title_ru': 'Стеклянная печь',
                   'category': 'A defensive investment and a returned spell',
                   'category_ru': 'Вложение в защиту и возвращённое заклинание',
                   'briefing': 'Win within two turns. Burnout is active. Your Carnivorous Fingus '
                               'carries Strong Attack; the enemy Giant Bat carries Strength. You '
                               'have six ether now, three channels, and one hero health.',
                   'briefing_ru': 'Победите за два хода. На вас действует Сожжение. На Плотоядном '
                                  'фингусе лежит Усиление Атаки, на вражеской Гигантской летучей '
                                  'мыши — Усиление. Сейчас есть шесть единиц эфира, три канала и '
                                  'одна жизнь героя.',
                   'hints': ['One creature must supply damage now; the other must survive the '
                             'enemy turn before becoming the final source of damage.',
                             'Delusion returns to your hand when its holder leaves play. Shield of '
                             'Force can fund the later attack through a different statistic, but '
                             'the nine-power flyer still needs a surviving blocker.',
                             'Give the Wall of Lava a three-point Shield of Force. Delude the '
                             'Fingus and release its six-power spores at the enemy. Block the Bat '
                             'with the wall if it attacks. Next turn, Delude the wall and Burnout '
                             'its eleven power into the enemy hero.'],
                   'hints_ru': ['Одно существо должно нанести урон сейчас; другое — пережить ход '
                                'врага и стать последним источником урона.',
                                'Перестановка возвращается в руку, когда её носитель покидает '
                                'поле. Щит Силы может обеспечить будущий урон через другую '
                                'характеристику, но летуна с силой девять ещё нужно пережить.',
                                'Дайте Стене лавы Щит Силы на три. Примените Перестановку к '
                                'фингусу и направьте его споры силой шесть в героя. Если мышь '
                                'атакует, блокируйте её стеной. На следующем ходу Перестановка '
                                'превратит стену в источник одиннадцати урона для Сожжения.'],
                   'explanation': 'Shield of Force costs one plus three ether and changes the Wall '
                                  'of Lava from 1/8 to 1/11. Delusion spends the other two ether '
                                  'and turns the 1/6 Fingus into 6/1; its spores deal six and '
                                  "return Delusion. The wall survives the Bat's nine-point attack, "
                                  'and its wounds clear normally. On the second turn, the '
                                  'three-ether refill pays for Delusion and one Burnout '
                                  'activation. The wall becomes 11/1 and supplies the last eleven '
                                  'damage. Shielding the Fingus makes the first shot larger but '
                                  'leaves no defender that survives the Bat. Sacrificing the wall '
                                  'first leaves the hero exposed.',
                   'explanation_ru': 'Щит Силы стоит один плюс три эфира и превращает Стену лавы '
                                     'из 1/8 в 1/11. Оставшиеся два эфира оплачивают Перестановку: '
                                     'фингус 1/6 становится 6/1. Его споры наносят шесть, а '
                                     'Перестановка возвращается в руку. Стена переживает девять '
                                     'урона от мыши; её раны затем исчезают по обычным правилам. '
                                     'На втором ходу три эфира оплачивают Перестановку и одно '
                                     'применение Сожжения. Стена становится 11/1 и наносит '
                                     'последние одиннадцать. Щит на фингусе усиливает первый '
                                     'выстрел, но оставляет армию без защитника, способного '
                                     'пережить удар мыши. Жертва стены в первом ходе открывает '
                                     'самого героя.',
                   'hero_names': ['The Glassworker', 'The Night Hunter'],
                   'hero_names_ru': ['Стекольщик', 'Ночной охотник']},
 'last_funeral': {'title': 'The Last Funeral',
                  'title_ru': 'Последние похороны',
                  'category': 'A forced attack, precise blocks and a counterstroke',
                  'category_ru': 'Вынужденная атака, точные блоки и контрудар',
                  'briefing': 'Win within two turns. Fury already forces the opposing creatures to '
                              'attack. The Reinforced Pteros carries Shell Skin and has no ether '
                              'for its active dispel. Your hero has three health, four ether and '
                              'four channels; both graveyards are empty.',
                  'briefing_ru': 'Победите за два хода. Бешенство уже заставляет врагов атаковать. '
                                 'На Армированном птеросе лежит Ледяной Панцирь; эфира для '
                                 'активного рассеивания у него нет. У героя три жизни, четыре '
                                 'эфира и четыре канала; оба могильника пусты.',
                  'hints': ['Winning the defence is only half the problem. The finishing turn '
                            'needs both surviving attack power and a corpse worth returning.',
                            'The Pteros dispels on a combat hit. A stronger wall alone loses its '
                            'enhancement before it can strike back. Alpha Strike solves that '
                            'problem, but its holder will die when the enemy turn ends.',
                            'Give Alpha Strike to the Wall of Blades and Strength to the Great '
                            'Treant. Block the Pteros with the wall, the Tick with the Treant, and '
                            'the Ogre with the Fire Elemental. Next turn, Repair the wall before '
                            'Burning Graves, then attack with the Treant and Elemental.'],
                  'hints_ru': ['Успешная защита — лишь половина задачи. Для завершающего хода '
                               'нужны и живые атакующие, и подходящее тело для возвращения.',
                               'Птерос рассеивает чары боевым ударом. Просто усиленная стена '
                               'потеряет прибавку до своего ответа. Альфа-удар решает эту '
                               'проблему, но его носитель погибнет в конце хода врага.',
                               'Дайте Альфа-удар Стене лезвий, а Усиление — Старому древню. Стеной '
                               'блокируйте птероса, древнем — клеща, Элементалем огня — людоеда. '
                               'На следующем ходу примените Ремонт к стене перед Пылающими '
                               'Могилами, затем атакуйте древнем и элементалем.'],
                  'explanation': 'The alpha-striking wall has twelve power and kills the '
                                 'ten-toughness Pteros before its dispelling hit. Strength makes '
                                 'the Treant 7/3, enough to survive and kill the Tick. The Fire '
                                 'Elemental first-strikes the Ogre. The wall then dies when Alpha '
                                 'Strike expires, while both ground attackers survive. Repair '
                                 'removes that sole friendly grave card and deals six; Burning '
                                 'Graves now deals nine to the opponent without killing your '
                                 'three-health hero. The Treant and Elemental supply the remaining '
                                 'seven plus six in combat: twenty-eight total. General Haste '
                                 'leaves too little finishing damage; Alpha Strike on the Treant '
                                 "leaves the wall vulnerable to the Pteros's dispel.",
                  'explanation_ru': 'Стена с Альфа-ударом имеет двенадцать силы и убивает птероса '
                                    'со стойкостью десять до его рассеивающего удара. Усиление '
                                    'делает древня существом 7/3: он переживает клеща и убивает '
                                    'его. Элементаль огня первым ударом уничтожает людоеда. Затем '
                                    'Альфа-удар заканчивается и убивает стену, но оба наземных '
                                    'бойца остаются живы. Ремонт убирает единственную карту из '
                                    'вашего могильника и наносит шесть. Пылающие Могилы наносят '
                                    'врагу девять, не убивая героя с тремя жизнями. Древень и '
                                    'элементаль добавляют в бою семь и шесть: всего двадцать '
                                    'восемь. Общая Спешка не оставляет достаточного урона для '
                                    'завершения; Альфа-удар на древне оставляет стену уязвимой к '
                                    'рассеиванию птероса.',
                  'hero_names': ['The Bone Strategist', 'The Siege Captain'],
                  'hero_names_ru': ['Костяной стратег', 'Капитан осады']},
 'two_doors': {'title': 'Two Doors, One Key',
               'title_ru': 'Две двери — один ключ',
               'category': 'Planar shelter, health conversion and reply denial',
               'category_ru': 'Укрытие в другом плане, смена здоровья и запрет ответа',
               'briefing': 'Win within two turns. Transfer Aspects is active. Your Pale Knight has '
                           'just been summoned into the Ether and cannot use its own dissipation '
                           'yet; your Invoker and the enemy Knight are in the Colourless Plane. '
                           'The enemy has Polymorph and will refill one ether on its turn.',
               'briefing_ru': 'Победите за два хода. На вас действует Обмен Планами. Ваш '
                              'Бесцветный Рыцарь только что призван в Эфирный План и пока не может '
                              'сам уйти в Бесцветный; ваш Чародей и вражеский Рыцарь находятся в '
                              'Бесцветном Плане. У врага есть Превращение и один канал для '
                              'следующего пополнения.',
               'hints': ['The first exchange has to do two jobs: make a valuable spell target '
                         "accessible and keep your future attacker safe from the enemy's answer.",
                         "Polymorph sets your health to the victim's power plus toughness. "
                         'Exchange does not require its participants to be ready. Save Alpha '
                         'Strike for the second turn, when it can produce an attack.',
                         'Exchange the enemy Knight into the Ether and your own Knight into the '
                         'Colourless Plane, then Polymorph the enemy Knight. Next turn, drain any '
                         'remaining enemy ether with the Invoker. Exchange your Knight out and the '
                         'wall in, then Alpha Strike and attack. If the enemy Polymorphed its own '
                         'wall, exchange its remaining Mechos instead.'],
               'hints_ru': ['Первый обмен должен одновременно открыть ценную цель для заклинания и '
                            'спасти будущего атакующего от вражеского ответа.',
                            'Превращение устанавливает здоровье по сумме силы и стойкости жертвы. '
                            'Для Обмена Планами готовность существ не нужна. Сохраните Альфа-удар '
                            'до второго хода, когда сможете действительно атаковать.',
                            'Обменяйте планы вражеского и своего Рыцарей, затем примените '
                            'Превращение к вражескому. На следующем ходу Чародеем заберите '
                            'оставшийся у врага эфир. Обменяйте планы своего Рыцаря и стены, '
                            'примените Альфа-удар и атакуйте. Если враг превратил свою стену, '
                            'отправьте в Бесцветный План оставшегося мехоса.'],
               'explanation': 'The first exchange spends one ether and protects the still-sick '
                              'Knight without asking it to activate an ability. Polymorph spends '
                              'the other ether and sets your health to sixteen; you can survive '
                              "the Mechos's eight-point attack. The second refill is three: one "
                              'for another exchange and two for Alpha Strike. With the wall '
                              'hidden, the sixteen-power trampling Knight deals at least ten '
                              'through a six-toughness Mechos. If Polymorph remains in the enemy '
                              'hand, the Invoker drains its one ether and deals the one point that '
                              'reduces eleven health to ten. If the enemy instead spends Polymorph '
                              'on a friendly creature, its maximum resulting health is fourteen '
                              'and the remaining blocker can be exchanged away. A different first '
                              'Polymorph target leaves the enemy Knight available to obstruct or '
                              'heal, while spending Alpha Strike early loses the required '
                              'finishing power.',
               'explanation_ru': 'Первый обмен расходует один эфир и укрывает ещё неготового '
                                 'Рыцаря без применения его собственной способности. Превращение '
                                 'тратит второй эфир и устанавливает здоровье на шестнадцати: '
                                 'этого хватает, чтобы пережить удар мехоса на восемь. Следующее '
                                 'пополнение даёт три — один на новый обмен и два на Альфа-удар. '
                                 'После исчезновения стены Рыцарь с силой шестнадцать и пробивным '
                                 'ударом наносит не меньше десяти сквозь мехоса со стойкостью '
                                 'шесть. Если Превращение осталось у врага, Чародей забирает '
                                 'единственный эфир и снимает одну жизнь: из одиннадцати '
                                 'получается десять. Если враг сам потратил Превращение на своё '
                                 'существо, итоговое здоровье не превышает четырнадцати, а '
                                 'оставшегося защитника можно убрать обменом. Иная первая цель '
                                 'Превращения оставляет вражеского Рыцаря для защиты или лечения, '
                                 'а ранний Альфа-удар лишает завершающей силы.',
               'hero_names': ['The Gatekeeper', 'The Keeper of Bodies'],
               'hero_names_ru': ['Привратник', 'Хранитель тел']},
 'venom_clock': {'title': 'The Venom Clock',
                 'title_ru': 'Часы яда',
                 'category': 'A poison clock, reserves and ordered blocks',
                 'category_ru': 'Ядовитый отсчёт, резерв и порядок блоков',
                 'briefing': 'Win within three turns. You have one hero health, five ether and no '
                             'channels. Your Gray Ogre is resting. The enemy Bat is poisonous, the '
                             'Lamia Warlord has first strike and trample, and the enemy can afford '
                             'Haste after its next refill.',
                 'briefing_ru': 'Победите за три хода. У вас одна жизнь героя, пять эфира и ни '
                                'одного канала. Серый людоед отдыхает. Вражеская мышь ядовита, '
                                'Ламия-повелительница обладает первым и пробивным ударами, а '
                                'следующее пополнение позволит врагу применить Спешку.',
                 'hints': ['The Snake supplies a growing clock. The resting Ogre is your next-turn '
                           'reserve: preserving it changes which attacks the enemy can afford to '
                           'make.',
                           'Cloak of Fear on the Snake and Shell Skin on the air wall leave one '
                           'ether. That reserve can regenerate the Wall of Blades after poison on '
                           'the first enemy turn. Do not offer the Ogre to a ready first-striking '
                           'blocker.',
                           'Cloak the Snake; armor Air. Attack with Snake every turn. If Bat alone '
                           'attacks first, Blades blocks and regenerates. If both attack first, '
                           'Air blocks Bat and Blades blocks Lamia; counterattack with Snake and '
                           'Ogre. Keep Ogre against a ready first striker. For a later combined '
                           'attack, Blades blocks Bat; Air FIRST and Ogre SECOND block Lamia. If '
                           'the enemy delays, retain the reserve and let venom finish.'],
                 'hints_ru': ['Змея запускает растущий отсчёт. Отдыхающий людоед — резерв '
                              'следующего хода: сохранив его, вы меняете то, какие атаки может '
                              'позволить себе враг.',
                              'Маска Ужаса на змее и Ледяной Панцирь на воздушной стене оставляют '
                              'один эфир. В первый вражеский ход этот запас может оплатить '
                              'регенерацию Стены лезвий после яда. Не отдавайте людоеда готовому '
                              'блокирующему с первым ударом.',
                              'Дайте змее Маску Ужаса, воздушной стене — Ледяной Панцирь. Атакуйте '
                              'змеёй каждый ход. Первую отдельную атаку мыши примите лезвиями и '
                              'регенерируйте. Если сначала атакуют оба, воздушная стена блокирует '
                              'мышь, лезвия — ламию; затем контратакуйте змеёй и людоедом. '
                              'Сохраняйте людоеда против готового первого удара. В поздней общей '
                              'атаке лезвия блокируют мышь, воздушная стена ПЕРВОЙ и людоед ВТОРЫМ '
                              '— ламию. Если враг медлит, держите резерв и дождитесь яда.'],
                 'explanation': 'Cloak the Snake and give Shell Skin to the Wall of Air. Keep the '
                                'Ogre and the last ether for Blades to regenerate through poison '
                                'on the first enemy turn. Three Snake hits plus venom ticks of '
                                'one, two and three total nine.\n'
                                '\n'
                                'First reply: against Bat alone, Blades blocks, kills and '
                                'regenerates; against Lamia alone, Blades holds. Against both, Air '
                                'takes Bat and Blades takes Lamia: both enemies then rest, '
                                'allowing Snake plus Ogre to finish on turn two. If neither '
                                'attacks, preserve the army.\n'
                                '\n'
                                'Later, hold the Ogre whenever a ready first striker could kill '
                                'it. Against both attackers, assign Blades to Bat; assign Air '
                                'FIRST and Ogre SECOND to Lamia. Air absorbs six damage; Ogre '
                                'survives the remaining two. Against Bat alone, Blades can trade, '
                                'leaving Air and Ogre to cover Lamia. Against Lamia alone, use '
                                'Blades while it remains available.\n'
                                '\n'
                                'Attack with the Ogre when safe. Otherwise preserve the defence '
                                'and let the third venom tick finish. The reference demonstrates '
                                'the delayed combined attack.',
                 'explanation_ru': 'Дайте змее Маску Ужаса, Стене воздуха — Ледяной Панцирь. '
                                   'Сохраните людоеда и последний эфир для регенерации Стены '
                                   'лезвий после яда в первом вражеском ходе. Три удара змеи и '
                                   'срабатывания яда на один, два и три дают девять.\n'
                                   '\n'
                                   'Первый ответ: одну мышь блокируют лезвия, убивают её и '
                                   'регенерируют; одну ламию также держат лезвия. Если атакуют '
                                   'оба, воздушная стена принимает мышь, лезвия — ламию. Оба врага '
                                   'начинают отдыхать: на втором ходу змея и людоед добивают '
                                   'героя. Если никто не атакует, сохраняйте армию.\n'
                                   '\n'
                                   'Позже придерживайте людоеда, если готовый первый удар может '
                                   'его убить. Против общей атаки назначьте лезвия на мышь, '
                                   'воздушную стену ПЕРВОЙ и людоеда ВТОРЫМ на ламию. Стена '
                                   'принимает шесть урона; людоед переживает оставшиеся две '
                                   'единицы. Против одной мыши лезвия могут разменяться, оставив '
                                   'воздушную стену и людоеда для ламии. Одну ламию держите '
                                   'лезвиями, пока они остаются в строю.\n'
                                   '\n'
                                   'Атакуйте людоедом, когда это безопасно. Иначе сохраняйте '
                                   'защиту до третьего срабатывания яда. Пример показывает '
                                   'задержанную общую атаку. Раннее Самопожертвование не '
                                   'гарантирует победу: враг может дождаться окончания временного '
                                   'усиления.',
                 'hero_names': ['The Patient Venomist', 'The Venom Cavalry'],
                 'hero_names_ru': ['Терпеливый отравитель', 'Ядовитая конница']}}
