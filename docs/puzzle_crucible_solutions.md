# Crucible: complete solutions / полные решения

**Full spoilers for all 10 Crucible puzzles.** For the collection overview and installation notes, see the [nonspoiler guide](puzzle_crucible.md). The three in-game hints reveal the plan gradually; this document includes every hint, the full explanations in both languages, and the exact reference commands.

**Полные решения всех 10 задач «Горнила».** Описание коллекции и установка находятся в [руководстве без решений](puzzle_crucible.md). Ниже приведены все три подсказки, объяснения на обоих языках и точные команды примеров.

## How to use these solutions

All ten objectives are ordinary hero victories, within the stated number of your own turns. **Any legal winning line within that limit is accepted.** These witnesses do not establish that the solution is unique. A reference includes one concrete sequence of enemy actions; it is not a universal fixed script that works unchanged against every reply. Different attacks, spell choices or timing can require different blocks, targets or resource decisions. Follow the explanatory strategy and adapt to the actual position. The Venom Clock includes its complete adaptive policy below.

Во всех десяти задачах цель — обычная победа над героем за указанное число собственных ходов. **Игра принимает любое законное решение, укладывающееся в лимит.** Примеры не означают, что решение единственное. Каждый пример включает конкретные действия противника; при другом ответе могут потребоваться иные блоки, цели или момент применения способности. Следуйте плану из объяснения и учитывайте текущую позицию. Для «Часов яда» ниже сохранён полный план с разными ответами врага.

### Command notation

- `0` is your hero; `1` is the enemy hero. Creature IDs are shown beside each starting position. New creatures receive the next available ID during the replay.
- An explicit `"side": 1` marks an opponent action. When `side` is omitted, the command applies to the active side in that phase.
- `card` is the repository card code. `target` is a hero or creature ID; `-1` means no explicit target.
- `power` is the chosen variable value, not the total ether price. For grave-directed casts, `grave` is the current zero-based graveyard index; for dispels, that field selects the enchantment ID. Earlier commands can change graveyard indices.
- An ability key such as `burnout:1` identifies the ability supplied by enchantment `1`. Its `choice` can mean a second creature, an enchantment ID or a graveyard index, according to that ability.
- Preserve the order of `block` commands: that order can decide how trample damage is distributed. An `end_phase` may also advance through an empty defence, so consecutive enemy commands can be intentional.

Числа и порядок в JSON сохранены из установленных каталогов. `0` — ваш герой, `1` — враг; `side: 1` указывает действие врага. Индексы могильника начинаются с нуля и могут изменяться после предыдущих команд. Порядок назначения блокирующих важен, особенно против пробивного удара.

## Contents

| Edition | Puzzle / Задача | Own turns | Main commands |
| --- | --- | ---: | ---: |
| Etherlords I | The Buried Reserve / Погребённый резерв | 2 | 16 |
| Etherlords I | A Mortal Equation / Смертельное уравнение | 1 | 6 |
| Etherlords I | The Frozen Account / Замороженный счёт | 2 | 22 |
| Etherlords I | The Black Furnace / Чёрная печь | 2 | 15 |
| Etherlords I | Two Bequests / Два наследства | 2 | 18 |
| Etherlords II | Borrowed Violence / Заёмная сила | 2 | 6 |
| Etherlords II | Glass Furnace / Стеклянная печь | 2 | 10 |
| Etherlords II | The Last Funeral / Последние похороны | 2 | 14 |
| Etherlords II | Two Doors, One Key / Две двери — один ключ | 2 | 12 |
| Etherlords II | The Venom Clock / Часы яда | 3 | 24 |

The main references contain 143 commands. The Black Furnace also has a separately declared alternate reference.

## Etherlords I

### The Buried Reserve / Погребённый резерв

`el1_tactical_v2_crucible_buried_reserve` · **Expert / Эксперт** · Own-turn limit / Лимит собственных ходов: **2** · Objective / Цель: **win / победа**

**Briefing:** Win within two turns. Your Cutter Man is resting. A Hopper lies beneath two newer creatures in your graveyard, and your four ether will not refill.

**Обстановка:** Победите за два хода. Раскройщик отдыхает. Над Прыгуном в вашем могильнике лежат два более новых существа. Четыре единицы эфира больше не пополнятся.

**Starting heroes / Герои в начале:**

| ID | Hero / Герой | Health / Жизни | Ether / Эфир | Channels / Каналы |
| --- | --- | ---: | ---: | ---: |
| 0 | Crucible challenger / Испытуемый | 1 | 4 | 0 |
| 1 | Crucible defender / Страж испытания | 22 | 0 | 0 |

**Starting creature IDs / Начальные номера существ:**

| ID | Side / Сторона | Card | Creature / Существо | Initial status / Начальное состояние |
| --- | --- | --- | --- | --- |
| 2 | You / Вы | `CTMN` | Cutter Man / Раскройщик | 7/4; resting / отдыхает |
| 3 | You / Вы | `WLFC` | Wall of Force / Стена силы | 0/12 |
| 4 | You / Вы | `TIWR` | Tick Warrior / Клещ-воин | 2/2 |
| 5 | Enemy / Враг | `IRMZ` | Iron Mechozaurus / Железный мехозавр | 6/4 |
| 6 | Enemy / Враг | `BUDG` | Blue Dragon / Синий дракон | 8/8 |

**Starting graveyards / Начальные могильники:** 0: `HOPR, STRT, KBSH`; 1: empty / пусто.

**Hints:**

1. Reserve the creatures needed for the counterattack.
2. One more burial will return the Hopper at the turn boundary. The Cutter needs two separate sacrifices.
3. Feed the Tick to the Cutter, overload it and give it Cloak of Fear. Keep the returned Hopper; sacrifice it during your next defence, then block the Mechozaurus with the Cutter and the Dragon with the wall.

**Подсказки:**

1. Берегите существ, которые понадобятся для отражения контратаки.
2. Ещё одна смерть обеспечит возвращение Прыгуна на границе хода. Раскройщику понадобятся две разные жертвы.
3. Пожертвуйте Клеща Раскройщику, дайте Раскройщику Перегрузку и Маску Ужаса. Берегите вернувшегося Прыгуна: пожертвуйте его при следующей защите. Раскройщиком блокируйте Мехозавра, стеной — Дракона.

**Why it works:**

The first sacrifice places the third newer creature over the Hopper, which returns at the end of the turn. Overload and Cloak produce a twelve-point unblockable attack. The Cutter then decays to 10/7; sacrificing the returned Hopper readies it for defence. It survives the Mechozaurus's six damage and kills that attacker while the wall stops the flyer. Its last ten damage is exact: the dead Mechozaurus no longer drains its controller. If the Mechozaurus stays home, that four-health drain instead makes the final attack easier.

**Почему это работает:**

Первая жертва кладёт третье новое существо над Прыгуном: он вернётся в конце хода. Перегрузка и Маска Ужаса обеспечивают неблокируемую атаку на двенадцать. Затем Раскройщик ослабевает до 10/7; жертва Прыгуна будит его для защиты. Он выдерживает шесть урона Железного мехозавра и убивает его, пока стена держит Дракона. Последние десять урона точны: погибший Мехозавр уже не отнимает здоровье у хозяина. Если враг оставит Мехозавра дома, тот сам отнимет четыре здоровья, облегчив последнюю атаку.

