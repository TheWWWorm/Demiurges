# Wiki

The Demiurges wiki has two parts, as the EI remake's wiki does: **guides** (installing, controls, rules, campaigns, duels, options, differences from the originals) and an **encyclopedia** with a page for every creature, sorcery, enchantment, artifact, skill and specialization of both games, plus a list page per category. It has two readers:

- **On the web** at [demiurges.wwworm.com/wiki](https://demiurges.wwworm.com/wiki/), served from `public/wiki` beside the browser build. It needs no game files, engine or account: the page never loads the engine, and the game's service worker passes its requests through. The browser build's start page (`game/web/shell.html`) links to it before any files are chosen.
- **In the game**: the **Wiki** button beside the game choice on the main menu and the game files screen, a **Wiki (F1)** button under the Etherlords II Esc menus in battle and on the map, and **F1** on every screen (the `WikiHotkey` autoload). The game is paused while it is open; **Esc**, **F1** or **Close** resumes it as it was.

Every article exists in English and Russian. Both readers have an EN/RU switch and remember the choice (the website in `localStorage`, the game in `user://wiki.cfg`). Until the player chooses, the game follows the language of the installed game's texts and the website follows the browser.

Guides name game things as the original English (GOG) and Russian editions do.

The engine ships no game content. The in-game encyclopedia is built live from the player's installed copy by `ELWikiCatalog`, so it follows that copy's language, data and patches, and a creature's page shows the creature's own model, playing its idle animation, which the player can drag to turn and zoom with the wheel (`ELWikiPreview`). Encyclopedia pages exist only for installed games; links to another game's pages lead to the contents with a note. The website's encyclopedia is the same builder's output, exported from the original editions together with rendered creature pictures and card icons (see below); like EI's public wiki, it publishes the games' names, descriptions and pictures, credited to their owners.

## Sources

| Path | Contents |
|---|---|
| `wiki/categories.json` | Categories in their order, with English and Russian names |
| `wiki/en/<page>.md`, `wiki/ru/<page>.md` | One article per language; the file name is the page name |
| `web/wiki/` | The website: `index.html`, `wiki.js`, `wiki.css` and the interface texts `i18n.json` |
| `tools/build_wiki.py` | Validates the sources and writes both outputs |
| `game/src/wiki/wiki_data.gd` | Generated articles for the game (`ELWikiData`); never edit it by hand |
| `game/src/wiki/wiki_html.gd` | `ELWikiHtml`: the article HTML subset to RichTextLabel BBCode |
| `game/src/wiki/wiki_screen.gd` | `ELWikiScreen`: the in-game reader |
| `game/src/wiki/wiki_hotkey.gd` | The `WikiHotkey` autoload (F1) |
| `game/src/wiki/wiki_catalog.gd` | `ELWikiCatalog`: encyclopedia pages from a loaded game (`ELProfile`) |
| `game/src/wiki/wiki_preview.gd` | `ELWikiPreview`: the turnable creature model, also used to render website pictures |
| `tools/export_wiki.gd` | Exports one game's encyclopedia (and pictures) for the website |
| `wiki/catalog/` | The exported encyclopedia: `<game>-<lang>.json` and `images/<game>/` (`<CODE>.webp` creatures, `icon-<CODE>.png` cards) |

Each article starts with front matter:

```
---
title: Turn and phases
category: combat
order: 20
summary: The order of a turn
---
```

`category` is an id from `categories.json`; `order` sorts pages within it; `summary` is shown under search results. The body is a small Markdown subset: `## ` and `### ` headings, paragraphs, `- ` and `1. ` lists (continue an item on lines indented by two spaces), `|` tables with a `|---|` separator row, `> ` notes, `**bold**`, `*italic*`, `` `code` ``, links to other pages as `[label](page-name)` and to websites as `[label](https://…)`. The title becomes the page heading, so do not start the body with `# `.

## Exporting the encyclopedia

The website's encyclopedia is exported, not written. Export each game once per language with the engine (Godot 4.7, the project imported):

```sh
godot --path game --script /abs/tools/export_wiki.gd -- --wiki-game=el1 \
  --wiki-path="/path/to/Etherlords" --wiki-language=ru \
  --wiki-output=/abs/wiki/catalog --wiki-images=/abs/wiki/catalog/images
godot --headless --path game --script /abs/tools/export_wiki.gd -- --wiki-game=el1 \
  --wiki-path="/path/to/Etherlords" --wiki-language=en --wiki-output=/abs/wiki/catalog \
  --wiki-texts=/private/gog-el1/Resources/text.res --wiki-regs=/private/gog-el1/Resources/regs.res \
  --wiki-pages-from=/abs/wiki/catalog/el1-ru.json
```

and the same with `--wiki-game=el2` and the Etherlords II folder. `--wiki-language` sets the page labels; names and descriptions come from the mounted game. The checked export uses the Russian Steam copies for Russian and, for English, the same installs with the text and table archives of the GOG English editions (`--wiki-texts`, `--wiki-regs`; nothing in the installation changes). Those two archives can be taken from a GOG installer without running it, for example with the engine's `ELInnoSetup` or innoextract. `--wiki-pages-from` keeps the English export to the Russian page set: the GOG English tables name a few internal helper records (such as `AOUD` or "GraveyardToPlay") that the Russian edition leaves unnamed. Records whose name is only their code are never listed.

`--wiki-images` needs rendering, so that run omits `--headless`: it saves each card's icon and renders each creature with `ELWikiPreview` (960 px, cropped to the creature, saved as 480 px WebP). Run it once per game; the pictures do not depend on the language.

## Building

```sh
python3 tools/build_wiki.py
python3 tools/build_wiki.py --check
```

The build fails, without writing anything, when:

- the English and Russian page sets differ, or a page's category, order, number of `## ` sections or set of linked pages differs between the languages;
- a link points to a missing page, or a page is not linked from any other page (except `home`);
- a Russian article is mostly not in Cyrillic, a table is malformed, or front matter is missing;
- `web/wiki/i18n.json` lacks a key in one language;
- a game's encyclopedia is exported in only one language, its English and Russian pages differ, one of its links points to a missing page, or a guide does not link to one of its list pages.

It then replaces `public/wiki` (interface files, `images/`, `data/<lang>/index.json`, `data/<lang>/pages/<page>.json` and `BUILD-INFO.json` with every file's size and SHA-256) and `game/src/wiki/wiki_data.gd`. The game data holds only the guides; the encyclopedia is never shipped with the engine. On the website, a card page's `<figure data-card>` becomes its creature picture or card icon; the sidebar keeps the long encyclopedia lists closed unless one holds the open page or a search is typed. `--check` rebuilds into a temporary folder and fails if `public/wiki` or the game data differ from the sources; run it before committing. The version shown in both readers is `config/version` from `game/project.godot`, so rebuild the wiki when the version changes.

Both readers get the same escaped HTML. Internal links are `wiki://<page>`: the website turns them into `/wiki/?lang=<lang>&page=<page>` addresses (Back, Forward, reload and shared links work), the game into page navigation. The game opens `https://` links in the system browser and never executes anything from an article.

## Hosting

`worker.js` redirects `/wiki` to `/wiki/` and serves the wiki with `Cache-Control: no-cache` and a restrictive content security policy (only its own scripts, styles and data). `public/_headers` carries the same headers for hosts that read it, and `tools/serve_web.py public` sends them locally: open `http://localhost:8060/wiki/`. `tools/prepare_web_host.py` keeps an existing `public/wiki` when it replaces the browser build, so a new engine export does not remove the wiki. The game's service worker does not cache wiki files.

## Checking

After `build_wiki.py`, import the project once and run the in-game check:

```sh
godot --headless --path game --import
godot --headless --path game --script /absolute/path/to/tools/wiki_check.gd
```

It converts every page in both languages, follows every link, and exercises history, search, the language switch, narrow windows and pausing. With Steam copies installed (or `-- --wiki-el1=<folder> --wiki-el2=<folder>`), it also builds both games' encyclopedias in both languages, checks their links and list pages, opens a creature page and turns and zooms its live model. Without `--headless`, add `-- --wiki-shots=<folder>` to save screenshots. It restores the player's remembered wiki language afterwards. Check the website in a browser in both languages, including Back and reload, on a desktop and a phone-sized window.
