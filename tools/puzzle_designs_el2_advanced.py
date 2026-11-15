"""Advanced EL2 studies: control, defensive conversion, forced choices and timing."""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end


def puzzles():
    game = "el2"
    out = []

    out.append(puzzle(game, "chain_of_custody", "Chain of Custody", "Control and retained auras", 2, 1,
        state(game,
            hero("Blue", [], mana=9, health=8),
            hero("Green", [], health=30, enchantments=[enchant("ENWO", id=2), enchant("STWO", id=3)]),
            [unit("OUE1", 2, plane=True), unit("OUE3", 3, plane=True),
             # Stored health must already include the two real hero auras for restore.
             unit("CTMN", 4, 1, origin=0, resting=True, damage=4, power=9, toughness=6, enchantments=[enchant("CHCM", id=1, owner=1)]),
             unit("RZMN", 5, 1, resting=True, damage=8, power=13, toughness=10)]),
        "Finish this turn controlling both the wounded Cutter Man and Razor Man, with both still alive. The Cutter originally belonged to you. Two enemy army enchantments keep the captives stronger than their printed bodies.",
        ["Your two Pale casters do different things with an enchantment: one refunds it, the other returns it as a card.",
         "Both woodland auras cost four, but removing their toughness bonus kills the wounded captives. Changing control preserves the army auras they already carry.",
         "Absorb Strength of Woods. Transpose Change of Command from the Cutter, returning it to you and placing the spell in your hand. Cast that recovered Change of Command on the Razor Man."],
        "Absorbing Strength of Woods spends one ether and refunds four, raising your pool from nine to twelve. Endurance of the Woods must remain: both captives have lethal damage without its two toughness. Transposition costs seven, removes the enemy's Change of Command, and gives you that card. The Cutter returns to its original owner while retaining the endurance aura; the remaining five ether captures the Razor Man. Absorbing the command instead loses the only control spell, while transposing a woodland aura gives the wrong card.",
        [ability(2, "absorb", 1, choice=3), ability(3, "transpose", 4, choice=1), cast("CHCM", 5)],
        objective={"type": "control", "targets": [4, 5]},
        refutations=[
            {"label": "Refund the toughness aura instead of the power aura", "commands": [ability(2, "absorb", 1, choice=2)]},
            {"label": "Absorb the control spell instead of recovering its card", "commands": [ability(2, "absorb", 4, choice=1)]},
            {"label": "Transpose Strength of Woods", "commands": [ability(3, "transpose", 1, choice=3)]},
        ]))

    out.append(puzzle(game, "last_line_of_defence", "The Last Line of Defence", "Defensive resource allocation", 3, 1,
        state(game,
            hero("Red", ["PLMR", "ENAL"], mana=3, health=3, enchantments=[enchant("CMBN", id=1)]),
            hero("Blue", [], health=40),
            [unit("WLLV", 2), unit("FREL", 3), unit("CTMN", 4, resting=True),
             unit("BLDG", 5, 1), unit("GROG", 6, 1, enchantments=[enchant("SPBA", id=2)]), unit("TIWR", 7, 1, enchantments=[enchant("SPBA", id=3)])],
            phase=1, attacker=1, attacks=[5, 6, 7]),
        "Clear the attacking army while keeping your Wall of Lava and Fire Elemental alive. Martyrdom is already active. You have three ether. The enemy Ogre and Tick Warrior both carry Spirit of the Basilisk: any creature they wound in combat is doomed.",
        ["Budget for three different jobs: remove an attacker, strengthen a blocker, and reach an exact damage threshold.",
         "The resting Cutter can contribute its full power and toughness without waking up. The wall must handle the flying Dragon; your Elemental can kill a poisonous attacker before it deals a wound.",
         "Use Martyrdom to sacrifice the Cutter into the Wall of Lava. Polymorph one of the two poisonous ground attackers. Spend one ether on the wall's power ability, then block the Dragon with the wall and the remaining ground attacker with your Elemental."],
        "Martyrdom spends one ether to turn the wall from 1/8 into 8/12 using the Cutter's 7/4 body. One more ether makes the wall 9/12, enough to kill the 8/9 Black Dragon and survive. Polymorph removes one poisonous ground attacker; your own Fire Elemental first-strikes the other before receiving a lethal wound. Either ground creature is a valid spell target. Removing the Dragon instead leaves two poisonous attackers, and the wall cannot survive a wound from either. All three ether have distinct jobs: sacrifice, transformation, and the final point of power.",
        [ability(0, "combine:1", 4, choice=2), cast("PLMR", 6), ability(2, "lava_power", amount=1),
         block(2, 5), block(3, 7), end()],
        objective={"type": "clear", "protect": [2, 3]},
        refutations=[
            {"label": "Polymorph the largest attacker", "commands": [cast("PLMR", 5)]},
            {"label": "Combine the Cutter into your Fire Elemental", "commands": [ability(0, "combine:1", 4, choice=3)]},
            {"label": "Spend the entire pool on the wall's power", "commands": [ability(2, "lava_power", amount=3)]},
        ]))

    out.append(puzzle(game, "every_road_hurts", "Every Road Hurts", "Forced blocks and a response window", 3, 1,
        state(game, hero("Black", ["IRRT", "PALN", "ZAPP"], mana=5, health=8),
            hero("Blue", [], mana=3, health=7),
            [unit("WKHR", 2), unit("AVAS", 3), unit("WLFC", 4, 1), unit("PTRS", 5, 1)]),
        "Win this turn against every arrangement of the two blockers. The Pteros has enough ether to remove Pain Link during defence. The Assassin can only be blocked by the wall.",
        ["You need both attackers. Nine trample damage alone has a defensive answer, and the Assassin alone is too small.",
         "Make the wall painful to use, then make sure that enchantment survives the defender's action window.",
         "Irritate the Pteros, put Pain Link on the Wall of Force, and attack with both creatures. Even a double block ordered Pteros first, wall second leaves five linked damage plus two from the Assassin."],
        "Irritation prevents the Pteros from using its dispel, preserving Pain Link. With both attackers declared, the defender cannot avoid seven damage. A wall block on the Assassin deals two through Pain Link and leaves at least five trample damage from the Horror. Blocking the Horror with the Pteros first and then the wall absorbs four before the wall takes five; the unblocked Assassin supplies the other two. A lone Pteros block also lets five trample damage through. Pain Link on the Pteros instead can be avoided by putting the wall in front of the Horror.",
        [cast("IRRT", 5), cast("PALN", 4), attack(2), attack(3), end(),
         block(5, 2, side=1), block(4, 2, side=1), end(side=1)],
        refutations=[
            {"label": "Put Pain Link on the smaller blocker", "commands": [cast("PALN", 5)]},
            {"label": "Suppress the wall rather than the dispeller", "commands": [cast("IRRT", 4)]},
            {"label": "Spend one ether on immediate hero damage", "commands": [cast("ZAPP", 1)]},
        ]))

    out.append(puzzle(game, "three_turn_lock", "A Three-Turn Lock", "Denial, upkeep and reserve defence", 3, 3,
        state(game, hero("Blue", ["STSI", "IRRT", "WEAK", "FOGG"], mana=6, health=3),
            hero("Red", ["FOGG", "CLIG"], mana=0, channels=5, health=8),
            [unit("AVAS", 2), unit("RKWL", 3), unit("ORSH", 4, 1), unit("GRTN", 5, 1)]),
        "Win within three turns. Your Assassin needs repeated attacks. The enemy's five channels would fund Fog and Lightning, and its Shaman can remove an enchantment without spending ether. Your own channels are empty.",
        ["Deny the enemy its next refill, but first account for the creature that can remove that denial.",
         "The last two ether are an upkeep reserve. Spending them on a tempting extra spell releases the lock one enemy turn too soon.",
         "Irritate the Shaman and cast Stasis, retaining two ether. Attack with the Assassin on all three turns. Keep the wall for the Treant; the Shaman's two one-point attacks can be endured. The first Stasis upkeep is paid, and the later expiry occurs after the last enemy refill you need to prevent."],
        "Irritation disables the Shaman's channel-sacrificing dispel and deals one damage to its hero at each enemy turn end. Stasis holds both ether pools at their current values. Keeping two ether pays the first upkeep, so the enemy remains unable to cast either defensive card through the second attack and following turn. The next upkeep cannot be paid, but the enemy is still at zero during your final attack. Three two-point Assassin hits plus two Irritation triggers total eight. The wall stops the Treant, and your three health tolerates the Shaman's two attacks.",
        [cast("IRRT", 4), cast("STSI"), attack(2), end(), end(side=1),
         attack(4, side=1), attack(5, side=1), end(side=1), block(3, 5), end(),
         attack(2), end(), end(side=1), attack(4, side=1), attack(5, side=1), end(side=1), block(3, 5), end(),
         attack(2), end(), end(side=1)],
        objective={"type": "win", "protect": [2]},
        refutations=[
            {"label": "Suppress the Treant instead of the Shaman", "commands": [cast("IRRT", 5)]},
            {"label": "Spend the upkeep reserve weakening the Treant", "commands": [cast("WEAK", 5)]},
            {"label": "Invest in Fog before creating the lock", "commands": [cast("FOGG")]},
        ]))

    out.append(puzzle(game, "third_funeral", "The Third Funeral", "Burial order and delayed reinforcements", 3, 2,
        state(game,
            hero("Black", ["PLMR"], mana=1, channels=1, health=4, grave=["MXHP", "STRT"],
                 enchantments=[enchant("FURY", id=1)]),
            hero("Green", ["PLMR"], mana=1, channels=0, health=17),
            [unit("CTMN", 2, resting=True, enchantments=[enchant("ALST", id=2, power=7), enchant("ENBR", id=3), enchant("IRRT", id=4, owner=1)]),
             unit("WKHR", 3), unit("GRTN", 4, resting=True, enchantments=[enchant("ALST", id=5, power=3)]),
             unit("ORSH", 5, enchantments=[enchant("SHSK", id=6)]),
             unit("GRTN", 6, 1, resting=True), unit("STRT", 7, 1)]),
        "Win in two turns and keep your Orc Shaman alive. Both Alpha Strikes expire at the end of the enemy's next turn. A Maxi Hopper lies beneath one card in your graveyard; it returns at your turn end only after three newer burials.",
        ["The first attack and the finishing attack need different bodies. Reconstruct the graveyard before committing either.",
         "A regeneration that seems to save an ally can spend the only ether needed for Polymorph. The Horror's departure also forces the enemy to spend its last ether regenerating.",
         "Use the Shaman's rite to remove Irritation from the Cutter. Polymorph your resting, fragile Treant before the Horror dies. Then let the Cutter sacrifice the Horror and attack for fourteen. The Hopper returns at turn end; use your reserve to block the compelled Treant attack, then finish with the Hopper."],
        "The Shaman spends your channel to free the Cutter's sacrifice ability. Polymorph kills your own Treant without regeneration, preserving the sequence and adding the second newer grave card. The Cutter sacrifices the Horror, wakes up, and the third newer burial qualifies the Hopper to return at turn end. Energy Barrier keeps the Cutter's one-toughness Alpha Strike body alive through the Horror's wave. The enemy Treant must regenerate, spending the ether that would otherwise fund defensive Polymorph. The Cutter deals fourteen, then expires after the enemy turn; the returned Hopper supplies the final three. Fury forces the enemy Treant to commit, creating the finishing opening.",
        [ability(5, "orc_rite", 2, choice=4), cast("PLMR", 4), ability(2, "sacrifice", 3),
         attack(2), end(), end(side=1), end(side=1), block(8, 6), end(), attack(8), end(), end(side=1)],
        objective={"type": "win", "protect": [5]},
        refutations=[
            {"label": "Release the Horror's wave before spending the Polymorph ether", "commands": [ability(5, "orc_rite", 2, choice=4), ability(2, "sacrifice", 3)]},
            {"label": "Polymorph the enemy Treant instead of your own", "commands": [cast("PLMR", 6)]},
            {"label": "Remove Energy Barrier instead of Irritation", "commands": [ability(5, "orc_rite", 2, choice=3)]},
        ]))

    out.append(puzzle(game, "beneath_the_numbers", "Beneath the Numbers", "Printed strength and specialist removal", 2, 1,
        state(game, hero("Green", ["TWST"], mana=5, health=3),
            hero("Blue", [], mana=1, health=40),
            [unit("BUDG", 2), unit("GRDG", 3),
             unit("TNSA", 4, 1, enchantments=[enchant("BLSS")]),
             unit("WNMG", 5, 1, enchantments=[enchant("WEAK")]), unit("WLFC", 6, 1)]),
        "Clear the enemy army this turn. Your hero has only three health. Twister hurts the attacking hero according to its victim's strength without the victim's own enchantments.",
        ["The visually weakest enemy is not the safest Twister target.",
         "Your dragons already have answers to a flying body and a wall. Keep the spell for the remaining kind of threat.",
         "Twister the blessed Treant, whose printed power is one. Use the Blue Dragon's breath on the weakened Maggot and the Green Dragon's wall-breaking ability on the Wall of Force."],
        "Twister ignores Bless when calculating its recoil, so the five-power Treant costs only one hero health and cannot regenerate. The Maggot displays zero power, but its unenchanted power is three: Twister would kill you. Blue Dragon breath handles it without recoil, and Green Dragon removes the wall. Using Twister on the wall is safe for your health but leaves no way to clear the regenerating ground creature this turn.",
        [cast("TWST", 4), ability(2, "breath"), ability(3, "wall_break", 6)],
        objective={"type": "clear"},
        refutations=[
            {"label": "Twister the enemy displaying zero power", "commands": [cast("TWST", 5)]},
            {"label": "Spend Twister on the wall to avoid all recoil", "commands": [cast("TWST", 6)]},
        ]))
    for entry in out:
        localized = dict(_LOCALIZED[entry["id"].removeprefix("el2_tactical_v2_")])
        entry.update(localized)
    return out


