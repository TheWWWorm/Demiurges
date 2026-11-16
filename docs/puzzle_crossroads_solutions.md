# Crossroads solutions

**Spoilers below.** Use the three in-game hints for a gradual nudge. These are tested reference solutions, not the only accepted sequences. Enemy commands show a concrete legal response.

## Etherlords I

### The Last Receipt / Последняя квитанция

`el1_tactical_v2_crossroads_last_receipt` · Medium · win · 1 own turn(s)

**Briefing:** Win before your second attack phase and preserve the Rock Wall. Both heroes are on turn fourteen, with the enemy already attacking. Your expert Channeling means the level-three enemy will take exactly four ether-disturbance damage at its next turn start; it currently has five health. Your own clock is safe. Repair Station is active, your graveyard is empty, and your one channel will refill one ether.

**Обстановка:** Победите до своей второй фазы атаки и сохраните Каменную стену. Оба героя находятся на четырнадцатом ходу, враг уже атакует. Ваш высший Контроль означает, что в начале следующего хода враг третьего уровня получит ровно четыре урона от возмущения эфира; сейчас у него пять здоровья. Вашему герою возмущение до срока не грозит. Ремонтная Мастерская действует, могильник пуст, единственный канал пополнит один эфир.

**Hints:**

1. Four impending damage is one short. The Repair Station can supply the missing point, but first it needs a creature card in your graveyard.
2. One route makes a safe combat sacrifice: the Rat holds the non-trampling Elemental, the Wall holds the Mechos, and the Bat deals three. Another route creates the corpse with Polymorph and prevents combat with Fog.
3. Either use those blocks, or Polymorph your own Rat and cast Fog. On your next turn use Repair Station on the Rat for one ether, then pass. Its ping leaves four health for the enemy’s four-point disturbance.

**Подсказки:**

1. До победы после четырёх ожидаемых урона не хватает единицы. Её даст Ремонтная Мастерская, но сначала в вашем могильнике должна появиться карта существа.
2. Один путь — безопасная боевая жертва: Крыса удерживает Элементаля без пробивного удара, Стена — мехоса, Мышь наносит три. Другой путь создаёт карту в могильнике Превращением и предотвращает бой Туманом.
3. Либо используйте указанные блоки, либо примените Превращение к своей Крысе и произнесите Туман. На следующем ходу за один эфир верните Крысу Ремонтной Мастерской и передайте ход. Её урон оставит врагу четыре здоровья перед возмущением на четыре.

**Why it works:** In the combat route, the Rock Wall absorbs the Mechos’s eight damage, the Rat dies blocking the non-trampling Elemental, and the Bat lowers your four health to one. In the spell route, Polymorph costs one, kills your Rat and sets your health to its one toughness; Fog costs the remaining two and prevents combat. Either route supplies the same grave card while preserving the Wall. The next one-ether refill pays Repair Station: the Rat returns to hand and the enemy takes one damage. Passing then reaches the disclosed four-point disturbance and wins before the enemy can act. Fog alone supplies no corpse. Creating the corpse only after the next refill spends the sole ether needed to repair it.

**Почему это работает:** В боевом плане Каменная стена поглощает восемь урона мехоса, Крыса погибает при блокировании Элементаля без пробивного удара, а Мышь снижает ваши четыре здоровья до одного. В плане с заклинаниями Превращение за один эфир убивает вашу Крысу и устанавливает здоровье равным её единице стойкости; Туман за оставшиеся два предотвращает бой. Оба пути дают одну и ту же карту в могильнике и сохраняют Стену. Следующее пополнение одного эфира оплачивает Ремонтную Мастерскую: Крыса возвращается в руку, враг получает один урон. Передача хода приводит к указанным четырём урона от возмущения и победе до действий врага. Один Туман не даёт карты в могильнике. Если создавать её только после пополнения, уйдёт единственный эфир, нужный для ремонта.

**Exact commands:**

```json
[
  {
    "id": 2.0,
    "kind": "block",
    "target": 4.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 5.0
  },
  {
    "kind": "end_phase"
  },
  {
    "choice": 0.0,
    "id": 0.0,
    "key": "repair:1",
    "kind": "ability",
    "target": 0.0
  },
  {
    "kind": "end_phase"
  }
]
```

**Another winning line: Polymorph the Rat and prevent combat with Fog**

```json
[
  {
    "card": "PLMR",
    "kind": "cast",
    "target": 3.0
  },
  {
    "card": "FOGG",
    "kind": "cast",
    "target": -1.0
  },
  {
    "kind": "end_phase"
  },
  {
    "choice": 0.0,
    "id": 0.0,
    "key": "repair:1",
    "kind": "ability",
    "target": 0.0
  },
  {
    "kind": "end_phase"
  }
]
```

**Tempting alternatives and observed evidence:**

- Cancel combat and postpone making the corpse: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### First Free the Midwife / Сначала освободите повитуху

`el1_tactical_v2_crossroads_free_midwife` · Medium · win · 2 own turn(s)

**Briefing:** Win within two turns and preserve all four original creatures. You have twelve ether and one health. Defense prevents your army from attacking. Irritation stops the second Mother Tick from using its ability and will deal one to you at your turn end. Each Mother’s brood costs four ether; a newborn may be sacrificed even while sick.

**Обстановка:** Победите за два хода и сохраните всех четырёх исходных существ. У вас двенадцать эфира и одно здоровье. Защита запрещает армии атаковать. Раздражение не даёт второй Матке клещей использовать способность и нанесёт вам один урон в конце вашего хода. Каждое потомство стоит четыре эфира; новорождённого можно принести в жертву, несмотря на болезнь вызова.

