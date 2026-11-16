"""Paradoxes: seven further deterministic Etherlords I tactical studies.

The first Curiosities expansion and the earlier catalog remain untouched.
Presentation is separated from the small executable positions below so the
English and Russian explanations can be reviewed together. Only ordinary
battle commands and existing objectives are used.
"""
from puzzle_authoring import hero, unit, state, enchant, puzzle, cast, ability, attack, block, end

_PRESENTATION = {'borrowed_scissors': {'category': 'Borrow the enemy’s disenchanting strike',
                       'title_ru': 'Чужие ножницы',
                       'category_ru': 'Используйте рассеивающий удар врага',
                       'briefing': 'Survive the committed attack and preserve both allies. Your hero has one health. '
                                   'Both the Hopper and Rock Wall carry Redirect. The Stink Rat carries Spell Breaker '
                                   'and attacks before the Giant Bat.',
                       'hints': ['The larger defender is not the safest first blocker. Think about which ally should '
                                 'still carry Redirect when the Bat strikes.',
                                 'In this edition, Spell Breaker removes a creature’s enchantments before its strike '
                                 'damages that creature. A blocked Rat can remove the dangerous obligation from your '
                                 'smaller shield.',
                                 'Block the Stink Rat with the Hopper. Leave the Giant Bat unblocked: after the Rat '
                                 'strips the Hopper’s Redirect, only the Rock Wall will receive the redirected five '
                                 'damage.'],
                       'explanation': 'The Rat’s Spell Breaker removes Redirect from the Hopper before dealing one '
                                      'damage. The Hopper survives and kills the Rat with its two-power return strike. '
                                      'The Bat then hits your hero for five, but the remaining Redirect sends that '
                                      'damage to the ten-toughness Rock Wall and spares the hero completely. Both '
                                      'allies survive. Blocking the Rat with the Wall removes the wrong Redirect: the '
                                      'fragile Hopper then receives the Bat’s full five damage and dies. Redirect does '
                                      'not divide the damage between its holders.',
                       'briefing_ru': 'Переживите уже объявленную атаку, сохранив обоих союзников. У героя одно '
                                      'здоровье. И на Прыгуне, и на Каменной стене есть Переадресация. Вонючая крыса '
                                      'несёт Разрушитель Чар и атакует раньше Гигантской летучей мыши.',
                       'hints_ru': ['Самый крупный защитник — не лучший первый блокирующий. Подумайте, на ком должна '
                                    'остаться Переадресация к удару Мыши.',
                                    'В этой игре Разрушитель Чар снимает чары с существа до нанесения урона. '
                                    'Заблокированная Крыса может освободить меньший щит от опасной обязанности.',
                                    'Блокируйте Вонючую крысу Прыгуном. Гигантскую летучую мышь пропустите: после '
                                    'снятия Переадресации с Прыгуна все пять перенаправленного урона получит только '
                                    'Каменная стена.'],
                       'explanation_ru': 'Разрушитель Чар Крысы снимает Переадресацию с Прыгуна до нанесения одного '
                                         'урона. Прыгун выживает и убивает Крысу ответным ударом силой два. Мышь затем '
                                         'наносит герою пять, но оставшаяся Переадресация переносит урон на Каменную '
                                         'стену с десятью стойкости, полностью сохраняя здоровье героя. Оба союзника '
                                         'живы. Если блокировать Крысу Стеной, снимется не та Переадресация: хрупкий '
                                         'Прыгун получит все пять урона Мыши и погибнет. Переадресация не делит урон '
                                         'между своими носителями.',
                       'hero_names': ['Synthet Insurer', 'Vital Disenchanter'],
                       'hero_names_ru': ['Страховщик синтетов', 'Рассеиватель виталов']},
 'keep_the_change': {'category': 'Close every route for spending the burn away',
                     'title_ru': 'Оставьте сдачу',
                     'category_ru': 'Не дайте потратить обжигающий запас',
                     'briefing': 'Win before your second turn. You have three ether and one health; the enemy has four '
                                 'health and will refill four ether. The enemy has no cards or activated abilities, '
                                 'only three Tick Warriors. Ether Burn hurts each acting hero for their unspent ether '
                                 'at turn end. Timidity charges one ether for each attack declaration. Your Wall of '
                                 'Distortion can close combat.',
                     'hints': ['Your own pool must be empty, while the enemy’s pool must stay full. Preventing combat '
                               'damage is only half the problem.',
                               'Under Timidity, an enemy can spend ether merely by declaring attacks. Cancelling those '
                               'attacks later does not refund that ether.',
                               'Spend all three ether on Ether Burn and Timidity, then activate the Wall of Distortion '
                               'before passing. The enemy cannot declare attacks and therefore cannot spend any of the '
                               'four ether that will burn them.'],
                     'explanation': 'Ether Burn costs two and Timidity costs one, leaving you with nothing to burn at '
                                    'your own turn end. Activating distortion now prevents every enemy attack '
                                    'declaration. Their four channels refill four ether; with no cards, abilities or '
                                    'legal attacks, all four remain when Ether Burn resolves and defeat the '
                                    'four-health hero. Waiting until defence allows the enemy to pay attack taxes '
                                    'first. Even one declaration spends a coin, so cancelling that attack leaves only '
                                    'three burn damage and misses the deadline.',
                     'briefing_ru': 'Победите до своего второго хода. У вас три эфира и одно здоровье; у врага четыре '
                                    'здоровья, и он пополнит четыре эфира. У врага нет карт и активных способностей, '
                                    'только три Клеща-воина. Обжигающий Эфир в конце хода наносит действующему герою '
                                    'урон за весь неизрасходованный эфир. Нерешительность берёт один эфир за каждое '
                                    'объявление атаки. Стена искажения может прекратить бой.',
                     'hints_ru': ['Ваш запас должен стать пустым, а вражеский — остаться полным. Одного предотвращения '
                                  'боевого урона недостаточно.',
                                  'При Нерешительности враг тратит эфир уже при объявлении атаки. Последующая отмена '
                                  'атаки этот эфир не возвращает.',
                                  'Потратьте все три эфира на Обжигающий Эфир и Нерешительность, затем активируйте '
                                  'Стену искажения до передачи хода. Враг не сможет объявить атаки и потратить хотя бы '
                                  'часть четырёх эфира, которые его сожгут.'],
                     'explanation_ru': 'Обжигающий Эфир стоит два, Нерешительность — один: к концу вашего хода '
                                       'обжигать нечего. Немедленное искажение запрещает врагу объявлять атаки. Четыре '
                                       'канала пополняют четыре эфира; без карт, способностей и доступных атак весь '
                                       'запас остаётся к срабатыванию Обжигающего Эфира и убивает героя с четырьмя '
                                       'здоровья. Если ждать фазы защиты, враг сначала оплатит объявления атак. Даже '
                                       'одно объявление расходует монету: отменённая позднее атака оставляет лишь три '
                                       'урона от эфира, и срок будет упущен.',
                     'hero_names': ['Chaot Tollkeeper', 'Vital Hoarder'],
                     'hero_names_ru': ['Сборщик пошлин хаотов', 'Накопитель виталов']},
 'no_free_funerals': {'category': 'Count actual deaths and reserve regeneration',
                      'title_ru': 'Похороны не бесплатны',
                      'category_ru': 'Считайте погибших и берегите эфир регенерации',
                      'briefing': 'Clear the enemy army this turn and preserve both of your Treants. You have seven '
                                  'ether, four health and one Spiritual Web already active. The enemy has exactly one '
                                  'ether, enough for the Great Treant’s regeneration. Fury of Nature charges its '
                                  'caster health for every creature it tries to destroy, including regenerated '
                                  'survivors.',
                      'hints': ['The River Halo can both deny an enemy recovery and finance a friendly one. Do that '
                                'before sweeping the battlefield.',
                                'Fury of Nature costs six. Your two Treants need one ether each to regenerate. The '
                                'existing Web heals you for actual deaths; another Web would spend a coin needed to '
                                'keep a Treant alive.',
                                'Siphon the enemy’s last ether with the River Halo, raising your pool to eight. Cast '
                                'Fury of Nature immediately. Keep the last two ether for the two automatic '
                                'regenerations.'],
                      'explanation': 'Siphon moves the enemy’s one ether to you: eight is exactly six for Fury of '
                                     'Nature and two for the friendly Treants’ regeneration. The enemy Treant now has '
                                     'no ether to regenerate. Fury attempts five destructions; your two protected '
                                     'Treants survive, while the Halo and both enemies die. The existing Spiritual Web '
                                     'heals three, then Fury deals five to the caster: four health becomes two. Buying '
                                     'a second Web increases healing but leaves only one ether after the spell, so one '
                                     'protected Treant dies and the objective fails.',
                      'briefing_ru': 'Очистите вражескую армию за этот ход и сохраните обоих своих древней. У вас семь '
                                     'эфира, четыре здоровья и уже действует одна Паутина Душ. У врага ровно один эфир '
                                     '— достаточно для регенерации Старого древня. Ярость Природы наносит заклинателю '
                                     'урон за каждую попытку уничтожить существо, включая спасённых регенерацией.',
                      'hints_ru': ['Речной нимб одновременно лишает врага восстановления и оплачивает ваше. Сделайте '
                                   'это до уничтожения армий.',
                                   'Ярость Природы стоит шесть. Каждому из ваших древней нужен ещё один эфир для '
                                   'регенерации. Действующая Паутина лечит за реальные смерти; новая потратит монету, '
                                   'нужную живому древню.',
                                   'Речным нимбом заберите последний эфир врага, подняв свой запас до восьми. Сразу '
                                   'примените Ярость Природы. Последние два эфира оставьте для двух автоматических '
                                   'регенераций.'],
                      'explanation_ru': 'Нимб переносит к вам единственный эфир врага: восемь — ровно шесть на Ярость '
                                        'Природы и два на регенерации союзных древней. У вражеского древня эфира для '
                                        'регенерации больше нет. Ярость делает пять попыток уничтожения; два '
                                        'защищаемых древня выживают, а Нимб и оба врага погибают. Действующая Паутина '
                                        'Душ лечит на три, затем Ярость наносит заклинателю пять: четыре здоровья '
                                        'превращаются в два. Вторая Паутина даёт больше лечения, но оставляет после '
                                        'заклинания лишь один эфир. Один из защищаемых древней погибает, и задача '
                                        'провалена.',
                      'hero_names': ['Vital Undertaker', 'Kinet Estate Keeper'],
                      'hero_names_ru': ['Могильщик виталов', 'Хранитель владений кинетов']},
 'night_shift': {'category': 'Three turns of borrowed vigilance through Smoke',
                 'title_ru': 'Ночная смена',
                 'category_ru': 'Три хода без отдыха сквозь Дым',
                 'briefing': 'Win in three turns, preserving your Orc Guard, Orc Shaman and Rock Wall. Smoke is '
                             'already active: resting creatures will not rise naturally. The enemy Orc Elder gives '
                             'every Orc on either side Restless. It currently has one wound. You have two Cloaks of '
                             'Fear, one Call Lightning, five ether and no channels. The enemy has no hand cards.',
                 'hints': ['Choose attackers for all three turns, not only for the first attack. One enemy is '
                           'supplying the exception to Smoke that your army needs.',
                           'The Elder makes both of your Orcs Restless. The Hopper is not an Orc and would stay '
                           'resting after one attack. The Guard also needs another Orc to declare first.',
                           'Give the two Cloaks to the Guard and Shaman. Each turn declare the Shaman first, then the '
                           'Guard; their three unblockable damage adds up to nine. Keep the Rock Wall ready to block '
                           'the Elder. Do not kill the Elder.'],
                 'explanation': 'The enemy Elder’s aura lets both friendly Orcs attack without resting, so Smoke '
                                'cannot lock them out of later turns. Cloaks protect both lanes from the Elder’s '
                                'blocks; declaring the one-power Shaman first enables the two-power Guard’s team '
                                'attack. Three damage on each of three turns defeats the nine-health hero. The Rock '
                                'Wall safely absorbs any six-power counterattack. A cloaked Hopper contributes only '
                                'once, and an uncloaked Shaman can be killed by a block. Call Lightning can kill the '
                                'wounded Elder immediately, but that removes Restless and leaves your attackers '
                                'permanently resting after their first attack. Using the Shaman’s ether ability would '
                                'also rest it: Restless prevents resting from attacks, not from that ability.',
                 'briefing_ru': 'Победите за три хода, сохранив Орка-стражника, Орка-шамана и Каменную стену. Уже '
                                'действует Дым: отдыхающие существа сами не поднимаются. Вражеский Старейшина орков '
                                'даёт всем оркам с обеих сторон возможность не отдыхать после атаки. Сейчас у него '
                                'одна рана. У вас две Маски Ужаса, одна Молния, пять эфира и нет каналов. Рука врага '
                                'пуста.',
                 'hints_ru': ['Выбирайте атакующих на все три хода, а не только на первую атаку. Один враг даёт вашей '
                              'армии нужное исключение из действия Дыма.',
                              'Благодаря Старейшине оба ваших орка не отдыхают после атаки. Прыгун не орк и после '
                              'первого удара останется отдыхать. Стражнику также нужен другой орк, объявленный '
                              'атакующим раньше него.',
                              'Дайте Маски Стражнику и Шаману. Каждый ход сначала объявляйте атаку Шамана, затем '
                              'Стражника: три неблокируемых урона за ход дадут девять. Каменной стеной блокируйте '
                              'Старейшину. Не убивайте его.'],
                 'explanation_ru': 'Аура вражеского Старейшины позволяет обоим союзным оркам атаковать без отдыха, '
                                   'поэтому Дым не лишает их следующих ходов. Маски защищают обе атаки от блока '
                                   'Старейшины; объявленный первым Шаман с силой один разрешает парную атаку Стражника '
                                   'с силой два. Три урона на каждом из трёх ходов побеждают героя с девятью здоровья. '
                                   'Каменная стена выдерживает ответные атаки силой шесть. Прыгун с Маской ударит лишь '
                                   'однажды, а Шамана без Маски враг может убить блоком. Молния сразу убивает раненого '
                                   'Старейшину, но вместе с ним исчезает отсутствие отдыха: после первой атаки ваши '
                                   'орки навсегда лягут под Дымом. Способность Шамана получать эфир тоже усыпит его: '
                                   'аура предотвращает отдых после атаки, а не после этой способности.',
                 'hero_names': ['Chaot Night Captain', 'Keeper of the Shared Watch'],
                 'hero_names_ru': ['Ночной капитан хаотов', 'Хранитель общего дозора']},
 'riot_on_repeat': {'category': 'One returning curse, two ways to finish',
                    'title_ru': 'Бескровие на бис',
                    'category_ru': 'Возвращающиеся чары и два способа добить',
                    'briefing': 'Clear both wounded enemies this turn and preserve the Kobold Shaman. Each enemy has '
                                'one toughness remaining, but both can regenerate for one ether and the enemy has two '
                                'ether. You have five ether, one Riot, Call Lightning and an unused Energize ability. '
                                'Riot returns to its caster’s hand when its creature leaves play.',
                    'hints': ['You do not need two copies of the anti-regeneration enchantment. You need the first '
                              'enchanted creature to die before choosing the second.',
                              'Riot prevents regeneration and returns after the first death. Its two casts cost four '
                              'ether. The final ether can pay either to ready the Shaman or to cast Call Lightning.',
                              'Enchant one enemy with Riot, then kill it with the Shaman’s shot. Reuse the returned '
                              'Riot on the other enemy. Finish with either Energize plus a second shot, or Call '
                              'Lightning.'],
                    'explanation': 'Each enemy’s last point is protected by regeneration until Riot forbids it. The '
                                   'first shot kills the cursed creature and returns Riot to your hand, so you can '
                                   'curse the other enemy. Four ether pays for the two casts. One valid plan spends '
                                   'the fifth ether on Energize and uses the Shaman twice; a different plan uses the '
                                   'Shaman once and pays the final ether for Call Lightning. Either route clears both '
                                   'enemies. Damage before Riot merely triggers regeneration, erases the old wounds '
                                   'and consumes a limited damage tool before it can finish its job.',
                    'briefing_ru': 'Уничтожьте обоих раненых врагов за этот ход и сохраните Кобольда-шамана. У каждого '
                                   'врага осталась одна стойкость, но оба регенерируют за один эфир, а у противника '
                                   'есть два эфира. У вас пять эфира, одно Бескровие, Молния и неиспользованная '
                                   'Подзарядка. Когда носитель Бескровия покидает поле, карта возвращается в руку '
                                   'заклинателя.',
                    'hints_ru': ['Вам не нужны две копии чар против регенерации. Нужно, чтобы первый зачарованный враг '
                                 'погиб раньше, чем вы займётесь вторым.',
                                 'Бескровие запрещает регенерацию и возвращается после первой смерти. Два применения '
                                 'стоят четыре эфира. Последний эфир можно потратить на пробуждение Шамана или на '
                                 'Молнию.',
                                 'Наложите Бескровие на одного врага и убейте его выстрелом Шамана. Вернувшимся '
                                 'Бескровием зачаруйте второго. Добейте его либо Подзарядкой и вторым выстрелом, либо '
                                 'Молнией.'],
                    'explanation_ru': 'Последнюю стойкость каждого врага защищает регенерация, пока её не запретит '
                                      'Бескровие. Первый выстрел убивает зачарованное существо и возвращает Бескровие '
                                      'в руку: теперь можно зачаровать второго врага. Четыре эфира оплачивают два '
                                      'применения. Один верный план тратит пятый эфир на Подзарядку и стреляет Шаманом '
                                      'дважды; другой использует Шамана один раз и оплачивает последним эфиром Молнию. '
                                      'Оба плана очищают поле. Урон до Бескровия лишь запускает регенерацию, стирает '
                                      'старые раны и тратит ограниченный источник урона до того, как он сможет добить '
                                      'цель.',
                    'hero_names': ['Chaot Encore Conductor', 'Vital Recovery Broker'],
                    'hero_names_ru': ['Дирижёр хаотов', 'Распорядитель восстановления виталов']},
 'living_budget': {'category': 'A sacrifice changes both income and upkeep',
                   'title_ru': 'Живой бюджет',
                   'category_ru': 'Жертва меняет доход и содержание',
                   'briefing': 'Survive this committed attack, then capture this exact Bat during your next attack '
                               'phase. Keep the Wall of Force, Orc Guard and Hopper alive. You have one ether, six '
                               'channels and two unused Ether Feeding abilities. Thirsty Creatures is active: after '
                               'your refill, every creature you still own costs one ether. The enemy has no hand '
                               'cards. A newborn recruit is not needed for this defence.',
                   'hints': ['You need five ether for Change of Command. Forecast the next refill after paying for '
                             'your surviving army, not just the channel total.',
                             'Each Ether Feeding adds one channel and removes one future upkeep payment. Only the Rat '
                             'and Shaman may be sacrificed. First collect the Shaman’s ether so you can afford both '
                             'sacrifices.',
                             'Use the Orc Shaman’s ether ability, then feed the Rat and Shaman through the two Ether '
                             'Feeding abilities. Block the Bat with the Wall and the Treant with the Guard. Eight '
                             'channels minus three survivors leaves five ether next turn: capture the Bat.'],
                   'explanation': 'The Shaman raises your current pool from one to two. Two Ether Feeding activations '
                                  'spend it, sacrifice the two unprotected creatures and raise channels from six to '
                                  'eight. The Wall blocks the Bat without killing the future recruit; the Guard '
                                  'survives the Treant’s three damage. At your next turn, eight ether refills and '
                                  'Thirsty Creatures takes three for the remaining Wall, Guard and Hopper. The exact '
                                  'five left pays Change of Command. With only one sacrifice, seven channels minus '
                                  'four creatures leaves three. Sacrificing the Shaman before using its ability leaves '
                                  'no second payment; postponing the other sacrifice cannot retroactively increase the '
                                  'refill you already received.',
                   'briefing_ru': 'Переживите уже объявленную атаку, затем в своей следующей фазе атаки захватите '
                                  'именно эту Летучую мышь. Сохраните Стену силы, Орка-стражника и Прыгуна. У вас один '
                                  'эфир, шесть каналов и две неиспользованные Эфирные Подпитки. Действует Эфирная '
                                  'Жажда: после пополнения каждое ваше существо заберёт один эфир. Рука врага пуста. '
                                  'Новое существо для этой защиты не требуется.',
                   'hints_ru': ['На Переподчинение нужно пять эфира. Считайте следующий запас после содержания '
                                'выжившей армии, а не просто число каналов.',
                                'Каждая Эфирная Подпитка добавляет канал и убирает одну будущую плату за содержание. '
                                'Жертвовать можно только Крысой и Шаманом. Сначала получите эфир от Шамана, чтобы '
                                'оплатить обе жертвы.',
                                'Получите эфир Орком-шаманом, затем двумя Эфирными Подпитками пожертвуйте Крысу и '
                                'Шамана. Стеной блокируйте Мышь, Стражником — древня. Восемь каналов минус три '
                                'выживших оставят пять эфира: подчините Мышь.'],
                   'explanation_ru': 'Шаман увеличивает текущий запас с одного до двух. Две Эфирные Подпитки расходуют '
                                     'его, приносят в жертву двух незащищаемых существ и повышают число каналов с '
                                     'шести до восьми. Стена блокирует Мышь, не убивая будущего новобранца; Стражник '
                                     'выдерживает три урона древня. В начале вашего хода восемь эфира пополняются, а '
                                     'Эфирная Жажда забирает три за оставшихся Стену, Стражника и Прыгуна. Ровно пять '
                                     'остатка оплачивают Переподчинение. Одна жертва даёт семь каналов минус четыре '
                                     'существа, то есть лишь три эфира. Если пожертвовать Шамана до его способности, '
                                     'не хватит второй оплаты. Поздняя жертва не увеличит уже полученное пополнение '
                                     'задним числом.',
                   'hero_names': ['Vital Census Keeper', 'Chaot Bailiff'],
                   'hero_names_ru': ['Переписчик виталов', 'Пристав хаотов']},
 'fatal_upgrade': {'category': 'An enemy bonus starts a lethal decay clock',
                   'title_ru': 'Смертельное улучшение',
                   'category_ru': 'Усиление врага запускает гибельный распад',
                   'briefing': 'Clear the enemy army within three of your turns and preserve the Rock Wall. The enemy '
                               'Great Treant has eight ether and eight channels, so ordinary destruction can be '
                               'regenerated repeatedly. You have five ether, no channels and an unused Energize. Your '
                               'Wall is resting. Overload adds five power and toughness, then permanently removes two '
                               'of each at every turn end belonging to its creature’s controller.',
                   'hints': ['Stopping regeneration is not enough: your Wall has no power to kill the Treant. Look for '
                             'a death caused by the creature’s own shrinking statistics.',
                             'Overload and Weaken together make the Treant 4/4. Its two end-of-turn reductions will '
                             'make it 2/2 and then 0/0. You still need a safe blocker while the clock runs.',
                             'Cast Overload and Weaken on the enemy Treant before the first enemy turn. Save the last '
                             'ether for Energize on the Wall. Block any Treant attack; its second end-of-turn decay '
                             'kills it without regeneration.'],
                   'explanation': 'Overload adds five and Weaken subtracts four from the Treant’s printed 3/3, making '
                                  '4/4. Four ether pays for that pair, leaving the one ether needed to ready your '
                                  'Wall. The first enemy turn end applies two points of permanent decay, leaving 2/2; '
                                  'the next applies two more, leaving zero toughness. Overload’s decay kills without '
                                  'regeneration, regardless of the enemy’s stocked ether. A ten-toughness Wall safely '
                                  'holds either attack, and passing does not spare the Treant from decay. Casting Riot '
                                  'instead removes regeneration without supplying lethal damage. Merely weakening and '
                                  'waiting loses the opening mana: with no channels, your next refill is zero.',
                   'briefing_ru': 'Очистите вражескую армию за три своих хода и сохраните Каменную стену. У вражеского '
                                  'Старого древня восемь эфира и восемь каналов: обычное уничтожение можно многократно '
                                  'переживать регенерацией. У вас пять эфира, нет каналов и доступна Подзарядка. Стена '
                                  'отдыхает. Перегрузка добавляет пять силы и стойкости, затем навсегда отнимает по '
                                  'два в конце каждого хода хозяина существа.',
                   'hints_ru': ['Одного запрета регенерации недостаточно: у Стены нет силы для убийства древня. Ищите '
                                'гибель от уменьшения собственных показателей существа.',
                                'Перегрузка вместе со Слабостью делает древня 4/4. Два уменьшения в конце хода '
                                'превратят его в 2/2, затем в 0/0. Пока идёт отсчёт, всё ещё нужен безопасный '
                                'защитник.',
                                'До первого хода врага примените к древню Перегрузку и Слабость. Последний эфир '
                                'оставьте на Подзарядку Стены. Блокируйте атаки древня; второй распад в конце его хода '
                                'убьёт его без регенерации.'],
                   'explanation_ru': 'Перегрузка добавляет пять, а Слабость отнимает четыре от печатных 3/3 древня: '
                                     'получается 4/4. Эта пара стоит четыре эфира, оставляя один для пробуждения '
                                     'Стены. В конце первого вражеского хода постоянный распад отнимает два, оставляя '
                                     '2/2; в конце следующего — ещё два, снижая стойкость до нуля. Распад Перегрузки '
                                     'убивает без регенерации независимо от запаса эфира врага. Стена с десятью '
                                     'стойкости выдерживает любую атаку, а пропуск атаки не спасает древня от распада. '
                                     'Бескровие вместо Перегрузки запрещает регенерацию, но не создаёт смертельного '
                                     'урона. Если лишь ослабить и ждать, начальный эфир пропадёт: без каналов '
                                     'следующее пополнение равно нулю.',
                   'hero_names': ['Kinet Decay Engineer', 'Vital Evergreen Warden'],
                   'hero_names_ru': ['Мастер распада кинетов', 'Хранитель вечной зелени виталов']}}


