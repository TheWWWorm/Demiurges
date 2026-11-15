# Tactical Studies — 57 solutions and teaching notes

**Spoilers for the complete collection, including Heroes and Creatures.** In the game, hints require deliberate requests; this guide reveals the combinations.

Each reference is a legal demonstration. Opponent actions illustrate one reply; separate adversarial checks examine other choices. Independent preparations and alternative legal winning plans are allowed.

Hero levels below are actual battle levels, separate from the difficulty label. Maximum health and skills are explicit snapshot values. The hero-name labels do not themselves grant abilities.

All studies suppress deck draws and natural channel growth. Existing channels refill normally, and real card effects can create or return cards and change ether. Completion requirements apply at success; continuous health floors and protected identities apply throughout.

## Etherlords I

### 1. Empty Battlements

**Easy · Win · Evasion and enemy counterplay**

**Matchup:** Kinet adept (Lv 4) / Kinet adept (Lv 4).

Win this turn. The Assassin can evade the dragon as a blocker, but the dragon's breath is still a threat.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 20 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 2 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. The wall is a legal blocker; the dragon threatens an ability during defence.
2. You need to remove one obstacle and rest the other, using only three ether.
3. Enfeeble the Blue Dragon, invert the zero-power Wall of Force with Delusion, then attack with the Assassin.

**Solution and reason**

Enfeeble the Blue Dragon so it cannot use its readying-dependent breath ability during defence. Cast Delusion on the Wall of Force: swapping its 0/12 stats leaves it at 12/0, so it dies. The Dragon is not a Wall and cannot block the Aviak Assassin. Its two damage is lethal. Tapping only the wall looks cheaper, but leaves the Dragon able to kill the Assassin with its breath. The two preparation spells may be cast in either order.

**Tempting alternatives checked**

- Spend the budget increasing the Assassin's damage
- Rest only the wall and leave the Dragon ready
- Clear the wall and attack without disabling the breath

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Пустые бойницы — Обход защиты и ответ противника**

Адепт кинетов (Lv 4) / Адепт кинетов (Lv 4)

Победите за этот ход. Дракон не может заблокировать авиака-убийцу, но его дыхание всё ещё опасно.

1. Стена может заблокировать авиака, а дракон — применить способность во время защиты.
2. Одну преграду нужно уничтожить, а другую отправить на отдых. На всё есть три единицы эфира.
3. Примените «Бессилие» к синему дракону, «Перестановку» к стене силы, затем атакуйте авиаком-убийцей.

«Бессилие» отправляет синего дракона на отдых и лишает его возможности применить дыхание. «Перестановка» меняет характеристики стены силы с 0/12 на 12/0, и она погибает. Дракон не является телохранителем и не может блокировать авиака-убийцу: две единицы урона решают бой. Если отправить на отдых только стену, дракон убьёт авиака дыханием. Два подготовительных заклинания можно применить в любом порядке.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_empty_battlements`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "ENFL",
    "kind": "cast",
    "target": 4
  },
  {
    "card": "DELS",
    "kind": "cast",
    "target": 3
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 2. Count the Ashes

**Easy · Win · Graveyard arithmetic**

**Matchup:** Chaot warrior (Lv 4) / Chaot warrior (Lv 4).

Win this turn and remain alive. Both graveyards contain two creatures.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `RedMaleWarrior2` | 4 | 3 / 20 | 4 | None |
| Opponent | `RedMaleWarrior2` | 4 | 4 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. A spell that burns both graveyards is dangerous at three health.
2. The Disease Rat can remove a card from either hero's graveyard.
3. Gnaw one creature from your own graveyard, then cast Burning Graves.

**Solution and reason**

Use the Disease Rat's Ghoul ability on your own graveyard for one ether. Burning Graves then deals two damage to you and four to the enemy. You survive on one health. Burning first is a draw; clearing the enemy's graveyard saves the wrong hero.

**Tempting alternatives checked**

- Burn before making the graveyards asymmetric
- Gnaw the enemy's graveyard

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Сосчитать пепел — Расчёт урона от могильников**

Воин хаотов (Lv 4) / Воин хаотов (Lv 4)

Победите за этот ход и останьтесь в живых. В обоих могильниках по два создания.

1. При трёх единицах здоровья заклинание, поражающее обоих героев, опасно и для вас.
2. Заразная крыса может удалить карту из могильника любого героя.
3. Удалите крысой одно создание из собственного могильника, затем примените «Пылающие могилы».

Потратьте одну единицу эфира на «Трупоеда» заразной крысы и удалите создание из своего могильника. «Пылающие могилы» нанесут вам два урона, а противнику — четыре. Вы останетесь с одной единицей здоровья. Если начать с заклинания, погибнут оба героя; если очистить вражеский могильник, вы спасёте не того героя.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_count_the_ashes`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "choice": 0,
    "id": 2,
    "key": "gnaw",
    "kind": "ability",
    "target": 0
  },
  {
    "card": "BRGR",
    "kind": "cast",
    "target": -1
  }
]
```

</details>

### 3. A Dangerous Promotion

**Easy · Clear · Target thresholds**

**Matchup:** Synthet adept (Lv 4) / Vital warrior (Lv 4).

Clear the enemy army this turn and keep the Huntress alive. Her shot only accepts creatures with at least four power.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlackMale1` | 4 | 20 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 20 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"protect": [2], "type": "clear"}`.

**Hint progression**

1. A harmful spell is not always the best way to remove an enemy.
2. One enemy is too weak for the Huntress to target. You can change that.
3. Enhance the enemy Tick, shoot it, ready the Huntress with Spirit of War, then shoot the Ogre.

**Solution and reason**

Twisted Enhancement raises the enemy Tick Warrior from two to four power, making it a legal Huntress target. Shoot it, use Spirit of War to ready the Huntress, and shoot the Gray Ogre. Shooting the Ogre first is also valid if you keep the readying spell and the Tick's enhancement. The puzzle tests the two-target plan, not an arbitrary order between independent preparations.

**Tempting alternatives checked**

- Use the only enhancement on your own Huntress

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Опасное усиление — Порог выбора цели**

Адепт синтетов (Lv 4) / Воин виталов (Lv 4)

Уничтожьте всю вражескую армию за этот ход и сохраните охотницу. Её выстрел поражает только создания с силой не меньше четырёх.

1. Чтобы избавиться от врага, не обязательно сначала его ослаблять.
2. Один противник слишком слаб для выстрела охотницы. Это можно исправить.
3. Усильте вражеского клеща, застрелите его, поднимите охотницу «Духом войны» и застрелите людоеда.

«Искажённое улучшение» повышает силу вражеского клеща-воина с двух до четырёх: теперь охотница может его застрелить. После выстрела поднимите её «Духом войны» и уничтожьте серого людоеда. Можно начать и с людоеда, если сохранить заклинания подъёма и усиления для второго выстрела. Важен план на обе цели, а не искусственно заданный порядок независимых приготовлений.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_dangerous_promotion`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "TWEN",
    "kind": "cast",
    "target": 3
  },
  {
    "id": 2,
    "key": "hunt",
    "kind": "ability",
    "target": 3
  },
  {
    "card": "SPWR",
    "kind": "cast",
    "target": 2
  },
  {
    "id": 2,
    "key": "hunt",
    "kind": "ability",
    "target": 4
  }
]
```

</details>

### 4. One Open Lane

**Medium · Survive · Defensive assignment**

**Matchup:** Synthet adept (Lv 4) / Chaot warrior (Lv 4).

Survive this enemy attack and preserve your Mech Worm. The two walls are resting; one attacker must get through.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlackMale1` | 4 | 3 / 20 | 4 | None |
| Opponent | `RedMaleWarrior2` | 4 | 20 / 20 | 4 | None |

Own-turn budget: **1**. Objective metadata: `{"enemy_turns": 1, "protect": [4], "type": "survive"}`.

**Hint progression**

1. Both evasive attackers require Walls, and one of them also flies.
2. Your ground Wall must take the Shadow Wolf. The flying Wall is needed elsewhere.
3. Cast Energize All, block the Wolf with Rock Wall and the Assassin with Wall of Force. Let the Tick hit your hero.

**Solution and reason**

Energize All readies both walls during defence. Rock Wall blocks Shadow Wolf, while Wall of Force blocks the flying Aviak Assassin. Leave the Tick Warrior unblocked: two damage leaves one health. Blocking the Tick with the protected Mech Worm would kill it, and spending ether on another spell loses the only way to ready both essential blockers.

**Tempting alternatives checked**

- Put the flying wall in the ground lane
- Save all hero damage by sacrificing the protected Worm

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Один открытый проход — Распределение блоков**

Адепт синтетов (Lv 4) / Воин хаотов (Lv 4)

Переживите эту атаку и сохраните механического червяка. Обе стены отдыхают; одного нападающего придётся пропустить.

1. Двум увертливым нападающим нужны блокирующие телохранители, причём один из нападающих летает.
2. Наземная стена должна принять призрачного волка. Летающая понадобится в другом месте.
3. Примените «Общую подзарядку». Заблокируйте волка каменной стеной, авиака — стеной силы, а клеща пропустите к герою.

«Общая подзарядка» поднимает обе стены во время защиты. Каменная стена блокирует призрачного волка, а стена силы — летающего авиака-убийцу. Клеща-воина пропустите: после двух урона у героя останется одно здоровье. Механический червяк погиб бы, блокируя клеща, а его нужно сохранить. Потратив эфир иначе, вы потеряете возможность поднять обе необходимые стены.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_one_open_lane`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "ENAL",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 5
  },
  {
    "id": 3,
    "kind": "block",
    "target": 6
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 5. Two Locked Gates

**Medium · Win · Reusing an active creature**

**Matchup:** Kinet adept (Lv 4) / Kinet adept (Lv 4).

Win this turn. Two flying walls stand between the Green Dragon and a seven-health hero.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 20 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 7 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. The Dragon has to work more than once, and it still needs to attack.
2. Spirit of War readies its target immediately; merely having Restless does not stop an ability from resting it.
3. Break a wall, ready the Dragon, break the other wall, ready it again, and attack.

**Solution and reason**

Use Wall Breaker on either Wall of Force, cast Spirit of War on the Dragon, break the second wall, then use the second Spirit of War. Attack with the now-ready Dragon for seven. Ready too early and the last ability leaves it resting. Removing just one wall lets the defender stop the Dragon and survive any Assassin damage.

**Tempting alternatives checked**

- Spend one readying effect before the first ability
- Ready the Assassin instead of the Dragon

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Двое запертых ворот — Повторное применение способности**

Адепт кинетов (Lv 4) / Адепт кинетов (Lv 4)

Победите за этот ход. Между зелёным драконом и героем с семью единицами здоровья стоят две летающие стены.

1. Дракону нужно применить способность несколько раз, а затем ещё и атаковать.
2. «Дух войны» сразу поднимает цель. Неутомимость не отменяет отдых после применения способности.
3. Разрушьте стену, поднимите дракона, разрушьте вторую, снова поднимите его и атакуйте.

Разрушьте зелёным драконом любую стену силы. Поднимите его первым «Духом войны», разрушьте вторую стену и поднимите вторым. Теперь дракон может атаковать на семь урона. Если потратить подъём заранее, последняя способность оставит дракона отдыхать. Одной уничтоженной стены недостаточно: оставшаяся остановит дракона, а урона авиака для победы не хватит.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_two_locked_gates`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "id": 2,
    "key": "wall_break",
    "kind": "ability",
    "target": 4
  },
  {
    "card": "SPWR",
    "kind": "cast",
    "target": 2
  },
  {
    "id": 2,
    "key": "wall_break",
    "kind": "ability",
    "target": 5
  },
  {
    "card": "SPWR",
    "kind": "cast",
    "target": 2
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 6. Borrowed Life

**Medium · Win · Sacrifice and resource conversion**

**Matchup:** Vital warrior (Lv 4) / Chaot warrior (Lv 4).

Win this turn. You have one ether and one health. Dissolution is already active, but choosing its sacrifice determines what remains possible.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `GreenMale1` | 4 | 1 / 20 | 4 | None |
| Opponent | `RedMaleWarrior2` | 4 | 8 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. You need ether, damage, and enough health to survive your own final spell.
2. The two creatures have the same toughness, but only one can supply the damage you need later.
3. Dissolve the Fingus, use Force of Sacrifice on the Patriarch, then burn the graveyards.

**Solution and reason**

Dissolve the 0/6 Carnivorous Fingus: the first game's Dissolution adds power plus toughness minus one, taking ether from one to six. Force of Sacrifice on the 6/6 Mantis Patriarch costs two, heals you from one to seven, and damages the enemy from eight to two. Burning Graves then deals four to each hero. Sacrificing the Patriarch for ether instead removes the damage source. Casting the graveyard burn before healing kills you.

**Tempting alternatives checked**

- Dissolve the largest attacker for more ether
- Burn the graves before gaining health

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Жизнь взаймы — Жертвы и обмен ресурсов**

Воин виталов (Lv 4) / Воин хаотов (Lv 4)

Победите за этот ход. У вас по одной единице эфира и здоровья. «Рассеяние» уже действует, но выбор жертвы определит дальнейший план.

1. Вам нужны эфир, урон и достаточно здоровья, чтобы пережить собственное последнее заклинание.
2. У обоих созданий одинаковая стойкость, но только одно даст необходимый урон позже.
3. Рассеяйте фингуса, примените «Силу жертвоприношения» к патриарху, затем сожгите могильники.

Пожертвуйте плотоядного фингуса 0/6 способностью «Рассеяния»: в первой игре она даёт сумму силы и стойкости минус один, увеличивая запас эфира с одного до шести. «Сила жертвоприношения» на мантиса-патриарха 6/6 стоит два эфира, поднимает ваше здоровье с одного до семи и снижает здоровье противника с восьми до двух. «Пылающие могилы» затем наносят обоим по четыре урона. Рассеяв патриарха, вы лишитесь источника урона; сжигая могильники до лечения — погибнете.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_borrowed_life`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "id": 0,
    "key": "sacrifice:1",
    "kind": "ability",
    "target": 2
  },
  {
    "card": "CANV",
    "kind": "cast",
    "target": 3
  },
  {
    "card": "BRGR",
    "kind": "cast",
    "target": -1
  }
]
```

</details>

### 7. The Late Arrival

**Medium · Win · Grave selection and summoning sickness**

**Matchup:** Synthet adept (Lv 4) / Vital warrior (Lv 4).

Win this turn. The graveyard offers a powerful Ogre and a smaller Hopper; there is no time to wait for a new creature to recover.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlackMale1` | 4 | 10 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 6 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. Printed power is not the only thing that matters when a creature returns this turn.
2. The Hopper ignores summoning sickness. Its final attack must trample through the Tick.
3. Exchange the Worm for the Hopper, Bless the Hopper, give it Alpha Strike, and attack.

**Solution and reason**

Body Exchange sacrifices the Mech Worm and summons the Hopper from grave slot one. Unlike the larger Ogre, the Hopper can attack immediately. Bless adds four power; Alpha Strike adds its printed two and grants First Strike plus Trample. Its eight power kills the 2/2 Tick and tramples for six. Buffing the original Worm reaches only six power, leaving four after the block.

**Tempting alternatives checked**

- Revive the stronger Ogre
- Spend Bless on the creature you begin with

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Опоздавшее подкрепление — Выбор возвращаемого создания**

Адепт синтетов (Lv 4) / Воин виталов (Lv 4)

Победите за этот ход. В могильнике есть сильный людоед и более слабый прыгун. Ждать, пока новое создание сможет атаковать, некогда.

1. При возвращении создания в этот ход важна не только его сила.
2. Прыгун может атаковать сразу. Его удар должен пройти через клеща и достать героя.
3. Обменяйте червяка на прыгуна, примените к прыгуну «Благословение» и «Альфа-удар», затем атакуйте.

«Телесный обмен» жертвует механического червяка и возвращает прыгуна из могильника. В отличие от более сильного людоеда, прыгун обладает Готовностью и может атаковать немедленно. «Благословение» добавляет четыре силы; «Альфа-удар» — ещё две, равные исходной силе, а также Первый удар и Кровожадность. Удар силой восемь уничтожает клеща 2/2 и проводит шесть урона в героя. Усиленный теми же заклинаниями червяк получает лишь шесть силы и проводит через блок только четыре урона.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_late_arrival`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "BDEX",
    "grave": 1,
    "kind": "cast",
    "target": 2
  },
  {
    "card": "BLSS",
    "kind": "cast",
    "target": 4
  },
  {
    "card": "ALST",
    "kind": "cast",
    "target": 4
  },
  {
    "id": 4,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 3,
    "kind": "block",
    "side": 1,
    "target": 4
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 8. Balanced Destruction

**Medium · Win · Two-sided damage accounting**

**Matchup:** Chaot warrior (Lv 4) / Chaot warrior (Lv 4).

Win this turn. Annihilation can reach the enemy hero, but it measures both armies before destroying them.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `RedMaleWarrior2` | 4 | 5 / 20 | 4 | None |
| Opponent | `RedMaleWarrior2` | 4 | 10 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. Count your army's total power and the enemy army's total power separately.
2. You need at least ten power on your side and less than five on theirs.
3. Bless one of your creatures, Weaken the enemy Ogre, then cast Annihilation.

**Solution and reason**

Your army begins with six power and the enemy with eight. Bless adds four to your total. Weaken on the Gray Ogre removes four enemy power, bringing its army to four. Annihilation therefore deals ten to the enemy and four to you, leaving one health. The two preparations may be done in either order. Buffing the enemy or weakening your own army solves the wrong half of the equation; casting Annihilation before both preparations is fatal or insufficient.

**Tempting alternatives checked**

- Annihilate immediately
- Prepare only your own damage total
- Weaken the smaller enemy

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Равновесие разрушения — Расчёт урона обеих армий**

Воин хаотов (Lv 4) / Воин хаотов (Lv 4)

Победите за этот ход. «Аннигиляция» достанет вражеского героя, но сначала подсчитает силу обеих армий.

1. Посчитайте суммарную силу каждой армии отдельно.
2. На вашей стороне должно быть не меньше десяти силы, а на вражеской — меньше пяти.
3. Благословите своё создание, ослабьте вражеского людоеда, затем примените «Аннигиляцию».

У вашей армии шесть силы, у вражеской — восемь. «Благословение» добавляет четыре к вашей сумме, а «Слабость» на серого людоеда убирает четыре из вражеской. «Аннигиляция» нанесёт противнику десять урона, а вам — четыре, оставив одно здоровье. Два подготовительных заклинания можно применить в любом порядке. Усиление врага или ослабление своего создания меняет не ту половину расчёта. Без обоих подготовительных заклинаний финальный удар либо погубит вас, либо не даст победы.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_balanced_destruction`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "BLSS",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "WEAK",
    "kind": "cast",
    "target": 4
  },
  {
    "card": "ANHL",
    "kind": "cast",
    "target": -1
  }
]
```

</details>

### 9. Silence Is Not Sleep

**Medium · Win · Resting versus disabling an ability**

**Matchup:** Vital warrior (Lv 4) / Synthet adept (Lv 4).

Win this turn. Two Walls stand between your Shadow Wolf and the enemy hero. You have four ether.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `GreenMale1` | 4 | 20 / 20 | 4 | None |
| Opponent | `BlackMale1` | 4 | 4 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. Removing a creature's ability and resting it are different operations.
2. The Mantis Scribe can rest both walls for one ether each. Distortion does not require a ready wall.
3. Put Irritation on the Wall of Distortion, use the Scribe to rest the walls, then attack with the Shadow Wolf.

**Solution and reason**

Irritation prevents the Wall of Distortion from sacrificing itself to cancel the attack. The Mantis Scribe's ability rests both walls, leaving no legal blocker for the Wolf's four damage. Enfeebling the Distortion Wall does not switch off its ability, which has no ready requirement. Using Irritation on the Scribe instead removes the only way to clear both blocking lanes. The two preparations may be performed in either order.

**Tempting alternatives checked**

- Enfeeble and tap the walls, then commit without disabling Distortion
- Put Irritation on the Scribe
- Spend an extra ether making the Wolf restless

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Молчание — не сон — Отдых и запрет способности**

Воин виталов (Lv 4) / Адепт синтетов (Lv 4)

Победите за этот ход. Между Призрачным волком и вражеским героем стоят две стены. У вас четыре единицы эфира.

1. Запрет способности и перевод существа в состояние отдыха — разные действия.
2. Мантис-летописец отправляет стены отдыхать за единицу эфира на каждую. Искажение не требует готовности стены.
3. Наложите Раздражение на Стену искажения, способностью Летописца отправьте стены отдыхать и атакуйте Призрачным волком.

Раздражение запрещает Стене искажения пожертвовать собой ради отмены атаки. Мантис-летописец отправляет обе стены отдыхать, и четыре урона Волка проходят герою. Бессилие не запрещает Искажение: этой способности не нужно готовое существо. Раздражение на самом Летописце лишает вас единственного способа одновременно убрать обоих защитников. Порядок двух подготовительных действий можно менять.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_silence_is_not_sleep`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "IRRT",
    "kind": "cast",
    "target": 4
  },
  {
    "id": 2,
    "key": "tap_walls",
    "kind": "ability",
    "target": -1
  },
  {
    "id": 3,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 10. The Useful Survivor

**Medium · Win · Selective dispelling and enemy regeneration**

**Matchup:** Kinet adept (Lv 4) / Vital warrior (Lv 4).

Win this turn. Both heroes have Life Channel. Your Pteros can remove one enchantment, and the enemy has exactly one ether for regeneration. A symmetric disaster would kill you first.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 2 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 6 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. An enemy surviving a spell can be useful if its regeneration heals the right hero.
2. Remove the enemy's Life Channel before provoking regeneration. Keep yours and budget for Catastrophe's printed cost plus X.
3. Use the Pteros to dispel the enemy Life Channel, strike the enemy Sapling with Call Lightning, then cast Catastrophe with X = 6.

**Solution and reason**

The Pteros pays two ether to remove the enemy's Life Channel. Lightning costs one and forces the Sapling's automatic regeneration, spending its owner's last ether. Only your remaining Life Channel triggers, raising you from two health to seven. Your eight remaining ether pays the two-cost Catastrophe plus X=6: you survive on one, and the enemy falls. Triggering regeneration before removing the enemy channel also heals that hero to eleven, beyond your lethal budget.

**Tempting alternatives checked**

- Provoke regeneration while both Life Channels remain
- Dispel your own Life Channel
- Spend the damage spell on the wall

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Полезный выживший — Выборочное рассеивание и регенерация врага**

Адепт кинетов (Lv 4) / Воин виталов (Lv 4)

Победите за этот ход. На обоих героях действует Канал Жизни. Птерос может снять одни чары, а у врага есть ровно единица эфира для регенерации. Симметричная катастрофа сначала погубит вас.

1. Выживание врага после заклинания полезно, если его регенерация лечит нужного героя.
2. Снимите вражеский Канал Жизни до регенерации. Сохраните свой и учтите обычную цену Катастрофы сверх X.
3. Птеросом рассеяйте Канал Жизни на враге, ударьте его Молодого древня Молнией и примените Катастрофу с X = 6.

Птерос тратит два эфира на снятие вражеского Канала Жизни. Молния за единицу эфира вызывает автоматическую регенерацию Древня, расходуя последний эфир врага. Срабатывает только ваш Канал Жизни: здоровье растёт с двух до семи. Оставшихся восьми единиц эфира хватает на обычную цену Катастрофы два и X=6. Вы остаётесь с единицей здоровья, враг погибает. Регенерация до снятия вражеских чар исцелит и соперника до одиннадцати — на смертельную Катастрофу эфира уже не хватит.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_useful_survivor`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "choice": 2,
    "id": 2,
    "key": "dispel",
    "kind": "ability",
    "target": 1
  },
  {
    "card": "CLIG",
    "kind": "cast",
    "target": 3
  },
  {
    "card": "CTST",
    "kind": "cast",
    "power": 6,
    "target": -1
  }
]
```

</details>

### 11. The Crowded Return

**Medium · Win · Mass return, hand counts and health capacity**

**Matchup:** Vital healer (Lv 5) / Kinet matriarch (Lv 20).

Win this turn with at least 20 health. Your wounded hero's maximum is 22; the opponent's is 67. Your three creatures are exhausted. Read both hands and the two steel creatures' different protections before spending fourteen ether.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `GreenFemale2` | 5 | 1 / 22 | 4 | None |
| Opponent | `BlueWingedFemale1` | 20 | 6 / 67 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"finish_health": 20, "type": "win"}`.

