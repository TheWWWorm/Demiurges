---
title: Duel
category: modes
order: 30
summary: Presets, the hero editor, multiplayer and replays
---
A duel is a single battle between two heroes, outside the campaigns. Open it from **New Game › Duel** (Etherlords) or **Single › Duel** (Etherlords II).

## Choosing heroes

Each side picks a **preset**: a ready-made hero with race, level, skills, specialisation, spells, runes (Etherlords) and artifacts. The games' own presets are joined by those you make yourself. **Random** picks a preset of the current resource level.

## The hero editor

The editor changes a preset. Everything costs resources, and the total must fit the chosen **resource level**:

- Etherlords: resource levels 1–5, hero levels 1–15. Each further copy of the same spell costs more.
- Etherlords II: resource levels 1–3, hero levels 1–13. The bag holds 16 spells with at most 4 copies of one.
- Up to five skills and five artifacts.

In Etherlords II, **Randomize** beside the preset name builds a random hero the way the community's random deck generator does. It picks a random race, skills and an artifact, and keeps the hero level you set. It fills the deck mostly with cantrips and common spells and the reserve with rare, unique and colourless spells, mixing every colour. The preset uses resource level 6, which allows any colour without a budget. Press it again for another deck, then save it like any other preset.

## The match

Set the number of rounds (1–99, all of them are played) and the arena, or **Random** for a new arena every round. A coin decides who attacks first in each round.

In Etherlords II, the remake records a duel win in the local **Hall of Fame** under **Duels**. The winner earns 100 points per round won. Open the Hall of Fame from **Single › Mission** and use its switch button to reach the duel table.

## HotSeat

Two players can play on one computer (**HotSeat**). A message between turns tells the next player to take the seat.

## Network duel

Open **New Game › Multiplayer › Duel** in Etherlords or **Multiplayer** in Etherlords II. Both players need the same Demiurges version and game edition. Under **Hero preset**, each player can pick a hero supplied with the game or a custom hero saved in the Duel editor. The game shares the preset automatically when you connect.

The host sets the arena, **Resource cap**, and **Rounds**, chooses a hero, then presses **Host**. Both heroes must be at or below the cap. In **LAN**, the waiting duels show their cap next to the arena. Select a duel and press **Join**, or enter the host's address and UDP port (27184 by default) in **LAN** or **TCP/IP**. After connecting, the guest sees the host's settings, picks an eligible hero, and presses **Ready**. For play over the internet, the UDP port must be reachable from the other player's network, or choose **Online room** under **Connection** in **TCP/IP**: the host gets a six-letter room code (copied to the clipboard) and the guest enters it instead of an address. No ports need to be opened, and the browser version plays online this way. If the guest's connection drops during a duel, the host waits two minutes; the guest can join again the same way and the duel continues where it stopped.

Network matches play all scheduled rounds (1–99). After each round, both players confirm the score screen to start the next battle with their chosen heroes. In Etherlords, the higher-level hero opens the first round. A coin toss decides who opens when their levels are equal and in all Etherlords II matches. The first attack alternates each round in both games. Use the desktop or Android game for network play.

Once connected, use the chat field in the lobby to talk to your opponent. In battle, press **Enter** or select **Chat** to open the conversation. Press **Enter** to send and **Esc** to close the panel. Messages stay with the current match across rounds.

In Etherlords, new messages appear at the top of the battlefield. Press **~** to read the match transcript in the console. In the general Options tab, clear **Show chat** to hide the brief battlefield messages. The transcript stays available in the console.

In Etherlords II, use **New hero** or **Edit hero** from the network lobby to open the Duel editor. Hosts can edit before hosting, and guests can edit while choosing a hero. The editor follows the current resource cap. Saving selects the new preset in the lobby.

In Etherlords II, the host can set **Turn limit (s)** to 10–3600 seconds, or leave it at 0 for unlimited play. Attack and defence each get a fresh clock. At zero, the active player ends the phase with their current attack or defence choices.

