#!/usr/bin/env python3
"""Export the engine for the browser or Android with Godot 4.7.

The output holds the engine only; players import their own game files.

  python3 tools/export_mobile.py web --output build/web
  python3 tools/export_mobile.py android --output build/android [--sdk DIR] [--java DIR] [--release]

Web: besides Godot's export, the page needs the local-file bridge in web/
(files.js and its workers), a service worker, icons and the cross-origin
isolation headers. Serve the result over HTTPS (or localhost) with
Cross-Origin-Opener-Policy: same-origin and Cross-Origin-Embedder-Policy:
require-corp; tools/serve_web.py does this locally.

Android: needs the Android SDK (--sdk or ANDROID_HOME) and a JDK (--java or
JAVA_HOME). A debug export signs with Godot's debug keystore. A release
export uses the release keystore configured in Godot's export credentials.
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile

LICENSE_SCRIPT = '''extends SceneTree
func _initialize():
 var file = FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
 file.store_string(Engine.get_license_text())
 var info = Engine.get_license_info()
 for name in info:
  file.store_string("\\n\\n" + name + "\\n" + str(info[name]) + "\\n")
 file.close()
 quit()
'''
ICON_SCRIPT = '''extends SceneTree
func _initialize():
 var source = FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0])
 for size in [192, 512]:
  var img = Image.new()
  img.load_svg_from_string(source, float(size) / 512.0)
  img.save_png(OS.get_cmdline_user_args()[1].path_join("icon-%d.png" % size))
 quit()
'''
WEB_FILES = ('storage.js', 'files.js', 'data-worker.js', 'installer-worker.js')
# The page mounts the player's stored files into the engine's file system, so
# the engine module must expose it. Godot's loader keeps it private otherwise.
FS_HOOK = 'Module["copyToFS"]=GodotFS.copy_to_fs'
NOTICES = ('LICENSE.md', 'THIRD_PARTY_NOTICES.md')
HEADERS = '''# Served by static hosts that read _headers (Cloudflare Workers assets, Pages, Netlify).
# The local-file bridge needs SharedArrayBuffer, so every page must be cross-origin isolated.
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  Cross-Origin-Resource-Policy: same-origin

/*.wasm
  Content-Type: application/wasm

# The shell and the service worker must be revalidated, so a new export is picked up.
/
  Cache-Control: no-cache

/index.html
  Cache-Control: no-cache

/service-worker.js
  Cache-Control: no-cache
'''


def run_checked(command, **kwargs):
    print('$', ' '.join(str(c) for c in command), flush=True)
    result = subprocess.run([str(c) for c in command], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, **kwargs)
    print(result.stdout, end='', flush=True)
    result.check_returncode()
    # Godot may return success despite a script or export error.
    if re.search(r'(?m)^(?:SCRIPT )?ERROR:', result.stdout):
        raise RuntimeError('Godot reported an error; see the output above.')
    return result.stdout


def stage_project(project, stage):
    stage.mkdir()
    for name in ('src', 'scenes', 'web', 'native'):
        if (project / name).is_dir():
            shutil.copytree(project / name, stage / name, ignore=shutil.ignore_patterns('*.import', '__pycache__'))
    for name in ('project.godot', 'export_presets.cfg', 'icon.svg'):
        shutil.copyfile(project / name, stage / name)


def notices_dir(project):
    for candidate in (project, project.parent):
        if all((candidate / name).is_file() for name in NOTICES) and (candidate / 'licenses').is_dir():
            return candidate
    raise SystemExit('LICENSE.md, THIRD_PARTY_NOTICES.md and licenses/ were not found next to the project.')


def godot_licenses(godot, target, env):
    with tempfile.TemporaryDirectory(prefix='demiurges-licenses-') as folder:
        script = pathlib.Path(folder) / 'licenses.gd'
        script.write_text(LICENSE_SCRIPT)
        run_checked([godot, '--headless', '--script', script, '--', target], env=env)


def android_notices(stage, notices, godot, env):
    """Embed the distribution notices in the package without changing the game."""
    target = stage / 'src/release_licenses'
    target.mkdir()
    names = []
    for source in [notices / name for name in NOTICES] + sorted((notices / 'licenses').glob('*.txt')):
        name = source.stem + '.txt'
        shutil.copyfile(source, target / name)
        names.append(name)
    godot_licenses(godot, target / 'GODOT_LICENSES.txt', env)
    names.append('GODOT_LICENSES.txt')
    presets = stage / 'export_presets.cfg'
    blocks = re.split(r'(?=\[preset\.\d+\]\n)', presets.read_text())
    matches = 0
    for index, block in enumerate(blocks):
        if re.search(r'^name="Android"$', block, re.M):
            existing = re.search(r'^include_filter="([^"]*)"$', block, re.M)
            filters = [value.strip() for value in existing[1].split(',') if value.strip()]
            filters += ['src/release_licenses/' + name for name in names]
            blocks[index] = block[:existing.start()] + 'include_filter=' + json.dumps(','.join(dict.fromkeys(filters))) + block[existing.end():]
            matches += 1
    if matches != 1:
        raise SystemExit('Expected one Android preset.')
    presets.write_text(''.join(blocks))


def android_settings(temp, sdk, java, env):
    """Point an isolated copy of Godot's editor settings at the SDK and JDK."""
    config = pathlib.Path(env.get('XDG_CONFIG_HOME', pathlib.Path.home() / '.config')) / 'godot/editor_settings-4.7.tres'
    settings = config.read_text() if config.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    for key, value in (('android_sdk_path', sdk), ('java_sdk_path', java)):
        if not value:
            continue
        line = 'export/android/' + key + ' = ' + json.dumps(str(pathlib.Path(value).resolve()))
        pattern = '^export/android/' + key + ' = .*?$'
        settings = re.sub(pattern, line, settings, flags=re.M) if re.search(pattern, settings, flags=re.M) else settings + line + '\n'
    folder = temp / 'config/godot'
    folder.mkdir(parents=True)
    (folder / 'editor_settings-4.7.tres').write_text(settings)
    env['XDG_CONFIG_HOME'] = str(folder.parent)


