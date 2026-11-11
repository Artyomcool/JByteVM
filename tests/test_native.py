"""Native bridge: cached IDs, dispatch, data access, rooting and exceptions."""
import ctypes as C
import struct
import unittest
import test_vm as api
from test_vm import VM, LIB, CLASSES, OK, BAD_ARG, OOM, MISSING, NULL, BOUNDS, NEGATIVE_SIZE, ARRAY_STORE, CLASS_CAST, BAD_REF


class Method(C.Structure):
    _fields_ = [('owner', C.c_void_p), ('method', C.c_void_p)]


class Field(C.Structure):
    _fields_ = [('owner', C.c_void_p), ('field', C.c_void_p)]


U64 = C.c_uint64
I32 = C.c_int32
WIDE = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_void_p, C.POINTER(I32), C.c_uint16, C.POINTER(U64))
LIB.jbv_resolve_method.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p, C.c_char_p, C.POINTER(Method)]
LIB.jbv_invoke.argtypes = [C.c_void_p, C.POINTER(Method), C.POINTER(I32), C.c_uint16, C.POINTER(U64)]
LIB.jbv_resolve_field.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p, C.c_char_p, C.POINTER(Field)]
LIB.jbv_get_field.argtypes = [C.c_void_p, C.POINTER(Field), I32, C.POINTER(U64)]
LIB.jbv_set_field.argtypes = [C.c_void_p, C.POINTER(Field), I32, U64]
LIB.jbv_alloc_object.argtypes = [C.c_void_p, C.c_char_p, C.POINTER(I32)]
LIB.jbv_new_array.argtypes = [C.c_void_p, C.c_char_p, I32, C.POINTER(I32)]
LIB.jbv_array_info.argtypes = [C.c_void_p, I32, C.POINTER(C.c_uint32), C.POINTER(C.c_char)]
LIB.jbv_array_read.argtypes = [C.c_void_p, I32, C.c_uint32, C.c_uint32, C.POINTER(U64)]
LIB.jbv_array_write.argtypes = LIB.jbv_array_read.argtypes
LIB.jbv_throw.argtypes = [C.c_void_p, I32]
LIB.jbv_clear_exception.argtypes = [C.c_void_p]
LIB.jbv_exception.argtypes = [C.c_void_p, C.POINTER(I32)]
LIB.jbv_bind_native_slots.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p, C.c_char_p, WIDE, C.c_void_p]


