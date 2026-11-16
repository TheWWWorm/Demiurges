# Etherlords II online server: what the original files show

Nival's [Silent Storm repository](https://github.com/nival/Silent-Storm/tree/main/bin) contains files from the **Etherlords II online service**, which went into the repo by accident alongside Silent Storm's tools. There is no source code, only compiled programs, one config file and one database dump. This page lists what can be read from them as text. Nothing in it comes from running the programs.

Sources:

| File | What it is |
|---|---|
| `bin/EthServer.exe`, `EthServer1.exe` | The server. Its window title is "Etherlords II Master Server". MFC, 2003. |
| `bin/EthServer_demo.exe`, `EthServer_demo_0xDEAD.exe` | The same server built for the multiplayer demo (`/ver%i (mpdemo)`). |
| `bin/ethc.exe` | A debug test client ("New TCP Client"). It keeps its source file names (`C:\work\Server_A6\New TCP client\EthClient.cpp`, `EthPacket.cpp`, `EthFA.cpp`, `Crypto.cpp`, …). |
| `cfg/EthServer.cfg` | The server's settings: ports, timers, draft pack makeup, allowed versions. The Russian comments were already corrupted when the file was uploaded. |
| `bin/MySQLEthServerDb` | A MySQL 4.0 dump of the account, ban and statistics tables. |
| `bin/CDKeyStatServer.exe`, `WatchDog.exe`, `cfg/WatchDog.cfg` | Supporting services. WatchDog restarts `MasterServer.exe` on ports 28002–28018. |
| `bin/MasterServer.exe` | **Not Etherlords.** Its version info says "Evil Islands MasterServer Version 1.1". It's a plain game-list server: hosts announce themselves and clients fetch the list. |

The repository's license covers Silent Storm, for non-commercial use only. Don't copy any of these files into Demiurges. This page only records rules and numbers.

Labels used below: **[cfg]** means the value is stated in the config file. **[str]** means a string in the program shows it exists. **[inferred]** means it is my reading of names and isn't confirmed.

## Overview

- Players register an account with a **name, a password and a CD key**. Only one session per CD key can be online at a time ("User with this CD-KEY is online"). The server keeps lists of banned names, banned IPs with masks, banned CD keys (`CDKeysBanList.txt`) and allowed IPs. [str]
- At login the server checks the client's protocol version against `AllowedVersionsList = "666 597 … 615"`. A client not on the list gets "Version is not supported!". There is also a separate "MP Duel version". [cfg][str]
- After login a player picks a **game type** and enters that game type's **title room**, which has a chat and a player list. Matches then form in **staging rooms**. [str]
- The battle itself runs **directly between the two game clients**. The code calls this the "A4 connection" (`A4` appears to be the game client and `A6` the server). The server sends each client its opponent's addresses and both sides try to connect. NAT handling includes "NAT detection", an "EVIL NAT" flag and a "Firewall penetrator". As a last resort, traffic goes through **EthProxy**, a relay inside the server. It is limited to 20 users at once (`MaxNProxyUsers`) and 1 GB per month (`TrafficPerMonth`). [cfg][str]
- When a battle ends, **each client sends its own result report** and the server compares the two. Result codes: winner, draw, loser, surrender, timeout, opponent disconnected, desync (`DE_ER_A4SYNERR`). A player can be marked a cheater, which turns the result into a loss or an unrated game (`MR_REACTION_CH_L`, `MR_REACTION_CH_NORATE`). Each player has a `Cheats` counter. [str][inferred]
- Server ports `0xDEAD` (57005) and `0xDEED` (57069). The config describes the second address and port as being for players behind NAT. The server accepts up to 500 players. [cfg]

## Game types

The server's internal names are `TrainingDuel`, `RatingDuel5`, `Sealed` and `Draft8`. The server's status page also lists a "Blind New" room next to "Blind" (Sealed), which looks like a newer variant. [str]

### Training duel (`td`): unrated, custom rooms

- The host creates a **staging room** that has a name and an optional password. Others join from the list. Join can fail with no such room, room full, or wrong password. [str]
- Timers [cfg]: room wait `td.sRoom = 0` (none), **turn 120 s**, **deck choice 120 s**.
- Results count for nothing.

Our network duel already works like this, with room codes instead of a room list.

### Rating duel (`rd5`): automatic matching, rated

- The player waits in the title room until the server finds an opponent (`ENEMY_FOUND`). **Both players must then accept**, and there's a timeout on the second accept. Either player can back out. Leaving after an opponent is found is handled as a separate case. [str]
- Timers [cfg]: **room wait 180 s**, **turn 120 s**, **deck 120 s**.
- The "5" in `RatingDuel5` isn't explained anywhere. It could be a number of rounds or a matching bracket. [unknown]
- The server collects reports from both players (`FIRST_GAME_REPORT`, `SECOND_GAME_REPORT`), with a timeout for each. A player who disconnects before reporting is handled as a separate case. [str]

### Sealed ("Blind", `s`): build from a random pool

- Each player receives a **77-spell pool** (`s.nSpellPackSize = 77`) and builds a deck from it. [cfg]
- Timers [cfg]: **inventory (deck building) 300 s**, **deck 120 s**, **turn 120 s**.
- Flow [str]: title room → opponent found → both accept → inventory phase → connect → duel → both report → back to the title room. Players can surrender during deck building.
- Admins can switch packs to a fixed seed (`random packs`, "Random spells switched off, seed=%i"). [str]

### Round table (Draft8, `d8`): 8-player booster draft

