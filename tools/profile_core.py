"""Alternate current/baseline DLL workloads; verify results against HotSpot 25."""
import argparse
import ctypes as C
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tests'))
import test_vm as api

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', required=True, type=Path)
parser.add_argument('--rounds', type=int, default=15)
args = parser.parse_args(api.remaining)
baseline = C.CDLL(str(args.baseline.resolve()))
for name, function in vars(api.LIB).items():
    if name.startswith('jbv_') and hasattr(baseline, name):
        entry = getattr(baseline, name)
        entry.argtypes, entry.restype = function.argtypes, function.restype
libraries = {'current': api.LIB, 'baseline': baseline}
workloads = [('integers', 500000), ('arrays', 200000), ('wide', 200000), ('calls', 30000)]
oracle = subprocess.run([str(api.JAVA), '-cp', str(api.CLASSES), 'Oracle'],
    input=''.join(f'CoreBench#{method} {n}\n' for method, n in workloads),
    capture_output=True, text=True, check=True, timeout=30)
expected = [int(x) for x in oracle.stdout.splitlines()]
assert len(expected) == len(workloads)
vms, samples = {}, {name: {method: [] for method, _ in workloads} for name in libraries}
try:
    for name, lib in libraries.items():
        api.LIB = lib
        vm = vms[name] = api.VM()
        assert vm.status == api.OK
        for path in sorted(api.CLASSES.glob('CoreBench*.class')):
            assert vm.load(path.read_bytes()) == api.OK
    for round_index in range(args.rounds + 3):
        order = list(libraries) if round_index % 2 else list(reversed(libraries))
        for (method, n), answer in zip(workloads, expected):
            for name in order:
                api.LIB = libraries[name]
                start = time.perf_counter_ns()
                result = vms[name].call(method, n, owner='CoreBench')
                elapsed = (time.perf_counter_ns() - start) / 1e6
                assert result == (api.OK, answer), (name, method, result, answer)
                if round_index >= 3:
                    samples[name][method].append(elapsed)
finally:
    for name, vm in vms.items():
        api.LIB = libraries[name]
        vm.close()
report = {
    'architecture': api.options.arch,
    'baseline': str(args.baseline.resolve()),
    'current': str(api.BUILD / 'Release/jbytevm.dll'),
    'baseline_sha256': hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
    'current_sha256': hashlib.sha256((api.BUILD / 'Release/jbytevm.dll').read_bytes()).hexdigest(),
    'workloads': {method: {
        'iterations': n, 'hotspot_result': answer,
        **{name + '_median_ms': statistics.median(samples[name][method]) for name in libraries},
        'current_over_baseline': statistics.median(samples['current'][method]) / statistics.median(samples['baseline'][method]),
        'samples_ms': {name: samples[name][method] for name in libraries},
    } for (method, n), answer in zip(workloads, expected)},
}
(api.BUILD / 'core-profile.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({method: {k: v for k, v in data.items() if k != 'samples_ms'}
                  for method, data in report['workloads'].items()}, indent=2))
