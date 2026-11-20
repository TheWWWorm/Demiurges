class_name ELExpeditionContent
extends RefCounted
## Expedition-only passives and events. They use existing duel rules rather
## than changing the printed effects of cards shared with other game modes.

const STARTING_RELICS := ["amber_seed", "silver_scale", "glass_compass"]
const RELIC_SHOP_PRICES := {"amber_seed": 65, "silver_scale": 45, "glass_compass": 65,
	"hunters_badge": 60, "merchant_seal": 35, "travel_rations": 65, "pilgrims_flask": 45,
	"aether_prism": 85, "duelists_crest": 80, "ember_purse": 45, "purifier_stone": 70, "twin_seal": 55}
const RELICS := {
	"amber_seed": ["Amber Seed", "Янтарное семя",
		"Recover 2 life after every victory.", "Восстанавливает 2 ед. здоровья после каждой победы."],
	"silver_scale": ["Silver Scale", "Серебряная чешуйка",
		"Earn 6 extra gold after every victory.", "Приносит ещё 6 золотых после каждой победы."],
	"glass_compass": ["Glass Compass", "Стеклянный компас",
		"Spell rewards offer one extra spell to choose from. You still take one reward.", "В награде за бой на одно заклинание больше. Взять можно только одну награду."],
	"hunters_badge": ["Hunter's Badge", "Знак охотника",
		"Earn 20 extra gold after elite and guardian victories, including event duels.", "Приносит ещё 20 золотых за победы над элитой и стражами, включая бои в событиях."],
	"merchant_seal": ["Merchant's Seal", "Печать торговца",
		"Pay 20% less at merchants. Event prices stay the same.", "Цены у торговцев ниже на 20%. Цены в событиях не меняются."],
	"travel_rations": ["Wayfarer's Rations", "Припасы странника",
		"Recover 2 life on entering an event, merchant, camp, or treasure room.", "Восстанавливает 2 ед. здоровья при входе в событие, лавку, лагерь или сокровищницу."],
	"pilgrims_flask": ["Pilgrim's Flask", "Фляга паломника",
		"Resting at camp restores 45% of maximum life instead of 30%.", "Отдых в лагере восстанавливает 45% максимального здоровья вместо 30%."],
	"aether_prism": ["Ether Prism", "Эфирная призма",
		"Fight one hero level higher in every duel, up to level 20.", "Уровень героя в каждом бою выше на один, но не выше 20-го."],
	"duelists_crest": ["Duelist's Crest", "Герб дуэлянта",
		"With 12 or fewer pages in your active book, fight two hero levels higher, up to level 20.", "Если в боевой книге не больше 12 страниц, уровень героя в бою выше на два, но не выше 20-го."],
	"ember_purse": ["Ember Purse", "Кошель с угольком",
		"Win a duel by the end of round 6 to earn 12 extra gold.", "Победа не позднее 6-го раунда приносит ещё 12 золотых."],
	"purifier_stone": ["Purifier's Stone", "Камень очищения",
		"The one spell removal offered at each merchant is free.", "Одно удаление заклинания у каждого торговца бесплатно."],
	"twin_seal": ["Master's Seal", "Печать мастера",
		"You can train combat skills three times per run instead of twice.", "Можно улучшать боевые навыки трижды за поход вместо двух раз."],
}