- **8 seats.** Empty seats can be filled with **bots** (`PT_BOT`, `INV_ADD_BOT_OR_DEL`), and bots pick spells automatically (`FA_OUT_DR_BOT_AUTO_SELECT_SPELL`). [str]
- **Pack makeup** [cfg]: **10 cantrips, 21 common, 21 rare, 20 unique, 5 skills**, 77 in all, the same as the sealed pool. The corrupted comment under these lines has the word lengths of "не должна быть больше 100", which would mean the total may not exceed 100. [inferred]
- **Draft** [cfg][str]: the server deals packs (`NEW_PACK`). Each player selects one spell per step (`SELECT_SPELL`). A step ends when everyone has picked or the step timer runs out, and then the server announces `DRAFTING_STEP_PASSED`. The step timer starts at **20 s** (`d8.sDraftingStart`) and shrinks to **8 s** (`d8.sDraftingEnd`) as the draft goes on. The client logs each pick to `%s_Drafting.log`. Admins can turn draft randomization on or off. Whether packs pass around the table like a booster draft isn't confirmed. [inferred]
- **Inventory** [cfg]: **300 s** to build the deck. **Deck 120 s**, **turn 40 s**. The short turn timer keeps an 8-player event moving.
- **Duels** [str]: the server runs a "battle plan", meaning the pairings, then sends the duel start and the connection details. After each duel both players report. The draft has its own round-results screen, an "exchange" phase between duels (`FA_ND_DR_EXCHANGE`; what changes hands isn't known), the next duel, and final results. A player who leaves the match ends up in the staging room or the title room. There's a result code for a bad deck (`DF_BAD_DECK_TAKEN`). [inferred: the format of the pairings]
- **Whole match limit: 2700 s (45 min)** (`d8.sMatchTout`). [cfg]

## Ratings and statistics (`statistics` table)

- For each of **Duel, Draft and Sealed**, the server stores wins, losses, draws, a rating and a place, and it also keeps these **for each race** (Chaot, Kinet, Synthet, Vital, Pale). On top of that there are totals per race and an overall rating. Every rating starts at **100**. A race can be `ER_NOT_CHOSEN`. [str]
- After a result, the player's rating changes and the places of everyone between the old and new rating move by one, using `UPDATE … SET place=place±1 WHERE rating BETWEEN …`. There is also a full "places global update". [str]
- **The rating formula isn't visible in the strings.** Finding it would mean reading the compiled code. [unknown]
- The server also records minutes played, the last match ID, and site-wide counters (users online, registered users, games running).
- The `users` table holds ID, name, password (stored as plain text, up to 40 characters), a banned flag, the CD key and the last login time.

## Admin and chat commands

Players whisper to the server as a user (`/w server <command>`). These commands appear in the strings [str]: `who am i` (name, rating, level, cheats, game type, state, room and match IDs, host flag, penalty), `who are you`, `set rating`, `set cheats`, `set const.` / `view consts` (change timers while running), `set login msg`, `set periodic msg`, `surrender`, `set/reset/show bInternal`, `show NAT`, `force evilnat`, `show traffic`, `show duel version`, `drop user`, ping, `dump drmatch <nick>`, `dump all drmatches/smatches/dmatches`, `dump advtrs`, `random packs`, `Draft rnd on/off`, `battleplan`, `how many players in Draft match`, `terminate`. The server also has a flood guard ("Stop flooding!").

## Packet format (`ethc.exe`)

The client describes packets with small format strings. My reading of the notation [inferred]: `b` byte, `w` 16-bit word, `d` 32-bit dword, `s[min,max]` a string with a length range, `b[min,max]` a bounded byte, `%N(...)` a group repeated N times, and `%0x01(...)` a group repeated by a count read earlier. Examples:

```
b,s[0x1,0x20],s[0x1,0x20],w,s[0x1,0x100],b[0x0,0x8],%5(d),d
b,s[0x1,0x20],s[0x1,0x20],w,b[0x0,0x8],%4(d),d
b,w,%0x01(b,d,w,s[0x0,0x80],s[0x0,0x20],d,w,b,w,b,w)
b,w,%0x01(s[0x0,0x20],s[0x0,0x20],s[0x1,0x3FF],d,b)
```

The first two have the shape of register and login (name up to 32, password up to 32, a version word, and an extra string for registration, probably the CD key). The others look like lists of rooms or players. The connection is encrypted (`Crypto.cpp`, `SEND2_CRYPTO_KEYS`). Copying this protocol would only matter for letting the original game connect, which Demiurges doesn't attempt.

## Compared with Demiurges

| Original service | Demiurges today |
|---|---|
| Accounts, CD keys, bans | None. Rooms are reached by code through the relay, and LAN or direct IP also work. |
| Peer-to-peer game connection, EthProxy as a fallback | All online games go through the WebSocket relay. LAN and direct connections are also available. |
| Training duel: custom rooms, turn and deck 120 s | Network duel: host sets the arena, resource cap, rounds (1–99) and optional turn and deck timers. |
| Rating duel: automatic matching, both accept, rated | No matching and no ratings. |
| Sealed: 77-spell pool, 300 s to build | Not implemented. |
| Round table: 8-seat draft with bots, timers shrinking 20 → 8 s, 45-minute match | Not implemented. Between rounds, players can swap cards from their reserve. |
| Each side reports the result and the server compares them | Both sides play out the same ordered commands. The host is in charge of the timers. |

If Demiurges adds draft or sealed, the numbers marked [cfg] above are the original defaults to start from. They are timers, pool sizes and the rarity split. Open questions, each needing either a look at the compiled code or someone who played on the service:
- How packs move between the 8 drafters.
- How the draft pairs players for its duels.
- What the "exchange" phase between duels is.
- The rating formula.
- What `rd5` means.
