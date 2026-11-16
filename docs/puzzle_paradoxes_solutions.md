# Paradoxes solutions

**Spoilers below.** Use the three in-game hints for a gradual nudge. These are tested reference solutions, not the only accepted sequences. Enemy commands show a concrete legal response.

## Etherlords I

### Borrowed Scissors / Чужие ножницы

`el1_tactical_v2_paradox_borrowed_scissors` · Medium · survive · 1 own turn(s)

**Briefing:** Survive the committed attack and preserve both allies. Your hero has one health. Both the Hopper and Rock Wall carry Redirect. The Stink Rat carries Spell Breaker and attacks before the Giant Bat.

**Обстановка:** Переживите уже объявленную атаку, сохранив обоих союзников. У героя одно здоровье. И на Прыгуне, и на Каменной стене есть Переадресация. Вонючая крыса несёт Разрушитель Чар и атакует раньше Гигантской летучей мыши.

**Hints:**

1. The larger defender is not the safest first blocker. Think about which ally should still carry Redirect when the Bat strikes.
2. In this edition, Spell Breaker removes a creature’s enchantments before its strike damages that creature. A blocked Rat can remove the dangerous obligation from your smaller shield.
3. Block the Stink Rat with the Hopper. Leave the Giant Bat unblocked: after the Rat strips the Hopper’s Redirect, only the Rock Wall will receive the redirected five damage.

**Подсказки:**

1. Самый крупный защитник — не лучший первый блокирующий. Подумайте, на ком должна остаться Переадресация к удару Мыши.
2. В этой игре Разрушитель Чар снимает чары с существа до нанесения урона. Заблокированная Крыса может освободить меньший щит от опасной обязанности.
3. Блокируйте Вонючую крысу Прыгуном. Гигантскую летучую мышь пропустите: после снятия Переадресации с Прыгуна все пять перенаправленного урона получит только Каменная стена.

**Why it works:** The Rat’s Spell Breaker removes Redirect from the Hopper before dealing one damage. The Hopper survives and kills the Rat with its two-power return strike. The Bat then hits your hero for five, but the remaining Redirect sends that damage to the ten-toughness Rock Wall and spares the hero completely. Both allies survive. Blocking the Rat with the Wall removes the wrong Redirect: the fragile Hopper then receives the Bat’s full five damage and dies. Redirect does not divide the damage between its holders.

**Почему это работает:** Разрушитель Чар Крысы снимает Переадресацию с Прыгуна до нанесения одного урона. Прыгун выживает и убивает Крысу ответным ударом силой два. Мышь затем наносит герою пять, но оставшаяся Переадресация переносит урон на Каменную стену с десятью стойкости, полностью сохраняя здоровье героя. Оба союзника живы. Если блокировать Крысу Стеной, снимется не та Переадресация: хрупкий Прыгун получит все пять урона Мыши и погибнет. Переадресация не делит урон между своими носителями.

**Exact commands:**

```json
[
  {
    "id": 2.0,
    "kind": "block",
    "target": 4.0
  },
  {
    "kind": "end_phase"
  }
]
```

**Tempting alternatives and observed evidence:**

- Let the Rock Wall absorb the Rat: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Keep the Change / Оставьте сдачу

`el1_tactical_v2_paradox_keep_the_change` · Medium · win · 1 own turn(s)

**Briefing:** Win before your second turn. You have three ether and one health; the enemy has four health and will refill four ether. The enemy has no cards or activated abilities, only three Tick Warriors. Ether Burn hurts each acting hero for their unspent ether at turn end. Timidity charges one ether for each attack declaration. Your Wall of Distortion can close combat.

**Обстановка:** Победите до своего второго хода. У вас три эфира и одно здоровье; у врага четыре здоровья, и он пополнит четыре эфира. У врага нет карт и активных способностей, только три Клеща-воина. Обжигающий Эфир в конце хода наносит действующему герою урон за весь неизрасходованный эфир. Нерешительность берёт один эфир за каждое объявление атаки. Стена искажения может прекратить бой.

**Hints:**

1. Your own pool must be empty, while the enemy’s pool must stay full. Preventing combat damage is only half the problem.
2. Under Timidity, an enemy can spend ether merely by declaring attacks. Cancelling those attacks later does not refund that ether.
3. Spend all three ether on Ether Burn and Timidity, then activate the Wall of Distortion before passing. The enemy cannot declare attacks and therefore cannot spend any of the four ether that will burn them.

**Подсказки:**

1. Ваш запас должен стать пустым, а вражеский — остаться полным. Одного предотвращения боевого урона недостаточно.
2. При Нерешительности враг тратит эфир уже при объявлении атаки. Последующая отмена атаки этот эфир не возвращает.
3. Потратьте все три эфира на Обжигающий Эфир и Нерешительность, затем активируйте Стену искажения до передачи хода. Враг не сможет объявить атаки и потратить хотя бы часть четырёх эфира, которые его сожгут.

**Why it works:** Ether Burn costs two and Timidity costs one, leaving you with nothing to burn at your own turn end. Activating distortion now prevents every enemy attack declaration. Their four channels refill four ether; with no cards, abilities or legal attacks, all four remain when Ether Burn resolves and defeat the four-health hero. Waiting until defence allows the enemy to pay attack taxes first. Even one declaration spends a coin, so cancelling that attack leaves only three burn damage and misses the deadline.

**Почему это работает:** Обжигающий Эфир стоит два, Нерешительность — один: к концу вашего хода обжигать нечего. Немедленное искажение запрещает врагу объявлять атаки. Четыре канала пополняют четыре эфира; без карт, способностей и доступных атак весь запас остаётся к срабатыванию Обжигающего Эфира и убивает героя с четырьмя здоровья. Если ждать фазы защиты, враг сначала оплатит объявления атак. Даже одно объявление расходует монету: отменённая позднее атака оставляет лишь три урона от эфира, и срок будет упущен.

**Exact commands:**