**Exact main reference / Точный основной пример:**

```json
[
  {"kind": "ability", "id": 2, "key": "sacrifice", "target": 4},
  {"kind": "cast", "card": "OVRL", "target": 2},
  {"kind": "cast", "card": "CLFR", "target": 2},
  {"kind": "attack", "id": 2},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1},
  {"kind": "attack", "id": 5, "side": 1},
  {"kind": "attack", "id": 6, "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "ability", "id": 2, "key": "sacrifice", "target": 7},
  {"kind": "block", "id": 2, "target": 5},
  {"kind": "block", "id": 3, "target": 6},
  {"kind": "end_phase"},
  {"kind": "attack", "id": 2},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1}
]
```


### A Mortal Equation / Смертельное уравнение

`el1_tactical_v2_crucible_mortal_equation` · **Expert / Эксперт** · Own-turn limit / Лимит собственных ходов: **1** · Objective / Цель: **win / победа**

**Briefing:** Win this turn. You have three ether, two health, and no ready attacker. The Steel Mechozaurus is unaffected by magic; your Cutter carries Delusion.

**Обстановка:** Победите за этот ход. У вас три эфира, два здоровья и ни одного готового атакующего. Стальной мехозавр невосприимчив к магии, а на Раскройщике действует Перестановка.

**Starting heroes / Герои в начале:**

| ID | Hero / Герой | Health / Жизни | Ether / Эфир | Channels / Каналы |
| --- | --- | ---: | ---: | ---: |
| 0 | Crucible challenger / Испытуемый | 2 | 3 | 0 |
| 1 | Crucible defender / Страж испытания | 15 | 0 | 0 |

**Starting creature IDs / Начальные номера существ:**

| ID | Side / Сторона | Card | Creature / Существо | Initial status / Начальное состояние |
| --- | --- | --- | --- | --- |
| 2 | You / Вы | `CTMN` | Cutter Man / Раскройщик | 4/7; resting / отдыхает; enchantments / чары: DELS |
| 3 | You / Вы | `GRTN` | Great Treant / Старый древень | 3/3; resting / отдыхает |
| 4 | You / Вы | `WLIL` | Wall of Illusion / Стена иллюзии | 0/3 |
| 5 | Enemy / Враг | `WLFC` | Wall of Force / Стена силы | 0/12 |
| 6 | Enemy / Враг | `STMZ` | Steel Mechozaurus / Стальной мехозавр | 8/6 |
| 7 | Enemy / Враг | `GRDG` | Green Dragon / Зеленый дракон | 11/8; enchantments / чары: STRG |

**Starting graveyards / Начальные могильники:** 0: empty / пусто; 1: empty / пусто.

**Hints:**

1. Calculate both sides of Annihilation before choosing what to remove.
2. Ether Trade heals the enemy as well as funding you. Spending more life can put the enemy beyond your final damage.
3. Polymorph the Green Dragon, trade six health, dispel the Cutter's Delusion, and give the Cutter Alpha Strike plus Strength. Annihilation now deals exactly twenty-one.

**Подсказки:**

1. Прежде чем выбирать цель уничтожения, посчитайте урон Аннигиляции для обеих сторон.
2. Эфирная Торговля не только даёт вам эфир, но и лечит врага. Лишняя плата здоровьем может вывести его из-под летального удара.
3. Превратите Зелёного дракона, обменяйте шесть здоровья на эфир, снимите Перестановку с Раскройщика и дайте ему Альфа-удар с Усилением. Аннигиляция нанесёт ровно двадцать один урон.

**Why it works:**

Polymorph removes eleven opposing power and sets health to eight. Ether Trade at six leaves two health, provides ten ether and heals the enemy from fifteen to twenty-one. Lesser Disenchant, Alpha Strike, Strength and Annihilation cost exactly ten. The restored Cutter supplies eighteen power and the Treant three. The unaffected Mechozaurus contributes no Annihilation damage. Trading less cannot fund the line; trading more heals the enemy beyond twenty-one.

**Почему это работает:**

Превращение убирает одиннадцать вражеской силы и устанавливает герою восемь здоровья. Эфирная Торговля на шесть оставляет два здоровья, даёт десять эфира и лечит врага с пятнадцати до двадцати одного. Снятие Чар, Альфа-удар, Усиление и Аннигиляция стоят ровно десять. Раскройщик без Перестановки даёт восемнадцать силы, Старый древень — три. Невосприимчивый Мехозавр не добавляет урона Аннигиляции. Меньшая плата не финансирует комбинацию, большая лечит врага выше двадцати одного.

**Exact main reference / Точный основной пример:**

```json
[
  {"kind": "cast", "card": "PLMR", "target": 7},
  {"kind": "cast", "card": "CHNL", "target": -1, "power": 6},
  {"kind": "cast", "card": "CLNP", "target": 2, "grave": 1},
  {"kind": "cast", "card": "ALST", "target": 2},
  {"kind": "cast", "card": "STRG", "target": 2},
  {"kind": "cast", "card": "ANHL", "target": -1}
]
```


### The Frozen Account / Замороженный счёт

`el1_tactical_v2_crucible_frozen_account` · **Expert / Эксперт** · Own-turn limit / Лимит собственных ходов: **2** · Objective / Цель: **win / победа**

**Briefing:** Win within two turns. The opponent has six ether, six channels, Call Lightning and Polymorph, and is already Envenomed. You have three ether and no channels.

**Обстановка:** Победите за два хода. У противника шесть эфира, шесть каналов, Молния и Превращение; на нём уже действует Отравление. У вас три эфира и ни одного канала.

**Starting heroes / Герои в начале:**

| ID | Hero / Герой | Health / Жизни | Ether / Эфир | Channels / Каналы |
| --- | --- | ---: | ---: | ---: |
| 0 | Crucible challenger / Испытуемый | 1 | 3 | 0 |
| 1 | Crucible defender / Страж испытания | 18 | 6 | 6 |

**Starting creature IDs / Начальные номера существ:**

| ID | Side / Сторона | Card | Creature / Существо | Initial status / Начальное состояние |
| --- | --- | --- | --- | --- |
| 2 | You / Вы | `SWHL` | Swamp Halo / Болотный нимб | 3/11; enchantments / чары: SHSK |
| 3 | You / Вы | `AREL` | Air Elemental / Элементаль воздуха | 3/6 |
| 4 | You / Вы | `RKWL` | Rock Wall / Каменная стена | 0/10 |
| 5 | Enemy / Враг | `BUDG` | Blue Dragon / Синий дракон | 8/8 |
| 6 | Enemy / Враг | `IRMC` | Iron Mechos / Железный мехос | 6/4 |

**Starting graveyards / Начальные могильники:** 0: empty / пусто; 1: empty / пусто.

**Hints:**

1. The enemy must lose both the ether it has and the refill it expects.
2. Your source of ether must also stop the flying counterattack. Reserve Stasis upkeep before spending the final points.
3. Siphon all six ether, cast Stasis, give the Air Elemental Strength, and use Energize All after the siphon. Attack with the Elemental, cover the Dragon with the Halo and the Mechos with the wall, and retain two ether for upkeep.

