class_name ELRestoredStory
## What the heroes of the restored missions say on the way. Neither edition
## has lines for Savage Desert, Evil Dale or the Snowflake Maze beyond their
## briefings, so these
## are Demiurges' own, written after the dialogues of the second game.
##
## Each beat is told once, when its trigger is met after an act, at a new
## day or at the start, as a speaker's message box (the hero's portrait and
## name). A place or figure a hero only walks past on the way counts too:
## every tile of the move is checked (`stepped`). Triggers:
##   start           the mission begins;
##   near  at, r     a hero of the player comes within r tiles of a place;
##   meet  who, r    a hero of the player comes within r tiles of `who`;
##   beaten who      a hero of the player has just beaten `who`.
## Places are map fractions (Vector2) or tiles (Vector2i). A line's speaker
## is "hero" (the hero the trigger is about) or the template name of a
## rival hero or creature on the map.

const STORY := {
	ELRestoredMissions.SAVAGE_DESERT: [
		{"id": "start", "trigger": {"kind": "start"}, "lines": [
			["hero", "The sands still smoke after the battle. The Rusted Ones fled and left their shops and mines behind – spoils for Great Chaos now. But a renegade Cyclops has dug in among the north-eastern mountains. By the flame of Chaos, he will not mock us for long!",
				"Пески еще дымятся после битвы. Ржавые бежали, бросив свои лавки и шахты, – теперь это добыча Великого Хаоса. Но в северо-восточных горах засел Циклоп-отступник. Клянусь пламенем Хаоса, недолго ему осталось глумиться над нами!"]]},
		{"id": "fallen", "trigger": {"kind": "near", "at": ELRestoredMissions.SYNTHET_HOME, "r": 11}, "lines": [
			["hero", "So this is all that is left of the Synthets' stronghold – broken walls and the craters of our spells. Yet iron creatures still roam the ruins. Their masters are gone, but their orders, it seems, still stand.",
				"Вот и все, что осталось от твердыни синтетов, – обломки стен да воронки от наших заклятий. Но среди развалин еще бродят железные твари. Хозяев у них больше нет, а приказ, похоже, все еще в силе."]]},
		{"id": "mountains", "trigger": {"kind": "near", "at": ELRestoredMissions.LAIR, "r": 22}, "lines": [
			["hero", "The ground here breathes fire, like the deep mountains of my homeland. The renegade chose his lair well! But the fire that warms him will burn him too.",
				"Земля здесь дышит огнем, как в недрах гор моей родины. Хорошее логово выбрал себе отступник! Только огонь, что согревает его, сожжет и его самого."]]},
		{"id": "chief", "trigger": {"kind": "beaten", "who": "OgreChief"}, "lines": [
			["hero", "Even the ogre chief has fallen at my feet. Now only stone and his own pride stand between me and the Cyclops.",
				"Даже вождь огров пал к моим ногам. Теперь между мной и Циклопом – лишь камень да его собственная гордыня."]]},
		{"id": "lair", "trigger": {"kind": "meet", "who": "Cyclope", "r": 8}, "lines": [
			["Cyclope", "Who is trampling my stones? I left your hordes, and I serve neither Chaos nor its Lords any longer! Get out, before I crush you like a scorpion!",
				"Кто там топчет мои камни? Я ушел из ваших орд и не служу больше ни Хаосу, ни его лордам! Убирайся, пока я не раздавил тебя, как скорпиона!"],
			["hero", "Whoever betrays the flame burns in it. Prepare for battle, renegade!",
				"Кто предал пламя, тот сгорит в нем. Готовься к битве, отступник!"]]},
	],
	ELRestoredMissions.EVIL_DALE: [
		{"id": "start", "trigger": {"kind": "start"}, "lines": [
			["hero", "The branches closed behind me, and mountains rose where the path lay a moment ago. Well, the elders warned me: the Way of Knowledge leads only forward. May the Power of the Forest keep me!",
				"Ветви сомкнулись за моей спиной, и горы выросли там, где только что лежала тропа. Что ж, старейшины предупреждали: Путь Знания ведет лишь вперед. Да хранит меня Сила Леса!"]]},
		{"id": "rock", "trigger": {"kind": "near", "at": Vector2i(90, 14), "r": 12}, "lines": [
			["hero", "Black stone, ash and the smell of sulphur – the Chaots have been here. So the scroll's secret was revealed not only to the Vitals...",
				"Черный камень, пепел и запах серы – сюда добрались хаоты. Значит, не только виталам открылась тайна свитка..."]]},
		{"id": "zarus", "trigger": {"kind": "meet", "who": "BLevHero1", "r": 9}, "lines": [
			["BLevHero1", "Another lost soul! May the mountain orcs devour me if this dale has ever let anyone out alive. But since we are locked in here, green mould, the spoils are mine! Keep away if you value your hide.",
				"Еще один заблудший! Пусть сожрут меня горные орки, если эта долина хоть кого-то выпустила живым. Но раз уж мы здесь заперты, зеленая плесень, – добыча моя! Не подходи, если тебе дорога шкура."]]},
		{"id": "snow", "trigger": {"kind": "near", "at": ELRestoredMissions.DALE_HOMELAND, "r": 14}, "lines": [
			["hero", "Snow in the middle of summer – and an abandoned domain. The Kinets tried to settle here: the mines still work, the shops are open. But the owners have vanished, as if the wind carried them away.",
				"Снег посреди лета – и брошенные владения. Кинеты пытались обжить это место: шахты еще работают, лавки открыты. А хозяева исчезли, будто их унес ветер."]]},
		{"id": "valaddin", "trigger": {"kind": "meet", "who": "BLevHero3", "r": 9}, "lines": [
			["BLevHero3", "Stop, Vital. The Council of Sixteen did not send you here, so you have no business here. I have sought the way out too long to share it with a barbarian from the woods. Go your way – and do not make me draw my blade.",
				"Остановись, витал. Совет Шестнадцати не посылал тебя сюда, а значит, нет у тебя здесь никакого дела. Слишком долго я ищу выход, чтобы делить его с лесным варваром. Иди своей дорогой – и не заставляй меня обнажать клинок."]]},
		{"id": "outpost", "trigger": {"kind": "near", "at": ELRestoredMissions.OUTPOST, "r": 10}, "lines": [
			["hero", "A Synthet outpost. Not one living warrior – only machines that go on trading as if nothing had happened. The Rusted Ones do not care who pays – which suits me well.",
				"Застава синтетов. Ни одного живого воина – только механизмы, что продолжают торговать, словно ничего не случилось. Ржавым все равно, кто платит, – мне это только на руку."]]},
		{"id": "tango", "trigger": {"kind": "meet", "who": "BLevHero4", "r": 9}, "lines": [
			["BLevHero4", "Vital detected. Threat level... acceptable. The Cluster has not answered for forty thousand cycles, but the last order stands: gather data on the Power of the ruins. You are noise in the channel, Vital. Withdraw, or you will be disintegrated.",
				"Обнаружен витал. Уровень угрозы... приемлемый. Кластер не отвечает уже сорок тысяч тактов, но последний приказ в силе: накапливать данные о Силе руин. Ты – помеха в канале, витал. Отступи, или будешь дезинтегрирован."]]},
		{"id": "woods", "trigger": {"kind": "near", "at": Vector2i(64, 84), "r": 12}, "lines": [
			["hero", "The Forest again! But the leaves whisper uneasily here. Someone walks these paths day after day – always the same circle, like a sentry who has forgotten what he guards.",
				"Снова Лес! Но листва здесь шепчет тревожно. Кто-то ходит по этим тропам изо дня в день – одним и тем же кругом, как часовой, позабывший, что охраняет."]]},
		{"id": "glazzz", "trigger": {"kind": "meet", "who": "BLevHero2", "r": 11}, "lines": [
			["BLevHero2", "Brother? No... You smell of the Forest, but you are not of our clan. Many moons ago I came here by the same Way and found no way out. Now this path is mine, and no one shall walk it. So wills the Power of the Forest!",
				"Брат? Нет... Ты пахнешь Лесом, но ты не из нашего клана. Много лун назад я пришел сюда тем же Путем и не нашла выхода. Теперь эта тропа – моя, и никто не пройдет по ней. Так велит Сила Леса!"],
			["hero", "Brother, come to your senses! The dale has taken your mind. I do not want this battle – but there is no way back for me.",
				"Брат, опомнись! Долина отняла у тебя разум. Я не хочу этой битвы – но и назад мне дороги нет."]]},
		{"id": "glazzz_beaten", "trigger": {"kind": "beaten", "who": "BLevHero2"}, "lines": [
			["hero", "Forgive me, brother. May the Forest take you back and give you the peace the dale took away.",
				"Прости, брат. Пусть Лес примет тебя и вернет тебе покой, которого лишила тебя долина."]]},
		{"id": "warp", "trigger": {"kind": "meet", "who": "BLevHero5", "r": 13}, "lines": [
			["BLevHero5", "So here is the Chosen One! I have long waited for you at the pass. All who walked this dale have perished, but I live – for the flame of Chaos is stronger than any ancient magic. The secret of the ruins will be mine, and no forest upstart will carry it out of here!",
				"Вот и Избранный! Давно я жду тебя у перевала. Все, кто шел по этой долине, сгинули, а я жив – потому что пламя Хаоса сильнее любой древней магии. Тайна руин достанется мне, и ни один лесной выскочка не вынесет ее отсюда!"]]},
		{"id": "warp_beaten", "trigger": {"kind": "beaten", "who": "BLevHero5"}, "lines": [
			["hero", "The pass is free. Ahead lie the ruins where all four elements meet. I feel their Power: there is flame in it, and metal, and life, and motion...",
				"Перевал свободен. Там, впереди, – руины, где сходятся все четыре стихии. Я чувствую их Силу: в ней и пламя, и металл, и жизнь, и движение..."]]},
	],
	ELRestoredMissions.SNOWFLAKE_MAZE: [
		{"id": "start", "trigger": {"kind": "start"}, "lines": [
			["hero", "The Ice Maze again. Once a year the Best of the Kinets gather here to measure their strength and Knowledge – and only one of them will be granted a talk with the Greatest Teacher. This year it will be me. Motion is endless, like Knowledge: whoever stops has already lost.",
				"Снова Ледяной лабиринт. Раз в год Лучшие из кинетов сходятся здесь, чтобы помериться силой и Знанием, – и лишь один из них удостоится беседы с Величайшим Учителем. В этот раз им буду я. Движение бесконечно, как и Знание: остановившийся уже проиграл."]]},
		{"id": "maze", "trigger": {"kind": "near", "at": Vector2(0.5, 0.5), "r": 19}, "lines": [
			["hero", "The walls of the maze sparkle like a snowflake under a lens. Every year the ice lies differently – and here is the Teacher's first lesson: the straight way is not always the shortest...",
				"Стены лабиринта сверкают, как снежинка под увеличительным стеклом. Каждый год лед ложится по-новому – вот и первый урок Учителя: прямой путь не всегда самый короткий..."]]},
		{"id": "santa", "trigger": {"kind": "meet", "who": "NewYear2002Lamia", "r": 9}, "lines": [
			["NewYear2002Lamia", "So the Council let a newcomer into the tournament? Every year I bring gifts to the worthy – and to the unworthy I bring a lesson. I wonder which you will get?",
				"Значит, Совет допустил на турнир новичка? Каждый год я приношу дары достойным, а недостойным – урок. Интересно, что достанется тебе?"],
			["hero", "I will take the lesson. And the gift I will take myself – once I have beaten you.",
				"Урок я приму. А дар возьму сам – после того, как одержу над тобой верх."]]},
		{"id": "santa_beaten", "trigger": {"kind": "beaten", "who": "NewYear2002Lamia"}, "lines": [
			["hero", "Even the oldest guests of the tournament must make way. Motion does not wait for those who stand still.",
				"Даже старейшим гостям турнира приходится уступать дорогу. Движение не ждет тех, кто стоит на месте."]]},
		{"id": "frost", "trigger": {"kind": "meet", "who": "NewYear2002Aviak", "r": 9}, "lines": [
			["NewYear2002Aviak", "Cold is the best teacher: it forgives no mistake. I have frozen lords stronger than you in this maze. You will freeze before you reach the heart of the snowflake.",
				"Холод – лучший учитель: он не прощает ошибок. Я заморозил в этом лабиринте лордов посильнее тебя. Ты замерзнешь раньше, чем доберешься до сердца снежинки."],
			["hero", "Cold teaches – but Motion warms. Let us see whose lesson proves stronger.",
				"Холод учит, но Движение согревает. Посмотрим, чей урок окажется сильнее."]]},
		{"id": "frost_beaten", "trigger": {"kind": "beaten", "who": "NewYear2002Aviak"}, "lines": [
			["hero", "The frost has retreated. Now only the maze itself stands between me and the Teacher.",
				"Мороз отступил. Теперь между мной и Учителем – только сам лабиринт."]]},
		{"id": "heart", "trigger": {"kind": "near", "at": Vector2(0.5, 0.5), "r": 3}, "lines": [
			["hero", "The heart of the snowflake. Here, they say, the Greatest Teacher talks with the worthy about the boundlessness of Knowledge. But the tournament is not over while my rivals' castles stand.",
				"Сердце снежинки. Говорят, здесь Величайший Учитель беседует с достойными о бесконечности Знания. Но турнир не окончен, пока стоят замки соперников."]]},
	],
}