def puzzles():
    g='el1';out=[]
    def add(slug,title,level,turns,pos,line,obj=None,refs=None):
     text = dict(_PRESENTATION[slug])
     out.append(puzzle(g, 'paradox_' + slug, title, text.pop('category'), level, turns, pos,
                       text.pop('briefing'), text.pop('hints'), text.pop('explanation'), line, obj,
                       refutations=refs or [], **text))
    add('borrowed_scissors','Borrowed Scissors',2,1,
     state(g,hero('Black',[],health=1,level=8),hero('Green',[],health=30,level=11),[
     unit('HOPR',2,enchantments=[enchant('REDR',id=1)]),unit('RKWL',3,enchantments=[enchant('REDR',id=2)]),
     unit('STRT',4,1,enchantments=[enchant('SGHT',id=3)]),unit('GBAT',5,1)],phase=1,attacker=1,attacks=[4,5]),
     [block(2,4),end()],{'type':'survive','enemy_turns':1,'protect':[2,3]},
     [{'label':'Let the Rock Wall absorb the Rat','commands':[block(3,4),end()]}])
    add('keep_the_change','Keep the Change',2,1,
     state(g,hero('Red',['MNBN','LSDS'],mana=3,health=1,level=7),hero('Green',[],mana=0,channels=4,health=4,level=12),[
     unit('WLDT',2),unit('TIWR',3,1),unit('TIWR',4,1),unit('TIWR',5,1)]),
     [cast('MNBN'),cast('LSDS'),ability(2,'distortion'),end(),end(side=1)],None,
     [{'label':'Save distortion until after the enemy declares an attack','commands':[cast('MNBN'),cast('LSDS'),end(),attack(3,side=1),end(side=1),ability(2,'distortion'),end()]}])
    add('no_free_funerals','No Free Funerals',2,1,
     state(g,hero('Green',['FRNT','SPWB','SLRP'],mana=7,health=4,level=14,enchantments=[enchant('SPWB',id=1)]),
     hero('Blue',[],mana=1,health=30,level=15),[
     unit('TNSA',2),unit('GRTN',3),unit('RVHL',4),unit('GRTN',5,1),unit('BATT',6,1)]),
     [ability(4,'siphon'),cast('FRNT')],{'type':'clear','protect':[2,3]},
     [{'label':'Buy a second Spiritual Web before the mass destruction','commands':[ability(4,'siphon'),cast('SPWB'),cast('FRNT')]}])
    add('night_shift','Night Shift',3,3,
     state(g,hero('Red',['CLFR','CLFR','CLIG'],mana=5,health=1,channels=0,level=15,enchantments=[enchant('SMOK',id=1)]),
     hero('Red',[],health=9,level=17),[
     unit('ORGD',2),unit('ORSH',3),unit('HOPR',4),unit('RKWL',5),unit('OREL',6,1,damage=1)]),
     [cast('CLFR',2),cast('CLFR',3),attack(3),attack(2),end(),end(side=1),attack(6,side=1),end(side=1),block(5,6),end(),
     attack(3),attack(2),end(),end(side=1),attack(6,side=1),end(side=1),block(5,6),end(),attack(3),attack(2),end(),end(side=1)],
     {'type':'win','protect':[2,3,5]},[
     {'label':'Kill the wounded enemy Elder before attacking','commands':[cast('CLIG',6)]},
     {'label':'Cloak the Hopper and send the exposed Shaman as the Guard’s partner','commands':[cast('CLFR',2),cast('CLFR',4),attack(3),attack(2),attack(4),end(),block(6,3,side=1),end(side=1)]}])
    add('riot_on_repeat','Riot on Repeat',2,1,
     state(g,hero('Red',['RIOT','CLIG'],mana=5,health=4,level=10,enchantments=[enchant('ENRG',id=1)]),
     hero('Green',[],mana=2,health=30,level=13),[
     unit('KBSH',2),unit('GRTN',3,1,damage=2),unit('WLBL',4,1,damage=8)]),
     [cast('RIOT',3),ability(2,'sting',3),ability(0,'energize:1',2),cast('RIOT',4),ability(2,'sting',4)],
     {'type':'clear','protect':[2]},[
     {'label':'Shoot the Treant before denying regeneration','commands':[ability(2,'sting',3)]},
     {'label':'Cast Call Lightning before using the returning curse','commands':[cast('CLIG',3)]}])
    add('living_budget','The Living Budget',3,1,
     state(g,hero('Green',['CHCM','FOGG'],mana=1,channels=6,health=1,level=16,
     enchantments=[enchant('SPLK',id=1),enchant('SPLK',id=2),enchant('SPTR',id=3)]),
     hero('Red',[],health=30,level=18),[
     unit('WLFC',2),unit('ORGD',3),unit('HOPR',4),unit('STRT',5),unit('ORSH',6),unit('GRTN',7,1),unit('BATT',8,1)],phase=1,attacker=1,attacks=[7,8]),
     [ability(6,'ether'),ability(0,'spirit_lock:1',5),ability(0,'spirit_lock:2',6),block(2,8),block(3,7),end(),cast('CHCM',8)],
     {'type':'control','targets':[8],'enemy_turns':1,'protect':[2,3,4]},[
     {'label':'Feed the Shaman first and postpone the Rat until after refill','commands':[ability(0,'spirit_lock:1',6),block(2,8),block(3,7),end(),ability(0,'spirit_lock:2',5),end(),end(side=1)]},
     {'label':'Keep the second sacrifice and spend the resulting three ether on Fog','commands':[ability(6,'ether'),ability(0,'spirit_lock:1',5),block(2,8),block(3,7),end(),cast('FOGG'),end(),end(side=1)]}])
    add('fatal_upgrade','A Fatal Upgrade',2,3,
     state(g,hero('Blue',['OVRL','WEAK','RIOT'],mana=5,channels=0,health=1,level=13,enchantments=[enchant('ENRG',id=1)]),
     hero('Green',[],mana=8,channels=8,health=30,level=20),[
     unit('RKWL',2,resting=True),unit('GRTN',3,1)]),
     [cast('OVRL',3),cast('WEAK',3),end(),attack(3,side=1),end(side=1),ability(0,'energize:1',2),block(2,3),end(),end(),attack(3,side=1),end(side=1),block(2,3),end()],
     {'type':'clear','protect':[2]},[
     {'label':'Deny regeneration instead of overloading the enemy','commands':[cast('RIOT',3)]},
     {'label':'Only weaken the enemy and wait through its first turn','commands':[cast('WEAK',3),end(),end(side=1)]}])
    for entry in out:
     if entry['id'].endswith('riot_on_repeat'):
      entry['alternative_solutions'] = [
       {'label': 'Use the Shaman once and Call Lightning for the second finish',
        'commands': [cast('RIOT',3),ability(2,'sting',3),cast('RIOT',4),cast('CLIG',4)]}
      ]
    return out