**Подсказки:**

1. Враг должен потерять и нынешний запас эфира, и ожидаемое пополнение.
2. Ваш источник эфира должен также остановить воздушную контратаку. Прежде чем расходовать последние единицы, оставьте плату за Стазис.
3. Украдите Нимбом все шесть эфира, наложите Стазис и дайте Элементалю воздуха Усиление. Затем примените Общую Подзарядку. Атакуйте Элементалем; Нимбом держите Дракона, стеной — Мехоса. Два оставшихся эфира оплатят Стазис: переживите и вторую контратаку, чтобы сработало Отравление.

**Why it works:**

Siphon creates nine ether and removes the defensive Polymorph. Stasis prevents the six-channel refill and the lethal Lightning. Strength makes the unblockable Elemental hit for seven twice; Envenoming supplies two damage at each enemy turn end. Energize All restores the Halo for the flying counterattack; Rock Wall must stop the Mechos because its execution ignores surviving non-Walls. The remaining two ether pays Stasis upkeep at the second own turn. Both defenders must cover another counterattack before the poison finishes the enemy. On this line, allowing Stasis to expire gives the enemy its lethal Lightning first.

**Почему это работает:**

Кража даёт девять эфира и лишает врага защитного Превращения. Стазис отменяет пополнение от шести каналов и смертельную Молнию. Усиленный неблокируемый Элементаль дважды наносит по семь, Отравление — ещё по два в конце каждого вражеского хода. Общая Подзарядка будит Нимб после кражи, позволяя остановить Дракона. Каменная стена должна держать Мехоса: его добивание уничтожает уцелевших существ, кроме стен. Два сохранённых эфира оплачивают Стазис в начале второго своего хода. Оба защитника нужны для второй контратаки до последнего урона Отравления; в этой линии отмена Стазиса даст врагу Молнию раньше этого момента.

**Exact main reference / Точный основной пример:**

```json
[
  {"kind": "ability", "id": 2, "key": "siphon", "target": -1},
  {"kind": "cast", "card": "STSI", "target": -1},
  {"kind": "cast", "card": "STRG", "target": 3},
  {"kind": "cast", "card": "ENAL", "target": -1},
  {"kind": "attack", "id": 3},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1},
  {"kind": "attack", "id": 5, "side": 1},
  {"kind": "attack", "id": 6, "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "block", "id": 2, "target": 5},
  {"kind": "block", "id": 4, "target": 6},
  {"kind": "end_phase"},
  {"kind": "attack", "id": 3},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1},
  {"kind": "attack", "id": 5, "side": 1},
  {"kind": "attack", "id": 6, "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "block", "id": 2, "target": 5},
  {"kind": "block", "id": 4, "target": 6},
  {"kind": "end_phase"}
]
```


### The Black Furnace / Чёрная печь

`el1_tactical_v2_crucible_black_furnace` · **Expert / Эксперт** · Own-turn limit / Лимит собственных ходов: **2** · Objective / Цель: **win / победа**

**Briefing:** Win within two turns. Burnout is active and your Walking Horror is resting. The Warrior Spirit is a berserker with regeneration; the Wizard and a wall support its defence.

**Обстановка:** Победите за два хода. Сожжение уже действует, Ходячий ужас отдыхает. Призрак-воин обладает регенерацией и обязан атаковать; Колдун и стена поддерживают его защиту.

**Starting heroes / Герои в начале:**

| ID | Hero / Герой | Health / Жизни | Ether / Эфир | Channels / Каналы |
| --- | --- | ---: | ---: | ---: |
| 0 | Crucible challenger / Испытуемый | 1 | 6 | 1 |
| 1 | Crucible defender / Страж испытания | 36 | 2 | 2 |

**Starting creature IDs / Начальные номера существ:**

| ID | Side / Сторона | Card | Creature / Существо | Initial status / Начальное состояние |
| --- | --- | --- | --- | --- |
| 2 | You / Вы | `WKHR` | Walking Horror / Ходячий ужас | 9/9; resting / отдыхает |
| 3 | Enemy / Враг | `WRSP` | Warrior Spirit / Призрак-воин | 5/1 |
| 4 | Enemy / Враг | `WZSP` | Wizard Spirit / Призрак-колдун | 3/2 |
| 5 | Enemy / Враг | `WLBR` | Wall of Burning Rock / Стена горящего камня | 1/3 |

**Starting graveyards / Начальные могильники:** 0: empty / пусто; 1: empty / пусто.

**Hints:**

1. The Horror must contribute in more than one phase.
2. An early sacrifice wastes future attacks. The overloaded body loses two power at the end of each of your turns.
3. Polymorph the Wizard. Give the Horror Overload, Spirit of War and Cloak of Fear. Hit for fourteen, block the regenerating Spirit, then hit for twelve. During the next forced defence, burn the Horror for the final ten.

**Подсказки:**

1. Ужас должен принести пользу в нескольких разных фазах.
2. Ранняя жертва теряет будущие атаки. Перегрузка отнимает две силы в конце каждого вашего хода.
3. Превратите Колдуна. Дайте Ужасу Перегрузку, Дух Войны и Маску Ужаса. Ударьте на четырнадцать, заблокируйте регенерирующего Призрака, затем ударьте на двенадцать. Во время следующей обязательной защиты Сожжение Ужаса даст последние десять.

**Why it works:**

The initial six ether funds all four preparations, leaving no early Burnout payment. Polymorph removes the second attacker and raises the hero to two health. The Horror attacks for fourteen, decays to twelve and remains ready to block because of Spirit of War. The Spirit regenerates and must attack again. At the second own turn one ether refills; the Horror deals twelve, then decays to ten. Preserve that ether until the following defence and use Burnout before combat. Fourteen plus twelve plus ten is exactly thirty-six. Another valid plan replaces Cloak with Bless: its eighteen-power first attack tramples for fourteen through the wall and Spirit together; the wall dies and the berserker remains resting during your second attack.

**Почему это работает:**

Начальные шесть эфира оплачивают все четыре приготовления, не оставляя платы за раннее Сожжение. Превращение убирает второго атакующего и даёт герою два здоровья. Ужас атакует на четырнадцать, ослабевает до двенадцати и благодаря Духу Войны остаётся готовым блокировать. Призрак регенерирует и снова будет обязан атаковать. Второй свой ход даёт один эфир; Ужас наносит двенадцать, затем ослабевает до десяти. Сохраните эфир до следующей защиты и примените Сожжение до разрешения боя. Четырнадцать, двенадцать и десять дают ровно тридцать шесть. Есть и другой план: вместо Маски Ужаса примените Благословение. Первая атака с силой восемнадцать наносит четырнадцать через совместный блок стены и Призрака; стена гибнет, а к вашей второй атаке берсерк уже отдыхает.

**Exact main reference / Точный основной пример:**

