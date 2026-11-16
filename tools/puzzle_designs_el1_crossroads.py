"""Crossroads: six further deterministic Etherlords I studies.

Existing catalogs and earlier collections remain untouched. Positions use
ordinary battle commands, documented starting conditions and existing goals.
The Last Receipt records two different winning routes through the defence.
"""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end

_PRESENTATION = {'life_installments': {'category': 'One channel across three attacks',
                       'title_ru': 'Жизнь в рассрочку',
                       'category_ru': 'Один канал на три атаки',
                       'briefing': 'Win within three turns, preserving the Gibberling Gang and Rock Wall. You have '
                                   'five ether now, one channel, three health and an active Energize. The Gang is '
                                   'unblockable but does not rise naturally. The enemy has no hand cards. Its active '
                                   'Fireball costs one ether and deals two damage to any target; it starts with no '
                                   'ether and refills one each turn.',
                       'hints': ['The Gang must survive direct damage, pay for your survival and attack again. A '
                                 'larger first hit cannot replace all three jobs.',
                                 'Air Link returns life only when the Gang hits the enemy hero. Shell Skin keeps the '
                                 'Gang alive against Fireball. Your single channel can then fund Energize each later '
                                 'turn.',
                                 'Put Air Link and Shell Skin on the Gang and attack. Block the Fire Elemental with '
                                 'the Wall, letting the Treant through. On each following turn spend your one ether to '
                                 'ready the Gang, then attack again.'],
                       'explanation': 'Air Link costs two and Shell Skin costs three, using the opening five ether. '
                                      'The Gang becomes 4/5, so Fireball cannot kill it. Its first two hits restore '
                                      'four health each. Even when the enemy combines a two-point Fireball at your '
                                      'hero with the Treant’s three-point attack, blocking the six-power Elemental '
                                      'leaves you alive at two health after the first wave and one after the second. '
                                      'Your one channel pays Energize on each later turn, overcoming the Gang’s '
                                      'inability to rise. The third four-point attack defeats the remaining three '
                                      'enemy health. The enemy may choose other Fireball targets or omit attackers; '
                                      'the same defensive plan covers those replies. Strength leaves too little ether '
                                      'to buy both Air Link and Shell Skin, while armour on the Wall leaves the Gang '
                                      'vulnerable.',
                       'briefing_ru': 'Победите за три хода, сохранив Шайку гибберлинов и Каменную стену. У вас пять '
                                      'эфира сейчас, один канал, три здоровья и действует Подзарядка. Шайку нельзя '
                                      'блокировать, но она сама не поднимается. Рука врага пуста. Его Огненный Шар за '
                                      'один эфир наносит два урона любой цели; сейчас эфира нет, каждый ход '
                                      'пополняется один.',
                       'hints_ru': ['Шайка должна пережить прямой урон, оплатить ваше выживание и снова атаковать. '
                                    'Одного усиленного первого удара для всех трёх задач недостаточно.',
                                    'Воздушная Связь возвращает здоровье только при попадании Шайки по вражескому '
                                    'герою. Ледяной Панцирь спасает её от Огненного Шара. Единственный канал затем '
                                    'оплачивает Подзарядку каждый следующий ход.',
                                    'Дайте Шайке Воздушную Связь и Ледяной Панцирь, затем атакуйте. Стеной блокируйте '
                                    'Элементаля огня, пропуская древня. На каждом следующем ходу тратьте единственный '
                                    'эфир на пробуждение Шайки и атакуйте снова.'],
                       'explanation_ru': 'Воздушная Связь стоит два, Ледяной Панцирь — три: начальные пять эфира '
                                         'израсходованы. Шайка становится 4/5, и Огненный Шар её не убивает. Первые '
                                         'два попадания возвращают по четыре здоровья. Даже если враг сочетает два '
                                         'урона Огненного Шара по герою с тремя от древня, блок Элементаля с силой '
                                         'шесть оставляет вас в живых: два здоровья после первой волны и одно после '
                                         'второй. Единственный канал оплачивает Подзарядку на следующих ходах, '
                                         'позволяя Шайке подниматься. Третья атака силой четыре снимает оставшиеся три '
                                         'здоровья врага. Другие цели Огненного Шара или отказ от части атак также '
                                         'покрываются этим планом защиты. После Усиления не хватает эфира одновременно '
                                         'на Воздушную Связь и Ледяной Панцирь; Панцирь на Стене оставляет Шайку '
                                         'уязвимой.',
                       'hero_names': ['Synthet Circuit Medic', 'Chaot Cinder Judge'],
                       'hero_names_ru': ['Лекарь синтетов', 'Судья пепла хаотов']},
 'last_receipt': {'category': 'Two ways to supply the last point before disturbance',
                  'title_ru': 'Последняя квитанция',
                  'category_ru': 'Два пути к последнему урону перед возмущением',
                  'briefing': 'Win before your second attack phase and preserve the Rock Wall. Both heroes are on turn '
                              'fourteen, with the enemy already attacking. Your expert Channeling means the '
                              'level-three enemy will take exactly four ether-disturbance damage at its next turn '
                              'start; it currently has five health. Your own clock is safe. Repair Station is active, '
                              'your graveyard is empty, and your one channel will refill one ether.',
                  'hints': ['Four impending damage is one short. The Repair Station can supply the missing point, but '
                            'first it needs a creature card in your graveyard.',
                            'One route makes a safe combat sacrifice: the Rat holds the non-trampling Elemental, the '
                            'Wall holds the Mechos, and the Bat deals three. Another route creates the corpse with '
                            'Polymorph and prevents combat with Fog.',
                            'Either use those blocks, or Polymorph your own Rat and cast Fog. On your next turn use '
                            'Repair Station on the Rat for one ether, then pass. Its ping leaves four health for the '
                            'enemy’s four-point disturbance.'],
                  'explanation': 'In the combat route, the Rock Wall absorbs the Mechos’s eight damage, the Rat dies '
                                 'blocking the non-trampling Elemental, and the Bat lowers your four health to one. In '
                                 'the spell route, Polymorph costs one, kills your Rat and sets your health to its one '
                                 'toughness; Fog costs the remaining two and prevents combat. Either route supplies '
                                 'the same grave card while preserving the Wall. The next one-ether refill pays Repair '
                                 'Station: the Rat returns to hand and the enemy takes one damage. Passing then '
                                 'reaches the disclosed four-point disturbance and wins before the enemy can act. Fog '
                                 'alone supplies no corpse. Creating the corpse only after the next refill spends the '
                                 'sole ether needed to repair it.',
                  'briefing_ru': 'Победите до своей второй фазы атаки и сохраните Каменную стену. Оба героя находятся '
                                 'на четырнадцатом ходу, враг уже атакует. Ваш высший Контроль означает, что в начале '
                                 'следующего хода враг третьего уровня получит ровно четыре урона от возмущения эфира; '
                                 'сейчас у него пять здоровья. Вашему герою возмущение до срока не грозит. Ремонтная '
                                 'Мастерская действует, могильник пуст, единственный канал пополнит один эфир.',
                  'hints_ru': ['До победы после четырёх ожидаемых урона не хватает единицы. Её даст Ремонтная '
                               'Мастерская, но сначала в вашем могильнике должна появиться карта существа.',
                               'Один путь — безопасная боевая жертва: Крыса удерживает Элементаля без пробивного '
                               'удара, Стена — мехоса, Мышь наносит три. Другой путь создаёт карту в могильнике '
                               'Превращением и предотвращает бой Туманом.',
                               'Либо используйте указанные блоки, либо примените Превращение к своей Крысе и '
                               'произнесите Туман. На следующем ходу за один эфир верните Крысу Ремонтной Мастерской и '
                               'передайте ход. Её урон оставит врагу четыре здоровья перед возмущением на четыре.'],
                  'explanation_ru': 'В боевом плане Каменная стена поглощает восемь урона мехоса, Крыса погибает при '
                                    'блокировании Элементаля без пробивного удара, а Мышь снижает ваши четыре здоровья '
                                    'до одного. В плане с заклинаниями Превращение за один эфир убивает вашу Крысу и '
                                    'устанавливает здоровье равным её единице стойкости; Туман за оставшиеся два '
                                    'предотвращает бой. Оба пути дают одну и ту же карту в могильнике и сохраняют '
                                    'Стену. Следующее пополнение одного эфира оплачивает Ремонтную Мастерскую: Крыса '
                                    'возвращается в руку, враг получает один урон. Передача хода приводит к указанным '
                                    'четырём урона от возмущения и победе до действий врага. Один Туман не даёт карты '
                                    'в могильнике. Если создавать её только после пополнения, уйдёт единственный эфир, '
                                    'нужный для ремонта.',
                  'hero_names': ['Chaot Salvage Clerk', 'Chaot Last Attacker'],
                  'hero_names_ru': ['Сборщик трофеев хаотов', 'Последний налётчик хаотов']},
 'free_midwife': {'category': 'Two broods and two sacrifices',
                  'title_ru': 'Сначала освободите повитуху',
                  'category_ru': 'Два потомства и две жертвы',
                  'briefing': 'Win within two turns and preserve all four original creatures. You have twelve ether '
                              'and one health. Defense prevents your army from attacking. Irritation stops the second '
                              'Mother Tick from using its ability and will deal one to you at your turn end. Each '
                              'Mother’s brood costs four ether; a newborn may be sacrificed even while sick.',
                  'hints': ['Both enchantments must go, and every original creature must stay. Arrange a supply of two '
                            'new sacrifices.',
                            'The first newborn must free the second Mother. Removing Defense first leaves you with '
                            'only one operating Mother, already resting, while Irritation still kills you at turn end.',
                            'Brood with the unenchanted Mother. Sacrifice that newborn to remove Irritation from the '
                            'second Mother. Brood with the freed Mother, then sacrifice its newborn to remove Defense. '
                            'Attack with the Warrior and Worker on both turns.'],
                  'explanation': 'The first four-ether brood supplies a new Tick Warrior. A two-ether sacrificial '
                                 'dispel consumes that newborn and removes Irritation from the second Mother, making '
                                 'another brood possible. Its newborn pays for the other two-ether dispel, removing '
                                 'Defense. The whole chain costs twelve and preserves the four original creatures. The '
                                 'Worker’s shared bonus makes the original Warrior 3/3 and the Worker 1/3; their '
                                 'combined four damage twice defeats eight health. Removing Defense with the first '
                                 'sacrifice does permit an attack, but four damage is not lethal and the remaining '
                                 'Irritation kills your one-health hero before another brood or attack. The two dispel '
                                 'cards may trade places in the correct dependency chain.',
                  'briefing_ru': 'Победите за два хода и сохраните всех четырёх исходных существ. У вас двенадцать '
                                 'эфира и одно здоровье. Защита запрещает армии атаковать. Раздражение не даёт второй '
                                 'Матке клещей использовать способность и нанесёт вам один урон в конце вашего хода. '
                                 'Каждое потомство стоит четыре эфира; новорождённого можно принести в жертву, '
                                 'несмотря на болезнь вызова.',
                  'hints_ru': ['Нужно убрать обе чары и сохранить всех исходных существ. Организуйте появление двух '
                               'новых жертв.',
                               'Первый новорождённый должен освободить вторую Матку. Если сначала снять Защиту, '
                               'останется лишь одна способная действовать Матка, уже отдыхающая, а Раздражение всё ещё '
                               'убьёт вас в конце хода.',
                               'Создайте потомство свободной Маткой. Пожертвуйте новорождённого ради снятия '
                               'Раздражения со второй Матки. Ею создайте ещё одного и пожертвуйте его ради снятия '
                               'Защиты. Оба хода атакуйте Воином и Рабочим.'],
                  'explanation_ru': 'Первое потомство за четыре эфира даёт нового Клеща-воина. Жертвенное рассеивание '
                                    'за два поглощает его и снимает Раздражение со второй Матки, разрешая ещё одно '
                                    'потомство. Её новорождённый становится жертвой второго рассеивания за два, '
                                    'снимающего Защиту. Цепочка стоит двенадцать и сохраняет четырёх исходных существ. '
                                    'Общая прибавка Рабочего делает исходного Воина 3/3, самого Рабочего — 1/3; их '
                                    'суммарные четыре урона дважды снимают восемь здоровья. Снятие Защиты первой '
                                    'жертвой разрешает атаку, но четыре урона не смертельны, а оставшееся Раздражение '
                                    'убивает героя с одним здоровьем до нового потомства или атаки. Два жертвенных '
                                    'рассеивания можно поменять местами внутри верной цепочки.',
                  'hero_names': ['Vital Nursery Keeper', 'Kinet Lockmaker'],
                  'hero_names_ru': ['Хранительница яслей виталов', 'Мастер замков кинетов']},
 'above_flood': {'category': 'Recovery on the ground and in the air',
                 'title_ru': 'Над потопом',
                 'category_ru': 'Подъём на земле и в воздухе',
                 'briefing': 'Win within two turns and preserve your Bat and Wall of Wind. You have seven ether, no '
                             'channels and one health. Your Bat is resting; Energize and Fury are active. Fury forces '
                             'the enemy’s ready creatures to attack. The Fire Elemental is Restless, the Giant Bat '
                             'flies, and the Kobold Shaman can shoot for one damage. The enemy has no hand cards.',
                 'hints': ['You need a lasting hold on the ground threats and a safe answer to the flyer. Merely '
                           'resting creatures will not stop their next recovery.',
                           'Ice Storm can rest the Restless Elemental; Glitterdust cannot. Flood then holds ground '
                           'creatures down, while both Bats can recover. Fury will make the enemy flyer leave its '
                           'defensive post.',
                           'Cast Ice Storm and Flood, then Energize your Bat with the last ether. Attack for three. '
                           'When the Giant Bat is forced to attack, block it with the Wall of Wind. Your Bat rises '
                           'next turn; the enemy flyer is still resting, so attack for the last three.'],
                 'explanation': 'Ice Storm spends four and rests the non-Walls, including the Restless Elemental. '
                                'Flood costs two and prevents the grounded Elemental and Shaman from rising on their '
                                'turn. The last ether readies your own Bat for three damage through the rested '
                                'defenders. The Giant Bat can recover because it flies, but Fury immediately commits '
                                'it to attack. The nine-toughness Wall of Wind safely absorbs its five damage. After '
                                'that attack the Giant Bat rests, while your own flying Bat rises for the second '
                                'three-point hit. Glitterdust leaves the Restless Elemental ready alongside the flyer, '
                                'overwhelming one blocker. Condensed Air holds the flyers instead and allows the '
                                'ground threats to recover.',
                 'briefing_ru': 'Победите за два хода и сохраните свою Летучую мышь и Стену ветра. У вас семь эфира, '
                                'нет каналов и одно здоровье. Мышь отдыхает; действуют Подзарядка и Бешенство. '
                                'Бешенство заставляет готовых врагов атаковать. Элементаль огня не отдыхает после '
                                'атаки, Гигантская летучая мышь летает, Кобольд-шаман может выстрелить на один урон. '
                                'Рука врага пуста.',
                 'hints_ru': ['Нужно надолго удержать наземные угрозы и безопасно ответить летуну. Простое усыпление '
                              'не помешает существам подняться на следующем ходу.',
                              'Снежная Буря усыпляет неутомимого Элементаля, Слепящая Пыль — нет. Затем Наводнение '
                              'удерживает наземных существ, а обе Мыши могут подниматься. Бешенство заставит '
                              'вражеского летуна покинуть защиту.',
                              'Произнесите Снежную Бурю и Наводнение, затем последним эфиром поднимите свою Мышь '
                              'Подзарядкой. Атакуйте на три. Вынужденную атаку Гигантской мыши блокируйте Стеной '
                              'ветра. На следующем ходу ваша Мышь поднимется, а вражеская ещё отдыхает: нанесите '
                              'последние три.'],
                 'explanation_ru': 'Снежная Буря за четыре эфира усыпляет всех, кроме стен, включая неутомимого '
                                   'Элементаля. Наводнение за два не даёт наземным Элементалю и Шаману подняться в их '
                                   'ход. Последний эфир поднимает вашу Мышь для трёх урона мимо отдыхающих защитников. '
                                   'Гигантская мышь поднимается, потому что летает, но Бешенство сразу отправляет её в '
                                   'атаку. Стена ветра с девятью стойкости выдерживает её пять урона. После атаки '
                                   'Гигантская мышь отдыхает, а ваша летучая Мышь поднимается для второго удара на '
                                   'три. Слепящая Пыль оставляет неутомимого Элементаля готовым вместе с летуном, и '
                                   'один блокирующий не справляется. Густой Воздух удерживает летунов вместо наземных '
                                   'врагов и позволяет угрозам на земле подняться.',
                 'hero_names': ['Vital Flood Navigator', 'Synthet Air Marshal'],
                 'hero_names_ru': ['Проводник потопа виталов', 'Воздушный маршал синтетов']},
 'quiet_cleric': {'category': 'A reborn ally helps before it can act',
                  'title_ru': 'Тихий жрец',
                  'category_ru': 'Возрождённый союзник помогает до первого действия',
                  'briefing': 'Clear the enemy army within one turn and preserve your three original creatures. The '
                              'Ogre King and Bat are already attacking. You have seven ether and an unused Second '
                              'Birth, which charges the returned creature’s printed cost. Your grave holds a Cleric '
                              'Spirit, Wizard Spirit and Shaman Spirit. Your Warrior Spirit already has Shell Skin and '
                              'the Wizard’s shared power bonus. Returned Spirits are sick and cannot block '
                              'immediately, but their passive auras already apply.',
                  'hints': ['The new creature need not block. An immediate passive bonus can improve a defender that '
                            'is already ready.',
                            'The Warrior needs six power to kill the King before the return strike. The Wind Wall '
                            'needs two ether of power to kill the Bat. Reserve that second payment when choosing the '
                            'grave card.',
                            'Return the five-cost Cleric Spirit with Second Birth. Its aura makes the Warrior 6/6. '
                            'Spend the remaining two on the Wall of Wind’s power, then block the King with the Warrior '
                            'and the Bat with the Wall.'],
                  'explanation': 'Before the return, the Warrior is 5/5: its printed 3/1, the Wizard’s two power and '
                                 'Shell Skin’s four toughness. The Cleric’s immediate +1/+1 aura makes it 6/6 even '
                                 'though the new Cleric is still sick. First strike then kills the six-toughness Ogre '
                                 'King before its eight-power reply. Returning the Cleric costs five, leaving two '
                                 'ether to make the Wall of Wind 2/9, enough to survive and kill the 3/2 Bat. The '
                                 'obvious stronger-Wizard route leaves only one ether for that Wall; the cheaper '
                                 'Shaman route leaves the Warrior at five power. The reference plan needs the Cleric’s '
                                 'particular mix of cost and passive benefit.',
                  'briefing_ru': 'Очистите вражескую армию за один ход и сохраните трёх исходных существ. Вождь '
                                 'людоедов и Летучая мышь уже атакуют. У вас семь эфира и неиспользованное Второе '
                                 'Рождение, которое берёт печатную цену возвращаемого существа. В могильнике лежат '
                                 'Призрак-жрец, Призрак-колдун и Призрак-шаман. На Призраке-воине уже есть Ледяной '
                                 'Панцирь, и он получает общую прибавку силы Колдуна. Возвращённые духи больны после '
                                 'вызова и сразу блокировать не могут, но их пассивные ауры уже действуют.',
                  'hints_ru': ['Новому существу необязательно блокировать. Немедленная пассивная прибавка может '
                               'усилить уже готового защитника.',
                               'Воину нужно шесть силы, чтобы убить Вождя до ответного удара. Стене ветра нужны два '
                               'эфира силы для убийства Мыши. При выборе карты из могильника сохраните вторую оплату.',
                               'Вторым Рождением верните Жреца за пять эфира. Его аура делает Воина 6/6. Оставшиеся '
                               'два потратьте на силу Стены ветра. Воином блокируйте Вождя, Стеной — Мышь.'],
                  'explanation_ru': 'До возвращения Воин имеет 5/5: печатные 3/1, две силы от Колдуна и четыре '
                                    'стойкости от Ледяного Панциря. Немедленная аура Жреца +1/+1 делает его 6/6, хотя '
                                    'новый Жрец ещё болен после вызова. Первый удар убивает Вождя со стойкостью шесть '
                                    'до ответа силой восемь. Возвращение Жреца стоит пять, оставляя два эфира, чтобы '
                                    'сделать Стену ветра 2/9: она переживает удар Мыши 3/2 и убивает её. Прямой план с '
                                    'более сильным Колдуном оставляет Стене лишь один эфир; более дешёвый Шаман '
                                    'оставляет Воину пять силы. Эталонному плану требуется именно сочетание цены и '
                                    'пассивной прибавки Жреца.',
                  'hero_names': ['Kinet Quiet Council', 'Chaot Siege Choir'],
                  'hero_names_ru': ['Тихий совет кинетов', 'Осадный хор хаотов']},
 'anchor_you_own': {'category': 'Shared bonds and a hostile sacrifice',
                    'title_ru': 'Ваш собственный якорь',
                    'category_ru': 'Общие узы и вражеская жертва',
                    'briefing': 'Win within three turns and preserve both of your creatures. All Abominations are '
                                'resting; your Hopper is ready. The two enemy Steel Abominations have Ether Defense. '
                                'The enemy has no hand cards, but has active Dissolution, one ether and one channel, '
                                'so it can sacrifice its own Bronze Abomination. Earth Bonds prevents every creature '
                                'of the enchanted creature’s race from rising, on both sides.',
                    'hints': ['The protected Steel Abominations still share a race with creatures you can target. '
                              'Choose the holder of the bonds, not only the race.',
                              'Putting Earth Bonds on the enemy’s weaker Abomination gives it an escape: Dissolution '
                              'removes that holder and its enchantment. The same bonds on your own Abomination are '
                              'outside the opponent’s sacrifice choices.',
                              'Cast Earth Bonds on your resting Bronze Abomination. Leave that anchor in place and '
                              'attack with the Hopper on all three turns. The enemy may dissolve its own Bronze '
                              'creature, but the two Steel creatures remain bound.'],
                    'explanation': 'Earth Bonds checks the holder’s race across both armies, so targeting your Bronze '
                                   'Abomination holds the enemy Steel Abominations despite their protection from '
                                   'direct targeting. Your own anchor stays resting, but the Hopper belongs to another '
                                   'race and rises normally. Three two-point attacks defeat six health. Dissolution '
                                   'can remove the enemy’s Bronze creature, but cannot sacrifice yours or remove its '
                                   'Earth Bonds. If the bonds instead sit on the enemy Bronze creature, the opponent '
                                   'can sacrifice it before a recovery and release both Steel creatures. Binding the '
                                   'Hopper chooses the wrong race and does nothing to contain the Abominations.',
                    'briefing_ru': 'Победите за три хода и сохраните обоих своих существ. Все исчадия отдыхают, ваш '
                                   'Прыгун готов. Два вражеских Стальных исчадия защищены от прямого выбора целью. '
                                   'Рука врага пуста, но у него действует Рассеяние, есть один эфир и один канал: он '
                                   'может пожертвовать своим Бронзовым исчадием. Кровные Узы запрещают подниматься '
                                   'всем существам расы носителя по обе стороны поля.',
                    'hints_ru': ['Защищённые Стальные исчадия всё ещё одной расы с существами, которые можно выбрать '
                                 'целью. Выбирайте не только расу, но и носителя уз.',
                                 'Кровные Узы на слабом вражеском исчадии дают противнику выход: Рассеяние уберёт '
                                 'носителя вместе с чарами. Те же узы на вашем исчадии недоступны вражеской жертве.',
                                 'Наложите Кровные Узы на своё отдыхающее Бронзовое исчадие. Сохраните этот якорь и '
                                 'все три хода атакуйте Прыгуном. Враг может рассеять своё бронзовое существо, но оба '
                                 'стальных останутся связанными.'],
                    'explanation_ru': 'Кровные Узы проверяют расу носителя по обе стороны поля, поэтому выбор вашего '
                                      'Бронзового исчадия удерживает вражеских Стальных, несмотря на их защиту от '
                                      'прямого выбора целью. Ваш якорь продолжает отдыхать, но Прыгун другой расы и '
                                      'поднимается как обычно. Три атаки по два снимают шесть здоровья. Рассеяние '
                                      'убирает вражеское бронзовое существо, но не может пожертвовать вашим и снять с '
                                      'него Кровные Узы. Если узы находятся на вражеском Бронзовом исчадии, противник '
                                      'может пожертвовать его перед восстановлением и освободить обоих Стальных. Узы '
                                      'на Прыгуне выбирают не ту расу и совсем не сдерживают исчадий.',
                    'hero_names': ['Synthet Bond Warden', 'Synthet Dissolution Broker'],
                    'hero_names_ru': ['Хранитель уз синтетов', 'Распорядитель рассеяния синтетов']}}


