"""EL2 master studies: aspect tactics, delayed clocks and resource commitments."""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end


def puzzles():
    game = "el2"
    out = []

    out.append(puzzle(game, "shared_escape", "A Shared Escape", "Capture and a counterspell window", 3, 1,
        state(game,
            hero("Blue", ["CLNP", "CHCM"], mana=8, health=2, enchantments=[enchant("PRWR", id=1, owner=1), enchant("ENBR", id=2), enchant("OEXC", id=3)]),
            hero("Green", ["PLMR"], mana=1, channels=1, health=30),
            [unit("OUE1", 2, plane=True), unit("IRMZ", 3), unit("SMWB", 4, 1), unit("GROG", 5, 1)]),
        "Control the enemy Pale Knight after one complete enemy turn. Keep your Spelleater alive. Transfer Aspects and an enemy Aspect Ward are already on your hero; the opponent holds Polymorph.",
        ["Both your new captive and your protected helper must survive an enemy spell window.",
         "Removing Aspect Ward must leave the Spelleater ready. A manifestation through Transfer Aspects does not rest it.",
         "Use Lesser Disenchant on Aspect Ward, capture the Knight, and exchange its aspect with the Spelleater. Dissipate the still-ready Spelleater. Keep the Iron Mechozaurus to stop the Ogre."],
        "Lesser Disenchant removes the ward for two ether. Change of Command costs five, and Transfer Aspects uses the last ether to manifest your Spelleater while sheltering the sick captive in the Colourless Plane. The Spelleater must then dissipate itself. Absorbing the ward would refund its cost but rest the only helper that still needs to escape Polymorph. Energy Barrier reduces the Mechozaurus's four upkeep damage to one, leaving your hero alive. The untargetable Mechozaurus can stop the Ogre while both Pale creatures remain safe through the enemy turn.",
        [cast("CLNP", 0, grave=1), cast("CHCM", 4), ability(0, "recycle:3", 2, choice=4), ability(2, "dissipate"),
         end(), attack(5, side=1), end(side=1), block(3, 5), end()],
        objective={"type": "control", "targets": [4], "enemy_turns": 1, "protect": [2]},
        refutations=[
            {"label": "Absorb the ward for its refund", "commands": [ability(2, "absorb", 0, choice=1)]},
            {"label": "Exchange aspects before capturing the Knight", "commands": [ability(0, "recycle:3", 2, choice=4)]},
            {"label": "Capture the Ogre instead of the Knight", "commands": [cast("CHCM", 5)]},
        ]))

    out.append(puzzle(game, "sealed_response", "Seal the Response", "Manifestation order and resource denial", 4, 1,
        state(game,
            hero("White", ["PLSL", "ALNS"], mana=3, health=9, grave=["STRT"]),
            hero("White", ["PLMR"], mana=5, channels=1, health=13, enchantments=[enchant("OST2", id=1)]),
            [unit("SMWB", 2, plane=True), unit("OUS2", 3, plane=True), unit("OUD3", 4, 1, plane=True), unit("OUE3", 5, 1, plane=True)]),
        "Win this turn. The enemy has a Pale Slayer, a Spellshifter with five ether, and a Pale Revenant trap. Your Knight has one graveyard card available for manifestation.",
        ["A normal attack lets the defender bring a body out of the Colourless Plane. Seal creates another body as well as closing the plane.",
         "The enemy can pay five ether to transpose your Seal. Remove that payment before the defence phase, without losing the Knight's manifestation.",
         "Manifest the Knight using the graveyard. Have the Invoker drain the enemy hero's five ether for five damage. Cast Seal only after the Knight is bright, then attack for eight."],
        "The Knight must become bright before the global seal takes effect. The Invoker's five-point drain reduces the enemy from thirteen health to eight and removes the five ether needed to transpose Seal. Seal triggers the trap, but the new Revenant enters the Colourless Plane and cannot manifest under the same seal. The Slayer also remains trapped there. The Knight's eight-point attack therefore finishes the hero. Spending on Mark of Pale leaves no Seal, and sealing too early locks your own finisher away.",
        [ability(2, "sinister", 0, choice=0), ability(3, "ether_plea", 1), cast("PLSL"), attack(2), end(), end(side=1)],
        refutations=[
            {"label": "Seal before manifesting the Knight", "commands": [cast("PLSL")]},
            {"label": "Spend the Invoker's damage on your own hero", "commands": [ability(3, "ether_plea", 0)]},
            {"label": "Buy Mark of Pale before the seal", "commands": [ability(2, "sinister", 0, choice=0), cast("ALNS", 2)]},
            {"label": "Commit the Knight without sealing the defence", "commands": [ability(2, "sinister", 0, choice=0), ability(3, "ether_plea", 1), attack(2), end()]},
        ]))

    out.append(puzzle(game, "surviving_investment", "The Surviving Investment", "Channel conversion and delayed income", 3, 2,
        state(game,
            hero("White", ["STSK"], channels=1, health=5),
            hero("Green", [], health=30),
            [unit("OUS1", 2, plane=True), unit("OUD3", 3, plane=True), unit("WNMG", 4, 1),
             unit("ANTN", 5, 1, enchantments=[enchant("MNBR", id=1, owner=0), enchant("MNBR", id=2, owner=0)])]),
        "Clear the enemy army within two turns and finish with at least four ether. Keep your Pale Slayer alive. You have one channel, no ether, and two Ether Breezes on the enemy Ancient Treant.",
        ["The enemy carrying your investment has to remain alive until the next refill.",
         "The Channeler can turn a channel into immediate ether; the Slayer can recover the channel by killing a suitable target.",
         "Convert the channel, slay the Maggot, and allow the Treant to survive the enemy turn. At your next turn, the recovered channel and both Breezes provide seven ether. Slay the Treant for three and finish with four."],
        "The first conversion funds exactly one use of the Slayer. Killing the Maggot recovers a channel while preserving both three-ether Breeze triggers. The Treant can hit your hero for four, leaving one health, but neither Pale helper needs to enter the bright aspect. Your next refill provides one channel ether plus six from the living Treant. The second slay costs three, leaving the required four. Killing the Treant first destroys the future income; burning another channel then can fund the last kill but cannot meet the finishing reserve.",
        [ability(2, "channel_ether"), ability(3, "pale_devour", 4), end(), attack(5, side=1), end(side=1), end(), ability(3, "pale_devour", 5)],
        objective={"type": "clear", "finish_mana": 4, "protect": [3]},
        refutations=[
            {"label": "Manifest the Slayer with the only channel", "commands": [ability(3, "fiendish")]},
            {"label": "Slay the creature carrying both investments first", "commands": [ability(2, "channel_ether"), ability(3, "pale_devour", 5)]},
            {"label": "Spend the converted ether on Stone Skin", "commands": [ability(2, "channel_ether"), cast("STSK", 0)]},
        ]))

    out.append(puzzle(game, "delayed_verdicts", "Two Delayed Verdicts", "A delayed clock and remaining toughness", 4, 2,
        state(game,
            hero("White", ["SHSK", "PRBN", "PRBN", "ZAPP", "ZAPP", "MALS", "OBLS"], mana=11, health=8,
                 enchantments=[enchant("PLWP", id=1), enchant("PLWP", id=2), enchant("FTDS", id=3)]),
            hero("White", ["CLNP"], mana=2, channels=2, health=13),
            [unit("OUE2", 2, resting=True, damage=1), unit("OUE3", 3, plane=True, resting=True),
             unit("SMWB", 4, 1, resting=True, damage=5, enchantments=[enchant("IMMB", id=4, owner=0)]),
             unit("SMTG", 5, 1, resting=True, damage=2, enchantments=[enchant("IMMB", id=5, owner=0)])]),
        "Win within two turns while preserving your Pale Spellweaver and Spellshifter. Two Pale Warps will trigger at the start of your next turn. Fatal Disease keeps all wounds. The opponent has one Lesser Disenchant and two ether.",
        ["The Warps choose the Pale creature with the least remaining toughness, from either army. A tie is not a safe plan for your own helper.",
         "Prepare two victims below your protected creatures, stop dissipation from saving them, and account for the opponent's dispel.",
         "Give the wounded Spellweaver Shell Skin. Lock both enemy aspects, Zap each enemy once, and discard the enemy's Lesser Disenchant with Malison. Leave Fatal Disease and both Pale Warps intact; their next triggers kill the locked Knight and Zealot."],
        "Shell Skin raises the wounded Spellweaver's remaining toughness from one to five. Each wounded enemy starts with three remaining toughness; one Zap apiece lowers both to two, below the three-toughness Spellshifter. Fatal Disease preserves that ordering across turn cleanup. Lock Aspect makes the delayed lethal effects destroy their victims rather than dissipate them, dealing their printed powers of eight and five to the enemy hero. Malison removes Lesser Disenchant: otherwise the opponent can remove Fatal Disease, letting its army recover while the plane-bound Spellshifter becomes the next victim. Blast removes the newest enchantment before damaging. Stacking two Locks buys an immediate kill, but spends too much to prepare and protect the remaining verdict.",
        [cast("SHSK", 2), cast("PRBN", 4), cast("PRBN", 5), cast("ZAPP", 4), cast("ZAPP", 5), cast("MALS", 1),
         end(), end(side=1)],
        objective={"type": "win", "protect": [2, 3]},
        refutations=[
            {"label": "Put Shell Skin on the wounded Knight", "commands": [cast("SHSK", 4)]},
            {"label": "Manifest, stack two Locks and Blast the Knight immediately", "commands": [ability(3, "mystic", 4, choice=4), cast("PRBN", 4), cast("PRBN", 4), cast("OBLS", 4)]},
            {"label": "Use one Lock Aspect on your Spellweaver", "commands": [cast("PRBN", 2)]},
            {"label": "Pass with both victims prepared but leave the dispel in hand", "commands": [cast("SHSK", 2), cast("PRBN", 4), cast("PRBN", 5), cast("ZAPP", 4), cast("ZAPP", 5), end()]},
        ]))

    out.append(puzzle(game, "airlock_census", "Airlock Census", "Beacon, dispel access and a body count", 3, 1,
        state(game,
            hero("White", ["STRT", "OFLX"], mana=3, health=7),
            hero("White", [], health=30, enchantments=[enchant("PRWT", id=1)]),
            [unit("OUE1", 2, plane=True, enchantments=[enchant("PRGD", id=2)]), unit("OUE3", 3, plane=True),
             unit("GROG", 4, damage=5, enchantments=[enchant("SHSK", id=3)]), unit("TIWR", 5), unit("AVSC", 6), unit("RKWL", 7),
             unit("OUD3", 8, 1, plane=True, damage=2), unit("SMWB", 9, 1, plane=True, damage=4)]),
        "Clear the enemy army this turn, preserve your Spelleater and Spellshifter, and finish with at least five allied creatures. Paleness sends new summons to the Colourless Plane. Your Spelleater carries Beacon; Shell Skin is your only enchantment currently outside the plane.",
        ["Flux counts your non-Pale creatures even when they are in the Colourless Plane, then damages every creature in that plane.",
         "Both protected casters must become bright. The Beacon itself is inaccessible to a dispel while its bearer remains in the plane.",
         "Summon the Stink Rat. Manifest the Beacon-bearing Spelleater by removing Shell Skin from the wounded Ogre: Beacon brings the Spellshifter along. The Ogre dies, leaving four non-Pale bodies to power Flux."],
        "The new Rat raises the non-Pale count from four to five even though Paleness places it in the Colourless Plane. Removing Shell Skin kills the wounded Ogre and drops that count to four. The bearer must perform Mystic manifestation: Beacon then brings the other caster out as well. Manifesting only the Spellshifter strands the Spelleater, because its Beacon is still in the plane and cannot be dispelled. Flux calculates four damage before applying it; both wounded enemies and the new Rat die. Your five survivors are the Spelleater, Spellshifter, Tick Warrior, Scout and wall. Absorbing Shell Skin produces ether but consumes the only accessible enchantment without opening the airlock.",
        [cast("STRT"), ability(2, "mystic", 4, choice=3), cast("OFLX")],
        objective={"type": "clear", "protect": [2, 3], "min_allies": 5},
        refutations=[
            {"label": "Manifest the Spellshifter instead of the Beacon bearer", "commands": [ability(3, "mystic", 4, choice=3)]},
            {"label": "Cast Flux while your casters remain in the plane", "commands": [cast("OFLX")]},
            {"label": "Absorb Shell Skin for extra ether", "commands": [ability(2, "absorb", 4, choice=3)]},
        ]))
    out.append(puzzle(game, "last_breath", "The Last Breath", "Healing order and the final body count", 3, 1,
        state(game,
            hero("Green", ["SYMB", "SHSK", "ZAPP"], mana=3, health=1, enchantments=[enchant("SFGS", id=1)]),
            hero("Blue", [], health=3),
            [unit("SPFG", 2, resting=True), unit("AVSC", 3, resting=True), unit("ORSH", 4, resting=True), unit("RKWL", 5),
             unit("TIWR", 6, 1), unit("AVSC", 7, 1)]),
        "Win this turn with at least eleven health and two allied creatures remaining. Suffocating Gas will strike everyone at the end of your turn. All of your creatures except the wall are resting.",
        ["Symbiosis measures every creature still in play. Finishing health is checked when you win, so you may begin below the target.",
         "The Fingus can release spores while resting. That damage saves an ether but removes a creature from the healing count.",
         "Cast Symbiosis while all six creatures remain. Give Shell Skin to the Scout or Shaman, then release the Fingus's spores at the enemy hero. End the turn: the gas finishes the enemy, and your wall plus the sheltered creature survive."],
        "Symbiosis counts six bodies and heals twelve, raising you from one health to thirteen. The Fingus then supplies the single point needed to leave the enemy at two. Shell Skin lets either the Scout or Shaman survive alongside the wall; the other small ally and both enemies die in the gas. Its two damage leaves your hero at exactly eleven when the opponent reaches zero. Releasing spores before Symbiosis loses two healing. Spending ether on Zap leaves too little for both the heal and the protective enchantment. Shell Skin on the Fingus is lost when it sacrifices itself.",
        [cast("SYMB"), cast("SHSK", 3), ability(2, "spores", 1), end()],
        objective={"type": "win", "finish_health": 11, "min_allies": 2},
        refutations=[
            {"label": "Release the spores before healing", "commands": [ability(2, "spores", 1)]},
            {"label": "Use Zap for the opening point of damage", "commands": [cast("ZAPP", 1)]},
            {"label": "Armor the Fingus before its sacrifice", "commands": [cast("SHSK", 2)]},
        ]))
    for entry in out:
        entry.update(_LOCALIZED[entry["id"].removeprefix("el2_tactical_v2_")])
    return out


