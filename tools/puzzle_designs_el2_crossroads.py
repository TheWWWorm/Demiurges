"""Crossroads: EL2 studies about preparation, restraint and useful enemies.

Six independent additions to the existing catalogue.  No earlier position is
changed.  Reference lines and losing choices are checked in the real GDScript
battle implementation, with bounded opponent-response searches.
"""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end


_ROLES = {
    "step_back": (("The Red Accountant", "The Cloud Warden"), ("Красный счетовод", "Страж облаков")),
    "dismiss_parasite": (("The Unwilling Host", "The Last King"), ("Невольный хозяин", "Последний вождь")),
    "small_appetite": (("The Patient Chemist", "The Hungry Gardener"), ("Терпеливый химик", "Голодный садовник")),
    "grow_teeth": (("The Snake Gardener", "The Impatient Disenchanter"), ("Садовница змей", "Нетерпеливый рассеиватель")),
    "empty_pockets": (("The Unburdened Raider", "The Quiet Alchemist"), ("Налётчик налегке", "Тихий алхимик")),
    "last_reprieve": (("The Contrary Healer", "The Regenerating Warden"), ("Лекарь наперекор", "Возрождающийся страж")),
}


def _study(slug, title, title_ru, category, category_ru, level, turns, position,
           briefing, briefing_ru, hints, hints_ru, explanation, explanation_ru,
           solution, objective=None, refutations=None, alternative_solutions=None):
    value = puzzle("el2", "crossroads_" + slug, title, category, level, turns, position,
        briefing, hints, explanation, solution, objective=objective,
        title_ru=title_ru, category_ru=category_ru, briefing_ru=briefing_ru,
        hints_ru=hints_ru, explanation_ru=explanation_ru,
        hero_names=list(_ROLES[slug][0]), hero_names_ru=list(_ROLES[slug][1]),
        refutations=refutations or [])
    if alternative_solutions:
        value["alternative_solutions"] = alternative_solutions
    return value