Between Etherlords II rounds, select **Change deck** on the score screen if your hero has reserve spells. Select one spell in each column and swap them. The deck stays at 16 spells, with up to four copies of each spell. The host can set a separate **Deck change (s)** limit of 10–3600 seconds, or 0 for unlimited. When time runs out, your staged deck is confirmed for the next round.

## Strategic multiplayer preview

In Etherlords, open **New Game › Multiplayer › Strategy**, then choose **Local Network** or **Internet**. The host chooses an original map and two distinct human seats. Additional seats play as AI. On a LAN, select a waiting match under **LAN games** to fill in the host’s address and port. You can also enter the address and UDP port (27186 by default) directly. In **Internet**, **Online room** under **Connection** works the same way as for duels: the host gets a room code and the guest enters it. Both players need the same Demiurges build and original map.

The preview supports movement orders, resource sites, artifact and scroll pickups, castle assaults, and battles. During planning, both commanders can edit spellbooks, learn offered skills, and rearrange or exchange equipment between their own adjacent heroes. The hero screen can dismiss a hero with confirmation. A commander who still has a castle can continue after dismissing their last hero. Both commanders commit their orders with **End Turn**, then the host resolves one shared night.

When one commander fights a neutral creature, the other stays on the adventure map and sees when the battle starts and ends. The night resumes after the battle settles.

An adjacent hero can open a laboratory or component portal their commander owns. Orders to visit other shops resolve at night. The night waits for the visiting commander to finish each shop dialog. Owned shops can be upgraded through the buildings list.

Orders to enter forts also resolve at night. During planning you can upgrade a fort you own from the buildings list or release its garrison. The hero returns immediately to the tile used to enter.

If the guest leaves during a night shop visit, the host keeps the map. Captures and completed purchases stand, and any unconfirmed guest purchases are cleared. The host can finish their own open shop before the night continues.

Some maps start players with castles and no heroes. Open **Global Spells** and produce **Summon Recruit**. Once you have invested enough ether, confirm **Cast** to recruit a hero at your castle. Other available global spells use the same prompt, with a choice of target when needed. Cancel production to recover its material cost, or dispel one of your active spells from **Global Spells** or the affected hero's screen.

**Remote Use** lets a hero trade at an explored laboratory or component portal from anywhere on the map. The hero stays put and the shop keeps its owner. The other commander can keep planning while you trade.

Open **Diplomacy** to propose peace terms, counter an offer, or trade resources. Use the inbox and outbox to read, decline, or withdraw offers. Resource trades settle immediately when both commanders can pay. Accepted peace terms and broken alliances take effect at the next dawn.

When hosting, set **Adventure time limit** in seconds or leave it at zero for unlimited planning. The clock starts when both commanders have loaded the new day. At zero it ends any uncommitted turns, dismisses open planning windows, and refunds the materials for a ready global spell while keeping the ether spent.

**Combat time limit** sets a separate countdown for each attack and defence phase. At zero, the active player ends the phase with their current choices. Leave it at zero for untimed combat. Saved matches keep both limits and start a fresh adventure clock when both commanders reconnect.

The host can use **Save** or **F5** while both commanders are still planning. To resume, choose **Load** in the Strategy lobby, pick the save, and host it. The guest can find a resumed LAN match in the list or join again by address. The saved day, seats, and queued orders carry over. Both commanders must confirm **End Turn** again.

During a live match, **Load** and quick load are unavailable on the map. If the guest quits or loses the connection during planning, the host can keep playing against the AI in the same match. If the guest leaves during a battle between the two commanders, the host wins that battle and the AI takes over on the map. A result already decided stands. Save again after the AI takes over to resume that match from **Load** in the Strategy lobby without waiting for a guest.

## Ether Expedition

