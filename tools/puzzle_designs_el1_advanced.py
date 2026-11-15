"""Advanced Etherlords I studies: defence, delayed plans, and contested control.

All positions use ordinary edition-specific card mechanics. Inline translations
keep new studies self-contained; no previous puzzle IDs are changed.
"""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end


def puzzles():
    game = "el1"
    out = []

    out.append(puzzle(
        game, "buried_reserve", "Buried Reserve", "Burial, regeneration and a delayed attack", 3, 2,
        state(game,
              hero("Blue", ["LGST", "CLFR", "SHSK"], mana=4, channels=2, health=1,
                   grave=["HOPR"], enchantments=[enchant("COPL", id=1)]),
              hero("Red", [], health=2),
              [unit("TNSA", 2, sick=True), unit("WLBR", 3, damage=1), unit("RVHL", 4),
               unit("PHWL", 5, damage=3), unit("GROG", 6, 1), unit("RKWL", 7, 1)]),
        "Win within two turns and keep the newly summoned Treant Sapling alive. Your wounded army cannot win a normal attack. "
        "One Hopper is buried in your graveyard; Life Channel is already active.",
        ["A useful creature can arrive after your own turn ends. Count the new corpses above the Hopper.",
         "Lightning Storm can bury three creatures while the Sapling regenerates. Its regeneration also heals you through Life Channel. Keep one ether for defence.",
         "Cast Lightning Storm, then end the turn. Block the Ogre with the Sapling if it attacks. On your next turn, give the returning Hopper Cloak of Fear and attack."],
        "Lightning Storm kills the wounded Wall of Burning Rock, River Halo and wounded Phantasmal Wall. "
        "The Sapling regenerates for one ether, triggering Life Channel's five healing. The first game's "
        "storm damages creatures, not heroes: you finish on six health; the enemy still has two. Three newer corpses "
        "return the Hopper at your turn end. Keep the last ether for the Sapling to regenerate while blocking "
        "the Ogre; using the Hopper as the blocker loses your winning attack. The next two-channel refill "
        "pays for Cloak of Fear and the Hopper's two damage wins. If the Ogre stays home, the same attack wins.",
        [cast("LGST"), end(), attack(6, side=1), end(side=1), block(2, 6), end(),
         cast("CLFR", 8), attack(8), end(), end(side=1)],
        objective={"type": "win", "protect": [2]},
        refutations=[
            {"label": "Buy evasion for the starting Sapling", "commands": [cast("CLFR", 2)]},
            {"label": "Spend the reserve on Shell Skin", "commands": [cast("SHSK", 2)]},
            {"label": "Use the returning Hopper as the Ogre's blocker", "commands": [cast("LGST"), end(), attack(6, side=1), end(side=1), block(8, 6), end()]},
        ],
        title_ru="Погребённый резерв", category_ru="Погребение, регенерация и отложенная атака",
        briefing_ru="Победите за два хода и сохраните только что призванного Молодого древня. Раненая армия не выиграет обычной атакой. "
        "В вашем могильнике лежит Прыгун; Канал Жизни уже действует.",
        hints_ru=["Полезное существо может появиться после завершения вашего хода. Посчитайте новые карты над Прыгуном в могильнике.",
                  "Шторм Молний погребёт три существа, а Древень регенерирует. Его регенерация также исцелит вас через Канал Жизни. Оставьте единицу эфира для защиты.",
                  "Примените Шторм Молний и завершите ход. Если Людоед атакует, блокируйте Молодым древнем. На следующем ходу дайте вернувшемуся Прыгуну Маску Ужаса и атакуйте."],
        explanation_ru="Шторм Молний убивает раненую Стену горящего камня, Речного нимба и раненую Стену нереальности. "
        "Молодой древень регенерирует за единицу эфира. Канал Жизни восстанавливает вам пять здоровья. В первой игре "
        "этот Шторм повреждает существ, но не героев: у вас становится шесть здоровья, у врага остаётся два. Три новые карты над "
        "Прыгуном возвращают его в бой в конце хода. Последний эфир нужен Древню для регенерации при блокировании "
        "Людоеда; жертвовать Прыгуном нельзя — это будущий победный удар. На следующем ходу два канала дают эфир "
        "для Маски Ужаса, и Прыгун наносит два урона. Отказ Людоеда от атаки плану не мешает.",
    ))

    out.append(puzzle(
        game, "silence_is_not_sleep", "Silence Is Not Sleep", "Resting versus disabling an ability", 2, 1,
        state(game, hero("Green", ["IRRT", "ENFL", "SPWR"], mana=4),
              hero("Black", [], health=4),
              [unit("MTSC", 2, enchantments=[enchant("DISM", id=1)]), unit("SHWL", 3), unit("WLDT", 4, 1), unit("RKWL", 5, 1)]),
        "Win this turn. Two Walls stand between your Shadow Wolf and the enemy hero. You have four ether.",
        ["Removing a creature's ability and resting it are different operations.",
         "The Mantis Scribe can rest both walls for one ether each. Distortion does not require a ready wall.",
         "Put Irritation on the Wall of Distortion, use the Scribe to rest the walls, then attack with the Shadow Wolf."],
        "Irritation prevents the Wall of Distortion from sacrificing itself to cancel the attack. "
        "The Mantis Scribe's ability rests both walls, leaving no legal blocker for the Wolf's four damage. "
        "Enfeebling the Distortion Wall does not switch off its ability, which has no ready requirement. "
        "Using Irritation on the Scribe instead removes the only way to clear both blocking lanes. "
        "The two preparations may be performed in either order.",
        [cast("IRRT", 4), ability(2, "tap_walls"), attack(3), end(), end(side=1)],
        refutations=[
            {"label": "Enfeeble and tap the walls, then commit without disabling Distortion", "commands": [cast("ENFL", 4), ability(2, "tap_walls"), attack(3), end()]},
            {"label": "Put Irritation on the Scribe", "commands": [cast("IRRT", 2)]},
            {"label": "Spend an extra ether making the Wolf restless", "commands": [cast("SPWR", 3)]},
        ],
        title_ru="Молчание — не сон", category_ru="Отдых и запрет способности",
        briefing_ru="Победите за этот ход. Между Призрачным волком и вражеским героем стоят две стены. У вас четыре единицы эфира.",
        hints_ru=["Запрет способности и перевод существа в состояние отдыха — разные действия.",
                  "Мантис-летописец отправляет стены отдыхать за единицу эфира на каждую. Искажение не требует готовности стены.",
                  "Наложите Раздражение на Стену искажения, способностью Летописца отправьте стены отдыхать и атакуйте Призрачным волком."],
        explanation_ru="Раздражение запрещает Стене искажения пожертвовать собой ради отмены атаки. "
        "Мантис-летописец отправляет обе стены отдыхать, и четыре урона Волка проходят герою. Бессилие "
        "не запрещает Искажение: этой способности не нужно готовое существо. Раздражение на самом Летописце "
        "лишает вас единственного способа одновременно убрать обоих защитников. Порядок двух подготовительных действий можно менять.",
    ))

    out.append(puzzle(
        game, "lasting_wounds", "Lasting Wounds", "Defensive tempo and retained damage", 3, 1,
        state(game,
              hero("Red", ["FOGG"], mana=2, health=3,
                   enchantments=[enchant("ENRG", id=1), enchant("ENRG", id=2), enchant("FTDS", id=3)]),
              hero("Green", [], mana=1, channels=1, health=30),
              [unit("RDDG", 2, resting=True), unit("RKWL", 3),
               unit("GROG", 4, 1), unit("TANT", 5, 1), unit("RFPT", 6, 1)],
              phase=1, attacker=1, attacks=[4, 5, 6]),
        "Clear every enemy creature by the end of your next own turn. Preserve the Red Dragon and Rock Wall. "
        "The attack is committed and the Dragon is resting. Your hero has Fatal Disease and two Energize enchantments. Three damage to your hero would be fatal.",
        ["One breath is insufficient. The first wave has to survive the turn's normal recovery.",
         "Fatal Disease affects the enemy's recovery in this edition. The Dragon needs to breathe during defence and still become a blocker. Each Energize can act once.",
         "Use one Energize on the Dragon, breathe, then use the other Energize. Block the Pteros with the Dragon and the Ogre with Rock Wall. On your own turn, breathe again."],
        "The existing Fatal Disease prevents enemy regeneration and wound recovery. The first Energize readies "
        "the resting Dragon; its breath kills the Treant and leaves three wounds on the Ogre. That ability "
        "rests the Dragon again, so the second Energize is needed to block the flying Pteros. Rock Wall "
        "holds the Ogre. The Dragon kills the Pteros in combat. "
        "The enemy Ogre keeps its three wounds at cleanup; the second breath on your own turn finishes it. "
        "Your own creatures recover normally because you cast the first game's Fatal Disease.",
        [ability(0, "energize:1", 2), ability(2, "breath"), ability(0, "energize:2", 2),
         block(2, 6), block(3, 4), end(), ability(2, "breath")],
        objective={"type": "clear", "protect": [2, 3]},
        refutations=[
            {"label": "Cancel the combat with Fog", "commands": [cast("FOGG")]},
            {"label": "Defend without delivering the first breath", "commands": [ability(0, "energize:1", 2), block(2, 6), block(3, 4), end()]},
            {"label": "Breathe but leave the Dragon resting for combat", "commands": [ability(0, "energize:1", 2), ability(2, "breath"), block(3, 4), end()]},
        ],
        title_ru="Незаживающие раны", category_ru="Защита и сохранение урона",
        briefing_ru="Уберите всех вражеских существ до конца своего ближайшего хода. Сохраните Красного дракона "
        "и Каменную стену. Атака объявлена, Дракон отдыхает. На герое действуют Роковая Болезнь и две Подзарядки; три урона герою будут смертельны.",
        hints_ru=["Одного дыхания мало. Следы первой волны должны сохраниться после обычного восстановления в конце хода.",
                  "В первой игре Роковая Болезнь мешает восстановлению врага. Дракон должен использовать дыхание в фазе защиты и всё же успеть блокировать. Каждая Подзарядка действует один раз.",
                  "Поднимите Дракона одной Подзарядкой, используйте дыхание и поднимите его второй. Драконом блокируйте Птероса, стеной — Людоеда. На своём ходу повторите дыхание."],
        explanation_ru="Действующая Роковая Болезнь запрещает врагу регенерацию и восстановление ран. Первая Подзарядка "
        "поднимает Дракона; дыхание убивает Древня и оставляет три раны Людоеду. Способность снова отправляет "
        "Дракона отдыхать, поэтому вторая Подзарядка нужна для блокирования летающего Птероса. Каменная стена "
        "держит Людоеда. Дракон убивает Птероса. Три раны Людоеда не исчезают в конце "
        "хода, и следующее дыхание его добивает. Ваши существа восстанавливаются нормально: в первой игре "
        "ваша Роковая Болезнь мешает только сопернику.",
    ))

    out.append(puzzle(
        game, "safe_passage", "Safe Passage", "Contested control and defensive reserves", 3, 2,
        state(game,
              hero("Blue", ["MALS", "CHCM", "CHCM", "WEAK"], mana=9, channels=5, health=3),
              hero("Blue", ["CLNP"], mana=2, channels=2, health=30),
              [unit("TNSA", 2), unit("RKWL", 3), unit("FREL", 4, 1), unit("GROG", 5, 1), unit("SHWL", 6, 1)]),
        "Take control of both the Fire Elemental and Gray Ogre within two turns, keeping both alive. "
        "Your Treant Sapling must also survive. The enemy holds exactly one Lesser Disenchant.",
        ["You cannot afford both captures now. Plan which attacker remains hostile and how your new enchantment survives the enemy's turn.",
         "A Sapling can regenerate through the Ogre, but the Fire Elemental prevents regeneration. You also need one ether left after your first capture.",
         "Discard the enemy's Disenchant with Malison, then capture the Fire Elemental. Keep the Sapling for the Ogre and Rock Wall for the Wolf. Use the next refill to capture the Ogre."],
        "Malison removes the enemy's only dispel. Capturing the Fire Elemental uses five more ether, "
        "leaving exactly one for the Sapling's regeneration. If the enemy attacks, block the Ogre with "
        "the Sapling and the evasive Wolf with Rock Wall. Do not let the captured Elemental kill the "
        "Ogre: the objective needs that exact creature alive. The next five-channel refill pays for "
        "the second Change of Command. Taking the Ogre first leaves the Elemental's anti-regeneration "
        "strike facing a protected Sapling; keeping the dispel in the enemy's hand lets them undo a capture.",
        [cast("MALS", 1), cast("CHCM", 4), end(), attack(5, side=1), attack(6, side=1), end(side=1),
         block(2, 5), block(3, 6), end(), cast("CHCM", 5)],
        objective={"type": "control", "targets": [4, 5], "protect": [2]},
        refutations=[
            {"label": "Capture the Ogre first", "commands": [cast("CHCM", 5)]},
            {"label": "Spend two ether weakening the Wolf", "commands": [cast("WEAK", 6)]},
            {"label": "Pass after capturing while the enemy still holds Disenchant", "commands": [cast("CHCM", 4), end()]},
        ],
        title_ru="Безопасный переход", category_ru="Перехват контроля и резерв на защиту",
        briefing_ru="За два хода подчините Элементаля огня и Серого людоеда, сохранив обоих в живых. "
        "Ваш Молодой древень тоже должен выжить. Единственная карта врага — Снятие Чар.",
        hints_ru=["На два подчинения сразу эфира нет. Решите, какой атакующий останется врагом и как сохранить новые чары на протяжении его хода.",
                  "Древень регенерирует после удара Людоеда, но Элементаль огня запрещает регенерацию. После первого подчинения нужна ещё единица эфира.",
                  "Проклятием сбросьте рассеивание врага и подчините Элементаля огня. Оставьте Древня для Людоеда, стену — для Волка. Следующее пополнение эфира потратьте на Людоеда."],
        explanation_ru="Проклятие убирает единственное рассеивание врага. Подчинение Элементаля стоит ещё пять "
        "эфира; остаётся ровно один для регенерации Древня. При атаке врага блокируйте Людоеда Древнем, "
        "а обходящего обычных защитников Волка — Каменной стеной. Не убивайте Людоеда захваченным Элементалем: "
        "цель требует сохранить именно это существо. Следующее пополнение от пяти каналов оплачивает второе "
        "Переподчинение. Захват Людоеда первым оставляет защищаемого Древня против удара Элементаля, "
        "запрещающего регенерацию. Оставленное в руке рассеивание позволяет врагу отменить захват.",
    ))

    out.append(puzzle(
        game, "wings_outlive_wizard", "Wings Outlive the Wizard", "Lingering effects and sacrificed auras", 3, 1,
        state(game,
              hero("Blue", [], mana=2, health=5, enchantments=[enchant("CMBN", id=1), enchant("CMBN", id=2)]),
              hero("Blue", [], health=30),
              [unit("WRSP", 2), unit("WZSP", 3), unit("SHSP", 4, enchantments=[enchant("MGHT", id=3)]), unit("RKWL", 5),
               unit("BUDG", 6, 1, damage=1, enchantments=[enchant("SHSK", id=4)]),
               unit("GROG", 7, 1), unit("SHWL", 8, 1)],
              phase=1, attacker=1, attacks=[6, 7, 8]),
        "Survive this attack while preserving your Warrior Spirit and Rock Wall. You have five health. "
        "Two copies of Martyrdom are active. The wounded Dragon leads the attack; none of your creatures currently flies.",
        ["A granted effect can outlive its source, while an aura usually cannot.",
         "Give the Warrior Spirit flight before sacrificing the Wizard. Recalculate its power after each lost Spirit aura; the Dragon needs eleven more damage. The Shaman already carries Might.",
         "Use the Wizard's flight ability, then both copies of Martyrdom to feed the Wizard and Shaman to the Warrior. Block the Dragon with the Warrior and the Ogre with Rock Wall; let the Wolf through."],
        "The Wizard's flight effect lasts through this enemy turn even after the Wizard dies. Its "
        "+2-power aura does not. Martyrdom adds the Wizard's 3/2 and the enhanced Shaman's 5/4, but their auras "
        "disappear, so the Warrior ends at 11/7. Its first strike supplies "
        "the eleven damage needed to kill the wounded 8/12 Dragon before retaliation. Rock Wall blocks "
        "the six-power Ogre, while the Wolf's four damage leaves one hero health. Life drain does not "
        "heal the hero for damage dealt to a creature, so letting the Ogre through is fatal. "
        "Both sacrifices must contribute to the Warrior; combining them first is also valid if flight was granted. "
        "Sacrificing the Wizard before granting flight makes the air lane impossible.",
        [ability(3, "spirit_flight"), ability(0, "combine:1", 3, choice=2),
         ability(0, "combine:2", 4, choice=2), block(2, 6), block(5, 7), end()],
        objective={"type": "survive", "enemy_turns": 1, "protect": [2, 5]},
        refutations=[
            {"label": "Sacrifice the Wizard before it grants flight", "commands": [ability(0, "combine:1", 3, choice=2)]},
            {"label": "Give the enhanced Shaman's strength to the Wall", "commands": [ability(0, "combine:2", 4, choice=5)]},
            {"label": "Preserve the Shaman as a blocker rather than transferring its power", "commands": [ability(3, "spirit_flight"), ability(0, "combine:1", 3, choice=2), block(2, 6), block(5, 7), end()]},
            {"label": "Block the evasive Wolf and rely on life drain against the Dragon", "commands": [ability(3, "spirit_flight"), ability(0, "combine:1", 3, choice=2), ability(0, "combine:2", 4, choice=2), block(2, 6), block(5, 8), end()]},
        ],
        title_ru="Крылья переживут колдуна", category_ru="Длительные эффекты и потеря аур",
        briefing_ru="Переживите атаку, сохранив Призрака-воина и Каменную стену. У героя пять здоровья. "
        "Действуют два Самопожертвования. Раненый Дракон возглавляет атаку; сейчас ни одно ваше существо не летает.",
        hints_ru=["Дарованная способность может пережить свой источник, а аура обычно исчезает вместе с ним.",
                  "Дайте Воину полёт, прежде чем пожертвовать Колдуном. После каждой утраты ауры пересчитайте силу; Дракону нужно нанести ещё одиннадцать урона. На Шамане уже есть Мощь.",
                  "Способностью Колдуна дайте Воину полёт. Двумя Самопожертвованиями передайте Воину силу Колдуна и Шамана. Воином блокируйте Дракона, стеной — Людоеда; пропустите Волка."],
        explanation_ru="Полёт от Колдуна действует до конца этого вражеского хода, даже если Колдун погибнет. "
        "Его аура +2 к силе при этом исчезает. Самопожертвование передаёт Воину 3/2 Колдуна и 5/4 усиленного Шамана, "
        "но убирает их ауры: получается 11/7. Первый удар наносит одиннадцать урона "
        "раненому Дракону 8/12 и убивает его до ответного удара. Стена блокирует Людоеда с силой шесть, "
        "а четыре урона Волка оставляют герою единицу здоровья. Похищение жизни не исцеляет героя за урон "
        "существам, поэтому пропускать Людоеда нельзя. Сила обеих жертв должна перейти Воину; можно и сначала "
        "объединить их, если полёт уже дарован. Если пожертвовать Колдуном до того, как он даст полёт, "
        "вы останетесь без воздушного защитника.",
    ))

    out.append(puzzle(
        game, "useful_survivor", "The Useful Survivor", "Selective dispelling and enemy regeneration", 2, 1,
        state(game,
              hero("Blue", ["CLIG", "CTST", "HUNG"], mana=11, health=2, enchantments=[enchant("COPL", id=1)]),
              hero("Green", [], mana=1, health=6, enchantments=[enchant("COPL", id=2)]),
              [unit("PTRS", 2), unit("TNSA", 3, 1), unit("RKWL", 4, 1)]),
        "Win this turn. Both heroes have Life Channel. Your Pteros can remove one enchantment, "
        "and the enemy has exactly one ether for regeneration. A symmetric disaster would kill you first.",
        ["An enemy surviving a spell can be useful if its regeneration heals the right hero.",
         "Remove the enemy's Life Channel before provoking regeneration. Keep yours and budget for Catastrophe's printed cost plus X.",
         "Use the Pteros to dispel the enemy Life Channel, strike the enemy Sapling with Call Lightning, then cast Catastrophe with X = 6."],
        "The Pteros pays two ether to remove the enemy's Life Channel. Lightning costs one and forces "
        "the Sapling's automatic regeneration, spending its owner's last ether. Only your remaining Life "
        "Channel triggers, raising you from two health to seven. Your eight remaining ether pays the "
        "two-cost Catastrophe plus X=6: you survive on one, and the enemy falls. Triggering regeneration "
        "before removing the enemy channel also heals that hero to eleven, beyond your lethal budget.",
        [ability(2, "dispel", 1, choice=2), cast("CLIG", 3), cast("CTST", power=6)],
        refutations=[
            {"label": "Provoke regeneration while both Life Channels remain", "commands": [cast("CLIG", 3)]},
            {"label": "Dispel your own Life Channel", "commands": [ability(2, "dispel", 0, choice=1)]},
            {"label": "Spend the damage spell on the wall", "commands": [cast("CLIG", 4)]},
        ],
        title_ru="Полезный выживший", category_ru="Выборочное рассеивание и регенерация врага",
        briefing_ru="Победите за этот ход. На обоих героях действует Канал Жизни. Птерос может снять одни чары, "
        "а у врага есть ровно единица эфира для регенерации. Симметричная катастрофа сначала погубит вас.",
        hints_ru=["Выживание врага после заклинания полезно, если его регенерация лечит нужного героя.",
                  "Снимите вражеский Канал Жизни до регенерации. Сохраните свой и учтите обычную цену Катастрофы сверх X.",
                  "Птеросом рассеяйте Канал Жизни на враге, ударьте его Молодого древня Молнией и примените Катастрофу с X = 6."],
        explanation_ru="Птерос тратит два эфира на снятие вражеского Канала Жизни. Молния за единицу эфира "
        "вызывает автоматическую регенерацию Древня, расходуя последний эфир врага. Срабатывает только ваш "
        "Канал Жизни: здоровье растёт с двух до семи. Оставшихся восьми единиц эфира хватает на обычную цену "
        "Катастрофы два и X=6. Вы остаётесь с единицей здоровья, враг погибает. Регенерация до снятия вражеских "
        "чар исцелит и соперника до одиннадцати — на смертельную Катастрофу эфира уже не хватит.",
    ))

    return out