_LOCALIZED = {
    "shared_escape": {
        "title_ru": "Путь для двоих",
        "category_ru": "Захват и ответное заклинание",
        "briefing_ru": "После завершения одного вражеского хода управляйте Бесцветным Рыцарем противника. Сохраните своего Чароеда. На вашем герое уже действуют Обмен Планами и вражеский Планарный Барьер; противник держит Превращение.",
        "hints_ru": [
            "Ответное заклинание должны пережить и новый пленник, и защищаемый помощник.",
            "После снятия Планарного Барьера Чароед должен остаться готовым к действию. Обмен Планами сам по себе не отправляет его отдыхать.",
            "Снятием Чар уберите Планарный Барьер, переподчините Рыцаря и обменяйте его план с Чароедом. Затем готовым Чароедом уйдите обратно в Бесцветный План. Железного мехозавра оставьте для блока людоеда.",
        ],
        "explanation_ru": "Снятие Чар убирает барьер за два эфира. Переподчинение стоит пять, а последний эфир оплачивает Обмен Планами: Чароед выходит в Эфирный План, а ещё не готовый к действиям пленник скрывается в Бесцветном. Чароед должен сразу уйти следом. Если поглотить барьер, его стоимость вернётся, но Чароед начнёт отдыхать и уже не сможет спастись от Превращения. Энергетический Барьер уменьшает четыре урона от содержания мехозавра до одного, сохраняя жизнь герою. Сам мехозавр недоступен для направленных заклинаний и может остановить людоеда, пока оба бесцветных пережидают вражеский ход.",
    },
    "sealed_response": {
        "title_ru": "Запечатать ответ",
        "category_ru": "Переход между планами и лишение эфира",
        "briefing_ru": "Победите за этот ход. У врага есть Бесцветный Убийца, Ловкач с пятью единицами эфира и ловушка Бесцветного Карателя. Для выхода вашего Рыцаря из Бесцветного Плана в могильнике есть одна карта.",
        "hints_ru": [
            "Обычная атака позволит врагу вывести защитника из Бесцветного Плана. Печать не только закроет переходы, но и вызовет ещё одно создание.",
            "Враг может заплатить пять эфира и снять вашу Печать Ловкачом. Лишите его этой возможности до фазы защиты, не заперев собственного Рыцаря.",
            "Выведите Рыцаря в Эфирный План, потратив карту из могильника. Чародеем заберите весь вражеский эфир и нанесите пять урона герою. Лишь затем наложите Печать и атакуйте Рыцарем на восемь.",
        ],
        "explanation_ru": "Рыцарь должен выйти до того, как Печать запретит все переходы. Способность Чародея уменьшает вражеские жизни с тринадцати до восьми и лишает Ловкача пяти эфира, необходимых для снятия Печати. Колдовство активирует ловушку, но новый Каратель появляется в Бесцветном Плане и уже не может выйти. Там же остаётся Убийца. Удар Рыцаря на восемь добивает героя. Клеймо Бесцветности оставит вас без эфира для Печати, а слишком ранняя Печать запрёт вашего собственного бойца.",
    },
    "surviving_investment": {
        "title_ru": "Живой источник дохода",
        "category_ru": "Обмен каналов и отложенное пополнение",
        "briefing_ru": "Уничтожьте вражескую армию за два хода и завершите задачу хотя бы с четырьмя единицами эфира. Сохраните Бесцветного Убийцу. У вас один канал, пустой запас эфира и два Эфирных Бриза на вражеском Вековом древне.",
        "hints_ru": [
            "Враг, на котором держится ваш будущий доход, должен дожить до следующего пополнения.",
            "Маг превращает канал в немедленный запас эфира, а Убийца может вернуть канал, уничтожив подходящую цель.",
            "Превратите канал в эфир, убейте Маггота и оставьте древня в живых на вражеский ход. Затем восстановленный канал и два Бриза дадут семь эфира. Убийство древня стоит три: останется нужный запас в четыре.",
        ],
        "explanation_ru": "Первая жертва канала оплачивает ровно одно применение Убийцы. Уничтожение Маггота возвращает канал и сохраняет оба будущих поступления по три эфира. Древень может нанести герою четыре урона, оставив одну жизнь; ни одному из бесцветных помощников не требуется выходить в Эфирный План. В начале следующего хода канал даёт один эфир, а живой древень — ещё шесть. Второе убийство стоит три и оставляет четыре. Если сначала убрать древня, исчезнет будущий доход. Ещё одна жертва канала позволит оплатить последний удар, но не обеспечит необходимый запас к завершению.",
    },
    "delayed_verdicts": {
        "title_ru": "Два отложенных приговора",
        "category_ru": "Отложенная угроза и оставшаяся стойкость",
        "briefing_ru": "Победите за два хода, сохранив своих Бесцветных Ткача и Ловкача. В начале вашего следующего хода сработают две Деформации Бесцветности. Роковая Болезнь сохраняет все раны. У противника одно Снятие Чар и два эфира.",
        "hints_ru": [
            "Деформация выбирает бесцветное создание с наименьшей оставшейся стойкостью из обеих армий. Равенство опасно для вашего помощника.",
            "Сделайте оставшуюся стойкость двух жертв ниже, чем у защищаемых созданий, запретите спасительный переход и учтите вражеское снятие чар.",
            "Наложите Ледяной Панцирь на раненого Ткача. Свяжите обоих врагов Эфирными Узами, ударьте каждого Электрошоком и сбросьте Снятие Чар с помощью Проклятия. Сохраните Болезнь и обе Деформации: в начале хода они уничтожат связанных Рыцаря и Воина.",
        ],
        "explanation_ru": "Панцирь поднимает оставшуюся стойкость раненого Ткача с одного до пяти. У каждого врага сначала остаётся по три; Электрошок снижает оба значения до двух — ниже трёх единиц Ловкача. Болезнь сохраняет этот порядок после окончания ходов. Эфирные Узы заменяют спасительный переход уничтожением, и герой получает базовую силу погибших: восемь и пять. Проклятие убирает Снятие Чар: иначе враг снимет Болезнь, его армия восстановится, а следующим погибнет находящийся в Бесцветном Плане Ловкач. Бесцветный Удар сначала снимает самые новые чары. Две копии Уз позволяют немедленно убить одну цель, но стоят слишком дорого, чтобы подготовить и защитить оставшийся приговор.",
    },
    "airlock_census": {
        "title_ru": "Перепись у шлюза",
        "category_ru": "Маяк, доступность чар и число созданий",
        "briefing_ru": "Уничтожьте армию врага за этот ход, сохраните Чароеда и Ловкача и завершите задачу хотя бы с пятью союзными созданиями. Обесцвечивание отправляет новые создания в Бесцветный План. Чароед несёт Маяк; Ледяной Панцирь — ваши единственные чары вне этого плана.",
        "hints_ru": [
            "Бесцветный Шторм считает ваши небесцветные создания даже в Бесцветном Плане, а затем наносит урон всем созданиям в этом плане.",
            "Оба защищаемых мага должны выйти в Эфирный План. Сам Маяк нельзя снять, пока его носитель остаётся в Бесцветном.",
            "Вызовите Вонючую крысу. Выведите Чароеда с Маяком, сняв Панцирь с раненого людоеда: Маяк выведет и Ловкача. Людоед погибнет, оставив четыре небесцветных создания для Бесцветного Шторма.",
        ],
        "explanation_ru": "Новая крыса увеличивает число небесцветных созданий с четырёх до пяти, хотя Обесцвечивание отправляет её в Бесцветный План. Снятие Панциря убивает раненого людоеда, возвращая число к четырём. Выйти должен именно носитель Маяка: тогда следом выйдет второй маг. Если первым вывести Ловкача, Чароед останется заперт: его Маяк ещё находится в Бесцветном Плане и недоступен для снятия. Шторм вычисляет четыре урона до применения: погибают оба раненых врага и новая крыса. Остаются пять союзников — Чароед, Ловкач, Клещ-воин, авиак и стена. Поглощение Панциря даст эфир, но потратит единственные доступные чары, не открыв шлюз.",
    },
    "last_breath": {
        "title_ru": "Последний вдох",
        "category_ru": "Порядок лечения и число выживших",
        "briefing_ru": "Победите за этот ход, завершив его хотя бы с одиннадцатью жизнями и двумя союзными созданиями. Удушающий Газ поразит всех в конце вашего хода. Все ваши создания, кроме стены, отдыхают.",
        "hints_ru": [
            "Симбиоз считает все создания, ещё находящиеся в игре. Требование к жизням проверяется в момент победы: сейчас их может быть меньше.",
            "Фингус выпускает споры даже во время отдыха. Этот урон экономит эфир, но убирает одно создание из будущего подсчёта лечения.",
            "Примените Симбиоз, пока в игре все шесть созданий. Наложите Ледяной Панцирь на авиака или шамана, затем направьте споры фингуса во вражеского героя. Завершите ход: газ добьёт врага, а стена и укрытое создание выживут.",
        ],
        "explanation_ru": "Симбиоз считает шесть созданий и восстанавливает двенадцать жизней: у вас становится тринадцать. Споры фингуса наносят нужную единицу урона, оставляя врагу две жизни. Панцирь позволяет авиаку или шаману выжить вместе со стеной; другой слабый союзник и оба врага погибают от газа. После его двух единиц урона у вас остаётся ровно одиннадцать жизней, а у противника — ноль. Споры до Симбиоза лишают вас двух единиц лечения. Электрошок расходует эфир, необходимый одновременно для лечения и защитных чар. Панцирь на фингусе пропадёт при его жертве.",
    },
}
