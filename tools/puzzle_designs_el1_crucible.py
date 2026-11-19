"""Crucible: five compact expert lethal studies for Etherlords I.

Every goal is a normal hero victory. Resource scarcity, legal reaction windows,
blocking, and existing card interactions provide the difficulty. No new combat
rules or hidden restrictions are introduced. The lab replays and searches the
exact snapshots produced by these deterministic authoring functions.
"""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end


def puzzles():
    game='el1'
    out=[]
    out.append(puzzle(game,'crucible_buried_reserve','The Buried Reserve','Crucible · A sacrifice held across two battles',4,2,
     state(game,hero('Black',['OVRL','CLFR','SHSK','ENAL'],mana=4,channels=0,health=1,grave=['HOPR','STRT','KBSH']),hero('Blue',[],mana=0,health=22),
     [unit('CTMN',2,resting=True),unit('WLFC',3),unit('TIWR',4),unit('IRMZ',5,1),unit('BUDG',6,1)]),
     'Win within two turns. Your Cutter Man is resting. A Hopper lies beneath two newer creatures in your graveyard, and your four ether will not refill.',
     ['Reserve the creatures needed for the counterattack.','One more burial will return the Hopper at the turn boundary. The Cutter needs two separate sacrifices.','Feed the Tick to the Cutter, overload it and give it Cloak of Fear. Keep the returned Hopper; sacrifice it during your next defence, then block the Mechozaurus with the Cutter and the Dragon with the wall.'],
     "The first sacrifice places the third newer creature over the Hopper, which returns at the end of the turn. Overload and Cloak produce a twelve-point unblockable attack. The Cutter then decays to 10/7; sacrificing the returned Hopper readies it for defence. It survives the Mechozaurus's six damage and kills that attacker while the wall stops the flyer. Its last ten damage is exact: the dead Mechozaurus no longer drains its controller. If the Mechozaurus stays home, that four-health drain instead makes the final attack easier.",
     [ability(2,'sacrifice',4),cast('OVRL',2),cast('CLFR',2),attack(2),end(),end(side=1),attack(5,side=1),attack(6,side=1),end(side=1),ability(2,'sacrifice',7),block(2,5),block(3,6),end(),attack(2),end(),end(side=1)],
     refutations=[{'label':'Sacrifice the wall instead','commands':[ability(2,'sacrifice',3)]},{'label':'Spend three ether on Energize All','commands':[cast('ENAL')]}]))
    out.append(puzzle(game,'crucible_mortal_equation','A Mortal Equation','Crucible · A lethal with an exact life payment',4,1,
     state(game,hero('Green',['CHNL','PLMR','CLNP','ALST','STRG','ANHL','HUNG'],mana=3,health=2),hero('Blue',[],health=15),
     [unit('CTMN',2,resting=True,enchantments=[enchant('DELS',id=1)]),unit('GRTN',3,resting=True),unit('WLIL',4),unit('WLFC',5,1),unit('STMZ',6,1),unit('GRDG',7,1,enchantments=[enchant('STRG',id=2)])]),
     'Win this turn. You have three ether, two health, and no ready attacker. The Steel Mechozaurus is unaffected by magic; your Cutter carries Delusion.',
     ['Calculate both sides of Annihilation before choosing what to remove.','Ether Trade heals the enemy as well as funding you. Spending more life can put the enemy beyond your final damage.',"Polymorph the Green Dragon, trade six health, dispel the Cutter's Delusion, and give the Cutter Alpha Strike plus Strength. Annihilation now deals exactly twenty-one."],
     'Polymorph removes eleven opposing power and sets health to eight. Ether Trade at six leaves two health, provides ten ether and heals the enemy from fifteen to twenty-one. Lesser Disenchant, Alpha Strike, Strength and Annihilation cost exactly ten. The restored Cutter supplies eighteen power and the Treant three. The unaffected Mechozaurus contributes no Annihilation damage. Trading less cannot fund the line; trading more heals the enemy beyond twenty-one.',
     [cast('PLMR',7),cast('CHNL',power=6),cast('CLNP',2,grave=1),cast('ALST',2),cast('STRG',2),cast('ANHL')],
     refutations=[{'label':'Spend Lesser Disenchant on the enemy Strength','commands':[cast('CLNP',7,grave=2)]},{'label':'Trade only five health','commands':[cast('PLMR',7),cast('CHNL',power=5)]},{'label':'Trade seven health and heal the enemy too far','commands':[cast('PLMR',7),cast('CHNL',power=7)]}]))
    out.append(puzzle(game,'crucible_frozen_account','The Frozen Account','Crucible · Denial, upkeep and a defensive reserve',4,2,
     state(game,hero('Blue',['STSI','STRG','ENAL','SHSK','FLOD','SMOK'],mana=3,channels=0,health=1),hero('Red',['CLIG','PLMR'],mana=6,channels=6,health=18,enchantments=[enchant('ENVM',id=1,owner=0)]),
     [unit('SWHL',2,enchantments=[enchant('SHSK',id=2)]),unit('AREL',3),unit('RKWL',4),unit('BUDG',5,1),unit('IRMC',6,1)]),
     'Win within two turns. The opponent has six ether, six channels, Call Lightning and Polymorph, and is already Envenomed. You have three ether and no channels.',
     ['The enemy must lose both the ether it has and the refill it expects.','Your source of ether must also stop the flying counterattack. Reserve Stasis upkeep before spending the final points.','Siphon all six ether, cast Stasis, give the Air Elemental Strength, and use Energize All after the siphon. Attack with the Elemental, cover the Dragon with the Halo and the Mechos with the wall, and retain two ether for upkeep.'],
     'Siphon creates nine ether and removes the defensive Polymorph. Stasis prevents the six-channel refill and the lethal Lightning. Strength makes the unblockable Elemental hit for seven twice; Envenoming supplies two damage at each enemy turn end. Energize All restores the Halo for the flying counterattack; Rock Wall must stop the Mechos because its execution ignores surviving non-Walls. The remaining two ether pays Stasis upkeep at the second own turn. Both defenders must cover another counterattack before the poison finishes the enemy. On this line, allowing Stasis to expire gives the enemy its lethal Lightning first.',
     [ability(2,'siphon'),cast('STSI'),cast('STRG',3),cast('ENAL'),attack(3),end(),end(side=1),attack(5,side=1),attack(6,side=1),end(side=1),block(2,5),block(4,6),end(),attack(3),end(),end(side=1),attack(5,side=1),attack(6,side=1),end(side=1),block(2,5),block(4,6),end()],
     refutations=[{'label':'Cast Energize All before siphoning','commands':[cast('ENAL')]},{'label':'Put Strength on the flying Halo','commands':[cast('STRG',2)]}]))
    out.append(puzzle(game,'crucible_black_furnace','The Black Furnace','Crucible · A damage clock across response windows',4,2,
     state(game,hero('Black',['OVRL','SPWR','CLFR','PLMR','BLSS','DELS','ENAL'],mana=6,channels=1,health=1,enchantments=[enchant('BROT',id=1)]),hero('Blue',[],mana=2,channels=2,health=36),
     [unit('WKHR',2,resting=True),unit('WRSP',3,1),unit('WZSP',4,1),unit('WLBR',5,1)]),
     'Win within two turns. Burnout is active and your Walking Horror is resting. The Warrior Spirit is a berserker with regeneration; the Wizard and a wall support its defence.',
     ['The Horror must contribute in more than one phase.','An early sacrifice wastes future attacks. The overloaded body loses two power at the end of each of your turns.','Polymorph the Wizard. Give the Horror Overload, Spirit of War and Cloak of Fear. Hit for fourteen, block the regenerating Spirit, then hit for twelve. During the next forced defence, burn the Horror for the final ten.'],
     'The initial six ether funds all four preparations, leaving no early Burnout payment. Polymorph removes the second attacker and raises the hero to two health. The Horror attacks for fourteen, decays to twelve and remains ready to block because of Spirit of War. The Spirit regenerates and must attack again. At the second own turn one ether refills; the Horror deals twelve, then decays to ten. Preserve that ether until the following defence and use Burnout before combat. Fourteen plus twelve plus ten is exactly thirty-six. Another valid plan replaces Cloak with Bless: its eighteen-power first attack tramples for fourteen through the wall and Spirit together; the wall dies and the berserker remains resting during your second attack.',
     [cast('PLMR',4),cast('OVRL',2),cast('SPWR',2),cast('CLFR',2),attack(2),end(),end(side=1),end(side=1),block(2,3),end(),attack(2),end(),end(side=1),end(side=1),ability(0,'burnout:1',2,choice=1)],
     refutations=[{'label':'Burn the unprepared Horror immediately','commands':[ability(0,'burnout:1',2,choice=1)]},{'label':'Use Energize All instead of Spirit of War','commands':[cast('ENAL')]}], alternative_solutions=[{'label':'Break the first blockade with Bless instead of Cloak of Fear','commands':[cast('BLSS',2),cast('OVRL',2),cast('SPWR',2),cast('PLMR',4),attack(2),end(),block(5,2,side=1),block(3,2,side=1),end(side=1),end(side=1),block(2,3),end(),attack(2),end(),end(side=1),end(side=1),ability(0,'burnout:1',2,choice=1)]}]))
    out.append(puzzle(game,'crucible_two_bequests','Two Bequests','Crucible · Survive the siege, then build the lethal',4,2,
     state(game,hero('Green',['PLMR','PLMR','STRG','HAST','ENAL'],mana=2,channels=4,health=1,enchantments=[enchant('CMBN',id=1)]),hero('Blue',[],health=18),
     [unit('AVAS',2),unit('WLLV',3,enchantments=[enchant('SHSK',id=2)]),unit('LMMN',4,resting=True),unit('GROG',5,resting=True),unit('STMC',6,1),unit('BUDG',7,1),unit('SHWL',8,1,enchantments=[enchant('STRG',id=3)]),unit('RKWL',9,1)],phase=1,attacker=1,attacks=[6,7,8]),
     'Survive this attack and win within two of your own turns. Martyrdom is active. The enemy attacks through the ground, the air and a lane only a Wall can block; its Rock Wall protects the backline.',
     ['One winning plan borrows toughness for the opening defence and power for the finishing attack.','The Mechos kills a non-Wall after damaging it, even if its toughness was high enough. Keep the Wall for the Wolf.','Polymorph the Mechos. Sacrifice the Lamia Monk into the Assassin, block the Dragon with the Assassin and the Wolf with the Wall. On your turn, Polymorph the Dragon, strengthen the Assassin and give it the Ogre through Martyrdom. Attack for twelve, then six.'],
     'The Monk grants eight toughness, allowing the Assassin to survive eight aerial damage. The Ogre grants only five toughness and is saved for the attack in this line. Remove Steel Mechos to keep the Assassin alive: its execution would ignore the extra toughness. The twelve-toughness Wall covers the eight-power elusive Wolf. At your first turn, four ether pays for Polymorph, Strength and Martyrdom. The ground Rock Wall cannot block the flying Assassin, and the Wolf cannot block its elusive attack; it deals twelve, then six after the temporary Ogre bonus expires. The Wall remains to cover the counterattack.',
     [cast('PLMR',6),ability(0,'combine:1',4,choice=2),block(2,7),block(3,8),end(),cast('PLMR',7),cast('STRG',2),ability(0,'combine:1',5,choice=2),attack(2),end(),end(side=1),attack(8,side=1),end(side=1),block(3,8),end(),attack(2),end(),end(side=1)],
     refutations=[{'label':'Feed the only Assassin into the Ogre','commands':[ability(0,'combine:1',2,choice=5)]},{'label':'Sacrifice the wall into the Assassin','commands':[ability(0,'combine:1',3,choice=2)]}]))
    for entry in out:
        entry.update(_LOCALIZED[entry["id"].removeprefix("el1_tactical_v2_crucible_")])
        entry["hero_names"] = ["Crucible challenger", "Crucible defender"]
        entry["hero_names_ru"] = ["Испытуемый", "Страж испытания"]
    return out