## The ids of a mission's beats.
static func ids(scenario: String) -> Array[String]:
	var result: Array[String] = []
	for beat: Dictionary in STORY.get(scenario, []): result.append(str(beat.id))
	return result

## Tells every beat of the running restored mission whose trigger is met
## now (`battle`: the battle just fought, as ELFirstScenario.evaluate gets
## it). Single missions only, with the local player in command.
static func tell(director: ELAdventureDirector, battle: Dictionary = {}, start := false) -> void:
	var state := director.state
	if state.scenario.is_empty() or state.scenario.get("campaign", false) or not state.outcome.is_empty() or not director.strategy_commanders().is_empty(): return
	var scenario := ELRestoredMissions.scenario_of(state.map)
	if scenario.is_empty(): return
	var told: Array = state.scenario.get_or_add("told", [])
	var heroes: Array[Dictionary] = []
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) == state.current_player and item.get("placed", true): heroes.append(item)
	if heroes.is_empty(): return
	var russian := ELRemakeText.language(state.map.profile) == "ru"
	var due: Dictionary = state.scenario.get("due", {})
	state.scenario.erase("due")
	for beat: Dictionary in STORY.get(scenario, []):
		if told.has(beat.id): continue
		var hero := _met(state, beat.trigger, heroes, battle, start)
		# Passed on the way, by a hero still on the map.
		if hero.is_empty() and due.has(beat.id):
			for item: Dictionary in heroes:
				if int(item.uid) == int(due[beat.id]): hero = item
		if hero.is_empty(): continue
		told.append(beat.id)
		for line: Array in beat.lines:
			var speaker := hero if line[0] == "hero" else _object(state, str(line[0]))
			if speaker.is_empty(): continue
			state.event.emit({"kind": "message_box", "speaker": int(speaker.uid), "text": str(line[2] if russian else line[1]),
				"question": false, "hook": false, "box": "text", "speaker_box": true})

