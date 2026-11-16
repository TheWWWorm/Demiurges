# Curiosities solutions

**Spoilers below.** The in-game three-stage hints offer a gentler route. These are reference solutions, not the only permitted sequences. Enemy commands in a line show a concrete legal response.

## Etherlords I

### The Last Coin / Последняя монета

`el1_tactical_v2_curiosity_last_coin` · Easy · win · 1 own turn(s)

**Briefing:** Win this turn, starting with no ether. River Halo can steal two ether; Sea Halo can steal four. Broken Reality burns all ether remaining in its target's pool as damage.

**Обстановка:** Победите за этот ход, начав без эфира. Речной нимб крадёт два эфира, Морской — четыре. Разрушение Реальности сжигает весь оставшийся эфир выбранного героя, нанося столько же урона.

**Hints:**

1. You need enough ether to cast one spell, not the largest possible theft.
2. Every stolen ether also removes one point of damage from the enemy's Broken Reality.
3. Use River Halo to steal two, leaving the enemy seven. Cast Broken Reality on the enemy hero.

**Подсказки:**

1. Вам нужен эфир на одно заклинание, а не максимально большая кража.
2. Каждая украденная единица уменьшает урон Разрушения Реальности по врагу.
3. Речным нимбом украдите два эфира, оставив сопернику семь. Примените Разрушение Реальности к вражескому герою.

**Why it works:** The smaller siphon gives you two ether and leaves seven opposite. Broken Reality costs one and burns those remaining seven for lethal damage. Using Sea Halo first leaves only five damage in the enemy pool; the Wall prevents the remaining Halo from filling the gap with combat.

**Почему это работает:** Меньшая кража даёт вам два эфира и оставляет семь врагу. Разрушение Реальности стоит один и превращает в урон оставшиеся семь. Морской нимб оставляет врагу лишь пять эфира; стена не позволит оставшемуся нимбу восполнить нехватку уроном в бою.

**Exact commands:**