_LOCALIZED = {
    "buried_reserve": {
        "title_ru": "Погребённый резерв",
        "category_ru": "Горнило · Жертва между двумя боями",
        "briefing_ru": "Победите за два хода. Раскройщик отдыхает. Над Прыгуном в вашем могильнике лежат два более новых существа. Четыре единицы эфира больше не пополнятся.",
        "hints_ru": [
            "Берегите существ, которые понадобятся для отражения контратаки.",
            "Ещё одна смерть обеспечит возвращение Прыгуна на границе хода. Раскройщику понадобятся две разные жертвы.",
            "Пожертвуйте Клеща Раскройщику, дайте Раскройщику Перегрузку и Маску Ужаса. Берегите вернувшегося Прыгуна: пожертвуйте его при следующей защите. Раскройщиком блокируйте Мехозавра, стеной — Дракона.",
        ],
        "explanation_ru": "Первая жертва кладёт третье новое существо над Прыгуном: он вернётся в конце хода. Перегрузка и Маска Ужаса обеспечивают неблокируемую атаку на двенадцать. Затем Раскройщик ослабевает до 10/7; жертва Прыгуна будит его для защиты. Он выдерживает шесть урона Железного мехозавра и убивает его, пока стена держит Дракона. Последние десять урона точны: погибший Мехозавр уже не отнимает здоровье у хозяина. Если враг оставит Мехозавра дома, тот сам отнимет четыре здоровья, облегчив последнюю атаку.",
    },
    "mortal_equation": {
        "title_ru": "Смертельное уравнение",
        "category_ru": "Горнило · Летальный удар с точной ценой в здоровье",
        "briefing_ru": "Победите за этот ход. У вас три эфира, два здоровья и ни одного готового атакующего. Стальной мехозавр невосприимчив к магии, а на Раскройщике действует Перестановка.",
        "hints_ru": [
            "Прежде чем выбирать цель уничтожения, посчитайте урон Аннигиляции для обеих сторон.",
            "Эфирная Торговля не только даёт вам эфир, но и лечит врага. Лишняя плата здоровьем может вывести его из-под летального удара.",
            "Превратите Зелёного дракона, обменяйте шесть здоровья на эфир, снимите Перестановку с Раскройщика и дайте ему Альфа-удар с Усилением. Аннигиляция нанесёт ровно двадцать один урон.",
        ],
        "explanation_ru": "Превращение убирает одиннадцать вражеской силы и устанавливает герою восемь здоровья. Эфирная Торговля на шесть оставляет два здоровья, даёт десять эфира и лечит врага с пятнадцати до двадцати одного. Снятие Чар, Альфа-удар, Усиление и Аннигиляция стоят ровно десять. Раскройщик без Перестановки даёт восемнадцать силы, Старый древень — три. Невосприимчивый Мехозавр не добавляет урона Аннигиляции. Меньшая плата не финансирует комбинацию, большая лечит врага выше двадцати одного.",
    },
    "frozen_account": {
        "title_ru": "Замороженный счёт",
        "category_ru": "Горнило · Лишение эфира, содержание чар и резерв защиты",
        "briefing_ru": "Победите за два хода. У противника шесть эфира, шесть каналов, Молния и Превращение; на нём уже действует Отравление. У вас три эфира и ни одного канала.",
        "hints_ru": [
            "Враг должен потерять и нынешний запас эфира, и ожидаемое пополнение.",
            "Ваш источник эфира должен также остановить воздушную контратаку. Прежде чем расходовать последние единицы, оставьте плату за Стазис.",
            "Украдите Нимбом все шесть эфира, наложите Стазис и дайте Элементалю воздуха Усиление. Затем примените Общую Подзарядку. Атакуйте Элементалем; Нимбом держите Дракона, стеной — Мехоса. Два оставшихся эфира оплатят Стазис: переживите и вторую контратаку, чтобы сработало Отравление.",
        ],
        "explanation_ru": "Кража даёт девять эфира и лишает врага защитного Превращения. Стазис отменяет пополнение от шести каналов и смертельную Молнию. Усиленный неблокируемый Элементаль дважды наносит по семь, Отравление — ещё по два в конце каждого вражеского хода. Общая Подзарядка будит Нимб после кражи, позволяя остановить Дракона. Каменная стена должна держать Мехоса: его добивание уничтожает уцелевших существ, кроме стен. Два сохранённых эфира оплачивают Стазис в начале второго своего хода. Оба защитника нужны для второй контратаки до последнего урона Отравления; в этой линии отмена Стазиса даст врагу Молнию раньше этого момента.",
    },
    "black_furnace": {
        "title_ru": "Чёрная печь",
        "category_ru": "Горнило · Урон по обе стороны боевой фазы",
        "briefing_ru": "Победите за два хода. Сожжение уже действует, Ходячий ужас отдыхает. Призрак-воин обладает регенерацией и обязан атаковать; Колдун и стена поддерживают его защиту.",
        "hints_ru": [
            "Ужас должен принести пользу в нескольких разных фазах.",
            "Ранняя жертва теряет будущие атаки. Перегрузка отнимает две силы в конце каждого вашего хода.",
            "Превратите Колдуна. Дайте Ужасу Перегрузку, Дух Войны и Маску Ужаса. Ударьте на четырнадцать, заблокируйте регенерирующего Призрака, затем ударьте на двенадцать. Во время следующей обязательной защиты Сожжение Ужаса даст последние десять.",
        ],
        "explanation_ru": "Начальные шесть эфира оплачивают все четыре приготовления, не оставляя платы за раннее Сожжение. Превращение убирает второго атакующего и даёт герою два здоровья. Ужас атакует на четырнадцать, ослабевает до двенадцати и благодаря Духу Войны остаётся готовым блокировать. Призрак регенерирует и снова будет обязан атаковать. Второй свой ход даёт один эфир; Ужас наносит двенадцать, затем ослабевает до десяти. Сохраните эфир до следующей защиты и примените Сожжение до разрешения боя. Четырнадцать, двенадцать и десять дают ровно тридцать шесть. Есть и другой план: вместо Маски Ужаса примените Благословение. Первая атака с силой восемнадцать наносит четырнадцать через совместный блок стены и Призрака; стена гибнет, а к вашей второй атаке берсерк уже отдыхает.",
    },
    "two_bequests": {
        "title_ru": "Два наследства",
        "category_ru": "Горнило · Пережить осаду и собрать летальный удар",
        "briefing_ru": "Переживите эту атаку и победите за два своих хода. Самопожертвование уже действует. Враг атакует по земле, по воздуху и существом, которое может блокировать только стена; его Каменная стена прикрывает тыл.",
        "hints_ru": [
            "Один из выигрышных планов использует стойкость жертвы для начальной защиты, а силу другой — для решающей атаки.",
            "Мехос добивает повреждённое существо, даже если его стойкости хватило для выживания. Стены защищены от этого; свою стену берегите для Волка.",
            "Превратите Мехоса. Пожертвуйте Ламию-монахиню Авиаку-убийце; Авиаком блокируйте Дракона, стеной — Волка. На своём ходу превратите Дракона, усильте Авиака и передайте ему Людоеда через Самопожертвование. Атакуйте на двенадцать, затем на шесть.",
        ],
        "explanation_ru": "Монахиня даёт восемь стойкости: Авиак выдерживает восемь воздушного урона. Людоед дал бы лишь пять; его нужно сохранить для атаки. Стального мехоса необходимо убрать: добивание убило бы Авиака несмотря на добавленную стойкость. Стена со стойкостью двенадцать держит неуловимого Волка с силой восемь. На первом своём ходу четыре эфира оплачивают Превращение, Усиление и Самопожертвование. Наземная Каменная стена не достаёт летающего Авиака, а Волк не может блокировать его неуловимую атаку. Он наносит двенадцать, затем шесть после окончания временного бонуса Людоеда. Ваша стена остаётся для отражения контратаки.",
    },
}
