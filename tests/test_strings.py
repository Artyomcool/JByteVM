"""Object/Class, UTF-16 strings, inline concatenation and native text ownership."""
import ctypes as C
import random
import subprocess
import unittest
import test_vm as api
from test_vm import VM, LIB, CLASSES, OK, BAD_ARG, OOM, NULL, BOUNDS, CLASS_CAST, BAD_REF

U16, U32, I32 = C.c_uint16, C.c_uint32, C.c_int32
LIB.jbv_string_new_utf16.argtypes = [C.c_void_p, C.POINTER(U16), U32, C.POINTER(I32)]
LIB.jbv_string_new_utf8.argtypes = [C.c_void_p, C.c_void_p, U32, C.POINTER(I32)]
LIB.jbv_string_length.argtypes = [C.c_void_p, I32, C.POINTER(U32)]
LIB.jbv_string_read_utf16.argtypes = [C.c_void_p, I32, U32, U32, C.POINTER(U16)]
LIB.jbv_string_read_utf8.argtypes = [C.c_void_p, I32, C.c_void_p, U32, C.POINTER(U32)]


def read_units(vm, ref):
    length = U32()
    assert LIB.jbv_string_length(vm.handle, ref, C.byref(length)) == OK
    data = (U16 * length.value)()
    assert LIB.jbv_string_read_utf16(vm.handle, ref, 0, length, data) == OK
    return list(data)