**Hint progression**

1. The battlefield and the hands are two different ways to count the same creatures. Count your own cards as carefully as the enemy's.
2. Greater Unsummoning can return the Steel Abomination without targeting it, but the Steel Mechozaurus is unaffected. Mind Blast is removed from your hand before it counts the remaining cards.
3. Cast Greater Healing before the lethal spell. Greater Unsummoning returns three creatures to each hand; then Mind Blast counts six cards in your hand and eight in the enemy hand, dealing two and six damage.

**Solution and reason**

Greater Healing restores your maximum of 22. Greater Unsummoning returns all three of your creatures and three enemy creatures: protection from targeting does not stop this global spell, while the Steel Mechozaurus's complete spell immunity does. After Mind Blast leaves your hand, you hold six cards and the enemy holds eight. The resulting two and six damage kill the opponent and leave you at exactly 20. Healing and the mass return may trade order, but both must precede Mind Blast. Spending even one ether on a separate Unsummon breaks the fourteen-ether budget; healing after lethal would be too late to meet the finishing condition. Waiting for the enemy's parasitic upkeep deals only five, leaving it alive.

**Tempting alternatives checked**

- Spend one ether separately returning the Iron Abomination
- Heal, then blast before returning the armies
- Return the armies and blast before restoring health

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Переполненные руки — Массовое возвращение, карты и запас здоровья**

Целительница виталов (Lv 5) / Наставница кинетов (Lv 20)

Победите за этот ход, сохранив хотя бы 20 здоровья. Максимум вашего раненого героя — 22, противника — 67. Трое ваших существ устали. Изучите обе руки и разную защиту двух стальных существ, прежде чем тратить четырнадцать эфира.

1. Поле и рука — два способа посчитать одних и тех же существ. Считайте свои карты так же внимательно, как вражеские.
2. Великое Развоплощение возвращает Стальное исчадие, не выбирая его целью, но не действует на Стального мехозавра. Удар по Разуму покидает вашу руку до подсчёта карт.
3. Исцеление нужно до смертельного заклинания. Великое Развоплощение возвращает по три существа в каждую руку; затем Удар по Разуму считает шесть карт у вас и восемь у врага, нанося два и шесть урона.

Исцеление восстанавливает заданный максимум — 22 здоровья. Великое Развоплощение возвращает всех троих ваших существ и троих вражеских: защита от выбора целью не мешает общему заклинанию, а полная невосприимчивость Стального мехозавра мешает. Когда Удар по Разуму покидает руку, у вас остаётся шесть карт, а у врага — восемь. Два и шесть урона убивают противника и оставляют вам ровно 20 здоровья. Исцеление и массовое возвращение можно переставить, но оба нужны до Удара по Разуму. Даже отдельное Развоплощение за один эфир нарушает бюджет. Исцелиться после смертельного удара уже нельзя: условие конечного здоровья проверяется сразу. Паразит в конце хода наносит врагу лишь пять урона и оставляет его в живых.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_crowded_return`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "GRHE",
    "kind": "cast",
    "target": -1
  },
  {
    "card": "GRUN",
    "kind": "cast",
    "target": -1
  },
  {
    "card": "MDBL",
    "kind": "cast",
    "target": -1
  }
]
```

</details>

### 12. Fall of the Crown

**Hard · Clear · Shared auras and cascading deaths**

**Matchup:** Vital warrior (Lv 4) / Vital warrior (Lv 4).

Clear the enemy army this turn and preserve your injured Tick Warrior. Tick auras strengthen both sides, and existing wounds remain.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `GreenMale1` | 4 | 5 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 20 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"protect": [3], "type": "clear"}`.

**Hint progression**

1. The enemy's apparent health comes from two different aura sources.
2. Removing your Queen will start a chain reaction, including a dangerous change to your own injured Tick.
3. Bless your injured Tick first, then sacrifice your Queen with Force of Sacrifice.

**Solution and reason**

Bless the friendly Tick Warrior before sacrificing the Tick Queen. Losing the Queen's +2 toughness makes the injured enemy Worker die. That removes its global +1/+1 aura, collapsing both injured enemy Warriors. Your own Warrior would also die at its unmodified two toughness, so it must be protected before the cascade starts. Twisted Enhancement on the survivor is a valid alternate protection; the important dependency is protection before removing the Queen.

**Tempting alternatives checked**

- Start the cascade before protecting your injured Tick
- Protect the aura source instead of the survivor

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Падение короны — Общие ауры и цепная гибель**

Воин виталов (Lv 4) / Воин виталов (Lv 4)

Уничтожьте всю вражескую армию за этот ход и сохраните раненого клеща-воина. Ауры клещей усиливают обе стороны, а полученный урон сохраняется.

1. За видимой стойкостью врагов стоят два разных источника усиления.
2. Гибель вашей королевы запустит цепную реакцию, опасную и для собственного раненого клеща.
3. Сначала благословите своего раненого клеща, затем пожертвуйте королеву «Силой жертвоприношения».

Усильте дружеского клеща-воина до жертвы королевы. Когда исчезнет её прибавка в две единицы стойкости, погибнет раненый вражеский рабочий клещ. Вместе с ним исчезнет общая прибавка +1/+1, и погибнут оба вражеских воина. Ваш воин без защиты тоже погиб бы: его базовая стойкость равна уже полученным двум единицам урона. Вместо «Благословения» подходит и «Искажённое улучшение». Обязателен порядок: сначала защита выжившего, затем гибель королевы.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_fall_of_the_crown`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "BLSS",
    "kind": "cast",
    "target": 3
  },
  {
    "card": "CANV",
    "kind": "cast",
    "target": 2
  }
]
```

</details>

### 13. Keep the Spark

**Hard · Win · Two-turn maintenance and defence**

**Matchup:** Synthet adept (Lv 4) / Chaot warrior (Lv 4).

Win within two turns and preserve your Rock Wall. The Big Velos is your only lasting damage source, if you can keep it alive.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlackMale1` | 4 | 3 / 20 | 4 | None |
| Opponent | `RedMaleWarrior2` | 4 | 8 / 20 | 3 | None |

Own-turn budget: **2**. Objective metadata: `{"protect": [3], "type": "win"}`.

**Hint progression**

1. A creature may need to receive damage in order to survive.
2. The Velos must bypass the enemy wall twice. Your Rock Wall can absorb the Ogre's counterattack.
3. Zap your own Velos, give it Cloak of Fear, attack, block the Ogre with Rock Wall, and attack again next turn.

**Solution and reason**

Zap your own Big Velos, leaving it alive and marked as having taken damage. Cloak of Fear lets its four power bypass all blockers. Its damage mark keeps it from destroying itself at the first turn end. Block a Gray Ogre counterattack with Rock Wall, then attack again for the remaining four. The opponent can also decline to attack; that does not stop your second hit. Zapping the enemy hero instead improves immediate damage but loses the Velos at turn end.

**Tempting alternatives checked**

- Use the direct damage on the enemy hero
- Spend ether resting the Ogre instead of protecting the Velos

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Сохранить искру — Подготовка на два хода и защита**

Адепт синтетов (Lv 4) / Воин хаотов (Lv 4)

Победите за два хода и сохраните каменную стену. От большого колесника нужен не один удар; его нужно сохранить.

1. Иногда создание должно получить урон, чтобы пережить конец хода.
2. Колеснику нужно дважды обойти вражескую стену. Ваша стена выдержит ответный удар людоеда.
3. Ударьте своего колесника «Электрошоком», дайте ему «Маску ужаса» и атакуйте. Заблокируйте людоеда стеной и атакуйте колесником ещё раз.

«Электрошок» по собственному большому колеснику оставляет его в живых и отмечает полученный урон. «Маска ужаса» позволяет провести четыре урона мимо блокирующих. Благодаря полученному урону колесник не погибает в конце первого хода. Ответную атаку серого людоеда примите каменной стеной, затем нанесите оставшиеся четыре урона. Отказ противника от атаки тоже не спасает его. «Электрошок» по вражескому герою даёт больше немедленного урона, но оставляет колесника погибать в конце хода.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_keep_the_spark`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "ZAPP",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "CLFR",
    "kind": "cast",
    "target": 2
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 3,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 14. The Cracked Mirror

**Hard · Win · Inversion with retained damage**

**Matchup:** Synthet adept (Lv 4) / Kinet adept (Lv 4).

Win this turn. The Carnivorous Fingus has already taken two damage; its spores deal its current power to their target.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlackMale1` | 4 | 4 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 8 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. The displayed toughness after an inversion still has to survive the damage already on the creature.
2. Shell Skin promises a larger attack value, but it does not create enough toughness after the swap.
3. Give the wounded Fingus Might and Twisted Enhancement, then Delusion. Its eight-power spores finish the hero.

**Solution and reason**

Might plus Twisted Enhancement turns the Fingus into 5/8. Delusion then makes it 8/5, safely above its two existing damage. Sacrifice it with Stinging Spores for eight damage. A Shell Skin line can produce a larger nominal power, but if only Twisted Enhancement supplied its pre-swap power, the resulting two toughness is already lethal. The small Spitting Fingus cannot compensate for a six-damage shortcut.

**Tempting alternatives checked**

- Chase the largest nominal post-swap power
- Invert before providing a safe toughness
- Spend Twisted Enhancement on the smaller Fingus

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Треснувшее зеркало — Перестановка характеристик и старые раны**

Адепт синтетов (Lv 4) / Адепт кинетов (Lv 4)

Победите за этот ход. Плотоядный фингус уже получил два урона. Его споры наносят цели урон, равный текущей силе фингуса.

1. После перестановки характеристик создание всё ещё должно выдержать уже полученный урон.
2. «Ледяной панцирь» обещает большую силу после перестановки, но не обеспечит достаточную стойкость.
3. Дайте раненому фингусу «Мощь» и «Искажённое улучшение», затем примените «Перестановку». Восемь урона спорами решат бой.

«Мощь» и «Искажённое улучшение» превращают фингуса в 5/8. После «Перестановки» он становится 8/5 и выдерживает уже полученные два урона. Пожертвуйте его способностью спор, чтобы нанести герою восемь. Вариант с «Ледяным панцирем» обещает большую итоговую силу, но если исходную силу повысило только «Искажённое улучшение», после перестановки стойкость окажется равна двум: фингус сразу погибнет от старых ран. Один урон плюющегося фингуса не позволит добить героя после шести урона от плотоядного.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_cracked_mirror`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "MGHT",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "TWEN",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "DELS",
    "kind": "cast",
    "target": 2
  },
  {
    "id": 2,
    "key": "spores",
    "kind": "ability",
    "target": 1
  }
]
```

</details>

### 15. Buried Reserve

**Hard · Win · Burial, regeneration and a delayed attack**

**Matchup:** Kinet adept (Lv 4) / Chaot warrior (Lv 4).

Win within two turns and keep the newly summoned Treant Sapling alive. Your wounded army cannot win a normal attack. One Hopper is buried in your graveyard; Life Channel is already active.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 1 / 20 | 4 | None |
| Opponent | `RedMaleWarrior2` | 4 | 2 / 20 | 3 | None |

Own-turn budget: **2**. Objective metadata: `{"protect": [2], "type": "win"}`.

**Hint progression**

1. A useful creature can arrive after your own turn ends. Count the new corpses above the Hopper.
2. Lightning Storm can bury three creatures while the Sapling regenerates. Its regeneration also heals you through Life Channel. Keep one ether for defence.
3. Cast Lightning Storm, then end the turn. Block the Ogre with the Sapling if it attacks. On your next turn, give the returning Hopper Cloak of Fear and attack.

**Solution and reason**

Lightning Storm kills the wounded Wall of Burning Rock, River Halo and wounded Phantasmal Wall. The Sapling regenerates for one ether, triggering Life Channel's five healing. The first game's storm damages creatures, not heroes: you finish on six health; the enemy still has two. Three newer corpses return the Hopper at your turn end. Keep the last ether for the Sapling to regenerate while blocking the Ogre; using the Hopper as the blocker loses your winning attack. The next two-channel refill pays for Cloak of Fear and the Hopper's two damage wins. If the Ogre stays home, the same attack wins.

**Tempting alternatives checked**

- Buy evasion for the starting Sapling
- Spend the reserve on Shell Skin
- Use the returning Hopper as the Ogre's blocker

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Погребённый резерв — Погребение, регенерация и отложенная атака**

Адепт кинетов (Lv 4) / Воин хаотов (Lv 4)

Победите за два хода и сохраните только что призванного Молодого древня. Раненая армия не выиграет обычной атакой. В вашем могильнике лежит Прыгун; Канал Жизни уже действует.

1. Полезное существо может появиться после завершения вашего хода. Посчитайте новые карты над Прыгуном в могильнике.
2. Шторм Молний погребёт три существа, а Древень регенерирует. Его регенерация также исцелит вас через Канал Жизни. Оставьте единицу эфира для защиты.
3. Примените Шторм Молний и завершите ход. Если Людоед атакует, блокируйте Молодым древнем. На следующем ходу дайте вернувшемуся Прыгуну Маску Ужаса и атакуйте.

