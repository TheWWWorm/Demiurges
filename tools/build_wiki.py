#!/usr/bin/env python3
"""Build the Demiurges wiki from its English and Russian sources.

The articles are authored in `wiki/<lang>/<page>.md` (a small Markdown subset,
see docs/wiki.md). This tool validates them and writes both readers' data:

- `public/wiki/`: the hosted website. The interface files are copied from
  `web/wiki/`; every article becomes `data/<lang>/pages/<page>.json` and each
  language gets a searchable `data/<lang>/index.json`. `BUILD-INFO.json` lists
  every file with its size and SHA-256.
- `game/src/wiki/wiki_data.gd`: the same articles for the in-game reader
  (ELWikiScreen), generated, never edited by hand.

Both readers receive the same escaped HTML subset (h1-h3, p, ul/ol/li, table,
strong, em, code, a). Internal links are `wiki://<page>`; the website rewrites
them to `?page=<page>`. The encyclopedia comes from `wiki/catalog/` (exported by
tools/export_wiki.gd); only its pictures that pages show are published.

    python3 tools/build_wiki.py            # rebuild both outputs
    python3 tools/build_wiki.py --check    # fail if either output is stale
"""
import argparse
import hashlib
import html
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'wiki'
FRONTEND = ROOT / 'web/wiki'
PUBLIC = ROOT / 'public/wiki'
GAME_DATA = ROOT / 'game/src/wiki/wiki_data.gd'
LANGUAGES = ['en', 'ru']
KEY = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)*$')
CYRILLIC = re.compile('[Ѐ-ӿ]')


class WikiError(Exception):
    pass


def game_version():
    text = (ROOT / 'game/project.godot').read_text(encoding='utf-8')
    return re.search(r'^config/version="([^"]+)"', text, re.M)[1]


def categories():
    data = json.loads((SOURCE / 'categories.json').read_text(encoding='utf-8'))
    for row in data:
        if set(row) - {'catalog'} != {'id', *LANGUAGES} or not all(row[lang].strip() for lang in LANGUAGES):
            raise WikiError(f'categories.json: {row} needs an id and a name in {LANGUAGES} (and may say "catalog": true)')
    return data


# --- Markdown subset ----------------------------------------------------------

INLINE = re.compile(r'(`[^`]+`)|\*\*(.+?)\*\*|\*(.+?)\*|\[([^\]]+)\]\(([^)\s]+)\)')


def inline(text, page, links):
    """Escaped HTML for one line: **bold**, *italic*, `code`, [label](target)."""
    out, pos = [], 0
    for m in INLINE.finditer(text):
        out.append(html.escape(text[pos:m.start()], quote=False))
        code, bold, em, label, target = m.groups()
        if code:
            out.append(f'<code>{html.escape(code[1:-1], quote=False)}</code>')
        elif bold:
            out.append(f'<strong>{inline(bold, page, links)}</strong>')
        elif em:
            out.append(f'<em>{inline(em, page, links)}</em>')
        elif target.startswith('https://'):
            out.append(f'<a href="{html.escape(target)}">{inline(label, page, links)}</a>')
        else:
            if not KEY.match(target):
                raise WikiError(f'{page}: link target {target!r} is neither a page name nor an https:// address')
            links.add(target)
            out.append(f'<a href="wiki://{target}">{inline(label, page, links)}</a>')
        pos = m.end()
    out.append(html.escape(text[pos:], quote=False))
    return ''.join(out)


HERO = re.compile(r'(el1|el2)/([^=|]+?)\s*=\s*([^|]+)')


def heroes(value, name):
    """Story heroes of a page: `heroes: el1/Diamanda = Caption | el2/...`, each a
    HeroTemplates row of a game and its caption -> [[game, row, caption], ...]."""
    out = []
    for item in filter(None, (part.strip() for part in value.split('|'))):
        m = HERO.fullmatch(item)
        if not m:
            raise WikiError(f'{name}: heroes entries are "el1|el2/<HeroTemplates row> = <caption>", not {item!r}')
        out.append([m[1], m[2].strip(), m[3].strip()])
    return out


def hero_image(game, template):
    """The exported picture of a story hero (tools/export_wiki.gd names it so)."""
    return f'{game}/hero-' + re.sub(r'[^a-z0-9]+', '-', template.lower()).strip('-') + '.webp'