# These are new Expedition items, not additions to the original artifact
# catalog. The setting references are documented in expedition_lore_sources.md.
const RELIC_LORE := {
	"amber_seed": ["A Vital hermit kept it in a pouch of mandrake leaves.", "Отшельник-витал хранил его в мешочке с листьями мандрагоры."],
	"silver_scale": ["A Kinet trader brought it from the City of Eight Gates.", "Торговец-кинет привёз её из Города Восьми Ворот."],
	"glass_compass": ["A lens from an Ocularis Orb turns behind the glass.", "За стеклом поворачивается линза Магического Глаза."],
	"hunters_badge": ["Soot from a Chaot monster arena still marks its edge.", "По краю ещё видна копоть с арены чудовищ Хаотов."],
	"merchant_seal": ["Its stamp comes from the Market Place of the City of Eight Gates.", "На ней стоит клеймо Рынка Города Восьми Ворот."],
	"travel_rations": ["Vital trail food, packed with herbs gathered beside the forest rivers.", "Дорожная еда Виталов с травами, собранными у лесных рек."],
	"pilgrims_flask": ["A Vital hermit marked it with a passage from the Book of Life.", "Отшельник-витал начертал на ней строки из Книги Жизни."],
	"aether_prism": ["A Kinet lens etched with the paths of the four suns.", "Линза Кинетов с выгравированными путями четырёх светил."],
	"duelists_crest": ["A tournament crest from the Kinets' ice labyrinth.", "Знак участника турнира в ледяном лабиринте Кинетов."],
	"ember_purse": ["A Chaot arena champion left a singed purse as the next prize.", "Победитель арены Хаотов оставил этот подпалённый кошель следующему претенденту."],
	"purifier_stone": ["A Synthet crystal cut from a disused Purify Station.", "Кристалл Синтетов, отколотый от заброшенной Очистной Станции."],
	"twin_seal": ["Its paired marks were copied from a Shrine of Knowledge.", "Парные знаки скопированы со Святыни Знания."],
}

# Guardian rewards have a separate pool so adding them never changes old
# merchants, starting boons, or version-eight/nine seeded relic offers.
const KEYSTONES := {
	"blood_crown": ["Blood Crown", "Кровавая корона",
		"Fight one hero level higher, up to level 20. You can no longer take healing instead of a spell reward. Other healing still works.",
		"Уровень героя в бою выше на один, но не выше 20-го. Больше нельзя выбирать лечение вместо заклинания в награде. Другие способы лечения действуют."],
	"living_heart": ["Living Heart", "Живое сердце",
		"Gain 8 maximum life and recover 8 life now. Pay 20% more at merchants. Apply this and the Merchant's Seal discount before rounding the price up.",
		"Максимум здоровья увеличивается на 8; сразу восстанавливается 8 ед. здоровья. Цены у торговцев выше на 20%. Надбавка и скидка Печати торговца применяются до округления цены вверх."],
	"prismatic_quill": ["Prismatic Quill", "Призматическое перо",
		"Spell rewards offer one extra spell to choose from. Your one reward redraw per act is free. You still take one reward.",
		"В награде за бой на одно заклинание больше. Обновление награды один раз за акт бесплатно. Взять можно только одну награду."],
	"wayfarer_compass": ["Wayfarer's Compass", "Компас странника",
		"Once per act, reach a room on the next floor without a connecting path. Following a marked path keeps this detour available.",
		"Один раз за акт можно перейти в комнату следующего этажа, к которой не ведёт путь. Переходы по отмеченным путям не расходуют эту возможность."],
}

const KEYSTONE_LORE := {
	"blood_crown": ["Its inner band carries a Chaot oath to the Flame of Chaos.", "На внутренней стороне начертана клятва Хаотов пламени Хаоса."],
	"living_heart": ["A living knot of wood, tended by a Vital forest keeper.", "Живой древесный нарост, выращенный хранителем леса из Виталов."],
	"prismatic_quill": ["A Kinet quill cut for the fine lettering of the City of Eight Gates.", "Перо Кинетов, заточенное для изящной каллиграфии Города Восьми Ворот."],
	"wayfarer_compass": ["Its dial was salvaged from a teleporter's receiver.", "Его шкала снята с приёмной части телепорта."],
}