def finish_web(stage, output, notices, godot, env):
    index = output / 'index.js'
    script = index.read_text()
    if script.count(FS_HOOK) != 1:
        raise SystemExit('This Godot web template is not supported: its file system hook was not found.')
    index.write_text(script.replace(FS_HOOK, FS_HOOK + ';Module["ELFS"]=FS'))
    for name in WEB_FILES:
        shutil.copyfile(stage / 'web' / name, output / name)
    with tempfile.TemporaryDirectory(prefix='demiurges-icons-') as folder:
        icon_script = pathlib.Path(folder) / 'icons.gd'
        icon_script.write_text(ICON_SCRIPT)
        run_checked([godot, '--headless', '--script', icon_script, '--', stage / 'icon.svg', output], env=env)
    manifest = {'id': './', 'name': 'Demiurges', 'short_name': 'Demiurges', 'start_url': './', 'scope': './',
                'display': 'standalone', 'orientation': 'landscape', 'background_color': '#0f1118',
                'theme_color': '#0f1118', 'icons': [{'src': f'icon-{size}.png', 'sizes': f'{size}x{size}',
                                                      'type': 'image/png', 'purpose': 'any'} for size in (192, 512)]}
    (output / 'manifest.webmanifest').write_text(json.dumps(manifest, indent=2) + '\n')
    for name in NOTICES:
        shutil.copyfile(notices / name, output / name)
    (output / 'licenses').mkdir(exist_ok=True)
    for source in sorted((notices / 'licenses').glob('*.txt')):
        if source.name != 'GODOT_LICENSES.txt':
            shutil.copyfile(source, output / 'licenses' / source.name)
    godot_licenses(godot, output / 'GODOT_LICENSES.txt', env)
    # The service worker caches exactly these files and reuses unchanged ones
    # (same SHA-256) from the previous version.
    files = sorted(p.name for p in output.iterdir() if p.is_file() and p.suffix in
                   {'.html', '.js', '.wasm', '.pck', '.png', '.webmanifest'} and p.name != 'service-worker.js')
    digest, hashes = hashlib.sha256(), {}
    for name in files:
        data = (output / name).read_bytes()
        digest.update(data)
        hashes[name] = hashlib.sha256(data).hexdigest()
    worker = (stage / 'web/service-worker.js').read_text()
    worker = worker.replace('@BUILD@', digest.hexdigest()[:20]).replace('@FILES@', json.dumps(hashes, indent=0))
    (output / 'service-worker.js').write_text(worker)
    (output / '_headers').write_text(HEADERS)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('platform', choices=['web', 'android'])
    parser.add_argument('--output', type=pathlib.Path, required=True)
    here = pathlib.Path(__file__).resolve().parents[1]
    default_project = here / 'game' if (here / 'game/project.godot').exists() else here
    parser.add_argument('--project', type=pathlib.Path, default=default_project)
    parser.add_argument('--godot', default=shutil.which('godot-4') or shutil.which('godot'))
    parser.add_argument('--sdk', default=os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT'))
    parser.add_argument('--java', default=os.environ.get('JAVA_HOME'))
    parser.add_argument('--release', action='store_true', help='Release export (Android: needs release signing credentials).')
    args = parser.parse_args()
    project, output = args.project.resolve(), args.output.resolve()
    if output.is_relative_to(project):
        parser.error('Keep builds outside the engine source folder.')
    if not args.godot:
        parser.error('Install Godot 4.7 and its export templates.')
    notices = notices_dir(project)
    if args.platform == 'web' and output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    with tempfile.TemporaryDirectory(prefix='demiurges-export-') as temp:
        temp = pathlib.Path(temp)
        stage = temp / 'project'
        stage_project(project, stage)
        if args.platform == 'android':
            android_settings(temp, args.sdk, args.java, env)
            android_notices(stage, notices, args.godot, env)
        run_checked([args.godot, '--headless', '--path', stage, '--editor', '--import', '--quit'], env=env)
        credentials = project / '.godot/export_credentials.cfg'
        if args.release and credentials.exists():
            shutil.copyfile(credentials, stage / '.godot/export_credentials.cfg')
        name = 'index.html' if args.platform == 'web' else ('demiurges.apk' if args.release else 'demiurges-debug.apk')
        run_checked([args.godot, '--headless', '--path', stage, '--export-release' if args.release else '--export-debug',
                     'Web' if args.platform == 'web' else 'Android', output / name], env=env)
        if args.platform == 'web':
            finish_web(stage, output, notices, args.godot, env)
    print(output / name)


if __name__ == '__main__':
    main()