Choose **Expedition** on the main menu with Etherlords II installed. Compare the starting spellbooks and hero stats before choosing a preset, then take it through three branching acts. The connections between rooms vary by run. Choose **Scout next rooms** to compare the opponents, life, and levels in reachable battles before choosing a room. Life carries between duels. At a battle reward, add or replace a spell or choose **Recover life instead**. Elite battles and the first two guardians offer extra choices, with priority given to rare and unique spells. Camps let you heal or remove a spell. From Act II, you can use a camp to replace one spell with a faction spell that removes enchantments. At the Wayside Spring, you can borrow a one-charge artifact for your next duel. It expires after that duel even if unused. The first two guardians can vary between runs. The route journal names the current guardian and gives a preparation tip. Choose **Scout guardians** to inspect the guardian's life, level, and starting spellbook. You can scout White Lord from the first act and draft spells for that fight. Defeating White Lord ends the run.

Expedition opponents with a placement on an original campaign map use an arena from that terrain. The room seed keeps the arena choice consistent across reloads. White Lord awaits in the citadel.

New runs give priority to opponents you have yet to face in the act. Reachable room previews match the battles you enter, and older runs keep their original matchups.

You can scout the next rooms while choosing a reward, resolving an event, or resting at camp. Select **Inspect spellbook** to see an opponent’s starting cards, skills, and specialization before making your current choice.

Battle rewards in new runs offer a creature, a sorcery or enchantment, and a third spell when eligible cards are available. The first two slots favor your faction. In the first two rooms, the creature slot prioritizes spells that cost at most three ether. Elite and guardian rewards still offer extra choices.

The journal header shows the run seed. To replay a route, enter that number in **Run seed** on the Expedition start screen and choose the same starting spellbook. Leave the field empty for a random route.

Open **Journey log** on the route or results screen to see which rooms you visited in each act. The log survives a checkpoint reload. Earlier acts in older checkpoints may lack room details.

The results screen lets you inspect your last opponent and review the round and remaining enemy life when recorded. **Retry this seed** starts a fresh run with the same starter, seed, and route rules after you confirm. Your new choices still shape the run.

Starting in Act II, you can spend a camp visit learning or improving a combat skill. Training lasts for the rest of the run. You can train twice per expedition and review the skills you earned in **Deck**. Each training choice shows the effect of its next rank.

Guardian scouting shows the skills and specialization used in the fight. Select the specialization to read how it works in the in-game wiki.

At the Spellwright’s Mirror, you can spend 3 life to exchange an offered common spell or cantrip for a rarer spell of the same type. Compare both spells and their ether costs before you confirm. The exchange replaces one copy and keeps your spellbook the same size.

From Act II of a new run, the Silent Reliquary can offer a keepsake for 5 life. You can carry one keepsake at a time. It starts each duel with one charge, and the **Deck** panel shows which one you chose.

From Act II, a new run can also encounter the **Bridge Warden**. Inspect the opponent's starting spellbook before accepting the duel. A win earns an elite reward, a loss ends the expedition, and walking away lets you continue the route.

Open **Deck** to check spell counts, creature stats, and the average base ether cost. When replacing a spell, select the outgoing card to compare it with the reward before confirming.

Press **Esc** to step back from the deck or spell comparison. From the list of spells to replace, **Esc** returns to the reward offers.

The game saves when you enter a room, make a choice, or finish a combat action. If saving a battle result fails, choose **Retry save** to keep the result before continuing. **Resume expedition** restores the current room, including the battlefield, hands, and phase of an unfinished duel. Older room-only saves resume from the duel's opening.

If you already have a saved run, **Begin expedition** asks before replacing it. Choose **Keep saved expedition** to return to the starter and seed you entered.

## Replays

Etherlords II duels can be saved and watched again (**Replay** on the Duel screen). After a completed local or network match, choose **Save duel replay** on the final score screen. The game writes one replay per round and includes each round's starting decks and both players' combat actions. Network replays open from the recording player's side. The engine reads the original replays and writes its own.

See [How a battle works](combat).