```json
[
  {"kind": "cast", "card": "PLMR", "target": 4},
  {"kind": "cast", "card": "OVRL", "target": 2},
  {"kind": "cast", "card": "SPWR", "target": 2},
  {"kind": "cast", "card": "CLFR", "target": 2},
  {"kind": "attack", "id": 2},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "block", "id": 2, "target": 3},
  {"kind": "end_phase"},
  {"kind": "attack", "id": 2},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "ability", "id": 0, "key": "burnout:1", "target": 2, "choice": 1}
]
```

**Declared alternative / Дополнительное решение:** Break the first blockade with Bless instead of Cloak of Fear

Use Bless instead of Cloak of Fear to break the first blockade. The following replay is a separate legal winning witness; its enemy blocks are part of that example. It is not a claim that the same enemy response will occur in every attempt.

Вместо Маски Ужаса используйте Благословение, чтобы пройти первую блокаду. Ниже дан отдельный законный пример победы; вражеские блоки относятся именно к нему и могут отличаться в другой попытке.

```json
[
  {"kind": "cast", "card": "BLSS", "target": 2},
  {"kind": "cast", "card": "OVRL", "target": 2},
  {"kind": "cast", "card": "SPWR", "target": 2},
  {"kind": "cast", "card": "PLMR", "target": 4},
  {"kind": "attack", "id": 2},
  {"kind": "end_phase"},
  {"kind": "block", "id": 5, "target": 2, "side": 1},
  {"kind": "block", "id": 3, "target": 2, "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "block", "id": 2, "target": 3},
  {"kind": "end_phase"},
  {"kind": "attack", "id": 2},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "ability", "id": 0, "key": "burnout:1", "target": 2, "choice": 1}
]
```


### Two Bequests / Два наследства

`el1_tactical_v2_crucible_two_bequests` · **Expert / Эксперт** · Own-turn limit / Лимит собственных ходов: **2** · Objective / Цель: **win / победа**

**Briefing:** Survive this attack and win within two of your own turns. Martyrdom is active. The enemy attacks through the ground, the air and a lane only a Wall can block; its Rock Wall protects the backline.

**Обстановка:** Переживите эту атаку и победите за два своих хода. Самопожертвование уже действует. Враг атакует по земле, по воздуху и существом, которое может блокировать только стена; его Каменная стена прикрывает тыл.

**Starting heroes / Герои в начале:**

| ID | Hero / Герой | Health / Жизни | Ether / Эфир | Channels / Каналы |
| --- | --- | ---: | ---: | ---: |
| 0 | Crucible challenger / Испытуемый | 1 | 2 | 4 |
| 1 | Crucible defender / Страж испытания | 18 | 0 | 0 |

**Starting creature IDs / Начальные номера существ:**

| ID | Side / Сторона | Card | Creature / Существо | Initial status / Начальное состояние |
| --- | --- | --- | --- | --- |
| 2 | You / Вы | `AVAS` | Aviak Assassin / Авиак-убийца | 2/1 |
| 3 | You / Вы | `WLLV` | Wall of Lava / Стена лавы | 1/12; enchantments / чары: SHSK |
| 4 | You / Вы | `LMMN` | Lamia Monk / Ламия-монахиня | 4/8; resting / отдыхает |
| 5 | You / Вы | `GROG` | Gray Ogre / Серый людоед | 6/5; resting / отдыхает |
| 6 | Enemy / Враг | `STMC` | Steel Mechos / Стальной мехос | 8/6 |
| 7 | Enemy / Враг | `BUDG` | Blue Dragon / Синий дракон | 8/8 |
| 8 | Enemy / Враг | `SHWL` | Shadow wolf / Призрачный волк | 8/3; enchantments / чары: STRG |
| 9 | Enemy / Враг | `RKWL` | Rock Wall / Каменная стена | 0/10 |

**Starting graveyards / Начальные могильники:** 0: empty / пусто; 1: empty / пусто.

**Hints:**

1. One winning plan borrows toughness for the opening defence and power for the finishing attack.
2. The Mechos kills a non-Wall after damaging it, even if its toughness was high enough. Keep the Wall for the Wolf.
3. Polymorph the Mechos. Sacrifice the Lamia Monk into the Assassin, block the Dragon with the Assassin and the Wolf with the Wall. On your turn, Polymorph the Dragon, strengthen the Assassin and give it the Ogre through Martyrdom. Attack for twelve, then six.

**Подсказки:**

1. Один из выигрышных планов использует стойкость жертвы для начальной защиты, а силу другой — для решающей атаки.
2. Мехос добивает повреждённое существо, даже если его стойкости хватило для выживания. Стены защищены от этого; свою стену берегите для Волка.
3. Превратите Мехоса. Пожертвуйте Ламию-монахиню Авиаку-убийце; Авиаком блокируйте Дракона, стеной — Волка. На своём ходу превратите Дракона, усильте Авиака и передайте ему Людоеда через Самопожертвование. Атакуйте на двенадцать, затем на шесть.

**Why it works:**

The Monk grants eight toughness, allowing the Assassin to survive eight aerial damage. The Ogre grants only five toughness and is saved for the attack in this line. Remove Steel Mechos to keep the Assassin alive: its execution would ignore the extra toughness. The twelve-toughness Wall covers the eight-power elusive Wolf. At your first turn, four ether pays for Polymorph, Strength and Martyrdom. The ground Rock Wall cannot block the flying Assassin, and the Wolf cannot block its elusive attack; it deals twelve, then six after the temporary Ogre bonus expires. The Wall remains to cover the counterattack.

**Почему это работает:**

Монахиня даёт восемь стойкости: Авиак выдерживает восемь воздушного урона. Людоед дал бы лишь пять; его нужно сохранить для атаки. Стального мехоса необходимо убрать: добивание убило бы Авиака несмотря на добавленную стойкость. Стена со стойкостью двенадцать держит неуловимого Волка с силой восемь. На первом своём ходу четыре эфира оплачивают Превращение, Усиление и Самопожертвование. Наземная Каменная стена не достаёт летающего Авиака, а Волк не может блокировать его неуловимую атаку. Он наносит двенадцать, затем шесть после окончания временного бонуса Людоеда. Ваша стена остаётся для отражения контратаки.

**Exact main reference / Точный основной пример:**

```json
[
  {"kind": "cast", "card": "PLMR", "target": 6},
  {"kind": "ability", "id": 0, "key": "combine:1", "target": 4, "choice": 2},
  {"kind": "block", "id": 2, "target": 7},
  {"kind": "block", "id": 3, "target": 8},
  {"kind": "end_phase"},
  {"kind": "cast", "card": "PLMR", "target": 7},
  {"kind": "cast", "card": "STRG", "target": 2},
  {"kind": "ability", "id": 0, "key": "combine:1", "target": 5, "choice": 2},
  {"kind": "attack", "id": 2},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1},
  {"kind": "attack", "id": 8, "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "block", "id": 3, "target": 8},
  {"kind": "end_phase"},
  {"kind": "attack", "id": 2},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1}
]
```


## Etherlords II

### Borrowed Violence / Заёмная сила

`el2_tactical_v2_crucible_right_corpse` · **Expert / Эксперт** · Own-turn limit / Лимит собственных ходов: **2** · Objective / Цель: **win / победа**

