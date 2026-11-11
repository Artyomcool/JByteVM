"""Real compiled x86 typed native functions, registration, GC and nested errors."""
import ctypes as C
import struct
import unittest
import test_vm as api
from test_vm import VM, LIB, BUILD, CLASSES, OK, BAD_ARG, MISSING, LINKAGE, UNSUPPORTED, LIMIT, BUSY, BAD_REF
from test_native import Method, U64, I32


class Entry(C.Structure):
    _fields_ = [('name', C.c_char_p), ('descriptor', C.c_char_p), ('function', C.c_void_p)]


class Value(C.Union):
    _fields_ = [('i', I32), ('j', C.c_int64), ('f', C.c_float), ('d', C.c_double), ('ref', I32), ('bits', U64)]


FIXTURE = C.CDLL(str(BUILD / 'Release/jbytevm-typed-fixture.dll'))
FIXTURE.typed_install.argtypes = [C.c_void_p, C.c_void_p]
FIXTURE.typed_install_inner.argtypes = [C.c_void_p, C.c_void_p]
FIXTURE.typed_install_max.argtypes = [C.c_void_p]
FIXTURE.typed_address.argtypes = [I32]
FIXTURE.typed_address.restype = C.c_void_p
LIB.jbv_register_natives.argtypes = [C.c_void_p, C.c_char_p, C.POINTER(Entry), C.c_uint32, C.c_void_p]
LIB.jbv_native_context.argtypes = [C.c_void_p]
LIB.jbv_native_context.restype = C.c_void_p
LIB.jbv_native_fail.argtypes = [C.c_void_p, C.c_int]
LIB.jbv_call_slots.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p, C.c_char_p, C.POINTER(I32), C.c_uint16, C.POINTER(U64)]
LIB.jbv_invoke_args.argtypes = [C.c_void_p, C.POINTER(Method), C.POINTER(Value)]


def words(bits):
    return [bits & 0xffffffff, (bits >> 32) & 0xffffffff]


def fp(value, wide=False):
    return struct.unpack('<Q' if wide else '<I', struct.pack('<d' if wide else '<f', value))[0]


