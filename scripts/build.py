#!/usr/bin/env python3
"""Rebuild the tested EFI locally; no personal identifiers are committed."""
import argparse
import hashlib
import json
import pathlib
import platform
import plistlib
import re
import shutil
import subprocess
import tempfile
import urllib.request
import uuid
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def download(item):
    cache = ROOT / '.cache'
    cache.mkdir(exist_ok=True)
    target = cache / item['name']
    if not target.exists():
        print('Downloading', item['name'])
        request = urllib.request.Request(item['url'], headers={'User-Agent': 'M720q-EFI-builder'})
        with urllib.request.urlopen(request, timeout=120) as response:
            temporary = target.with_suffix('.download')
            with temporary.open('wb') as output:
                shutil.copyfileobj(response, output)
            temporary.replace(target)
    if digest(target) != item['sha256']:
        raise RuntimeError(f'Archive hash mismatch: {target.name}')
    return target


def extract(archive, destination):
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            member = pathlib.PurePosixPath(entry.filename)
            if member.is_absolute() or '..' in member.parts or '\\' in entry.filename:
                raise RuntimeError('Unsafe archive path')
        package.extractall(destination)


def validate_paths(config, efi):
    oc = efi / 'OC'
    for item in config['ACPI']['Add']:
        if item['Enabled'] and not (oc / 'ACPI' / item['Path']).is_file():
            raise RuntimeError('Missing ACPI: ' + item['Path'])
    for item in config['UEFI']['Drivers']:
        if item['Enabled'] and not (oc / 'Drivers' / item['Path']).is_file():
            raise RuntimeError('Missing driver: ' + item['Path'])
    for item in config['Misc']['Tools']:
        if item['Enabled'] and not (oc / 'Tools' / item['Path']).is_file():
            raise RuntimeError('Missing tool: ' + item['Path'])
    for item in config['Kernel']['Add']:
        if not item['Enabled']:
            continue
        bundle = oc / 'Kexts' / item['BundlePath']
        for key in ('PlistPath', 'ExecutablePath'):
            if item[key] and not (bundle / item[key]).is_file():
                raise RuntimeError('Missing kext file: ' + item['BundlePath'] + '/' + item[key])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generate-smbios', action='store_true', help='Generate a fresh iMac20,1 identity')
    args = parser.parse_args()
    destination = ROOT / 'dist' / 'USB'
    if destination.exists():
        raise RuntimeError('dist/USB already exists. Move it aside before building again.')
    dependencies = json.loads((ROOT / 'dependencies.json').read_text())
    archives = {key: download(value) for key, value in dependencies.items()}
    with tempfile.TemporaryDirectory(prefix='m720q-build-') as work:
        work = pathlib.Path(work)
        for key, archive in archives.items():
            extract(archive, work / key)
        oc_package = work / 'opencore'
        source_efi = ROOT / 'EFI'
        if not source_efi.is_dir():
            raise RuntimeError('Repository EFI/ directory is missing')

        identity = None
        system = platform.system()
        if args.generate_smbios:
            tool_name = {'Windows': 'macserial.exe', 'Darwin': 'macserial', 'Linux': 'macserial.linux'}[system]
            serial_tool = oc_package / 'Utilities' / 'macserial' / tool_name
            serial_tool.chmod(0o755)
            result = subprocess.check_output([str(serial_tool), '-m', 'iMac20,1', '-n', '1'], text=True)
            match = re.search(r'([A-Z0-9]{12})\s*\|\s*([A-Z0-9]{17})', result)
            if not match:
                raise RuntimeError('Could not parse macserial output')
            rom = bytearray(uuid.uuid4().bytes[:6])
            rom[0] = (rom[0] & 0xFE) | 0x02
            identity = {'SystemSerialNumber': match[1], 'MLB': match[2], 'SystemUUID': str(uuid.uuid4()).upper(), 'ROM': bytes(rom)}

        for profile, subdir in [('usb', pathlib.Path('EFI')), ('internal', pathlib.Path('HardDisk-Install/EFI'))]:
            efi = destination / subdir
            for sub in ('Boot', 'OC'):
                shutil.copytree(source_efi / sub, efi / sub, dirs_exist_ok=True)
            config = plistlib.loads((ROOT / 'profiles' / (profile + '.plist')).read_bytes())
            if identity:
                config['PlatformInfo']['Generic'].update(identity)
            target_config = efi / 'OC' / 'config.plist'
            target_config.write_bytes(plistlib.dumps(config, sort_keys=False))
            validate_paths(config, efi)
            validator_name = {'Windows': 'ocvalidate.exe', 'Darwin': 'ocvalidate', 'Linux': 'ocvalidate.linux'}[system]
            validator = oc_package / 'Utilities' / 'ocvalidate' / validator_name
            validator.chmod(0o755)
            subprocess.run([str(validator), str(target_config)], check=True)

        for script in ('Install-Internal-EFI.command', 'Prepare-Standalone-Shell.command', 'Restore-USB-Boot.command'):
            shutil.copyfile(ROOT / 'scripts' / script, destination / script)
        payload = destination / 'HardDisk-Install'
        lines = [digest(path) + '  ' + path.relative_to(payload).as_posix()
                 for path in sorted((payload / 'EFI').rglob('*')) if path.is_file()]
        (payload / 'SHA256SUMS').write_text('\n'.join(lines) + '\n', encoding='ascii')
        print('EFI built and validated:', destination)
        print('Recovery image is NOT included; obtain it separately using macrecovery.')
        if not identity:
            print('SMBIOS is still a template. Generate your own identifiers before booting.')


if __name__ == '__main__':
    main()