**Hints:**

1. Both enchantments must go, and every original creature must stay. Arrange a supply of two new sacrifices.
2. The first newborn must free the second Mother. Removing Defense first leaves you with only one operating Mother, already resting, while Irritation still kills you at turn end.
3. Brood with the unenchanted Mother. Sacrifice that newborn to remove Irritation from the second Mother. Brood with the freed Mother, then sacrifice its newborn to remove Defense. Attack with the Warrior and Worker on both turns.

**Подсказки:**

1. Нужно убрать обе чары и сохранить всех исходных существ. Организуйте появление двух новых жертв.
2. Первый новорождённый должен освободить вторую Матку. Если сначала снять Защиту, останется лишь одна способная действовать Матка, уже отдыхающая, а Раздражение всё ещё убьёт вас в конце хода.
3. Создайте потомство свободной Маткой. Пожертвуйте новорождённого ради снятия Раздражения со второй Матки. Ею создайте ещё одного и пожертвуйте его ради снятия Защиты. Оба хода атакуйте Воином и Рабочим.

**Why it works:** The first four-ether brood supplies a new Tick Warrior. A two-ether sacrificial dispel consumes that newborn and removes Irritation from the second Mother, making another brood possible. Its newborn pays for the other two-ether dispel, removing Defense. The whole chain costs twelve and preserves the four original creatures. The Worker’s shared bonus makes the original Warrior 3/3 and the Worker 1/3; their combined four damage twice defeats eight health. Removing Defense with the first sacrifice does permit an attack, but four damage is not lethal and the remaining Irritation kills your one-health hero before another brood or attack. The two dispel cards may trade places in the correct dependency chain.

**Почему это работает:** Первое потомство за четыре эфира даёт нового Клеща-воина. Жертвенное рассеивание за два поглощает его и снимает Раздражение со второй Матки, разрешая ещё одно потомство. Её новорождённый становится жертвой второго рассеивания за два, снимающего Защиту. Цепочка стоит двенадцать и сохраняет четырёх исходных существ. Общая прибавка Рабочего делает исходного Воина 3/3, самого Рабочего — 1/3; их суммарные четыре урона дважды снимают восемь здоровья. Снятие Защиты первой жертвой разрешает атаку, но четыре урона не смертельны, а оставшееся Раздражение убивает героя с одним здоровьем до нового потомства или атаки. Два жертвенных рассеивания можно поменять местами внутри верной цепочки.

**Exact commands:**