_LOCALIZED = {
    "chain_of_custody": {
        "title_ru": "Цепочка подчинения",
        "category_ru": "Переподчинение и сохранённые ауры",
        "briefing_ru": "До конца этого хода возьмите под контроль раненых Раскройщика и Потрошителя, сохранив обоих в живых. Раскройщик изначально принадлежал вам. Две чары на вражеском герое усиливают его армию.",
        "hints_ru": [
            "Два ваших бесцветных мага по-разному используют чужие чары: один возвращает эфир, другой — само заклинание.",
            "Обе лесные ауры стоят четыре, но снятие прибавки к стойкости убьёт раненых пленников. При смене стороны существо сохраняет уже действующие на него ауры армии.",
            "Чароедом поглотите Силу Леса. Ловкачом снимите Переподчинение с Раскройщика и получите его карту. Раскройщик вернётся к вам; полученное Переподчинение примените к Потрошителю.",
        ],
        "explanation_ru": "Поглощение Силы Леса тратит один эфир и возвращает четыре: запас растёт с девяти до двенадцати. Стойкость Леса должна остаться: без её прибавки в два пункта раны обоих пленников станут смертельными. Способность Ловкача стоит семь, снимает Переподчинение и даёт вам его карту. Раскройщик возвращается к исходному владельцу, сохраняя ауру стойкости; оставшихся пяти единиц эфира хватает на Потрошителя. Если поглотить само Переподчинение, вы потеряете единственный способ захватить второго пленника. Снятие лесной ауры Ловкачом даст не ту карту.",
    },
    "last_line_of_defence": {
        "title_ru": "Последний рубеж",
        "category_ru": "Распределение ресурсов в защите",
        "briefing_ru": "Уничтожьте атакующую армию, сохранив Стену лавы и своего Элементаля огня. Самопожертвование уже действует. У вас три единицы эфира. На вражеских Огре и Клеще-воине лежит «Призрак Василиска»: любое существо, которое они ранят в бою, обречено.",
        "hints_ru": [
            "Эфир нужен для трёх разных задач: убрать атакующего, усилить защитника и достичь точного порога урона.",
            "Отдыхающий Раскройщик может передать всю свою силу и стойкость, не просыпаясь. Стена должна встретить летающего дракона, а Элементаль — убить ядовитого атакующего первым ударом, не получив раны.",
            "Самопожертвованием передайте характеристики Раскройщика Стене лавы. Превратите одного из двух ядовитых наземных атакующих. За последний эфир увеличьте силу стены на один; ею блокируйте дракона, а Элементалем — оставшегося наземного атакующего.",
        ],
        "explanation_ru": "Самопожертвование за один эфир прибавляет к стене 1/8 характеристики Раскройщика 7/4: получается 8/12. Ещё один эфир поднимает силу до девяти, чтобы убить Чёрного дракона 8/9 и пережить его удар. Превращение убирает одного ядовитого наземного врага; Элементаль огня первым ударом уничтожает второго до ответной раны. Превратить можно любого из них. Если убрать дракона, останутся два ядовитых врага, а стена не переживёт рану ни от одного. Каждый квант эфира решает отдельную задачу: жертва, превращение и последний пункт силы.",
    },
    "every_road_hurts": {
        "title_ru": "Цена каждой преграды",
        "category_ru": "Вынужденная защита и окно ответа",
        "briefing_ru": "Победите за этот ход при любом распределении двух защитников. У Птероса достаточно эфира, чтобы снять Болевую Связь во время защиты. Авиака-убийцу может блокировать только стена.",
        "hints_ru": [
            "Нужны оба атакующих. От девяти единиц избыточного урона можно защититься, а одного авиака слишком мало.",
            "Сделайте использование стены болезненным и позаботьтесь, чтобы эти чары пережили окно ответных действий врага.",
            "Раздражением отключите способность Птероса, наложите Болевую Связь на Стену силы и атакуйте обоими. Даже если Птерос блокирует Ужас первым, а стена второй, пять урона через связь и два от авиака решат бой.",
        ],
        "explanation_ru": "Раздражение лишает Птероса способности снять Болевую Связь. При атаке обоими существами враг не может избежать семи урона. Блок авиака стеной даёт два урона через связь, а Птерос пропускает ещё пять избыточного урона Ужаса. Если поставить Птероса перед Ужасом первым, а стену второй, Птерос поглотит четыре, стене достанется пять, а неблокированный авиак нанесёт ещё два. Один Птерос тоже пропускает пять. Если связать Птероса вместо стены, враг может безболезненно остановить Ужас стеной.",
    },
    "three_turn_lock": {
        "title_ru": "Три хода Стазиса",
        "category_ru": "Блокада эфира и запас на содержание",
        "briefing_ru": "Победите за три хода. Авиаку придётся атаковать несколько раз. Пять каналов врага обеспечили бы Туман и Молнию, а его шаман умеет снимать чары без затрат эфира. У вас нет своих каналов.",
        "hints_ru": [
            "Остановите следующее пополнение вражеского эфира, но сначала разберитесь с существом, которое способно снять эту блокаду.",
            "Последние две единицы эфира нужны на содержание Стазиса. Лишнее заклинание снимет блокаду на один вражеский ход раньше, чем нужно.",
            "Наложите Раздражение на шамана и Стазис на своего героя, оставив два эфира. Атакуйте авиаком на каждом из трёх ходов. Стеной прикрывайте древня; два удара шамана по единице можно принять. Первое содержание оплачивается, а последующее снятие Стазиса происходит уже после последнего опасного пополнения врага.",
        ],
        "explanation_ru": "Раздражение отключает обряд шамана и в конце каждого вражеского хода наносит его герою единицу урона. Стазис сохраняет текущие запасы эфира вместо обычного пополнения. Два оставленных эфира оплачивают первое содержание: враг не может применить свои карты во время второй атаки и следующего хода. Второе содержание уже не оплачивается, но к вашей последней атаке у врага всё ещё ноль эфира. Три удара авиака по два и два срабатывания Раздражения дают ровно восемь. Стена останавливает древня, а три жизни позволяют пережить два удара шамана.",
    },
    "third_funeral": {
        "title_ru": "Третьи похороны",
        "category_ru": "Порядок погребений и позднее подкрепление",
        "briefing_ru": "Победите за два хода и сохраните Орка-шамана. Обе Альфа-атаки закончатся в конце следующего вражеского хода. Большой прыгун лежит под одной картой в вашем могильнике и вернётся в конце вашего хода лишь после трёх более поздних погребений.",
        "hints_ru": [
            "Первый удар и добивание должны выполнить разные существа. Восстановите будущий порядок могильника до начала атаки.",
            "Регенерация, которая кажется спасением союзника, может потратить единственный эфир для Превращения. Уход Ужаса также заставит врага потратить последний эфир на собственную регенерацию.",
            "Обрядом шамана снимите Раздражение с Раскройщика. Превратите своего отдыхающего хрупкого древня до смерти Ужаса. Затем Раскройщиком пожертвуйте Ужасом и атакуйте на четырнадцать. Прыгун вернётся в конце хода; заблокируйте вынужденную атаку древня резервом, а затем добейте врага Прыгуном.",
        ],
        "explanation_ru": "Шаман жертвует каналом, снимая запрет на способность Раскройщика. Превращение убивает вашего древня без регенерации и кладёт вторую новую карту поверх Прыгуна. Раскройщик жертвует Ужасом и просыпается; третье новое погребение позволит Прыгуну вернуться в конце хода. Энергетический Барьер защищает однопунктовую стойкость Раскройщика от прощальной волны Ужаса. Вражеский древень обязан регенерировать, тратя эфир, которым враг мог бы оплатить защитное Превращение. Раскройщик наносит четырнадцать и погибает после вражеского хода; вернувшийся Прыгун добавляет последние три. Бешенство заставляет вражеского древня атаковать и открывает путь для добивания.",
    },
    "beneath_the_numbers": {
        "title_ru": "Под маской чисел",
        "category_ru": "Базовая сила и точечное устранение",
        "briefing_ru": "Уничтожьте вражескую армию за этот ход. У вашего героя всего три жизни. Смерч ранит атакующего героя согласно силе жертвы без её собственных чар.",
        "hints_ru": [
            "Враг с самыми низкими видимыми характеристиками — не самая безопасная цель для Смерча.",
            "У драконов уже есть ответы на летающее существо и стену. Сохраните заклинание для угрозы другого типа.",
            "Примените Смерч к благословлённому Молодому древню: его базовая сила равна единице. Дыханием Синего дракона убейте ослабленного Маггота, а способностью Зелёного дракона уничтожьте Стену силы.",
        ],
        "explanation_ru": "При вычислении отдачи Смерч не учитывает Благословение. Поэтому древень с силой пять отнимет лишь одну жизнь и не сможет регенерировать. У Маггота показана нулевая сила, но без собственных чар она равна трём: его уничтожение Смерчем убьёт вашего героя. Дыхание Синего дракона устраняет Маггота без отдачи, а Зелёный дракон разбирает стену. Смерч по стене безопасен для героя, но оставляет регенерирующее наземное существо без подходящего ответа.",
    },
}