```json
[
  {
    "id": 2.0,
    "key": "siphon",
    "kind": "ability",
    "target": -1.0
  },
  {
    "card": "BRRL",
    "kind": "cast",
    "target": 1.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Take the larger four-ether siphon: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.



### Inferno Geometry / Геометрия пламени

`el1_tactical_v2_curiosity_inferno_geometry` · Medium · win · 1 own turn(s)

**Briefing:** Win this turn with six ether. Your Wall of Inferno Flames cannot attack, but Burnout is already active. Its toughness ability lets you choose how much ether to spend.

**Обстановка:** Победите за этот ход, имея шесть эфира. Стена адского пламени не атакует, но Сожжение уже действует. В её способности усиления стойкости можно выбрать расход эфира.

**Hints:**

1. The wall's ten toughness is more useful than its one power.
2. Delusion exchanges the two statistics. A temporary toughness increase becomes power after the exchange. Reserve three ether for Delusion and Burnout.
3. Spend three ether on the Wall's toughness ability, cast Delusion on it, then use Burnout to sacrifice the thirteen-power Wall into the enemy hero.

**Подсказки:**

1. Десять стойкости стены полезнее её единицы силы.
2. Перестановка меняет силу и стойкость местами. Временное усиление стойкости станет силой. Оставьте три эфира на Перестановку и Сожжение.
3. Потратьте три эфира на стойкость стены, примените к ней Перестановку и пожертвуйте стеной через Сожжение, выбрав целью вражеского героя.

**Why it works:** Three ether raises the Wall to 1/13. Delusion costs two and turns it into 13/1; Burnout costs the last ether and deals thirteen directly. Sharp Claws increases the wrong statistic before the exchange and consumes part of the required budget. The temporary ability may also be used after Delusion: the engine recomputes its toughness contribution before applying the inversion.

**Почему это работает:** Три эфира превращают стену в 1/13. Перестановка за два эфира делает её 13/1, а Сожжение за последний эфир наносит герою тринадцать урона. Острые Когти усиливают не тот показатель перед обменом и тратят необходимый запас. Способность стойкости допустимо использовать и после Перестановки: игра сначала пересчитывает её прибавку к стойкости, затем применяет обмен показателей.

**Exact commands:**

```json
[
  {
    "amount": 3.0,
    "id": 2.0,
    "key": "hellfire_health",
    "kind": "ability",
    "target": -1.0
  },
  {
    "card": "DELS",
    "kind": "cast",
    "target": 2.0
  },
  {
    "choice": 1.0,
    "id": 0.0,
    "key": "burnout:1",
    "kind": "ability",
    "target": 2.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Burn the wall before inverting its statistics: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Spend four ether on toughness and leave too little for the conversion: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.



### A Clean Copy / Чистая копия

`el1_tactical_v2_curiosity_clean_copy` · Medium · win · 1 own turn(s)

**Briefing:** Win this turn. Your Hopper is crippled by Weakness. The enemy's Lamia is much larger. Cloning gives you a fresh printed creature, not a copy of its attached enchantments.

**Обстановка:** Победите за этот ход. Ваш Прыгун ослаблен Слабостью. Вражеская ламия гораздо сильнее. Клон создаёт новое существо с печатными показателями, не копируя наложенные чары.

**Hints:**

1. The biggest creature is not necessarily useful before the deadline.
2. The Hopper has haste. A clone of it arrives without Weakness; the Lamia clone would still be sick.
3. Clone your Hopper, give the new Hopper Cloak of Fear, then attack with the new creature.

**Подсказки:**

1. Самое крупное существо не обязательно успеет помочь до срока.
2. У Прыгуна есть ускорение. Его копия появится без Слабости, а копия ламии ещё не сможет атаковать.
3. Клонируйте своего Прыгуна, дайте новому Прыгуну Маску Ужаса и атакуйте им.

**Why it works:** The cloned Hopper is a fresh 2/3 with haste, so it can act this turn. Cloak of Fear takes it past both blockers for the final two damage. A cloned Lamia is stronger but cannot attack before the deadline. Enhancing the original weakened Hopper spends the budget without restoring enough power.

**Почему это работает:** Клон Прыгуна — свежий 2/3 с ускорением: он действует в этот же ход. Маска Ужаса проводит его мимо обоих защитников, нанося последние два урона. Копия ламии сильнее, но не успевает атаковать. Усиление исходного ослабленного Прыгуна расходует бюджет, не возвращая достаточно силы.

**Exact commands:**

```json
[
  {
    "card": "CLON",
    "kind": "cast",
    "target": 2.0
  },
  {
    "card": "CLFR",
    "kind": "cast",
    "target": 5.0
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

- Clone the eight-power Lamia: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Improve the original crippled Hopper: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.



### A Universal Wake-Up Call / Побудка для всех

`el1_tactical_v2_curiosity_universal_wakeup` · Medium · win · 1 own turn(s)

**Briefing:** Win this turn. All three Warrior Spirits are resting. Your Shaman readies every Warrior Spirit on both sides, and the enemy can currently afford one regeneration.

**Обстановка:** Победите за этот ход. Все три Призрака-воина отдыхают. Ваш Призрак-шаман поднимает Призраков-воинов с обеих сторон, а враг пока может оплатить одну регенерацию.

**Hints:**

1. The rally wakes an enemy as well as your attackers.
2. Remove the enemy Spirit first, but drain its regeneration reserve before trying to kill it.
3. Siphon the enemy's two ether with River Halo. Cast Hunger on its Warrior Spirit, use the Shaman's wake-up ability, then attack with both friendly Warrior Spirits.

**Подсказки:**

1. Побудка поднимет и вражеского защитника.
2. Сначала уберите вражеского Призрака, но перед убийством заберите запас на его регенерацию.
3. Речным нимбом украдите два эфира. Примените Голод к вражескому Призраку, поднимите своих Призраком-шаманом и атакуйте обоими.

**Why it works:** River Halo removes the opponent's two-ether regeneration reserve while raising your pool to four. Hunger then kills its 3/2 Warrior Spirit. Shaman Spirit wakes your two 3/2 Warriors, which deal six through the now empty board. The siphon both funds Hunger and removes its target's regeneration reserve. Cloaking one Spirit cannot get all six required damage through the remaining blocker.

**Почему это работает:** Речной нимб забирает два эфира, нужные врагу для регенерации, и увеличивает ваш запас до четырёх. Голод убивает его Призрака 3/2. Призрак-шаман поднимает двух союзных Призраков-воинов 3/2, которые наносят шесть урона по пустому полю. Кража одновременно оплачивает Голод и убирает запас врага на регенерацию. Маска Ужаса только на одном Призраке не проводит все нужные шесть урона мимо оставшегося защитника.

**Exact commands:**

```json
[
  {
    "id": 5.0,
    "key": "siphon",
    "kind": "ability",
    "target": -1.0
  },
  {
    "card": "HUNG",
    "kind": "cast",
    "target": 6.0
  },
  {
    "id": 4.0,
    "key": "rouse",
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

- Wake everyone and cloak only one friendly Spirit: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Feed the River Halo to Hunger instead: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.



### The Pteros' Bargain / Выгодная сделка птероса

`el1_tactical_v2_curiosity_pteros_bargain` · Medium · clear · 1 own turn(s)

**Briefing:** Clear both wounded enemies this turn and preserve the Pteros. Each enemy survives only because of its toughness enchantment. You have three ether; the Pteros charges the enchantment's printed cost to dispel it.

**Обстановка:** Уничтожьте обоих раненых врагов за этот ход и сохраните Птероса. Каждый враг жив лишь благодаря чарам стойкости. У вас три эфира; Птерос берёт за рассеивание печатную стоимость чар.

**Hints:**

1. The larger defensive bonus may be cheaper to remove.
2. Shield of Force has a printed cost of one; the four ether originally spent on X is not part of the Pteros' price. Scale Skin costs two.
3. Use the Pteros to dispel Shield of Force from the Ogre King for one ether, then Lesser Disenchant to remove Scale Skin from the Lamia for two.

**Подсказки:**

1. Большую защитную прибавку иногда дешевле снять.
2. Печатная цена Щита Силы — один: четыре эфира, когда-то вложенные в X, в цену Птероса не входят. Ледяная Чешуя стоит два.
3. Птеросом за один эфир снимите Щит Силы с Вождя людоедов, затем Снятием Чар за два снимите Ледяную Чешую с Ламии.

**Why it works:** The Pteros removes the four-point Shield of Force for its printed one-ether cost. The King's existing eight wounds become lethal against its restored six toughness. The remaining two ether pays Lesser Disenchant; the Lamia's eight wounds become lethal when Scale Skin leaves. Spending the Pteros' action on the two-cost Scale Skin leaves only one ether and no affordable second dispel.

**Почему это работает:** Птерос снимает Щит Силы на четыре стойкости по его печатной цене — один эфир. Восемь ран Вождя становятся смертельными при исходной стойкости шесть. Два оставшихся эфира оплачивают Снятие Чар: восемь ран Ламии становятся смертельными без Ледяной Чешуи. Если потратить действие Птероса на Ледяную Чешую за два, останется лишь один эфир и не будет доступного второго рассеивания.

**Exact commands:**

```json
[
  {
    "choice": 1.0,
    "id": 2.0,
    "key": "dispel",
    "kind": "ability",
    "target": 3.0
  },
  {
    "card": "CLNP",
    "grave": 2.0,
    "kind": "cast",
    "target": 4.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Use the Pteros on the apparently smaller Scale Skin: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Buy Shell Skin for the Pteros: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.



### Poison Division / Распределение яда

`el1_tactical_v2_curiosity_poison_division` · Hard · clear · 1 own turn(s)

**Briefing:** Clear both committed attackers, preserving the Shadow Wolf and Magic Hornet. Your Bat already has Spirit of the Basilisk, and Battle Cry grants first strike. The armored Wolf has nine toughness. The Wolf and Hornet are resting. Two Energize abilities are available, with two ether total. The Mechozaurus is unaffected by poison.

**Обстановка:** Уничтожьте обоих уже атакующих врагов, сохранив Призрачного волка и Магического шершня. На Мыши уже есть Призрак Василиска, а Огненный Кулак даёт первый удар. Защищённый чарами Волк имеет девять стойкости. Волк и Шершень отдыхают. Доступны две Подзарядки и всего два эфира. Мехозавр невосприимчив к яду.

**Hints:**

1. Poison is not the answer to both attackers. Ordered first strikes can cover the immune one together.
2. Blockers fight sequentially. The armored Wolf can survive the Mechozaurus after its own four-point strike; then the Hornet supplies the last two. The poisoned Bat handles the Monk.
3. Use the two Energize abilities to ready the Wolf and Hornet. Block the Mechozaurus with the Wolf FIRST, then the Hornet. Block the Monk with the poisoned Bat.

**Подсказки:**

1. Яд не решает обе задачи. Правильный порядок первых ударов решает задачу невосприимчивого врага.
2. Защитники сражаются по очереди. Волк переживёт ответ Мехозавра после своих четырёх урона, затем Шершень добавит последние два. Ядовитая Мышь справится с Монахиней.
3. Двумя Подзарядками поднимите Волка и Шершня. СНАЧАЛА Волком, затем Шершнем блокируйте Мехозавра; ядовитой Мышью — Монахиню.

**Why it works:** Blockers fight in their assignment order. The Wolf strikes for four, then survives the Mechozaurus' eight damage with its nine toughness. The Hornet strikes next for the remaining two, killing the immune attacker. Reversing these blockers kills the protected Hornet. Battle Cry lets the poisoned Bat hit the Monk before dying to its return strike; poison resolves after combat and finishes the Monk. Both protected defenders survive and the enemy army clears. The nonregenerating, nontrampling Monk cannot spill damage onto your hero.

**Почему это работает:** Защитники сражаются в порядке назначения. Волк наносит четыре и выдерживает восемь урона Мехозавра благодаря девяти стойкости. Следом Шершень наносит последние два и убивает невосприимчивого врага. Обратный порядок губит защищаемого Шершня. Огненный Кулак позволяет ядовитой Мыши ударить Монахиню до собственной гибели от ответа; яд добивает Монахиню после боя. Оба защищаемых существа выживают, вражеская армия пуста. У Монахини нет натиска, поэтому лишний урон не проходит герою.

**Exact commands:**

```json
[
  {
    "id": 0.0,
    "key": "energize:1",
    "kind": "ability",
    "target": 2.0
  },
  {
    "id": 0.0,
    "key": "energize:2",
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

- Split the first strikers between the attackers: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Let the Hornet's poison handle the immune Mechozaurus alone: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### A Merciful Exchange / Милосердный обмен

`el1_tactical_v2_curiosity_merciful_exchange` · Hard · survive · 1 own turn(s)

**Briefing:** Survive the enemy turn with at least six health and keep your resting Wall of Blades. Fury will force the King and Bat to attack. Weird Exchange can name another friendly creature as its second target, and grants that creature's controller its toughness even if it regenerates.

**Обстановка:** Переживите ход врага, сохранив хотя бы шесть здоровья и отдыхающую Стену лезвий. Бешенство вынудит Вождя и Мышь атаковать. Второй целью Причудливого Обмена может быть союзник; его хозяин получает здоровье по стойкости, даже если существо регенерирует.

**Hints:**

1. Removing an enemy is not enough to reach the required health. Your own Wall offers a larger recovery.
2. Sacrifice the Rat and choose your Wall as the creature to destroy. Regeneration costs one ether and does not wake the already resting Wall; reserve another ether to ready it during defence.
3. Use Weird Exchange: Rat first, Wall second. After passing, Energize the Wall, block the Ogre King with it, and let the Bat deal five damage.

**Подсказки:**

1. Убийства врага недостаточно для нужного здоровья. Собственная стена даёт большее восстановление.
2. Пожертвуйте Крысой и выберите свою стену для уничтожения. Регенерация стоит один эфир и не поднимает уже отдыхающую стену; оставьте ещё один для её подъёма при защите.
3. Примените Причудливый Обмен: первой выберите Крысу, второй — стену. Передайте ход, поднимите стену Подзарядкой и блокируйте Вождя людоедов. Пропустите пять урона Мыши.

**Why it works:** Weird Exchange spends two ether, sacrifices the Rat and destroys the Wall. Its one-ether regeneration saves it without waking it, while the exchange still grants you nine health: two becomes eleven. The last ether readies the Wall during defence. Its six damage kills the six-toughness King, and its nine toughness survives the King's eight. The Bat deals five, leaving the required six health. Blocking the Bat instead lets eight trample damage through and misses the health target.

**Почему это работает:** Причудливый Обмен тратит два эфира, жертвует Крысой и уничтожает стену. Регенерация за один эфир спасает её, не поднимая, а обмен всё равно даёт девять здоровья: два превращается в одиннадцать. Последний эфир поднимает стену при защите. Её шесть силы убивают Вождя со стойкостью шесть, а девять стойкости выдерживают его восемь урона. Мышь наносит пять, оставляя нужные шесть здоровья. Блокирование Мыши пропускает восемь урона Вождя и не выполняет условие.

**Exact commands:**

```json
[
  {
    "card": "TRAD",
    "grave": 3.0,
    "kind": "cast",
    "target": 2.0
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "id": 0.0,
    "key": "energize:1",
    "kind": "ability",
    "target": 3.0
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

- Sacrifice the Wall instead of the Rat: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Spend the regeneration reserve on Fog before passing: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Two Mouths, One Meal / Два рта, одна порция

`el1_tactical_v2_curiosity_two_mouths` · Hard · clear · 1 own turn(s)

**Briefing:** Clear all three committed attackers, keeping both Cutters and at least three creatures. Your Battle Cry grants first strike. Both Cutters are resting and need a sacrifice to wake; the Rat carries your Water Link. The Hornet is your only flying defender; Shell Skin gives it six toughness.

**Обстановка:** Уничтожьте троих уже атакующих врагов, сохранив обоих Резчиков и хотя бы три существа. Огненный Кулак даёт первый удар. Оба Резчика отдыхают и требуют жертву для подъёма; на Крысе — ваша Водная Связь. Шершень — единственный летающий защитник; Ледяной Панцирь даёт ему шесть стойкости.

**Hints:**

1. One creature can supply two sacrifices if it returns between them.
2. Water Link brings the Rat back as a new creature. The returned Rat is sick, but it can still be sacrificed. Keep the Hornet for the flying lane.
3. Wake one Cutter by sacrificing the linked Rat, then wake the other with the returned Rat. Block the Steel Mechos and Lamia with the Cutters, and the Bat with the Hornet.

**Подсказки:**

1. Существо даст две жертвы, если вернётся между ними.
2. Водная Связь возвращает Крысу новым существом. Она пока не может действовать, но её можно пожертвовать. Шершня сохраните для воздушного направления.
3. Поднимите одного Резчика, пожертвовав связанной Крысой; второму отдайте вернувшуюся Крысу. Резчиками блокируйте Мехоса и Ламию, а Шершнем — Мышь.

**Why it works:** The first Cutter sacrifices the Rat and wakes. Water Link heals you and creates a new Rat, which supplies the second Cutter's sacrifice. Battle Cry lets both Cutters kill their ground attackers before retaliation, and the Hornet's first strike poisons the Bat. Its six toughness survives the Bat's five damage, then poison kills the Bat after combat. Both Cutters and the Hornet survive. Sacrificing the Hornet instead leaves no flying blocker, while sacrificing either Cutter violates the preservation objective. Either Cutter can take the first Rat, and either can defeat either ground attacker.

**Почему это работает:** Первый Резчик жертвует Крысой и встаёт. Водная Связь лечит вас и создаёт новую Крысу, которая служит жертвой второму Резчику. Огненный Кулак позволяет обоим убить наземных врагов до ответных ударов, а первый удар Шершня отравляет Мышь. Его шесть стойкости выдерживают пять урона ответа; затем яд убивает Мышь после боя. Все трое защитников выживают. Жертва Шершнем лишает воздушного защитника, а жертва Резчиком нарушает условие сохранения. Первую Крысу может получить любой Резчик; каждый из них справится с любым из двух наземных противников.

**Exact commands:**

```json
[
  {
    "id": 2.0,
    "key": "sacrifice",
    "kind": "ability",
    "target": 4.0
  },
  {
    "id": 3.0,
    "key": "sacrifice",
    "kind": "ability",
    "target": 9.0
  },
  {
    "id": 2.0,
    "kind": "block",
    "target": 6.0
  },
  {
    "id": 3.0,
    "kind": "block",
    "target": 7.0
  },
  {
    "id": 5.0,
    "kind": "block",
    "target": 8.0
  },
  {
    "kind": "end_phase"
  }
]
```

**Tempting alternatives and observed evidence:**

- Feed the flying Hornet to the first Cutter: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Feed one Cutter to the other: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Keep the Quarry Alive / Сохраните добычу живой

`el1_tactical_v2_curiosity_keep_quarry_alive` · Expert · control · 2 own turn(s)

**Briefing:** Capture this exact Big Velos and Female Fighter within two turns, keeping both alive and preserving Rock Wall. The Velos has Scale Skin and four toughness, but destroys itself at its controller's turn end unless it took damage that turn. Fury forces enemy attacks. You have nine ether now and five channels.

**Обстановка:** За два хода захватите именно этих Большого колесника и Серого некроманта, сохранив их в живых и не потеряв Каменную стену. Ледяная Чешуя даёт колеснику четыре стойкости, но он уничтожает себя в конце хода хозяина, если за ход не получил урона. Бешенство заставляет врагов атаковать. Сейчас у вас девять эфира и пять каналов.

**Hints:**

1. Your future captive must survive an enemy turn before you can afford the second capture. An untouched Velos destroys itself; excessive damage also loses it.
2. Capture the Fighter first and lower both its power and toughness. It must wound the Velos with first strike, then regenerate through the return hit. Keep exactly two ether for regeneration.
3. Capture the Female Fighter, put Weakness on it, and pass. Block the Velos with your 2/2 Fighter and Iron Mechos with Rock Wall. On your next turn, capture the living Velos.

**Подсказки:**

1. Будущий пленник должен пережить вражеский ход до того, как вы оплатите второй захват. Невредимый колесник уничтожает себя; слишком большой урон тоже губит его.
2. Сначала подчините Некроманта и уменьшите его силу и стойкость. Первый удар должен ранить колесника, затем регенерация спасёт Некроманта от ответа. Оставьте на неё ровно два эфира.
3. Подчините Некроманта, примените к ней Слабость и передайте ход. Некромантом 2/2 блокируйте колесника, Каменной стеной — Железного мехоса. На следующем ходу подчините живого колесника.

**Why it works:** Change of Command costs five and Weakness costs two, leaving the Fighter's two-ether regeneration reserve. Weakness changes the 6/6 Fighter into 2/2. Its first strike wounds the four-toughness Velos without killing it; the Velos' four damage then causes regeneration, preserving the same Fighter instance. The Velos has taken damage and survives its fatal upkeep. Rock Wall absorbs the Iron Mechos' six damage. Your next five-channel refill pays for the second capture. An unweakened Fighter kills the required Velos. A zero-power Wall leaves it unhurt, while capturing the Velos first leaves no safe defence against the Fighter and Mechos with the tools provided.

**Почему это работает:** Переподчинение стоит пять, Слабость — два, оставляя два эфира для регенерации Некроманта. Слабость превращает 6/6 в 2/2. Первый удар ранит колесника со стойкостью четыре, не убивая его; затем четыре урона ответа вызывают регенерацию и сохраняют тот же экземпляр Некроманта. Колесник получил урон и переживает свою проверку в конце хода. Каменная стена поглощает шесть урона Железного мехоса. Пополнение пяти каналов оплачивает второй захват. Неослабленный Некромант убивает нужного колесника. Стена с нулевой силой оставляет его невредимым; захват колесника первым не даёт безопасно защититься от Некроманта и Мехоса имеющимися средствами.

**Exact commands:**

```json
[
  {
    "card": "CHCM",
    "kind": "cast",
    "target": 4.0
  },
  {
    "card": "WEAK",
    "kind": "cast",
    "target": 4.0
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
    "kind": "block",
    "target": 3.0
  },
  {
    "id": 2.0,
    "kind": "block",
    "target": 5.0
  },
  {
    "kind": "end_phase"
  },
  {
    "card": "CHCM",
    "kind": "cast",
    "target": 3.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Weaken the Velos instead of preparing its future guard: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Capture the fragile Velos first: The legal prefix remains live in replay; bounded lab search refutes its continuations within this puzzle's deadline.

- Use the Fighter at full power against the required Velos: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Use the zero-power Wall to leave the Velos completely unhurt: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### The Adoption Papers / Документы на усыновление

`el1_tactical_v2_curiosity_adoption_papers` · Expert · control · 2 own turn(s)

**Briefing:** Capture the exact Cutter within two turns, after at least one enemy turn; keep both starting allies and finish with at least three health. Madness on the Cutter deals two to its controller at that controller's turn end. You have seven ether now, five channels, and expert Regeneration. The enemy has an unblocked flying threat and a Shaman forced into the same attack by Fury.

**Обстановка:** За два хода захватите именно этого Раскройщика после хотя бы одного хода врага; сохраните обоих исходных союзников и закончите хотя бы с тремя здоровья. Безумие на Раскройщике наносит его хозяину два урона в конце его хода. Сейчас у вас семь эфира, пять каналов и высшая Регенерация. У врага есть летун, которого нечем блокировать, и Шаман.

**Hints:**

1. Capturing an afflicted creature also transfers responsibility for its end-of-turn damage. Your two health cannot pay that debt.
2. Dispel Madness now, but do not buy control yet. The flying attack still requires two ether for Fog; five channels will finance the capture after the enemy turn.
3. Remove Madness from the enemy Cutter with Lesser Disenchant, then pass. Use Fog during defence. After your next regeneration and refill, use Change of Command on that same Cutter.

**Подсказки:**

1. Вместе с больным существом вы получаете ответственность за его урон в конце хода. Два здоровья не покрывают этот долг.
2. Снимите Безумие сейчас, но не покупайте контроль. Для летуна ещё нужны два эфира на Туман; пять каналов оплатят захват после хода врага.
3. Снятием Чар уберите Безумие с вражеского Раскройщика и передайте ход. При защите используйте Туман. После регенерации и пополнения эфира подчините того же Раскройщика.

**Why it works:** Lesser Disenchant costs two and removes the future liability while the Cutter is still hostile. Holding five ether allows Fog to stop the otherwise lethal Bat; Fury also commits the zero-power Shaman to combat, so it cannot use its shot. Expert Regeneration raises your health from two to three at your next turn start. Five channels then pay for Change of Command, completing the capture with both original allies intact and at least three health. Capturing first without dispelling makes Madness kill you at your own turn end. Paying for capture plus dispel spends all seven, leaving no Fog against the Bat. Wait until defence to cast Fog: an early Fog prevents Fury from committing the Shaman, allowing its shot to spoil the three-health requirement.

**Почему это работает:** Снятие Чар за два эфира убирает будущую угрозу, пока Раскройщик ещё враждебен. Оставшиеся пять позволяют оплатить Туман против смертельной Мыши. Бешенство вынуждает Шамана с нулевой силой атаковать, поэтому выстрелить он не может. Высшая Регенерация поднимает здоровье с двух до трёх в начале следующего хода. Пять каналов оплачивают Переподчинение; оба исходных союзника целы, здоровья хотя бы три. Немедленный захват без лечения убивает вас Безумием в конце хода. Захват вместе с лечением расходует все семь, не оставляя Тумана. Дождитесь фазы защиты для Тумана: ранний Туман не даст Бешенству включить Шамана в атаку, позволяя выстрелом сорвать требование трёх здоровья.

**Exact commands:**

```json
[
  {
    "card": "CLNP",
    "grave": 2.0,
    "kind": "cast",
    "target": 4.0
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
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
    "card": "CHCM",
    "kind": "cast",
    "target": 4.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Cast Fog early and release the Shaman from its compulsory attack: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Recruit immediately without removing Madness: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.

- Pay for both the cure and recruitment before budgeting for defence: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



## Etherlords II

### Copy Through Glass / Копия сквозь стекло

`el2_tactical_v2_curiosity_glass` · Medium · win · 1 own turn(s)

**Briefing:** Win this turn and preserve your Spellweaver. Your Suffocating Gas will deal two damage to both heroes at turn end. Both Pale creatures are in the Colourless Plane; the enemy carries Energy Barrier and Stone Skin.

**Обстановка:** Победите за этот ход и сохраните Ткача. Ваш Удушающий Газ нанесёт обоим героям два урона в конце хода. Оба бесцветных существа находятся в Бесцветном Плане; на враге есть Энергетический Барьер и Каменная Кожа.

**Hints:**

1. The gas is already a winning attack. The missing half is surviving it.
2. Weaving copies rather than dispels: it can reach a holder in the Colourless Plane.
3. Copy the enemy's Energy Barrier for three ether, cast the copy on your own hero for two, then end the turn. Stay in the Plane.

**Подсказки:**

1. Газ уже обеспечивает победный урон. Нужно лишь пережить его самому.
2. Плетение чар копирует, а не снимает чары: носитель в Бесцветном Плане ему доступен.
3. За три эфира скопируйте Энергетический Барьер врага, за два наложите его на своего героя и завершите ход. Оставайтесь в Бесцветном Плане.

**Why it works:** Weave costs one plus the enchantment's printed two: three ether. The copied Barrier costs the remaining two and stops the gas's magical damage to your hero. The Pale Spellweaver remains protected by its aspect. Stone Skin stops physical damage only; removing the gas avoids defeat but also removes the only winning attack.

**Почему это работает:** Плетение чар стоит один эфир плюс печатная цена чар — итого три. За оставшиеся два Барьер защищает вашего героя от магического урона газа. Ткач остаётся защищён своим планом. Каменная Кожа уменьшает только физический урон; снятие газа спасает героя, но убирает единственный способ победить.

**Exact commands:**

```json
[
  {
    "choice": 2.0,
    "id": 2.0,
    "key": "weave",
    "kind": "ability",
    "target": 3.0
  },
  {
    "card": "ENBR",
    "kind": "cast",
    "target": 0.0
  },
  {
    "kind": "end_phase"
  }
]
```

**Tempting alternatives and observed evidence:**

- Armor the hero against the gas: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Throw Away the Shield / Отбросьте щит

`el2_tactical_v2_curiosity_bare_echo` · Medium · win · 1 own turn(s)

**Briefing:** Win this turn. Your hero has Energy Barrier and Ethereal Resonance: every damage instance that reaches you also hits the enemy for twice that amount. Four health, five ether and three Zaps are all you have.

**Обстановка:** Победите за этот ход. На вашем герое есть Энергетический Барьер и Эфирный Резонанс: каждый полученный вами урон отражается во врага в двойном размере. У вас четыре жизни, пять эфира и три Электрошока.

**Hints:**

1. Three ordinary Zaps cannot remove six enemy health.
2. Your own protection prevents Resonance from seeing any damage. Remove the protection, not the mirror.
3. Disenchant your Energy Barrier, then cast all three Zaps on your own hero. You survive on one health while Resonance deals six.

**Подсказки:**

1. Три обычных Электрошока не отнимут у врага шесть жизней.
2. Ваша защита не пропускает урон, который нужен Резонансу. Снимите защиту, а не отражение.
3. Снятием Чар снимите свой Энергетический Барьер и направьте все три Электрошока в своего героя. Вы останетесь с одной жизнью, а Резонанс нанесёт шесть урона.

**Why it works:** Lesser Disenchant costs two and each Zap one. Removing Energy Barrier allows three one-point self-hits; Resonance doubles each into two enemy damage. Your health moves 4→3→2→1 and the enemy's 6→4→2→0. A Zap aimed directly at the enemy loses one point of the required total. Removing Resonance leaves no way to double the spells.

**Почему это работает:** Снятие Чар стоит два эфира, каждый Электрошок — один. Без Барьера три единичных саморанения превращаются Резонансом в три двойных удара. Ваши жизни меняются 4→3→2→1, вражеские — 6→4→2→0. Прямой Электрошок во врага теряет единицу нужного урона. Без Резонанса удвоить урон нечем.

**Exact commands:**

```json
[
  {
    "card": "CLNP",
    "grave": 1.0,
    "kind": "cast",
    "target": 0.0
  },
  {
    "card": "ZAPP",
    "kind": "cast",
    "target": 0.0
  },
  {
    "card": "ZAPP",
    "kind": "cast",
    "target": 0.0
  },
  {
    "card": "ZAPP",
    "kind": "cast",
    "target": 0.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Remove Resonance rather than the Barrier: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Two Appetites / Два аппетита

`el2_tactical_v2_curiosity_appetites` · Medium · clear · 1 own turn(s)

**Briefing:** Clear the enemy army this turn, preserve both devourers, and finish with at least sixteen health. The Scourge judges power and heals by remaining toughness; the Reaper judges toughness and heals by power.

**Обстановка:** Уничтожьте армию врага за этот ход, сохраните обоих пожирателей и завершите задачу хотя бы с шестнадцатью жизнями. Жнец сравнивает силу и лечит на оставшуюся стойкость жертвы; Разрушитель сравнивает стойкость и лечит на её силу.

**Hints:**

1. Each enemy is a meal for a different specialist. You also need all fifteen points of healing.
2. Weaken makes the Mechos edible, but it also removes four points from the Reaper's healing.
3. Dwindle the Steel Mechos. Let the Scourge eat the Giant Fingus and the Reaper eat the Mechos. Keep both devourers in the Plane.

**Подсказки:**

1. Каждому врагу соответствует свой пожиратель. Для цели нужны все пятнадцать единиц лечения.
2. Слабость делает Мехоса съедобным, но одновременно убирает четыре единицы лечения Разрушителя.
3. Примените Истощение к Стальному мехосу. Жнецом съешьте Хищного фингуса, Разрушителем — Мехоса. Обоих оставьте в Бесцветном Плане.

**Why it works:** The 2/7 Fingus has less power than the 3/4 Scourge and grants seven health. Dwindle makes the Mechos 8/2, below the Reaper's four toughness; eating it grants eight health. One plus seven plus eight is exactly sixteen. Weaken instead creates a 4/2 Mechos and grants only four health, so clearing the army alone is insufficient.

**Почему это работает:** У фингуса 2/7 меньше силы, чем у Жнеца 3/4; его пожирание возвращает семь жизней. Истощение делает Мехоса 8/2: его стойкость ниже четырёх у Разрушителя, а сила даёт восемь жизней. Один плюс семь плюс восемь — ровно шестнадцать. Ослабленный Мехос 4/2 даст лишь четыре жизни, поэтому одного уничтожения армии мало.

**Exact commands:**

```json
[
  {
    "card": "DWND",
    "kind": "cast",
    "target": 5.0
  },
  {
    "id": 2.0,
    "key": "pale_devour",
    "kind": "ability",
    "target": 4.0
  },
  {
    "id": 3.0,
    "key": "pale_devour",
    "kind": "ability",
    "target": 5.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Weaken the Mechos instead of reducing only its toughness: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Borrow the Door / Одолжите дверь

`el2_tactical_v2_curiosity_borrow_door` · Medium · clear · 1 own turn(s)

**Briefing:** Clear the enemy army this turn and preserve your Spitting Fingus. Transfer Aspects is already active. The enemy Spelleater is in the Colourless Plane; your Fingus and the enemy Rat are in the Ether.

**Обстановка:** Уничтожьте вражескую армию за этот ход и сохраните Плюющегося фингуса. Обмен Планами уже действует. Вражеский Чароед находится в Бесцветном Плане; ваш фингус и вражеская крыса — в Эфирном.

**Hints:**

1. The same transfer can expose the creature you must remove and shelter the one you must preserve.
2. Cleave cannot reach the Spelleater in the Plane. A global physical position change must come first.
3. Use Transfer Aspects: manifest the Spelleater and send your Fingus into the Plane. Cleave the Spelleater, then Lightning Storm the Rat.

**Подсказки:**

1. Один обмен может открыть для удара нужного врага и укрыть союзника, которого надо сохранить.
2. Бесцветный Молот не достаёт Чароеда в Бесцветном Плане. Сначала измените расположение существ.
3. Обменом Планами выведите Чароеда и отправьте своего фингуса в Бесцветный План. Примените Бесцветный Молот к Чароеду, затем Штормом Молний убейте крысу.

**Why it works:** Transfer costs one, Cleave three and Lightning Storm two. Cleave kills the manifested Pale creature without allowing dissipation. Lightning Storm then removes the one-toughness Rat, while the sheltered Fingus ignores ordinary damage. Casting Lightning Storm first kills the protected Fingus. Ripple reaches the Plane and would destroy that shelter's occupant.

**Почему это работает:** Обмен стоит один эфир, Бесцветный Молот — три, Шторм Молний — два. Бесцветный Молот уничтожает проявленного бесцветного врага, не давая ему рассеяться. Затем Шторм Молний убивает крысу со стойкостью один; укрытый фингус не получает обычный урон. Если начать с Шторма Молний, защищаемый фингус погибнет. Бесцветная Зыбь достаёт Бесцветный План и уничтожила бы его там.

**Exact commands:**

```json
[
  {
    "choice": 2.0,
    "id": 0.0,
    "key": "recycle:1",
    "kind": "ability",
    "target": 3.0
  },
  {
    "card": "OCLV",
    "kind": "cast",
    "target": 3.0
  },
  {
    "card": "LGST",
    "kind": "cast",
    "target": -1.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Start with Lightning Storm before providing shelter: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### The Enemy You Need / Нужный вам враг

`el2_tactical_v2_curiosity_needed_enemy` · Medium · win · 1 own turn(s)

**Briefing:** Win this turn. The enemy Mother forbids walls from blocking any Beholder, including yours. She is also the only enemy that can currently block your two flying eyes.

**Обстановка:** Победите за этот ход. Вражеская Матка злобоглазов запрещает стенам блокировать любых злобоглазов, в том числе ваших. При этом она сама — единственный враг, способный сейчас блокировать ваших двух летунов.

**Hints:**

1. Removing the largest threat would restore a useful defender to the enemy.
2. You need the Mother alive but unavailable to block. Your Mantis offers precisely that distinction.
3. Use the Mantis to rest the Mother. Attack with the Evil Eye Warrior and Evil Eye for five plus three. Leave the Mother in play.

**Подсказки:**

1. Уничтожение крупнейшей угрозы вернёт противнику полезного защитника.
2. Матка должна остаться живой, но не иметь возможности блокировать. Именно это умеет богомол.
3. Богомолом усыпите Матку. Атакуйте Злобоглазом-воином и Злобоглазом на пять плюс три. Сохраните Матку на поле.

**Why it works:** The Mantis spends one ether and rests the Mother. Her anti-wall aura remains global, so the Wall of Force cannot block either Beholder and eight damage ends the duel. Hurricane removes the aura along with the Mother, letting the wall absorb an attacker. A poison enchantment cannot make both Beholders connect through the still-ready Mother.

**Почему это работает:** Богомол тратит один эфир и отправляет Матку отдыхать. Её общая аура сохраняется: Стена Силы не может блокировать ни одного злобоглаза, и восемь урона завершают дуэль. Ураган уберёт вместе с Маткой её ауру, после чего стена задержит атакующего. Чары яда не помогут обоим злобоглазам пройти через готовую Матку.

**Exact commands:**

```json
[
  {
    "id": 2.0,
    "key": "tap_target",
    "kind": "ability",
    "target": 5.0
  },
  {
    "id": 3.0,
    "kind": "attack"
  },
  {
    "id": 4.0,
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

- Destroy the Mother with Hurricane: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Late Insurance / Страховка вовремя

`el2_tactical_v2_curiosity_late_insurance` · Medium · clear · 2 own turn(s)

**Briefing:** Clear the enemy army and keep your Gray Ogre alive. Your Gas triggers at the end of this turn, then Fury forces the Fire Elemental to attack. Lifeguard cancels one damage instance and can be cast during defence.

**Обстановка:** Уничтожьте армию врага и сохраните Серого людоеда. Ваш Газ сработает в конце этого хода, затем Бешенство заставит Элементаля огня атаковать. Телохранитель отменяет один случай урона; его можно применить во время защиты.

**Hints:**

1. The Ogre can survive the gas without help. It cannot survive the Elemental's first strike.
2. If you buy protection now, the smaller event consumes it before the dangerous one arrives.
3. End your turn without casting. Let the compelled enemy attack begin, then cast Lifeguard on the Ogre during defence and block the Elemental.

**Подсказки:**

1. Людоед переживёт газ без помощи. Первый удар Элементаля он не переживёт.
2. Если защитить его сейчас, слабое воздействие израсходует защиту до опасного удара.
3. Завершите ход без заклинаний. Дождитесь вынужденной атаки врага, затем во время защиты наложите Телохранителя на людоеда и блокируйте Элементаля.

**Why it works:** Passing allows both creatures to take the gas while the hero falls from three health to one. During defence, Lifeguard absorbs the Elemental's six-point first strike; the surviving Ogre then deals six and kills it. An early Lifeguard is consumed by two gas damage, leaving nothing to stop the first strike. The important move is waiting for the defensive spell window.

**Почему это работает:** После передачи хода оба существа получают урон газа, а у героя вместо трёх жизней остаётся одна. В защите Телохранитель поглощает первый удар Элементаля на шесть; выживший людоед отвечает шестью и убивает его. Ранний Телохранитель израсходуется на два урона газа. Главное решение — дождаться защитного окна заклинаний.

**Exact commands:**

```json
[
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
  {
    "card": "LFGR",
    "kind": "cast",
    "target": 2.0
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

- Protect the Ogre before ending your own turn: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Lend Them Wings / Одолжите им крылья

`el2_tactical_v2_curiosity_lend_wings` · Medium · clear · 1 own turn(s)

**Briefing:** Clear the enemy army this turn and preserve your Wizard Spirit and Blue Dragon. The enemy has no ether to regenerate. The Wizard's flight affects Warrior Spirits on both sides; Blue Dragon breath hits only enemy flyers.

**Обстановка:** Уничтожьте вражескую армию за этот ход, сохранив Призрака-колдуна и Синего дракона. У врага нет эфира для регенерации. Полёт от Колдуна действует на Призраков-воинов обеих сторон; дыхание Синего дракона бьёт только вражеских летунов.

**Hints:**

1. Your mass attack currently misses three ground creatures. Can two of them be made eligible together?
2. Giving flight to an enemy is a benefit only if it survives the next action.
3. Use the Wizard's spirit-flight ability first. Breathe with the Blue Dragon to kill both Warrior Spirits and the Hornet, then Lightning the Treant.

**Подсказки:**

1. Массовый удар пока не достаёт троих наземных врагов. Можно ли сразу двоих сделать подходящими целями?
2. Полёт полезен врагу лишь в том случае, если тот переживёт ваше следующее действие.
3. Сначала используйте полёт Призрака-колдуна. Дыханием Синего дракона уничтожьте обоих Призраков-воинов и шершня, затем Молнией — древня.

**Why it works:** The Wizard grants flight globally to Warrior Spirits. Dragon breath then deals three to both one-toughness Spirits and the two-toughness Hornet. Lightning's three damage handles the remaining Treant. The enemy's zero ether prevents every regeneration. Breathing first wastes the only repeatable-area opportunity this turn, and spending Lightning on a Spirit leaves the grounded Treant unanswered.

**Почему это работает:** Колдун даёт полёт всем Призракам-воинам. Дыхание дракона наносит три обоим призракам со стойкостью один и шершню со стойкостью два. Молния с тремя урона убирает оставшегося древня. Нулевой эфир врага исключает регенерацию. Раннее дыхание расходует единственный массовый удар хода; Молния в призрака оставляет без ответа наземного древня.

**Exact commands:**

```json
[
  {
    "id": 2.0,
    "key": "spirit_flight",
    "kind": "ability",
    "target": -1.0
  },
  {
    "id": 3.0,
    "key": "breath",
    "kind": "ability",
    "target": -1.0
  },
  {
    "card": "CLIG",
    "kind": "cast",
    "target": 6.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Breathe before granting the Spirits flight: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Block the Smallest / Блокируйте слабейшего

`el2_tactical_v2_curiosity_smallest_block` · Medium · win · 1 own turn(s)

**Briefing:** Win from this defence and preserve your Wall of Air. Ethereal Resonance on your hero doubles damage back onto the enemy. The Rat, Bat and Tick are already attacking for one, three and two. Blocking everything is neither possible nor desirable.

**Обстановка:** Победите из этой защиты и сохраните Стену воздуха. Эфирный Резонанс удваивает полученный героем урон во врага. Крыса, мышь и клещ уже атакуют на один, три и два. Остановить всё невозможно, да и не нужно.

**Hints:**

1. You need to receive five damage while surviving. The three attacks total six.
2. The wall can safely remove the smallest hit. Protecting the hero from a larger hit also removes the winning reflected damage.
3. Block only the one-power Rat with the Wall of Air, then resolve combat without casting. Let the Bat and Tick hit your hero for three plus two.

**Подсказки:**

1. Нужно получить пять урона и выжить. Сумма трёх атак — шесть.
2. Стена безопасно убирает самый слабый удар. Защита героя от сильного удара уберёт и победное отражение.
3. Стеной воздуха блокируйте только крысу с силой один и разрешите бой без заклинаний. Пусть мышь и клещ нанесут герою три плюс два.

**Why it works:** Removing the Rat's one-point hit leaves five incoming damage: the hero survives at one and reflects ten, enough to win. The wall survives its one damage. Blocking the Bat or Tick loses the protected wall; blocking nothing receives six and kills the hero. Lifeguard and Polymorph are tempting defensive tools, but their prevention removes the exact reflected damage needed to finish this turn.

**Почему это работает:** Убрав единичный удар крысы, вы пропускаете пять: герой остаётся с одной жизнью и отражает десять — достаточно для победы. Стена переживает свой единичный урон. Блок мыши или клеща губит защищаемую стену; отсутствие блоков даёт шесть и убивает героя. Телохранитель и Превращение выглядят полезными, но отменяют часть точного отражённого урона.

**Exact commands:**

```json
[
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

- Commit the wall to the largest attacker and resolve combat: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Catch the Shockwave / Сдержать ударную волну

`el2_tactical_v2_curiosity_shockwave` · Medium · clear · 1 own turn(s)

**Briefing:** Clear the attacking army and preserve your Spitting Fingus and Lamia Monk. A dying Walking Horror releases three damage to every other creature. You have exactly enough ether for one Lifeguard and one Polymorph.

**Обстановка:** Уничтожьте атакующую армию и сохраните Плюющегося фингуса и Ламию-монахиню. Гибель Ходячего ужаса наносит три урона каждому другому существу. Эфира хватает ровно на одного Телохранителя и одно Превращение.

**Hints:**

1. Removing the largest attacker also removes the smaller one, but the effect reaches your own army.
2. The Monk can withstand the wave. The two-toughness Fingus cannot, even though it is not fighting.
3. Cast Lifeguard on the Fingus first, then Polymorph the Walking Horror. Its death wave kills the Hopper while both allies survive.

**Подсказки:**

1. Устранение крупного атакующего уберёт и малого, но эффект заденет вашу армию.
2. Монахиня выдержит волну. Фингус со стойкостью два — нет, хотя он не участвует в бою.
3. Сначала наложите Телохранителя на фингуса, затем Превращение на Ходячий ужас. Его смертельная волна убьёт прыгуна, а оба союзника выживут.

**Why it works:** Lifeguard must be on the fragile bystander before the Horror dies. Polymorph kills the Horror, its three-point death wave kills the 2/3 Hopper, and the shield protects the 0/2 Fingus. The Monk survives three damage naturally. Polymorph then sets the hero's health to the Horror's power plus toughness, eighteen. Shielding the hero or the Monk instead loses the protected Fingus; removing the Hopper first leaves the Horror unanswered.

**Почему это работает:** Телохранитель должен прикрывать хрупкого свидетеля до смерти Ужаса. Превращение убивает Ужас, его волна на три уничтожает прыгуна 2/3, а щит спасает фингуса 0/2. Монахиня выдерживает три урона сама. Затем Превращение устанавливает здоровье героя равным силе плюс стойкости Ужаса — восемнадцати. Щит на герое или монахине не спасёт фингуса; раннее удаление прыгуна оставит Ужас без ответа.

**Exact commands:**

```json
[
  {
    "card": "LFGR",
    "kind": "cast",
    "target": 2.0
  },
  {
    "card": "PLMR",
    "kind": "cast",
    "target": 4.0
  }
]
```

**Tempting alternatives and observed evidence:**

- Remove the Horror before shielding the bystander: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Not a Scratch / Ни царапины

`el2_tactical_v2_curiosity_no_scratch` · Hard · clear · 2 own turn(s)

**Briefing:** Clear the enemy army while preserving both walls. Fury forces both poisonous, first-striking Hornets to attack next turn. Fatal Disease prevents regeneration. You have six ether; each Stone Skin reduces every physical hit by two.

**Обстановка:** Уничтожьте армию врага, сохранив обе стены. Бешенство заставит обоих ядовитых шершней с первым ударом атаковать на следующем ходу. Роковая Болезнь запрещает регенерацию. У вас шесть эфира; каждая Каменная Кожа уменьшает физический удар на два.

**Hints:**

1. A single point of Hornet damage is still lethal poison. The safe target is zero damage.
2. The two-power Hornet needs one armor layer; the three-power Hornet needs two. Hellfire can destroy a flying creature with one successful hit.
3. Put one Stone Skin on the Wall of Blades and two on the Wall of Inferno Flames. Pass, then block the Magic Hornet with Blades and the Mystic Hornet with Inferno.

**Подсказки:**

1. Даже одна царапина шершня несёт смертельный яд. Нужно полностью поглотить удар.
2. Шершню с силой два хватает одного слоя брони; с силой три нужны два. Адское пламя уничтожает летающего врага даже после одного успешного попадания.
3. Наложите одну Каменную Кожу на Стену лезвий и две на Стену адского пламени. Передайте ход; лезвиями блокируйте Магического шершня, пламенем — Мистического.

**Why it works:** Stone Skin reduces the Hornets' first strikes to zero before poison can be applied. Blades kills the 2/2 Hornet with six power; the Inferno wall's one-point hit destroys the other flyer through its special effect. Both walls survive. The reverse armor allocation also works if the blocks are reversed with it. Energy Barrier cannot stop physical strikes, and concentrating all armor on one wall leaves the other poisoned.

**Почему это работает:** Каменная Кожа снижает первые удары шершней до нуля до наложения яда. Лезвия с силой шесть убивают шершня 2/2; единичный удар адского пламени уничтожает второго летуна особым эффектом. Обе стены выживают. Можно поменять распределение брони вместе с назначением блоков. Энергетический Барьер не останавливает физические удары, а вся броня на одной стене оставит вторую без защиты от яда.

**Exact commands:**

```json
[
  {
    "card": "STSK",
    "kind": "cast",
    "target": 2.0
  },
  {
    "card": "STSK",
    "kind": "cast",
    "target": 3.0
  },
  {
    "card": "STSK",
    "kind": "cast",
    "target": 3.0
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1.0
  },
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
  }
]
```

**Tempting alternatives and observed evidence:**

- Use a magical barrier in place of physical armor: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### Bury It Tomorrow / Похороните завтра

`el2_tactical_v2_curiosity_bury_tomorrow` · Hard · survive · 2 own turn(s)

**Briefing:** Survive two enemy turns and preserve your Pale Knight. Only one card is in your graveyard. The enemy's Plague Rat can purge a graveyard during its turn. Your Giant Bat can stop a Rat attack. A Knight blocking the Walking Horror takes lethal damage and dissipates, so it needs another graveyard card to manifest again.

**Обстановка:** Переживите два вражеских хода и сохраните Бесцветного Рыцаря. В вашем могильнике всего одна карта. Чумная крыса может очищать могильники на своём ходу. Ваша Гигантская летучая мышь способна остановить атаку крысы. Рыцарь, блокирующий Ходячего ужаса, получает смертельный урон и рассеивается: для нового проявления ему нужна ещё одна карта могильника.

**Hints:**

1. There are enough creatures to pay for two manifestations, but an early burial gives the Rat a chance to erase the second payment.
2. The Bat must remain alive through the first enemy decision window. If the Rat attacks, the Giant Bat can block, survive and kill it. Keep that defender ready.
3. Manifest the Knight with the old grave card and keep the Bat. Block the Walking Horror with the Knight. On your next turn, sacrifice the Giant Bat with Cannibalism; manifest the Knight from that fresh grave card and block the Walking Horror again.

**Подсказки:**

1. Существ хватит на два проявления, но ранние похороны позволят крысе стереть вторую плату.
2. Мышь должна дожить до первого вражеского окна решений. Если крыса атакует, Гигантская летучая мышь может блокировать, выжить и убить её. Сохраните этого защитника готовым.
3. Проявите Рыцаря старой картой и оставьте мышь. Рыцарём блокируйте Ходячего ужаса. На следующем своём ходу принесите Гигантскую летучую мышь в жертву Каннибализмом и используйте свежую карту для нового проявления. Рыцарём снова блокируйте Ходячего ужаса.

**Why it works:** Each Walking Horror block sends one trample damage to the hero and dissipates the Knight instead of killing it. The first manifestation consumes the existing Rat card. Cannibalism must be delayed until after the opponent's first grave-purge window: it then creates the Bat card immediately before the second manifestation and heals four. If the Rat attacks on the first turn, the ready Giant Bat kills it and survives. On the second enemy turn the heal also leaves enough health to absorb a surviving Rat's three damage while the Knight stops the Walking Horror. An early sacrifice lets the Rat erase the only second manifestation card.

**Почему это работает:** Каждый блок Ходячего ужаса пропускает герою один урон и отправляет Рыцаря в Бесцветный План вместо смерти. Первое проявление съедает старую карту крысы. Каннибализм нужно отложить до завершения первого вражеского окна очистки: тогда карта мыши появится прямо перед вторым проявлением, а герой вылечит четыре жизни. Если крыса атакует на первом ходу, готовая Гигантская летучая мышь убьёт её и выживет. На втором вражеском ходу лечения хватит, чтобы принять три урона от оставшейся крысы, пока Рыцарь останавливает Ходячего ужаса. Ранняя жертва позволит крысе стереть единственную плату за второе проявление.

**Exact commands:**

```json
[
  {
    "choice": 0.0,
    "id": 2.0,
    "key": "sinister",
    "kind": "ability",
    "target": 0.0
  },
  {
    "kind": "end_phase"
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
    "id": 2.0,
    "kind": "block",
    "target": 4.0
  },
  {
    "kind": "end_phase"
  },
  {
    "card": "CNBL",
    "kind": "cast",
    "target": 3.0
  },
  {
    "choice": 0.0,
    "id": 2.0,
    "key": "sinister",
    "kind": "ability",
    "target": 0.0
  },
  {
    "kind": "end_phase"
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

- Sacrifice the Giant Bat before the Rat's first turn: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.



### A Cage Built in Advance / Клетка заранее

`el2_tactical_v2_curiosity_advance_cage` · Expert · control · 2 own turn(s)

**Briefing:** After two enemy turns, control the Blue Dragon and preserve your Wall of Force. You have four ether now and eight channels. Both enemy Pteroses can remove Change of Command for five ether. The first enemy attack can leave your hero on one health; the captured Dragon will still be resting after that attack.

**Обстановка:** После двух вражеских ходов владейте Синим драконом и сохраните Стену Силы. Сейчас у вас четыре эфира и восемь каналов. Каждый вражеский птерос способен за пять эфира снять Переподчинение. Первая атака может оставить герою одну жизнь; захваченный дракон всё ещё будет отдыхать после неё.

**Hints:**

1. The capture is affordable next turn. Its two answers must be disabled before then.
2. The first defence uses health as a resource; the second needs two ready flying blockers. Energizing before changing control helps the wrong army.
3. Irritate both Pteroses now. Let the wall block the Dragon and endure both small hits. Next turn capture the Dragon, then use Energize All after it is yours. Block one remaining Pteros with the wall and the other with the Dragon.

**Подсказки:**

1. Захват станет доступен на следующем ходу. Оба ответа на него нужно отключить заранее.
2. В первой защите придётся потратить жизни; во второй нужны два готовых летающих защитника. Пробуждение до смены владельца поможет не той армии.
3. Раздражите обоих птеросов сейчас. Стеной блокируйте дракона и примите два малых удара. На следующем ходу захватите дракона и лишь затем примените Общую Подзарядку. Каждого оставшегося птероса остановите отдельным летающим защитником.

**Why it works:** Two Irritations consume the first four ether and disable both dispellers. The wall absorbs the Dragon's eight while the two Pteroses deal four, leaving one hero health in the worst attack. The next refill is exactly five for Change of Command plus three for Energize All. Capturing does not wake the resting Dragon; energizing after the capture supplies the second flying blocker. Both dispellers remain disabled through the objective's second enemy turn. Spending the first reserve on extra wall toughness leaves a live dispeller able to release the Dragon.

**Почему это работает:** Два Раздражения расходуют первые четыре эфира и отключают обоих рассеивателей. Стена принимает восемь от дракона, птеросы наносят четыре: в худшем случае остаётся одна жизнь. Следующее пополнение — ровно пять на Переподчинение и три на Общую Подзарядку. Захват не будит отдыхающего дракона; пробуждение после захвата даёт второго летучего защитника. Оба рассеивателя должны оставаться отключёнными до конца второго вражеского хода. Раннее усиление стены оставит работающего птероса, который освободит дракона.

**Exact commands:**

```json
[
  {
    "card": "IRRT",
    "kind": "cast",
    "target": 4.0
  },
  {
    "card": "IRRT",
    "kind": "cast",
    "target": 5.0
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
    "id": 2.0,
    "kind": "block",
    "target": 3.0
  },
  {
    "kind": "end_phase"
  },
  {
    "card": "CHCM",
    "kind": "cast",
    "target": 3.0
  },
  {
    "card": "ENAL",
    "kind": "cast",
    "target": -1.0
  },
  {
    "kind": "end_phase"
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
  }
]
```

**Tempting alternatives and observed evidence:**

- Buy extra wall toughness instead of suppressing both dispellers: This complete legal alternative ends in failure; a shorter prefix may still be recoverable.