# Indices extend, and never reorder, the five original events.
const EVENTS := [
	["Caravan in the Mist", "Караван в тумане",
		"A caravan has lost its way. Browse its wares, or guide it to safety for a small payment.",
		"Караван сбился с пути. Посмотрите товары или проводите его за небольшую плату."],
	["The Lost Courier", "Заблудившийся курьер",
		"A courier needs 20 gold to reopen a supply route. Win two more duels to receive 55 gold. The contract survives the next act.",
		"Курьер просит 20 золотых на восстановление пути. После ещё двух побед вы получите 55 золотых. Договор действует и в следующем акте."],
	["Runesmith's Forge", "Кузница рун",
		"The runesmith can turn a common spell into a rarer one of the same type, or teach a combat skill. You may choose one service.",
		"Мастер может обменять обычное заклинание на более редкое того же типа или научить боевому навыку. Выберите одну услугу."],
	["The Wounded Cartographer", "Раненый картограф",
		"A mapmaker offers coin for help crossing a dangerous pass. Or pay for the healing supplies in their pack.",
		"Картограф заплатит за помощь на опасном перевале. Можно и самому купить целебные припасы из его сумки."],
	["The Veteran's Trial", "Испытание ветерана",
		"Face an elite duelist for a relic and spell reward. Win by round 6 for 30 extra gold. Defeat ends the expedition; walking away is safe.",
		"Победите элитного дуэлянта ради реликвии и заклинания. Победа не позднее 6-го раунда даст ещё 30 золотых. Поражение завершит поход; уйти можно без риска."],
	["The Sealed Vault", "Запечатанное хранилище",
		"One relic waits behind the seal. Buy its release, or break the ward with your own life. Both choices claim the same relic.",
		"За печатью скрывается реликвия. Заплатите за её освобождение или сломайте защиту ценой здоровья. Обе сделки дают одну и ту же реликвию."],
	["Feast of Wanderers", "Пир странников",
		"Share a modest meal, buy a restorative feast, or provision your next duel. Provisions raise your hero's level by one for that duel only.",
		"Разделите скромную трапезу, купите сытный обед или припасы для следующего боя. Припасы повысят уровень героя на один только в этом бою."],
	["The Relic Broker", "Меняла реликвий",
		"Trade one of your relics and 12 gold for a different passive. Inspect the offers before choosing which relic to surrender.",
		"Обменяйте одну свою реликвию и 12 золотых на другую. Изучите предложения, прежде чем решать, с чем расстаться."],
	["The Bounty Board", "Доска заказов",
		"Pay a 10-gold bond for an optional contract. Meet its objective within your next two victories to collect the payment. An expired contract pays nothing.",
		"Внесите залог в 10 золотых за добровольный заказ. Выполните условие за две следующие победы, чтобы получить плату. Просроченный заказ не оплачивается."],
	["The Crossroads Archive", "Архив на перекрёстке",
		"Study a different school to steer future spell rewards and merchant stock, or sell copies of your travel notes. Choose one service.",
		"Изучите другую школу, чтобы изменить будущие награды и товары торговцев, или продайте путевые заметки. Выберите одну услугу."],
	["The Resonant Anvil", "Резонирующая наковальня",
		"Bind two identical common or cantrip pages from your active book into one rarer spell of the same type for 12 gold. Inspect the result first. Your book loses a page and its charges; you can salvage metal for 10 gold instead.",
		"За 12 золотых соедините две одинаковые обычные или простейшие страницы боевой книги в одно более редкое заклинание того же типа. Сначала изучите результат. Книга потеряет страницу и её заряды; вместо этого можно собрать металл на 10 золотых."],
	["The Abandoned Library", "Заброшенная библиотека",
		"Pack one affordable common spell into your two-page reserve, or sell the catalogue for 12 gold. Reserved pages cannot be used in battle until exchanged into the active book at camp or the Last Haven.",
		"Возьмите одно недорогое обычное заклинание в запас на две страницы или продайте каталог за 12 золотых. Запасные страницы нельзя использовать в бою, пока вы не обменяете их со страницами боевой книги на привале или Последнем привале."],
]