**Briefing:** Win within two turns. Burnout is already active. You have five ether now, but only one channel; the enemy army can kill your one-health hero on its next attack. Both graveyard creatures are available to your spells.

**Обстановка:** Победите за два хода. На вас уже действует Сожжение. Сейчас есть пять единиц эфира, но только один канал; следующая атака врага смертельна для героя с одной жизнью. Оба существа в могильнике доступны вашим заклинаниям.

**Starting heroes / Герои в начале:**

| ID | Hero / Герой | Health / Жизни | Ether / Эфир | Channels / Каналы |
| --- | --- | ---: | ---: | ---: |
| 0 | The Last Mechanist / Последний механик | 1 | 5 | 1 |
| 1 | The Winged Executioner / Крылатый палач | 28 | 0 | 0 |

**Starting creature IDs / Начальные номера существ:**

| ID | Side / Сторона | Card | Creature / Существо | Initial status / Начальное состояние |
| --- | --- | --- | --- | --- |
| 2 | Enemy / Враг | `GBAT` | Giant Bat / Гигантская летучая мышь | 5/4 |
| 3 | Enemy / Враг | `GROG` | Gray Ogre / Серый людоед | 6/5 |

**Starting graveyards / Начальные могильники:** 0: `WKHR, RZMN`; 1: empty / пусто.

**Hints:**

1. The largest printed attack is not enough. Your opening must also remove both attackers before they get a turn.
2. The Walking Horror damages the other creatures both when it arrives and when it leaves. These enemies survive one three-point wave. Alpha Strike adds printed power to the reanimated creature.
3. Quick Fix the Walking Horror, give it Alpha Strike, and use Burnout on it against the enemy hero. Its two waves clear the enemy army. On your second turn, use the only ether to Repair the Razor Man.

**Подсказки:**

1. Одной большой силы недостаточно. Начальный план должен убрать обоих врагов до их хода.
2. Ходячий ужас ранит остальных существ и при появлении, и при гибели. Эти враги переживут одну волну на три. Альфа-удар прибавляет печатную силу возвращённого существа.
3. Верните Ходячий ужас Быстрой Починкой, примените к нему Альфа-удар и принесите его в жертву Сожжением против героя. Две волны уничтожат вражескую армию. На втором ходу потратьте единственный эфир на Ремонт Потрошителя.

**Why it works:**

Quick Fix brings the Horror back as 8/8 and its arrival deals three to each enemy. Alpha Strike adds its printed nine power, making seventeen. Burnout spends the fifth ether, deals seventeen to the hero and releases the second three-point wave, killing both attackers. The Horror returns to the grave and Quick Fix returns to hand, but the next refill is only one ether. Repair the other corpse, the Razor Man: its printed eleven power supplies the exact remaining damage. Reviving the Razor Man first cannot combine a sufficiently large finish with both Horror waves before the lethal reply.

**Почему это работает:**

Быстрая Починка возвращает Ходячий ужас существом 8/8; его появление наносит каждому врагу три урона. Альфа-удар добавляет девять печатной силы: получается семнадцать. Сожжение расходует пятый эфир, наносит герою семнадцать и запускает вторую волну на три, убивая обоих врагов. Ужас возвращается в могильник, а Быстрая Починка — в руку, но следующее пополнение даёт лишь один эфир. Примените Ремонт к другому телу, Потрошителю: его одиннадцать печатной силы дают ровно недостающий урон. Начав с Потрошителя, нельзя совместить достаточный урон герою и обе волны Ужаса до смертельного ответа.

**Exact main reference / Точный основной пример:**

```json
[
  {"kind": "cast", "card": "QKFX", "target": 0, "grave": 0},
  {"kind": "cast", "card": "ALST", "target": 4},
  {"kind": "ability", "id": 0, "key": "burnout:1", "target": 4, "choice": 1},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1},
  {"kind": "cast", "card": "REPR", "target": 0, "grave": 0}
]
```


### Glass Furnace / Стеклянная печь

`el2_tactical_v2_crucible_glass_furnace` · **Expert / Эксперт** · Own-turn limit / Лимит собственных ходов: **2** · Objective / Цель: **win / победа**

**Briefing:** Win within two turns. Burnout is active. Your Carnivorous Fingus carries Strong Attack; the enemy Giant Bat carries Strength. You have six ether now, three channels, and one hero health.

**Обстановка:** Победите за два хода. На вас действует Сожжение. На Плотоядном фингусе лежит Усиление Атаки, на вражеской Гигантской летучей мыши — Усиление. Сейчас есть шесть единиц эфира, три канала и одна жизнь героя.

**Starting heroes / Герои в начале:**

| ID | Hero / Герой | Health / Жизни | Ether / Эфир | Channels / Каналы |
| --- | --- | ---: | ---: | ---: |
| 0 | The Glassworker / Стекольщик | 1 | 6 | 3 |
| 1 | The Night Hunter / Ночной охотник | 17 | 0 | 0 |

**Starting creature IDs / Начальные номера существ:**

| ID | Side / Сторона | Card | Creature / Существо | Initial status / Начальное состояние |
| --- | --- | --- | --- | --- |
| 2 | You / Вы | `CAFG` | Carnivorous Fingus / Плотоядный фингус | 1/6; enchantments / чары: STAT |
| 3 | You / Вы | `WLLV` | Wall of Lava / Стена лавы | 1/8 |
| 4 | Enemy / Враг | `GBAT` | Giant Bat / Гигантская летучая мышь | 9/4; enchantments / чары: STRG |

**Starting graveyards / Начальные могильники:** 0: empty / пусто; 1: empty / пусто.

**Hints:**

1. One creature must supply damage now; the other must survive the enemy turn before becoming the final source of damage.
2. Delusion returns to your hand when its holder leaves play. Shield of Force can fund the later attack through a different statistic, but the nine-power flyer still needs a surviving blocker.
3. Give the Wall of Lava a three-point Shield of Force. Delude the Fingus and release its six-power spores at the enemy. Block the Bat with the wall if it attacks. Next turn, Delude the wall and Burnout its eleven power into the enemy hero.

**Подсказки:**

1. Одно существо должно нанести урон сейчас; другое — пережить ход врага и стать последним источником урона.
2. Перестановка возвращается в руку, когда её носитель покидает поле. Щит Силы может обеспечить будущий урон через другую характеристику, но летуна с силой девять ещё нужно пережить.
3. Дайте Стене лавы Щит Силы на три. Примените Перестановку к фингусу и направьте его споры силой шесть в героя. Если мышь атакует, блокируйте её стеной. На следующем ходу Перестановка превратит стену в источник одиннадцати урона для Сожжения.

**Why it works:**

Shield of Force costs one plus three ether and changes the Wall of Lava from 1/8 to 1/11. Delusion spends the other two ether and turns the 1/6 Fingus into 6/1; its spores deal six and return Delusion. The wall survives the Bat's nine-point attack, and its wounds clear normally. On the second turn, the three-ether refill pays for Delusion and one Burnout activation. The wall becomes 11/1 and supplies the last eleven damage. Shielding the Fingus makes the first shot larger but leaves no defender that survives the Bat. Sacrificing the wall first leaves the hero exposed.