```json
[
  {
    "id": 2.0,
    "key": "brood",
    "kind": "ability",
    "target": -1.0
  },
  {
    "card": "ETTD",
    "grave": 2.0,
    "kind": "cast",
    "target": 6.0
  },
  {
    "id": 3.0,
    "key": "brood",
    "kind": "ability",
    "target": -1.0
  },
  {
    "card": "WHAS",
    "grave": 1.0,
    "kind": "cast",
    "target": 7.0
  },
  {
    "id": 4.0,
    "kind": "attack"
  },
  {
    "id": 5.0,
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
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 4.0,
    "kind": "attack"
  },
  {
    "id": 5.0,
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

- Use the first newborn to remove Defense: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.



### The Quiet Cleric / Тихий жрец

`el1_tactical_v2_crossroads_quiet_cleric` · Medium · clear · 1 own turn(s)

**Briefing:** Clear the enemy army within one turn and preserve your three original creatures. The Ogre King and Bat are already attacking. You have seven ether and an unused Second Birth, which charges the returned creature’s printed cost. Your grave holds a Cleric Spirit, Wizard Spirit and Shaman Spirit. Your Warrior Spirit already has Shell Skin and the Wizard’s shared power bonus. Returned Spirits are sick and cannot block immediately, but their passive auras already apply.

**Обстановка:** Очистите вражескую армию за один ход и сохраните трёх исходных существ. Вождь людоедов и Летучая мышь уже атакуют. У вас семь эфира и неиспользованное Второе Рождение, которое берёт печатную цену возвращаемого существа. В могильнике лежат Призрак-жрец, Призрак-колдун и Призрак-шаман. На Призраке-воине уже есть Ледяной Панцирь, и он получает общую прибавку силы Колдуна. Возвращённые духи больны после вызова и сразу блокировать не могут, но их пассивные ауры уже действуют.

**Hints:**

1. The new creature need not block. An immediate passive bonus can improve a defender that is already ready.
2. The Warrior needs six power to kill the King before the return strike. The Wind Wall needs two ether of power to kill the Bat. Reserve that second payment when choosing the grave card.
3. Return the five-cost Cleric Spirit with Second Birth. Its aura makes the Warrior 6/6. Spend the remaining two on the Wall of Wind’s power, then block the King with the Warrior and the Bat with the Wall.

**Подсказки:**

1. Новому существу необязательно блокировать. Немедленная пассивная прибавка может усилить уже готового защитника.
2. Воину нужно шесть силы, чтобы убить Вождя до ответного удара. Стене ветра нужны два эфира силы для убийства Мыши. При выборе карты из могильника сохраните вторую оплату.
3. Вторым Рождением верните Жреца за пять эфира. Его аура делает Воина 6/6. Оставшиеся два потратьте на силу Стены ветра. Воином блокируйте Вождя, Стеной — Мышь.

**Why it works:** Before the return, the Warrior is 5/5: its printed 3/1, the Wizard’s two power and Shell Skin’s four toughness. The Cleric’s immediate +1/+1 aura makes it 6/6 even though the new Cleric is still sick. First strike then kills the six-toughness Ogre King before its eight-power reply. Returning the Cleric costs five, leaving two ether to make the Wall of Wind 2/9, enough to survive and kill the 3/2 Bat. The obvious stronger-Wizard route leaves only one ether for that Wall; the cheaper Shaman route leaves the Warrior at five power. The reference plan needs the Cleric’s particular mix of cost and passive benefit.

**Почему это работает:** До возвращения Воин имеет 5/5: печатные 3/1, две силы от Колдуна и четыре стойкости от Ледяного Панциря. Немедленная аура Жреца +1/+1 делает его 6/6, хотя новый Жрец ещё болен после вызова. Первый удар убивает Вождя со стойкостью шесть до ответа силой восемь. Возвращение Жреца стоит пять, оставляя два эфира, чтобы сделать Стену ветра 2/9: она переживает удар Мыши 3/2 и убивает её. Прямой план с более сильным Колдуном оставляет Стене лишь один эфир; более дешёвый Шаман оставляет Воину пять силы. Эталонному плану требуется именно сочетание цены и пассивной прибавки Жреца.

**Exact commands:**

```json
[
  {
    "choice": 0.0,
    "id": 0.0,
    "key": "second_birth:1",
    "kind": "ability",
    "target": 0.0
  },
  {
    "amount": 2.0,
    "id": 4.0,
    "key": "lava_power",
    "kind": "ability",
    "target": -1.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 5.0
  },
  {
    "id": 4.0,
    "kind": "block",
    "target": 6.0
  },
  {
    "kind": "end_phase"
  }
]
```

**Tempting alternatives and observed evidence:**

- Raise the second Wizard, spend the last ether on the Wall, and hold out: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Raise the Shaman, buy two Wall power, and use the same blocks: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Life in Installments / Жизнь в рассрочку

`el1_tactical_v2_crossroads_life_installments` · Hard · win · 3 own turn(s)

**Briefing:** Win within three turns, preserving the Gibberling Gang and Rock Wall. You have five ether now, one channel, three health and an active Energize. The Gang is unblockable but does not rise naturally. The enemy has no hand cards. Its active Fireball costs one ether and deals two damage to any target; it starts with no ether and refills one each turn.

**Обстановка:** Победите за три хода, сохранив Шайку гибберлинов и Каменную стену. У вас пять эфира сейчас, один канал, три здоровья и действует Подзарядка. Шайку нельзя блокировать, но она сама не поднимается. Рука врага пуста. Его Огненный Шар за один эфир наносит два урона любой цели; сейчас эфира нет, каждый ход пополняется один.

**Hints:**

1. The Gang must survive direct damage, pay for your survival and attack again. A larger first hit cannot replace all three jobs.
2. Air Link returns life only when the Gang hits the enemy hero. Shell Skin keeps the Gang alive against Fireball. Your single channel can then fund Energize each later turn.
3. Put Air Link and Shell Skin on the Gang and attack. Block the Fire Elemental with the Wall, letting the Treant through. On each following turn spend your one ether to ready the Gang, then attack again.

**Подсказки:**

1. Шайка должна пережить прямой урон, оплатить ваше выживание и снова атаковать. Одного усиленного первого удара для всех трёх задач недостаточно.
2. Воздушная Связь возвращает здоровье только при попадании Шайки по вражескому герою. Ледяной Панцирь спасает её от Огненного Шара. Единственный канал затем оплачивает Подзарядку каждый следующий ход.
3. Дайте Шайке Воздушную Связь и Ледяной Панцирь, затем атакуйте. Стеной блокируйте Элементаля огня, пропуская древня. На каждом следующем ходу тратьте единственный эфир на пробуждение Шайки и атакуйте снова.

**Why it works:** Air Link costs two and Shell Skin costs three, using the opening five ether. The Gang becomes 4/5, so Fireball cannot kill it. Its first two hits restore four health each. Even when the enemy combines a two-point Fireball at your hero with the Treant’s three-point attack, blocking the six-power Elemental leaves you alive at two health after the first wave and one after the second. Your one channel pays Energize on each later turn, overcoming the Gang’s inability to rise. The third four-point attack defeats the remaining three enemy health. The enemy may choose other Fireball targets or omit attackers; the same defensive plan covers those replies. Strength leaves too little ether to buy both Air Link and Shell Skin, while armour on the Wall leaves the Gang vulnerable.

**Почему это работает:** Воздушная Связь стоит два, Ледяной Панцирь — три: начальные пять эфира израсходованы. Шайка становится 4/5, и Огненный Шар её не убивает. Первые два попадания возвращают по четыре здоровья. Даже если враг сочетает два урона Огненного Шара по герою с тремя от древня, блок Элементаля с силой шесть оставляет вас в живых: два здоровья после первой волны и одно после второй. Единственный канал оплачивает Подзарядку на следующих ходах, позволяя Шайке подниматься. Третья атака силой четыре снимает оставшиеся три здоровья врага. Другие цели Огненного Шара или отказ от части атак также покрываются этим планом защиты. После Усиления не хватает эфира одновременно на Воздушную Связь и Ледяной Панцирь; Панцирь на Стене оставляет Шайку уязвимой.

**Exact commands:**

```json
[
  {
    "card": "AILK",
    "kind": "cast",
    "target": 2.0
  },
  {
    "card": "SHSK",
    "kind": "cast",
    "target": 2.0
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
    "id": 1.0,
    "key": "fireball:2",
    "kind": "ability",
    "side": 1.0,
    "target": 0.0
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
    "id": 3.0,
    "kind": "block",
    "target": 4.0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 0.0,
    "key": "energize:1",
    "kind": "ability",
    "target": 2.0
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
    "id": 1.0,
    "key": "fireball:2",
    "kind": "ability",
    "side": 1.0,
    "target": 0.0
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
    "id": 3.0,
    "kind": "block",
    "target": 4.0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 0.0,
    "key": "energize:1",
    "kind": "ability",
    "target": 2.0
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

- Buy Strength before completing both protections: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Put the armor on the Wall: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.



### Above the Flood / Над потопом

`el1_tactical_v2_crossroads_above_flood` · Hard · win · 2 own turn(s)

**Briefing:** Win within two turns and preserve your Bat and Wall of Wind. You have seven ether, no channels and one health. Your Bat is resting; Energize and Fury are active. Fury forces the enemy’s ready creatures to attack. The Fire Elemental is Restless, the Giant Bat flies, and the Kobold Shaman can shoot for one damage. The enemy has no hand cards.

**Обстановка:** Победите за два хода и сохраните свою Летучую мышь и Стену ветра. У вас семь эфира, нет каналов и одно здоровье. Мышь отдыхает; действуют Подзарядка и Бешенство. Бешенство заставляет готовых врагов атаковать. Элементаль огня не отдыхает после атаки, Гигантская летучая мышь летает, Кобольд-шаман может выстрелить на один урон. Рука врага пуста.

**Hints:**

1. You need a lasting hold on the ground threats and a safe answer to the flyer. Merely resting creatures will not stop their next recovery.
2. Ice Storm can rest the Restless Elemental; Glitterdust cannot. Flood then holds ground creatures down, while both Bats can recover. Fury will make the enemy flyer leave its defensive post.
3. Cast Ice Storm and Flood, then Energize your Bat with the last ether. Attack for three. When the Giant Bat is forced to attack, block it with the Wall of Wind. Your Bat rises next turn; the enemy flyer is still resting, so attack for the last three.

**Подсказки:**

1. Нужно надолго удержать наземные угрозы и безопасно ответить летуну. Простое усыпление не помешает существам подняться на следующем ходу.
2. Снежная Буря усыпляет неутомимого Элементаля, Слепящая Пыль — нет. Затем Наводнение удерживает наземных существ, а обе Мыши могут подниматься. Бешенство заставит вражеского летуна покинуть защиту.
3. Произнесите Снежную Бурю и Наводнение, затем последним эфиром поднимите свою Мышь Подзарядкой. Атакуйте на три. Вынужденную атаку Гигантской мыши блокируйте Стеной ветра. На следующем ходу ваша Мышь поднимется, а вражеская ещё отдыхает: нанесите последние три.

**Why it works:** Ice Storm spends four and rests the non-Walls, including the Restless Elemental. Flood costs two and prevents the grounded Elemental and Shaman from rising on their turn. The last ether readies your own Bat for three damage through the rested defenders. The Giant Bat can recover because it flies, but Fury immediately commits it to attack. The nine-toughness Wall of Wind safely absorbs its five damage. After that attack the Giant Bat rests, while your own flying Bat rises for the second three-point hit. Glitterdust leaves the Restless Elemental ready alongside the flyer, overwhelming one blocker. Condensed Air holds the flyers instead and allows the ground threats to recover.

**Почему это работает:** Снежная Буря за четыре эфира усыпляет всех, кроме стен, включая неутомимого Элементаля. Наводнение за два не даёт наземным Элементалю и Шаману подняться в их ход. Последний эфир поднимает вашу Мышь для трёх урона мимо отдыхающих защитников. Гигантская мышь поднимается, потому что летает, но Бешенство сразу отправляет её в атаку. Стена ветра с девятью стойкости выдерживает её пять урона. После атаки Гигантская мышь отдыхает, а ваша летучая Мышь поднимается для второго удара на три. Слепящая Пыль оставляет неутомимого Элементаля готовым вместе с летуном, и один блокирующий не справляется. Густой Воздух удерживает летунов вместо наземных врагов и позволяет угрозам на земле подняться.

**Exact commands:**

```json
[
  {
    "card": "ICST",
    "kind": "cast",
    "target": -1.0
  },
  {
    "card": "FLOD",
    "kind": "cast",
    "target": -1.0
  },
  {
    "id": 0.0,
    "key": "energize:1",
    "kind": "ability",
    "target": 2.0
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
    "kind": "end_phase",
    "side": 1.0
  },
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

- Save ether by using Glitterdust instead of Ice Storm: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Hold flyers with Condensed Air: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.



### The Anchor You Own / Ваш собственный якорь

`el1_tactical_v2_crossroads_anchor_you_own` · Hard · win · 3 own turn(s)

**Briefing:** Win within three turns and preserve both of your creatures. All Abominations are resting; your Hopper is ready. The two enemy Steel Abominations have Ether Defense. The enemy has no hand cards, but has active Dissolution, one ether and one channel, so it can sacrifice its own Bronze Abomination. Earth Bonds prevents every creature of the enchanted creature’s race from rising, on both sides.

**Обстановка:** Победите за три хода и сохраните обоих своих существ. Все исчадия отдыхают, ваш Прыгун готов. Два вражеских Стальных исчадия защищены от прямого выбора целью. Рука врага пуста, но у него действует Рассеяние, есть один эфир и один канал: он может пожертвовать своим Бронзовым исчадием. Кровные Узы запрещают подниматься всем существам расы носителя по обе стороны поля.

**Hints:**

1. The protected Steel Abominations still share a race with creatures you can target. Choose the holder of the bonds, not only the race.
2. Putting Earth Bonds on the enemy’s weaker Abomination gives it an escape: Dissolution removes that holder and its enchantment. The same bonds on your own Abomination are outside the opponent’s sacrifice choices.
3. Cast Earth Bonds on your resting Bronze Abomination. Leave that anchor in place and attack with the Hopper on all three turns. The enemy may dissolve its own Bronze creature, but the two Steel creatures remain bound.

**Подсказки:**

1. Защищённые Стальные исчадия всё ещё одной расы с существами, которые можно выбрать целью. Выбирайте не только расу, но и носителя уз.
2. Кровные Узы на слабом вражеском исчадии дают противнику выход: Рассеяние уберёт носителя вместе с чарами. Те же узы на вашем исчадии недоступны вражеской жертве.
3. Наложите Кровные Узы на своё отдыхающее Бронзовое исчадие. Сохраните этот якорь и все три хода атакуйте Прыгуном. Враг может рассеять своё бронзовое существо, но оба стальных останутся связанными.

**Why it works:** Earth Bonds checks the holder’s race across both armies, so targeting your Bronze Abomination holds the enemy Steel Abominations despite their protection from direct targeting. Your own anchor stays resting, but the Hopper belongs to another race and rises normally. Three two-point attacks defeat six health. Dissolution can remove the enemy’s Bronze creature, but cannot sacrifice yours or remove its Earth Bonds. If the bonds instead sit on the enemy Bronze creature, the opponent can sacrifice it before a recovery and release both Steel creatures. Binding the Hopper chooses the wrong race and does nothing to contain the Abominations.

**Почему это работает:** Кровные Узы проверяют расу носителя по обе стороны поля, поэтому выбор вашего Бронзового исчадия удерживает вражеских Стальных, несмотря на их защиту от прямого выбора целью. Ваш якорь продолжает отдыхать, но Прыгун другой расы и поднимается как обычно. Три атаки по два снимают шесть здоровья. Рассеяние убирает вражеское бронзовое существо, но не может пожертвовать вашим и снять с него Кровные Узы. Если узы находятся на вражеском Бронзовом исчадии, противник может пожертвовать его перед восстановлением и освободить обоих Стальных. Узы на Прыгуне выбирают не ту расу и совсем не сдерживают исчадий.

**Exact commands:**

```json
[
  {
    "card": "ERBN",
    "kind": "cast",
    "target": 2.0
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
  },
  {
    "id": 1.0,
    "key": "sacrifice:1",
    "kind": "ability",
    "side": 1.0,
    "target": 6.0
  },
  {
    "kind": "end_phase",
    "side": 1.0
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
  },
  {
    "kind": "end_phase",
    "side": 1.0
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

- Put the race lock on the enemy Bronze Abomination: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Bind the Hopper instead of an Abomination: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.



## Etherlords II

### Evict the Parasite / Выселите паразита

`el2_tactical_v2_crossroads_dismiss_parasite` · Medium · win · 1 own turn(s)

**Briefing:** Win while preserving the Rock Wall. The Ogre King is already attacking for seven with trample. Both heroes have one health. Weak Toxin will remove the enemy's last health at the end of your coming turn; your Iron Mechozaurus drains four health from you at that same turn end.

**Обстановка:** Победите, сохранив Каменную стену. Вождь людоедов уже атакует на семь с пробивным ударом. У обоих героев по одной жизни. Слабый Токсин отнимет последнюю жизнь врага в конце вашего ближайшего хода; ваш Железный мехозавр в тот же конец хода отнимает у вас четыре жизни.

**Hints:**

1. Surviving the Ogre's attack is only the first problem. Decide which ally must still be alive when the toxin resolves.
2. The untargetable, unaffected Mechozaurus can still die in combat. Trample distributes damage through blockers in the order you assign them.
3. Assign the Iron Mechozaurus to block the Ogre first, then add the Rock Wall to the same attack. The Mechozaurus takes four and dies; the Wall absorbs the remaining three. Pass your turn and let Weak Toxin finish the enemy.

**Подсказки:**

1. Пережить удар людоеда — лишь первая задача. Решите, кто из союзников должен дожить до срабатывания токсина.
2. Мехозавр защищён от выбора целью и невосприимчив к магии, но может погибнуть в бою. Пробивной урон проходит по блокирующим в порядке их назначения.
3. Сначала назначьте Железного мехозавра блокировать людоеда, затем добавьте Каменную стену к той же атаке. Мехозавр получит четыре и погибнет; стена примет оставшиеся три. Пропустите свой ход, и Слабый Токсин добьёт врага.

**Why it works:** The first blocker receives four of the Ogre's seven damage and dies before retaliating. The ten-toughness wall safely takes the other three. With the parasite gone, your one-health hero survives the coming turn end, while Weak Toxin kills the enemy. Putting the Wall first spends all seven damage on it and leaves the Mechozaurus alive. Its four-point drain then kills you in the same turn-end sequence that the toxin kills the opponent; that mutual defeat is not a win.

**Почему это работает:** Первый блокирующий получает четыре из семи единиц урона людоеда и погибает до ответного удара. Стена со стойкостью десять благополучно принимает оставшиеся три. Без паразита ваш герой с одной жизнью переживает ближайший конец хода, а Слабый Токсин убивает врага. Если поставить стену первой, все семь урона уйдут в неё и мехозавр останется жив. Его потеря четырёх жизней убьёт вас в той же последовательности конца хода, в которой токсин убьёт противника; обоюдное поражение не считается победой.

**Exact commands:**

```json
[
  {
    "id": 2.0,
    "kind": "block",
    "target": 4.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 4.0
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase"
  }
]
```

**Tempting alternatives and observed evidence:**

- Put the Wall before the parasite: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### A Small Appetite / Маленький аппетит

`el2_tactical_v2_crossroads_small_appetite` · Medium · clear · 1 own turn(s)

**Briefing:** Clear the enemy army this turn and preserve your Bee Warrior. Both enemies can regenerate, but their hero has no ether. Ravaging Hunger makes creatures on both sides take damage equal to their own current power; the gases affect both armies too.

**Обстановка:** Уничтожьте армию врага за этот ход и сохраните Пчелу-воина. Оба врага могут регенерировать, но у их героя нет эфира. Опустошающий Голод наносит существам с обеих сторон урон, равный их текущей силе; газы также действуют на обе армии.

**Hints:**

1. Your smallest creature must lose its appetite completely. The enemy Treant still needs some appetite left.
2. Drowsy Gas removes one power, while Depressing Gas removes two. Frenzy Gas reduces toughness, but ordinary gas reduction never lowers toughness below one.
3. Cast Drowsy Gas and Frenzy Gas, then Ravaging Hunger. The Bee is 0/1, while the enemies are 1/1 and 4/2. The zero-power Bee takes no hunger damage.

**Подсказки:**

1. Ваше самое маленькое существо должно полностью потерять аппетит. Вражескому древню нужно оставить хоть немного.
2. Ослабляющий Газ убирает одну единицу силы, Подавляющий Газ — две. Веселящий Газ уменьшает стойкость, но обычное снижение от газа не опускает её ниже единицы.
3. Произнесите Ослабляющий Газ и Веселящий Газ, затем Опустошающий Голод. Пчела станет 0/1, враги — 1/1 и 4/2. Пчела с нулевой силой не получает урона голода.

**Why it works:** One point of power reduction protects the 1/1 Bee without reducing the 2/2 Treant to zero power. Frenzy Gas then leaves both small creatures at one toughness and the Mech Wyrm at two. Hunger kills both enemies and spares the Bee; neither enemy has ether for regeneration. Depressing Gas also makes the Treant's power zero, so Hunger never hurts it. Another valid order is Drowsy Gas, Hunger, then Frenzy Gas: Hunger leaves one wound on the Treant, and the final toughness reduction makes that wound lethal.

**Почему это работает:** Снижение силы на единицу защищает Пчелу 1/1, не обнуляя силу Древня 2/2. Веселящий Газ оставляет обоим малым существам по одной стойкости, а Червезавру — две. Голод убивает обоих врагов и щадит пчелу; эфира для регенерации у врага нет. Подавляющий Газ обнуляет и силу древня, поэтому Голод вовсе его не ранит. Допустим и другой порядок: Ослабляющий Газ, Голод, затем Веселящий Газ. Голод оставляет на древне одну рану, а последнее снижение стойкости делает её смертельной.

**Exact commands:**

```json
[
  {
    "card": "DRGS",
    "kind": "cast",
    "target": -1.0
  },
  {
    "card": "FRGS",
    "kind": "cast",
    "target": -1.0
  },
  {
    "card": "RVHG",
    "kind": "cast",
    "target": -1.0
  }
]
```

**Another winning line: Alternate order: Hunger before Frenzy Gas**

```json
[
  {
    "card": "DRGS",
    "kind": "cast",
    "target": -1.0
  },
  {
    "card": "RVHG",
    "kind": "cast",
    "target": -1.0
  },
  {
    "card": "FRGS",
    "kind": "cast",
    "target": -1.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Choose the stronger power-reducing gas: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Empty Pockets, Fast Feet / Пустые карманы, быстрые ноги

`el2_tactical_v2_crossroads_empty_pockets` · Medium · win · 1 own turn(s)

**Briefing:** Win this turn with four ether. The enemy has Hostile Ambience active and exactly three Polymorphs in hand; its one ether can pay for a defensive Polymorph. Your Mech Worm has Haste and is aggressive, but new creatures arrive resting while Hostile Ambience remains.

**Обстановка:** Победите за этот ход с четырьмя эфирами. У врага действует Враждебное Окружение, а в руке ровно три Превращения; его одного эфира хватит на Превращение в защите. У вашего Механического червяка есть спешка и агрессивность, но при Враждебном Окружении новые существа появляются отдыхающими.

**Hints:**

1. You must solve both the arrival problem and the enemy's defensive hand before ending the turn.
2. Removing Hostile Ambience does not wake a creature that already arrived resting. Sclerosis discards the excess of the enemy's hand over the cards you still hold after casting it.
3. Disenchant Hostile Ambience first, summon the Mech Worm second, then cast Sclerosis as your last card. It removes all three Polymorphs, and the Worm's compulsory attack deals the final point.

**Подсказки:**

1. До завершения хода нужно решить и проблему появления существа, и проблему защитных карт врага.
2. Снятие Враждебного Окружения не поднимает существо, уже появившееся отдыхающим. Склероз сбрасывает избыток вражеской руки над числом карт, оставшихся у вас после его произнесения.
3. Сначала снимите Враждебное Окружение, затем вызовите Механического червяка и последней картой произнесите Склероз. Он уберёт все три Превращения, а обязательная атака червяка нанесёт последнюю единицу урона.

**Why it works:** The costs are two for Lesser Disenchant, one for the Worm and one for Sclerosis. Removing Ambience before the summon lets the hasty Worm arrive ready and join the attack immediately. Casting Sclerosis last leaves your hand empty, so the difference is all three enemy cards. Casting it with one or two cards still in your hand leaves the enemy a Polymorph. Summoning first instead leaves the Worm resting even after Ambience is removed, missing this turn's attack.

**Почему это работает:** Снятие Чар стоит два, червяк — один и Склероз — один. Снятое до вызова Окружение позволяет существу со спешкой появиться готовым и сразу присоединиться к атаке. Склероз последней картой оставляет вашу руку пустой, поэтому разница составляет все три вражеские карты. Если у вас остаётся одна или две карты, противнику хватит оставшегося Превращения. Если же сначала вызвать червяка, он останется отдыхать даже после снятия Окружения и пропустит атаку этого хода.

**Exact commands:**

```json
[
  {
    "card": "CLNP",
    "grave": 1.0,
    "kind": "cast",
    "target": 1.0
  },
  {
    "card": "MCWO",
    "kind": "cast",
    "target": -1.0
  },
  {
    "card": "BANN",
    "kind": "cast",
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

- Summon before removing Hostile Ambience: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Use Sclerosis while still holding two cards: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Step Back, Spring Forward / Шаг назад — рывок вперёд

`el2_tactical_v2_crossroads_step_back` · Hard · clear · 2 own turn(s)

**Briefing:** Clear both enemy flyers within two turns and preserve your Orc Shaman. Both heroes have four channels; you have two ether now. The enemy's Depressing Gas is active and its hand is empty. In this edition, the Shaman supplies one extra ether at the start of your turn.

**Обстановка:** Уничтожьте обоих вражеских летунов за два хода и сохраните Орка-шамана. У обоих героев по четыре канала; сейчас у вас два эфира. У врага действует Подавляющий Газ, а рука пуста. В этой версии игры шаман даёт один дополнительный эфир в начале вашего хода.

**Hints:**

1. Two Hurricanes cost six ether. Your ordinary next-turn refill supplies only five.
2. Forces of Balance grants two channels only while you have fewer than the enemy. The Shaman's rite removes an enchantment by spending a channel, leaving your current ether untouched.
3. Use the Shaman's rite on Depressing Gas, then cast Forces of Balance. Survive the Pteros's possible three-point hit. Your next refill is five channels plus the Shaman's one ether: cast a Hurricane on each flyer.

**Подсказки:**

1. Два Урагана стоят шесть эфира. Обычное пополнение следующего хода даст лишь пять.
2. Равновесие даёт два канала, только когда у вас их меньше, чем у врага. Обряд шамана снимает чары ценой канала, не расходуя текущий эфир.
3. Обрядом шамана снимите Подавляющий Газ, затем примените Равновесие. Переживите возможный удар птероса на три. Следующее пополнение — пять каналов и один эфир шамана: направьте по Урагану в каждого летуна.

**Why it works:** The rite changes your channel count from four to three. Forces of Balance is now legal and raises it to five, using the two available ether. On your next turn the five channels and the Shaman supply exactly six, enough for both Hurricanes. Removing the gas restores the Pteros to three power, but your four health survive that attack. Lesser Disenchant removes the same gas without lowering your channels; the tie prevents Balance, and the resulting five-ether refill cannot pay for both removals.

**Почему это работает:** Обряд уменьшает число ваших каналов с четырёх до трёх. Равновесие становится доступным и поднимает их число до пяти, расходуя имеющиеся два эфира. На следующем ходу пять каналов и шаман дают ровно шесть — достаточно для двух Ураганов. После снятия газа сила птероса возвращается к трём, но четыре жизни позволяют пережить его атаку. Снятие Чар убирает тот же газ без потери канала; равенство каналов запрещает Равновесие, а пополнения в пять эфира не хватает для обоих уничтожений.

**Exact commands:**

```json
[
  {
    "choice": 1.0,
    "id": 2.0,
    "key": "orc_rite",
    "kind": "ability",
    "target": 1.0
  },
  {
    "card": "BLNC",
    "kind": "cast",
    "target": -1.0
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
    "kind": "end_phase"
  },
  {
    "card": "HRCN",
    "kind": "cast",
    "target": 3.0
  },
  {
    "card": "HRCN",
    "kind": "cast",
    "target": 4.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Dispel the gas without sacrificing a channel: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Let It Grow Teeth / Пусть отрастит клыки

`el2_tactical_v2_crossroads_grow_teeth` · Hard · win · 3 own turn(s)

**Briefing:** Win in three turns while preserving the Snake and Wall. The Grass Snake starts with Cloak of Fear. The enemy holds Lesser Disenchant: it has only one ether now, but two channels will fund the spell next turn. Rage grants your army four power and removes two toughness; that reduction can kill.

**Обстановка:** Победите за три хода, сохранив змею и стену. На Травяной змее уже есть Маска Ужаса. У врага в руке Снятие Чар: сейчас ему хватает лишь одного эфира, но два канала оплатят заклинание на следующем ходу. Ярость даёт вашей армии четыре силы и отнимает две стойкости; это снижение может убить.

**Hints:**

1. The Snake can earn the toughness needed to survive Rage. First make sure its attack route remains open.
2. Every hit on the enemy hero permanently gives the Grass Snake +1/+1. Cutting the enemy to one channel keeps Lesser Disenchant unaffordable on every reply.
3. Cast Inconsistent Reality before passing the first turn. Attack with the Snake for one, then for two on the next turn; block any Fire Elemental attacks with the Wall. On turn three the Snake is 3/3: Rage makes it 7/1, enough for the last seven damage.

**Подсказки:**

1. Змея может вырастить стойкость, нужную для выживания после Ярости. Сначала сохраните ей открытый путь для атак.
2. Каждый удар по вражескому герою навсегда даёт Травяной змее +1/+1. Уменьшение запаса врага до одного канала не позволит ему оплатить Снятие Чар ни на одном ответном ходу.
3. До завершения первого хода примените Искажение Реальности. Атакуйте змеёй на один, затем на два в следующем ходу; атаки Элементаля огня блокируйте стеной. На третьем ходу змея будет 3/3: Ярость сделает её 7/1 — ровно для последних семи урона.

**Why it works:** Inconsistent Reality removes one enemy channel before its refill, protecting the Cloak from the disclosed two-ether dispel. The first two unblocked Snake hits deal one and two, leaving the enemy at seven while growing the Snake to 3/3. Only then can it survive Rage's lethal two-toughness penalty and attack for seven. The Wall safely holds the Elemental between turns. Rage earlier kills the protected Snake; delaying the income cut lets the enemy remove the Cloak, after which its first-striking Elemental can stop the growth plan.

**Почему это работает:** Искажение Реальности убирает один вражеский канал до пополнения, защищая Маску от известного заклинания снятия за два эфира. Первые два беспрепятственных удара змеи наносят один и два урона, оставляя врагу семь жизней и выращивая змею до 3/3. Лишь теперь она переживёт смертельный штраф Ярости в две стойкости и атакует на семь. Между ходами стена благополучно удерживает элементаля. Ранняя Ярость убивает защищаемую змею; промедление с сокращением дохода позволяет врагу снять Маску, после чего элементаль с первым ударом остановит план роста.

**Exact commands:**

```json
[
  {
    "card": "INCR",
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
  },
  {
    "id": 4.0,
    "kind": "attack",
    "side": 1.0
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 3.0,
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
    "kind": "end_phase"
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
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 4.0
  },
  {
    "kind": "end_phase"
  },
  {
    "card": "IMML",
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

- Pass the first attack without cutting the dispel income: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Use Rage before the Snake has grown: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### One Last Reprieve / Последняя отсрочка

`el2_tactical_v2_crossroads_last_reprieve` · Hard · clear · 1 own turn(s)

**Briefing:** Clear the enemy army and preserve both Lake Snakes. The 2/2 Treant is already attacking, and its hero has one ether for regeneration. Your first Snake wears Stone Skin; the other has no protection. Lake Snake venom lowers the creature it hits by one power and one toughness.

**Обстановка:** Уничтожьте армию врага и сохраните обеих Озерных змей. Древень 2/2 уже атакует, и у его героя есть один эфир для регенерации. На вашей первой змее есть Каменная Кожа; вторая не защищена. Яд Озерной змеи снижает силу и стойкость поражённого существа на единицу.

**Hints:**

1. An ordinary lethal first strike lets the Treant regenerate and leave combat. Find a way to keep it present for a second bite.
2. Lake Snake venom lowers toughness before its strike deals damage. Lifeguard can cancel that first damage without cancelling the venom. Zero maximum toughness cannot be saved by regeneration.
3. Put Lifeguard on the enemy Treant. Block first with the armored Snake, then add the unarmored Snake to the same attack. The first venom leaves one toughness; the second lowers it to zero.

**Подсказки:**

1. Обычный смертельный первый удар позволяет древню регенерировать и выйти из боя. Найдите способ оставить его на месте для второго укуса.
2. Яд Озерной змеи уменьшает стойкость до нанесения урона её ударом. Телохранитель может поглотить первый урон, не отменяя яд. Нулевую максимальную стойкость регенерация не спасает.
3. Наложите Телохранителя на вражеского древня. Сначала назначьте блокировать змею с бронёй, затем добавьте незащищённую к той же атаке. Первый яд оставит одну стойкость, второй снизит её до нуля.

**Why it works:** The armored Snake first reduces the Treant from 2/2 to 1/1. The enemy's Lifeguard then cancels the three-point strike, so the Treant does not regenerate or withdraw. Its original two-point attack is absorbed by Stone Skin. The second Snake applies another venom, reducing maximum toughness to zero and killing the Treant despite its reserved ether. Shielding your own Snake instead allows the first hit to trigger regeneration and end the exchange early. Assigning the unarmored Snake first exposes it to the two-point return hit and loses a protected ally.

**Почему это работает:** Змея с бронёй сначала уменьшает характеристики древня с 2/2 до 1/1. Телохранитель врага поглощает удар на три, поэтому древень не регенерирует и не выходит из боя. Его исходные две единицы атаки поглощаются Каменной Кожей. Вторая змея накладывает ещё один яд, снижая максимальную стойкость до нуля и убивая древня вопреки запасённому эфиру. Защита собственной змеи вместо врага позволяет первому удару вызвать регенерацию и преждевременно завершить обмен. Если первой назначить незащищённую змею, она получит ответные две единицы урона и погибнет.

**Exact commands:**

```json
[
  {
    "card": "LFGR",
    "kind": "cast",
    "target": 4.0
  },
  {
    "id": 2.0,
    "kind": "block",
    "target": 4.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 4.0
  },
  {
    "kind": "end_phase"
  }
]
```

**Tempting alternatives and observed evidence:**

- Protect your first Snake instead of the enemy: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Let the unarmored Snake take the first block: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.