def puzzles():
    g = "el2"
    out = []

    out.append(_study("step_back", "Step Back, Spring Forward", "Шаг назад — рывок вперёд",
        "A conditional investment and its refill", "Условное вложение и пополнение", 3, 2,
        state(g, hero("Red", ["CLNP", "BLNC", "HRCN", "HRCN"], mana=2, channels=4, health=4, level=12),
                 hero("Black", [], channels=4, health=30, level=16,
                      enchantments=[enchant("DPGS", id=1)]),
                 [unit("ORSH", 2), unit("RFPT", 3, 1), unit("WLFC", 4, 1)]),
        "Clear both enemy flyers within two turns and preserve your Orc Shaman. Both heroes have four channels; you have two ether now. The enemy's Depressing Gas is active and its hand is empty. In this edition, the Shaman supplies one extra ether at the start of your turn.",
        "Уничтожьте обоих вражеских летунов за два хода и сохраните Орка-шамана. У обоих героев по четыре канала; сейчас у вас два эфира. У врага действует Подавляющий Газ, а рука пуста. В этой версии игры шаман даёт один дополнительный эфир в начале вашего хода.",
        ["Two Hurricanes cost six ether. Your ordinary next-turn refill supplies only five.",
         "Forces of Balance grants two channels only while you have fewer than the enemy. The Shaman's rite removes an enchantment by spending a channel, leaving your current ether untouched.",
         "Use the Shaman's rite on Depressing Gas, then cast Forces of Balance. Survive the Pteros's possible three-point hit. Your next refill is five channels plus the Shaman's one ether: cast a Hurricane on each flyer."],
        ["Два Урагана стоят шесть эфира. Обычное пополнение следующего хода даст лишь пять.",
         "Равновесие даёт два канала, только когда у вас их меньше, чем у врага. Обряд шамана снимает чары ценой канала, не расходуя текущий эфир.",
         "Обрядом шамана снимите Подавляющий Газ, затем примените Равновесие. Переживите возможный удар птероса на три. Следующее пополнение — пять каналов и один эфир шамана: направьте по Урагану в каждого летуна."],
        "The rite changes your channel count from four to three. Forces of Balance is now legal and raises it to five, using the two available ether. On your next turn the five channels and the Shaman supply exactly six, enough for both Hurricanes. Removing the gas restores the Pteros to three power, but your four health survive that attack. Lesser Disenchant removes the same gas without lowering your channels; the tie prevents Balance, and the resulting five-ether refill cannot pay for both removals.",
        "Обряд уменьшает число ваших каналов с четырёх до трёх. Равновесие становится доступным и поднимает их число до пяти, расходуя имеющиеся два эфира. На следующем ходу пять каналов и шаман дают ровно шесть — достаточно для двух Ураганов. После снятия газа сила птероса возвращается к трём, но четыре жизни позволяют пережить его атаку. Снятие Чар убирает тот же газ без потери канала; равенство каналов запрещает Равновесие, а пополнения в пять эфира не хватает для обоих уничтожений.",
        [ability(2, "orc_rite", 1, choice=1), cast("BLNC"), end(), attack(3, side=1), end(side=1), end(),
         cast("HRCN", 3), cast("HRCN", 4)],
        objective={"type": "clear", "protect": [2]},
        refutations=[{"label": "Dispel the gas without sacrificing a channel", "commands": [cast("CLNP", 1, grave=1)],
                      "failure_line": [cast("CLNP", 1, grave=1), end(), attack(3, side=1), end(side=1), end(),
                                       cast("HRCN", 3), end(), end(side=1)]}]))

    out.append(_study("dismiss_parasite", "Evict the Parasite", "Выселите паразита",
        "Dispose of a dangerous ally through an ordered block", "Избавьтесь от опасного союзника порядком блоков", 2, 1,
        state(g, hero("Red", [], health=1, level=8),
                 hero("Red", [], health=1, level=14, enchantments=[enchant("WETX", id=1, owner=0)]),
                 [unit("IRMZ", 2), unit("RKWL", 3), unit("OGKN", 4, 1)],
                 phase=1, attacker=1, attacks=[4]),
        "Win while preserving the Rock Wall. The Ogre King is already attacking for seven with trample. Both heroes have one health. Weak Toxin will remove the enemy's last health at the end of your coming turn; your Iron Mechozaurus drains four health from you at that same turn end.",
        "Победите, сохранив Каменную стену. Вождь людоедов уже атакует на семь с пробивным ударом. У обоих героев по одной жизни. Слабый Токсин отнимет последнюю жизнь врага в конце вашего ближайшего хода; ваш Железный мехозавр в тот же конец хода отнимает у вас четыре жизни.",
        ["Surviving the Ogre's attack is only the first problem. Decide which ally must still be alive when the toxin resolves.",
         "The untargetable, unaffected Mechozaurus can still die in combat. Trample distributes damage through blockers in the order you assign them.",
         "Assign the Iron Mechozaurus to block the Ogre first, then add the Rock Wall to the same attack. The Mechozaurus takes four and dies; the Wall absorbs the remaining three. Pass your turn and let Weak Toxin finish the enemy."],
        ["Пережить удар людоеда — лишь первая задача. Решите, кто из союзников должен дожить до срабатывания токсина.",
         "Мехозавр защищён от выбора целью и невосприимчив к магии, но может погибнуть в бою. Пробивной урон проходит по блокирующим в порядке их назначения.",
         "Сначала назначьте Железного мехозавра блокировать людоеда, затем добавьте Каменную стену к той же атаке. Мехозавр получит четыре и погибнет; стена примет оставшиеся три. Пропустите свой ход, и Слабый Токсин добьёт врага."],
        "The first blocker receives four of the Ogre's seven damage and dies before retaliating. The ten-toughness wall safely takes the other three. With the parasite gone, your one-health hero survives the coming turn end, while Weak Toxin kills the enemy. Putting the Wall first spends all seven damage on it and leaves the Mechozaurus alive. Its four-point drain then kills you in the same turn-end sequence that the toxin kills the opponent; that mutual defeat is not a win.",
        "Первый блокирующий получает четыре из семи единиц урона людоеда и погибает до ответного удара. Стена со стойкостью десять благополучно принимает оставшиеся три. Без паразита ваш герой с одной жизнью переживает ближайший конец хода, а Слабый Токсин убивает врага. Если поставить стену первой, все семь урона уйдут в неё и мехозавр останется жив. Его потеря четырёх жизней убьёт вас в той же последовательности конца хода, в которой токсин убьёт противника; обоюдное поражение не считается победой.",
        [block(2, 4), block(3, 4), end(), end()],
        objective={"type": "win", "protect": [3]},
        refutations=[{"label": "Put the Wall before the parasite",
                      "commands": [block(3, 4), block(2, 4), end(), end()]}]))

    out.append(_study("small_appetite", "A Small Appetite", "Маленький аппетит",
        "Balance a shared hunger sweep", "Расчёт общего голода", 2, 1,
        state(g, hero("Black", ["DRGS", "DPGS", "FRGS", "RVHG"], mana=13, health=4, level=11,
                      template="StartBlackMale"),
                 hero("Green", [], health=30, level=12),
                 [unit("BEWR", 2), unit("TANT", 3, 1), unit("MCWY", 4, 1)]),
        "Clear the enemy army this turn and preserve your Bee Warrior. Both enemies can regenerate, but their hero has no ether. Ravaging Hunger makes creatures on both sides take damage equal to their own current power; the gases affect both armies too.",
        "Уничтожьте армию врага за этот ход и сохраните Пчелу-воина. Оба врага могут регенерировать, но у их героя нет эфира. Опустошающий Голод наносит существам с обеих сторон урон, равный их текущей силе; газы также действуют на обе армии.",
        ["Your smallest creature must lose its appetite completely. The enemy Treant still needs some appetite left.",
         "Drowsy Gas removes one power, while Depressing Gas removes two. Frenzy Gas reduces toughness, but ordinary gas reduction never lowers toughness below one.",
         "Cast Drowsy Gas and Frenzy Gas, then Ravaging Hunger. The Bee is 0/1, while the enemies are 1/1 and 4/2. The zero-power Bee takes no hunger damage."],
        ["Ваше самое маленькое существо должно полностью потерять аппетит. Вражескому древню нужно оставить хоть немного.",
         "Ослабляющий Газ убирает одну единицу силы, Подавляющий Газ — две. Веселящий Газ уменьшает стойкость, но обычное снижение от газа не опускает её ниже единицы.",
         "Произнесите Ослабляющий Газ и Веселящий Газ, затем Опустошающий Голод. Пчела станет 0/1, враги — 1/1 и 4/2. Пчела с нулевой силой не получает урона голода."],
        "One point of power reduction protects the 1/1 Bee without reducing the 2/2 Treant to zero power. Frenzy Gas then leaves both small creatures at one toughness and the Mech Wyrm at two. Hunger kills both enemies and spares the Bee; neither enemy has ether for regeneration. Depressing Gas also makes the Treant's power zero, so Hunger never hurts it. Another valid order is Drowsy Gas, Hunger, then Frenzy Gas: Hunger leaves one wound on the Treant, and the final toughness reduction makes that wound lethal.",
        "Снижение силы на единицу защищает Пчелу 1/1, не обнуляя силу Древня 2/2. Веселящий Газ оставляет обоим малым существам по одной стойкости, а Червезавру — две. Голод убивает обоих врагов и щадит пчелу; эфира для регенерации у врага нет. Подавляющий Газ обнуляет и силу древня, поэтому Голод вовсе его не ранит. Допустим и другой порядок: Ослабляющий Газ, Голод, затем Веселящий Газ. Голод оставляет на древне одну рану, а последнее снижение стойкости делает её смертельной.",
        [cast("DRGS"), cast("FRGS"), cast("RVHG")],
        objective={"type": "clear", "protect": [2]},
        refutations=[{"label": "Choose the stronger power-reducing gas", "commands": [cast("DPGS")],
                      "failure_line": [cast("DPGS"), cast("FRGS"), cast("RVHG"), end(), end(side=1)]}],
        alternative_solutions=[{"label": "Alternate order: Hunger before Frenzy Gas",
            "label_ru": "Другой порядок: Голод перед Веселящим Газом",
            "commands": [cast("DRGS"), cast("RVHG"), cast("FRGS")]}]))

    out.append(_study("grow_teeth", "Let It Grow Teeth", "Пусть отрастит клыки",
        "Permanent growth unlocks a dangerous final boost", "Постоянный рост открывает опасное финальное усиление", 3, 3,
        state(g, hero("Green", ["INCR", "IMML"], mana=3, channels=3, health=1, level=16,
                      template="GreenFemale2"),
                 hero("Red", ["CLNP"], mana=1, channels=2, health=10, level=15),
                 [unit("GRSN", 2, enchantments=[enchant("CLFR", id=1)]), unit("RKWL", 3), unit("FREL", 4, 1)]),
        "Win in three turns while preserving the Snake and Wall. The Grass Snake starts with Cloak of Fear. The enemy holds Lesser Disenchant: it has only one ether now, but two channels will fund the spell next turn. Rage grants your army four power and removes two toughness; that reduction can kill.",
        "Победите за три хода, сохранив змею и стену. На Травяной змее уже есть Маска Ужаса. У врага в руке Снятие Чар: сейчас ему хватает лишь одного эфира, но два канала оплатят заклинание на следующем ходу. Ярость даёт вашей армии четыре силы и отнимает две стойкости; это снижение может убить.",
        ["The Snake can earn the toughness needed to survive Rage. First make sure its attack route remains open.",
         "Every hit on the enemy hero permanently gives the Grass Snake +1/+1. Cutting the enemy to one channel keeps Lesser Disenchant unaffordable on every reply.",
         "Cast Inconsistent Reality before passing the first turn. Attack with the Snake for one, then for two on the next turn; block any Fire Elemental attacks with the Wall. On turn three the Snake is 3/3: Rage makes it 7/1, enough for the last seven damage."],
        ["Змея может вырастить стойкость, нужную для выживания после Ярости. Сначала сохраните ей открытый путь для атак.",
         "Каждый удар по вражескому герою навсегда даёт Травяной змее +1/+1. Уменьшение запаса врага до одного канала не позволит ему оплатить Снятие Чар ни на одном ответном ходу.",
         "До завершения первого хода примените Искажение Реальности. Атакуйте змеёй на один, затем на два в следующем ходу; атаки Элементаля огня блокируйте стеной. На третьем ходу змея будет 3/3: Ярость сделает её 7/1 — ровно для последних семи урона."],
        "Inconsistent Reality removes one enemy channel before its refill, protecting the Cloak from the disclosed two-ether dispel. The first two unblocked Snake hits deal one and two, leaving the enemy at seven while growing the Snake to 3/3. Only then can it survive Rage's lethal two-toughness penalty and attack for seven. The Wall safely holds the Elemental between turns. Rage earlier kills the protected Snake; delaying the income cut lets the enemy remove the Cloak, after which its first-striking Elemental can stop the growth plan.",
        "Искажение Реальности убирает один вражеский канал до пополнения, защищая Маску от известного заклинания снятия за два эфира. Первые два беспрепятственных удара змеи наносят один и два урона, оставляя врагу семь жизней и выращивая змею до 3/3. Лишь теперь она переживёт смертельный штраф Ярости в две стойкости и атакует на семь. Между ходами стена благополучно удерживает элементаля. Ранняя Ярость убивает защищаемую змею; промедление с сокращением дохода позволяет врагу снять Маску, после чего элементаль с первым ударом остановит план роста.",
        [cast("INCR"), attack(2), end(), end(side=1), attack(4, side=1), end(side=1), block(3, 4), end(),
         attack(2), end(), end(side=1), attack(4, side=1), end(side=1), block(3, 4), end(),
         cast("IMML"), attack(2), end(), end(side=1)],
        objective={"type": "win", "protect": [2, 3]},
        refutations=[
            {"label": "Pass the first attack without cutting the dispel income",
             "commands": [attack(2), end(), end(side=1)],
             "failure_line": [attack(2), end(), end(side=1), cast("CLNP", 2, grave=1, side=1),
                              attack(4, side=1), end(side=1), block(3, 4), end(), attack(2), end(),
                              block(4, 2, side=1), end(side=1)]},
            {"label": "Use Rage before the Snake has grown", "commands": [cast("IMML")]},
        ]))

    out.append(_study("empty_pockets", "Empty Pockets, Fast Feet", "Пустые карманы, быстрые ноги",
        "Spend your hand in the right order", "Расходуйте руку в верном порядке", 2, 1,
        state(g, hero("Red", ["CLNP", "MCWO", "BANN"], mana=4, health=6, level=6),
                 hero("Black", ["PLMR", "PLMR", "PLMR"], mana=1, health=1, level=10,
                      enchantments=[enchant("HOAM", id=1)]), []),
        "Win this turn with four ether. The enemy has Hostile Ambience active and exactly three Polymorphs in hand; its one ether can pay for a defensive Polymorph. Your Mech Worm has Haste and is aggressive, but new creatures arrive resting while Hostile Ambience remains.",
        "Победите за этот ход с четырьмя эфирами. У врага действует Враждебное Окружение, а в руке ровно три Превращения; его одного эфира хватит на Превращение в защите. У вашего Механического червяка есть спешка и агрессивность, но при Враждебном Окружении новые существа появляются отдыхающими.",
        ["You must solve both the arrival problem and the enemy's defensive hand before ending the turn.",
         "Removing Hostile Ambience does not wake a creature that already arrived resting. Sclerosis discards the excess of the enemy's hand over the cards you still hold after casting it.",
         "Disenchant Hostile Ambience first, summon the Mech Worm second, then cast Sclerosis as your last card. It removes all three Polymorphs, and the Worm's compulsory attack deals the final point."],
        ["До завершения хода нужно решить и проблему появления существа, и проблему защитных карт врага.",
         "Снятие Враждебного Окружения не поднимает существо, уже появившееся отдыхающим. Склероз сбрасывает избыток вражеской руки над числом карт, оставшихся у вас после его произнесения.",
         "Сначала снимите Враждебное Окружение, затем вызовите Механического червяка и последней картой произнесите Склероз. Он уберёт все три Превращения, а обязательная атака червяка нанесёт последнюю единицу урона."],
        "The costs are two for Lesser Disenchant, one for the Worm and one for Sclerosis. Removing Ambience before the summon lets the hasty Worm arrive ready and join the attack immediately. Casting Sclerosis last leaves your hand empty, so the difference is all three enemy cards. Casting it with one or two cards still in your hand leaves the enemy a Polymorph. Summoning first instead leaves the Worm resting even after Ambience is removed, missing this turn's attack.",
        "Снятие Чар стоит два, червяк — один и Склероз — один. Снятое до вызова Окружение позволяет существу со спешкой появиться готовым и сразу присоединиться к атаке. Склероз последней картой оставляет вашу руку пустой, поэтому разница составляет все три вражеские карты. Если у вас остаётся одна или две карты, противнику хватит оставшегося Превращения. Если же сначала вызвать червяка, он останется отдыхать даже после снятия Окружения и пропустит атаку этого хода.",
        [cast("CLNP", 1, grave=1), cast("MCWO"), cast("BANN"), end(), end(side=1)],
        refutations=[
            {"label": "Summon before removing Hostile Ambience", "commands": [cast("MCWO")],
             "failure_line": [cast("MCWO"), cast("CLNP", 1, grave=1), cast("BANN"), end(), end(side=1)]},
            {"label": "Use Sclerosis while still holding two cards", "commands": [cast("BANN")],
             "failure_line": [cast("BANN"), cast("CLNP", 1, grave=1), cast("MCWO"), end(),
                              cast("PLMR", 2, side=1), end(side=1), end(side=1)]},
        ]))

    out.append(_study("last_reprieve", "One Last Reprieve", "Последняя отсрочка",
        "Keep a regenerating attacker in combat", "Удержите регенерирующего врага в бою", 3, 1,
        state(g, hero("Green", ["LFGR"], mana=4, health=1, level=17, template="Diamanda4Green"),
                 hero("Black", [], mana=1, channels=1, health=30, level=18),
                 [unit("LASN", 2, enchantments=[enchant("STSK", id=1)]), unit("LASN", 3), unit("TANT", 4, 1)],
                 phase=1, attacker=1, attacks=[4]),
        "Clear the enemy army and preserve both Lake Snakes. The 2/2 Treant is already attacking, and its hero has one ether for regeneration. Your first Snake wears Stone Skin; the other has no protection. Lake Snake venom lowers the creature it hits by one power and one toughness.",
        "Уничтожьте армию врага и сохраните обеих Озерных змей. Древень 2/2 уже атакует, и у его героя есть один эфир для регенерации. На вашей первой змее есть Каменная Кожа; вторая не защищена. Яд Озерной змеи снижает силу и стойкость поражённого существа на единицу.",
        ["An ordinary lethal first strike lets the Treant regenerate and leave combat. Find a way to keep it present for a second bite.",
         "Lake Snake venom lowers toughness before its strike deals damage. Lifeguard can cancel that first damage without cancelling the venom. Zero maximum toughness cannot be saved by regeneration.",
         "Put Lifeguard on the enemy Treant. Block first with the armored Snake, then add the unarmored Snake to the same attack. The first venom leaves one toughness; the second lowers it to zero."],
        ["Обычный смертельный первый удар позволяет древню регенерировать и выйти из боя. Найдите способ оставить его на месте для второго укуса.",
         "Яд Озерной змеи уменьшает стойкость до нанесения урона её ударом. Телохранитель может поглотить первый урон, не отменяя яд. Нулевую максимальную стойкость регенерация не спасает.",
         "Наложите Телохранителя на вражеского древня. Сначала назначьте блокировать змею с бронёй, затем добавьте незащищённую к той же атаке. Первый яд оставит одну стойкость, второй снизит её до нуля."],
        "The armored Snake first reduces the Treant from 2/2 to 1/1. The enemy's Lifeguard then cancels the three-point strike, so the Treant does not regenerate or withdraw. Its original two-point attack is absorbed by Stone Skin. The second Snake applies another venom, reducing maximum toughness to zero and killing the Treant despite its reserved ether. Shielding your own Snake instead allows the first hit to trigger regeneration and end the exchange early. Assigning the unarmored Snake first exposes it to the two-point return hit and loses a protected ally.",
        "Змея с бронёй сначала уменьшает характеристики древня с 2/2 до 1/1. Телохранитель врага поглощает удар на три, поэтому древень не регенерирует и не выходит из боя. Его исходные две единицы атаки поглощаются Каменной Кожей. Вторая змея накладывает ещё один яд, снижая максимальную стойкость до нуля и убивая древня вопреки запасённому эфиру. Защита собственной змеи вместо врага позволяет первому удару вызвать регенерацию и преждевременно завершить обмен. Если первой назначить незащищённую змею, она получит ответные две единицы урона и погибнет.",
        [cast("LFGR", 4), block(2, 4), block(3, 4), end()],
        objective={"type": "clear", "protect": [2, 3]},
        refutations=[
            {"label": "Protect your first Snake instead of the enemy", "commands": [cast("LFGR", 2)],
             "failure_line": [cast("LFGR", 2), block(2, 4), block(3, 4), end(), end(), end(side=1)]},
            {"label": "Let the unarmored Snake take the first block",
             "commands": [cast("LFGR", 4), block(3, 4), block(2, 4), end()]},
        ]))
    return out