# Version twelve separates the scene from the rules shown on each choice.
# Keep EVENTS above intact for resumed runs using the previous event text.
const SCENES := [
	["Wayside Spring", "Придорожный источник",
		"A Vital hermit has spread mandrake leaves and charged artifacts beside the spring. Their book lies open at a passage from the Book of Life.",
		"Отшельник-витал разложил у родника листья мандрагоры и заряженные артефакты. Его книга раскрыта на строках, переписанных из Книги Жизни."],
	["Spellwright's Mirror", "Зеркало чародея",
		"A Kinet scribe has set an Ocularis Orb's lens in a copper mirror. In its reflection, your spellbook keeps changing.",
		"Писец-кинет вставил линзу Магического Глаза в медное зеркало. В отражении строки вашей книги всё время меняются."],
	["Totem of the Wilds", "Тотем диких земель",
		"A Vital keeper has carved the cycle of life and death into a wooden shrine. Fresh herbs lie beside its bloodstained offering bowl.",
		"Хранитель-витал вырезал круговорот жизни и смерти на деревянной святыне. Рядом с окровавленной чашей для подношений лежат свежие травы."],
	["The Silent Reliquary", "Безмолвный реликварий",
		"An Artifact Recharger still pulses in a deserted Synthet workshop. Freeing a charged artifact from the damaged machine will draw on your life. A sealed flask stands on the bench.",
		"В заброшенной мастерской Синтетов ещё пульсирует Реконструктор Артефактов. Чтобы вытащить заряженный артефакт из повреждённого механизма, придётся отдать часть своей жизни. На верстаке стоит закупоренная фляга."],
	["The Bridge Warden", "Страж моста",
		"Beside a bridge of Kinet ice, a duelist sets a spellbook on the parapet. The crossing is free; the challenge is an invitation.",
		"У ледяного моста, возведённого Кинетами, дуэлянт кладёт книгу на парапет. Переход свободен; поединок — лишь предложение."],
	["Caravan in the Mist", "Караван в тумане",
		"The caravan carries spell pages from the City of Eight Gates. At an unmarked fork in the Borderlands, its driver loses faith in the map.",
		"Караван везёт страницы заклинаний из Города Восьми Ворот. На развилке в Пограничье возница перестаёт доверять своей карте."],
	["The Lost Courier", "Заблудившийся курьер",
		"A Kinet messenger's cart has lost a wheel. The letter cases bear the careful calligraphy of the City of Eight Gates. Fund the repairs and clear the road ahead, and the messenger promises you a share of the delivery fee.",
		"У телеги посланника Кинетов отвалилось колесо. На футлярах с письмами — аккуратная каллиграфия Города Восьми Ворот. Если оплатить починку и расчистить дорогу впереди, посланник обещает долю платы за доставку."],
	["Runesmith's Forge", "Кузница рун",
		"A Synthet technician has fitted a smith's bench with laboratory clamps. Beside it, diagrams show how to take a spell's pattern apart.",
		"Техник-синтет оснастил кузнечный верстак лабораторными зажимами. На схемах рядом показано, как разобрать узор заклинания."],
	["The Wounded Cartographer", "Раненый картограф",
		"A Kinet mapmaker has bound a torn wing. Their map marks the northern peninsula, but the next pass is too steep to cross alone.",
		"Картограф-кинет перевязал порванное крыло. На его карте отмечен Северный Полуостров, но ближайший перевал слишком крут, чтобы пройти его без помощи."],
	["The Veteran's Trial", "Испытание ветерана",
		"Scorched stones mark an old Chaot monster arena. The waiting veteran opens a spellbook and gestures to the other side of the ring.",
		"Обгорелые камни очерчивают старую арену чудовищ Хаотов. Ожидающий ветеран раскрывает книгу и указывает на другую сторону круга."],
	["The Sealed Vault", "Запечатанное хранилище",
		"A Rune Stone seals the strongroom. A trader offers its Warding Stone for coin; forcing the cracked barrier will demand something else from you.",
		"Рунная преграда запирает хранилище. Торговец предлагает Ключ-камень за плату; взлом потрескавшихся чар потребует от вас другой жертвы."],
	["Feast of Wanderers", "Пир странников",
		"Around a Chaot campfire, someone is singing of a glorious last stand. The cook interrupts long enough to ask whether you have eaten.",
		"У костра Хаотов поют о славной последней битве. Повар прерывает песню, чтобы спросить, ели ли вы сегодня."],
	["The Relic Broker", "Меняла реликвий",
		"A Kinet broker greets you with a precise bow. Relics from all four lands stand on the counter, each with a neatly written label.",
		"Меняла-кинет приветствует вас выверенным поклоном. На прилавке стоят реликвии из земель всех четырёх рас, каждая с аккуратной подписью."],
	["The Bounty Board", "Доска заказов",
		"At a Borderlands waystation, a clerk copies contracts from Kinet letters and Synthet dispatches. The ledger has room for another name.",
		"На стоянке в Пограничье писарь составляет заказы по письмам Кинетов и донесениям Синтетов. В книге осталось место ещё для одного имени."],
	["The Crossroads Archive", "Архив на перекрёстке",
		"A Kinet archivist has gathered copies from the Vault of True Knowledge. Your travel notes may fill a gap between the indexed volumes.",
		"Архивариус-кинет собрал копии записей из Хранилища Истинного Знания. Ваши путевые заметки могут заполнить пробел между томами."],
	["The Resonant Anvil", "Резонирующая наковальня",
		"A Synthet technician has wired the anvil to a Reality Convertor. Matching spell pages sit in paired clamps above a heap of metal offcuts.",
		"Техник-синтет соединил наковальню с Преобразователем Реальности. Одинаковые страницы заклинаний закреплены в парных зажимах над кучей металлических обрезков."],
	["The Abandoned Library", "Заброшенная библиотека",
		"A Kinet bookseller is emptying a deserted library before the Pale reach it. They want the catalogue; loose spell pages still cover the tables.",
		"Букинист-кинет вывозит книги из пустой библиотеки, пока сюда не добрались Бесцветные. Ему нужен каталог; на столах ещё лежат страницы заклинаний."],
	["Shrine of Knowledge", "Святыня Знания",
		"A Kinet scholar has spread spell diagrams at the foot of a Shrine of Knowledge. They set aside an unfinished copy and make room for your book.",
		"Учёный-кинет разложил схемы заклинаний у Святыни Знания. Он откладывает незаконченные записи и освобождает место для вашей книги."],
	["The Artifact Constructor", "Мастерская артефактов",
		"A Synthet artificer has unfinished artifacts laid out beside a salvage crate. Take a project to finish on the road, or help sort the usable metal.",
		"Мастер-синтет разложил у ящика с ломом незаконченные артефакты. Можно взять заготовку для сборки в пути или помочь разобрать годный металл."],
]