Шторм Молний убивает раненую Стену горящего камня, Речного нимба и раненую Стену нереальности. Молодой древень регенерирует за единицу эфира. Канал Жизни восстанавливает вам пять здоровья. В первой игре этот Шторм повреждает существ, но не героев: у вас становится шесть здоровья, у врага остаётся два. Три новые карты над Прыгуном возвращают его в бой в конце хода. Последний эфир нужен Древню для регенерации при блокировании Людоеда; жертвовать Прыгуном нельзя — это будущий победный удар. На следующем ходу два канала дают эфир для Маски Ужаса, и Прыгун наносит два урона. Отказ Людоеда от атаки плану не мешает.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_buried_reserve`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "LGST",
    "kind": "cast",
    "target": -1
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 6,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 6
  },
  {
    "kind": "end_phase"
  },
  {
    "card": "CLFR",
    "kind": "cast",
    "target": 8
  },
  {
    "id": 8,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 16. Lasting Wounds

**Hard · Clear · Defensive tempo and retained damage**

**Matchup:** Chaot warrior (Lv 4) / Vital warrior (Lv 4).

Clear every enemy creature by the end of your next own turn. Preserve the Red Dragon and Rock Wall. The attack is committed and the Dragon is resting. Your hero has Fatal Disease and two Energize enchantments. Three damage to your hero would be fatal.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `RedMaleWarrior2` | 4 | 3 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 30 / 30 | 4 | None |

Own-turn budget: **1**. Objective metadata: `{"protect": [2, 3], "type": "clear"}`.

**Hint progression**

1. One breath is insufficient. The first wave has to survive the turn's normal recovery.
2. Fatal Disease affects the enemy's recovery in this edition. The Dragon needs to breathe during defence and still become a blocker. Each Energize can act once.
3. Use one Energize on the Dragon, breathe, then use the other Energize. Block the Pteros with the Dragon and the Ogre with Rock Wall. On your own turn, breathe again.

**Solution and reason**

The existing Fatal Disease prevents enemy regeneration and wound recovery. The first Energize readies the resting Dragon; its breath kills the Treant and leaves three wounds on the Ogre. That ability rests the Dragon again, so the second Energize is needed to block the flying Pteros. Rock Wall holds the Ogre. The Dragon kills the Pteros in combat. The enemy Ogre keeps its three wounds at cleanup; the second breath on your own turn finishes it. Your own creatures recover normally because you cast the first game's Fatal Disease.

**Tempting alternatives checked**

- Cancel the combat with Fog
- Defend without delivering the first breath
- Breathe but leave the Dragon resting for combat

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Незаживающие раны — Защита и сохранение урона**

Воин хаотов (Lv 4) / Воин виталов (Lv 4)

Уберите всех вражеских существ до конца своего ближайшего хода. Сохраните Красного дракона и Каменную стену. Атака объявлена, Дракон отдыхает. На герое действуют Роковая Болезнь и две Подзарядки; три урона герою будут смертельны.

1. Одного дыхания мало. Следы первой волны должны сохраниться после обычного восстановления в конце хода.
2. В первой игре Роковая Болезнь мешает восстановлению врага. Дракон должен использовать дыхание в фазе защиты и всё же успеть блокировать. Каждая Подзарядка действует один раз.
3. Поднимите Дракона одной Подзарядкой, используйте дыхание и поднимите его второй. Драконом блокируйте Птероса, стеной — Людоеда. На своём ходу повторите дыхание.

Действующая Роковая Болезнь запрещает врагу регенерацию и восстановление ран. Первая Подзарядка поднимает Дракона; дыхание убивает Древня и оставляет три раны Людоеду. Способность снова отправляет Дракона отдыхать, поэтому вторая Подзарядка нужна для блокирования летающего Птероса. Каменная стена держит Людоеда. Дракон убивает Птероса. Три раны Людоеда не исчезают в конце хода, и следующее дыхание его добивает. Ваши существа восстанавливаются нормально: в первой игре ваша Роковая Болезнь мешает только сопернику.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_lasting_wounds`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "id": 0,
    "key": "energize:1",
    "kind": "ability",
    "target": 2
  },
  {
    "id": 2,
    "key": "breath",
    "kind": "ability",
    "target": -1
  },
  {
    "id": 0,
    "key": "energize:2",
    "kind": "ability",
    "target": 2
  },
  {
    "id": 2,
    "kind": "block",
    "target": 6
  },
  {
    "id": 3,
    "kind": "block",
    "target": 4
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 2,
    "key": "breath",
    "kind": "ability",
    "target": -1
  }
]
```

</details>

### 17. Safe Passage

**Hard · Control · Contested control and defensive reserves**

**Matchup:** Kinet adept (Lv 4) / Kinet adept (Lv 4).

Take control of both the Fire Elemental and Gray Ogre within two turns, keeping both alive. Your Treant Sapling must also survive. The enemy holds exactly one Lesser Disenchant.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 3 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 30 / 30 | 3 | None |

Own-turn budget: **2**. Objective metadata: `{"protect": [2], "targets": [4, 5], "type": "control"}`.

**Hint progression**

1. You cannot afford both captures now. Plan which attacker remains hostile and how your new enchantment survives the enemy's turn.
2. A Sapling can regenerate through the Ogre, but the Fire Elemental prevents regeneration. You also need one ether left after your first capture.
3. Discard the enemy's Disenchant with Malison, then capture the Fire Elemental. Keep the Sapling for the Ogre and Rock Wall for the Wolf. Use the next refill to capture the Ogre.

**Solution and reason**

Malison removes the enemy's only dispel. Capturing the Fire Elemental uses five more ether, leaving exactly one for the Sapling's regeneration. If the enemy attacks, block the Ogre with the Sapling and the evasive Wolf with Rock Wall. Do not let the captured Elemental kill the Ogre: the objective needs that exact creature alive. The next five-channel refill pays for the second Change of Command. Taking the Ogre first leaves the Elemental's anti-regeneration strike facing a protected Sapling; keeping the dispel in the enemy's hand lets them undo a capture.

**Tempting alternatives checked**

- Capture the Ogre first
- Spend two ether weakening the Wolf
- Pass after capturing while the enemy still holds Disenchant

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Безопасный переход — Перехват контроля и резерв на защиту**

Адепт кинетов (Lv 4) / Адепт кинетов (Lv 4)

За два хода подчините Элементаля огня и Серого людоеда, сохранив обоих в живых. Ваш Молодой древень тоже должен выжить. Единственная карта врага — Снятие Чар.

1. На два подчинения сразу эфира нет. Решите, какой атакующий останется врагом и как сохранить новые чары на протяжении его хода.
2. Древень регенерирует после удара Людоеда, но Элементаль огня запрещает регенерацию. После первого подчинения нужна ещё единица эфира.
3. Проклятием сбросьте рассеивание врага и подчините Элементаля огня. Оставьте Древня для Людоеда, стену — для Волка. Следующее пополнение эфира потратьте на Людоеда.

Проклятие убирает единственное рассеивание врага. Подчинение Элементаля стоит ещё пять эфира; остаётся ровно один для регенерации Древня. При атаке врага блокируйте Людоеда Древнем, а обходящего обычных защитников Волка — Каменной стеной. Не убивайте Людоеда захваченным Элементалем: цель требует сохранить именно это существо. Следующее пополнение от пяти каналов оплачивает второе Переподчинение. Захват Людоеда первым оставляет защищаемого Древня против удара Элементаля, запрещающего регенерацию. Оставленное в руке рассеивание позволяет врагу отменить захват.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_safe_passage`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "MALS",
    "kind": "cast",
    "target": 1
  },
  {
    "card": "CHCM",
    "kind": "cast",
    "target": 4
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 6,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 5
  },
  {
    "id": 3,
    "kind": "block",
    "target": 6
  },
  {
    "kind": "end_phase"
  },
  {
    "card": "CHCM",
    "kind": "cast",
    "target": 5
  }
]
```

</details>

### 18. Wings Outlive the Wizard

**Hard · Survive · Lingering effects and sacrificed auras**

**Matchup:** Kinet adept (Lv 4) / Kinet adept (Lv 4).

Survive this attack while preserving your Warrior Spirit and Rock Wall. You have five health. Two copies of Martyrdom are active. The wounded Dragon leads the attack; none of your creatures currently flies.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 5 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 30 / 30 | 4 | None |

Own-turn budget: **1**. Objective metadata: `{"enemy_turns": 1, "protect": [2, 5], "type": "survive"}`.

**Hint progression**

1. A granted effect can outlive its source, while an aura usually cannot.
2. Give the Warrior Spirit flight before sacrificing the Wizard. Recalculate its power after each lost Spirit aura; the Dragon needs eleven more damage. The Shaman already carries Might.
3. Use the Wizard's flight ability, then both copies of Martyrdom to feed the Wizard and Shaman to the Warrior. Block the Dragon with the Warrior and the Ogre with Rock Wall; let the Wolf through.

**Solution and reason**

The Wizard's flight effect lasts through this enemy turn even after the Wizard dies. Its +2-power aura does not. Martyrdom adds the Wizard's 3/2 and the enhanced Shaman's 5/4, but their auras disappear, so the Warrior ends at 11/7. Its first strike supplies the eleven damage needed to kill the wounded 8/12 Dragon before retaliation. Rock Wall blocks the six-power Ogre, while the Wolf's four damage leaves one hero health. Life drain does not heal the hero for damage dealt to a creature, so letting the Ogre through is fatal. Both sacrifices must contribute to the Warrior; combining them first is also valid if flight was granted. Sacrificing the Wizard before granting flight makes the air lane impossible.

**Tempting alternatives checked**

- Sacrifice the Wizard before it grants flight
- Give the enhanced Shaman's strength to the Wall
- Preserve the Shaman as a blocker rather than transferring its power
- Block the evasive Wolf and rely on life drain against the Dragon

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Крылья переживут колдуна — Длительные эффекты и потеря аур**

Адепт кинетов (Lv 4) / Адепт кинетов (Lv 4)

Переживите атаку, сохранив Призрака-воина и Каменную стену. У героя пять здоровья. Действуют два Самопожертвования. Раненый Дракон возглавляет атаку; сейчас ни одно ваше существо не летает.

1. Дарованная способность может пережить свой источник, а аура обычно исчезает вместе с ним.
2. Дайте Воину полёт, прежде чем пожертвовать Колдуном. После каждой утраты ауры пересчитайте силу; Дракону нужно нанести ещё одиннадцать урона. На Шамане уже есть Мощь.
3. Способностью Колдуна дайте Воину полёт. Двумя Самопожертвованиями передайте Воину силу Колдуна и Шамана. Воином блокируйте Дракона, стеной — Людоеда; пропустите Волка.

Полёт от Колдуна действует до конца этого вражеского хода, даже если Колдун погибнет. Его аура +2 к силе при этом исчезает. Самопожертвование передаёт Воину 3/2 Колдуна и 5/4 усиленного Шамана, но убирает их ауры: получается 11/7. Первый удар наносит одиннадцать урона раненому Дракону 8/12 и убивает его до ответного удара. Стена блокирует Людоеда с силой шесть, а четыре урона Волка оставляют герою единицу здоровья. Похищение жизни не исцеляет героя за урон существам, поэтому пропускать Людоеда нельзя. Сила обеих жертв должна перейти Воину; можно и сначала объединить их, если полёт уже дарован. Если пожертвовать Колдуном до того, как он даст полёт, вы останетесь без воздушного защитника.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_wings_outlive_wizard`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "id": 3,
    "key": "spirit_flight",
    "kind": "ability",
    "target": -1
  },
  {
    "choice": 2,
    "id": 0,
    "key": "combine:1",
    "kind": "ability",
    "target": 3
  },
  {
    "choice": 2,
    "id": 0,
    "key": "combine:2",
    "kind": "ability",
    "target": 4
  },
  {
    "id": 2,
    "kind": "block",
    "target": 6
  },
  {
    "id": 5,
    "kind": "block",
    "target": 7
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 19. Two Lives, One Reset

**Hard · Clear · Reanimation, regeneration and a health reset**

**Matchup:** Kinet adept (Lv 4) / Vital warrior (Lv 4).

Clear the enemy army this turn, finishing with at least two creatures and eight hero health. You begin without an army. The enemy has one ether for regeneration.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 1 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 30 / 30 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"finish_health": 8, "min_allies": 2, "type": "clear"}`.

**Hint progression**

1. Removing an enemy can also recruit it, but a regeneration is not a death.
2. Use the removal that forbids regeneration on the Treant. Polymorph sets your health instead of adding to it.
3. Water Link the Treant and Polymorph it first. Then Water Link the Fire Elemental and destroy it with Rift.

**Solution and reason**

Linking the Treant before Polymorph brings it back under your control. Polymorph bypasses regeneration and sets your health to the Treant's three toughness, overriding the link's healing. Link the Elemental next and Rift it: its return gives the second ally and adds five health, finishing at eight. Reversing the two removals ends at three health. Rifting the Treant instead allows regeneration, spending the removal without recruiting or clearing that creature.

**Tempting alternatives checked**

- Use Rift on the regenerating Treant
- Collect the Elemental's healing before the health reset
- Polymorph the Treant before linking it

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Две жизни и один сброс — Возвращение, регенерация и смена здоровья**

Адепт кинетов (Lv 4) / Воин виталов (Lv 4)

За этот ход уберите вражескую армию, закончив хотя бы с двумя существами и восемью единицами здоровья героя. Своих существ пока нет. У врага один эфир для регенерации.

1. Убрать врага можно так, чтобы он стал союзником, но регенерация не считается смертью.
2. Древню нужно заклинание, запрещающее регенерацию. Превращение устанавливает здоровье героя, а не прибавляет его.
3. Сначала свяжите Древня Водной Связью и примените Превращение. Затем свяжите Элементаля огня и уничтожьте его Разломом.

Водная Связь возвращает Древня под ваш контроль после Превращения. Регенерация запрещена, а здоровье героя становится равным трём — стойкости Древня; это перекрывает исцеление от связи. Затем свяжите Элементаля и примените Разлом. Его возвращение даёт второго союзника и ещё пять здоровья: итог — восемь. Обратный порядок убийств оставляет лишь три здоровья. Разлом на Древне вызывает регенерацию: заклинание потрачено, а враг не убит и не перешёл к вам.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_two_lives_one_reset`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "WTLK",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "PLMR",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "WTLK",
    "kind": "cast",
    "target": 3
  },
  {
    "card": "RIFT",
    "kind": "cast",
    "target": 3
  }
]
```

</details>

### 20. A Census of Eyes

**Hard · Clear · Racial counts and two removal thresholds**

**Matchup:** Vital warrior (Lv 4) / Kinet adept (Lv 4).

Clear the enemy army this turn. Your two Evil Eyes measure different attributes. A newly created creature may matter before it is ready to act.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `GreenMale1` | 4 | 20 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 30 / 30 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "clear"}`.

**Hint progression**

1. Both gaze thresholds depend on how many Evil Eyes you control.
2. A clone counts immediately, although it cannot use its own gaze yet. The Warrior's gaze measures power and refuses Walls.
3. Clone either Evil Eye, Weaken the Green Dragon, use the ordinary Eye on the wall and the Warrior on the Dragon.

**Solution and reason**

Cloning either Eye raises the count from two to three. The original Evil Eye can now destroy the three-toughness Wall of Burning Rock. Weaken lowers the Dragon's power from seven to three, so the Warrior's different gaze can destroy it. The new clone's summoning sickness is irrelevant to the racial count. A cloned Dragon or Wall contributes no Eye, and an early Spirit of War leaves too little ether for both the count increase and the necessary debuff.

**Tempting alternatives checked**

- Clone the impressive enemy Dragon
- Weaken the wall to lower its toughness
- Buy an extra action before improving either threshold

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Перепись злобоглазов — Численность расы и разные пороги уничтожения**

Воин виталов (Lv 4) / Адепт кинетов (Lv 4)

Уберите вражескую армию за этот ход. Ваши два злобоглаза оценивают разные характеристики. Новое существо может принести пользу ещё до готовности к действию.

1. Порог обоих взглядов зависит от числа ваших злобоглазов.
2. Клон сразу входит в это число, хотя сам пока не может смотреть. Взгляд Воина проверяет силу и не действует на стены.
3. Клонируйте любого злобоглаза, ослабьте Зелёного дракона, обычным Злобоглазом уничтожьте стену, а Воином — Дракона.

Клон любого злобоглаза увеличивает их число с двух до трёх. Исходный Злобоглаз теперь уничтожает Стену горящего камня со стойкостью три. Слабость снижает силу Дракона с семи до трёх, позволяя уничтожить его взглядом Воина. Неготовность клона не мешает учитывать его в численности расы. Клон Дракона или стены злобоглазом не считается, а ранний Дух Войны тратит эфир, необходимый и для увеличения числа существ, и для ослабления цели.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_census_of_eyes`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "CLON",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "WEAK",
    "kind": "cast",
    "target": 5
  },
  {
    "id": 2,
    "key": "gaze",
    "kind": "ability",
    "target": 4
  },
  {
    "id": 3,
    "key": "gaze",
    "kind": "ability",
    "target": 5
  }
]
```

</details>

### 21. A Gift Too Generous

**Hard · Survive · Private income and a defensive reserve**

**Matchup:** Chaot warrior (Lv 4) / Chaot warrior (Lv 4).

Survive two enemy turns, preserve both creatures, and finish with at least five ether. You begin with no ether channels. The enemy's only card is Rift, currently beyond its one-channel income.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `RedMaleWarrior2` | 4 | 1 / 20 | 4 | None |
| Opponent | `RedMaleWarrior2` | 4 | 30 / 30 | 3 | None |

Own-turn budget: **2**. Objective metadata: `{"enemy_turns": 2, "finish_mana": 5, "protect": [2, 3], "type": "survive"}`.

**Hint progression**

1. The largest channel spell improves both heroes' future budgets.
2. You need five channels of your own and one ether left for the first defence. A reserve blocker is more valuable than a one-point attack.
3. Cast Volcano and both Geysers, keeping one ether. Block the Ogre with Rock Wall and the Tick with the Sapling whenever they attack. Your five channels refill for the later defence and the finish.

**Solution and reason**

Volcano adds three private channels; the two Geysers add one each. Their seven-ether cost leaves the one ether needed for the Sapling to regenerate through the Tick's first attack. The Wall holds the Ogre. Subsequent refills provide five ether, including the refill at the successful second enemy-turn boundary. Ether Storm looks efficient but gives the enemy four channels too, making its Rift affordable and destroying a protected defender. Stone Ring spends too much of the opening budget for too little future income.

**Tempting alternatives checked**

- Use the larger shared channel increase
- Invest in the inefficient Stone Ring
- Send the future blocker into an unnecessary attack

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Слишком щедрый дар — Собственный доход и запас на защиту**

Воин хаотов (Lv 4) / Воин хаотов (Lv 4)

Переживите два хода врага, сохраните обоих существ и закончите хотя бы с пятью единицами эфира. У вас пока нет эфирных каналов. Единственная карта врага — Разлом; дохода от одного канала ему пока не хватает.

1. Самое большое увеличение каналов улучшит будущие возможности обоих героев.
2. Вам нужны пять своих каналов и единица эфира на первую защиту. Будущий защитник важнее атаки на один урон.
3. Примените Вулкан и оба Гейзера, оставив один эфир. При атаках блокируйте Людоеда стеной, Клеща — Древнем. Пять каналов дадут эфир для следующей защиты и завершения задачи.