class StringTests(unittest.TestCase):
    def prepare(self, **kwargs):
        vm = VM(**kwargs)
        self.addCleanup(vm.close)
        self.assertEqual(vm.status, OK)
        for p in sorted(CLASSES.glob('String*.class')):
            self.assertFalse(api.has_indy(p.read_bytes()), p)
            self.assertEqual(vm.load(p.read_bytes()), OK, p)
        def collect(handle, user, args, count, out):
            return LIB.jbv_collect(handle)
        self.assertEqual(vm.bind('collect', collect, owner='Strings', descriptor='()V'), OK)
        return vm

    def new16(self, vm, units):
        ref = I32()
        self.assertEqual(LIB.jbv_string_new_utf16(vm.handle, (U16 * len(units))(*units), len(units), C.byref(ref)), OK)
        return ref.value

    def text_call(self, vm, method, args=(), descriptor='()Ljava/lang/String;'):
        status, ref = vm.call(method, *args, owner='Strings', descriptor=descriptor)
        self.assertEqual(status, OK, (method, args, status))
        try:
            return ''.join(f'{c:04x}' for c in read_units(vm, ref))
        finally:
            self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)

    def oracle(self, lines):
        result = subprocess.run([str(api.JAVA), '-cp', str(CLASSES), 'TextOracle'],
                                input='\n'.join(lines)+'\n', capture_output=True, text=True, check=True)
        return result.stdout.splitlines()

    def test_object_class_strings_and_builders_match_hotspot(self):
        strings = ['literal', 'constant', 'empty', 'concat', 'builder', 'primitiveConcat', 'nullText', 'objectText', 'classNames', 'reentryAndRanges','edits','replacements']
        integers = ['classSemantics', 'noInitialization', 'constructors', 'comparisons', 'intern', 'errors', 'builderCapacity', 'wrapperTypes','editErrors','cloneArrays']
        expected = self.oracle(['S '+x for x in strings] + ['I '+x for x in integers])
        vm = self.prepare()
        for method, value in zip(strings, expected):
            with self.subTest(method=method): self.assertEqual(self.text_call(vm, method), value)
        for method, value in zip(integers, expected[len(strings):]):
            with self.subTest(method=method): self.assertEqual(vm.call(method, owner='Strings', descriptor='()I'), (OK, int(value)))
        self.assertEqual(self.text_call(vm, 'concatDynamic', (7,), '(I)Ljava/lang/String;'), 'value=7/8'.encode('utf-16-be').hex())

    def test_float_double_format_matches_hotspot(self):
        rng = random.Random(7001)
        cases = []
        for kind, width, fraction, max_exp in [('F',32,23,255), ('D',64,52,2047)]:
            values = [0, 1, 2, 3, 10, (1 << fraction)-1, 1 << fraction, (max_exp << fraction)-1,
                      max_exp << fraction, (max_exp << fraction)+1, (max_exp << fraction)+(1 << (fraction-1))]
            # Every normal exponent, both sides of powers of two (asymmetric margins).
            for e in range(1, max_exp):
                values.extend([(e << fraction)-1, e << fraction, (e << fraction)+1])
            values += [rng.getrandbits(width-1) for _ in range(500)]
            values += [v | (1 << (width-1)) for v in values[:30]]
            cases += [(kind,v) for v in values]
        expected = self.oracle([f'{kind} {bits:x}' for kind,bits in cases])
        vm = self.prepare()
        for (kind, bits), value in zip(cases, expected):
            args = (bits & 0xffffffff,) if kind == 'F' else (bits & 0xffffffff, bits >> 32)
            actual = self.text_call(vm, 'fmt'+kind, args, '('+kind+')Ljava/lang/String;')
            self.assertEqual(actual, value, (kind, hex(bits), bytes.fromhex(actual), bytes.fromhex(value)))
        print(f'HotSpot decimal comparisons: {len(cases)}', flush=True)

    def test_native_utf16_utf8_and_atomic_errors(self):
        vm = self.prepare()
        units = [0, 65, 0x416, 0xd83d, 0xde00, 0xd800, 0x78, 0xdc00]
        ref = self.new16(vm, units)
        self.assertEqual(read_units(vm, ref), units)
        required = U32(123)
        self.assertEqual(LIB.jbv_string_read_utf8(vm.handle, ref, None, 0, C.byref(required)), OK)
        expected = '\0AЖ😀\ufffdx\ufffd'.encode('utf-8')
        self.assertEqual(required.value, len(expected))
        buffer = C.create_string_buffer(b'!' * (len(expected)+1))
        required.value = 77
        self.assertEqual(LIB.jbv_string_read_utf8(vm.handle, ref, buffer, len(expected)-1, C.byref(required)), BAD_ARG)
        self.assertEqual(required.value, 77)
        self.assertEqual(buffer.raw[:-1], b'!'*(len(expected)+1))
        self.assertEqual(LIB.jbv_string_read_utf8(vm.handle, ref, buffer, len(expected), C.byref(required)), OK)
        self.assertEqual(buffer.raw[:len(expected)], expected)
        self.assertEqual(buffer.raw[len(expected)], ord('!'))
        partial = (U16 * 2)(123,456)
        self.assertEqual(LIB.jbv_string_read_utf16(vm.handle, ref, 3, 2, partial), OK)
        self.assertEqual(list(partial), [0xd83d,0xde00])
        self.assertEqual(LIB.jbv_string_read_utf16(vm.handle, ref, 8, 1, partial), BOUNDS)
        self.assertEqual(list(partial), [0xd83d,0xde00])
        for invalid in [b'\xc0\x80', b'\xed\xa0\x80', b'\xf4\x90\x80\x80', b'\xff', b'\xc2', b'\xe0\x80\x80', b'\xe2(\xa1']:
            out = I32(123)
            self.assertEqual(LIB.jbv_string_new_utf8(vm.handle, invalid, len(invalid), C.byref(out)), BAD_ARG)
            self.assertEqual(out.value, 123)
        raw = '\0AЖ😀'.encode('utf-8'); out = I32()
        self.assertEqual(LIB.jbv_string_new_utf8(vm.handle, raw, len(raw), C.byref(out)), OK)
        self.assertEqual(read_units(vm,out.value), units[:5])
        for value in (out.value,ref): self.assertEqual(LIB.jbv_release(vm.handle,value), OK)
        self.assertEqual(LIB.jbv_collect(vm.handle), OK)
        self.assertEqual(LIB.jbv_string_length(vm.handle, ref, C.byref(required)), BAD_REF)
        self.assertEqual(LIB.jbv_string_length(vm.handle, 0, C.byref(required)), NULL)

    def test_gc_reentry_literals_mirrors_and_weak_intern(self):
        vm = self.prepare()
        for method in ['literal','classNames','constant']:
            first = self.text_call(vm, method)
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(self.text_call(vm, method), first)
        self.assertEqual(LIB.jbv_set_heap_limit(vm.handle, vm.stats().bytes + 4000), OK)
        expected = ('gc'*24)[1:].encode('utf-16-be').hex()
        self.assertEqual(self.text_call(vm,'gcText',(24,),'(I)Ljava/lang/String;'), expected)
        ref = self.new16(vm,[0x1234,0,0x5678])
        status, result = vm.call('identity',ref,owner='Strings',descriptor='(Ljava/lang/String;)Ljava/lang/String;')
        self.assertEqual((status,result),(OK,ref))
        self.assertEqual(LIB.jbv_release(vm.handle,ref),OK)

        self.assertEqual(LIB.jbv_collect(vm.handle),OK)
        self.assertEqual(read_units(vm,ref),[0x1234,0,0x5678])
        status, interned = vm.call('dynamicIntern',ref,owner='Strings',descriptor='(Ljava/lang/String;)Ljava/lang/String;')
        self.assertEqual((status,interned),(OK,ref))
        self.assertEqual(LIB.jbv_release(vm.handle,ref),OK)
        self.assertEqual(LIB.jbv_release(vm.handle,interned),OK)
        self.assertEqual(LIB.jbv_collect(vm.handle),OK)
        length = U32()
        self.assertEqual(LIB.jbv_string_length(vm.handle,ref,C.byref(length)),BAD_REF)

    def test_builtin_layouts_cannot_be_shadowed_before_lazy_creation(self):
        original = (CLASSES/'StringPeer.class').read_bytes()
        with VM() as vm:
            for name in [b'java/lang/String',b'java/lang/Class',b'java/lang/Integer',b'java/lang/Throwable']:
                renamed = original.replace(b'\0\x0aStringPeer',len(name).to_bytes(2,'big')+name)
                self.assertEqual(vm.load(renamed),api.LINKAGE)
            ref = self.new16(vm,[65])
            self.assertEqual(LIB.jbv_release(vm.handle,ref),OK)

    def test_allocation_failure_cleanup_and_recovery(self):
        # Inject failures at each allocation in lazy String metadata + String/char[].
        succeeded = False
        for allowed in range(35):
            with VM() as vm:
                vm.fail_after = vm.allocations + allowed
                out = I32(123)
                status = LIB.jbv_string_new_utf8(vm.handle,b'hello',5,C.byref(out))
                if status == OK:
                    succeeded = True
                    self.assertEqual(LIB.jbv_release(vm.handle,out.value),OK)
                else:
                    self.assertEqual(status,OOM)
                    self.assertEqual(out.value,123)
                vm.fail_after = None
                self.assertEqual(LIB.jbv_collect(vm.handle),OK)
                self.assertEqual(LIB.jbv_string_new_utf8(vm.handle,b'recovered',9,C.byref(out)),OK)
                self.assertEqual(read_units(vm,out.value),list(b'recovered'))
                self.assertEqual(LIB.jbv_release(vm.handle,out.value),OK)
        self.assertTrue(succeeded)

    def test_class_mirror_failure_cleanup_and_primitive_namespace(self):
        for allowed in range(35):
            with VM() as vm:
                self.assertEqual(vm.load_name('Strings'),OK)
                vm.fail_after = vm.allocations + allowed
                status, ref = vm.call('intClass',owner='Strings',descriptor='()Ljava/lang/Class;')
                if status == OK: self.assertEqual(LIB.jbv_release(vm.handle,ref),OK)
                else: self.assertIn(status,(OOM,api.LINKAGE))
        vm = self.prepare()
        data = (CLASSES/'StringPeer.class').read_bytes()
        self.assertIn(b'\0\x0aStringPeer',data)
        renamed = data.replace(b'\0\x0aStringPeer',b'\0\x03int')
        self.assertEqual(vm.load(renamed),OK)
        self.assertEqual(vm.call('classSemantics',owner='Strings',descriptor='()I'),(OK,1023))
        status, ref = vm.call('value',owner='int',descriptor='()Ljava/lang/String;')
        self.assertEqual(status,OK)
        self.assertEqual(LIB.jbv_release(vm.handle,ref),OK)


if __name__ == '__main__':
    unittest.main(argv=[__file__, *api.remaining], verbosity=2)
