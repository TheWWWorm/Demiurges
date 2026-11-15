"""Etherlords II studies of aspects, enchantment order, and borrowed resources.

These positions use normal cards and battle commands. The authored reference
lines deliberately include the defender's strongest available blocks.
"""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end


def puzzles():
    game = "el2"
    out = []

    out.append(puzzle(
        game, "borrowed_tomorrow", "Borrowed Tomorrow", "Pale revival and haste", 2, 1,
        state(game,
              hero("Blue", ["BNSH", "ORFT", "UNSM", "OBLS"], mana=5, health=5),
              hero("Black", [], mana=0, health=3, grave=["SMWB", "MXHP", "MCWO"]),
              [unit("SMWB", 2, 1), unit("RKWL", 3, 1)]),
        "Win this turn with no creatures of your own. The enemy has a Knight and a wall in play, "
        "and three very different creatures in the graveyard. Your five ether must do all the work.",
        ["You need removal and an attacker from the same spell.",
         "Pale Revival can consume an enemy in the Colourless Plane and take a creature from either graveyard. The strongest printed creature may not attack immediately.",
         "Dissipate the enemy Knight, use Pale Revival on it to raise the enemy Maxi Hopper, then Unsummon the wall and attack with the Hopper."],
        "Dissipate moves the enemy Knight into the Colourless Plane for one ether. Pale Revival "
        "then destroys it and raises the enemy graveyard's Maxi Hopper under your control. Haste "
        "lets the Hopper attack immediately for exactly three; Unsummon removes the remaining "
        "wall. Reviving the eight-power Knight instead produces a sick creature in pale aspect, "
        "while the Mech Worm cannot deal enough damage. Blasting first wastes the ether needed "
        "to remove the wall.",
        [cast("BNSH", 2), cast("ORFT", 2, grave=1001), cast("UNSM", 3),
         attack(4), end(), end(side=1)],
        refutations=[
            {"label": "Revive the largest printed creature", "commands": [cast("BNSH", 2), cast("ORFT", 2, grave=1000)]},
            {"label": "Return the Knight to hand instead of moving it into the Plane", "commands": [cast("UNSM", 2)]},
            {"label": "Start by damaging the Knight with Blast", "commands": [cast("OBLS", 2)]},
        ],
        title_ru="Одолженное завтра", category_ru="Бесцветное оживление и готовность",
        briefing_ru="Победите за этот ход, не имея своих существ. У врага на поле Рыцарь и стена, "
        "а на кладбище — три совсем разных существа. На весь план есть пять единиц эфира.",
        hints_ru=["Одно заклинание должно убрать врага и одновременно дать вам атакующего.",
                  "Бесцветное Оживление может уничтожить врага в Бесцветном Плане и взять существо из любого могильника. Самое сильное существо не обязательно сможет атаковать сразу.",
                  "Примените Растворение к вражескому Рыцарю, затем Бесцветное Оживление — и поднимите Большого прыгуна из могильника врага. Развоплощением верните стену в руку и атакуйте Прыгуном."],
        explanation_ru="Растворение за квант эфира отправляет вражеского Рыцаря в Бесцветный План. "
        "Бесцветное Оживление уничтожает его и поднимает под вашим контролем Большого прыгуна из могильника "
        "противника. Благодаря готовности Прыгун сразу атакует и наносит ровно три урона; оставшуюся стену "
        "нужно вернуть в руку Развоплощением. Рыцарь с силой восемь появится неготовым к атаке и в Бесцветном Плане, "
        "а Механическому червяку не хватит силы. Начальный Бесцветный Удар тратит эфир, необходимый для стены.",
    ))

    out.append(puzzle(
        game, "smaller_refund", "The Smaller Refund", "Enchantment economy and counterplay", 3, 1,
        state(game,
              hero("Green", ["BLSS"], mana=2, health=8,
                   enchantments=[enchant("GEWR", id=1)]),
              hero("Blue", ["FOGG"], mana=2, health=1,
                   enchantments=[enchant("GSWR", id=2)]),
              [unit("OUE1", 2, plane=True),
               unit("SMWB", 3, enchantments=[enchant("MGHT", id=3)]),
               unit("RKWL", 4, 1, enchantments=[enchant("TGSK", id=4)]),
               unit("HOPR", 5, 1)]),
        "The Spelleater can turn an enchantment into ether. The enemy holds Fog and has two ether. "
        "Win this turn against both blockers, without opening a defensive escape.",
        ["The largest refund can also make the enemy's hand affordable.",
         "Greater Sorcery Warding doubles both Bless and Fog. Your Knight needs fifteen power to beat the combined blockers, but the enemy must remain unable to cast Fog.",
         "Absorb Greater Enchantment Warding from your hero. Spend the resulting four ether on Bless for the Knight, leaving Greater Sorcery Warding in play; then attack."],
        "Absorbing the three-cost enchantment ward costs one and refunds three, taking your ether "
        "from two to four. The sorcery ward stays in play: Bless costs exactly four and raises the "
        "Knight to fifteen power, while Fog still costs four, more than the enemy has. Even both "
        "blockers together provide only fourteen toughness, so trample deals the final damage. "
        "Absorbing the four-cost sorcery ward gives more ether but makes Fog affordable. Absorbing "
        "Might removes the power your Knight needs. Manifesting the Spelleater gives another "
        "attacker but neither enough damage nor the ether for Bless.",
        [ability(2, "absorb", 0, choice=1), cast("BLSS", 3), attack(3), end(),
         block(4, 3, side=1), block(5, 3, side=1), end(side=1)],
        refutations=[
            {"label": "Take the largest refund by absorbing Greater Sorcery Warding", "commands": [ability(2, "absorb", 1, choice=2)]},
            {"label": "Absorb the Knight's Might instead", "commands": [ability(2, "absorb", 3, choice=3)]},
            {"label": "Manifest for free instead of converting the ward into ether", "commands": [ability(2, "mystic", 0, choice=1)]},
        ],
        title_ru="Меньший возврат", category_ru="Экономия чар и ответ противника",
        briefing_ru="Бесцветный Чароед умеет превращать чары в эфир. У противника в руке Туман "
        "и две единицы эфира. Победите за этот ход, пройдя обоих защитников и не позволив врагу спастись заклинанием.",
        hints_ru=["Самый большой возврат эфира может сделать доступным и заклинание противника.",
                  "Великая защита от колдовства удваивает цену и Благословения, и Тумана. Рыцарю нужно пятнадцать силы против обоих защитников, но Туман должен остаться недоступным врагу.",
                  "Поглотите Великую защиту от чар на своём герое. Потратьте полученные четыре эфира на Благословение Рыцаря, сохранив защиту от колдовства, и атакуйте."],
        explanation_ru="Поглощение защиты от чар стоимостью три сначала тратит единицу эфира, затем "
        "возвращает три: запас растёт с двух до четырёх. Защита от колдовства остаётся. Благословение "
        "стоит ровно четыре и поднимает силу Рыцаря до пятнадцати, а Туман тоже стоит четыре — больше, "
        "чем есть у врага. Суммарная стойкость защитников равна четырнадцати, поэтому избыточный "
        "урон Рыцаря проходит герою. Поглощение более дорогой защиты от колдовства даёт больше эфира, "
        "но открывает врагу Туман. Поглощение Мощи лишает Рыцаря необходимой силы.",
    ))

    out.append(puzzle(
        game, "last_layer", "The Last Layer", "Enchantment order and recycling", 3, 1,
        state(game,
              hero("Blue", ["PRBN", "ALNS", "ALNS", "OBLS", "OBLS"], mana=10, health=5),
              hero("White", [], mana=0, health=6),
              [unit("OUE1", 2, 1), unit("OUD1", 3, 1, damage=1)]),
        "Win this turn without an army. The enemy's Spelleater and wounded Scourge are both in "
        "the Ether. You have one Lock Aspect, two Marks of Pale, and two Blasts.",
        ["Preventing dissipation is only useful if the prevention survives until the damage happens.",
         "Blast removes the newest removable enchantment before dealing three damage. Lock Aspect returns when its creature leaves play, but a cover removed by Blast does not.",
         "Lock the Spelleater, cover the lock with Mark of Pale, then Blast it. Reuse the returned Lock Aspect on the wounded Scourge, add your second Mark, and use the second Blast."],
        "Lock Aspect prevents a Pale creature from dissipating and deals its printed power to its "
        "owner when it leaves play. Blast alone would remove the lock before dealing damage, so "
        "cast Mark of Pale afterwards as the newest layer. Blast strips that mark, restoring the "
        "target's original toughness, then kills it while the lock remains. Its three-power backlash "
        "damages the hero and returns Lock Aspect to your hand. Repeat with the wounded Scourge "
        "using the second Mark and Blast for the remaining three damage. The removed covers do "
        "not return; the one binding does. Independent target order is allowed.",
        [cast("PRBN", 2), cast("ALNS", 2), cast("OBLS", 2),
         cast("PRBN", 3), cast("ALNS", 3), cast("OBLS", 3)],
        refutations=[
            {"label": "Blast immediately after Lock Aspect", "commands": [cast("PRBN", 2), cast("OBLS", 2)]},
            {"label": "Put the lock on top of its cover", "commands": [cast("ALNS", 2), cast("PRBN", 2), cast("OBLS", 2)]},
            {"label": "Spend the first Blast on an unbound creature", "commands": [cast("OBLS", 2)]},
        ],
        title_ru="Последний слой", category_ru="Порядок чар и повторное использование",
        briefing_ru="Победите за этот ход без собственной армии. Вражеские Чароед и раненый Жнец "
        "находятся в Эфирном Плане. У вас одни Эфирные Узы, два Клейма Бесцветности и два Бесцветных Удара.",
        hints_ru=["Запрет перехода в Бесцветный План полезен лишь тогда, когда действует в момент нанесения урона.",
                  "Бесцветный Удар снимает самые свежие доступные чары, а затем наносит три урона. Эфирные Узы возвращаются при уходе носителя; снятое Ударом прикрытие не возвращается.",
                  "Наложите Эфирные Узы на Чароеда, поверх них — Клеймо Бесцветности, затем Бесцветный Удар. Вернувшиеся Узы наложите на раненого Жнеца, добавьте второе Клеймо и второй Удар."],
        explanation_ru="Эфирные Узы не дают бесцветному существу уйти в Бесцветный План и при уходе "
        "носителя наносят его владельцу урон, равный базовой силе. Бесцветный Удар сначала снял бы "
        "сами Узы, поэтому их нужно прикрыть более новым Клеймом Бесцветности. Удар снимает Клеймо, "
        "возвращает исходную стойкость и убивает существо под действующими Узами. Владелец получает "
        "три урона, а Узы возвращаются вам в руку. Повторите на раненом Жнеце со вторым Клеймом "
        "и вторым Ударом. Прикрытия расходуются, но одних Уз хватает на обе цели; порядок целей свободный.",
    ))

    return out