Вулкан даёт три канала только вам, два Гейзера — ещё по одному. Семь потраченных единиц эфира оставляют одну для регенерации Древня при первой атаке Клеща. Стена держит Людоеда. Дальнейшие пополнения дают пять эфира, включая пополнение на границе после второго хода врага. Эфирный Шторм кажется выгоднее, но добавляет четыре канала и врагу: тот сможет применить Разлом к защищаемому существу. Кольцо Камней слишком дорого обходится для столь малого будущего дохода.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_gift_too_generous`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "VOLC",
    "kind": "cast",
    "target": -1
  },
  {
    "card": "GEYS",
    "kind": "cast",
    "target": -1
  },
  {
    "card": "GEYS",
    "kind": "cast",
    "target": -1
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 4,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 4
  },
  {
    "id": 3,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 4,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 4
  },
  {
    "id": 3,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 22. The Empty-Handed Standard

**Hard · Win · Kobold rally, attack partners and a deadline**

**Matchup:** Chaot Marshal (Lv 16) / Kinet Novice (Lv 2).

Win before the rival can use Greater Healing. On its next turn, the level-two rival takes one disturbance damage; your level-sixteen hero is still outside that clock. Three Guards are resting.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `RedMaleWarrior2` | 16 | 4 / 55 | 14 | None |
| Opponent | `BlueWingedMale1` | 2 | 4 / 13 | 13 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. The Elder can restore several Kobolds, but cannot restore itself. A Guard still needs an attacking partner.
2. One Shaman shot matters. Its second action must contribute an attack partner, even though it has zero power.
3. Shoot the hero with the Shaman, rally with the Elder, then attack with the Shaman and all three Guards. The Wall can stop only one Guard; the next disturbance supplies the final point.

**Solution and reason**

The Shaman deals one damage before the Elder readies it and the three Guards. The resting Elder cannot lead the attack, so the zero-power Shaman must do so. Two Guards get past the single Wall and leave the rival at one health. Its level-two disturbance arrives at the start of turn fourteen, before Greater Healing is available. A second Shaman shot uses up the only ready non-Guard partner. Rallying before the first shot loses that extra point.

**Tempting alternatives checked**

- Rally before taking the Shaman's first shot
- Use the restored Shaman for a second shot
- Commit the Elder instead of rallying the Guards

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Знамя без оружия — Сбор кобольдов, напарник и предельный срок**

Маршал Хаотов (Lv 16) / Ученик Кинетов (Lv 2)

Победите до того, как соперник применит Исцеление. В начале следующего хода герой второго уровня получит единицу урона от эфирного возмущения; вашему герою шестнадцатого уровня оно пока не грозит. Трое Стражей отдыхают.

1. Старейшина поднимает нескольких кобольдов, но не самого себя. Стражам всё равно нужен атакующий напарник.
2. Нужен один выстрел Шамана. Вторым действием он должен стать напарником для атаки, несмотря на нулевую силу.
3. Выстрелите Шаманом в героя, соберите кобольдов Старейшиной и атакуйте Шаманом со всеми тремя Стражами. Стена остановит лишь одного; последний урон нанесёт возмущение.

Шаман наносит единицу урона, затем Старейшина поднимает его и трёх Стражей. Сам Старейшина уже отдыхает, поэтому атаку должен возглавить Шаман с нулевой силой. Два Стража проходят мимо единственной стены, оставляя врагу одно здоровье. Герой второго уровня получает урон от возмущения в начале четырнадцатого хода — раньше, чем сможет исцелиться. Второй выстрел Шамана тратит единственного готового напарника, а преждевременный сбор теряет первый выстрел.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_empty_handed_standard`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "id": 3,
    "key": "sting",
    "kind": "ability",
    "target": 1
  },
  {
    "id": 2,
    "key": "rally",
    "kind": "ability",
    "target": -1
  },
  {
    "id": 3,
    "kind": "attack"
  },
  {
    "id": 4,
    "kind": "attack"
  },
  {
    "id": 5,
    "kind": "attack"
  },
  {
    "id": 6,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 7,
    "kind": "block",
    "side": 1,
    "target": 4
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 23. Two Venoms Before Dawn

**Hard · Win · Poison, a forest threshold and a defensive reserve**

**Matchup:** Diamanda (Lv 8) / The White Lord (Lv 20).

Win before your next turn begins: level-eight disturbance will deal two damage. The rival regenerates one health at its turn start and shelters behind Dense Forest. The two Elementals can attack back.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `Diamanda` | 8 | 2 / 31 | 20 | None |
| Opponent | `White Lord I` | 20 | 5 / 67 | 19 | Regeneration 3 |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. Direct combat damage is not the entire attack. Each Snake that reaches the hero leaves a separate venom.
2. The weaker Snake cannot attack through Dense Forest yet. The Patriarch can rest both Elementals together, but that does not prevent their next-turn retaliation.
3. Give Lesser Strength to the Tree Snake, tap the Elemental race, and attack with both Snakes. Reserve two ether for Fog against the counterattack. Two venoms overcome the rival's one-point regeneration at its turn end.

**Solution and reason**

Lesser Strength raises the Tree Snake above Dense Forest's one-power threshold. The Patriarch spends two ether to rest both Elementals, so the two Snakes deal four damage and attach two venoms. The rival starts its turn at one health, regenerates to two, and readies its Elementals. Fog stops that retaliation; the two end-of-turn venoms kill the rival before your own two-point disturbance. Buffing the stronger Snake leaves the Tree Snake trapped, and spending Fog before establishing the attack loses the required venom clock.

**Tempting alternatives checked**

- Improve the stronger Snake instead
- Cover the battlefield with Fog before attacking
- Commit the Patriarch to combat instead of opening both lanes

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Два яда до рассвета — Яд, предел леса и запас на защиту**

Диаманда (Lv 8) / Белый Лорд (Lv 20)

Победите до начала своего следующего хода: эфирное возмущение восьмого уровня нанесёт два урона. Соперник восстанавливает единицу здоровья в начале хода и укрыт Густым Лесом. Оба Элементаля способны контратаковать.

1. Урон в бою — лишь часть атаки. Каждая Змея, добравшаяся до героя, оставляет отдельный яд.
2. Слабая Змея пока не может пройти через Густой Лес. Патриарх укладывает обоих Элементалей одной способностью, но на следующем ходу они поднимутся.
3. Дайте Боевой Дух Древесной змее, усыпите расу Элементалей и атакуйте обеими Змеями. Сохраните два эфира для Тумана при контратаке. Два яда в конце хода преодолеют единицу регенерации.

Боевой Дух выводит Древесную змею выше предела Густого Леса — одной единицы силы. Патриарх за два эфира укладывает обоих Элементалей. Две Змеи наносят четыре урона и оставляют два яда. Враг начинает ход с одним здоровьем, восстанавливает его до двух и поднимает Элементалей. Туман останавливает ответную атаку; два яда убивают героя в конце его хода, раньше вашего возмущения на два урона. Усиление второй Змеи оставляет первую в лесу, а ранний Туман мешает нужной атаке.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_two_venoms_before_dawn`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "LSST",
    "kind": "cast",
    "target": 2
  },
  {
    "id": 4,
    "key": "tap_race",
    "kind": "ability",
    "target": 5
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "id": 3,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 6,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "card": "FOGG",
    "kind": "cast",
    "target": -1
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 24. Recruit from the Enemy Grave

**Hard · Clear · A free resurrection and two defensive jobs**

**Matchup:** Omega-800D Diamanda (Lv 12) / Chaot Veteran (Lv 20).

Clear the enemy army within two turns, keeping the Fighter and another creature, with at least two hero health. Fury forces an attack; the Giant Bat has Shell Skin. You have six ether. Your next disturbance deals two before regeneration heals one.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `Omega-800D "Diamanda"` | 12 | 3 / 43 | 24 | Regeneration 3 |
| Opponent | `RedMaleWarrior2` | 20 | 30 / 67 | 23 | None |

Own-turn budget: **2**. Objective metadata: `{"finish_health": 2, "min_allies": 2, "protect": [2], "type": "clear"}`.

**Hint progression**

1. The Fighter's necromancy can use either graveyard. The recruit's printed cost matters, and its combat abilities matter more than its power.
2. The Fighter must be ready again for the ground attacker. Poison resolves after the flying victim has struck back, so the Hornet needs protection as well.
3. Raise the Magic Hornet and give it Shell Skin. Reserve three ether for Energize All. Block Steel Mechos with the Fighter and the armored Giant Bat with the Hornet.

**Solution and reason**

The Fighter can raise the four-cost Hornet for no ether, but rests while doing it. Shell Skin lets the Hornet survive the Bat's five damage. After the turn change the recruit is no longer sick, and Fury forces both enemies forward. Energize All restores the Fighter, whose eight first-strike damage kills Steel Mechos before it hits back. The Hornet survives the Bat's return strike and its poison then finishes the eight-toughness flyer. Your level-twelve disturbance removes two health and expert Regeneration restores one, finishing at two. Another valid route lets the Hornet trade, then raises it again on your second turn to restore the required army size. The larger Giant Bat recruit cannot kill the armored enemy in one combat, and the Mech Worm cannot cover the flying lane.

**Verified alternative: Trade the Hornet, then resurrect it again**

```json
[
  {
    "choice": 0,
    "id": 2,
    "key": "necromancy",
    "kind": "ability",
    "target": 1
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "card": "ENAL",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 3
  },
  {
    "id": 5,
    "kind": "block",
    "target": 4
  },
  {
    "kind": "end_phase"
  },
  {
    "choice": 0,
    "id": 2,
    "key": "necromancy",
    "kind": "ability",
    "target": 0
  }
]
```

**Tempting alternatives checked**

- Raise the more powerful Giant Bat
- Raise the hasty Mech Worm
- Spend Energize All before using necromancy

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Новобранец из вражеской могилы — Бесплатное воскрешение и два рубежа защиты**

Омега-800D Диаманда (Lv 12) / Ветеран Хаотов (Lv 20)

Уничтожьте вражескую армию за два хода, сохранив Некроманта, ещё одно существо и хотя бы два здоровья героя. Бешенство вынуждает врага атаковать; Мышь защищена Панцирем. У вас шесть эфира. Следующее возмущение нанесёт два урона, затем регенерация восстановит один.

1. Способность воскрешения работает с обоими могильниками. Важны печатная цена и способности новобранца, а не только его сила.
2. Некромант должен снова встать для наземного врага. Яд убивает после ответного удара жертвы, поэтому Шершню нужна и защита.
3. Поднимите Магического шершня и дайте ему Ледяной Панцирь. Сохраните три эфира для Общей Подзарядки. Некромантом блокируйте Стального мехоса, Шершнем — защищённую Летучую мышь.

Некромант бесплатно поднимает Шершня с ценой четыре, но сам ложится. Ледяной Панцирь позволяет Шершню выдержать пять урона Мыши. После смены хода новобранец готов, а Бешенство заставляет обоих врагов атаковать. Общая Подзарядка поднимает Некроманта: его восемь урона первым ударом уничтожают Стального мехоса до ответа. Шершень переживает ответ Мыши, и его яд добивает летающего врага со стойкостью восемь. Возмущение двенадцатого уровня отнимает два здоровья, высшая Регенерация возвращает одно: итог — два. Допустим и размен Шершня с последующим воскрешением на втором ходу: так вы восстановите нужную численность армии. Более сильная Летучая мышь не убивает защищённого врага за один бой, а Мехочервь не закрывает воздушное направление.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_enemy_grave_recruit`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "choice": 0,
    "id": 2,
    "key": "necromancy",
    "kind": "ability",
    "target": 1
  },
  {
    "card": "SHSK",
    "kind": "cast",
    "target": 5
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "card": "ENAL",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 3
  },
  {
    "id": 5,
    "kind": "block",
    "target": 4
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 25. Spare the Parasite

**Hard · Win · A living enemy as the winning clock**

**Matchup:** Synthet Novice (Lv 2) / The White Lord (Lv 20).

Win during this defence. Steel Mechozaurus costs its controller five health at turn end, but its attack can drain life. If the duel continues, your level-two disturbance deals a lethal three before you can act.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlackMale1` | 2 | 2 / 13 | 15 | None |
| Opponent | `White Lord I` | 20 | 5 / 67 | 16 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. You need the parasite alive at turn end and its owner still at five health.
2. Prevent all trample damage without dealing enough combat damage to kill the Mechozaurus. Poison will not destroy an unaffected creature.
3. Use Energize All, then block only with the Lamia Monk. It absorbs all eight damage and dies; its four damage leaves the parasite alive. Do not add the Hornet.

**Solution and reason**

The Monk's eight toughness absorbs the entire attack, so the enemy gains no life. Its four damage does not kill the six-toughness Mechozaurus. The parasite then drains its controller's last five health, ending the duel before your next disturbance. Adding the Hornet contributes two first-strike damage; that plus the Monk's four kills the parasite and removes the very upkeep that would win. With no enemy death at turn end, your own three-point disturbance arrives first and kills you. Polymorph cannot target the protected Mechozaurus; consuming your Monk for health removes the only adequate blocker.

**Tempting alternatives checked**

- Combine both blockers to kill the attacker
- Turn the resting Monk into eight hero health
- Use only the ready poisonous flyer

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Пощадите паразита — Живой враг как условие победы**

Ученик Синтетов (Lv 2) / Белый Лорд (Lv 20)

Победите во время этой защиты. Стальной мехозавр отнимает у хозяина пять здоровья в конце хода, но его атака может высосать жизнь. Если бой продолжится, ваше возмущение второго уровня нанесёт смертельные три урона до любого действия.

1. К концу хода паразит должен остаться жив, а его хозяин — сохранить ровно пять здоровья.
2. Поглотите весь натиск, не нанеся достаточно урона для убийства Мехозавра. Яд не уничтожает невосприимчивое существо.
3. Примените Общую Подзарядку и блокируйте только Ламией-монахиней. Она поглотит восемь урона и погибнет, оставив паразита в живых. Не добавляйте Шершня.

Восемь стойкости Монахини поглощают всю атаку: враг не получает жизни. Четыре ответных урона не убивают Мехозавра со стойкостью шесть. Паразит отнимает последние пять здоровья хозяина, завершая бой до вашего возмущения. Шершень добавил бы два урона первым ударом; вместе с четырьмя Монахини это убивает паразита и отменяет нужную плату в конце хода. Тогда первым погибнет ваш герой от возмущения на три урона. Превращение не может выбрать защищённого Мехозавра, а превращение своей Монахини в здоровье лишает вас подходящего защитника.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_spare_the_parasite`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "ENAL",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 4
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 26. Room for Two

**Hard · Win · Army capacity, spell income and a reflected finish**

**Matchup:** Kinet Archmage (Lv 20) / Chaot Adept (Lv 5).

Win this turn with at least 64 hero health. Your level-twenty veteran has a maximum of 67 but only one health remains. Two Ether Harvest enchantments are active, and your nine-creature army has one free slot. The enemy mirrors damage through Ethereal Resonance.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedFemale1` | 20 | 1 / 67 | 4 | None |
| Opponent | `RedMale4` | 5 | 1 / 22 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"finish_health": 64, "type": "win"}`.

**Hint progression**

1. Both heroes are at one health, so an immediate attack or shot loses the required healthy finish. You first need nine ether for Greater Healing.
2. Each actual creature-card cast triggers both Ether Harvest enchantments. Mother Bee's brood is not a cast. Two one-cost summons produce the required income, but you need room for both.
3. Sacrifice the Spitting Fingus into a sturdy friendly creature, cast Bee Worker and Bronze Abomination, and use Greater Healing. Then shoot the enemy with the Cyclops. The mirrored three damage leaves you at 64.

**Solution and reason**

The Fingus opens a second army slot without spending ether. Each one-cost summon spends one and receives four from the two Ether Harvest enchantments, so the pool rises from three to six to nine. Greater Healing restores the veteran's maximum of 67. The Cyclops's three-point shot also hurts you through Resonance, leaving 64 when the enemy dies. Mother Bee creates a creature without casting its card, so it gives no Harvest income and consumes a needed slot. Starting with the two-cost Disease Rat misses the budget. An alternative can sacrifice the newly summoned Worker with the Cyclops and save the Fingus for the final one-point hit; that healthy finish is also accepted.

**Verified alternative: Recycle the new Worker and retain the Fingus finisher**

```json
[
  {
    "card": "BEWK",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 2,
    "key": "sting",
    "kind": "ability",
    "target": 11
  },
  {
    "card": "BRAB",
    "kind": "cast",
    "target": -1
  },
  {
    "card": "GRHE",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 3,
    "key": "spores",
    "kind": "ability",
    "target": 1
  }
]
```

**Tempting alternatives checked**

- Use the Mother's brood as a cheap source of Harvest income
- Start with the more substantial Disease Rat
- Take the apparent immediate kill with the Fingus

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Место для двоих — Предел армии, доход от призыва и отражённый удар**

Архимаг Кинетов (Lv 20) / Адепт Хаотов (Lv 5)

Победите за этот ход, сохранив хотя бы 64 здоровья героя. Максимум вашего ветерана двадцатого уровня — 67, но осталось лишь одно здоровье. Действуют два Эфирных Урожая, а в армии из девяти существ одно свободное место. Враг отражает урон Эфирным Резонансом.

1. У обоих героев по одному здоровью. Немедленная атака или выстрел нарушают условие здорового завершения. Сначала нужны девять эфира для Исцеления.
2. Оба Урожая срабатывают при розыгрыше карты существа. Потомство Матки — не розыгрыш карты. Два призыва ценой по одному дадут нужный доход, но обоим требуется место.
3. Пожертвуйте Плюющимся фингусом, выбрав крепкого союзника. Призовите Рабочую пчелу и Бронзовое исчадие, затем примените Исцеление. Выстрел Циклопа убьёт врага, а отражённые три урона оставят вам 64 здоровья.

Фингус освобождает второе место без затрат эфира. Каждый призыв ценой один тратит единицу и получает четыре от двух Урожаев: запас растёт с трёх до шести, затем до девяти. Исцеление возвращает ветерану максимум в 67 здоровья. Выстрел Циклопа наносит три урона и вам через Резонанс: при смерти врага остаётся 64. Матка создаёт существо без розыгрыша карты, поэтому не даёт дохода и занимает нужное место. Начало с более дорогой Заразной крысы нарушает расчёт эфира. Допустим и другой путь: уничтожить новую Рабочую пчелу Циклопом, а Фингуса сохранить для последнего удара на единицу.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_room_for_two`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "id": 3,
    "key": "spores",
    "kind": "ability",
    "target": 2
  },
  {
    "card": "BEWK",
    "kind": "cast",
    "target": -1
  },
  {
    "card": "BRAB",
    "kind": "cast",
    "target": -1
  },
  {
    "card": "GRHE",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 2,
    "key": "sting",
    "kind": "ability",
    "target": 1
  }
]
```

</details>

### 27. Every Coin Draws Blood

**Expert · Win · Payment damage and an enemy resource reserve**

**Matchup:** Kinet adept (Lv 4) / Vital warrior (Lv 4).

Win this turn. Ether Thorns damages either hero for every ether spent. Two Fireballs and Life Channel are already active; a third Fireball is in hand. Your two Halos steal different amounts.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 2 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 4 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. The enemy needs to keep one ether long enough to do something useful for you.
2. Regeneration can trigger your Life Channel. Emptying the enemy's pool first prevents that healing, while installing the third Fireball before healing kills you.
3. Use the River Halo to take two ether and the Shaman for one. Fireball the Sapling so it regenerates, then install the third Fireball and use the two unused shots on the hero.

**Solution and reason**

River Halo leaves one enemy ether for the Sapling's automatic regeneration. With the Shaman, you have six ether in total. The first Fireball costs one health through Thorns, then regeneration triggers five healing from Life Channel. You can now afford the three-ether installation and the two remaining shots: six ether spent overall leaves one health. The enemy also loses one health paying to regenerate; two shots finish it. Sea Halo is safe only after that regeneration has happened. Stealing all three ether first disables the healing route. The weakened Sea Halo cannot replace the final shot with combat damage.

**Tempting alternatives checked**

- Empty the enemy pool with the larger Halo first
- Install the third Fireball before healing
- Take the apparent immediate kill with both existing shots

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Каждый квант оплачен кровью — Урон за оплату и резерв эфира врага**

Адепт кинетов (Lv 4) / Воин виталов (Lv 4)

Победите за этот ход. Колючий Эфир ранит любого героя за каждую потраченную единицу эфира. Два Огненных Шара и Канал Жизни уже действуют; третий Шар в руке. Два ваших нимба крадут разное количество эфира.

1. Врагу нужно ненадолго оставить единицу эфира: она позволит ему сделать нечто полезное для вас.
2. Регенерация активирует ваш Канал Жизни. Полное опустошение вражеского запаса запрещает это исцеление, а установка третьего Шара до исцеления убивает героя.
3. Речным нимбом заберите два эфира, Шаманом получите ещё один. Шаром заставьте Древня регенерировать, затем установите третий Шар и двумя неиспользованными выстрелами добейте героя.

Речной нимб оставляет врагу один эфир для автоматической регенерации Древня. Вместе со способностью Шамана вы получаете шесть эфира. Первый выстрел отнимает здоровье из-за Колючего Эфира, затем регенерация активирует Канал Жизни и восстанавливает пять здоровья. Теперь можно заплатить три за установку Шара и ещё два за последние выстрелы: всего потрачено шесть, у героя остаётся одно здоровье. Враг также теряет здоровье при оплате регенерации; двух выстрелов достаточно. Морского нимба можно использовать после регенерации, но его большой первоначальный захват отключает лечение. Ослабленный Морской нимб не заменит последний выстрел атакой.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_every_coin_draws_blood`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "id": 2,
    "key": "siphon",
    "kind": "ability",
    "target": -1
  },
  {
    "id": 4,
    "key": "ether",
    "kind": "ability",
    "target": -1
  },
  {
    "id": 0,
    "key": "fireball:1",
    "kind": "ability",
    "target": 5
  },
  {
    "card": "FRBL",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 0,
    "key": "fireball:2",
    "kind": "ability",
    "target": 1
  },
  {
    "id": 0,
    "key": "fireball:6",
    "kind": "ability",
    "target": 1
  }
]
```

</details>

### 28. The Wall After the Battle

**Expert · Survive · Temporary toughness, recovery and final health**

**Matchup:** Kinet adept (Lv 4) / Kinet adept (Lv 4).

Survive this attack, preserve all three creatures, and finish with at least eight hero health. The Wall of Illusion is already wounded. Enemy Fatal Disease prevents your wounds from recovering.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 1 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 30 / 30 | 4 | None |

Own-turn budget: **1**. Objective metadata: `{"enemy_turns": 1, "finish_health": 8, "protect": [2, 3, 4], "type": "survive"}`.

**Hint progression**

1. The wall has to survive both combat and the disappearance of its temporary toughness.
2. Removing Fatal Disease restores the normal cleanup, but does not erase existing wounds immediately. The Halo must finance all three jobs: a dispel, an illusion and a transformation.
3. Steal two ether with the Halo. Dispel Fatal Disease with the Pteros, Polymorph the Blue Dragon, and activate the wall's illusion. Block the Ogre with the wall.

**Solution and reason**

The Halo raises your pool from three to five. The Pteros pays three to remove Fatal Disease; Polymorph costs one and sets your hero to the Dragon's eight toughness. The wall's one-ether ability replaces its printed three toughness with five, because four creatures lie in your graveyard. Shell Skin remains, making nine toughness. Its two old wounds plus the Ogre's six damage leave it barely alive. Normal cleanup now erases those wounds before the temporary illusion ends. Keeping Fatal Disease would kill the wall when it falls back to seven toughness. Letting the Ogre through misses the final health requirement.

**Tempting alternatives checked**

- Dispel the wall's Shell Skin rather than Fatal Disease
- Polymorph the ground attacker
- Spend the opening pool on Energize All
- Remove disease but block without raising the wounded wall's toughness

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Стена после боя — Временная стойкость, восстановление и итоговое здоровье**

Адепт кинетов (Lv 4) / Адепт кинетов (Lv 4)

Переживите атаку, сохраните всех троих существ и закончите хотя бы с восемью единицами здоровья героя. Стена иллюзии уже ранена. Вражеская Роковая Болезнь мешает вашим ранам заживать.

1. Стена должна пережить и сам бой, и исчезновение временной стойкости.
2. Снятие Роковой Болезни возвращает обычное восстановление, но не убирает раны немедленно. Нимб должен оплатить три задачи: рассеивание, иллюзию и превращение.
3. Украдите Нимбом два эфира. Птеросом снимите Роковую Болезнь, Превращением уберите Синего дракона и активируйте иллюзию стены. Стеной блокируйте Людоеда.

Нимб увеличивает запас эфира с трёх до пяти. Птерос за три снимает Роковую Болезнь; Превращение за один устанавливает герою восемь здоровья — стойкость Дракона. Последний эфир оплачивает способность стены: четыре карты в могильнике заменяют её исходную стойкость три на пять. Ледяной Панцирь остаётся, давая итоговые девять. Две старые раны и шесть урона Людоеда оставляют стену в живых. Теперь обычное восстановление убирает раны до окончания иллюзии. С Роковой Болезнью стена погибла бы при возврате к семи стойкости. Пропуск Людоеда нарушает требование к итоговому здоровью.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_wall_after_battle`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "id": 4,
    "key": "siphon",
    "kind": "ability",
    "target": -1
  },
  {
    "choice": 1,
    "id": 3,
    "key": "dispel",
    "kind": "ability",
    "target": 1
  },
  {
    "card": "PLMR",
    "kind": "cast",
    "target": 6
  },
  {
    "id": 2,
    "key": "illusion",
    "kind": "ability",
    "target": -1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 29. Borrowed Armour

**Expert · Control · Enchantment ageing and a conditional defence**

**Matchup:** Kinet adept (Lv 4) / Vital warrior (Lv 4).

Control the Gray Ogre after the enemy's next turn, preserving your Wall and Sapling. Its aged Twisted Enhancement is already at −4/−4; Bless masks that weakness. The enemy holds one Call Lightning.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 1 / 20 | 8 | None |
| Opponent | `GreenMale1` | 4 | 30 / 30 | 7 | None |

Own-turn budget: **1**. Objective metadata: `{"enemy_turns": 1, "protect": [2, 3], "targets": [4], "type": "control"}`.

**Hint progression**

1. The Ogre's displayed toughness will not survive the turn change unchanged. Capture and protection must be planned together.
2. Shell Skin leaves the captured Ogre at four toughness after decay and Bless expiry. Save one ether for the Sapling, then inspect where the enemy spends Lightning.
3. Give the Ogre Shell Skin and capture it. Keep Rock Wall for the Mechos. If Lightning hits the Ogre, block the Treant with your Sapling; if it hits the Sapling and spends your regeneration ether, block the Treant with the Ogre.

**Solution and reason**

The temporary Bless expires at the end of your turn because the Ogre originally belongs to the enemy. Its aged Enhancement also decays to −5/−5. Shell Skin leaves four toughness; Scale Skin would leave only two and lose to Lightning. Nine ether pays for capture and Shell Skin with one left for regeneration. If Lightning wounds the Ogre, reserve it and regenerate the Sapling through the Treant. If Lightning instead consumes the Sapling's regeneration ether, the unwounded Ogre can absorb the Treant's three damage. Rock Wall blocks the Bronze Mechos: Walls resist its post-combat execution. The goal is checked after the next enemy turn counted from this snapshot.

**Verified alternative: Lightning hits the Sapling**

```json
[
  {
    "card": "SHSK",
    "kind": "cast",
    "target": 4
  },
  {
    "card": "CHCM",
    "kind": "cast",
    "target": 4
  },
  {
    "kind": "end_phase"
  },
  {
    "card": "CLIG",
    "kind": "cast",
    "side": 1,
    "target": 3
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 6,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 6
  },
  {
    "id": 4,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  }
]
```

**Tempting alternatives checked**

- Use the cheaper Scale Skin on the captive
- Protect the Sapling with Shell Skin instead
- Capture and pass while the temporary Bless is the only protection
- Keep the same Sapling block after Lightning spends its regeneration reserve

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Одолженная броня — Старение чар и защита по ответу противника**

Адепт кинетов (Lv 4) / Воин виталов (Lv 4)

После ближайшего хода врага контролируйте Серого людоеда, сохранив свою стену и Древня. Его старое Искажённое Улучшение уже даёт −4/−4; Благословение скрывает слабость. У врага одна Молния.

1. Показанная стойкость Людоеда изменится на границе хода. Захват и защиту нужно спланировать вместе.
2. После ослабления чар и окончания Благословения Ледяной Панцирь оставит Людоеду четыре стойкости. Сохраните один эфир для Древня, затем посмотрите, куда враг направит Молнию.
3. Дайте Людоеду Ледяной Панцирь и подчините его. Стеной держите Мехоса. Если Молния ранит Людоеда, блокируйте Старого древня Молодым; если она расходует эфир регенерации Молодого древня — блокируйте Людоедом.

Благословение закончится в конце вашего хода: исходный владелец Людоеда — враг. Старое Улучшение также ослабеет до −5/−5. Панцирь оставит четыре стойкости, а Чешуя — лишь две, недостаточные против Молнии. Из девяти эфира захват и Панцирь оставляют один для регенерации. Если Молния ранит Людоеда, берегите его и блокируйте Старого древня Молодым с регенерацией. Если же Молния потратит резерв на регенерацию Молодого древня, невредимый Людоед выдержит три урона Старого. Каменная стена блокирует Бронзового мехоса: его добивание после боя не действует на стены. Цель проверяется после ближайшего хода врага, отсчитываемого от начальной позиции.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el1_tactical_v2_borrowed_armour`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "SHSK",
    "kind": "cast",
    "target": 4
  },
  {
    "card": "CHCM",
    "kind": "cast",
    "target": 4
  },
  {
    "kind": "end_phase"
  },
  {
    "card": "CLIG",
    "kind": "cast",
    "side": 1,
    "target": 4
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 6,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 6
  },
  {
    "id": 3,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

## Etherlords II

### 1. Repair by Breaking

**Easy · Win · Graveyard conversion**

**Matchup:** Synthet adept (Lv 4) / Kinet adept (Lv 4).

Two walls stop your Wyrm. Find a win this turn without depending on combat. Inspect both enchantments on your creature.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlackMale1` | 4 | 7 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 5 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. The graveyard can be a firing position.
2. One of your creature's enchantments is keeping it alive. Removing it does more than change its stats.
3. Purify Quick Fix on your own Mech Wyrm, then Repair the Wyrm from your graveyard.

**Solution and reason**

Removing Quick Fix destroys its creature. Repair then returns the Wyrm and deals its printed 5 power to the enemy. Removing Twisted Enhancement merely weakens the Wyrm; attacking into two walls does not win.

**Tempting alternatives checked**

- Remove the visible stat bonus instead of Quick Fix

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Сломать, чтобы починить — Могильник как ресурс**

Адепт синтетов (Lv 4) / Адепт кинетов (Lv 4)

Две стены преграждают путь вашему Червезавру. Победите за этот ход, не полагаясь на атаку. Изучите обе чары на своём существе.

1. Могильник тоже может стать огневой позицией.
2. Одни из чар поддерживают жизнь вашего существа. Их снятие не ограничивается изменением характеристик.
3. Очисткой снимите Быструю Починку со своего Червезавра, затем верните его из могильника Ремонтом.

Снятие Быстрой Починки уничтожает её носителя. Ремонт возвращает Червезавра из могильника и наносит противнику урон, равный его базовой силе: пять. Снятие Искаженного Улучшения лишь ослабляет Червезавра; атака в две стены не приносит победы.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_repair_by_breaking`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "PRFY",
    "grave": 1,
    "kind": "cast",
    "target": 2
  },
  {
    "card": "REPR",
    "grave": 0,
    "kind": "cast",
    "target": 0
  }
]
```

</details>

### 2. The Other Reservoir

**Medium · Win · Redirection and resources**

**Matchup:** Synthet adept (Lv 4) / Kinet adept (Lv 4).

Both ether pools are within reach. Find a lethal line that leaves your fragile hero alive. Stealing ether also takes away the obvious damage source.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlackMale1` | 4 | 3 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 4 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. A damaging spell does not always need an enemy target.
2. After Powertap and Feedback, compare the ether in the two pools. Remember that Broken Reality pays its own cost first.
3. Use Powertap, put Feedback on yourself, then cast Broken Reality on your own hero.