**Почему это работает:**

Щит Силы стоит один плюс три эфира и превращает Стену лавы из 1/8 в 1/11. Оставшиеся два эфира оплачивают Перестановку: фингус 1/6 становится 6/1. Его споры наносят шесть, а Перестановка возвращается в руку. Стена переживает девять урона от мыши; её раны затем исчезают по обычным правилам. На втором ходу три эфира оплачивают Перестановку и одно применение Сожжения. Стена становится 11/1 и наносит последние одиннадцать. Щит на фингусе усиливает первый выстрел, но оставляет армию без защитника, способного пережить удар мыши. Жертва стены в первом ходе открывает самого героя.

**Exact main reference / Точный основной пример:**

```json
[
  {"kind": "cast", "card": "SHFR", "target": 3, "power": 3},
  {"kind": "cast", "card": "DELS", "target": 2},
  {"kind": "ability", "id": 2, "key": "spores", "target": 1},
  {"kind": "end_phase"},
  {"kind": "attack", "id": 4, "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "block", "id": 3, "target": 4},
  {"kind": "end_phase"},
  {"kind": "cast", "card": "DELS", "target": 3},
  {"kind": "ability", "id": 0, "key": "burnout:1", "target": 3, "choice": 1}
]
```


### The Last Funeral / Последние похороны

`el2_tactical_v2_crucible_last_funeral` · **Expert / Эксперт** · Own-turn limit / Лимит собственных ходов: **2** · Objective / Цель: **win / победа**

**Briefing:** Win within two turns. Fury already forces the opposing creatures to attack. The Reinforced Pteros carries Shell Skin and has no ether for its active dispel. Your hero has three health, four ether and four channels; both graveyards are empty.

**Обстановка:** Победите за два хода. Бешенство уже заставляет врагов атаковать. На Армированном птеросе лежит Ледяной Панцирь; эфира для активного рассеивания у него нет. У героя три жизни, четыре эфира и четыре канала; оба могильника пусты.

**Starting heroes / Герои в начале:**

| ID | Hero / Герой | Health / Жизни | Ether / Эфир | Channels / Каналы |
| --- | --- | ---: | ---: | ---: |
| 0 | The Bone Strategist / Костяной стратег | 3 | 4 | 4 |
| 1 | The Siege Captain / Капитан осады | 28 | 0 | 0 |

**Starting creature IDs / Начальные номера существ:**

| ID | Side / Сторона | Card | Creature / Существо | Initial status / Начальное состояние |
| --- | --- | --- | --- | --- |
| 2 | You / Вы | `WLBL` | Wall of Blades / Стена лезвий | 6/9 |
| 3 | You / Вы | `GRTN` | Great Treant / Старый древень | 3/3 |
| 4 | You / Вы | `FREL` | Fire Elemental / Элементаль огня | 6/5 |
| 5 | Enemy / Враг | `RFPT` | Reinforced Pteros / Армированный птерос | 3/10; enchantments / чары: SHSK |
| 6 | Enemy / Враг | `GROG` | Gray Ogre / Серый людоед | 6/5 |
| 7 | Enemy / Враг | `TIWR` | Tick Warrior / Клещ-воин | 2/2 |

**Starting graveyards / Начальные могильники:** 0: empty / пусто; 1: empty / пусто.

**Hints:**

1. Winning the defence is only half the problem. The finishing turn needs both surviving attack power and a corpse worth returning.
2. The Pteros dispels on a combat hit. A stronger wall alone loses its enhancement before it can strike back. Alpha Strike solves that problem, but its holder will die when the enemy turn ends.
3. Give Alpha Strike to the Wall of Blades and Strength to the Great Treant. Block the Pteros with the wall, the Tick with the Treant, and the Ogre with the Fire Elemental. Next turn, Repair the wall before Burning Graves, then attack with the Treant and Elemental.

**Подсказки:**

1. Успешная защита — лишь половина задачи. Для завершающего хода нужны и живые атакующие, и подходящее тело для возвращения.
2. Птерос рассеивает чары боевым ударом. Просто усиленная стена потеряет прибавку до своего ответа. Альфа-удар решает эту проблему, но его носитель погибнет в конце хода врага.
3. Дайте Альфа-удар Стене лезвий, а Усиление — Старому древню. Стеной блокируйте птероса, древнем — клеща, Элементалем огня — людоеда. На следующем ходу примените Ремонт к стене перед Пылающими Могилами, затем атакуйте древнем и элементалем.

**Why it works:**

The alpha-striking wall has twelve power and kills the ten-toughness Pteros before its dispelling hit. Strength makes the Treant 7/3, enough to survive and kill the Tick. The Fire Elemental first-strikes the Ogre. The wall then dies when Alpha Strike expires, while both ground attackers survive. Repair removes that sole friendly grave card and deals six; Burning Graves now deals nine to the opponent without killing your three-health hero. The Treant and Elemental supply the remaining seven plus six in combat: twenty-eight total. General Haste leaves too little finishing damage; Alpha Strike on the Treant leaves the wall vulnerable to the Pteros's dispel.

**Почему это работает:**

Стена с Альфа-ударом имеет двенадцать силы и убивает птероса со стойкостью десять до его рассеивающего удара. Усиление делает древня существом 7/3: он переживает клеща и убивает его. Элементаль огня первым ударом уничтожает людоеда. Затем Альфа-удар заканчивается и убивает стену, но оба наземных бойца остаются живы. Ремонт убирает единственную карту из вашего могильника и наносит шесть. Пылающие Могилы наносят врагу девять, не убивая героя с тремя жизнями. Древень и элементаль добавляют в бою семь и шесть: всего двадцать восемь. Общая Спешка не оставляет достаточного урона для завершения; Альфа-удар на древне оставляет стену уязвимой к рассеиванию птероса.

**Exact main reference / Точный основной пример:**

```json
[
  {"kind": "cast", "card": "ALST", "target": 2},
  {"kind": "cast", "card": "STRG", "target": 3},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1},
  {"kind": "block", "id": 2, "target": 5},
  {"kind": "block", "id": 3, "target": 7},
  {"kind": "block", "id": 4, "target": 6},
  {"kind": "end_phase"},
  {"kind": "cast", "card": "REPR", "target": 0, "grave": 0},
  {"kind": "cast", "card": "BRGR", "target": -1},
  {"kind": "attack", "id": 3},
  {"kind": "attack", "id": 4},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1}
]
```


### Two Doors, One Key / Две двери — один ключ

`el2_tactical_v2_crucible_two_doors` · **Expert / Эксперт** · Own-turn limit / Лимит собственных ходов: **2** · Objective / Цель: **win / победа**

**Briefing:** Win within two turns. Transfer Aspects is active. Your Pale Knight has just been summoned into the Ether and cannot use its own dissipation yet; your Invoker and the enemy Knight are in the Colourless Plane. The enemy has Polymorph and will refill one ether on its turn.

**Обстановка:** Победите за два хода. На вас действует Обмен Планами. Ваш Бесцветный Рыцарь только что призван в Эфирный План и пока не может сам уйти в Бесцветный; ваш Чародей и вражеский Рыцарь находятся в Бесцветном Плане. У врага есть Превращение и один канал для следующего пополнения.

