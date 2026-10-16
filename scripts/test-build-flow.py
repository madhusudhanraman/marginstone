#!/usr/bin/env python3
"""Check installer routing without an SDK; this is not a native compile test."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

project = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='nautilus-build-flow-') as temp:
    root = Path(temp).resolve(); copy = root/'Nautilus with spaces'
    shutil.copytree(project, copy, ignore=shutil.ignore_patterns('.git', '.build', 'dist', '__pycache__'))
    commands = root/'commands'; commands.mkdir()
    binary = root/'built product'; binary.mkdir()
    (binary/'Nautilus').write_text('stub executable')
    (binary/'Nautilus_Nautilus.bundle').mkdir()
    (binary/'Nautilus_Nautilus.bundle'/'resource.txt').write_text('stub resource')
    stubs = {
        'uname': 'echo Darwin',
        'xcrun': 'echo /stub/swift',
        'swift': '''printf '%s\n' "$*" >> "$TEST_LOG"
[[ "$1" == build ]] || { echo 'Installer invoked tests' >&2; exit 99; }
[[ " $* " == *' --product Nautilus '* ]] || exit 98
if [[ " $* " == *' --show-bin-path '* ]]; then echo "$TEST_BIN"; fi''',
        'swiftc': r'''while [[ $# -gt 0 ]]; do
if [[ "$1" == -o ]]; then shift; printf '#!/bin/bash\nexit 0\n' > "$1"; chmod +x "$1"; exit 0; fi
shift
done
exit 1''',
        'ditto': 'cp -R "$1" "$2"',
        'sips': ':',
        'iconutil': ':',
        'codesign': 'printf "%s\n" "$*" >> "$SIGN_LOG"',
    }
    for name, body in stubs.items():
        file = commands/name; file.write_text('#!/bin/bash\nset -euo pipefail\n'+body+'\n');file.chmod(0o755)
    env = dict(os.environ, PATH=str(commands)+os.pathsep+os.environ['PATH'], TEST_BIN=str(binary), TEST_LOG=str(root/'swift.log'), SIGN_LOG=str(root/'sign.log'))
    subprocess.run(['bash',str(copy/'scripts/build-macos.sh')],env=env,check=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    app = copy/'dist/Marginstone.app/Contents'
    assert (app/'MacOS/Marginstone').read_text()=='stub executable'
    assert (app/'Resources/Nautilus_Nautilus.bundle/resource.txt').read_text()=='stub resource'
    assert (app/'Info.plist').is_file()
    invocations=(root/'swift.log').read_text().splitlines()
    assert len(invocations)==2 and all(x.startswith('build ') and '--product Nautilus' in x and '--build-system native' in x and '--scratch-path' in x for x in invocations)
    assert '--verify --deep --strict' in (root/'sign.log').read_text()
    print('PASS: app-only builds, no XCTest invocation, paths with spaces, executable/resource packaging, signing/verification routing.')