**Solution and reason**

Powertap costs 1 and transfers the enemy's 3 ether, leaving pools of 9 and 0. Feedback costs 4. Broken Reality costs 1 before emptying your remaining 4 ether; Feedback redirects those 4 damage. Burning the enemy at the start deals only 3, and burning your own pool without protection is fatal.

**Tempting alternatives checked**

- Burn the enemy pool immediately
- Steal, then burn the enemy pool
- Burn yourself without Feedback

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Другой запас — Отражение урона и эфир**

Адепт синтетов (Lv 4) / Адепт кинетов (Lv 4)

Вам доступны оба запаса эфира. Найдите смертельную для врага комбинацию и сохраните своего хрупкого героя. Откачка эфира одновременно лишает вас очевидного источника урона.

1. Целью наносящего урон заклинания не обязательно должен быть противник.
2. После Откачки Эфира и Зеркала сравните оба запаса. Помните: сначала оплачивается само Разрушение Реальности.
3. Используйте Откачку Эфира, наложите Зеркало на себя, затем примените Разрушение Реальности к своему герою.

Откачка Эфира стоит один квант и забирает три у врага: запасы становятся равны девяти и нулю. Зеркало стоит четыре. Разрушение Реальности сначала тратит ещё один, затем опустошает ваш оставшийся запас из четырёх квантов; Зеркало перенаправляет эти четыре урона врагу. Применение Разрушения к врагу в начале даёт лишь три урона, а к себе без Зеркала — убивает вашего героя.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_other_reservoir`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "PWTP",
    "kind": "cast",
    "target": -1
  },
  {
    "card": "FDBK",
    "kind": "cast",
    "target": -1
  },
  {
    "card": "BRRL",
    "kind": "cast",
    "target": 0
  }
]
```

</details>

### 3. The Shield Belongs Elsewhere

**Medium · Survive · Defensive role assignment**

**Matchup:** Kinet adept (Lv 4) / Chaot warrior (Lv 4).

The enemy attack is already committed. Survive it without losing any hero health, and keep your Aviak Marksman alive. One ally may be sacrificed.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 3 / 20 | 4 | None |
| Opponent | `RedMale4` | 4 | 20 / 20 | 4 | None |

Own-turn budget: **1**. Objective metadata: `{"enemy_turns": 1, "min_health": 3, "protect": [2], "type": "survive"}`.

**Hint progression**

1. Your Marksman is useful even without blocking. A shield only stops one damage event.
2. Remove the smallest attacker, block the middle one, and find a different answer to the dragon.
3. Shoot the enemy Stink Rat with your Marksman; put Lifeguard on your hero; block the Mantis with your Stink Rat, then resolve combat.

**Solution and reason**

The free Marksman shot removes the small attack. Your Stink Rat absorbs the Mantis, while Lifeguard on the hero cancels the dragon's single unblocked hit. Shielding the Marksman instead leaves damage reaching the hero and fails the health requirement.

**Tempting alternatives checked**

- Shield the precious Marksman instead of the hero
- Spend the Marksman's shot on the Mantis

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Кому нужна защита — Распределение ролей в защите**

Адепт кинетов (Lv 4) / Воин хаотов (Lv 4)

Противник уже объявил атаку. Переживите её без потери здоровья героя и сохраните Авиака-стрелка. Одним союзником можно пожертвовать.

1. Стрелок полезен и без блокирования. Защита отменяет только один случай нанесения урона.
2. Уберите самого слабого атакующего, заблокируйте среднего и найдите отдельный ответ на дракона.
3. Стрелком убейте вражескую Вонючую крысу. Наложите Телохранителя на героя, своей Вонючей крысой заблокируйте Мантиса и завершите фазу.

Бесплатный выстрел убирает самую слабую атаку. Ваша Вонючая крыса принимает удар Мантиса, а Телохранитель на герое отменяет единственный незаблокированный удар дракона. Защита Стрелка вместо героя пропустит урон герою и нарушит условие по здоровью.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_shield_elsewhere`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "id": 2,
    "key": "shoot",
    "kind": "ability",
    "target": 6
  },
  {
    "card": "LFGR",
    "kind": "cast",
    "target": 0
  },
  {
    "id": 3,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 4. An Invitation to Discard

**Medium · Survive · Opponent-triggered summons**

**Matchup:** Kinet adept (Lv 4) / Chaot warrior (Lv 4).

Survive the enemy's next turn. Their only card is Call Lightning. Your two Ogres cost more ether than you have. The current edition's discard responses are the key.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 1 / 20 | 4 | None |
| Opponent | `RedMale4` | 4 | 30 / 30 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"enemy_turns": 1, "type": "survive"}`.

**Hint progression**

1. You do not have to pay to summon an Ogre if the enemy makes you discard it.
2. Call Lightning retaliates against forced discard by making the other hero discard three cards.
3. Cast Malison on the enemy. Its discarded Lightning makes you discard both Ogres, summoning them for free. End the turn; the Ogre King can block Fire Elemental and Gray Ogre can block Great Treant.

**Solution and reason**

Malison discards the enemy's only card. Lightning's discard response now makes you discard both remaining cards; both Ogres enter the battlefield. They lose summoning sickness at the end of your turn, ready to defend. The King survives Fire Elemental's first strike; Gray Ogre handles the Treant. No random draw is involved, and every remaining card is discarded regardless of order.

**Tempting alternatives checked**

- Cast Malison on yourself
- Pass without triggering the enemy's response

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Приглашение к сбросу — Существа в ответ на сброс**

Адепт кинетов (Lv 4) / Воин хаотов (Lv 4)

Переживите следующий ход противника. Его единственная карта — Молния. Ваши два людоеда стоят больше эфира, чем у вас есть. Ключ — особенности ответа на сброс во второй игре.

1. За призыв людоеда не нужно платить, если сбросить его вынудил противник.
2. Принудительно сброшенная Молния отвечает требованием сбросить три карты другому герою.
3. Проклятием заставьте врага сбросить Молнию. Её ответ сбросит обоих людоедов и бесплатно призовёт их. Завершите ход; Вождём блокируйте Элементаля огня, Серым людоедом — Старого древня.

Проклятие сбрасывает единственную карту врага. Ответ Молнии заставляет вас сбросить обе оставшиеся карты; оба людоеда появляются на поле. В конце вашего хода они становятся готовы к защите. Вождь переживает первый удар Элементаля огня, а Серый людоед справляется со Старым древнем. Случайного добора нет: все оставшиеся карты сбрасываются независимо от порядка.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_invitation_to_discard`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "MALS",
    "kind": "cast",
    "target": 1
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 2,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 3,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 5,
    "kind": "block",
    "target": 2
  },
  {
    "id": 4,
    "kind": "block",
    "target": 3
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 5. The Last Ether

**Medium · Clear · Regeneration reserve**

**Matchup:** Chaot warrior (Lv 4) / Vital warrior (Lv 4).

Clear the enemy army this turn. Both of your creatures must remain alive. Supernova hurts every creature and both heroes, and spends one ether channel.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `RedMale4` | 4 | 4 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 15 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"protect": [2, 3], "type": "clear"}`.

**Hint progression**

1. There are two ways for your creatures to survive the same blast, but they do not cost the same resources.
2. The Treant regenerates automatically only if you leave enough ether. The Marksman needs a different protection.
3. Put Shell Skin on the Marksman, then cast Supernova with X = 3. Leave the final ether for the Treant's regeneration.

**Solution and reason**

Shell Skin lets the Marksman endure 3 damage. Supernova costs 3 plus X and one channel: after the 2-cost enchantment, X=3 leaves exactly 1 ether for the Treant. It clears both enemies and leaves the hero at 1 health. More power kills the hero; shielding the Treant leaves the Marksman exposed.

**Tempting alternatives checked**

- Give Shell Skin to the regenerating Treant
- Try the blast before protecting the Marksman

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Последний квант — Запас на регенерацию**

Воин хаотов (Lv 4) / Воин виталов (Lv 4)

За этот ход уберите всю армию врага, сохранив обоих своих существ. Сверхновая наносит урон всем существам и обоим героям, а также расходует один эфирный канал.

1. Ваши существа могут пережить один взрыв двумя разными способами, требующими разных ресурсов.
2. Древень автоматически регенерирует, только если оставить достаточно эфира. Стрелку нужна другая защита.
3. Наложите Ледяной Панцирь на Стрелка, затем используйте Сверхновую с X = 3. Оставьте последний квант эфира на регенерацию Древня.

Ледяной Панцирь позволяет Стрелку пережить три урона. Сверхновая стоит 3 + X и один канал: после чар стоимостью два значение X = 3 оставляет ровно один квант на регенерацию Древня. Оба врага погибают, у героя остаётся одно здоровье. Большая сила заклинания убьёт героя; Панцирь на Древне оставит Стрелка без защиты.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_last_ether`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "SHSK",
    "kind": "cast",
    "target": 3
  },
  {
    "card": "SNOV",
    "kind": "cast",
    "power": 3,
    "target": -1
  }
]
```

</details>

### 6. The Exact Price

**Medium · Win · Life as a resource**

**Matchup:** Kinet adept (Lv 4) / Chaot warrior (Lv 4).

Your opening ether can pay for Ether Trade and nothing else. A larger loan also heals the enemy. Find a precise lethal sequence this turn.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 6 / 20 | 4 | None |
| Opponent | `RedMale4` | 4 | 5 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. Work backwards from the final graveyard, not from the largest spell value you can afford.
2. A third enemy corpse makes Burning Graves deal 9. You need 4 ether for the two remaining spells, while the enemy starts at 5 health.
3. Cast Ether Trade with X = 4, kill the Stink Rat with Call Lightning, then cast Burning Graves.

**Solution and reason**

The 4-health loan produces exactly 4 ether and raises enemy health from 5 to 9. Lightning adds the third corpse for 1 ether, and Burning Graves spends the other 3 to deal exactly 9 damage. Borrowing 3 leaves too little ether; borrowing 5 heals the enemy above lethal; borrowing 6 kills you.

**Tempting alternatives checked**

- Take the smaller loan
- Take the larger survivable loan
- Kill the rat before borrowing

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Точная цена — Здоровье как ресурс**

Адепт кинетов (Lv 4) / Воин хаотов (Lv 4)

Начального эфира хватает только на Эфирную Торговлю. Но чем больше вы занимаете, тем больше здоровья получает враг. Найдите точную смертельную комбинацию за этот ход.

1. Считайте от итогового состава могильника, а не от наибольшей доступной силы заклинания.
2. Третье существо в могильнике врага позволит Пылающим Могилам нанести девять урона. На два оставшихся заклинания нужно четыре эфира, а у врага сначала пять здоровья.
3. Используйте Эфирную Торговлю с X = 4, убейте Вонючую крысу Молнией и примените Пылающие Могилы.

Четыре здоровья дают ровно четыре эфира и поднимают здоровье врага с пяти до девяти. Молния за один квант добавляет третье существо в его могильник, а Пылающие Могилы тратят оставшиеся три и наносят ровно девять урона. При X = 3 не хватает эфира; при X = 5 у врага остаётся слишком много здоровья; при X = 6 ваш герой погибает.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_exact_price`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "CHNL",
    "kind": "cast",
    "power": 4,
    "target": -1
  },
  {
    "card": "CLIG",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "BRGR",
    "kind": "cast",
    "target": -1
  }
]
```

</details>

### 7. Borrowed Tomorrow

**Medium · Win · Pale revival and haste**

**Matchup:** Kinet adept (Lv 4) / Synthet adept (Lv 4).

Win this turn with no creatures of your own. The enemy has a Knight and a wall in play, and three very different creatures in the graveyard. Your five ether must do all the work.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 5 / 20 | 4 | None |
| Opponent | `BlackMale1` | 4 | 3 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. You need removal and an attacker from the same spell.
2. Pale Revival can consume an enemy in the Colourless Plane and take a creature from either graveyard. The strongest printed creature may not attack immediately.
3. Dissipate the enemy Knight, use Pale Revival on it to raise the enemy Maxi Hopper, then Unsummon the wall and attack with the Hopper.

**Solution and reason**

Dissipate moves the enemy Knight into the Colourless Plane for one ether. Pale Revival then destroys it and raises the enemy graveyard's Maxi Hopper under your control. Haste lets the Hopper attack immediately for exactly three; Unsummon removes the remaining wall. Reviving the eight-power Knight instead produces a sick creature in pale aspect, while the Mech Worm cannot deal enough damage. Blasting first wastes the ether needed to remove the wall.

**Tempting alternatives checked**

- Revive the largest printed creature
- Return the Knight to hand instead of moving it into the Plane
- Start by damaging the Knight with Blast

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Одолженное завтра — Бесцветное оживление и готовность**

Адепт кинетов (Lv 4) / Адепт синтетов (Lv 4)

Победите за этот ход, не имея своих существ. У врага на поле Рыцарь и стена, а на кладбище — три совсем разных существа. На весь план есть пять единиц эфира.

1. Одно заклинание должно убрать врага и одновременно дать вам атакующего.
2. Бесцветное Оживление может уничтожить врага в Бесцветном Плане и взять существо из любого могильника. Самое сильное существо не обязательно сможет атаковать сразу.
3. Примените Растворение к вражескому Рыцарю, затем Бесцветное Оживление — и поднимите Большого прыгуна из могильника врага. Развоплощением верните стену в руку и атакуйте Прыгуном.

Растворение за квант эфира отправляет вражеского Рыцаря в Бесцветный План. Бесцветное Оживление уничтожает его и поднимает под вашим контролем Большого прыгуна из могильника противника. Благодаря готовности Прыгун сразу атакует и наносит ровно три урона; оставшуюся стену нужно вернуть в руку Развоплощением. Рыцарь с силой восемь появится неготовым к атаке и в Бесцветном Плане, а Механическому червяку не хватит силы. Начальный Бесцветный Удар тратит эфир, необходимый для стены.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_borrowed_tomorrow`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "BNSH",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "ORFT",
    "grave": 1001,
    "kind": "cast",
    "target": 2
  },
  {
    "card": "UNSM",
    "kind": "cast",
    "target": 3
  },
  {
    "id": 4,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 8. Chain of Custody

**Medium · Control · Control and retained auras**

**Matchup:** Kinet adept (Lv 4) / Vital warrior (Lv 4).

Finish this turn controlling both the wounded Cutter Man and Razor Man, with both still alive. The Cutter originally belonged to you. Two enemy army enchantments keep the captives stronger than their printed bodies.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 8 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 30 / 30 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"targets": [4, 5], "type": "control"}`.

**Hint progression**

1. Your two Pale casters do different things with an enchantment: one refunds it, the other returns it as a card.
2. Both woodland auras cost four, but removing their toughness bonus kills the wounded captives. Changing control preserves the army auras they already carry.
3. Absorb Strength of Woods. Transpose Change of Command from the Cutter, returning it to you and placing the spell in your hand. Cast that recovered Change of Command on the Razor Man.

**Solution and reason**

Absorbing Strength of Woods spends one ether and refunds four, raising your pool from nine to twelve. Endurance of the Woods must remain: both captives have lethal damage without its two toughness. Transposition costs seven, removes the enemy's Change of Command, and gives you that card. The Cutter returns to its original owner while retaining the endurance aura; the remaining five ether captures the Razor Man. Absorbing the command instead loses the only control spell, while transposing a woodland aura gives the wrong card.

**Tempting alternatives checked**

- Refund the toughness aura instead of the power aura
- Absorb the control spell instead of recovering its card
- Transpose Strength of Woods

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Цепочка подчинения — Переподчинение и сохранённые ауры**

Адепт кинетов (Lv 4) / Воин виталов (Lv 4)

До конца этого хода возьмите под контроль раненых Раскройщика и Потрошителя, сохранив обоих в живых. Раскройщик изначально принадлежал вам. Две чары на вражеском герое усиливают его армию.

1. Два ваших бесцветных мага по-разному используют чужие чары: один возвращает эфир, другой — само заклинание.
2. Обе лесные ауры стоят четыре, но снятие прибавки к стойкости убьёт раненых пленников. При смене стороны существо сохраняет уже действующие на него ауры армии.
3. Чароедом поглотите Силу Леса. Ловкачом снимите Переподчинение с Раскройщика и получите его карту. Раскройщик вернётся к вам; полученное Переподчинение примените к Потрошителю.

Поглощение Силы Леса тратит один эфир и возвращает четыре: запас растёт с девяти до двенадцати. Стойкость Леса должна остаться: без её прибавки в два пункта раны обоих пленников станут смертельными. Способность Ловкача стоит семь, снимает Переподчинение и даёт вам его карту. Раскройщик возвращается к исходному владельцу, сохраняя ауру стойкости; оставшихся пяти единиц эфира хватает на Потрошителя. Если поглотить само Переподчинение, вы потеряете единственный способ захватить второго пленника. Снятие лесной ауры Ловкачом даст не ту карту.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_chain_of_custody`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "choice": 3,
    "id": 2,
    "key": "absorb",
    "kind": "ability",
    "target": 1
  },
  {
    "choice": 1,
    "id": 3,
    "key": "transpose",
    "kind": "ability",
    "target": 4
  },
  {
    "card": "CHCM",
    "kind": "cast",
    "target": 5
  }
]
```

</details>

### 9. Beneath the Numbers

**Medium · Clear · Printed strength and specialist removal**

**Matchup:** Vital warrior (Lv 4) / Kinet adept (Lv 4).

Clear the enemy army this turn. Your hero has only three health. Twister hurts the attacking hero according to its victim's strength without the victim's own enchantments.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `GreenMale1` | 4 | 3 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 40 / 40 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "clear"}`.

**Hint progression**

1. The visually weakest enemy is not the safest Twister target.
2. Your dragons already have answers to a flying body and a wall. Keep the spell for the remaining kind of threat.
3. Twister the blessed Treant, whose printed power is one. Use the Blue Dragon's breath on the weakened Maggot and the Green Dragon's wall-breaking ability on the Wall of Force.

**Solution and reason**

Twister ignores Bless when calculating its recoil, so the five-power Treant costs only one hero health and cannot regenerate. The Maggot displays zero power, but its unenchanted power is three: Twister would kill you. Blue Dragon breath handles it without recoil, and Green Dragon removes the wall. Using Twister on the wall is safe for your health but leaves no way to clear the regenerating ground creature this turn.

**Tempting alternatives checked**

- Twister the enemy displaying zero power
- Spend Twister on the wall to avoid all recoil

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Под маской чисел — Базовая сила и точечное устранение**

Воин виталов (Lv 4) / Адепт кинетов (Lv 4)

Уничтожьте вражескую армию за этот ход. У вашего героя всего три жизни. Смерч ранит атакующего героя согласно силе жертвы без её собственных чар.

1. Враг с самыми низкими видимыми характеристиками — не самая безопасная цель для Смерча.
2. У драконов уже есть ответы на летающее существо и стену. Сохраните заклинание для угрозы другого типа.
3. Примените Смерч к благословлённому Молодому древню: его базовая сила равна единице. Дыханием Синего дракона убейте ослабленного Маггота, а способностью Зелёного дракона уничтожьте Стену силы.

При вычислении отдачи Смерч не учитывает Благословение. Поэтому древень с силой пять отнимет лишь одну жизнь и не сможет регенерировать. У Маггота показана нулевая сила, но без собственных чар она равна трём: его уничтожение Смерчем убьёт вашего героя. Дыхание Синего дракона устраняет Маггота без отдачи, а Зелёный дракон разбирает стену. Смерч по стене безопасен для героя, но оставляет регенерирующее наземное существо без подходящего ответа.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_beneath_the_numbers`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "TWST",
    "kind": "cast",
    "target": 4
  },
  {
    "id": 2,
    "key": "breath",
    "kind": "ability",
    "target": -1
  },
  {
    "id": 3,
    "key": "wall_break",
    "kind": "ability",
    "target": 6
  }
]
```

</details>

### 10. The Smaller Well

**Medium · Survive · Siphoning without losing the defender**

**Matchup:** The Azure Adept (Lv 8) / The Winged Regent (Lv 12).

Survive one enemy turn, preserve both Halos, and finish with at least fifteen health. Your level-8 hero's maximum is 31; Healing restores health to half that maximum. The enemy has six ether but no channels.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 8 | 2 / 31 | 4 | None |
| Opponent | `BlueWingedFemale1` | 12 | 30 / 43 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"enemy_turns": 1, "finish_health": 15, "protect": [2, 3], "type": "survive"}`.

