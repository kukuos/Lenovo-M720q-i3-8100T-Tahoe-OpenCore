#!/usr/bin/env python3
"""Use the pinned OpenCore macrecovery utility to fetch Apple's current recovery."""
import json
import pathlib
import subprocess
import sys
import tempfile
from build import ROOT, download, extract

item = json.loads((ROOT / 'dependencies.json').read_text())['opencore']
archive = download(item)
output = ROOT / 'dist' / 'USB' / 'com.apple.recovery.boot'
if output.exists():
    raise SystemExit('Recovery directory already exists; move it aside before downloading again.')
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='m720q-recovery-') as work:
    extract(archive, pathlib.Path(work))
    utility = pathlib.Path(work) / 'Utilities' / 'macrecovery' / 'macrecovery.py'
    subprocess.run([sys.executable, str(utility), '-os', 'latest', '-o', str(output), 'download'], check=True)
print('Check the offered macOS version in Recovery before installing; latest is not a version pin.')