# Keys use the event index and the completed action's prefix. These are
# optional scene endings; the run receipt supplies the actual resource changes.
const OUTCOME_LINES := {
	"0:recover": ["The hermit waits while you drink, then returns to sorting mandrake.", "Отшельник ждёт, пока вы напьётесь, и снова перебирает мандрагору."],
	"0:trade": ["The Vital checks the copied lines. The last letters darken as the blood dries.", "Витал проверяет переписанные строки. Последние буквы темнеют по мере высыхания крови."],
	"0:borrow": ["The hermit wraps a charged artifact and places it beside your book.", "Отшельник заворачивает заряженный артефакт и кладёт его рядом с вашей книгой."],
	"1:craft": ["The Kinet adjusts the Ocularis lens until the reflected spell and your new page agree.", "Кинет поворачивает линзу Магического Глаза, пока отражённое заклинание не совпадёт с новой страницей."],
	"1:purge": ["The scribe covers the lens. When you look again, the unwanted spell is gone.", "Писец прикрывает линзу. Когда вы смотрите снова, ненужного заклинания уже нет."],
	"1:echo": ["Your reflection finishes first. The Kinet compares the matching pages and nods.", "Отражение заканчивает первым. Кинет сравнивает одинаковые страницы и кивает."],
	"2:oath": ["The Vital keeper finishes the rite. The wound remains; the oath is taken.", "Хранитель-витал завершает обряд. Рана остаётся; клятва принята."],
	"2:mend": ["The keeper shares the bitter herbs and leaves the offering bowl alone.", "Хранитель делится горькими травами, не касаясь чаши для подношений."],
	"3:keep": ["You lift the artifact from the Recharger. Its glow follows you out of the workshop.", "Вы забираете артефакт из Реконструктора. Его свечение провожает вас из мастерской."],
	"3:mend": ["You return the flask to the Synthet workbench and leave the machinery humming.", "Вы возвращаете флягу на верстак Синтетов и оставляете механизмы гудеть."],
	"3:recharge_artifact": ["The Recharger draws blood through its cracked fittings. You disconnect your artifact when its light steadies.", "Реконструктор тянет кровь сквозь треснувшие крепления. Когда свечение артефакта выравнивается, вы отсоединяете его от машины."],
	"5:caravan_guide": ["You find the next Borderlands sign. The wagons roll on toward firmer roads.", "Вы находите следующий указатель Пограничья. Повозки выходят на дорогу потвёрже."],
	"6:courier_contract": ["The Kinet pays a wheelwright, then returns to guarding the letter cases.", "Кинет платит мастеру и возвращается сторожить футляры с письмами."],
	"6:courier_wages": ["The messenger checks the delivery, pays you, and returns to the troublesome wheel.", "Посланник проверяет доставку, расплачивается и снова принимается за злополучное колесо."],
	"7:craft": ["The Synthet releases the clamps and checks the new spell against the diagram.", "Синтет раскрывает зажимы и сверяет новое заклинание со схемой."],
	"7:forge_train": ["The technician checks each exercise twice before returning your book.", "Техник дважды проверяет каждое упражнение, прежде чем вернуть вашу книгу."],
	"8:cartographer_help": ["Beyond the pass, the Kinet steadies the bound wing and pays you.", "За перевалом кинет поправляет перевязанное крыло и расплачивается с вами."],
	"8:cartographer_heal": ["The mapmaker hands over the medicine, careful not to disturb the injured wing.", "Картограф отдаёт лекарство, стараясь не задеть повреждённое крыло."],
	"10:vault_buy": ["The trader seats the Warding Stone in its slot. The barrier fades.", "Торговец вставляет Ключ-камень в паз. Преграда гаснет."],
	"10:vault_blood": ["Your spell cracks the Rune Stone. The backlash strikes before the barrier falls.", "Ваше заклинание раскалывает Рунную преграду. Обратный удар достигает вас раньше, чем чары рушатся."],
	"11:feast_meal": ["The Chaots make room by the fire. The singer starts the interrupted verse again.", "Хаоты освобождают место у огня. Певец снова начинает прерванный куплет."],
	"11:feast_heal": ["The Chaot cook fills your bowl again and tells the singer to leave you in peace.", "Повар-хаот снова наполняет вашу миску и велит певцу оставить вас в покое."],
	"11:feast_prepare": ["The cook wraps food for the road while the Chaots argue over the song's ending.", "Повар заворачивает еду в дорогу, пока Хаоты спорят о конце песни."],
	"12:broker_exchange": ["The Kinet replaces a label, puts your old relic away, and completes the exchange with a bow.", "Кинет меняет подпись, убирает вашу прежнюю реликвию и завершает обмен поклоном."],
	"13:bounty": ["The clerk enters your name beneath the dispatch and locks the bond in a small chest.", "Писарь вписывает ваше имя под донесением и запирает залог в небольшом ларце."],
	"14:refocus": ["The Kinet returns the archive copies to their shelves and hands back your notes.", "Кинет возвращает архивные копии на полки и отдаёт ваши заметки."],
	"14:archive_notes": ["The Kinet files a copy of your notes beside the older records. You keep the originals.", "Кинет подшивает копию ваших заметок к старым записям. Оригиналы остаются у вас."],
	"15:craft": ["The Reality Convertor falls quiet. The technician releases a single page from the paired clamps.", "Преобразователь Реальности затихает. Техник вынимает из парных зажимов одну страницу."],
	"15:anvil_salvage": ["The Synthet weighs the metal offcuts, pays you, and sorts them for reuse.", "Синтет взвешивает обрезки металла, платит вам и сортирует их для повторного использования."],
	"16:add": ["You bind the saved page into your book before the Kinet closes the shutters.", "Вы подшиваете спасённую страницу в книгу, прежде чем кинет закрывает ставни."],
	"16:replace": ["The old spell stays in the library. You carry the rescued page in its place.", "Прежнее заклинание остаётся в библиотеке. На его месте вы уносите спасённую страницу."],
	"16:reserve_add": ["You wrap the saved spell separately from your active book, ready for a later camp.", "Вы заворачиваете спасённое заклинание отдельно от боевой книги, до следующего привала."],
	"16:reserve_replace": ["You set the old reserve page aside and pack the one saved from the library.", "Вы откладываете прежнюю запасную страницу и берёте спасённую из библиотеки."],
	"16:library_notes": ["The Kinet pays for the catalogue and packs it with the books bound for safety.", "Кинет платит за каталог и укладывает его вместе с книгами, приготовленными к вывозу."],
	"17:opening_spell": ["The scholar rolls up the diagrams. Before leaving, you rehearse the opening words once more.", "Учёный сворачивает схемы. Перед уходом вы ещё раз повторяете начало заклинания."],
	"17:scholar_notes": ["The Kinet checks your copy, pays you, and returns to the shrine's inscriptions.", "Кинет проверяет вашу копию, расплачивается и возвращается к надписям на святыне."],
	"18:project": ["The Synthet wraps the blank artifact with its parts and a marked assembly diagram. You pack the bundle for a later stop.", "Синтет заворачивает заготовку вместе с деталями и размеченной схемой сборки. Вы убираете свёрток до следующей стоянки."],
	"18:constructor_salvage": ["The Synthet weighs the usable metal and counts out your payment. The unfinished artifacts stay on the bench.", "Синтет взвешивает годный металл и отсчитывает плату. Незаконченные артефакты остаются на верстаке."],
}