**Hint progression**

1. Taking the larger amount of ether is not free: the siphoning Halo must rest.
2. Only one of your two flyers can take a five-power hit and stay alive. Healing needs just four ether.
3. Siphon with the Sea Halo and spend its four ether on Healing. Keep the Swamp Halo ready to block the Giant Bat.

**Solution and reason**

The Sea Halo draws four of the enemy's six ether. Healing sets your health to floor(31/2), which is fifteen. The ready Swamp Halo survives the Giant Bat's five damage and preserves that total. Siphoning with the Swamp Halo gives more ether but leaves the fragile Sea Halo as the only blocker. Energy Barrier reduces non-combat damage, so it cannot save that Halo or preserve your finishing health against this attack.

**Tempting alternatives checked**

- Take six ether with the Swamp Halo
- Spend the smaller siphon's ether on Energy Barrier

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Меньший источник — Отбор эфира с сохранением защитника**

Лазурный адепт (Lv 8) / Крылатая правительница (Lv 12)

Переживите один вражеский ход, сохраните обоих нимбов и завершите задачу хотя бы с пятнадцатью жизнями. Максимум героя 8-го уровня — 31; Лечение восстанавливает здоровье до половины этого значения. У врага шесть единиц эфира и ни одного канала.

1. Больший запас эфира имеет цену: использовавший способность нимб должен отдыхать.
2. Только один из ваших двух летающих защитников переживёт удар силой пять. Для Лечения достаточно четырёх единиц эфира.
3. Заберите четыре эфира Морским нимбом и потратьте их на Лечение. Болотного нимба оставьте готовым для блока Гигантской летучей мыши.

Морской нимб забирает четыре из шести единиц вражеского эфира. Лечение поднимает здоровье до половины 31 с округлением вниз — пятнадцати. Готовый Болотный нимб выдерживает пять урона от Гигантской летучей мыши и сохраняет здоровье героя. Его собственная способность даст больше эфира, но оставит в защите лишь хрупкого Морского нимба. Энергетический Барьер уменьшает только небоевой урон: в этом бою он не спасёт ни нимба, ни требуемый запас здоровья.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_smaller_well`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "id": 2,
    "key": "siphon",
    "kind": "ability",
    "target": 1
  },
  {
    "card": "HEAL",
    "kind": "cast",
    "target": 0
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 4,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 3,
    "kind": "block",
    "target": 4
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 11. Plan the Second Attack

**Hard · Win · Recovery and counterplay**

**Matchup:** Kinet adept (Lv 4) / Chaot warrior (Lv 4).

Win in two turns. Your channels are empty, so any ether left over will be lost when your next turn begins. The Gibberling cannot recover normally, and the Shaman can shoot during defence.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 4 / 20 | 4 | None |
| Opponent | `RedMale4` | 4 | 9 / 20 | 3 | None |

Own-turn budget: **2**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. The opening attack needs three different kinds of preparation: enough damage, a second attack, and a living attacker.
2. A larger attack fails if the Shaman kills it; a protected attack fails if it rests forever. Commit the ether before your pool refills to zero.
3. Put Might, Spirit of War, and Shell Skin on the Gibberling Instigator. Attack with it on both turns. Keep the Hopper back to block the Great Treant if it attacks.

**Solution and reason**

Might gives the unblockable Instigator 6 power, Shell Skin keeps it safe from the Shaman, and Spirit of War prevents it resting after its first attack despite its inability to recover. All 6 ether must be spent in advance: the next refill is zero. The Hopper is a reserve defender; losing it is preferable to losing the two-turn plan.

**Tempting alternatives checked**

- Give the damage bonus to the Hopper
- Spend protection ether weakening the Treant
- Attack before investing in the second turn

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**План второй атаки — Повторная атака и ответ врага**

Адепт кинетов (Lv 4) / Воин хаотов (Lv 4)

Победите за два хода. Каналов нет: в начале следующего хода оставшийся эфир обнулится. Гибберлин не поднимается обычным способом, а Шаман может стрелять в фазе защиты.

1. Первая атака требует сразу трёх приготовлений: достаточной силы, возможности повторной атаки и живого атакующего.
2. Сильная атака бесполезна, если Шаман убьёт её участника. Защищённый участник бесполезен, если останется отдыхать навсегда. Потратьте эфир до обнуления запаса.
3. Наложите Мощь, Дух Войны и Ледяной Панцирь на Гибберлина-подстрекателя. Атакуйте им в оба хода. Прыгуна оставьте для блокирования Старого древня, если тот пойдёт в атаку.

Мощь даёт неблокируемому Подстрекателю шесть силы. Ледяной Панцирь спасает его от Шамана, а Дух Войны делает неутомимым: после первой атаки Гибберлин не уходит на отдых, несмотря на неспособность самостоятельно подняться. Все шесть квантов нужно потратить заранее — следующее пополнение даст ноль. Прыгун остаётся резервным защитником: лучше потерять его, чем сорвать план двух атак.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_second_attack`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "MGHT",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "SHSK",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "SPWR",
    "kind": "cast",
    "target": 2
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 4,
    "key": "sting",
    "kind": "ability",
    "side": 1,
    "target": 2
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 3,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 12. The Smaller Refund

**Hard · Win · Enchantment economy and counterplay**

**Matchup:** Vital warrior (Lv 4) / Kinet adept (Lv 4).

The Spelleater can turn an enchantment into ether. The enemy holds Fog and has two ether. Win this turn against both blockers, without opening a defensive escape.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `GreenMale1` | 4 | 8 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 1 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. The largest refund can also make the enemy's hand affordable.
2. Greater Sorcery Warding doubles both Bless and Fog. Your Knight needs fifteen power to beat the combined blockers, but the enemy must remain unable to cast Fog.
3. Absorb Greater Enchantment Warding from your hero. Spend the resulting four ether on Bless for the Knight, leaving Greater Sorcery Warding in play; then attack.

**Solution and reason**

Absorbing the three-cost enchantment ward costs one and refunds three, taking your ether from two to four. The sorcery ward stays in play: Bless costs exactly four and raises the Knight to fifteen power, while Fog still costs four, more than the enemy has. Even both blockers together provide only fourteen toughness, so trample deals the final damage. Absorbing the four-cost sorcery ward gives more ether but makes Fog affordable. Absorbing Might removes the power your Knight needs. Manifesting the Spelleater gives another attacker but neither enough damage nor the ether for Bless.

**Tempting alternatives checked**

- Take the largest refund by absorbing Greater Sorcery Warding
- Absorb the Knight's Might instead
- Manifest for free instead of converting the ward into ether

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Меньший возврат — Экономия чар и ответ противника**

Воин виталов (Lv 4) / Адепт кинетов (Lv 4)

Бесцветный Чароед умеет превращать чары в эфир. У противника в руке Туман и две единицы эфира. Победите за этот ход, пройдя обоих защитников и не позволив врагу спастись заклинанием.

1. Самый большой возврат эфира может сделать доступным и заклинание противника.
2. Великая защита от колдовства удваивает цену и Благословения, и Тумана. Рыцарю нужно пятнадцать силы против обоих защитников, но Туман должен остаться недоступным врагу.
3. Поглотите Великую защиту от чар на своём герое. Потратьте полученные четыре эфира на Благословение Рыцаря, сохранив защиту от колдовства, и атакуйте.

Поглощение защиты от чар стоимостью три сначала тратит единицу эфира, затем возвращает три: запас растёт с двух до четырёх. Защита от колдовства остаётся. Благословение стоит ровно четыре и поднимает силу Рыцаря до пятнадцати, а Туман тоже стоит четыре — больше, чем есть у врага. Суммарная стойкость защитников равна четырнадцати, поэтому избыточный урон Рыцаря проходит герою. Поглощение более дорогой защиты от колдовства даёт больше эфира, но открывает врагу Туман. Поглощение Мощи лишает Рыцаря необходимой силы.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_smaller_refund`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "choice": 1,
    "id": 2,
    "key": "absorb",
    "kind": "ability",
    "target": 0
  },
  {
    "card": "BLSS",
    "kind": "cast",
    "target": 3
  },
  {
    "id": 3,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 4,
    "kind": "block",
    "side": 1,
    "target": 3
  },
  {
    "id": 5,
    "kind": "block",
    "side": 1,
    "target": 3
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 13. The Last Layer

**Hard · Win · Enchantment order and recycling**

**Matchup:** Kinet adept (Lv 4) / White Lord (Lv 4).

Win this turn without an army. The enemy's Spelleater and wounded Scourge are both in the Ether. You have one Lock Aspect, two Marks of Pale, and two Blasts.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 5 / 20 | 4 | None |
| Opponent | `White Lord I` | 4 | 6 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. Preventing dissipation is only useful if the prevention survives until the damage happens.
2. Blast removes the newest removable enchantment before dealing three damage. Lock Aspect returns when its creature leaves play, but a cover removed by Blast does not.
3. Lock the Spelleater, cover the lock with Mark of Pale, then Blast it. Reuse the returned Lock Aspect on the wounded Scourge, add your second Mark, and use the second Blast.

**Solution and reason**

Lock Aspect prevents a Pale creature from dissipating and deals its printed power to its owner when it leaves play. Blast alone would remove the lock before dealing damage, so cast Mark of Pale afterwards as the newest layer. Blast strips that mark, restoring the target's original toughness, then kills it while the lock remains. Its three-power backlash damages the hero and returns Lock Aspect to your hand. Repeat with the wounded Scourge using the second Mark and Blast for the remaining three damage. The removed covers do not return; the one binding does. Independent target order is allowed.

**Tempting alternatives checked**

- Blast immediately after Lock Aspect
- Put the lock on top of its cover
- Spend the first Blast on an unbound creature

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Последний слой — Порядок чар и повторное использование**

Адепт кинетов (Lv 4) / Белый Лорд (Lv 4)

Победите за этот ход без собственной армии. Вражеские Чароед и раненый Жнец находятся в Эфирном Плане. У вас одни Эфирные Узы, два Клейма Бесцветности и два Бесцветных Удара.

1. Запрет перехода в Бесцветный План полезен лишь тогда, когда действует в момент нанесения урона.
2. Бесцветный Удар снимает самые свежие доступные чары, а затем наносит три урона. Эфирные Узы возвращаются при уходе носителя; снятое Ударом прикрытие не возвращается.
3. Наложите Эфирные Узы на Чароеда, поверх них — Клеймо Бесцветности, затем Бесцветный Удар. Вернувшиеся Узы наложите на раненого Жнеца, добавьте второе Клеймо и второй Удар.

Эфирные Узы не дают бесцветному существу уйти в Бесцветный План и при уходе носителя наносят его владельцу урон, равный базовой силе. Бесцветный Удар сначала снял бы сами Узы, поэтому их нужно прикрыть более новым Клеймом Бесцветности. Удар снимает Клеймо, возвращает исходную стойкость и убивает существо под действующими Узами. Владелец получает три урона, а Узы возвращаются вам в руку. Повторите на раненом Жнеце со вторым Клеймом и вторым Ударом. Прикрытия расходуются, но одних Уз хватает на обе цели; порядок целей свободный.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_last_layer`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "PRBN",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "ALNS",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "OBLS",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "PRBN",
    "kind": "cast",
    "target": 3
  },
  {
    "card": "ALNS",
    "kind": "cast",
    "target": 3
  },
  {
    "card": "OBLS",
    "kind": "cast",
    "target": 3
  }
]
```

</details>

### 14. The Last Line of Defence

**Hard · Clear · Defensive resource allocation**

**Matchup:** Chaot warrior (Lv 4) / Kinet adept (Lv 4).

Clear the attacking army while keeping your Wall of Lava and Fire Elemental alive. Martyrdom is already active. You have three ether. The enemy Ogre and Tick Warrior both carry Spirit of the Basilisk: any creature they wound in combat is doomed.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `RedMale4` | 4 | 3 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 40 / 40 | 4 | None |

Own-turn budget: **1**. Objective metadata: `{"protect": [2, 3], "type": "clear"}`.

**Hint progression**

1. Budget for three different jobs: remove an attacker, strengthen a blocker, and reach an exact damage threshold.
2. The resting Cutter can contribute its full power and toughness without waking up. The wall must handle the flying Dragon; your Elemental can kill a poisonous attacker before it deals a wound.
3. Use Martyrdom to sacrifice the Cutter into the Wall of Lava. Polymorph one of the two poisonous ground attackers. Spend one ether on the wall's power ability, then block the Dragon with the wall and the remaining ground attacker with your Elemental.

**Solution and reason**

Martyrdom spends one ether to turn the wall from 1/8 into 8/12 using the Cutter's 7/4 body. One more ether makes the wall 9/12, enough to kill the 8/9 Black Dragon and survive. Polymorph removes one poisonous ground attacker; your own Fire Elemental first-strikes the other before receiving a lethal wound. Either ground creature is a valid spell target. Removing the Dragon instead leaves two poisonous attackers, and the wall cannot survive a wound from either. All three ether have distinct jobs: sacrifice, transformation, and the final point of power.

**Tempting alternatives checked**

- Polymorph the largest attacker
- Combine the Cutter into your Fire Elemental
- Spend the entire pool on the wall's power

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Последний рубеж — Распределение ресурсов в защите**

Воин хаотов (Lv 4) / Адепт кинетов (Lv 4)

Уничтожьте атакующую армию, сохранив Стену лавы и своего Элементаля огня. Самопожертвование уже действует. У вас три единицы эфира. На вражеских Огре и Клеще-воине лежит «Призрак Василиска»: любое существо, которое они ранят в бою, обречено.

1. Эфир нужен для трёх разных задач: убрать атакующего, усилить защитника и достичь точного порога урона.
2. Отдыхающий Раскройщик может передать всю свою силу и стойкость, не просыпаясь. Стена должна встретить летающего дракона, а Элементаль — убить ядовитого атакующего первым ударом, не получив раны.
3. Самопожертвованием передайте характеристики Раскройщика Стене лавы. Превратите одного из двух ядовитых наземных атакующих. За последний эфир увеличьте силу стены на один; ею блокируйте дракона, а Элементалем — оставшегося наземного атакующего.

Самопожертвование за один эфир прибавляет к стене 1/8 характеристики Раскройщика 7/4: получается 8/12. Ещё один эфир поднимает силу до девяти, чтобы убить Чёрного дракона 8/9 и пережить его удар. Превращение убирает одного ядовитого наземного врага; Элементаль огня первым ударом уничтожает второго до ответной раны. Превратить можно любого из них. Если убрать дракона, останутся два ядовитых врага, а стена не переживёт рану ни от одного. Каждый квант эфира решает отдельную задачу: жертва, превращение и последний пункт силы.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_last_line_of_defence`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "choice": 2,
    "id": 0,
    "key": "combine:1",
    "kind": "ability",
    "target": 4
  },
  {
    "card": "PLMR",
    "kind": "cast",
    "target": 6
  },
  {
    "amount": 1,
    "id": 2,
    "key": "lava_power",
    "kind": "ability",
    "target": -1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 5
  },
  {
    "id": 3,
    "kind": "block",
    "target": 7
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 15. Every Road Hurts

**Hard · Win · Forced blocks and a response window**

**Matchup:** Synthet adept (Lv 4) / Kinet adept (Lv 4).

Win this turn against every arrangement of the two blockers. The Pteros has enough ether to remove Pain Link during defence. The Assassin can only be blocked by the wall.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlackMale1` | 4 | 8 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 7 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. You need both attackers. Nine trample damage alone has a defensive answer, and the Assassin alone is too small.
2. Make the wall painful to use, then make sure that enchantment survives the defender's action window.
3. Irritate the Pteros, put Pain Link on the Wall of Force, and attack with both creatures. Even a double block ordered Pteros first, wall second leaves five linked damage plus two from the Assassin.

**Solution and reason**

Irritation prevents the Pteros from using its dispel, preserving Pain Link. With both attackers declared, the defender cannot avoid seven damage. A wall block on the Assassin deals two through Pain Link and leaves at least five trample damage from the Horror. Blocking the Horror with the Pteros first and then the wall absorbs four before the wall takes five; the unblocked Assassin supplies the other two. A lone Pteros block also lets five trample damage through. Pain Link on the Pteros instead can be avoided by putting the wall in front of the Horror.

**Tempting alternatives checked**

- Put Pain Link on the smaller blocker
- Suppress the wall rather than the dispeller
- Spend one ether on immediate hero damage

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Цена каждой преграды — Вынужденная защита и окно ответа**

Адепт синтетов (Lv 4) / Адепт кинетов (Lv 4)

Победите за этот ход при любом распределении двух защитников. У Птероса достаточно эфира, чтобы снять Болевую Связь во время защиты. Авиака-убийцу может блокировать только стена.

1. Нужны оба атакующих. От девяти единиц избыточного урона можно защититься, а одного авиака слишком мало.
2. Сделайте использование стены болезненным и позаботьтесь, чтобы эти чары пережили окно ответных действий врага.
3. Раздражением отключите способность Птероса, наложите Болевую Связь на Стену силы и атакуйте обоими. Даже если Птерос блокирует Ужас первым, а стена второй, пять урона через связь и два от авиака решат бой.

Раздражение лишает Птероса способности снять Болевую Связь. При атаке обоими существами враг не может избежать семи урона. Блок авиака стеной даёт два урона через связь, а Птерос пропускает ещё пять избыточного урона Ужаса. Если поставить Птероса перед Ужасом первым, а стену второй, Птерос поглотит четыре, стене достанется пять, а неблокированный авиак нанесёт ещё два. Один Птерос тоже пропускает пять. Если связать Птероса вместо стены, враг может безболезненно остановить Ужас стеной.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_every_road_hurts`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "IRRT",
    "kind": "cast",
    "target": 5
  },
  {
    "card": "PALN",
    "kind": "cast",
    "target": 4
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "id": 3,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 5,
    "kind": "block",
    "side": 1,
    "target": 2
  },
  {
    "id": 4,
    "kind": "block",
    "side": 1,
    "target": 2
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 16. A Three-Turn Lock

**Hard · Win · Denial, upkeep and reserve defence**

**Matchup:** Kinet adept (Lv 4) / Chaot warrior (Lv 4).

Win within three turns. Your Assassin needs repeated attacks. The enemy's five channels would fund Fog and Lightning, and its Shaman can remove an enchantment without spending ether. Your own channels are empty.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 3 / 20 | 4 | None |
| Opponent | `RedMale4` | 4 | 8 / 20 | 3 | None |

Own-turn budget: **3**. Objective metadata: `{"protect": [2], "type": "win"}`.

**Hint progression**

1. Deny the enemy its next refill, but first account for the creature that can remove that denial.
2. The last two ether are an upkeep reserve. Spending them on a tempting extra spell releases the lock one enemy turn too soon.
3. Irritate the Shaman and cast Stasis, retaining two ether. Attack with the Assassin on all three turns. Keep the wall for the Treant; the Shaman's two one-point attacks can be endured. The first Stasis upkeep is paid, and the later expiry occurs after the last enemy refill you need to prevent.

**Solution and reason**

Irritation disables the Shaman's channel-sacrificing dispel and deals one damage to its hero at each enemy turn end. Stasis holds both ether pools at their current values. Keeping two ether pays the first upkeep, so the enemy remains unable to cast either defensive card through the second attack and following turn. The next upkeep cannot be paid, but the enemy is still at zero during your final attack. Three two-point Assassin hits plus two Irritation triggers total eight. The wall stops the Treant, and your three health tolerates the Shaman's two attacks.

**Tempting alternatives checked**

- Suppress the Treant instead of the Shaman
- Spend the upkeep reserve weakening the Treant
- Invest in Fog before creating the lock

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Три хода Стазиса — Блокада эфира и запас на содержание**

Адепт кинетов (Lv 4) / Воин хаотов (Lv 4)

Победите за три хода. Авиаку придётся атаковать несколько раз. Пять каналов врага обеспечили бы Туман и Молнию, а его шаман умеет снимать чары без затрат эфира. У вас нет своих каналов.

1. Остановите следующее пополнение вражеского эфира, но сначала разберитесь с существом, которое способно снять эту блокаду.
2. Последние две единицы эфира нужны на содержание Стазиса. Лишнее заклинание снимет блокаду на один вражеский ход раньше, чем нужно.
3. Наложите Раздражение на шамана и Стазис на своего героя, оставив два эфира. Атакуйте авиаком на каждом из трёх ходов. Стеной прикрывайте древня; два удара шамана по единице можно принять. Первое содержание оплачивается, а последующее снятие Стазиса происходит уже после последнего опасного пополнения врага.

Раздражение отключает обряд шамана и в конце каждого вражеского хода наносит его герою единицу урона. Стазис сохраняет текущие запасы эфира вместо обычного пополнения. Два оставленных эфира оплачивают первое содержание: враг не может применить свои карты во время второй атаки и следующего хода. Второе содержание уже не оплачивается, но к вашей последней атаке у врага всё ещё ноль эфира. Три удара авиака по два и два срабатывания Раздражения дают ровно восемь. Стена останавливает древня, а три жизни позволяют пережить два удара шамана.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_three_turn_lock`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "IRRT",
    "kind": "cast",
    "target": 4
  },
  {
    "card": "STSI",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 4,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 3,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 4,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 3,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 17. The Third Funeral

**Hard · Win · Burial order and delayed reinforcements**

**Matchup:** Synthet adept (Lv 4) / Vital warrior (Lv 4).

Win in two turns and keep your Orc Shaman alive. Both Alpha Strikes expire at the end of the enemy's next turn. A Maxi Hopper lies beneath one card in your graveyard; it returns at your turn end only after three newer burials.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlackMale1` | 4 | 4 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 17 / 20 | 3 | None |

Own-turn budget: **2**. Objective metadata: `{"protect": [5], "type": "win"}`.

**Hint progression**

1. The first attack and the finishing attack need different bodies. Reconstruct the graveyard before committing either.
2. A regeneration that seems to save an ally can spend the only ether needed for Polymorph. The Horror's departure also forces the enemy to spend its last ether regenerating.
3. Use the Shaman's rite to remove Irritation from the Cutter. Polymorph your resting, fragile Treant before the Horror dies. Then let the Cutter sacrifice the Horror and attack for fourteen. The Hopper returns at turn end; use your reserve to block the compelled Treant attack, then finish with the Hopper.

**Solution and reason**

The Shaman spends your channel to free the Cutter's sacrifice ability. Polymorph kills your own Treant without regeneration, preserving the sequence and adding the second newer grave card. The Cutter sacrifices the Horror, wakes up, and the third newer burial qualifies the Hopper to return at turn end. Energy Barrier keeps the Cutter's one-toughness Alpha Strike body alive through the Horror's wave. The enemy Treant must regenerate, spending the ether that would otherwise fund defensive Polymorph. The Cutter deals fourteen, then expires after the enemy turn; the returned Hopper supplies the final three. Fury forces the enemy Treant to commit, creating the finishing opening.

**Tempting alternatives checked**

- Release the Horror's wave before spending the Polymorph ether
- Polymorph the enemy Treant instead of your own
- Remove Energy Barrier instead of Irritation

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Третьи похороны — Порядок погребений и позднее подкрепление**

Адепт синтетов (Lv 4) / Воин виталов (Lv 4)

Победите за два хода и сохраните Орка-шамана. Обе Альфа-атаки закончатся в конце следующего вражеского хода. Большой прыгун лежит под одной картой в вашем могильнике и вернётся в конце вашего хода лишь после трёх более поздних погребений.

1. Первый удар и добивание должны выполнить разные существа. Восстановите будущий порядок могильника до начала атаки.
2. Регенерация, которая кажется спасением союзника, может потратить единственный эфир для Превращения. Уход Ужаса также заставит врага потратить последний эфир на собственную регенерацию.
3. Обрядом шамана снимите Раздражение с Раскройщика. Превратите своего отдыхающего хрупкого древня до смерти Ужаса. Затем Раскройщиком пожертвуйте Ужасом и атакуйте на четырнадцать. Прыгун вернётся в конце хода; заблокируйте вынужденную атаку древня резервом, а затем добейте врага Прыгуном.

Шаман жертвует каналом, снимая запрет на способность Раскройщика. Превращение убивает вашего древня без регенерации и кладёт вторую новую карту поверх Прыгуна. Раскройщик жертвует Ужасом и просыпается; третье новое погребение позволит Прыгуну вернуться в конце хода. Энергетический Барьер защищает однопунктовую стойкость Раскройщика от прощальной волны Ужаса. Вражеский древень обязан регенерировать, тратя эфир, которым враг мог бы оплатить защитное Превращение. Раскройщик наносит четырнадцать и погибает после вражеского хода; вернувшийся Прыгун добавляет последние три. Бешенство заставляет вражеского древня атаковать и открывает путь для добивания.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_third_funeral`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "choice": 4,
    "id": 5,
    "key": "orc_rite",
    "kind": "ability",
    "target": 2
  },
  {
    "card": "PLMR",
    "kind": "cast",
    "target": 4
  },
  {
    "id": 2,
    "key": "sacrifice",
    "kind": "ability",
    "target": 3
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 8,
    "kind": "block",
    "target": 6
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 8,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 18. A Shared Escape

**Hard · Control · Capture and a counterspell window**

**Matchup:** Kinet adept (Lv 4) / Vital warrior (Lv 4).

Control the enemy Pale Knight after one complete enemy turn. Keep your Spelleater alive. Transfer Aspects and an enemy Aspect Ward are already on your hero; the opponent holds Polymorph.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 4 | 2 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 30 / 30 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"enemy_turns": 1, "protect": [2], "targets": [4], "type": "control"}`.

**Hint progression**

1. Both your new captive and your protected helper must survive an enemy spell window.
2. Removing Aspect Ward must leave the Spelleater ready. A manifestation through Transfer Aspects does not rest it.
3. Use Lesser Disenchant on Aspect Ward, capture the Knight, and exchange its aspect with the Spelleater. Dissipate the still-ready Spelleater. Keep the Iron Mechozaurus to stop the Ogre.

**Solution and reason**

Lesser Disenchant removes the ward for two ether. Change of Command costs five, and Transfer Aspects uses the last ether to manifest your Spelleater while sheltering the sick captive in the Colourless Plane. The Spelleater must then dissipate itself. Absorbing the ward would refund its cost but rest the only helper that still needs to escape Polymorph. Energy Barrier reduces the Mechozaurus's four upkeep damage to one, leaving your hero alive. The untargetable Mechozaurus can stop the Ogre while both Pale creatures remain safe through the enemy turn.

**Tempting alternatives checked**

- Absorb the ward for its refund
- Exchange aspects before capturing the Knight
- Capture the Ogre instead of the Knight

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Путь для двоих — Захват и ответное заклинание**

Адепт кинетов (Lv 4) / Воин виталов (Lv 4)

После завершения одного вражеского хода управляйте Бесцветным Рыцарем противника. Сохраните своего Чароеда. На вашем герое уже действуют Обмен Планами и вражеский Планарный Барьер; противник держит Превращение.

1. Ответное заклинание должны пережить и новый пленник, и защищаемый помощник.
2. После снятия Планарного Барьера Чароед должен остаться готовым к действию. Обмен Планами сам по себе не отправляет его отдыхать.
3. Снятием Чар уберите Планарный Барьер, переподчините Рыцаря и обменяйте его план с Чароедом. Затем готовым Чароедом уйдите обратно в Бесцветный План. Железного мехозавра оставьте для блока людоеда.

Снятие Чар убирает барьер за два эфира. Переподчинение стоит пять, а последний эфир оплачивает Обмен Планами: Чароед выходит в Эфирный План, а ещё не готовый к действиям пленник скрывается в Бесцветном. Чароед должен сразу уйти следом. Если поглотить барьер, его стоимость вернётся, но Чароед начнёт отдыхать и уже не сможет спастись от Превращения. Энергетический Барьер уменьшает четыре урона от содержания мехозавра до одного, сохраняя жизнь герою. Сам мехозавр недоступен для направленных заклинаний и может остановить людоеда, пока оба бесцветных пережидают вражеский ход.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_shared_escape`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "CLNP",
    "grave": 1,
    "kind": "cast",
    "target": 0
  },
  {
    "card": "CHCM",
    "kind": "cast",
    "target": 4
  },
  {
    "choice": 4,
    "id": 0,
    "key": "recycle:3",
    "kind": "ability",
    "target": 2
  },
  {
    "id": 2,
    "key": "dissipate",
    "kind": "ability",
    "target": -1
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 3,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 19. The Surviving Investment

**Hard · Clear · Channel conversion and delayed income**

**Matchup:** White Lord (Lv 4) / Vital warrior (Lv 4).

Clear the enemy army within two turns and finish with at least four ether. Keep your Pale Slayer alive. You have one channel, no ether, and two Ether Breezes on the enemy Ancient Treant.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `White Lord I` | 4 | 5 / 20 | 4 | None |
| Opponent | `GreenMale1` | 4 | 30 / 30 | 3 | None |

Own-turn budget: **2**. Objective metadata: `{"finish_mana": 4, "protect": [3], "type": "clear"}`.

**Hint progression**

1. The enemy carrying your investment has to remain alive until the next refill.
2. The Channeler can turn a channel into immediate ether; the Slayer can recover the channel by killing a suitable target.
3. Convert the channel, slay the Maggot, and allow the Treant to survive the enemy turn. At your next turn, the recovered channel and both Breezes provide seven ether. Slay the Treant for three and finish with four.

**Solution and reason**

The first conversion funds exactly one use of the Slayer. Killing the Maggot recovers a channel while preserving both three-ether Breeze triggers. The Treant can hit your hero for four, leaving one health, but neither Pale helper needs to enter the bright aspect. Your next refill provides one channel ether plus six from the living Treant. The second slay costs three, leaving the required four. Killing the Treant first destroys the future income; burning another channel then can fund the last kill but cannot meet the finishing reserve.

**Tempting alternatives checked**

- Manifest the Slayer with the only channel
- Slay the creature carrying both investments first
- Spend the converted ether on Stone Skin

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Живой источник дохода — Обмен каналов и отложенное пополнение**

Белый Лорд (Lv 4) / Воин виталов (Lv 4)

Уничтожьте вражескую армию за два хода и завершите задачу хотя бы с четырьмя единицами эфира. Сохраните Бесцветного Убийцу. У вас один канал, пустой запас эфира и два Эфирных Бриза на вражеском Вековом древне.

1. Враг, на котором держится ваш будущий доход, должен дожить до следующего пополнения.
2. Маг превращает канал в немедленный запас эфира, а Убийца может вернуть канал, уничтожив подходящую цель.
3. Превратите канал в эфир, убейте Маггота и оставьте древня в живых на вражеский ход. Затем восстановленный канал и два Бриза дадут семь эфира. Убийство древня стоит три: останется нужный запас в четыре.

Первая жертва канала оплачивает ровно одно применение Убийцы. Уничтожение Маггота возвращает канал и сохраняет оба будущих поступления по три эфира. Древень может нанести герою четыре урона, оставив одну жизнь; ни одному из бесцветных помощников не требуется выходить в Эфирный План. В начале следующего хода канал даёт один эфир, а живой древень — ещё шесть. Второе убийство стоит три и оставляет четыре. Если сначала убрать древня, исчезнет будущий доход. Ещё одна жертва канала позволит оплатить последний удар, но не обеспечит необходимый запас к завершению.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_surviving_investment`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "id": 2,
    "key": "channel_ether",
    "kind": "ability",
    "target": -1
  },
  {
    "id": 3,
    "key": "pale_devour",
    "kind": "ability",
    "target": 4
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 3,
    "key": "pale_devour",
    "kind": "ability",
    "target": 5
  }
]
```

</details>

### 20. Airlock Census

**Hard · Clear · Beacon, dispel access and a body count**

**Matchup:** White Lord (Lv 4) / White Lord (Lv 4).

Clear the enemy army this turn, preserve your Spelleater and Spellshifter, and finish with at least five allied creatures. Paleness sends new summons to the Colourless Plane. Your Spelleater carries Beacon; Shell Skin is your only enchantment currently outside the plane.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `White Lord I` | 4 | 7 / 20 | 4 | None |
| Opponent | `White Lord I` | 4 | 30 / 30 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"min_allies": 5, "protect": [2, 3], "type": "clear"}`.