**Starting heroes / Герои в начале:**

| ID | Hero / Герой | Health / Жизни | Ether / Эфир | Channels / Каналы |
| --- | --- | ---: | ---: | ---: |
| 0 | The Gatekeeper / Привратник | 1 | 2 | 3 |
| 1 | The Keeper of Bodies / Хранитель тел | 11 | 0 | 1 |

**Starting creature IDs / Начальные номера существ:**

| ID | Side / Сторона | Card | Creature / Существо | Initial status / Начальное состояние |
| --- | --- | --- | --- | --- |
| 2 | You / Вы | `SMWB` | Pale Knight / Бесцветный Рыцарь | 8/8; newly summoned / только призвано |
| 3 | You / Вы | `OUS2` | Pale Invoker / Бесцветный Чародей | 1/2; Colourless Plane / Бесцветный План |
| 4 | Enemy / Враг | `SMWB` | Pale Knight / Бесцветный Рыцарь | 8/8; Colourless Plane / Бесцветный План |
| 5 | Enemy / Враг | `RKWL` | Rock Wall / Каменная стена | 0/10 |
| 6 | Enemy / Враг | `STMC` | Steel Mechos / Стальной мехос | 8/6 |

**Starting graveyards / Начальные могильники:** 0: empty / пусто; 1: empty / пусто.

**Hints:**

1. The first exchange has to do two jobs: make a valuable spell target accessible and keep your future attacker safe from the enemy's answer.
2. Polymorph sets your health to the victim's power plus toughness. Exchange does not require its participants to be ready. Save Alpha Strike for the second turn, when it can produce an attack.
3. Exchange the enemy Knight into the Ether and your own Knight into the Colourless Plane, then Polymorph the enemy Knight. Next turn, drain any remaining enemy ether with the Invoker. Exchange your Knight out and the wall in, then Alpha Strike and attack. If the enemy Polymorphed its own wall, exchange its remaining Mechos instead.

**Подсказки:**

1. Первый обмен должен одновременно открыть ценную цель для заклинания и спасти будущего атакующего от вражеского ответа.
2. Превращение устанавливает здоровье по сумме силы и стойкости жертвы. Для Обмена Планами готовность существ не нужна. Сохраните Альфа-удар до второго хода, когда сможете действительно атаковать.
3. Обменяйте планы вражеского и своего Рыцарей, затем примените Превращение к вражескому. На следующем ходу Чародеем заберите оставшийся у врага эфир. Обменяйте планы своего Рыцаря и стены, примените Альфа-удар и атакуйте. Если враг превратил свою стену, отправьте в Бесцветный План оставшегося мехоса.

**Why it works:**

The first exchange spends one ether and protects the still-sick Knight without asking it to activate an ability. Polymorph spends the other ether and sets your health to sixteen; you can survive the Mechos's eight-point attack. The second refill is three: one for another exchange and two for Alpha Strike. With the wall hidden, the sixteen-power trampling Knight deals at least ten through a six-toughness Mechos. If Polymorph remains in the enemy hand, the Invoker drains its one ether and deals the one point that reduces eleven health to ten. If the enemy instead spends Polymorph on a friendly creature, its maximum resulting health is fourteen and the remaining blocker can be exchanged away. A different first Polymorph target leaves the enemy Knight available to obstruct or heal, while spending Alpha Strike early loses the required finishing power.

**Почему это работает:**

Первый обмен расходует один эфир и укрывает ещё неготового Рыцаря без применения его собственной способности. Превращение тратит второй эфир и устанавливает здоровье на шестнадцати: этого хватает, чтобы пережить удар мехоса на восемь. Следующее пополнение даёт три — один на новый обмен и два на Альфа-удар. После исчезновения стены Рыцарь с силой шестнадцать и пробивным ударом наносит не меньше десяти сквозь мехоса со стойкостью шесть. Если Превращение осталось у врага, Чародей забирает единственный эфир и снимает одну жизнь: из одиннадцати получается десять. Если враг сам потратил Превращение на своё существо, итоговое здоровье не превышает четырнадцати, а оставшегося защитника можно убрать обменом. Иная первая цель Превращения оставляет вражеского Рыцаря для защиты или лечения, а ранний Альфа-удар лишает завершающей силы.

**Exact main reference / Точный основной пример:**

```json
[
  {"kind": "ability", "id": 0, "key": "recycle:1", "target": 4, "choice": 2},
  {"kind": "cast", "card": "PLMR", "target": 4},
  {"kind": "end_phase"},
  {"kind": "attack", "id": 6, "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "end_phase"},
  {"kind": "ability", "id": 3, "key": "ether_plea", "target": 1},
  {"kind": "ability", "id": 0, "key": "recycle:1", "target": 2, "choice": 5},
  {"kind": "cast", "card": "ALST", "target": 2},
  {"kind": "attack", "id": 2},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1}
]
```


### The Venom Clock / Часы яда

`el2_tactical_v2_crucible_venom_clock` · **Expert / Эксперт** · Own-turn limit / Лимит собственных ходов: **3** · Objective / Цель: **win / победа**

**Briefing:** Win within three turns. You have one hero health, five ether and no channels. Your Gray Ogre is resting. The enemy Bat is poisonous, the Lamia Warlord has first strike and trample, and the enemy can afford Haste after its next refill.

**Обстановка:** Победите за три хода. У вас одна жизнь героя, пять эфира и ни одного канала. Серый людоед отдыхает. Вражеская мышь ядовита, Ламия-повелительница обладает первым и пробивным ударами, а следующее пополнение позволит врагу применить Спешку.

**Starting heroes / Герои в начале:**

| ID | Hero / Герой | Health / Жизни | Ether / Эфир | Channels / Каналы |
| --- | --- | ---: | ---: | ---: |
| 0 | The Patient Venomist / Терпеливый отравитель | 1 | 5 | 0 |
| 1 | The Venom Cavalry / Ядовитая конница | 9 | 0 | 2 |

**Starting creature IDs / Начальные номера существ:**

| ID | Side / Сторона | Card | Creature / Существо | Initial status / Начальное состояние |
| --- | --- | --- | --- | --- |
| 2 | You / Вы | `TRSN` | Tree Snake / Древесная змея | 1/1 |
| 3 | You / Вы | `WLAR` | Wall of Air / Стена воздуха | 0/2 |
| 4 | You / Вы | `WLBL` | Wall of Blades / Стена лезвий | 6/9 |
| 5 | Enemy / Враг | `GBAT` | Giant Bat / Гигантская летучая мышь | 5/4; enchantments / чары: SPBA |
| 6 | Enemy / Враг | `LMWD` | Lamia Warlord / Ламия-повелительница | 8/7 |
| 7 | You / Вы | `GROG` | Gray Ogre / Серый людоед | 6/5; resting / отдыхает |

**Starting graveyards / Начальные могильники:** 0: empty / пусто; 1: empty / пусто.

**Hints:**

