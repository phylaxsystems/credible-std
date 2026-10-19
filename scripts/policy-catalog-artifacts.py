#!/usr/bin/env python3
"""Refresh or verify policy manifest artifacts after a policy-library build."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()

for path in sorted((ROOT / 'policy-catalog/policies').glob('*/metadata.json')):
    manifest = json.loads(path.read_text())
    compiled_artifact = None
    for binding in manifest['bindings']:
        candidates = []
        for candidate in (ROOT / 'policy-catalog/out').rglob(binding['contractName'] + '.json'):
            artifact = json.loads(candidate.read_text())
            target = artifact.get('metadata', {}).get('settings', {}).get('compilationTarget', {})
            if binding['sourceFile'] in target:
                candidates.append((candidate, artifact))
        if len(candidates) != 1:
            raise AssertionError(f'{path}: expected one artifact for {binding["contractName"]}, found {len(candidates)}')
        _, artifact = candidates[0]
        compiled_artifact = artifact
        bytecode = artifact['bytecode']['object'].lower()
        expected_bytecode_file = f"policy-catalog/policies/{manifest['template']['slug']}/bytecode.bin"
        expected = {
            'constructorAbi': [entry for entry in artifact['abi'] if entry['type'] == 'constructor'],
            'baseBytecode': bytecode,
            'compilerVersion': 'v' + artifact['metadata']['compiler']['version'],
            'evmVersion': artifact['metadata']['settings']['evmVersion'],
            'optimizerRuns': artifact['metadata']['settings']['optimizer']['runs'],
            'libraries': artifact['metadata']['settings']['libraries'],
        }
        functions = {entry.get('name') for entry in artifact['abi'] if entry['type'] == 'function'}
        assert set(binding['expectedAssertionSpec']['assertionFunctions']) <= functions, path
        bytecode_path = ROOT / expected_bytecode_file
        if args.check:
            assert binding.get('bytecodeFile') == expected_bytecode_file, f'{path}: stale bytecodeFile'
            assert bytecode_path.is_file(), f'{path}: missing {expected_bytecode_file}'
            assert bytecode_path.read_text().strip().lower() == bytecode, f'{path}: stale bytecode file'
        else:
            binding['bytecodeFile'] = expected_bytecode_file
            bytecode_path.write_text(f'{bytecode}\n')
        if args.check:
            for key, value in expected.items():
                assert binding[key] == value, f'{path}: stale {key}'
        else:
            binding.update(expected)
    if compiled_artifact is None:
        raise AssertionError(f'{path}: manifest has no compiled bindings')
    settings = dict(compiled_artifact['metadata']['settings'])
    settings.pop('compilationTarget', None)
    compiler_metadata = {
        'solcVersion': compiled_artifact['metadata']['compiler']['version'].split('+')[0],
        'fullVersion': 'v' + compiled_artifact['metadata']['compiler']['version'],
        'settings': settings,
    }
    if args.check:
        assert manifest['version']['compilerMetadata'] == compiler_metadata, f'{path}: stale compiler settings'
    else:
        manifest['version']['compilerMetadata'] = compiler_metadata
    if not args.check:
        path.write_text(json.dumps(manifest, indent=2) + '\n')
print('Policy artifacts match compiled constructor ABIs and bytecode.' if args.check else 'Updated policy artifacts.')