**Hint progression**

1. Flux counts your non-Pale creatures even when they are in the Colourless Plane, then damages every creature in that plane.
2. Both protected casters must become bright. The Beacon itself is inaccessible to a dispel while its bearer remains in the plane.
3. Summon the Stink Rat. Manifest the Beacon-bearing Spelleater by removing Shell Skin from the wounded Ogre: Beacon brings the Spellshifter along. The Ogre dies, leaving four non-Pale bodies to power Flux.

**Solution and reason**

The new Rat raises the non-Pale count from four to five even though Paleness places it in the Colourless Plane. Removing Shell Skin kills the wounded Ogre and drops that count to four. The bearer must perform Mystic manifestation: Beacon then brings the other caster out as well. Manifesting only the Spellshifter strands the Spelleater, because its Beacon is still in the plane and cannot be dispelled. Flux calculates four damage before applying it; both wounded enemies and the new Rat die. Your five survivors are the Spelleater, Spellshifter, Tick Warrior, Scout and wall. Absorbing Shell Skin produces ether but consumes the only accessible enchantment without opening the airlock.

**Tempting alternatives checked**

- Manifest the Spellshifter instead of the Beacon bearer
- Cast Flux while your casters remain in the plane
- Absorb Shell Skin for extra ether

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Перепись у шлюза — Маяк, доступность чар и число созданий**

Белый Лорд (Lv 4) / Белый Лорд (Lv 4)

Уничтожьте армию врага за этот ход, сохраните Чароеда и Ловкача и завершите задачу хотя бы с пятью союзными созданиями. Обесцвечивание отправляет новые создания в Бесцветный План. Чароед несёт Маяк; Ледяной Панцирь — ваши единственные чары вне этого плана.

1. Бесцветный Шторм считает ваши небесцветные создания даже в Бесцветном Плане, а затем наносит урон всем созданиям в этом плане.
2. Оба защищаемых мага должны выйти в Эфирный План. Сам Маяк нельзя снять, пока его носитель остаётся в Бесцветном.
3. Вызовите Вонючую крысу. Выведите Чароеда с Маяком, сняв Панцирь с раненого людоеда: Маяк выведет и Ловкача. Людоед погибнет, оставив четыре небесцветных создания для Бесцветного Шторма.

Новая крыса увеличивает число небесцветных созданий с четырёх до пяти, хотя Обесцвечивание отправляет её в Бесцветный План. Снятие Панциря убивает раненого людоеда, возвращая число к четырём. Выйти должен именно носитель Маяка: тогда следом выйдет второй маг. Если первым вывести Ловкача, Чароед останется заперт: его Маяк ещё находится в Бесцветном Плане и недоступен для снятия. Шторм вычисляет четыре урона до применения: погибают оба раненых врага и новая крыса. Остаются пять союзников — Чароед, Ловкач, Клещ-воин, авиак и стена. Поглощение Панциря даст эфир, но потратит единственные доступные чары, не открыв шлюз.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_airlock_census`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "STRT",
    "kind": "cast",
    "target": -1
  },
  {
    "choice": 3,
    "id": 2,
    "key": "mystic",
    "kind": "ability",
    "target": 4
  },
  {
    "card": "OFLX",
    "kind": "cast",
    "target": -1
  }
]
```

</details>

### 21. The Last Breath

**Hard · Win · Healing order and the final body count**

**Matchup:** Vital warrior (Lv 4) / Kinet adept (Lv 4).