class TypedTests(unittest.TestCase):
    def prepare(self, user=0x1234, **kwargs):
        vm = VM(**kwargs)
        self.addCleanup(vm.close)
        self.assertEqual(vm.status, OK)
        for p in sorted(CLASSES.glob('Typed*.class')):
            self.assertEqual(vm.load(p.read_bytes()), OK)
        self.assertEqual(FIXTURE.typed_install(vm.handle, user), OK)
        self.assertEqual(FIXTURE.typed_install_inner(vm.handle, 0x5678), OK)
        self.assertEqual(FIXTURE.typed_install_max(vm.handle), OK)
        return vm

    def call(self, vm, name, descriptor, args=(), owner='TypedNatives'):
        out = U64(0x123456789abcdef0)
        status = LIB.jbv_call_slots(vm.handle, owner.encode(), name.encode(), descriptor.encode(),
                                    (I32 * len(args))(*args), len(args), C.byref(out))
        return status, out.value

    def register(self, vm, entries):
        table = (Entry * len(entries))(*entries)
        return LIB.jbv_register_natives(vm.handle, b'TypedNatives', table, len(entries), None)

    def test_primitives_overloads_and_x87_results(self):
        vm = self.prepare()
        cases = [('invert', '(Z)Z', [0], 1), ('invert', '(Z)Z', [1], 0),
                 ('byteValue', '(B)B', [-128], 0xffffff80), ('byteValue', '(B)B', [127], 127),
                 ('charValue', '(C)C', [65535], 65535), ('shortValue', '(S)S', [-32768], 0xffff8000),
                 ('add', '(II)I', [0x7fffffff, 1], 0x80000000),
                 ('add', '(JJ)J', words(0x123456789abcdef0) + words(-17), 0x123456789abcdeDF),
                 ('add', '(JJ)J', words(0x7fffffffffffffff) + words(1), 0x8000000000000000),
                 ('floatValue', '(F)F', [fp(2.5)], fp(2.75)),
                 ('doubleValue', '(D)D', words(fp(3.25, True)), fp(3.75, True)),
                 ('nothing', '()V', [], 0), ('context', '()I', [], 0x1234)]
        for name, descriptor, args, expected in cases:
            with self.subTest(name=name, descriptor=descriptor):
                self.assertEqual(self.call(vm, name, descriptor, args), (OK, expected))
        # Repeated float/double results must pop ST(0), preserving the x87 stack.
        for _ in range(1000):
            self.assertEqual(self.call(vm, 'floatValue', '(F)F', [fp(-2.5)]), (OK, fp(-2.25)))
            self.assertEqual(self.call(vm, 'doubleValue', '(D)D', words(fp(-3.25, True))), (OK, fp(-2.75, True)))
        for i, bits in enumerate([0x80000000, 0x7f800000, 0x7fc12345]):
            self.assertEqual(self.call(vm, 'specialFloat', '(I)F', [i]), (OK, bits))
        for i, bits in enumerate([0x8000000000000000, 0x7ff0000000000000, 0x7ff8123456789abc]):
            self.assertEqual(self.call(vm, 'specialDouble', '(I)D', [i]), (OK, bits))
        self.assertEqual(self.call(vm, 'nativeLoop', '(I)I', [10000]), (OK, sum(range(10000)) + 70000))

    def test_mixed_signature_references_and_gc(self):
        vm = self.prepare()
        array = I32()
        self.assertEqual(LIB.jbv_new_array(vm.handle, b'[I', 1, C.byref(array)), OK)
        ref = array.value
        # Remove the host pin: the typed callback's arguments must protect it.
        self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)
        slots = [-13] + words(0x1234000000000000) + [fp(2.5)] + words(fp(-3.25, True)) + [ref, -5, 60000, -1000, 1]
        expected = 0x1234000000000000 - 13 + 2 - 3 + 100 - 5 + 60000 - 1000 + 1
        self.assertEqual(self.call(vm, 'mixed', '(IJFDLjava/lang/Object;BCSZ)J', slots), (OK, expected))
        self.assertEqual(self.call(vm, 'identity', '(Ljava/lang/Object;)Ljava/lang/Object;', [ref]), (OK, ref))
        self.assertEqual(self.call(vm, 'array', '([I)[I', [ref]), (OK, ref))
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 1)
        self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)
        self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 0)
        self.assertEqual(self.call(vm, 'badReference', '()Ljava/lang/Object;')[0], BAD_REF)

    def test_table_validation_is_atomic_and_legacy_rebinding_clears_kind(self):
        vm = self.prepare()
        subtract = FIXTURE.typed_address(-1)
        good = Entry(b'add', b'(II)I', subtract)
        invalid = [(Entry(b'missing', b'()I', subtract), MISSING),
                   (Entry(b'add', b'(I)I', subtract), MISSING),
                   (Entry(b'instance', b'()I', subtract), UNSUPPORTED),
                   (Entry(b'ordinary', b'(I)I', subtract), LINKAGE),
                   (Entry(b'add', b'(II)I', None), BAD_ARG),
                   (Entry(None, b'()I', subtract), BAD_ARG),
                   (good, BAD_ARG)]
        for bad, expected in invalid:
            self.assertEqual(self.register(vm, [good, bad]), expected)
            self.assertEqual(self.call(vm, 'add', '(II)I', [9, 4]), (OK, 13))
        self.assertEqual(self.register(vm, [good]), OK)
        self.assertEqual(self.call(vm, 'add', '(II)I', [9, 4]), (OK, 5))
        def old(handle, user, args, count, result):
            result[0] = 77
            return OK
        self.assertEqual(vm.bind('add', old, 'TypedNatives', '(II)I'), OK)
        self.assertEqual(self.call(vm, 'add', '(II)I', [9, 4]), (OK, 77))
        self.assertEqual(FIXTURE.typed_install(vm.handle, 0x1234), OK)
        self.assertEqual(self.call(vm, 'add', '(II)I', [9, 4]), (OK, 13))
        self.assertEqual(self.call(vm, 'rebind', '()I'), (OK, BUSY))
        self.assertEqual(self.call(vm, 'add', '(II)I', [9, 4]), (OK, 13))

    def test_nested_context_errors_and_exception_propagation(self):
        vm = self.prepare()
        self.assertIsNone(LIB.jbv_native_context(vm.handle))
        self.assertEqual(LIB.jbv_native_fail(vm.handle, LIMIT), BAD_ARG)
        self.assertEqual(self.call(vm, 'outer', '(Z)I', [0])[0], LIMIT)
        self.assertIsNone(LIB.jbv_native_context(vm.handle))
        self.assertEqual(self.call(vm, 'outer', '(Z)I', [1]), (OK, 0x1234 ^ 0x5678))
        self.assertEqual(self.call(vm, 'caught', '()I'), (OK, 42))
        self.assertEqual(self.call(vm, 'caughtStatus', '()I'), (OK, 43))
        self.assertEqual(self.call(vm, 'context', '()I'), (OK, 0x1234))
        second = self.prepare(user=0x2345)
        self.assertEqual(self.call(second, 'context', '()I'), (OK, 0x2345))
        self.assertEqual(self.call(vm, 'context', '()I'), (OK, 0x1234))

    def test_typed_reentry_shares_instruction_and_depth_limits(self):
        for kwargs in ({'depth': 8}, {'instructions': 40}):
            vm = self.prepare(**kwargs)
            self.assertEqual(self.call(vm, 'recurse', '(I)I', [100])[0], LIMIT)
            self.assertEqual(self.call(vm, 'recurse', '(I)I', [0]), (OK, 7))
            self.assertIsNone(LIB.jbv_native_context(vm.handle))

    def test_c_convenience_calls_and_maximum_slot_count(self):
        vm = self.prepare()
        self.assertEqual(self.call(vm, 'invokeConvenience', '()I'), (OK, 42))
        args = [(-1 if i % 3 == 0 else i * 17) for i in range(255)]
        expected = sum(a * (i + 1) for i, a in enumerate(args)) & 0xffffffff
        self.assertEqual(self.call(vm, 'maxArgs', '(' + 'I' * 255 + ')I', args, 'TypedMax'), (OK, expected))
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 0)
        method = Method()
        self.assertEqual(LIB.jbv_resolve_method(vm.handle, b'TypedMax', b'maxArgs', ('(' + 'I' * 255 + ')I').encode(), C.byref(method)), OK)
        out = Value()
        self.assertEqual(LIB.jbv_invoke_args(vm.handle, C.byref(method), C.byref(out), *[I32(a) for a in args]), OK)
        self.assertEqual(out.bits, expected)


if __name__ == '__main__':
    unittest.main(argv=[__file__] + api.remaining, verbosity=2)
