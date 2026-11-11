class_name ELAutochessText
extends RefCounted
## Texts of the autochess mode. Written in English in the code; shown in
## Russian when the installed game's texts are Russian. Formatted lines
## ("+%d defense.") are matched against their templates, so descriptions
## built from numbers translate as well; anything unknown falls back to the
## remake's shared dictionary and then to the English text.

static var _patterns: Array = []
static var _cache: Dictionary = {}

static func t(profile: ELProfile, text: String) -> String:
	if text.is_empty() or ELRemakeText.language(profile) != "ru": return text
	if _cache.has(text): return _cache[text]
	var result := _russian(text, 0)
	if result == text: result = ELRemakeText.t(text, profile)
	_cache[text] = result
	return result

static func _russian(text: String, depth: int) -> String:
	if RU.has(text): return RU[text]
	if depth > 2: return text
	for pattern: Array in _compiled():
		var found: RegExMatch = (pattern[0] as RegEx).search(text)
		if found == null: continue
		var values: Array = []
		for index in range(1, found.get_group_count() + 1):
			var value := found.get_string(index)
			if String(pattern[2][index - 1]) == "s": value = _fragment(value, depth + 1)
			values.append(value)
		return _fill(String(pattern[1]), values)
	# Several sentences: translate each.
	if text.contains(". ") and not RU.has(text):
		var parts := text.split(". ")
		if parts.size() > 1:
			var out := PackedStringArray()
			for index in parts.size():
				var piece := parts[index] + ("." if index < parts.size() - 1 else "")
				out.append(_russian(piece, depth + 1))
			var joined := " ".join(out)
			if joined != text: return joined
	return text

static func _fragment(value: String, depth: int) -> String:
	if RU.has(value): return RU[value]
	if value.contains(", "):
		var pieces := PackedStringArray()
		for piece: String in value.split(", "): pieces.append(_russian(piece, depth))
		return ", ".join(pieces)
	if value.begins_with(" (") and value.ends_with(")"):
		return " (" + _fragment(value.substr(2, value.length() - 3), depth) + ")"
	return _russian(value, depth)

static func _compiled() -> Array:
	if not _patterns.is_empty(): return _patterns
	var placeholder := RegEx.create_from_string("%(?:\\+)?(?:\\.\\d)?[dsf]|%%")
	for key: String in RU:
		if not key.contains("%"): continue
		var expression := "^"
		var kinds: Array[String] = []
		var at := 0
		for found: RegExMatch in placeholder.search_all(key):
			expression += _escape(key.substr(at, found.get_start() - at))
			var token := found.get_string()
			if token == "%%": expression += "%"
			elif token.ends_with("s"):
				expression += "(.+?)"
				kinds.append("s")
			else:
				expression += "([-+]?\\d+(?:\\.\\d+)?)"
				kinds.append("d")
			at = found.get_end()
		expression += _escape(key.substr(at)) + "$"
		var regex := RegEx.create_from_string(expression)
		if regex.is_valid(): _patterns.append([regex, RU[key], kinds])
	# Longer templates first, so specific lines win over general ones.
	_patterns.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as RegEx).get_pattern().length() > (b[0] as RegEx).get_pattern().length())
	return _patterns

static func _escape(text: String) -> String:
	var out := ""
	for character in text:
		if "\\^$.|?*+()[]{}".contains(character): out += "\\"
		out += character
	return out

static func _fill(template: String, values: Array) -> String:
	var placeholder := RegEx.create_from_string("%(?:\\+)?(?:\\.\\d)?[dsf]|%%")
	var out := ""
	var at := 0
	var index := 0
	for found: RegExMatch in placeholder.search_all(template):
		out += template.substr(at, found.get_start() - at)
		var token := found.get_string()
		if token == "%%": out += "%"
		else:
			out += String(values[index]) if index < values.size() else ""
			index += 1
		at = found.get_end()
	return out + template.substr(at)