Win this turn with at least eleven health and two allied creatures remaining. Suffocating Gas will strike everyone at the end of your turn. All of your creatures except the wall are resting.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `GreenMale1` | 4 | 1 / 20 | 4 | None |
| Opponent | `BlueWingedMale1` | 4 | 3 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"finish_health": 11, "min_allies": 2, "type": "win"}`.

**Hint progression**

1. Symbiosis measures every creature still in play. Finishing health is checked when you win, so you may begin below the target.
2. The Fingus can release spores while resting. That damage saves an ether but removes a creature from the healing count.
3. Cast Symbiosis while all six creatures remain. Give Shell Skin to the Scout or Shaman, then release the Fingus's spores at the enemy hero. End the turn: the gas finishes the enemy, and your wall plus the sheltered creature survive.

**Solution and reason**

Symbiosis counts six bodies and heals twelve, raising you from one health to thirteen. The Fingus then supplies the single point needed to leave the enemy at two. Shell Skin lets either the Scout or Shaman survive alongside the wall; the other small ally and both enemies die in the gas. Its two damage leaves your hero at exactly eleven when the opponent reaches zero. Releasing spores before Symbiosis loses two healing. Spending ether on Zap leaves too little for both the heal and the protective enchantment. Shell Skin on the Fingus is lost when it sacrifices itself.

**Tempting alternatives checked**

- Release the spores before healing
- Use Zap for the opening point of damage
- Armor the Fingus before its sacrifice

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Последний вдох — Порядок лечения и число выживших**

Воин виталов (Lv 4) / Адепт кинетов (Lv 4)

Победите за этот ход, завершив его хотя бы с одиннадцатью жизнями и двумя союзными созданиями. Удушающий Газ поразит всех в конце вашего хода. Все ваши создания, кроме стены, отдыхают.

1. Симбиоз считает все создания, ещё находящиеся в игре. Требование к жизням проверяется в момент победы: сейчас их может быть меньше.
2. Фингус выпускает споры даже во время отдыха. Этот урон экономит эфир, но убирает одно создание из будущего подсчёта лечения.
3. Примените Симбиоз, пока в игре все шесть созданий. Наложите Ледяной Панцирь на авиака или шамана, затем направьте споры фингуса во вражеского героя. Завершите ход: газ добьёт врага, а стена и укрытое создание выживут.

Симбиоз считает шесть созданий и восстанавливает двенадцать жизней: у вас становится тринадцать. Споры фингуса наносят нужную единицу урона, оставляя врагу две жизни. Панцирь позволяет авиаку или шаману выжить вместе со стеной; другой слабый союзник и оба врага погибают от газа. После его двух единиц урона у вас остаётся ровно одиннадцать жизней, а у противника — ноль. Споры до Симбиоза лишают вас двух единиц лечения. Электрошок расходует эфир, необходимый одновременно для лечения и защитных чар. Панцирь на фингусе пропадёт при его жертве.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_last_breath`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "SYMB",
    "kind": "cast",
    "target": -1
  },
  {
    "card": "SHSK",
    "kind": "cast",
    "target": 3
  },
  {
    "id": 2,
    "key": "spores",
    "kind": "ability",
    "target": 1
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 22. Midnight Census

**Hard · Survive · Bat drain before disturbance**

**Matchup:** The Crimson Keeper (Lv 3) / The Emerald Huntress (Lv 9).

Survive one enemy turn and finish with at least four health and four creatures. Your level-3 hero faces two disturbance damage at the next turn, followed by Regeneration III. The enemy Lamia Warrior has trample.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `RedMale4` | 3 | 1 / 16 | 15 | Regeneration 3 |
| Opponent | `GreenFemale2` | 9 | 20 / 34 | 14 | None |

Own-turn budget: **1**. Objective metadata: `{"enemy_turns": 1, "finish_health": 4, "min_allies": 4, "type": "survive"}`.

**Hint progression**

1. Drain counts Bats that have just arrived, so the order of summoning and draining matters immediately.
2. The Vampire must rest to drain. Keep another creature ready and tough enough to stop all seven combat damage.
3. Summon the fourth Bat before using Vampire Bat's drain. Give Shell Skin to the Giant Bat and have it block the Lamia Warrior. The next disturbance and regeneration leave exactly four health.

**Solution and reason**

The fourth Bat increases the drain from three to four, raising your one health to five. Shell Skin makes the Giant Bat 5/8, so it can absorb the Warrior's seven damage without losing a body or allowing trample through. At the next turn, the level-three disturbance deals two before Regeneration III heals one: five becomes four. Draining before summoning misses the finishing threshold. The ordinary Bat reaches only six toughness with Shell Skin; it cannot preserve the required four creatures against the Warrior.

**Tempting alternatives checked**

- Drain before the fourth Bat arrives
- Spend one ether on the Small Velos — recorded bounded search is inconclusive; this opening is not established as losing.
- Give Shell Skin to the ordinary Bat

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Полуночная перепись — Летучие мыши против возмущения**

Багровый хранитель (Lv 3) / Изумрудная охотница (Lv 9)

Переживите один вражеский ход и завершите задачу хотя бы с четырьмя жизнями и четырьмя созданиями. В начале следующего хода герой 3-го уровня получит два урона от возмущения, а затем сработает Регенерация III. Вражеская Ламия-воительница обладает пробивным ударом.

1. Способность вампира считает и только что призванных летучих мышей: порядок призыва и высасывания сразу меняет результат.
2. После способности вампир начнёт отдыхать. Сохраните другого готового защитника, способного принять все семь единиц урона.
3. Сначала призовите четвёртую Летучую мышь, затем используйте способность вампира. Наложите Ледяной Панцирь на Гигантскую летучую мышь и заблокируйте ею Ламию. После возмущения и регенерации останутся ровно четыре жизни.

Четвёртая мышь усиливает высасывание с трёх до четырёх: одна жизнь превращается в пять. Ледяной Панцирь делает Гигантскую летучую мышь созданием 5/8, которое принимает семь урона, сохраняет жизнь и не пропускает пробивной удар. В начале следующего хода возмущение на третьем уровне сначала отнимает две жизни, затем Регенерация III возвращает одну: остаётся четыре. Если использовать вампира до призыва, нужного здоровья не хватит. Стойкость обычной мыши даже с Панцирем достигает лишь шести, поэтому сохранить четыре создания таким блоком не получится.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_midnight_census`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "BATT",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 2,
    "key": "bat_drain",
    "kind": "ability",
    "target": 1
  },
  {
    "card": "SHSK",
    "kind": "cast",
    "target": 4
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 4,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 23. Bank the Discount

**Hard · Win · A foreign Warlord and a recovery investment**

**Matchup:** The Sapphire Veteran (Lv 12) / The Red Warlord (Lv 4).

Win within two turns and preserve your Lamia Monk and Warrior. The enemy Warlord carries Alpha Strike and will expire at the end of this turn. Your level-12 hero has its full 43 health; the opponent's scenario maximum is nineteen. You have six ether now and six channels.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `BlueWingedMale1` | 12 | 43 / 43 | 4 | None |
| Opponent | `RedMale4` | 4 | 19 / 19 | 3 | None |

Own-turn budget: **2**. Objective metadata: `{"protect": [2, 3], "type": "win"}`.

**Hint progression**

1. A Lamia Warlord reduces summoning costs for both armies. Its discount will disappear before your next refill.
2. The Monk returns a Lamia to your hand rather than putting it into play. Your health can pay for a turn spent preparing a new attacker.
3. Recover the Warlord and summon it for six while the enemy discount is present. Absorb the enemy attack, then spend the next six ether on three Cloaks of Fear. The Monk, Warrior and new Warlord attack for nineteen.

**Solution and reason**

The foreign Warlord makes your recovered Warlord cost six instead of eight. The Monk and existing Warrior are resting, but the new Warlord becomes available to block after turn cleanup. The reference accepts all thirty-three enemy damage, using the level-twelve hero's full forty-three health to preserve every attacker. A safe Warlord block can reduce that payment. At the next refill, three Cloaks of Fear make four, seven and eight power unblockable: exactly nineteen. Recovering another Warrior produces only eighteen power. Spending on an early Cloak loses the temporary summoning window.

**Tempting alternatives checked**

- Recover another Warrior instead of the Warlord — recorded bounded search is inconclusive; this opening is not established as losing.
- Buy a Cloak for the Monk before banking the discount — recorded bounded search is inconclusive; this opening is not established as losing.

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Успеть купить со скидкой — Чужая повелительница и вложение в армию**

Сапфировый ветеран (Lv 12) / Красный воевода (Lv 4)

Победите за два хода, сохранив своих Ламию-монахиню и Ламию-воительницу. На вражеской Повелительнице лежит Альфа-удар: она погибнет в конце этого хода. У вашего героя 12-го уровня полный запас в 43 жизни; у врага девятнадцать. Сейчас у вас шесть эфира и шесть каналов.

1. Ламия-повелительница удешевляет призыв для обеих армий. Её скидка исчезнет раньше вашего следующего пополнения эфира.
2. Монахиня возвращает Ламию в руку, а не сразу на поле. Запас здоровья позволяет посвятить ход подготовке нового бойца.
3. Верните Повелительницу и призовите её за шесть, пока действует чужая скидка. Примите вражескую атаку героем, затем потратьте следующие шесть эфира на три Маски Ужаса. Монахиня, Воительница и новая Повелительница нанесут девятнадцать урона.

Чужая Повелительница снижает стоимость вашей возвращённой карты с восьми до шести. Монахиня и прежняя Воительница отдыхают, но новая Повелительница сможет блокировать после завершения хода. Приведённое решение принимает все тридцать три урона героем: полный запас двенадцатого уровня в сорок три жизни позволяет сохранить каждого будущего атакующего. Безопасный блок Повелительницей может уменьшить эту плату. После пополнения три Маски Ужаса делают четыре, семь и восемь силы неблокируемыми — ровно девятнадцать. Ещё одна Воительница вместо Повелительницы даст лишь восемнадцать. Ранняя Маска отнимет эфир, необходимый для покупки в короткое окно скидки.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_bank_discount`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "choice": 0,
    "id": 2,
    "key": "recall_lamia",
    "kind": "ability",
    "target": 0
  },
  {
    "card": "LMWD",
    "kind": "cast",
    "target": -1
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 5,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 6,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 7,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 8,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "kind": "end_phase"
  },
  {
    "card": "CLFR",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "CLFR",
    "kind": "cast",
    "target": 3
  },
  {
    "card": "CLFR",
    "kind": "cast",
    "target": 9
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "id": 3,
    "kind": "attack"
  },
  {
    "id": 9,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 24. The Queen's Shadow

**Hard · Win · A shared Bee aura and a one-sided rally**

**Matchup:** The Verdant Matriarch (Lv 6) / The Scarlet Poacher (Lv 1).

Win this turn, preserve your Female Fighter, and finish with at least fifteen health. The enemy Bee Warrior shares your Mother's first-strike aura and your other Bees' strength bonuses. Scenario maximums are 25 for your level-6 hero and 10 for the level-1 opponent.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `GreenFemale2` | 6 | 1 / 25 | 4 | None |
| Opponent | `RedMale4` | 1 | 10 / 10 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"finish_health": 15, "protect": [5], "type": "win"}`.

**Hint progression**

1. Healing sets health to half the maximum. Any sacrifice healing that needs to exceed that floor must happen afterwards.
2. Mother Bee helps both armies while alive. Her death rallies only her own surviving Bees, and removes the enemy's first strike.
3. Heal first, then sacrifice Mother Bee. Give your army Haste for first strike and trample, and add the Female Fighter to the Bees' forced attack.

**Solution and reason**

Healing raises one health to twelve. The Queen and Worker make Mother Bee 2/3, so sacrificing her deals two and heals three: you reach fifteen while the enemy drops to eight. Mother's death removes the hostile Bee's first strike and sends your Queen and Worker into the attack. Haste restores first strike only to your side and grants trample. The Queen and Worker die when they hit the enemy hero, changing every remaining Bee's stats. If the enemy blocks the Fighter, the Queen deals two and dies, the Worker deals one and dies, then the Fighter tramples over the now one-toughness blocker for five: exactly eight. Blocking either Bee also lets eight through. Sacrificing before Healing ends at twelve health.

**Tempting alternatives checked**

- Sacrifice Mother Bee before Healing
- Sacrifice the Queen instead of the Mother
- Armor the Fighter before funding the attack

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Тень королевы — Общая аура и ярость своих пчёл**

Зелёная матриарх (Lv 6) / Алый браконьер (Lv 1)

Победите за этот ход, сохраните Серого некроманта и завершите задачу хотя бы с пятнадцатью жизнями. Вражеская Пчела-воин получает первый удар от вашей Матки и усиление от остальных ваших пчёл. В этой позиции максимум героя 6-го уровня равен 25, а у противника 1-го уровня десять жизней.

1. Лечение доводит здоровье до половины максимума. Лечение жертвой, которое должно поднять его выше этого порога, применяйте позже.
2. Живая Матка помогает обеим армиям. После её смерти в ярость приходят только свои пчёлы, а вражеская теряет первый удар.
3. Сначала примените Лечение, затем принесите Матку в жертву. Спешкой дайте своей армии первый и пробивной удары; к вынужденной атаке пчёл добавьте Серого некроманта.

Лечение поднимает одну жизнь до двенадцати. Королева и Рабочая пчела делают Матку созданием 2/3: её жертва наносит два урона и лечит на три. У вас пятнадцать жизней, у врага восемь. Смерть Матки убирает первый удар врага и отправляет ваших Королеву и Рабочую пчелу в атаку. Спешка даёт первый и пробивной удары лишь вашей армии. Пчёлы погибают после удара по герою, меняя характеристики оставшихся пчёл. Если враг блокирует некроманта, Королева наносит два и погибает, Рабочая — один и погибает, а некромант пробивает оставшуюся единицу стойкости блокирующего создания ещё на пять: ровно восемь. Блок любой пчелы также пропускает восемь. Жертва до Лечения оставит лишь двенадцать жизней.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_queens_shadow`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "HEAL",
    "kind": "cast",
    "target": 0
  },
  {
    "card": "CANV",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "HAST",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 5,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 6,
    "kind": "block",
    "side": 1,
    "target": 5
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 25. Behind the Magic Screen

**Hard · Clear · Global magic and a regeneration reserve**

**Matchup:** The Iron Exile (Lv 10) / The Ashen Marshal (Lv 16).

Clear the enemy army within two turns and preserve both Abominations. Haste and Fury already cover your hero; your Iron Abomination has Shell Skin. Your level-10 hero's next disturbance deals three damage.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `StartBlackMale` | 10 | 4 / 37 | 23 | None |
| Opponent | `RedMale4` | 16 | 55 / 55 | 22 | None |

Own-turn budget: **2**. Objective metadata: `{"protect": [2, 3], "type": "clear"}`.

**Hint progression**

1. The Steel Abomination cannot receive an ordinary targeted spell, but an army-wide enchantment can still strengthen it.
2. The Iron Abomination must survive the poisoned Orc's first strike and still have ether available for the later lethal effect.
3. Cast Dominance and save the last ether. Let Fury force the attack. Block the Mechos with Steel and the Orc with Iron; Iron regenerates after poison, and the next disturbance leaves your hero on one health.

**Solution and reason**

Dominance reaches the screened Steel Abomination and raises it to six power. Haste lets it kill the six-toughness Steel Mechos before receiving a hit. The armored Iron Abomination becomes 4/9: it survives the Orc's five-point first strike, kills the three-toughness Orc, then spends the reserved ether to regenerate through poison. Both enemies are gone. The level-ten disturbance deals three to your four-health hero at the next turn. Spending on a targeted defensive spell cannot supply Steel's missing power and removes the required combination of global enhancement and regeneration reserve.

**Tempting alternatives checked**

- Add a second Shell Skin to Iron
- Buy an Energy Barrier for the disturbance
- Reverse the two defensive assignments

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**За магическим щитом — Общая магия и запас на регенерацию**

Железный изгнанник (Lv 10) / Пепельный маршал (Lv 16)

Уничтожьте вражескую армию за два хода и сохраните обоих исчадий. На вашем герое уже действуют Спешка и Бешенство, на Железном исчадии — Ледяной Панцирь. Ближайшее возмущение нанесёт вашему герою 10-го уровня три урона.

1. Стальное исчадие не принимает обычные направленные заклинания, но чары на всю армию всё равно могут его усилить.
2. Железное исчадие должно пережить первый удар ядовитого Орка; после этого ему ещё понадобится эфир против смертельного эффекта.
3. Примените Господство и сохраните последний эфир. Бешенство заставит врагов атаковать. Стальным исчадием блокируйте мехоса, Железным — Орка. Железное регенерирует после яда, а возмущение оставит герою одну жизнь.

Господство проходит сквозь магический щит Стального исчадия и поднимает его силу до шести. Благодаря Спешке оно убивает Стального мехоса со стойкостью шесть раньше ответного удара. Закованное в Панцирь Железное исчадие становится 4/9: выдерживает первый удар Орка на пять, убивает его с тремя единицами стойкости и затем тратит сохранённый эфир на регенерацию после яда. Оба врага уничтожены. В начале следующего хода возмущение на десятом уровне отнимает три из четырёх жизней героя. Направленное защитное заклинание не даст Стальному исчадию недостающей силы и лишит вас сочетания общего усиления с запасом на регенерацию.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_behind_magic_screen`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "DOMN",
    "kind": "cast",
    "target": -1
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 2,
    "kind": "block",
    "target": 4
  },
  {
    "id": 3,
    "kind": "block",
    "target": 5
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

### 26. Seal the Response

**Expert · Win · Manifestation order and resource denial**

**Matchup:** White Lord (Lv 4) / White Lord (Lv 4).

Win this turn. The enemy has a Pale Slayer, a Spellshifter with five ether, and a Pale Revenant trap. Your Knight has one graveyard card available for manifestation.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `White Lord I` | 4 | 9 / 20 | 4 | None |
| Opponent | `White Lord I` | 4 | 13 / 20 | 3 | None |

Own-turn budget: **1**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. A normal attack lets the defender bring a body out of the Colourless Plane. Seal creates another body as well as closing the plane.
2. The enemy can pay five ether to transpose your Seal. Remove that payment before the defence phase, without losing the Knight's manifestation.
3. Manifest the Knight using the graveyard. Have the Invoker drain the enemy hero's five ether for five damage. Cast Seal only after the Knight is bright, then attack for eight.

**Solution and reason**

The Knight must become bright before the global seal takes effect. The Invoker's five-point drain reduces the enemy from thirteen health to eight and removes the five ether needed to transpose Seal. Seal triggers the trap, but the new Revenant enters the Colourless Plane and cannot manifest under the same seal. The Slayer also remains trapped there. The Knight's eight-point attack therefore finishes the hero. Spending on Mark of Pale leaves no Seal, and sealing too early locks your own finisher away.

**Tempting alternatives checked**

- Seal before manifesting the Knight
- Spend the Invoker's damage on your own hero
- Buy Mark of Pale before the seal
- Commit the Knight without sealing the defence

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Запечатать ответ — Переход между планами и лишение эфира**

Белый Лорд (Lv 4) / Белый Лорд (Lv 4)

Победите за этот ход. У врага есть Бесцветный Убийца, Ловкач с пятью единицами эфира и ловушка Бесцветного Карателя. Для выхода вашего Рыцаря из Бесцветного Плана в могильнике есть одна карта.

1. Обычная атака позволит врагу вывести защитника из Бесцветного Плана. Печать не только закроет переходы, но и вызовет ещё одно создание.
2. Враг может заплатить пять эфира и снять вашу Печать Ловкачом. Лишите его этой возможности до фазы защиты, не заперев собственного Рыцаря.
3. Выведите Рыцаря в Эфирный План, потратив карту из могильника. Чародеем заберите весь вражеский эфир и нанесите пять урона герою. Лишь затем наложите Печать и атакуйте Рыцарем на восемь.

Рыцарь должен выйти до того, как Печать запретит все переходы. Способность Чародея уменьшает вражеские жизни с тринадцати до восьми и лишает Ловкача пяти эфира, необходимых для снятия Печати. Колдовство активирует ловушку, но новый Каратель появляется в Бесцветном Плане и уже не может выйти. Там же остаётся Убийца. Удар Рыцаря на восемь добивает героя. Клеймо Бесцветности оставит вас без эфира для Печати, а слишком ранняя Печать запрёт вашего собственного бойца.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_sealed_response`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "choice": 0,
    "id": 2,
    "key": "sinister",
    "kind": "ability",
    "target": 0
  },
  {
    "id": 3,
    "key": "ether_plea",
    "kind": "ability",
    "target": 1
  },
  {
    "card": "PLSL",
    "kind": "cast",
    "target": -1
  },
  {
    "id": 2,
    "kind": "attack"
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 27. Two Delayed Verdicts

**Expert · Win · A delayed clock and remaining toughness**

**Matchup:** White Lord (Lv 4) / White Lord (Lv 4).

Win within two turns while preserving your Pale Spellweaver and Spellshifter. Two Pale Warps will trigger at the start of your next turn. Fatal Disease keeps all wounds. The opponent has one Lesser Disenchant and two ether.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `White Lord I` | 4 | 8 / 20 | 4 | None |
| Opponent | `White Lord I` | 4 | 13 / 20 | 3 | None |

Own-turn budget: **2**. Objective metadata: `{"protect": [2, 3], "type": "win"}`.

**Hint progression**

1. The Warps choose the Pale creature with the least remaining toughness, from either army. A tie is not a safe plan for your own helper.
2. Prepare two victims below your protected creatures, stop dissipation from saving them, and account for the opponent's dispel.
3. Give the wounded Spellweaver Shell Skin. Lock both enemy aspects, Zap each enemy once, and discard the enemy's Lesser Disenchant with Malison. Leave Fatal Disease and both Pale Warps intact; their next triggers kill the locked Knight and Zealot.

**Solution and reason**

Shell Skin raises the wounded Spellweaver's remaining toughness from one to five. Each wounded enemy starts with three remaining toughness; one Zap apiece lowers both to two, below the three-toughness Spellshifter. Fatal Disease preserves that ordering across turn cleanup. Lock Aspect makes the delayed lethal effects destroy their victims rather than dissipate them, dealing their printed powers of eight and five to the enemy hero. Malison removes Lesser Disenchant: otherwise the opponent can remove Fatal Disease, letting its army recover while the plane-bound Spellshifter becomes the next victim. Blast removes the newest enchantment before damaging. Stacking two Locks buys an immediate kill, but spends too much to prepare and protect the remaining verdict.

**Tempting alternatives checked**

- Put Shell Skin on the wounded Knight — recorded bounded search is inconclusive; this opening is not established as losing.
- Manifest, stack two Locks and Blast the Knight immediately
- Use one Lock Aspect on your Spellweaver — recorded bounded search is inconclusive; this opening is not established as losing.
- Pass with both victims prepared but leave the dispel in hand

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Два отложенных приговора — Отложенная угроза и оставшаяся стойкость**

Белый Лорд (Lv 4) / Белый Лорд (Lv 4)

Победите за два хода, сохранив своих Бесцветных Ткача и Ловкача. В начале вашего следующего хода сработают две Деформации Бесцветности. Роковая Болезнь сохраняет все раны. У противника одно Снятие Чар и два эфира.

1. Деформация выбирает бесцветное создание с наименьшей оставшейся стойкостью из обеих армий. Равенство опасно для вашего помощника.
2. Сделайте оставшуюся стойкость двух жертв ниже, чем у защищаемых созданий, запретите спасительный переход и учтите вражеское снятие чар.
3. Наложите Ледяной Панцирь на раненого Ткача. Свяжите обоих врагов Эфирными Узами, ударьте каждого Электрошоком и сбросьте Снятие Чар с помощью Проклятия. Сохраните Болезнь и обе Деформации: в начале хода они уничтожат связанных Рыцаря и Воина.

Панцирь поднимает оставшуюся стойкость раненого Ткача с одного до пяти. У каждого врага сначала остаётся по три; Электрошок снижает оба значения до двух — ниже трёх единиц Ловкача. Болезнь сохраняет этот порядок после окончания ходов. Эфирные Узы заменяют спасительный переход уничтожением, и герой получает базовую силу погибших: восемь и пять. Проклятие убирает Снятие Чар: иначе враг снимет Болезнь, его армия восстановится, а следующим погибнет находящийся в Бесцветном Плане Ловкач. Бесцветный Удар сначала снимает самые новые чары. Две копии Уз позволяют немедленно убить одну цель, но стоят слишком дорого, чтобы подготовить и защитить оставшийся приговор.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_delayed_verdicts`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "SHSK",
    "kind": "cast",
    "target": 2
  },
  {
    "card": "PRBN",
    "kind": "cast",
    "target": 4
  },
  {
    "card": "PRBN",
    "kind": "cast",
    "target": 5
  },
  {
    "card": "ZAPP",
    "kind": "cast",
    "target": 4
  },
  {
    "card": "ZAPP",
    "kind": "cast",
    "target": 5
  },
  {
    "card": "MALS",
    "kind": "cast",
    "target": 1
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase",
    "side": 1
  }
]
```

</details>

### 28. Keep the Gift Alive

**Expert · Win · A hostile gift between veterans**

**Matchup:** Diamanda, Last Form (Lv 20) / The Crimson Regent (Lv 18).

Win within two turns. The level-18 opponent has Regeneration III, two channels and Force of Sacrifice. You have two health and two walls. Your level-20 hero will take one disturbance damage at the next turn; the opponent's next two natural disturbances deal two and three.

| Side | Template | Level | Starting health / maximum | Own-turn counter | Skills |
| --- | --- | ---: | ---: | ---: | --- |
| You | `Diamanda4Green` | 20 | 2 / 67 | 31 | None |
| Opponent | `RedMale4` | 18 | 10 / 61 | 30 | Regeneration 3 |

Own-turn budget: **2**. Objective metadata: `{"type": "win"}`.

**Hint progression**

1. Gift changes more than ownership. Its bearer advances the receiving hero's disturbance clock by two turns.
2. The recipient must stay alive, even if it attacks you. Remove the opponent's way to sacrifice it, and choose the body that will last.
3. Discard Force of Sacrifice with Malison and give away the Night Wolf. Let the Wall of Air stop that Wolf without killing it; keep the Wall of Blades for the Ogre. Pass again to the next enemy turn.

**Solution and reason**

The gifted Wolf advances the opponent's next disturbance from two damage to five. Ten health becomes five, then Regeneration restores one. The following accelerated disturbance deals seven and kills the six-health hero before regeneration can trigger. A nonlethal block keeps the clock's carrier alive. Gifting the Small Velos fails because it dies at the end of its controller's turn: the next natural disturbance deals only three, which the opponent survives even if the elusive Wolf has attacked twice. Diamanda's level twenty is the exact survival margin: her next turn deals one damage; level nineteen would take two and die before the final pass.

**Tempting alternatives checked**

- Give away the expiring Small Velos
- Weaken the Ogre before preparing the clock
- Kill the gifted Wolf with the sharp wall

<details>
<summary>Russian matchup, briefing, hints, and explanation</summary>

**Берегите подарочек — Враждебный подарок между ветеранами**

Диаманда, последняя форма (Lv 20) / Багровый регент (Lv 18)

Победите за два хода. У противника 18-го уровня есть Регенерация III, два канала и Сила жертвоприношения. У вас две жизни и две стены. В начале следующего хода ваш герой 20-го уровня получит один урон от эфирного возмущения; два следующих возмущения противника без ускорения нанесут два и три.

1. Подарочек не просто меняет владельца. Пока подаренное создание живо, возмущение получателя опережает обычный срок на два хода.
2. Получатель должен остаться в живых, даже если нападёт на вас. Уберите возможность принести его в жертву и выберите создание, которое не исчезнет само.
3. Проклятием сбросьте Силу жертвоприношения и подарите Ночного волка. Стеной воздуха остановите его, не убивая; Стену лезвий оставьте для Вождя людоедов. Затем снова передайте ход противнику.

Подаренный Волк усиливает ближайшее возмущение противника с двух до пяти урона. Из десяти жизней остаётся пять, затем Регенерация возвращает одну. Следующее ускоренное возмущение наносит семь и убивает героя с шестью жизнями до срабатывания лечения. Поэтому носителя подарка нужно блокировать без смертельного урона. Малый колесник исчезает в конце своего хода: без него следующее возмущение нанесёт лишь три, и противник выживет даже после двух ударов неуловимого Волка. Двадцатый уровень Диаманды даёт точный запас: её ближайшее возмущение наносит один урон; на девятнадцатом уровне два урона убили бы её до последней передачи хода.

</details>

<details>
<summary>Machine-readable reference line</summary>

ID: `el2_tactical_v2_keep_gift_alive`. Creature targets are snapshot IDs; heroes are 0 (player) and 1 (opponent). `side: 1` identifies an opponent action. See `tools/PUZZLE_LAB.md` for command fields.

```json
[
  {
    "card": "MALS",
    "kind": "cast",
    "target": 1
  },
  {
    "card": "GIFT",
    "kind": "cast",
    "target": 2
  },
  {
    "kind": "end_phase"
  },
  {
    "id": 2,
    "kind": "attack",
    "side": 1
  },
  {
    "id": 6,
    "kind": "attack",
    "side": 1
  },
  {
    "kind": "end_phase",
    "side": 1
  },
  {
    "id": 4,
    "kind": "block",
    "target": 2
  },
  {
    "id": 5,
    "kind": "block",
    "target": 6
  },
  {
    "kind": "end_phase"
  },
  {
    "kind": "end_phase"
  }
]
```

</details>