static func text(profile: ELProfile, en: String, ru: String) -> String:
	return ru if ELRemakeText.language(profile) == "ru" else en

static func relic(profile: ELProfile, id: String, balanced := false) -> Dictionary:
	if not RELICS.has(id): return {}
	var row: Array = RELICS[id]
	var description := text(profile, row[2], row[3])
	if balanced and id == "purifier_stone":
		description = text(profile, "Remove a spell at a merchant for 25 less gold, before price modifiers. One removal per visit.", "Удаление заклинания у торговца стоит на 25 золотых меньше до применения скидок и надбавок. Одно удаление за визит.")
	elif balanced and id == "ember_purse":
		description = text(profile, "Win a duel by the end of round 8 to earn 12 extra gold.", "Победа не позднее 8-го раунда приносит ещё 12 золотых.")
	var lore: Array = RELIC_LORE[id]
	description += "\n" + text(profile, lore[0], lore[1])
	return {"id": id, "title": text(profile, row[0], row[1]), "description": description}

static func event(profile: ELProfile, index: int, rebalanced := false) -> Dictionary:
	if rebalanced:
		if index < 0 or index >= SCENES.size(): return {}
		var scene: Array = SCENES[index]
		return {"title": text(profile, scene[0], scene[1]), "description": text(profile, scene[2], scene[3])}
	if index < 5 or index >= 5 + EVENTS.size(): return {}
	var row: Array = EVENTS[index - 5]
	return {"title": text(profile, row[0], row[1]), "description": text(profile, row[2], row[3])}

static func outcome(profile: ELProfile, key: String) -> String:
	if not OUTCOME_LINES.has(key): return ""
	var row: Array = OUTCOME_LINES[key]
	return text(profile, row[0], row[1])

static func keystone(profile: ELProfile, id: String) -> Dictionary:
	if not KEYSTONES.has(id): return {}
	var row: Array = KEYSTONES[id]
	var lore: Array = KEYSTONE_LORE[id]
	return {"id": id, "title": text(profile, row[0], row[1]),
		"description": text(profile, row[2], row[3]) + "\n" + text(profile, lore[0], lore[1])}