## A hero of the player entered a tile while moving: the place and meeting
## beats it meets there wait for the act's end, so walking through a place
## (or past a figure) without stopping in it still tells them.
static func stepped(state: ELAdventureSession, actor: Dictionary) -> void:
	if state.scenario.is_empty() or state.scenario.get("campaign", false) or not state.outcome.is_empty(): return
	if actor.get("type") != "hero" or int(actor.get("owner", -1)) != state.current_player: return
	var scenario := ELRestoredMissions.scenario_of(state.map)
	if scenario.is_empty(): return
	var told: Array = state.scenario.get("told", [])
	var hero: Array[Dictionary] = [actor]
	for beat: Dictionary in STORY.get(scenario, []):
		if told.has(beat.id) or not str(beat.trigger.kind) in ["near", "meet"]: continue
		var due: Dictionary = state.scenario.get("due", {})
		if due.has(beat.id): continue
		if not _met(state, beat.trigger, hero, {}, false).is_empty(): state.scenario.get_or_add("due", {})[beat.id] = int(actor.uid)

## The hero of the player that meets `trigger`, or {}.
static func _met(state: ELAdventureSession, trigger: Dictionary, heroes: Array[Dictionary], battle: Dictionary, start: bool) -> Dictionary:
	match str(trigger.kind):
		"start":
			if not start: return {}
			for hero: Dictionary in heroes:
				if int(hero.uid) == state.main_hero: return hero
			return heroes[0]
		"near":
			var place: Variant = trigger.at
			var at: Vector2 = Vector2(place) * Vector2(state.map.width, state.map.height) if place is Vector2 else Vector2(place)
			for hero: Dictionary in heroes:
				if Vector2(hero.x, hero.y).distance_to(at) <= float(trigger.r): return hero
		"meet":
			var other := _object(state, str(trigger.who))
			if other.is_empty(): return {}
			for hero: Dictionary in heroes:
				if Vector2(hero.x, hero.y).distance_to(Vector2(other.x, other.y)) <= float(trigger.r): return hero
		"beaten":
			if battle.is_empty(): return {}
			var winner := state.object(int(battle.get("winner", -1)))
			var loser := state.object(int(battle.opponent) if int(battle.get("winner", -1)) == int(battle.get("hero", -1)) else int(battle.get("hero", -1)))
			if not heroes.has(winner) or loser.get("name") != trigger.who: return {}
			return winner
	return {}

## The living hero or creature of a template on the map, or {}.
static func _object(state: ELAdventureSession, name: String) -> Dictionary:
	for item: Dictionary in state.objects.values():
		if item.get("alive", false) and item.get("type") in ["hero", "monster"] and str(item.get("name", "")) == name: return item
	return {}