1. The Snake supplies a growing clock. The resting Ogre is your next-turn reserve: preserving it changes which attacks the enemy can afford to make.
2. Cloak of Fear on the Snake and Shell Skin on the air wall leave one ether. That reserve can regenerate the Wall of Blades after poison on the first enemy turn. Do not offer the Ogre to a ready first-striking blocker.
3. Cloak the Snake; armor Air. Attack with Snake every turn. If Bat alone attacks first, Blades blocks and regenerates. If both attack first, Air blocks Bat and Blades blocks Lamia; counterattack with Snake and Ogre. Keep Ogre against a ready first striker. For a later combined attack, Blades blocks Bat; Air FIRST and Ogre SECOND block Lamia. If the enemy delays, retain the reserve and let venom finish.

**Подсказки:**

1. Змея запускает растущий отсчёт. Отдыхающий людоед — резерв следующего хода: сохранив его, вы меняете то, какие атаки может позволить себе враг.
2. Маска Ужаса на змее и Ледяной Панцирь на воздушной стене оставляют один эфир. В первый вражеский ход этот запас может оплатить регенерацию Стены лезвий после яда. Не отдавайте людоеда готовому блокирующему с первым ударом.
3. Дайте змее Маску Ужаса, воздушной стене — Ледяной Панцирь. Атакуйте змеёй каждый ход. Первую отдельную атаку мыши примите лезвиями и регенерируйте. Если сначала атакуют оба, воздушная стена блокирует мышь, лезвия — ламию; затем контратакуйте змеёй и людоедом. Сохраняйте людоеда против готового первого удара. В поздней общей атаке лезвия блокируют мышь, воздушная стена ПЕРВОЙ и людоед ВТОРЫМ — ламию. Если враг медлит, держите резерв и дождитесь яда.

**Why it works — complete adaptive policy:**

Cloak of Fear makes the Snake unblockable; Shell Skin makes the Wall of Air 0/6. Their four-ether cost leaves one for a possible first-turn regeneration. Keep the Ogre. Three Snake hits plus the enemy-turn venom ticks of one, two and three total nine, but the defence must follow the enemy’s timing.

On the first enemy turn: if only the Bat attacks, block it with the Wall of Blades. Blades survives five damage, kills the Bat, and spends the reserved ether regenerating through poison. If only the Lamia attacks, Blades holds it. If both attack, Air blocks Bat and Blades blocks Lamia; Air dies to poison, but both enemies are then resting, so the newly ready Ogre and Snake deal the exact seven remaining damage on turn two. If neither attacks, keep the army intact.

From turn two onward, do not send the Ogre into a ready first-striking Lamia or a Bat still covered by Haste. It is needed as a reserve defender. Against a combined attack while both walls remain, put Blades on Bat and order Air FIRST, Ogre SECOND against Lamia. Air absorbs six of the Lamia’s eight damage; the Ogre survives the other two. Blades kills Bat and dies to poison, while the surviving Ogre can counterattack once the Lamia rests. Against a lone Bat, Blades can trade with it and leave Air plus Ogre to hold a later Lamia attack. Against a lone Lamia, Blades can hold it while it remains available.

The reference demonstrates the demanding delayed attack: the enemy casts Haste and sends only Lamia first, then both attackers on turn two. Hold the Ogre until the ordered double block; Snake and Ogre finish on turn three. If the enemy keeps a dangerous blocker ready, hold the Ogre instead, block the final reply, and let the third venom tick finish. A fixed early Martyrdom sacrifice is not a universal policy: the opponent can wait for its temporary creature bonus to expire.

**Почему это работает — полный план для разных ответов:**

Маска Ужаса делает змею неблокируемой, а Ледяной Панцирь превращает Стену воздуха в 0/6. Четыре потраченных эфира оставляют один для возможной регенерации в первом вражеском ходе. Сохраните людоеда. Три удара змеи и срабатывания яда на один, два и три дают девять, но защита зависит от времени вражеских атак.

В первый вражеский ход: если атакует только мышь, блокируйте Стеной лезвий. Она переживёт пять урона, убьёт мышь и потратит сохранённый эфир на регенерацию после яда. Если атакует только ламия, её держит Стена лезвий. Если атакуют оба, воздушная стена принимает мышь, а лезвия — ламию. Воздушная стена погибнет от яда, зато оба врага начнут отдыхать: на втором ходу готовый людоед и змея нанесут ровно семь оставшихся единиц урона. Если не атакует никто, сохраняйте армию.

Начиная со второго хода не отправляйте людоеда на готовую Ламию-повелительницу или мышь, на которой ещё действует Спешка: их первый удар убьёт его. Людоед нужен в резерве. Против общей атаки, пока обе стены живы, поставьте лезвия против мыши, а против ламии назначьте воздушную стену ПЕРВОЙ, людоеда ВТОРЫМ. Стена примет шесть из восьми единиц урона, людоед переживёт остальные две. Лезвия убьют мышь и погибнут от яда; выживший людоед сможет контратаковать после отдыха ламии. Против одной мыши лезвия могут разменяться, оставив воздушную стену и людоеда для будущей атаки ламии. Одну ламию можно удерживать лезвиями, пока эта стена остаётся в строю.

Пример решения показывает сложную задержанную атаку: враг применяет Спешку и сначала отправляет только ламию, а на втором ходу — обоих. Сохраните людоеда до упорядоченного двойного блока; змея и людоед завершат бой на третьем ходу. Если враг оставляет опасного блокирующего готовым, сохраняйте людоеда, переживите последний ответ и дайте третьему яду добить героя. Раннее Самопожертвование не является универсальным планом: противник может дождаться окончания временного усиления существа.

**Exact main reference / Точный основной пример:**

```json
[
  {"kind": "cast", "card": "CLFR", "target": 2},
  {"kind": "cast", "card": "SHSK", "target": 3},
  {"kind": "attack", "id": 2},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1},
  {"kind": "cast", "card": "HAST", "target": -1, "side": 1},
  {"kind": "attack", "id": 6, "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "block", "id": 4, "target": 6},
  {"kind": "end_phase"},
  {"kind": "attack", "id": 2},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1},
  {"kind": "attack", "id": 5, "side": 1},
  {"kind": "attack", "id": 6, "side": 1},
  {"kind": "end_phase", "side": 1},
  {"kind": "block", "id": 4, "target": 5},
  {"kind": "block", "id": 3, "target": 6},
  {"kind": "block", "id": 7, "target": 6},
  {"kind": "end_phase"},
  {"kind": "attack", "id": 2},
  {"kind": "attack", "id": 7},
  {"kind": "end_phase"},
  {"kind": "end_phase", "side": 1}
]
```


## Source of truth

The puzzle IDs, setups, staged hints and exact commands in this guide come from the installed `game/puzzles/el1.json` and `game/puzzles/el2.json` entries tagged `crucible-v1`. Venom’s expanded explanation is preserved here because the in-game result panel uses a shorter version. The full setup remains in the catalogs; this guide does not add a new objective or restrict the game to the printed witness.

Идентификаторы, позиции, подсказки и команды взяты из установленных каталогов с меткой `crucible-v1`. Расширенное объяснение «Часов яда» сохранено здесь; окно результатов в игре показывает сокращённый текст. Это руководство не вводит дополнительных условий победы и не ограничивает игру приведённым примером.