```json
[
  {
    "card": "MNBN",
    "kind": "cast",
    "target": -1.0
  },
  {
    "card": "LSDS",
    "kind": "cast",
    "target": -1.0
  },
  {
    "id": 2.0,
    "key": "distortion",
    "kind": "ability",
    "target": -1.0
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Save distortion until after the enemy declares an attack: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### No Free Funerals / Похороны не бесплатны

`el1_tactical_v2_paradox_no_free_funerals` · Medium · clear · 1 own turn(s)

**Briefing:** Clear the enemy army this turn and preserve both of your Treants. You have seven ether, four health and one Spiritual Web already active. The enemy has exactly one ether, enough for the Great Treant’s regeneration. Fury of Nature charges its caster health for every creature it tries to destroy, including regenerated survivors.

**Обстановка:** Очистите вражескую армию за этот ход и сохраните обоих своих древней. У вас семь эфира, четыре здоровья и уже действует одна Паутина Душ. У врага ровно один эфир — достаточно для регенерации Старого древня. Ярость Природы наносит заклинателю урон за каждую попытку уничтожить существо, включая спасённых регенерацией.

**Hints:**

1. The River Halo can both deny an enemy recovery and finance a friendly one. Do that before sweeping the battlefield.
2. Fury of Nature costs six. Your two Treants need one ether each to regenerate. The existing Web heals you for actual deaths; another Web would spend a coin needed to keep a Treant alive.
3. Siphon the enemy’s last ether with the River Halo, raising your pool to eight. Cast Fury of Nature immediately. Keep the last two ether for the two automatic regenerations.

**Подсказки:**

1. Речной нимб одновременно лишает врага восстановления и оплачивает ваше. Сделайте это до уничтожения армий.
2. Ярость Природы стоит шесть. Каждому из ваших древней нужен ещё один эфир для регенерации. Действующая Паутина лечит за реальные смерти; новая потратит монету, нужную живому древню.
3. Речным нимбом заберите последний эфир врага, подняв свой запас до восьми. Сразу примените Ярость Природы. Последние два эфира оставьте для двух автоматических регенераций.

**Why it works:** Siphon moves the enemy’s one ether to you: eight is exactly six for Fury of Nature and two for the friendly Treants’ regeneration. The enemy Treant now has no ether to regenerate. Fury attempts five destructions; your two protected Treants survive, while the Halo and both enemies die. The existing Spiritual Web heals three, then Fury deals five to the caster: four health becomes two. Buying a second Web increases healing but leaves only one ether after the spell, so one protected Treant dies and the objective fails.

**Почему это работает:** Нимб переносит к вам единственный эфир врага: восемь — ровно шесть на Ярость Природы и два на регенерации союзных древней. У вражеского древня эфира для регенерации больше нет. Ярость делает пять попыток уничтожения; два защищаемых древня выживают, а Нимб и оба врага погибают. Действующая Паутина Душ лечит на три, затем Ярость наносит заклинателю пять: четыре здоровья превращаются в два. Вторая Паутина даёт больше лечения, но оставляет после заклинания лишь один эфир. Один из защищаемых древней погибает, и задача провалена.

**Exact commands:**

```json
[
  {
    "id": 4.0,
    "key": "siphon",
    "kind": "ability",
    "target": -1.0
  },
  {
    "card": "FRNT",
    "kind": "cast",
    "target": -1.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Buy a second Spiritual Web before the mass destruction: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Riot on Repeat / Бескровие на бис

`el1_tactical_v2_paradox_riot_on_repeat` · Medium · clear · 1 own turn(s)

**Briefing:** Clear both wounded enemies this turn and preserve the Kobold Shaman. Each enemy has one toughness remaining, but both can regenerate for one ether and the enemy has two ether. You have five ether, one Riot, Call Lightning and an unused Energize ability. Riot returns to its caster’s hand when its creature leaves play.

**Обстановка:** Уничтожьте обоих раненых врагов за этот ход и сохраните Кобольда-шамана. У каждого врага осталась одна стойкость, но оба регенерируют за один эфир, а у противника есть два эфира. У вас пять эфира, одно Бескровие, Молния и неиспользованная Подзарядка. Когда носитель Бескровия покидает поле, карта возвращается в руку заклинателя.

**Hints:**

1. You do not need two copies of the anti-regeneration enchantment. You need the first enchanted creature to die before choosing the second.
2. Riot prevents regeneration and returns after the first death. Its two casts cost four ether. The final ether can pay either to ready the Shaman or to cast Call Lightning.
3. Enchant one enemy with Riot, then kill it with the Shaman’s shot. Reuse the returned Riot on the other enemy. Finish with either Energize plus a second shot, or Call Lightning.

**Подсказки:**

1. Вам не нужны две копии чар против регенерации. Нужно, чтобы первый зачарованный враг погиб раньше, чем вы займётесь вторым.
2. Бескровие запрещает регенерацию и возвращается после первой смерти. Два применения стоят четыре эфира. Последний эфир можно потратить на пробуждение Шамана или на Молнию.
3. Наложите Бескровие на одного врага и убейте его выстрелом Шамана. Вернувшимся Бескровием зачаруйте второго. Добейте его либо Подзарядкой и вторым выстрелом, либо Молнией.

**Why it works:** Each enemy’s last point is protected by regeneration until Riot forbids it. The first shot kills the cursed creature and returns Riot to your hand, so you can curse the other enemy. Four ether pays for the two casts. One valid plan spends the fifth ether on Energize and uses the Shaman twice; a different plan uses the Shaman once and pays the final ether for Call Lightning. Either route clears both enemies. Damage before Riot merely triggers regeneration, erases the old wounds and consumes a limited damage tool before it can finish its job.

**Почему это работает:** Последнюю стойкость каждого врага защищает регенерация, пока её не запретит Бескровие. Первый выстрел убивает зачарованное существо и возвращает Бескровие в руку: теперь можно зачаровать второго врага. Четыре эфира оплачивают два применения. Один верный план тратит пятый эфир на Подзарядку и стреляет Шаманом дважды; другой использует Шамана один раз и оплачивает последним эфиром Молнию. Оба плана очищают поле. Урон до Бескровия лишь запускает регенерацию, стирает старые раны и тратит ограниченный источник урона до того, как он сможет добить цель.

**Exact commands:**

```json
[
  {
    "card": "RIOT",
    "kind": "cast",
    "target": 3.0
  },
  {
    "id": 2.0,
    "key": "sting",
    "kind": "ability",
    "target": 3.0
  },
  {
    "id": 0.0,
    "key": "energize:1",
    "kind": "ability",
    "target": 2.0
  },
  {
    "card": "RIOT",
    "kind": "cast",
    "target": 4.0
  },
  {
    "id": 2.0,
    "key": "sting",
    "kind": "ability",
    "target": 4.0
  }
]
```

**Another winning route: Use the Shaman once and Call Lightning for the second finish**

```json
[
  {
    "card": "RIOT",
    "kind": "cast",
    "target": 3.0
  },
  {
    "id": 2.0,
    "key": "sting",
    "kind": "ability",
    "target": 3.0
  },
  {
    "card": "RIOT",
    "kind": "cast",
    "target": 4.0
  },
  {
    "card": "CLIG",
    "kind": "cast",
    "target": 4.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Shoot the Treant before denying regeneration: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Cast Call Lightning before using the returning curse: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.



### A Fatal Upgrade / Смертельное улучшение

`el1_tactical_v2_paradox_fatal_upgrade` · Medium · clear · 3 own turn(s)

**Briefing:** Clear the enemy army within three of your turns and preserve the Rock Wall. The enemy Great Treant has eight ether and eight channels, so ordinary destruction can be regenerated repeatedly. You have five ether, no channels and an unused Energize. Your Wall is resting. Overload adds five power and toughness, then permanently removes two of each at every turn end belonging to its creature’s controller.

**Обстановка:** Очистите вражескую армию за три своих хода и сохраните Каменную стену. У вражеского Старого древня восемь эфира и восемь каналов: обычное уничтожение можно многократно переживать регенерацией. У вас пять эфира, нет каналов и доступна Подзарядка. Стена отдыхает. Перегрузка добавляет пять силы и стойкости, затем навсегда отнимает по два в конце каждого хода хозяина существа.

**Hints:**

1. Stopping regeneration is not enough: your Wall has no power to kill the Treant. Look for a death caused by the creature’s own shrinking statistics.
2. Overload and Weaken together make the Treant 4/4. Its two end-of-turn reductions will make it 2/2 and then 0/0. You still need a safe blocker while the clock runs.
3. Cast Overload and Weaken on the enemy Treant before the first enemy turn. Save the last ether for Energize on the Wall. Block any Treant attack; its second end-of-turn decay kills it without regeneration.

**Подсказки:**

1. Одного запрета регенерации недостаточно: у Стены нет силы для убийства древня. Ищите гибель от уменьшения собственных показателей существа.
2. Перегрузка вместе со Слабостью делает древня 4/4. Два уменьшения в конце хода превратят его в 2/2, затем в 0/0. Пока идёт отсчёт, всё ещё нужен безопасный защитник.
3. До первого хода врага примените к древню Перегрузку и Слабость. Последний эфир оставьте на Подзарядку Стены. Блокируйте атаки древня; второй распад в конце его хода убьёт его без регенерации.

**Why it works:** Overload adds five and Weaken subtracts four from the Treant’s printed 3/3, making 4/4. Four ether pays for that pair, leaving the one ether needed to ready your Wall. The first enemy turn end applies two points of permanent decay, leaving 2/2; the next applies two more, leaving zero toughness. Overload’s decay kills without regeneration, regardless of the enemy’s stocked ether. A ten-toughness Wall safely holds either attack, and passing does not spare the Treant from decay. Casting Riot instead removes regeneration without supplying lethal damage. Merely weakening and waiting loses the opening mana: with no channels, your next refill is zero.

**Почему это работает:** Перегрузка добавляет пять, а Слабость отнимает четыре от печатных 3/3 древня: получается 4/4. Эта пара стоит четыре эфира, оставляя один для пробуждения Стены. В конце первого вражеского хода постоянный распад отнимает два, оставляя 2/2; в конце следующего — ещё два, снижая стойкость до нуля. Распад Перегрузки убивает без регенерации независимо от запаса эфира врага. Стена с десятью стойкости выдерживает любую атаку, а пропуск атаки не спасает древня от распада. Бескровие вместо Перегрузки запрещает регенерацию, но не создаёт смертельного урона. Если лишь ослабить и ждать, начальный эфир пропадёт: без каналов следующее пополнение равно нулю.

**Exact commands:**

```json
[
  {
    "card": "OVRL",
    "kind": "cast",
    "target": 3.0
  },
  {
    "card": "WEAK",
    "kind": "cast",
    "target": 3.0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 3.0,
    "kind": "attack",
    "side": 1.0
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 0.0,
    "key": "energize:1",
    "kind": "ability",
    "target": 2.0
  },
  {
    "id": 2.0,
    "kind": "block",
    "target": 3.0
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 3.0,
    "kind": "attack",
    "side": 1.0
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 2.0,
    "kind": "block",
    "target": 3.0
  },
  {
    "kind": "end_phase"
  }
]
```

**Tempting alternatives and observed evidence:**

- Deny regeneration instead of overloading the enemy: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Only weaken the enemy and wait through its first turn: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.



### Night Shift / Ночная смена

`el1_tactical_v2_paradox_night_shift` · Hard · win · 3 own turn(s)

**Briefing:** Win in three turns, preserving your Orc Guard, Orc Shaman and Rock Wall. Smoke is already active: resting creatures will not rise naturally. The enemy Orc Elder gives every Orc on either side Restless. It currently has one wound. You have two Cloaks of Fear, one Call Lightning, five ether and no channels. The enemy has no hand cards.

**Обстановка:** Победите за три хода, сохранив Орка-стражника, Орка-шамана и Каменную стену. Уже действует Дым: отдыхающие существа сами не поднимаются. Вражеский Старейшина орков даёт всем оркам с обеих сторон возможность не отдыхать после атаки. Сейчас у него одна рана. У вас две Маски Ужаса, одна Молния, пять эфира и нет каналов. Рука врага пуста.

**Hints:**

1. Choose attackers for all three turns, not only for the first attack. One enemy is supplying the exception to Smoke that your army needs.
2. The Elder makes both of your Orcs Restless. The Hopper is not an Orc and would stay resting after one attack. The Guard also needs another Orc to declare first.
3. Give the two Cloaks to the Guard and Shaman. Each turn declare the Shaman first, then the Guard; their three unblockable damage adds up to nine. Keep the Rock Wall ready to block the Elder. Do not kill the Elder.

**Подсказки:**

1. Выбирайте атакующих на все три хода, а не только на первую атаку. Один враг даёт вашей армии нужное исключение из действия Дыма.
2. Благодаря Старейшине оба ваших орка не отдыхают после атаки. Прыгун не орк и после первого удара останется отдыхать. Стражнику также нужен другой орк, объявленный атакующим раньше него.
3. Дайте Маски Стражнику и Шаману. Каждый ход сначала объявляйте атаку Шамана, затем Стражника: три неблокируемых урона за ход дадут девять. Каменной стеной блокируйте Старейшину. Не убивайте его.

**Why it works:** The enemy Elder’s aura lets both friendly Orcs attack without resting, so Smoke cannot lock them out of later turns. Cloaks protect both lanes from the Elder’s blocks; declaring the one-power Shaman first enables the two-power Guard’s team attack. Three damage on each of three turns defeats the nine-health hero. The Rock Wall safely absorbs any six-power counterattack. A cloaked Hopper contributes only once, and an uncloaked Shaman can be killed by a block. Call Lightning can kill the wounded Elder immediately, but that removes Restless and leaves your attackers permanently resting after their first attack. Using the Shaman’s ether ability would also rest it: Restless prevents resting from attacks, not from that ability.

**Почему это работает:** Аура вражеского Старейшины позволяет обоим союзным оркам атаковать без отдыха, поэтому Дым не лишает их следующих ходов. Маски защищают обе атаки от блока Старейшины; объявленный первым Шаман с силой один разрешает парную атаку Стражника с силой два. Три урона на каждом из трёх ходов побеждают героя с девятью здоровья. Каменная стена выдерживает ответные атаки силой шесть. Прыгун с Маской ударит лишь однажды, а Шамана без Маски враг может убить блоком. Молния сразу убивает раненого Старейшину, но вместе с ним исчезает отсутствие отдыха: после первой атаки ваши орки навсегда лягут под Дымом. Способность Шамана получать эфир тоже усыпит его: аура предотвращает отдых после атаки, а не после этой способности.

**Exact commands:**

```json
[
  {
    "card": "CLFR",
    "kind": "cast",
    "target": 2.0
  },
  {
    "card": "CLFR",
    "kind": "cast",
    "target": 3.0
  },
  {
    "id": 3.0,
    "kind": "attack"
  },
  {
    "id": 2.0,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 6.0,
    "kind": "attack",
    "side": 1.0
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 5.0,
    "kind": "block",
    "target": 6.0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 3.0,
    "kind": "attack"
  },
  {
    "id": 2.0,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 6.0,
    "kind": "attack",
    "side": 1.0
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 5.0,
    "kind": "block",
    "target": 6.0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 3.0,
    "kind": "attack"
  },
  {
    "id": 2.0,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Kill the wounded enemy Elder before attacking: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Cloak the Hopper and send the exposed Shaman as the Guard’s partner: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### The Living Budget / Живой бюджет

`el1_tactical_v2_paradox_living_budget` · Hard · control · 1 own turn(s)

**Briefing:** Survive this committed attack, then capture this exact Bat during your next attack phase. Keep the Wall of Force, Orc Guard and Hopper alive. You have one ether, six channels and two unused Ether Feeding abilities. Thirsty Creatures is active: after your refill, every creature you still own costs one ether. The enemy has no hand cards. A newborn recruit is not needed for this defence.

**Обстановка:** Переживите уже объявленную атаку, затем в своей следующей фазе атаки захватите именно эту Летучую мышь. Сохраните Стену силы, Орка-стражника и Прыгуна. У вас один эфир, шесть каналов и две неиспользованные Эфирные Подпитки. Действует Эфирная Жажда: после пополнения каждое ваше существо заберёт один эфир. Рука врага пуста. Новое существо для этой защиты не требуется.

**Hints:**

1. You need five ether for Change of Command. Forecast the next refill after paying for your surviving army, not just the channel total.
2. Each Ether Feeding adds one channel and removes one future upkeep payment. Only the Rat and Shaman may be sacrificed. First collect the Shaman’s ether so you can afford both sacrifices.
3. Use the Orc Shaman’s ether ability, then feed the Rat and Shaman through the two Ether Feeding abilities. Block the Bat with the Wall and the Treant with the Guard. Eight channels minus three survivors leaves five ether next turn: capture the Bat.

**Подсказки:**

1. На Переподчинение нужно пять эфира. Считайте следующий запас после содержания выжившей армии, а не просто число каналов.
2. Каждая Эфирная Подпитка добавляет канал и убирает одну будущую плату за содержание. Жертвовать можно только Крысой и Шаманом. Сначала получите эфир от Шамана, чтобы оплатить обе жертвы.
3. Получите эфир Орком-шаманом, затем двумя Эфирными Подпитками пожертвуйте Крысу и Шамана. Стеной блокируйте Мышь, Стражником — древня. Восемь каналов минус три выживших оставят пять эфира: подчините Мышь.

**Why it works:** The Shaman raises your current pool from one to two. Two Ether Feeding activations spend it, sacrifice the two unprotected creatures and raise channels from six to eight. The Wall blocks the Bat without killing the future recruit; the Guard survives the Treant’s three damage. At your next turn, eight ether refills and Thirsty Creatures takes three for the remaining Wall, Guard and Hopper. The exact five left pays Change of Command. With only one sacrifice, seven channels minus four creatures leaves three. Sacrificing the Shaman before using its ability leaves no second payment; postponing the other sacrifice cannot retroactively increase the refill you already received.

**Почему это работает:** Шаман увеличивает текущий запас с одного до двух. Две Эфирные Подпитки расходуют его, приносят в жертву двух незащищаемых существ и повышают число каналов с шести до восьми. Стена блокирует Мышь, не убивая будущего новобранца; Стражник выдерживает три урона древня. В начале вашего хода восемь эфира пополняются, а Эфирная Жажда забирает три за оставшихся Стену, Стражника и Прыгуна. Ровно пять остатка оплачивают Переподчинение. Одна жертва даёт семь каналов минус четыре существа, то есть лишь три эфира. Если пожертвовать Шамана до его способности, не хватит второй оплаты. Поздняя жертва не увеличит уже полученное пополнение задним числом.

**Exact commands:**

```json
[
  {
    "id": 6.0,
    "key": "ether",
    "kind": "ability",
    "target": -1.0
  },
  {
    "id": 0.0,
    "key": "spirit_lock:1",
    "kind": "ability",
    "target": 5.0
  },
  {
    "id": 0.0,
    "key": "spirit_lock:2",
    "kind": "ability",
    "target": 6.0
  },
  {
    "id": 2.0,
    "kind": "block",
    "target": 8.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 7.0
  },
  {
    "kind": "end_phase"
  },
  {
    "card": "CHCM",
    "kind": "cast",
    "target": 8.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Feed the Shaman first and postpone the Rat until after refill: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Keep the second sacrifice and spend the resulting three ether on Fog: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



## Etherlords II

### After the Storm / После шторма

`el2_tactical_v2_paradox_after_fire` · Medium · win · 1 own turn(s)

**Briefing:** Win this turn. Your Pale Healer is in the Colourless Plane. The enemy holds one Fog and has no ether, but its active Ether Harvest grants it two ether whenever you cast a creature summoning.

**Обстановка:** Победите за этот ход. Ваш Бесцветный Целитель находится в Бесцветном Плане. У врага есть один Туман и нет эфира, но его Эфирный Урожай даёт ему два эфира всякий раз, когда вы произносите заклинание вызова существа.

**Hints:**

1. The Healer needs a sacrifice after the blockers have gone. Plan when that sacrifice arrives.
2. A Pale Avenger trap creates its creature after the sorcery finishes. The trap's creature does not count as a creature spell for Ether Harvest.
3. Set Pale Avenger, cast Lightning Storm, then sacrifice the newly arrived Avenger to manifest the Healer. Attack for three.

**Подсказки:**

1. Целителю нужна жертва после исчезновения блокирующих. Продумайте момент её появления.
2. Ловушка Бесцветного Мстителя создаёт существо после завершения волшебства. Такое появление не считается заклинанием вызова для Эфирного Урожая.
3. Поставьте ловушку Бесцветного Мстителя, произнесите Шторм Молний и пожертвуйте появившимся Мстителем для проявления Целителя. Атакуйте на три.

**Why it works:** The one-ether trap and two-ether storm use the whole budget. Lightning Storm removes both blockers while the Healer remains safe in the Plane; only then does the Avenger arrive. Cruel manifestation consumes that new body without resting the Healer. The Healer deals exactly three. Starting with the storm leaves no later sorcery to trigger a trap; summoning a Stink Rat instead gives the enemy enough ether for Fog.

**Почему это работает:** Ловушка за один эфир и Шторм за два расходуют весь запас. Шторм Молний убивает обоих блокирующих, пока Целитель укрыт в Бесцветном Плане; лишь затем появляется Мститель. Жестокое проявление поглощает новое существо, не заставляя Целителя отдыхать. Целитель наносит ровно три урона. Если начать со Шторма, для ловушки уже не останется волшебства; обычный вызов Вонючей крысы даст врагу эфир на Туман.

**Exact commands:**

```json
[
  {
    "card": "OST1",
    "kind": "cast",
    "target": -1.0
  },
  {
    "card": "LGST",
    "kind": "cast",
    "target": -1.0
  },
  {
    "id": 2.0,
    "key": "cruel",
    "kind": "ability",
    "target": 5.0
  },
  {
    "id": 2.0,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Sweep before setting the trap: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### The Last Spell Is No Spell / Последнее заклинание — не заклинание

`el2_tactical_v2_paradox_last_spell` · Medium · clear · 1 own turn(s)

**Briefing:** Clear the enemy army this turn and preserve your Pale Spelleater. Data Attraction is already active on your two-health hero. The Lamia Monk has four wounds; the Spelleater starts ready in the Colourless Plane.

**Обстановка:** Уничтожьте армию врага за этот ход и сохраните Бесцветного Чароеда. На вашем герое с двумя жизнями уже действует Притяжение Данных. У Ламии-монахини четыре раны; Чароед готов к действию и находится в Бесцветном Плане.

**Hints:**

1. Removing a dangerous enchantment can still be dangerous if the removal itself is a spell.
2. Data Attraction remembers a non-creature spell before that spell resolves. Absorption is an ability and also returns the enchantment's printed ether cost.
3. Absorb your own Data Attraction: pay one and recover four, reaching five ether. Dwindle the wounded Monk, then use one Call Lightning on each smaller enemy.

**Подсказки:**

1. Снятие опасных чар тоже может быть опасным, если само является заклинанием.
2. Притяжение Данных замечает заклинание, не вызывающее существо, до завершения его действия. Поглощение — способность; она также возвращает печатную цену чар.
3. Поглотите своё Притяжение Данных: потратьте один эфир и получите четыре, доведя запас до пяти. Истощением убейте раненую монахиню, затем направьте по Молнии в каждого малого врага.

**Why it works:** Absorption removes Data Attraction without triggering its two-point backlash and leaves exactly five ether. Dwindle costs three and reduces the Monk's toughness to its existing four wounds; the two one-ether Lightning spells clear the other creatures. Lesser Disenchant does remove Data Attraction, but the already registered backlash still resolves and kills the hero. Mystic manifestation also avoids the backlash, but gives no ether refund: two ether cannot buy the required five-ether clearance. Absorption lets the Spelleater remain in the Plane.

**Почему это работает:** Поглощение убирает Притяжение Данных без двух единиц ответного урона и оставляет ровно пять эфира. Истощение стоит три и снижает стойкость монахини до уже полученных четырёх ран; две Молнии по одному эфиру убивают остальных. Снятие Чар убирает Притяжение Данных, но уже зарегистрированная отдача всё равно срабатывает и убивает героя. Мистическое проявление тоже избегает отдачи, однако не возвращает эфир: двух единиц недостаточно для нужной зачистки за пять. Поглощение позволяет Чароеду остаться в Бесцветном Плане.

**Exact commands:**

```json
[
  {
    "choice": 1.0,
    "id": 2.0,
    "key": "absorb",
    "kind": "ability",
    "target": 0.0
  },
  {
    "card": "DWND",
    "kind": "cast",
    "target": 3.0
  },
  {
    "card": "CLIG",
    "kind": "cast",
    "target": 4.0
  },
  {
    "card": "CLIG",
    "kind": "cast",
    "target": 5.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Disenchant Data Attraction: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Remove Data Attraction by free Mystic manifestation: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Empty the Other Room / Опустошите другую комнату

`el2_tactical_v2_paradox_empty_room` · Medium · win · 1 own turn(s)

**Briefing:** Win this turn. Transfer Aspects is active. Your Knight and the enemy Spelleater are in the Colourless Plane; the enemy Spellshifter is in the Ether. The enemy holds exactly two Fogs and can afford one.

**Обстановка:** Победите за этот ход. Действует Обмен Планами. Ваш Рыцарь и вражеский Чароед находятся в Бесцветном Плане, а вражеский Ловкач — в Эфирном. У врага ровно два Тумана и достаточно эфира на один.

**Hints:**

1. Opening an attack lane is only half the job. Both Fogs must disappear before the enemy can answer.
2. Pale Theft counts distinct Pale races; these two enemy enchanters share a race. Pale Calamity counts individual creatures in the Plane.
3. Transfer Aspects: manifest your Knight and send the enemy Spellshifter into the Plane. Cast Pale Calamity to discard both Fogs, then attack with the Knight.

**Подсказки:**

1. Свободный путь для атаки — лишь половина дела. До ответа противника должны исчезнуть оба Тумана.
2. Бесцветное Воровство считает разные расы бесцветных; оба вражеских чародея принадлежат одной расе. Бесцветная Напасть считает отдельных существ в Бесцветном Плане.
3. Обменом Планами проявите своего Рыцаря и отправьте вражеского Ловкача в Бесцветный План. Бесцветной Напастью сбросьте оба Тумана, затем атакуйте Рыцарем.

**Why it works:** The exchange leaves two enemy creatures in the Plane and none of yours there. Calamity therefore empties the enemy's two-card hand while preserving your remaining cards. Neither Pale enchanter can block from the Plane, and the Knight deals eight. Theft removes only one Fog because both enemies belong to the same Pale race; spending four ether on it leaves too little for a second discard spell.

**Почему это работает:** После обмена в Бесцветном Плане находятся два вражеских существа и ни одного вашего. Поэтому Напасть опустошает руку врага из двух карт и сохраняет ваши оставшиеся карты. Из Бесцветного Плана чародеи блокировать не могут, и Рыцарь наносит восемь урона. Воровство убирает лишь один Туман: оба врага одной бесцветной расы. Его цена в четыре эфира не оставляет средств на второе заклинание сброса.

**Exact commands:**

```json
[
  {
    "choice": 4.0,
    "id": 0.0,
    "key": "recycle:1",
    "kind": "ability",
    "target": 2.0
  },
  {
    "card": "OMWP",
    "kind": "cast",
    "target": -1.0
  },
  {
    "id": 2.0,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Transfer correctly, then use Pale Theft to remove the Fogs: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### A Helpful Thief / Полезный вор

`el2_tactical_v2_paradox_stolen_reply` · Medium · win · 1 own turn(s)

**Briefing:** Survive this defence and win on your next turn. Both enemies are already attacking. Your only card is Call Lightning, and you have no ether or channels. The opponent holds three Fogs and has enough ether to cast one.

**Обстановка:** Переживите эту защиту и победите на следующем своём ходу. Оба врага уже атакуют. Ваша единственная карта — Молния; эфира и каналов у вас нет. У противника три Тумана и достаточно эфира на один.

**Hints:**

1. Keeping every card is not always the best outcome. Look at what happens when Lightning is stolen.
2. In this edition, an enemy-forced discard of Call Lightning immediately makes that enemy discard three cards. Your walls do not have to block every attacker.
3. Block the Steel Mechos with a wall and let the Maxi Hopper hit your hero. Its discard triggers Lightning's answer and removes all three Fogs. Attack with the Night Wolf next turn.

**Подсказки:**

1. Сохранение всех карт не всегда выгодно. Посмотрите, что происходит при краже Молнии.
2. В этой версии игры вынужденный по вине врага сброс Молнии немедленно заставляет этого врага сбросить три карты. Вашим стенам не обязательно блокировать каждого атакующего.
3. Заблокируйте Стального мехоса стеной и пропустите Большого прыгуна к герою. Сброс Молнии вызовет ответ и уберёт все три Тумана. На следующем ходу атакуйте Ночным волком.

**Why it works:** The wall absorbs the Mechos's eight damage. The Hopper deals three, leaving the hero at one, and steals the only card; Lightning's discard response removes the enemy's entire three-Fog hand. Next turn neither enemy creature is a wall, so neither can block the elusive Night Wolf. Blocking both attackers preserves an uncastable card and leaves Fog available to stop that final point of damage.

**Почему это работает:** Стена принимает восемь урона мехоса. Прыгун наносит три, оставляя герою одну жизнь, и крадёт единственную карту; ответ Молнии убирает всю руку врага из трёх Туманов. На следующем ходу ни одно вражеское существо не является стеной, поэтому не может заблокировать неуловимого Ночного волка. Блокирование обоих атакующих сохраняет карту, которую нечем произнести, и оставляет врагу Туман против последней единицы урона.

**Exact commands:**

```json
[
  {
    "id": 3.0,
    "kind": "block",
    "target": 5.0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 2.0,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Block both attackers and keep the card: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Family at a Distance / Родство на расстоянии

`el2_tactical_v2_paradox_borrowed_kin` · Hard · survive · 1 own turn(s)

**Briefing:** Survive this defence and preserve your Rat, Bronze Mechozaurus and Rock Wall. Both enemy Rats are attacking. Unity was already active with all three Rats in the Ether; the unaffected Mechozaurus is exempt. Transfer Aspects is active, and the enemy Pale Channeler is in the Colourless Plane.

**Обстановка:** Переживите эту защиту и сохраните свою крысу, Бронзового мехозавра и Каменную стену. Обе вражеские крысы атакуют. Единство уже действует, а все три крысы находятся в Эфирном Плане; невосприимчивый мехозавр исключён из его действия. Обмен Планами активен, вражеский Бесцветный Маг находится в Бесцветном Плане.

**Hints:**

1. Your Rat helps the enemy as long as it is nearby. Preserving it and weakening the attackers can be the same action.
2. Unity counts other creatures of the same race on both sides, but excludes relatives in the Colourless Plane. The Mechozaurus receives no matching bonus to its three toughness.
3. Manifest the enemy Pale Channeler with Transfer Aspects and send your own Rat into the Plane. The enemy Rats become 2/2. Block one with the Rock Wall and the other with the Bronze Mechozaurus.

**Подсказки:**

1. Пока ваша крыса рядом, она помогает врагу. Её спасение и ослабление атакующих могут оказаться одним действием.
2. Единство считает других существ той же расы с обеих сторон, но не учитывает родичей в Бесцветном Плане. Мехозавр не получает соответствующей прибавки к своим трём единицам стойкости.
3. Обменом Планами проявите вражеского Бесцветного Мага и отправьте свою крысу в Бесцветный План. Вражеские крысы станут 2/2. Одну заблокируйте Каменной стеной, другую — Бронзовым мехозавром.

**Why it works:** Three Rats in the Ether give every Rat two relatives, making the attackers 3/3. A three-point strike kills the unaffected 4/3 Mechozaurus before it can retaliate. Moving your Rat into the Plane removes one relative from each enemy's count, reducing both to 2/2. The Rock Wall safely holds one, while the Mechozaurus survives the other and kills it. The enemy Channeler enters too late to join this already declared attack; your ordinary Rat returns safely at your next turn.

**Почему это работает:** При трёх крысах в Эфирном Плане у каждой есть два родича, поэтому атакующие имеют 3/3. Удар на три убивает невосприимчивого мехозавра 4/3 до ответного удара. Уход вашей крысы в Бесцветный План убирает по одному родичу из подсчёта врагов и снижает обоих до 2/2. Каменная стена удерживает одного, а мехозавр переживает удар другого и убивает его. Вражеский Маг проявляется слишком поздно, чтобы присоединиться к уже объявленной атаке; ваша обычная крыса благополучно возвращается в начале вашего хода.

**Exact commands:**

```json
[
  {
    "choice": 2.0,
    "id": 0.0,
    "key": "recycle:2",
    "kind": "ability",
    "target": 7.0
  },
  {
    "id": 4.0,
    "kind": "block",
    "target": 5.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 6.0
  },
  {
    "kind": "end_phase"
  }
]
```

**Tempting alternatives and observed evidence:**

- Block without changing which Rats count as relatives: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Thank You for the Fog / Спасибо за Туман

`el2_tactical_v2_paradox_wanted_fog` · Hard · win · 2 own turn(s)

**Briefing:** Win within two of your turns while preserving both Wolves. The enemy holds exactly one Fog and two ether. You have two ether and no channels. A full counterattack would deal fourteen damage to your nine-health hero.

**Обстановка:** Победите за два своих хода, сохранив обоих волков. У врага ровно один Туман и два эфира. У вас два эфира и нет каналов. Полная ответная атака нанесла бы четырнадцать урона вашему герою с девятью жизнями.

**Hints:**

1. The enemy's best defence can supply the creature you need for the counterattack.
2. Pale Redeemer waits for an enemy sorcery. Fog creates a 2/2 Redeemer in the Plane; keeping one card lets it manifest before blocking.
3. Set Pale Redeemer and attack with both Wolves. If Fog answers, manifest the Redeemer next defence by discarding Lightning, and block the Fire Elemental. Take the Mechos's eight damage, then attack with both Wolves again.

**Подсказки:**

1. Лучшая защита противника может дать вам существо, необходимое против ответной атаки.
2. Бесцветный Искупитель ждёт вражеского волшебства. Туман создаёт Искупителя 2/2 в Бесцветном Плане; сохранённая карта позволит проявить его перед блокированием.
3. Поставьте ловушку Бесцветного Искупителя и атакуйте обоими волками. Если враг ответит Туманом, в следующей защите проявите Искупителя, сбросив Молнию, и заблокируйте Элементаля огня. Примите восемь урона мехоса, затем снова атакуйте обоими волками.

**Why it works:** The Wolves threaten exactly five elusive damage, so passing without Fog loses immediately. Fog's two-ether price supplies a 2/2 Redeemer after the sorcery resolves. Cryptic manifestation consumes the saved Lightning; the Redeemer blocks the non-trampling Fire Elemental and dissipates, leaving only the Mechos's eight damage to reach the hero. The Wolves recover for the next turn, and no Fog remains. If the enemy declines part or all of its counterattack, the same next-turn attack still wins. Blocking the larger Mechos with the Redeemer is fatal: trample spills six damage past it while the Elemental deals another six.

**Почему это работает:** Волки угрожают ровно пятью единицами неуловимого урона, поэтому отказ от Тумана немедленно проигрывает. Цена Тумана в два эфира создаёт Искупителя 2/2 после завершения волшебства. Тайное проявление поглощает сохранённую Молнию; Искупитель блокирует не имеющего пробивного удара Элементаля огня и рассеивается, оставляя герою лишь восемь урона мехоса. К следующему ходу волки восстанавливаются, а Тумана уже нет. Если враг откажется от части или всей ответной атаки, та же следующая атака всё равно победит. Блокировать более крупного мехоса Искупителем смертельно: шесть пробивного урона пройдут к герою, и ещё шесть нанесёт элементаль.

**Exact commands:**

```json
[
  {
    "card": "OST3",
    "kind": "cast",
    "target": -1.0
  },
  {
    "id": 2.0,
    "kind": "attack"
  },
  {
    "id": 3.0,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "card": "FOGG",
    "kind": "cast",
    "side": 1.0,
    "target": -1.0
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 4.0,
    "kind": "attack",
    "side": 1.0
  },
  {
    "id": 5.0,
    "kind": "attack",
    "side": 1.0
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 6.0,
    "key": "cryptic",
    "kind": "ability",
    "target": -1.0
  },
  {
    "id": 6.0,
    "kind": "block",
    "target": 4.0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 2.0,
    "kind": "attack"
  },
  {
    "id": 3.0,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Spend ether on Lightning before setting the trap: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Use the Redeemer to block the larger trampling attacker: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Pay at Every Door / Плата за каждую дверь

`el2_tactical_v2_paradox_every_door` · Expert · survive · 1 own turn(s)

**Briefing:** Survive the current attack and the next enemy turn, preserving all three Pale creatures. Your army starts in the Colourless Plane. Aspect Ward and Transfer Aspects are active; each aspect change of one of your creatures costs your hero one ether and one health. You have eight ether now, two channels for the next turn, and one Stink Rat in your graveyard.

**Обстановка:** Переживите текущую атаку и следующий ход врага, сохранив всех трёх бесцветных существ. Ваша армия находится в Бесцветном Плане. Действуют Планарный Барьер и Обмен Планами; каждая смена плана вашего существа стоит вашему герою один эфир и одну жизнь. Сейчас у вас восемь эфира, на следующий ход — два канала; в могильнике одна Вонючая крыса.

**Hints:**

1. Each of your creatures' changes of aspect charges your hero. Make those passages affordable before preparing the blocks.
2. The Healer restores three health. The grave manifests one Knight; Transfer Aspects can manifest the other while removing the attacking Rat. Lifeguard can protect either a toll payment or the Knight facing the Horror.
3. Heal, protect your hero with Lifeguard, manifest one Knight from your grave, and exchange the other with the attacking Rat. Block the Horror and Ogre. Next turn heal again, manifest the dissipated Knight using the Ogre's grave card, and keep one ether for its next dissipation. Block the Horror and returning Rat.

**Подсказки:**

1. За каждую смену плана вашего существа платит ваш герой. Обеспечьте эту плату до назначения блоков.
2. Целитель возвращает три жизни. Могильник проявляет одного Рыцаря; Обмен Планами может проявить второго и убрать атакующую крысу. Телохранитель способен поглотить либо плату жизнью, либо удар ужаса по Рыцарю.
3. Исцелитесь, наложите Телохранителя на героя, проявите одного Рыцаря из своего могильника, второго обменяйте с атакующей крысой. Блокируйте ужаса и людоеда. На своём ходу снова исцелитесь, проявите рассеянного Рыцаря картой людоеда из могильника врага и сохраните один эфир для следующего рассеивания. Блокируйте ужаса и вернувшуюся крысу.

**Why it works:** The reference uses Lifeguard to absorb the first manifestation's health toll. Healing raises health to four; the second manifestation leaves three. The Horror makes its Knight dissipate, costing another health and ether, and tramples for one: the hero survives at one. The other Knight kills the Ogre and supplies the next grave card. On your turn, heal again, consume that card to manifest the first Knight, and save the last ether for the second defence. A second plan puts Lifeguard on the Horror's blocker: it remains in the Ether after the first attack, so no second manifestation is needed. The Horror's one point of trample still reaches the hero in either plan.

**Почему это работает:** В основном решении Телохранитель поглощает плату жизнью за первое проявление. Исцеление поднимает жизни до четырёх; второе проявление оставляет три. Ужас заставляет своего блокирующего Рыцаря рассеяться, забирая ещё жизнь и эфир, и наносит герою один пробивной урон: остаётся одна жизнь. Второй Рыцарь убивает людоеда и создаёт следующую карту в могильнике. На своём ходу снова исцелитесь, потратьте эту карту для проявления первого Рыцаря и сохраните последний эфир на вторую защиту. Другой план накладывает Телохранителя на блокирующего ужаса Рыцаря: после первой атаки тот остаётся в Эфирном Плане и повторное проявление не требуется. Один пробивной урон ужаса достигает героя при обоих планах.

**Exact commands:**

```json
[
  {
    "card": "LFGR",
    "kind": "cast",
    "target": 0.0
  },
  {
    "id": 4.0,
    "key": "pale_heal",
    "kind": "ability",
    "target": -1.0
  },
  {
    "choice": 0.0,
    "id": 2.0,
    "key": "sinister",
    "kind": "ability",
    "target": 0.0
  },
  {
    "choice": 7.0,
    "id": 0.0,
    "key": "recycle:2",
    "kind": "ability",
    "target": 3.0
  },
  {
    "id": 2.0,
    "kind": "block",
    "target": 5.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 6.0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 4.0,
    "key": "pale_heal",
    "kind": "ability",
    "target": -1.0
  },
  {
    "choice": 0.0,
    "id": 2.0,
    "key": "sinister",
    "kind": "ability",
    "target": 1.0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 5.0,
    "kind": "attack",
    "side": 1.0
  },
  {
    "id": 7.0,
    "kind": "attack",
    "side": 1.0
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 2.0,
    "kind": "block",
    "target": 5.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 7.0
  },
  {
    "kind": "end_phase"
  }
]
```

**Another winning route: Protect the Knight from the Horror instead of shielding a toll**

```json
[
  {
    "id": 4.0,
    "key": "pale_heal",
    "kind": "ability",
    "target": -1.0
  },
  {
    "choice": 0.0,
    "id": 2.0,
    "key": "sinister",
    "kind": "ability",
    "target": 0.0
  },
  {
    "choice": 7.0,
    "id": 0.0,
    "key": "recycle:2",
    "kind": "ability",
    "target": 3.0
  },
  {
    "card": "LFGR",
    "kind": "cast",
    "target": 2.0
  },
  {
    "id": 2.0,
    "kind": "block",
    "target": 5.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 6.0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 4.0,
    "key": "pale_heal",
    "kind": "ability",
    "target": -1.0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 5.0,
    "kind": "attack",
    "side": 1.0
  },
  {
    "id": 7.0,
    "kind": "attack",
    "side": 1.0
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 2.0,
    "kind": "block",
    "target": 5.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 7.0
  },
  {
    "kind": "end_phase"
  }
]
```

**Tempting alternatives and observed evidence:**

- Manifest before securing the first health payment: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.