def puzzles():
    g='el1';out=[]
    def add(slug,title,level,turns,pos,line,obj=None,refs=None,alts=None):
     text = dict(_PRESENTATION[slug])
     e = puzzle(g, 'crossroads_' + slug, title, text.pop('category'), level, turns, pos,
                text.pop('briefing'), text.pop('hints'), text.pop('explanation'), line, obj,
                refutations=refs or [], **text)
     if alts:e['alternative_solutions']=alts
     out.append(e)
    add('life_installments','Life in Installments',3,3,
     state(g,hero('Black',['AILK','SHSK','STRG'],mana=5,channels=1,health=3,level=14,enchantments=[enchant('ENRG',id=1)]),
     hero('Red',[],mana=0,channels=1,health=11,level=16,enchantments=[enchant('FRBL',id=2)]),[
     unit('GBGN',2),unit('RKWL',3),unit('FREL',4,1),unit('GRTN',5,1)]),
     [cast('AILK',2),cast('SHSK',2),attack(2),end(),end(side=1),ability(1,'fireball:2',0,side=1),attack(4,side=1),attack(5,side=1),end(side=1),block(3,4),end(),
     ability(0,'energize:1',2),attack(2),end(),end(side=1),ability(1,'fireball:2',0,side=1),attack(4,side=1),attack(5,side=1),end(side=1),block(3,4),end(),ability(0,'energize:1',2),attack(2),end(),end(side=1)],
     {'type':'win','protect':[2,3]},[
     {'label':'Buy Strength before completing both protections','commands':[cast('STRG',2)]},
     {'label':'Put the armor on the Wall','commands':[cast('AILK',2),cast('SHSK',3)]}])
    add('last_receipt','The Last Receipt',2,1,
     state(g,hero('Red',['PLMR','FOGG'],mana=3,channels=1,health=4,level=12,turns=14,skills={'CNLG':2},enchantments=[enchant('RPST',id=1)]),
     hero('Red',[],health=5,level=3,turns=14),[
     unit('RKWL',2),unit('STRT',3),unit('STMC',4,1),unit('FREL',5,1),unit('BATT',6,1)],phase=1,attacker=1,attacks=[4,5,6]),
     [block(2,4),block(3,5),end(),ability(0,'repair:1',0,choice=0),end()],
     {'type':'win','protect':[2]},[
     {'label':'Cancel combat and postpone making the corpse','commands':[cast('FOGG'),end(),cast('PLMR',3),end(),attack(4,side=1),attack(5,side=1),attack(6,side=1),end(side=1),block(2,4),end()]}],
     [{'label':'Polymorph the Rat and prevent combat with Fog','label_ru':'Превратить Крысу и предотвратить бой Туманом','commands':[cast('PLMR',3),cast('FOGG'),end(),ability(0,'repair:1',0,choice=0),end()]}])
    add('free_midwife','First Free the Midwife',2,2,
     state(g,hero('Green',['ETTD','WHAS'],mana=12,health=1,level=10,enchantments=[enchant('BLKD',id=1)]),
     hero('Blue',[],health=8,level=12),[
     unit('MOTI',2),unit('MOTI',3,enchantments=[enchant('IRRT',id=2)]),unit('TIWR',4),unit('TIWK',5)]),
     [ability(2,'brood'),cast('ETTD',6,grave=2),ability(3,'brood'),cast('WHAS',7,grave=1),attack(4),attack(5),end(),end(side=1),end(side=1),attack(4),attack(5),end(),end(side=1)],
     {'type':'win','protect':[2,3,4,5]},[
     {'label':'Use the first newborn to remove Defense','commands':[ability(2,'brood'),cast('ETTD',6,grave=1)]}])
    add('above_flood','Above the Flood',3,2,
     state(g,hero('Green',['ICST','FLOD','GLDT','CNAR'],mana=7,health=1,level=11,enchantments=[enchant('ENRG',id=1),enchant('FURY',id=2)]),
     hero('Black',[],health=6,level=18),[
     unit('BATT',2,resting=True),unit('WLWD',3),unit('FREL',4,1),unit('GBAT',5,1),unit('KBSH',6,1)]),
     [cast('ICST'),cast('FLOD'),ability(0,'energize:1',2),attack(2),end(),end(side=1),end(side=1),block(3,5),end(),attack(2),end(),end(side=1)],
     {'type':'win','protect':[2,3]},[
     {'label':'Save ether by using Glitterdust instead of Ice Storm','commands':[cast('GLDT')]},
     {'label':'Hold flyers with Condensed Air','commands':[cast('CNAR')]}])
    add('quiet_cleric','The Quiet Cleric',2,1,
     state(g,hero('Blue',[],mana=7,health=1,level=8,grave=['CLSP','WZSP','SHSP'],enchantments=[enchant('SCBR',id=1)]),
     hero('Red',[],health=30,level=15),[
     unit('WZSP',2),unit('WRSP',3,enchantments=[enchant('SHSK',id=2)]),unit('WLWD',4),unit('OGKN',5,1),unit('BATT',6,1)],phase=1,attacker=1,attacks=[5,6]),
     [ability(0,'second_birth:1',0,choice=0),ability(4,'lava_power',amount=2),block(3,5),block(4,6),end()],
     {'type':'clear','protect':[2,3,4]},[
     {'label':'Raise the second Wizard, spend the last ether on the Wall, and hold out','commands':[ability(0,'second_birth:1',0,choice=1),ability(4,'lava_power',amount=1),block(3,5),block(4,6),end(),end(),end(side=1),attack(6,side=1),end(side=1),block(4,6),end()]},
     {'label':'Raise the Shaman, buy two Wall power, and use the same blocks','commands':[ability(0,'second_birth:1',0,choice=2),ability(4,'lava_power',amount=2),block(3,5),block(4,6),end()]}])
    add('anchor_you_own','The Anchor You Own',3,3,
     state(g,hero('Black',['ERBN','FOGG'],mana=4,health=1,level=13),
     hero('Black',[],mana=1,channels=1,health=6,level=17,enchantments=[enchant('SACR',id=1)]),[
     unit('BRAB',2,resting=True),unit('HOPR',3),unit('STAB',4,1,resting=True),unit('STAB',5,1,resting=True),unit('BRAB',6,1,resting=True)]),
     [cast('ERBN',2),attack(3),end(),end(side=1),ability(1,'sacrifice:1',6,side=1),end(side=1),attack(3),end(),end(side=1),end(side=1),attack(3),end(),end(side=1)],
     {'type':'win','protect':[2,3]},[
     {'label':'Put the race lock on the enemy Bronze Abomination','commands':[cast('ERBN',6),attack(3),end(),end(side=1),ability(1,'sacrifice:1',6,side=1)]},
     {'label':'Bind the Hopper instead of an Abomination','commands':[cast('ERBN',3)]}])
    return out
