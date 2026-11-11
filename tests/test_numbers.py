"""Bit-exact numeric/slot/array checks against Java 25 HotSpot."""
import ctypes as C
import random
import subprocess
import unittest
from test_vm import VM, LIB, JAVA, CLASSES, remaining, OK

MASK = (1 << 64) - 1
LIB.jbv_call_slots.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p, C.c_char_p, C.POINTER(C.c_int32), C.c_uint16, C.POINTER(C.c_uint64)]
NATIVE_SLOTS = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_void_p, C.POINTER(C.c_int32), C.c_uint16, C.POINTER(C.c_uint64))
LIB.jbv_bind_native_slots.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p, C.c_char_p, NATIVE_SLOTS, C.c_void_p]

def call(vm, name, descriptor, *values):
    slots = []
    for kind, value in zip(descriptor[1:descriptor.index(')')], values):
        slots.append(value & 0xffffffff)
        if kind in 'JD': slots.append((value >> 32) & 0xffffffff)
    args = (C.c_int32 * len(slots))(*slots)
    result = C.c_uint64(0x1234)
    status = LIB.jbv_call_slots(vm.handle, b'Numbers', name.encode(), descriptor.encode(), args, len(slots), C.byref(result))
    return status, result.value

def nan(bits, kind):
    mask, infinity = (0x7fffffff, 0x7f800000) if kind == 'F' else (0x7fffffffffffffff, 0x7ff0000000000000)
    return bits & mask > infinity

class NumericTests(unittest.TestCase):
    def test_all_numeric_operations_against_hotspot(self):
        rng = random.Random(25069)
        longs = [0, 1, MASK, 1 << 63, (1 << 63)-1, (1 << 53)+1, (1 << 62)+(1 << 38)+1]
        longs += [rng.getrandbits(64) for _ in range(35)]
        ints = [0, 1, 0xffffffff, 0x80000000, 0x7fffffff, 63, 64, 65]
        floats = [0, 0x80000000, 1, 0x7fffff, 0x800000, 0x3f800000, 0xbf800000,
                  0x7f800000, 0xff800000, 0x7fc12345, 0x7f7fffff, 0x5f000000]
        floats += [rng.getrandbits(32) for _ in range(35)]
        doubles = [0, 1 << 63, 1, (1 << 52)-1, 1 << 52, 0x3ff0000000000000, 0xbff0000000000000,
                   0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000012345678, 0x7fefffffffffffff, 0x43e0000000000000]
        doubles += [rng.getrandbits(64) for _ in range(35)]
        cases = []
        for kind, values in (('J', longs), ('F', floats), ('D', doubles)):
            names = ['add', 'sub', 'mul', 'div', 'rem', 'cmp'] + (['and', 'or', 'xor'] if kind == 'J' else [])
            for name in names:
                for a in values:
                    for b in (values[0], values[1], values[5], rng.choice(values)):
                        if kind == 'J' and name in ('div', 'rem') and not b: continue
                        cases.append((name, f'({kind}{kind})' + ('I' if name == 'cmp' else kind), (a, b)))
            cases += [('neg', f'({kind}){kind}', (a,)) for a in values]
        for name in ('shl', 'shr', 'ushr'):
            cases += [(name, '(JI)J', (a, b)) for a in longs for b in ints]
        for source, values in (('I', ints), ('J', longs), ('F', floats), ('D', doubles)):
            for target in 'IJFD':
                if source != target:
                    name = ('l' if source == 'J' else source.lower()) + '2' + ('l' if target == 'J' else target.lower())
                    cases += [(name, f'({source}){target}', (a,)) for a in values]
        cases += [('shape', '(I)J', (n & 0xffffffff,)) for n in (-5, 0, 1, 25)]
        cases += [('catchLong', '(I)I', (n,)) for n in (0, 1, 7)]
        stdin = '\n'.join(' '.join([name, desc, *(format(n & MASK, 'x') for n in args)]) for name, desc, args in cases) + '\n'
        oracle = subprocess.run([str(JAVA), '-cp', str(CLASSES), 'NumericOracle'], input=stdin, text=True, capture_output=True, timeout=30)
        self.assertEqual(oracle.returncode, 0, oracle.stderr)
        expected = [int(n, 16) for n in oracle.stdout.splitlines()]
        self.assertEqual(len(expected), len(cases))
        with VM() as vm:
            self.assertEqual(vm.load_name('Numbers'), OK)
            for (name, desc, args), value in zip(cases, expected):
                status, actual = call(vm, name, desc, *args)
                self.assertEqual(status, OK, (name, desc, args))
                if desc[-1] in 'FD' and nan(value, desc[-1]):
                    self.assertTrue(nan(actual, desc[-1]), (name, desc, args, actual))
                else: self.assertEqual(actual, value, (name, desc, args))
        print(f'Numeric HotSpot cases: {len(cases)}', flush=True)

    def test_wide_native_slots_and_reference_gc(self):
        with VM() as vm:
            self.assertEqual(vm.load_name('Numbers'), OK)
            seen = []
            def bridge(handle, user, args, count, result):
                seen.append((count, args[4]))
                if LIB.jbv_collect(handle) != OK: return 2
                if LIB.jbv_retain(handle, args[4]) != OK: return 17
                LIB.jbv_release(handle, args[4])
                a = (args[0] & 0xffffffff) | ((args[1] & 0xffffffff) << 32)
                status, value = call(vm, 'add', '(JJ)J', a, 5)
                result[0] = value
                return status
            callback = NATIVE_SLOTS(bridge)
            self.assertEqual(LIB.jbv_bind_native_slots(vm.handle, b'Numbers', b'bridge', b'(JDLjava/lang/Object;)J', callback, None), OK)
            self.assertEqual(call(vm, 'nativeChain', '(I)J', 7), (OK, 0x123456789abcdef0 + 12))
            self.assertEqual(seen[0][0], 5)
            self.assertGreater(seen[0][1], 0)

if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining], verbosity=2)