class NativeTests(unittest.TestCase):
    def prepare(self, **kwargs):
        vm = VM(**kwargs)
        self.addCleanup(vm.close)
        self.assertEqual(vm.status, OK)
        for p in sorted(CLASSES.glob('NativeBridge*.class')):
            self.assertEqual(vm.load(p.read_bytes()), OK)
        return vm

    def method(self, vm, name, descriptor, owner='NativeBridge'):
        result = Method()
        self.assertEqual(LIB.jbv_resolve_method(vm.handle, owner.encode(), name.encode(), descriptor.encode(), C.byref(result)), OK)
        return result

    def field(self, vm, name, descriptor, owner='NativeBridge$Base'):
        result = Field()
        self.assertEqual(LIB.jbv_resolve_field(vm.handle, owner.encode(), name.encode(), descriptor.encode(), C.byref(result)), OK)
        return result

    def invoke(self, vm, method, *args):
        result = U64(0xabcdef)
        status = LIB.jbv_invoke(vm.handle, C.byref(method), (I32 * len(args))(*args), len(args), C.byref(result))
        return status, result.value

    def new(self, vm, owner):
        result = I32()
        self.assertEqual(LIB.jbv_alloc_object(vm.handle, owner.encode(), C.byref(result)), OK)
        return result.value

    def array(self, vm, descriptor, length):
        result = I32()
        self.assertEqual(LIB.jbv_new_array(vm.handle, descriptor.encode(), length, C.byref(result)), OK)
        return result.value

    def write(self, vm, array, values, start=0):
        return LIB.jbv_array_write(vm.handle, array, start, len(values), (U64 * len(values))(*values))

    def read(self, vm, array, count, start=0):
        values = (U64 * count)(*([0xabcdef] * count))
        status = LIB.jbv_array_read(vm.handle, array, start, count, values)
        return status, list(values)

    def test_cached_methods_and_static_native_only(self):
        vm = self.prepare()
        child = self.new(vm, 'NativeBridge$Child')
        init = self.method(vm, '<init>', '(I)V', 'NativeBridge$Child')
        self.assertEqual(self.invoke(vm, init, child, 7), (OK, 0))
        method = self.method(vm, 'apply', '(I)I', 'NativeBridge$Op')
        self.assertEqual(self.invoke(vm, method, child, 3), (OK, 110))
        private = self.method(vm, 'secret', '(I)I', 'NativeBridge$Base')
        self.assertEqual(self.invoke(vm, private, child, 3), (OK, 4))
        calls = []
        def native(handle, user, args, count, result):
            calls.append((args[0], args[1], count))
            status = LIB.jbv_collect(handle)
            if status != OK:
                return status
            status, value = self.invoke(vm, method, args[0], args[1])
            result[0] = value
            return status
        self.assertEqual(vm.bind('nativeInstance', native, 'NativeBridge$Base', '(I)I'), api.UNSUPPORTED)
        rejected = WIDE(lambda handle, user, args, count, result: OK)
        self.assertEqual(LIB.jbv_bind_native_slots(vm.handle, b'NativeBridge$Base', b'nativeInstance', b'(I)I', rejected, None), api.UNSUPPORTED)
        self.assertEqual(calls, [])
        self.assertEqual(vm.bind('nativeCall', native, 'NativeBridge', '(LNativeBridge$Base;I)I'), OK)
        call = self.method(vm, 'callNative', '(LNativeBridge$Base;I)I')
        for n in range(100):
            self.assertEqual(self.invoke(vm, call, child, n), (OK, 107 + n))
        self.assertEqual(len(calls), 100)
        self.assertEqual(calls[-1], (child, 99, 2))
        self.assertEqual(self.invoke(vm, method, 0, 1), (NULL, 0xabcdef))
        self.assertEqual(self.invoke(vm, method, child), (BAD_ARG, 0xabcdef))
        other = self.new(vm, 'NativeBridge$Other')
        self.assertEqual(self.invoke(vm, method, other, 1)[0], CLASS_CAST)
        self.assertEqual(LIB.jbv_release(vm.handle, child), OK)
        self.assertEqual(LIB.jbv_release(vm.handle, other), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 0)
        self.assertEqual(self.invoke(vm, method, child, 1)[0], BAD_REF)

    def test_fields_raw_bits_reference_ownership_and_static_initialization(self):
        vm = self.prepare()
        obj = self.new(vm, 'NativeBridge$Base')
        fields = [(self.field(vm, 'value', 'I'), 37),
                  (self.field(vm, 'wide', 'J'), 0x1234567800000005),
                  (self.field(vm, 'real', 'D'), struct.unpack('<Q', struct.pack('<d', -13.25))[0])]
        for field, bits in fields:
            self.assertEqual(LIB.jbv_set_field(vm.handle, C.byref(field), obj, bits), OK)
            out = U64()
            self.assertEqual(LIB.jbv_get_field(vm.handle, C.byref(field), obj, C.byref(out)), OK)
            self.assertEqual(out.value, bits)
        total = self.method(vm, 'fields', '(LNativeBridge$Base;)J')
        self.assertEqual(self.invoke(vm, total, obj), (OK, 0x123456780000001d))
        link = self.field(vm, 'link', 'Ljava/lang/Object;')
        shared = self.field(vm, 'shared', 'I')
        self.assertEqual(LIB.jbv_set_field(vm.handle, C.byref(shared), 0, 51), OK)
        self.assertEqual(LIB.jbv_set_field(vm.handle, C.byref(shared), obj, 0), BAD_ARG)
        child = self.new(vm, 'NativeBridge$Child')
        self.assertEqual(LIB.jbv_set_field(vm.handle, C.byref(link), obj, child), OK)
        self.assertEqual(LIB.jbv_release(vm.handle, child), OK)
        held = U64()
        self.assertEqual(LIB.jbv_get_field(vm.handle, C.byref(link), obj, C.byref(held)), OK)
        self.assertEqual(LIB.jbv_set_field(vm.handle, C.byref(link), obj, 0), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 2)
        self.assertEqual(LIB.jbv_release(vm.handle, held.value), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 1)
        self.assertEqual(LIB.jbv_set_field(vm.handle, C.byref(link), obj, child), BAD_REF)
        peer = self.field(vm, 'peer', 'LNativeBridge$Base;')
        other = self.new(vm, 'NativeBridge$Other')
        self.assertEqual(LIB.jbv_set_field(vm.handle, C.byref(peer), obj, other), CLASS_CAST)
        unchanged = U64(123)
        self.assertEqual(LIB.jbv_get_field(vm.handle, C.byref(link), other, C.byref(unchanged)), CLASS_CAST)
        self.assertEqual(unchanged.value, 123)
        self.assertEqual(LIB.jbv_release(vm.handle, other), OK)
        # Init.<clinit> collects: the stored value must be pinned before it runs.
        seen = []
        def checkpoint(handle, user, args, count, result):
            status = LIB.jbv_collect(handle)
            seen.append(vm.stats().objects)
            result[0] = 1
            return status
        self.assertEqual(vm.bind('checkpoint', checkpoint, 'NativeBridge', '()I'), OK)
        slot = self.field(vm, 'slot', 'Ljava/lang/Object;', 'NativeBridge$Init')
        self.assertEqual(LIB.jbv_release(vm.handle, obj), OK)
        self.assertEqual(LIB.jbv_set_field(vm.handle, C.byref(slot), 0, obj), OK)
        self.assertEqual(seen, [1])
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 1)
        self.assertEqual(LIB.jbv_set_field(vm.handle, C.byref(slot), 0, 0), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 0)

    def test_all_primitive_arrays_and_checked_ranges(self):
        vm = self.prepare()
        cases = [('Z', [2, 3], [0, 1]), ('B', [255, 128], [0xffffffff, 0xffffff80]),
                 ('C', [0x12345, 0xffffffff], [0x2345, 65535]), ('S', [65535, 32768], [0xffffffff, 0xffff8000]),
                 ('I', [0x80000000, 0xffffffff], [0x80000000, 0xffffffff]),
                 ('J', [0x123456789abcdef0, 0xffffffffffffffff], [0x123456789abcdef0, 0xffffffffffffffff]),
                 ('F', [0x80000000, 0x7fc12345], [0x80000000, 0x7fc12345]),
                 ('D', [0x8000000000000000, 0x7ff8123456789abc], [0x8000000000000000, 0x7ff8123456789abc])]
        for kind, values, expected in cases:
            with self.subTest(kind=kind):
                array = self.array(vm, '[' + kind, 2)
                length, actual = C.c_uint32(), C.c_char()
                self.assertEqual(LIB.jbv_array_info(vm.handle, array, C.byref(length), C.byref(actual)), OK)
                self.assertEqual((length.value, actual.value), (2, kind.encode()))
                self.assertEqual(self.write(vm, array, values), OK)
                self.assertEqual(self.read(vm, array, 2), (OK, expected))
                self.assertEqual(self.read(vm, array, 2, 1), (BOUNDS, [0xabcdef] * 2))
                self.assertEqual(self.write(vm, array, [77], 0xffffffff), BOUNDS)
                self.assertEqual(LIB.jbv_array_write(vm.handle, array, 2, 0, None), OK)
                self.assertEqual(LIB.jbv_array_read(vm.handle, array, 2, 0, None), OK)
                self.assertEqual(LIB.jbv_release(vm.handle, array), OK)
        array = self.array(vm, '[I', 3)
        self.assertEqual(self.write(vm, array, [17, 20, 5]), OK)
        method = self.method(vm, 'elements', '([I)I')
        self.assertEqual(self.invoke(vm, method, array), (OK, 42))
        self.assertEqual(LIB.jbv_release(vm.handle, array), OK)
        out = I32(123)
        self.assertEqual(LIB.jbv_new_array(vm.handle, b'[I', -1, C.byref(out)), NEGATIVE_SIZE)
        self.assertEqual(out.value, 123)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 0)

    def test_reference_arrays_atomic_writes_retained_reads_and_covariance(self):
        vm = self.prepare()
        array = self.array(vm, '[LNativeBridge$Base;', 2)
        child = self.new(vm, 'NativeBridge$Child')
        other = self.new(vm, 'NativeBridge$Other')
        self.assertEqual(self.write(vm, array, [child, other]), ARRAY_STORE)
        self.assertEqual(self.read(vm, array, 2), (OK, [0, 0]))
        self.assertEqual(self.write(vm, array, [child, child]), OK)
        self.assertEqual(LIB.jbv_release(vm.handle, child), OK)
        self.assertEqual(self.read(vm, array, 2), (OK, [child, child]))
        self.assertEqual(self.write(vm, array, [0, 0]), OK)
        self.assertEqual(LIB.jbv_release(vm.handle, child), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 3)  # one returned occurrence still owns it
        self.assertEqual(LIB.jbv_release(vm.handle, child), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 2)
        self.assertEqual(self.write(vm, array, [child, 0]), BAD_REF)
        nested = self.array(vm, '[[I', 1)
        ints = self.array(vm, '[I', 0)
        self.assertEqual(self.write(vm, nested, [ints]), OK)
        self.assertEqual(self.write(vm, nested, [array]), ARRAY_STORE)
        for ref in (array, other, nested, ints):
            self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 0)

    def test_throw_clear_and_reference_return_across_native_reentry(self):
        vm = self.prepare()
        init = self.method(vm, '<init>', '()V', 'java/lang/IllegalArgumentException')
        def throw(handle, user, args, count, result):
            ref = self.new(vm, 'java/lang/IllegalArgumentException')
            status, _ = self.invoke(vm, init, ref)
            if status == OK:
                status = LIB.jbv_throw(handle, ref)
            LIB.jbv_release(handle, ref)
            LIB.jbv_collect(handle)
            return status
        self.assertEqual(vm.bind('throwNative', throw, 'NativeBridge', '(I)V'), OK)
        self.assertEqual(vm.call('caught', 1, owner='NativeBridge'), (OK, 42))
        self.assertEqual(vm.call('explode', 0, owner='NativeBridge')[0], 22)
        exception = I32()
        self.assertEqual(LIB.jbv_exception(vm.handle, C.byref(exception)), OK)
        self.assertGreater(exception.value, 0)
        self.assertEqual(LIB.jbv_clear_exception(vm.handle), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        # The retained exception also owns its stack-trace object graph.
        self.assertGreaterEqual(vm.stats().objects, 1)
        self.assertEqual(LIB.jbv_release(vm.handle, exception.value), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 0)
        make = self.method(vm, 'make', '(I)LNativeBridge$Base;')
        def factory(handle, user, args, count, result):
            status, ref = self.invoke(vm, make, args[0])
            if status == OK:
                result[0] = ref
                status = LIB.jbv_release(handle, ref)
            return status
        self.assertEqual(vm.bind('nativeFactory', factory, 'NativeBridge', '(I)LNativeBridge$Base;'), OK)
        status, ref = vm.call('factory', 12, owner='NativeBridge', descriptor='(I)LNativeBridge$Base;')
        self.assertEqual(status, OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 1)
        apply = self.method(vm, 'apply', '(I)I', 'NativeBridge$Base')
        self.assertEqual(self.invoke(vm, apply, ref, 1), (OK, 113))
        self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 0)

    def test_cached_reentry_shares_limits_and_recovers(self):
        for settings in ({'depth': 8}, {'instructions': 40}):
            vm = self.prepare(**settings)
            method = self.method(vm, 'recurse', '(I)I')
            def again(handle, user, args, count, result):
                status, value = self.invoke(vm, method, args[0])
                if status == OK:
                    result[0] = value
                return status
            self.assertEqual(vm.bind('again', again, 'NativeBridge', '(I)I'), OK)
            self.assertEqual(self.invoke(vm, method, 100), (api.LIMIT, 0xabcdef))
            self.assertEqual(self.invoke(vm, method, 0), (OK, 7))

    def test_allocation_failure_and_bad_host_arguments(self):
        vm = self.prepare()
        method = Method(123, 456)
        self.assertEqual(LIB.jbv_resolve_method(vm.handle, b'NativeBridge', b'absent', b'()I', C.byref(method)), MISSING)
        self.assertEqual((method.owner, method.method), (123, 456))
        self.assertEqual(LIB.jbv_resolve_method(vm.handle, b'NativeBridge', b'<clinit>', b'()V', C.byref(method)), api.UNSUPPORTED)
        self.assertEqual(LIB.jbv_invoke(vm.handle, C.byref(Method()), None, 0, C.byref(U64())), BAD_ARG)
        out = I32(123)
        self.assertEqual(LIB.jbv_alloc_object(vm.handle, b'[I', C.byref(out)), BAD_ARG)
        self.assertEqual(LIB.jbv_new_array(vm.handle, b'[Q', 1, C.byref(out)), api.BAD_CLASS)
        self.assertEqual(out.value, 123)
        obj = self.new(vm, 'NativeBridge$Other')
        self.assertEqual(LIB.jbv_throw(vm.handle, obj), CLASS_CAST)
        self.assertEqual(LIB.jbv_throw(vm.handle, 0), NULL)
        self.assertEqual(LIB.jbv_array_info(vm.handle, obj, C.byref(C.c_uint32()), None), BAD_ARG)
        self.assertEqual(LIB.jbv_release(vm.handle, obj), OK)
        # Preload metadata so failure is in the array/object allocation path.
        array = self.array(vm, '[J', 0)
        self.assertEqual(LIB.jbv_release(vm.handle, array), OK)
        # Small objects come from already allocated heap chunks; a large one needs the host.
        vm.fail_after = vm.allocations
        self.assertEqual(LIB.jbv_new_array(vm.handle, b'[J', 100, C.byref(out)), OOM)
        self.assertEqual(out.value, 123)
        vm.fail_after = None
        array = self.array(vm, '[J', 100)
        self.assertEqual(LIB.jbv_release(vm.handle, array), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(vm.stats().objects, 0)


if __name__ == '__main__':
    unittest.main(argv=[__file__] + api.remaining, verbosity=2)