def parse(path):
    """Returns (meta, html, plain text, h2 count, links) for one source file."""
    text = path.read_text(encoding='utf-8').replace('\r\n', '\n')
    name = f'{path.parent.name}/{path.name}'
    m = re.match(r'---\n(.*?)\n---\n', text, re.S)
    if not m:
        raise WikiError(f'{name}: missing front matter')
    meta = {}
    for line in m[1].splitlines():
        key, _, value = line.partition(':')
        meta[key.strip()] = value.strip()
    if not meta.get('title') or not meta.get('category'):
        raise WikiError(f'{name}: front matter needs title and category')
    meta['order'] = int(meta.get('order', 100))
    meta['heroes'] = heroes(meta.get('heroes', ''), name)
    body = text[m.end():].strip('\n').split('\n')
    links, out, plain, sections = set(), [f'<h1>{html.escape(meta["title"], quote=False)}</h1>'], [meta['title']], 0
    i = 0

    def para_lines(start):
        rows = []
        j = start
        while j < len(body) and body[j].strip() and not re.match(r'(#{2,3} |- |\d+\. |\||> )', body[j]):
            rows.append(body[j].strip())
            j += 1
        return rows, j

    while i < len(body):
        line = body[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith('# '):
            raise WikiError(f'{name}: use the front-matter title instead of a "# " heading')
        h = re.match(r'(#{2,3}) (.+)', line)
        if h:
            level = len(h[1])
            sections += level == 2
            out.append(f'<h{level}>{inline(h[2], name, links)}</h{level}>')
            plain.append(h[2])
            i += 1
        elif re.match(r'(- |\d+\. )', line):
            tag = 'ul' if line.startswith('- ') else 'ol'
            items = []
            while i < len(body) and re.match(r'(- |\d+\. )' if tag == 'ol' else r'- ', body[i]):
                item = re.sub(r'^(- |\d+\. )', '', body[i]).strip()
                i += 1
                while i < len(body) and body[i].startswith('  ') and body[i].strip():
                    item += ' ' + body[i].strip()
                    i += 1
                items.append(f'<li>{inline(item, name, links)}</li>')
                plain.append(item)
            out.append(f'<{tag}>{"".join(items)}</{tag}>')
        elif line.startswith('|'):
            rows = []
            while i < len(body) and body[i].startswith('|'):
                rows.append([c.strip() for c in body[i].strip().strip('|').split('|')])
                i += 1
            if len(rows) < 3 or not all(re.fullmatch(r':?-+:?', c) for c in rows[1]):
                raise WikiError(f'{name}: a table needs a header row and a --- separator row')
            columns = len(rows[0])
            if any(len(r) != columns for r in rows):
                raise WikiError(f'{name}: table rows have different numbers of cells')
            cells = ['<tr>' + ''.join(f'<th>{inline(c, name, links)}</th>' for c in rows[0]) + '</tr>']
            for row in rows[2:]:
                cells.append('<tr>' + ''.join(f'<td>{inline(c, name, links)}</td>' for c in row) + '</tr>')
                plain.extend(row)
            out.append(f'<table data-columns="{columns}">{"".join(cells)}</table>')
        elif line.startswith('> '):
            rows = []
            while i < len(body) and body[i].startswith('> '):
                rows.append(body[i][2:].strip())
                i += 1
            out.append(f'<p class="note">{inline(" ".join(rows), name, links)}</p>')
            plain.extend(rows)
        else:
            rows, i = para_lines(i)
            out.append(f'<p>{inline(" ".join(rows), name, links)}</p>')
            plain.extend(rows)
    words = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', ' '.join(plain))
    words = re.sub(r'[*`]', '', words)
    return meta, ''.join(out), words, sections, links


def load():
    """Validated catalogue: {lang: [page, ...]} sorted by category and order."""
    cats = categories()
    known = {c['id'] for c in cats}
    rank = {c['id']: n for n, c in enumerate(cats)}
    pages = {}
    for lang in LANGUAGES:
        rows = []
        for path in sorted((SOURCE / lang).glob('*.md')):
            key = path.stem
            if not KEY.match(key):
                raise WikiError(f'{lang}/{path.name}: page names are lower-case words joined by "-"')
            meta, body, words, sections, links = parse(path)
            if meta['category'] not in known:
                raise WikiError(f'{lang}/{path.name}: unknown category {meta["category"]!r}')
            if lang == 'ru' and len(CYRILLIC.findall(words)) < len(words) * 0.3:
                raise WikiError(f'ru/{path.name}: the Russian article is mostly not in Russian')
            rows.append({'key': key, 'title': meta['title'], 'category': meta['category'],
                         'order': meta['order'], 'summary': meta.get('summary', ''), 'heroes': meta['heroes'],
                         'html': body, 'search': words.lower(), 'sections': sections, 'links': sorted(links)})
        pages[lang] = rows
    catalog_pages = load_catalog(known)
    catalog_keys = {r['key'] for r in catalog_pages.get('en', [])}
    for lang in LANGUAGES:
        pages[lang].sort(key=lambda r: (rank[r['category']], r['order'], r['key']))
    keys = {lang: [r['key'] for r in pages[lang]] for lang in LANGUAGES}
    if 'home' not in keys['en']:
        raise WikiError('The wiki needs a "home" page')
    for lang in LANGUAGES[1:]:
        if set(keys[lang]) != set(keys['en']):
            missing = sorted(set(keys['en']) ^ set(keys[lang]))
            raise WikiError(f'English and {lang} have different pages: {missing}')
    by_key = {lang: {r['key']: r for r in pages[lang]} for lang in LANGUAGES}
    for key in keys['en']:
        rows = [by_key[lang][key] for lang in LANGUAGES]
        if len({r['category'] for r in rows}) != 1 or len({r['order'] for r in rows}) != 1:
            raise WikiError(f'{key}: category and order must match in every language')
        if len({tuple((h[0], h[1]) for h in r['heroes']) for r in rows}) != 1:
            raise WikiError(f'{key}: the translations list different heroes')
        if len({r['sections'] for r in rows}) != 1:
            raise WikiError(f'{key}: the translations have different numbers of "## " sections')
        if len({tuple(r['links']) for r in rows}) != 1:
            raise WikiError(f'{key}: the translations link to different pages')
        for target in rows[0]['links']:
            if target not in by_key['en'] and target not in catalog_keys:
                raise WikiError(f'{key}: link to missing page {target!r}')
    for row in pages['en']:
        if row['key'] != 'home' and not any(row['key'] in r['links'] for r in pages['en']):
            raise WikiError(f'{row["key"]}: no other page links to it')
    linked = {target for r in pages['en'] for target in r['links']}
    for c in cats:
        if c.get('catalog') and c['id'] in catalog_keys and c['id'] not in linked:
            raise WikiError(f'{c["id"]}: no guide page links to this list')
    for lang in LANGUAGES:
        pages[lang] = sorted(pages[lang] + catalog_pages.get(lang, []),
                             key=lambda r: (rank[r['category']], r['order'], r['title'].lower() if r.get('catalog') else r['key']))
    return cats, pages


CATALOG = SOURCE / 'catalog'
FIGURE = re.compile(r'<figure data-card="([A-Za-z0-9_]+)" data-kind="(\w+)" data-games="([a-z0-9 ]+)"></figure>')


def load_catalog(known):
    """The exported encyclopedia (tools/export_wiki.gd: both games merged) in
    every language: {lang: [page, ...]}."""
    pages = {lang: [] for lang in LANGUAGES}
    files = {lang: CATALOG / f'{lang}.json' for lang in LANGUAGES}
    present = [lang for lang, path in files.items() if path.is_file()]
    if not present:
        return pages
    if len(present) != len(LANGUAGES):
        raise WikiError(f'catalog: exported only in {present}; export every language')
    data = {lang: json.loads(files[lang].read_text(encoding='utf-8')) for lang in LANGUAGES}
    keys = {lang: {p['key'] for p in data[lang]['pages']} for lang in LANGUAGES}
    for lang in LANGUAGES[1:]:
        if keys[lang] != keys['en']:
            raise WikiError(f'catalog: English and {lang} pages differ: {sorted(keys[lang] ^ keys["en"])[:12]}')
    for lang in LANGUAGES:
        for p in data[lang]['pages']:
            if p['category'] not in known:
                raise WikiError(f'catalog: {p["key"]} is in category {p["category"]!r}, missing from categories.json')
            links = sorted(set(re.findall(r'href="wiki://([a-z0-9-]+)"', p['html'])))
            for target in links:
                if target not in keys['en']:
                    raise WikiError(f'catalog: {p["key"]} links to missing page {target!r}')
            pages[lang].append({'key': p['key'], 'title': p['title'], 'category': p['category'],
                                'order': int(p.get('order', 0)), 'summary': p.get('summary', ''),
                                'html': p['html'], 'search': p.get('search', ''), 'links': links,
                                'catalog': True, 'games': p.get('games', [])})
    return pages


GAME_NAMES = {'el1': 'Etherlords', 'el2': 'Etherlords II'}


def web_figures(html, images, used):
    """The website shows the exported creature pictures (one per edition that
    draws it differently, captioned), or the card icon of the newest edition."""
    def figure(m):
        code, kind, games = m[1], m[2], m[3].split()
        if kind == 'creature':
            shown = [g for g in games if f'{g}/{code}.webp' in images]
            if shown:
                out = ''
                for game in shown:
                    used.add(f'{game}/{code}.webp')
                    caption = f'<figcaption>{GAME_NAMES[game]}</figcaption>' if len(shown) > 1 else ''
                    out += f'<figure class="model"><img src="/wiki/images/{game}/{code}.webp" alt="" loading="lazy">{caption}</figure>'
                return out if len(shown) == 1 else f'<div class="figures">{out}</div>'
        for game in ['el2', 'el1']:
            if f'{game}/icon-{code}.png' in images:
                used.add(f'{game}/icon-{code}.png')
                return f'<figure class="icon"><img src="/wiki/images/{game}/icon-{code}.png" alt="" loading="lazy"></figure>'
        return ''
    return FIGURE.sub(figure, html)


def web_heroes(page, heroes, images, used):
    """A story page's heroes as a captioned gallery under its heading, for the
    heroes whose pictures were exported."""
    out = ''
    for game, template, caption in heroes:
        name = hero_image(game, template)
        if name in images:
            used.add(name)
            out += (f'<figure class="model"><img src="/wiki/images/{name}" alt="{html.escape(caption)}" loading="lazy">'
                    f'<figcaption>{html.escape(caption, quote=False)}</figcaption></figure>')
    if not out:
        return page
    head, _, rest = page.partition('</h1>')
    return f'{head}</h1><div class="heroes">{out}</div>{rest}'


# --- Outputs ------------------------------------------------------------------

def interface_labels():
    labels = json.loads((FRONTEND / 'i18n.json').read_text(encoding='utf-8'))
    if set(labels) != set(LANGUAGES):
        raise WikiError(f'web/wiki/i18n.json needs exactly {LANGUAGES}')
    for lang in LANGUAGES:
        if set(labels[lang]) != set(labels['en']) or not all(labels[lang].values()):
            raise WikiError(f'web/wiki/i18n.json: {lang} keys differ from English or are empty')
    return labels


def write_public(output, cats, pages):
    interface_labels()
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    for source in sorted(FRONTEND.iterdir()):
        if source.is_file():
            shutil.copyfile(source, output / source.name)
    source = CATALOG / 'images'
    images = {p.relative_to(source).as_posix() for p in source.rglob('*') if p.is_file()} if source.is_dir() else set()
    used = set()
    version = game_version()
    report = {'version': version, 'languages': {}, 'requires_game_files': False, 'requires_account': False}
    for lang in LANGUAGES:
        folder = output / 'data' / lang / 'pages'
        folder.mkdir(parents=True)
        entries = []
        for row in pages[lang]:
            page = {'key': row['key'], 'title': row['title'], 'category': row['category'],
                    'html': web_heroes(web_figures(row['html'], images, used), row.get('heroes', []), images, used)}
            (folder / f'{row["key"]}.json').write_text(json.dumps(page, ensure_ascii=False, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
            entry = {'key': row['key'], 'title': row['title'], 'category': row['category'],
                     'summary': row['summary'], 'search': row['search']}
            if row.get('catalog'):
                entry['games'] = row['games']
            entries.append(entry)
        index = {'version': version, 'language': lang,
                 'categories': [{'id': c['id'], 'title': c[lang], **({'catalog': True} if c.get('catalog') else {})} for c in cats],
                 'entries': entries}
        (output / 'data' / lang / 'index.json').write_text(json.dumps(index, ensure_ascii=False, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
        report['languages'][lang] = {'pages': len(entries), 'catalog_pages': sum(1 for r in pages[lang] if r.get('catalog')),
                                     'links': sum(len(r['links']) for r in pages[lang])}
    # Only the pictures the pages show are published.
    for name in sorted(used):
        (output / 'images' / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, output / 'images' / name)
    report['images'] = len(used)
    report['translation_keys'] = len(interface_labels()['en'])
    files = {p.relative_to(output).as_posix(): {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
             for p in sorted(output.rglob('*')) if p.is_file()}
    report['files'] = files
    report['bytes'] = sum(r['bytes'] for r in files.values())
    (output / 'BUILD-INFO.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
    return report


def gd_string(value):
    return json.dumps(value, ensure_ascii=False)


def game_script(cats, pages):
    lines = [
        '# Generated by tools/build_wiki.py from wiki/<lang>/*.md. Do not edit;',
        '# edit the sources and run `python3 tools/build_wiki.py`.',
        'class_name ELWikiData',
        'extends RefCounted',
        '## The wiki articles for the in-game reader (ELWikiScreen), in every',
        '## language. Each page: key, title, category, html (escaped subset), search.',
        '',
        f'const VERSION := {gd_string(game_version())}',
        f'const LANGUAGES: Array[String] = {gd_string(LANGUAGES)}',
        'const CATEGORIES := [',
    ]
    for c in cats:
        fields = ['id', *LANGUAGES] + (['catalog'] if c.get('catalog') else [])
        lines.append('\t{' + ', '.join(f'{gd_string(k)}: {gd_string(c[k])}' for k in fields) + '},')
    lines += [']', '', 'const PAGES := {']
    for lang in LANGUAGES:
        lines.append(f'\t{gd_string(lang)}: [')
        for row in pages[lang]:
            if row.get('catalog'):
                continue
            fields = {k: row[k] for k in ['key', 'title', 'category', 'html', 'search']}
            if row.get('heroes'):
                fields['heroes'] = row['heroes']
            lines.append('\t\t{' + ', '.join(f'{gd_string(k)}: {gd_string(v)}' for k, v in fields.items()) + '},')
        lines.append('\t],')
    lines.append('}')
    return '\n'.join(lines) + '\n'


def compare(expected, actual):
    """Paths that differ between two directory trees."""
    names = {p.relative_to(expected).as_posix() for p in expected.rglob('*') if p.is_file()}
    names |= {p.relative_to(actual).as_posix() for p in actual.rglob('*') if p.is_file()} if actual.exists() else set()
    return sorted(n for n in names if not (expected / n).is_file() or not (actual / n).is_file()
                  or (expected / n).read_bytes() != (actual / n).read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true', help='Verify that public/wiki and the game data are current')
    parser.add_argument('--output', type=Path, default=PUBLIC, help='Website directory (default public/wiki)')
    args = parser.parse_args()
    try:
        cats, pages = load()
        script = game_script(cats, pages)
        if args.check:
            with tempfile.TemporaryDirectory() as tmp:
                staged = Path(tmp) / 'wiki'
                write_public(staged, cats, pages)
                stale = compare(staged, args.output)
            if stale:
                raise WikiError('The website is stale; run tools/build_wiki.py. Differs: ' + ', '.join(stale[:10]))
            if not GAME_DATA.is_file() or GAME_DATA.read_text(encoding='utf-8') != script:
                raise WikiError(f'{GAME_DATA.relative_to(ROOT)} is stale; run tools/build_wiki.py')
            print(f'Wiki verified: {len(pages["en"])} pages in {", ".join(LANGUAGES)}; version {game_version()}')
            return
        report = write_public(args.output, cats, pages)
        GAME_DATA.parent.mkdir(parents=True, exist_ok=True)
        GAME_DATA.write_text(script, encoding='utf-8', newline='\n')
        print(f'Wiki built: {len(pages["en"])} pages per language, {len(report["files"])} files, '
              f'{report["bytes"] / 1024:.0f} KiB -> {args.output}; {GAME_DATA.relative_to(ROOT)}')
    except WikiError as error:
        sys.exit(f'wiki: {error}')


if __name__ == '__main__':
    main()
