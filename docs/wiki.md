# Wiki

The Demiurges wiki explains how to install and play Etherlords and Etherlords II on this engine. It has the same articles in two readers:

- **On the web** at [demiurges.wwworm.com/wiki](https://demiurges.wwworm.com/wiki/), served from `public/wiki` beside the browser build. It needs no game files, engine or account: the page never loads the engine, and the game's service worker passes its requests through. The browser build's start page (`game/web/shell.html`) links to it before any files are chosen.
- **In the game**: the **Wiki** button beside the game choice on the main menu and the game files screen, a **Wiki (F1)** button under the Etherlords II Esc menus in battle and on the map, and **F1** on every screen (the `WikiHotkey` autoload). The game is paused while it is open; **Esc**, **F1** or **Close** resumes it as it was.

Every article exists in English and Russian. Both readers have an EN/RU switch and remember the choice (the website in `localStorage`, the game in `user://wiki.cfg`). Until the player chooses, the game follows the language of the installed game's texts and the website follows the browser.

The wiki contains no game content: no extracted texts, pictures or card descriptions, only short names of game things. Names follow the original English and Russian editions («Демиурги», «Демиурги II») where they apply.

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

## Building

```sh
python3 tools/build_wiki.py
python3 tools/build_wiki.py --check
```

The build fails, without writing anything, when:

- the English and Russian page sets differ, or a page's category, order, number of `## ` sections or set of linked pages differs between the languages;
- a link points to a missing page, or a page is not linked from any other page (except `home`);
- a Russian article is mostly not in Cyrillic, a table is malformed, or front matter is missing;
- `web/wiki/i18n.json` lacks a key in one language.

It then replaces `public/wiki` (interface files, `data/<lang>/index.json`, `data/<lang>/pages/<page>.json` and `BUILD-INFO.json` with every file's size and SHA-256) and `game/src/wiki/wiki_data.gd`. `--check` rebuilds into a temporary folder and fails if `public/wiki` or the game data differ from the sources; run it before committing. The version shown in both readers is `config/version` from `game/project.godot`, so rebuild the wiki when the version changes.

Both readers get the same escaped HTML. Internal links are `wiki://<page>`: the website turns them into `/wiki/?lang=<lang>&page=<page>` addresses (Back, Forward, reload and shared links work), the game into page navigation. The game opens `https://` links in the system browser and never executes anything from an article.

## Hosting

`worker.js` redirects `/wiki` to `/wiki/` and serves the wiki with `Cache-Control: no-cache` and a restrictive content security policy (only its own scripts, styles and data). `public/_headers` carries the same headers for hosts that read it, and `tools/serve_web.py public` sends them locally: open `http://localhost:8060/wiki/`. `tools/prepare_web_host.py` keeps an existing `public/wiki` when it replaces the browser build, so a new engine export does not remove the wiki. The game's service worker does not cache wiki files.

## Checking

After `build_wiki.py`, import the project once and run the in-game check:

```sh
godot --headless --path game --import
godot --headless --path game --script /absolute/path/to/tools/wiki_check.gd
```

It converts every page in both languages, follows every link, and exercises history, search, the language switch, narrow windows and pausing. Without `--headless`, add `-- --wiki-shots=<folder>` to save screenshots. It restores the player's remembered wiki language afterwards. Check the website in a browser in both languages, including Back and reload, on a desktop and a phone-sized window.