const RU := {
	# Screen
	"Menu": "Меню", "Shop": "Лавка", "Players · %d": "Игроки · %d", "All boards": "Все поля",
	"Damage": "Урон", "Alliances": "Союзы", "Artifacts and spells": "Артефакты и заклинания",
	"Choose a spell or artifact": "Выберите заклинание или артефакт", "Resume": "Продолжить",
	"Leave (the game is saved)": "Выйти (игра сохранится)", "Concede and end the game": "Сдаться и закончить игру",
	"Watch the other boards": "Смотреть другие поля", "Return to the main menu": "Вернуться в главное меню",
	"Evolution!": "Эволюция!", "Preparing": "Подготовка", "Battle in %ds": "Бой через %d с", "Battle": "Бой",
	"Round over": "Раунд окончен", "Tournament over": "Турнир окончен", "Battle!": "В бой!",
	"Victory": "Победа", "Draw": "Ничья", "Defeat": "Поражение",
	"You finished in place %d of %d": "Вы заняли %d место из %d",
	"%s is out of the tournament (place %d).": "%s выбывает из турнира (%d место).",
	"Locked": "Закреплено", "Lock": "Закрепить", "Refresh": "Обновить", "Level": "Уровень",
	"XP %d/%d · ◈ %d": "Опыт %d/%d · ◈ %d", "Maximum": "Максимум", "ether": "эфира",
	"Income +%d (interest %d)": "Доход +%d (проценты %d)", "Ready": "Готов", "Waiting…": "Ожидание…",
	"Start battle": "Начать бой", "Round %d": "Раунд %d", "Neutral round: wild creatures": "Нейтральный раунд: дикие существа",
	"Opponent: %s (copy)": "Противник: %s (копия)", "Opponent: %s": "Противник: %s", "Speed ×%d": "Скорость ×%d",
	"Army %d/%d": "Армия %d/%d", "Reserves %d/%d": "Резерв %d/%d",
	"Victory! You won the tournament.": "Победа! Вы выиграли турнир.", "Watch this board": "Смотреть это поле",
	"Tier %d": "Уровень %d", "Carried by %s": "Носит: %s", "Click, then click a creature to give it.": "Нажмите, затем выберите существо, чтобы отдать ему.",
	"Health %d · Attack %d · Defense %d": "Здоровье %d · Атака %d · Защита %d",
	"Attack every %.1f s · Original %d/%d": "Удар каждые %.1f с · В оригинале %d/%d",
	"Regeneration (%d)": "Регенерация (%d)", "Sell for ◈ %d": "Продать за ◈ %d",
	"Deploy at least one creature before starting.": "Перед боем выставьте хотя бы одно существо.",
	"Click a board to watch it. Tab closes the overview.": "Нажмите на поле, чтобы смотреть его. Tab закрывает обзор.",
	"Melee": "Ближний бой", "Ranged": "Дальний бой", "Red": "Хаоты", "Blue": "Кинеты", "Green": "Виталы", "Black": "Синтеты", "White": "Бесцветные",
	"Flying": "Полёт", "First strike": "Первый удар", "Trample": "Прорыв", "Bloodthirsty": "Кровожадность", "Tireless": "Неутомимость",
	"Vampire": "Вампиризм", "Evasive": "Неуловимость", "Unblockable": "Неблокируемость", "Breaks enchantments": "Снимает чары",
	"Guard": "Стража", "Lazy": "Медлительность", "Poisonous": "Яд", "Swift": "Стремительность", "Ether protection": "Защита эфира",
	"Magic screen": "Магический экран", "Colorless": "Бесцветный",
	# Lobby
	"Autochess": "Автошахматы", "Nine heroes, one pool of creatures, real-time battles.": "Девять героев, общий запас существ, бои в реальном времени.",
	"Choose your hero": "Выберите героя", "New tournament": "Новый турнир", "Continue tournament": "Продолжить турнир",
	"Host online": "Создать сетевую игру", "Join online": "Подключиться", "Back": "Назад", "Address": "Адрес", "Name": "Имя",
	"Start": "Начать", "Players": "Игроки", "Computer": "Компьютер", "Waiting for players… %d joined.": "Ожидание игроков… подключилось: %d.",
	"Connecting…": "Подключение…", "The connection was lost.": "Соединение потеряно.", "Could not host on port %d.": "Не удалось открыть порт %d.",
	"Could not connect.": "Не удалось подключиться.", "Waiting for the host to start.": "Ожидание начала игры.",
	"The game differs from the host's. Use the same Etherlords II installation.": "Игра отличается от игры ведущего. Нужна та же установка Etherlords II.",
	"Empty seats are taken by computer heroes.": "Свободные места займут компьютерные герои.",
	"Hero": "Герой", "The saved tournament could not be read.": "Не удалось прочитать сохранённый турнир.",
	"The game has already started.": "Игра уже началась.",
	# Alliances
	"Chaots": "Хаоты", "Kinets": "Кинеты", "Vitals": "Виталы", "Synthets": "Синтеты", "Flyers": "Летающие",
	"Chaot members deal 10/20/30% more attack damage at 2/4/6 different Chaot lines.": "Хаоты наносят на 10/20/30% больше урона при 2/4/6 разных линиях Хаотов.",
	"Kinet members recharge abilities 20/40% faster and attack 10/20% faster at 2/4 different Kinet lines.": "Кинеты перезаряжают способности на 20/40% и атакуют на 10/20% быстрее при 2/4 разных линиях Кинетов.",
	"Vital members regenerate 1/2% of their health every second at 2/4 different Vital lines.": "Виталы восстанавливают 1/2% здоровья в секунду при 2/4 разных линиях Виталов.",
	"Synthet members gain 3/6 defense at 2/4 different Synthet lines.": "Синтеты получают +3/6 защиты при 2/4 разных линиях Синтетов.",
	"Flying members evade 15/30% of attacks from creatures that cannot fly at 2/4 different flying lines.": "Летающие уклоняются от 15/30% атак нелетающих существ при 2/4 разных летающих линиях.",
	"First strike members deal 30/60% more damage with their opening blow on each enemy at 2/4 different lines.": "Существа с первым ударом наносят на 30/60% больше урона первым ударом по каждому врагу при 2/4 разных линиях.",
	"No bonus yet.": "Бонуса пока нет.", "+%d%% attack damage": "+%d%% урона", "+%d%% recharge, +%d%% attack speed": "+%d%% перезарядки, +%d%% скорости атаки",
	"%d%% health per second": "%d%% здоровья в секунду", "+%d defense": "+%d защиты", "%d%% evasion against ground attacks": "%d%% уклонения от наземных атак",
	"+%d%% opening blow": "+%d%% к первому удару",
	# Artifacts
	"+%d health.": "+%d здоровья.", "%d health.": "%d здоровья.", "+%d attack damage.": "+%d урона.", "+%d defense.": "+%d защиты.",
	"+%d%% attack speed.": "+%d%% скорости атаки.", "Regenerates %d%% health per second.": "Восстанавливает %d%% здоровья в секунду.",
	"Poison: hits deal %d%% more damage over 3 s.": "Яд: удары наносят ещё %d%% урона за 3 с.",
	"Venom: a struck enemy still below %d%% health 4 s later dies (not 3-star or 5-cost).": "Смертельный яд: раненый враг, у которого через 4 с меньше %d%% здоровья, погибает (кроме трёхзвёздных и стоимостью 5).",
	"Vampire: attacks restore %d%% of the damage dealt.": "Вампиризм: атаки восстанавливают %d%% нанесённого урона.",
	"Breaks enchantments: hits remove the target's bonuses.": "Снимает чары: удары убирают бонусы цели.",
	"Below 40%% health: heals %d%% of its health once.": "Ниже 40%% здоровья: один раз лечит %d%% здоровья.",
	"Every %d hits: %d damage to another enemy within 4 m.": "Каждые %d удара: %d урона другому врагу в пределах 4 м.",
	"Ether protection: enemy abilities cannot target it.": "Защита эфира: вражеские способности не могут выбрать его целью.",
	"Unblockable: goes for the enemy back line.": "Неблокируемость: идёт к задней линии врага.",
	"For the first %d s: +%d%% attack and a %d-point shield.": "Первые %d с: +%d%% атаки и щит на %d.",
	"First strike.": "Первый удар.", "Takes %d%% less damage from abilities.": "Получает на %d%% меньше урона от способностей.",
	"Melee attackers take %d damage.": "Атакующие вблизи получают %d урона.", "Reflects %d%% of ability damage.": "Отражает %d%% урона от способностей.",
	"Every %d s: %d damage to its target and %d to every other enemy.": "Каждые %d с: %d урона цели и %d каждому другому врагу.",
	"Every %d s: %d fire damage to its target.": "Каждые %d с: %d урона огнём цели.",
	"Allies within %d m regenerate %d%% health per second.": "Союзники в пределах %d м восстанавливают %d%% здоровья в секунду.",
	"At the bell, allies within %d m gain %d%% attack and health.": "В начале боя союзники в пределах %d м получают %d%% атаки и здоровья.",
	"At the bell, it and allies within %d m gain a %d-point shield.": "В начале боя он и союзники в пределах %d м получают щит на %d.",
	"On death, a Konung rises with %d%% of its health.": "После гибели появляется конунг с %d%% его здоровья.",
	"Returns once after death with %d%% health.": "Один раз возвращается после гибели с %d%% здоровья.",
	"Below half health: enemies within %d m cannot attack for %.1f s. Once.": "Ниже половины здоровья: враги в пределах %d м не могут атаковать %.1f с. Один раз.",
	"+%d%% attack and health, +%d%% more per ally of the same race.": "+%d%% атаки и здоровья и ещё +%d%% за каждого союзника той же расы.",
	"Fury: +%d%% attack, %d%% health.": "Ярость: +%d%% атаки, %d%% здоровья.",
	"Once: takes control of an enemy below %d%% health.": "Один раз: подчиняет врага, у которого меньше %d%% здоровья.",
	"Hits have a %d%% chance to paralyse for %.1f s.": "Удары с шансом %d%% парализуют на %.1f с.",
	"At the bell, every ally gains %d%% attack and health.": "В начале боя каждый союзник получает %d%% атаки и здоровья.",
	# Abilities
	"Aura of death: %d damage to every creature when it enters and when it dies.": "Аура смерти: %d урона каждому существу в начале боя и при его гибели.",
	"Aura: %s to allied %s.": "Аура: %s союзным существам (%s).", "+%d%% attack": "+%d%% атаки", "+%d%% health": "+%d%% здоровья",
	"+%d%% attack speed": "+%d%% скорости атаки", "reach the back line": "проход к задней линии",
	"Bloodsucker: each hit adds %d%% attack.": "Кровосос: каждый удар добавляет %d%% атаки.",
	"Breath: %d damage to every %s enemy.": "Дыхание: %d урона каждому врагу (%s).", "flying": "летающему", "ground": "наземному",
	"Burn: wounded enemies cannot regenerate for %d s.": "Ожог: раненые враги не восстанавливаются %d с.",
	"Corpse eater: heals %d%% when a creature dies nearby.": "Пожиратель трупов: лечится на %d%%, когда рядом гибнет существо.",
	"Destroys an enemy below %d%% health, otherwise deals %d damage.": "Уничтожает врага, у которого меньше %d%% здоровья, иначе наносит %d урона.",
	"Ether thief: %d damage; the target cannot use abilities for %d s.": "Похититель эфира: %d урона; цель не может применять способности %d с.",
	"Fright: stops %s for %.1f s.": "Страх: останавливает (%s) на %.1f с.", "its target": "свою цель",
	"enemies fighting in melee": "врагов в ближнем бою", "enemies of the target's race": "врагов той же расы, что и цель",
	"Fatalist: falls if no enemy wounds it for %d s.": "Фаталист: гибнет, если враги не ранят его %d с.",
	"Parasite: loses health over time.": "Паразит: со временем теряет здоровье.",
	"Piercing gaze: %d damage and removes the target's bonuses.": "Пронзающий взгляд: %d урона и снятие бонусов цели.",
	"Poisonous bite: hits reduce the target's attack by %d%%.": "Ядовитый укус: удары снижают атаку цели на %d%%.",
	"Rally: allied %s attack %d%% faster for %d s.": "Сбор: союзные существа (%s) атакуют на %d%% быстрее %d с.",
	"Returns a fallen ally%s with %d%% health.": "Возвращает павшего союзника%s с %d%% здоровья.",
	"Rises from the dead once after %d creatures fall.": "Один раз восстаёт из мёртвых после гибели %d существ.",
	"Robber: hits stop the target's abilities for %d s.": "Грабитель: удары блокируют способности цели на %d с.",
	"Snake venom: hits deal %d%% more damage over %d s.": "Змеиный яд: удары наносят ещё %d%% урона за %d с.",
	"Strike: %d damage to %s.": "Удар: %d урона (%s).", "the farthest enemy": "самому дальнему врагу", "the toughest enemy": "самому крепкому врагу",
	"an attacking enemy": "атакующему врагу",
	"Taste of blood: drains %d health per allied bat.": "Вкус крови: выпивает %d здоровья за каждую союзную мышь.",
	"Venom: a struck enemy still below %d%% health %d s later dies (not 3-star or 5-cost creatures).": "Смертельный яд: если у раненого врага меньше %d%% здоровья спустя %d с, он погибает (кроме трёхзвёздных и стоимостью 5).",
	"kobolds": "кобольды", "rats": "крысы", "bees": "пчёлы", "orcs": "орки", "bats": "мыши", "aviaks": "авиаки",
	"spirits": "духи", "lamias": "ламии", "beholders": "созерцатели", "ticks": "клещи",
	# Errors
	"Army full. Level up or withdraw a creature.": "Армия заполнена. Повысьте уровень или уберите существо.",
	"Arrange your army between battles.": "Расставляйте армию между боями.", "Change artifacts between battles.": "Меняйте артефакты между боями.",
	"Choose a creature from your army.": "Выберите существо из своей армии.", "Choose a reserve slot.": "Выберите место в резерве.",
	"Choose an artifact.": "Выберите артефакт.", "Choose an empty reserve slot.": "Выберите свободное место в резерве.",
	"Choose artifacts between battles.": "Выбирайте артефакты между боями.", "Choose one of the offered artifacts.": "Выберите один из предложенных артефактов.",
	"Deploy inside your half of the battlefield.": "Выставляйте существ на своей половине поля.",
	"Leave more space between creatures.": "Оставьте больше места между существами.", "Not enough ether.": "Недостаточно эфира.",
	"Only reserves can be sold during battle.": "Во время боя можно продавать только резерв.",
	"Recruit a creature before spending the rest of your ether.": "Наймите существо, прежде чем тратить остаток эфира.",
	"Reserves full. Deploy or sell a creature first.": "Резерв заполнен. Сначала выставьте или продайте существо.",
	"Reserves full. Deploy, evolve or sell a creature first.": "Резерв заполнен. Сначала выставьте, улучшите или продайте существо.",
	"Select a reserve, then one of your deployed creatures to swap them.": "Выберите существо из резерва, затем выставленное, чтобы поменять их.",
	"This offer has already been recruited.": "Это существо уже нанято.", "Unknown action.": "Неизвестное действие.",
	"Unlock an offer before refreshing.": "Открепите предложение перед обновлением.", "Wait for the next round.": "Дождитесь следующего раунда.",
	"You have left the tournament.": "Вы выбыли из турнира.", "Your army is at full strength.": "Армия уже максимального уровня.",
	# Interface after the evolution and round notices
	"%d health lost": "Потеряно здоровья: %d", "+%d base": "+%d основа", "+%d interest": "+%d проценты", "+%d streak": "+%d серия", "+%d victory": "+%d победа",
	"Attack %d → %d": "Атака %d → %d", "Health %d → %d": "Здоровье %d → %d", "Attack every %.1f s": "Атака раз в %.1f с",
	"Battle begins": "Бой начинается", "Choose a creature to carry %s.": "Выберите существо, которое понесёт %s.", "%s returns to your artifacts.": "%s возвращается к вашим артефактам.", "flies; enemies cannot dodge its blows": "летает; от его ударов нельзя увернуться", "its first blow on each enemy lands at once and delays that enemy's swing": "первый удар по каждому врагу наносится сразу и сбивает его замах", "a killing blow carries on into the next enemy": "добивающий удар переходит на следующего врага", "attacks 10% faster and keeps hitting its target until it falls": "атакует на 10% быстрее и бьёт цель, пока она не падёт", "attacks 5% faster and uses abilities without pausing": "атакует на 5% быстрее и применяет способности без паузы", "heals a quarter of the damage it deals": "лечится на четверть нанесённого урона", "slips past the front line to reach archers and casters": "проходит мимо передней линии к стрелкам и магам", "each blow removes the target's enchantments": "каждый удар снимает с цели заклинания", "+15% damage for each ally attacking the same enemy, up to two": "+15% урона за каждого союзника, атакующего ту же цель (до двух)", "attacks 45% slower but hits 45% harder": "атакует на 45% медленнее, но бьёт на 45% сильнее", "no effect in autochess battles": "в автошахматах не действует", "moves faster and uses its first ability sooner": "двигается быстрее и раньше применяет первую способность", "enemy abilities and poisons do not affect it": "вражеские способности и яды на него не действуют", "takes 25% less damage from abilities and artifacts": "получает на 25% меньше урона от способностей и артефактов", "recovers health after two seconds without taking damage": "восстанавливает здоровье, если 2 секунды не получает урона",
	"Click a board to watch it.": "Щёлкните поле, чтобы смотреть его.", "Your board": "Ваше поле", "Empty item slot": "Нет предмета",
	"Evolved": "Эволюция", "Income +%d": "Доход +%d", "Leave the online game": "Покинуть сетевую игру", "Level %d": "Уровень %d",
	"Gain %d XP for ◈ %d. The level is how many creatures you can field; it also brings costlier offers.": "Получить %d опыта за ◈ %d. Уровень — это сколько существ можно выставить; он же приносит более дорогие предложения.",
	"Give it to a creature from the artifact list on the left.": "Отдайте его существу из списка артефактов слева.",
	"Max level": "Макс. уровень", "Neutral round": "Нейтральный раунд", "Out": "Выбыл", "Owned: %d": "Есть: %d",
	"Recruit your first creature.": "Наймите первое существо.", "Recruited": "Нанято",
	"Refresh unlocked offers. Locked offers stay.": "Обновить незакреплённые предложения. Закреплённые останутся.", "Refresh · ◈ %d": "Обновить · ◈ %d",
	"Regeneration": "Регенерация", "Shared pool: %d/%d left": "Общий запас: осталось %d/%d",
	"The highlighted shop copies complete an evolution.": "Подсвеченные предложения завершают эволюцию.",
	"Tier %d · ◈ %d": "Ранг %d · ◈ %d", "XP %d/%d": "Опыт %d/%d", "◈ %d in total": "Всего ◈ %d",
	# Landing and online page
	"Connected. Waiting for the host to start the game.": "Подключено. Ждём, пока хозяин начнёт игру.", "Continue · round %d": "Продолжить · раунд %d",
	"Create a tournament and share your address with friends.": "Создайте турнир и сообщите друзьям свой адрес.",
	"Enter a friend's address and compete with your own army.": "Введите адрес друга и сражайтесь своей армией.",
	"Enter a whole number for the seed.": "Введите целое число для зерна.", "Enter the host's address.": "Введите адрес хозяина.",
	"Face eight other heroes. The last hero standing wins.": "Сразитесь с восемью героями. Побеждает последний оставшийся.",
	"Friends join with:": "Друзья подключаются по адресу:", "Host": "Создать", "Join": "Подключиться", "Leave": "Выйти", "Mode": "Режим", "Expedition": "Экспедиция",
	"Host or join a nine-hero tournament. Computers fill empty seats.": "Создайте турнир на девять героев или подключитесь к нему. Пустые места займёт компьютер.",
	"Host's address": "Адрес хозяина", "No network address found.": "Сетевой адрес не найден.", "Online autochess": "Автошахматы по сети",
	"Optional: enter a whole number to replay the same shops and opponents.": "Необязательно: целое число, чтобы повторить те же лавки и соперников.",
	"Play online": "Игра по сети", "Players: %d / %d": "Игроки: %d / %d", "Port": "Порт", "Random seed": "Случайное зерно",
	"Recruit creatures from the shared pool and collect three copies to evolve them.": "Нанимайте существ из общего запаса и собирайте по три копии, чтобы они эволюционировали.",
	"Recruit your army": "Наберите армию", "Resume with the same army and shop.": "Продолжить с той же армией и лавкой.", "Set seed": "Задать зерно",
	"Start game": "Начать игру", "Start hosting": "Создать игру", "Starting ether: %d": "Эфир в начале: %d",
	"Start with %d health. Fight neutral creatures in rounds 1–3 and every fifth round, and other heroes in between.": "В начале %d здоровья. В раундах 1–3 и каждом пятом — бой с нейтральными существами, в остальных — с другими героями.",
	"Starts a new tournament; the saved one is replaced.": "Начинает новый турнир; сохранённый будет заменён.",
	"Your hero represents you on the board and picks the battlefield. It does not change your army.": "Герой представляет вас на поле и выбирает место битвы. На армию он не влияет.",
	"Your name": "Ваше имя", "e.g. 192.168.1.20:%d": "например, 192.168.1.20:%d",
	"A journey across the map, battle after battle.": "Путешествие по карте, бой за боем.",
	"Attack": "Атака", "Attack every": "Атака раз в", "Defense": "Защита", "Health": "Здоровье", "Sell +◈ %d": "Продать +◈ %d",
	"Loading…": "Загрузка…", "Decoding textures…": "Распаковка текстур…", "Loading battlefields…": "Загрузка полей боя…", "Loading heroes…": "Загрузка героев…",
	"Loading creatures…": "Загрузка существ…", "Preparing creature figures…": "Подготовка фигур существ…", "Preparing portraits…": "Подготовка портретов…", "s": "с",
}
