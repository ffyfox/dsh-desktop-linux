#!/usr/bin/env python3
"""Check package hashes and both patch consumers without touching the source checkout.

Uses the pinned commit from an existing upstream Git checkout. Optional
--reference compares every patched file against a separately built source tree.
No application, user profile, compositor or network connection is opened.
"""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT/'upstream')
    parser.add_argument('--reference', type=Path)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    reference = args.reference.resolve(strict=True) if args.reference else None
    # PKGBUILD is part of this trusted repository, not an application-supplied path.
    entries = subprocess.check_output([
        'bash', '-c',
        'source "$1"; printf "%s\\n" "$_commit"; for i in "${!source[@]}"; do '
        'printf "%s\\t%s\\n" "${source[$i]}" "${sha256sums[$i]}"; done',
        '_', str(ROOT/'PKGBUILD'),
    ], text=True).splitlines()
    commit, package_entries = entries[0], entries[2:]
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('PKGBUILD must pin a complete upstream commit')
    patches = sorted((ROOT/'patches').glob('*.patch'))
    listed = []
    for entry in package_entries:
        name, expected = entry.split('\t')
        if Path(name).name != name:
            raise ValueError('Local package sources must use basenames')
        path = ROOT/('patches' if name.endswith('.patch') else 'assets')/name
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Package checksum mismatch: '+name)
        if name.endswith('.patch'):
            listed.append(name)
    if listed != [patch.name for patch in patches]:
        raise ValueError('PKGBUILD patch order differs from patches/')
    files = set()
    for patch in patches:
        files.update(re.findall(r'^\+\+\+ b/(.+)$', patch.read_text(), re.MULTILINE))
    with tempfile.TemporaryDirectory(prefix='dsh-patch-check-') as temporary:
        temporary = Path(temporary)
        archive = temporary/'upstream.tar'
        with archive.open('wb') as output:
            subprocess.run(['git', '-C', str(source), 'archive', commit], stdout=output, check=True)
        for mode in ['git', 'gnu']:
            tree = temporary/mode
            tree.mkdir()
            with tarfile.open(archive) as upstream:
                upstream.extractall(tree, filter='data')
            for patch in patches:
                command = ['git', 'apply', str(patch)] if mode == 'git' else ['patch', '--batch', '-Np1', '-i', str(patch)]
                result = subprocess.run(command, cwd=tree, capture_output=True, text=True)
                if result.returncode:
                    raise RuntimeError(mode+' failed on '+patch.name+'\n'+result.stdout+result.stderr)
            if reference:
                for name in sorted(files):
                    if (tree/name).read_bytes() != (reference/name).read_bytes():
                        raise ValueError(mode+' differs from reference: '+name)
            print(f'{mode}: {len(patches)} patches applied'+(f'; {len(files)} reference files match' if reference else ''))
    print(f'{len(package_entries)} local package source checksums verified')


if __name__ == '__main__':
    main()
