"""Integration, HotSpot differential, trusted-code loading, reentry and allocation tests."""
import argparse
import ctypes as C
import json
from pathlib import Path
import random
import struct
import subprocess
import sys
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_no_indy import has_indy

parser = argparse.ArgumentParser()
parser.add_argument("--jdk", required=True, type=Path)
parser.add_argument("--build", type=Path)
options, remaining = parser.parse_known_args()
BUILD = (options.build or ROOT / "build/x86").resolve()
if C.sizeof(C.c_void_p) != 4:
    raise SystemExit("Use 32-bit Python: the DLL is x86.")
JAVA = options.jdk / "bin/java.exe"
JAVAP = options.jdk / "bin/javap.exe"
CLASSES = ROOT / "build/classes"
LIB = C.CDLL(str(BUILD / "Release/jbytevm.dll"))
LIB.jbv_features.restype = C.c_uint32
FEATURES = LIB.jbv_features()
CRT = C.CDLL("ucrtbase")
CRT.malloc.argtypes = [C.c_size_t]
CRT.malloc.restype = C.c_void_p
CRT.free.argtypes = [C.c_void_p]
CRT.free.restype = None
ALLOC = C.CFUNCTYPE(C.c_void_p, C.c_void_p, C.c_size_t)
FREE = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p)
NATIVE = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_void_p, C.POINTER(C.c_int32), C.c_uint16, C.POINTER(C.c_int32))


class Config(C.Structure):
    _fields_ = [("alloc", ALLOC), ("free", FREE), ("user", C.c_void_p),
                ("max_slots", C.c_uint32), ("max_depth", C.c_uint32), ("max_instructions", C.c_uint64),
                ("max_memory", C.c_size_t), ("max_heap", C.c_size_t)]


LIB.jbv_create.argtypes = [C.POINTER(Config), C.POINTER(C.c_void_p)]
LIB.jbv_destroy.argtypes = [C.c_void_p]
LIB.jbv_load_class.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t]
LIB.jbv_load_jar.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t]
LIB.jbv_call.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p, C.c_char_p, C.POINTER(C.c_int32), C.c_uint16, C.POINTER(C.c_int32)]
LIB.jbv_bind_native.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p, C.c_char_p, NATIVE, C.c_void_p]
LIB.jbv_status_string.argtypes = [C.c_int]
LIB.jbv_status_string.restype = C.c_char_p
OK, BAD_ARG, OOM, BAD_CLASS, VERSION, INDY, UNSUPPORTED, MISSING, LINKAGE, DIV_ZERO, LIMIT, BUSY = range(12)
NULL, BOUNDS, NEGATIVE_SIZE, ARRAY_STORE, CLASS_CAST, BAD_REF = range(12, 18)
LIB.jbv_retain.argtypes = [C.c_void_p, C.c_int32]
LIB.jbv_release.argtypes = [C.c_void_p, C.c_int32]
LIB.jbv_collect.argtypes = [C.c_void_p]
LIB.jbv_clear_exception.argtypes = [C.c_void_p]
LIB.jbv_set_heap_limit.argtypes = [C.c_void_p, C.c_size_t]


class HeapStats(C.Structure):
    _fields_ = [("bytes", C.c_size_t), ("objects", C.c_uint32), ("collections", C.c_uint64)]


LIB.jbv_heap_stats.argtypes = [C.c_void_p, C.POINTER(HeapStats)]


class VM:
    def __init__(self, slots=0, depth=0, instructions=0, fail_after=None, memory=0, heap=0):
        self.live = {}
        self.allocator_errors = []
        self.fail_after = fail_after
        self.allocations = 0
        self.peak_bytes = 0
        self.live_bytes = 0
        self.callbacks = []

        def alloc(user, size):
            if self.fail_after is not None and self.allocations >= self.fail_after:
                return None
            self.allocations += 1
            pointer = CRT.malloc(size)
            if pointer:
                self.live[pointer] = size
                self.live_bytes += size
                self.peak_bytes = max(self.peak_bytes, self.live_bytes)
            return pointer

        def free(user, pointer):
            if pointer not in self.live:
                self.allocator_errors.append(f"invalid free: {pointer}")
                return
            self.live_bytes -= self.live.pop(pointer)
            CRT.free(pointer)

        self.alloc = ALLOC(alloc)
        self.free = FREE(free)
        self.config = Config(self.alloc, self.free, None, slots, depth, instructions, memory, heap)
        self.handle = C.c_void_p()
        self.status = LIB.jbv_create(C.byref(self.config), C.byref(self.handle))

    def load_jar(self, data):
        buffer = C.create_string_buffer(data)
        return LIB.jbv_load_jar(self.handle, buffer, len(data))

    def load(self, data):
        buffer = C.create_string_buffer(data)
        return LIB.jbv_load_class(self.handle, buffer, len(data))

    def load_name(self, name):
        return self.load((CLASSES / f"{name}.class").read_bytes())

    def call(self, method, *args, owner="Core", descriptor=None):
        descriptor = descriptor or "(" + "I" * len(args) + ")I"
        packed = (C.c_int32 * len(args))(*args)
        result = C.c_int32(0x13579)
        status = LIB.jbv_call(self.handle, owner.encode(), method.encode(), descriptor.encode(), packed, len(args), C.byref(result))
        return status, result.value

    def bind(self, name, function, owner="Core", descriptor="(I)I"):
        native = NATIVE(function)
        self.callbacks.append(native)
        return LIB.jbv_bind_native(self.handle, owner.encode(), name.encode(), descriptor.encode(), native, None)

    def stats(self):
        result = HeapStats()
        assert LIB.jbv_heap_stats(self.handle, C.byref(result)) == OK
        return result

    def load_objects(self):
        for path in sorted(CLASSES.glob("Objects*.class")):
            assert self.load(path.read_bytes()) == OK, path

    def close(self):
        if self.handle:
            assert LIB.jbv_destroy(self.handle) == OK
            self.handle = C.c_void_p()
        assert not self.live, self.live
        assert not self.allocator_errors, self.allocator_errors

    def __enter__(self):
        assert self.status == OK, self.status
        return self

    def __exit__(self, *_):
        self.close()


def class_code(data):
    """Find Code arrays for targeted mutations, independently of the C parser."""
    count = struct.unpack_from(">H", data, 8)[0]
    texts, index, pos = {}, 1, 10
    while index < count:
        tag = data[pos]
        pos += 1
        if tag == 1:
            n = struct.unpack_from(">H", data, pos)[0]
            pos += 2
            texts[index] = bytes(data[pos:pos + n]).decode("utf-8")
            pos += n
        elif tag in (3, 4, 9, 10, 11, 12, 17, 18):
            pos += 4
        elif tag in (5, 6):
            pos += 8
            index += 1
        elif tag in (7, 8, 16, 19, 20):
            pos += 2
        elif tag == 15:
            pos += 3
        else:
            raise ValueError(tag)
        index += 1
    pos += 6
    interfaces = struct.unpack_from(">H", data, pos)[0]
    pos += 2 + interfaces * 2
    codes = {}
    for kind in ("field", "method"):
        members = struct.unpack_from(">H", data, pos)[0]
        pos += 2
        for _ in range(members):
            _, name, _, attrs = struct.unpack_from(">HHHH", data, pos)
            pos += 8
            for _ in range(attrs):
                attr, size = struct.unpack_from(">HI", data, pos)
                pos += 6
                if kind == "method" and texts[attr] == "Code":
                    code_size = struct.unpack_from(">I", data, pos + 4)[0]
                    codes[texts[name]] = (pos + 8, code_size, pos)
                pos += size
    return codes


class RuntimeTests(unittest.TestCase):
    def test_trusted_frames_keep_only_reference_roots(self):
        with VM() as vm:
            for path in sorted(CLASSES.glob('TrustedFrames*.class')):
                self.assertEqual(vm.load(path.read_bytes()), OK)
            def checkpoint(handle, user, args, count, result):
                status = LIB.jbv_collect(handle)
                if status == OK:
                    result[0] = vm.stats().objects
                return status
            self.assertEqual(vm.bind('checkpoint', checkpoint, 'TrustedFrames', '()I'), OK)
            # Reference arguments around long/double values survive a native GC.
            self.assertEqual(vm.call('roots', 11, owner='TrustedFrames'), (OK, 3044))
            # A reused frame must clear old local reference bits before any GC.
            self.assertEqual(vm.call('reuse', 7, owner='TrustedFrames'), (OK, 0))
            status, ref = vm.call('make', 9, owner='TrustedFrames', descriptor='(I)LTrustedFrames$Box;')
            self.assertEqual(status, OK)
            self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)
            # An integer equal to a live handle is not a GC root.
            self.assertEqual(vm.call('integerBits', ref, owner='TrustedFrames'), (OK, 0))

    def test_java_exception_handlers_and_gc(self):
        cases = [(method, n) for method in ("nested", "ordered", "cleanup", "suppressed", "resources") for n in (-1, 0, 1, 2, 7)]
        cases += [("initialization", 0), ("initialization", 1)]
        stdin = "\n".join(f"Exceptions#{method} {n}" for method, n in cases) + "\n"
        oracle = subprocess.run([str(JAVA), "-cp", str(CLASSES), "Oracle"], input=stdin, capture_output=True, text=True, check=True, timeout=30)
        expected = [int(x) for x in oracle.stdout.splitlines()]
        self.assertEqual(len(expected), len(cases))
        LIB.jbv_exception.argtypes = [C.c_void_p, C.POINTER(C.c_int32)]
        with VM() as vm:
            for path in sorted(CLASSES.glob("Exceptions*.class")):
                self.assertEqual(vm.load(path.read_bytes()), OK)
            for (method, n), value in zip(cases, expected):
                self.assertEqual(vm.call(method, n, owner="Exceptions"), (OK, value), (method, n))
            def gc(handle, user, args, count, result):
                result[0] = 0
                return LIB.jbv_collect(handle)
            self.assertEqual(vm.bind("gc", gc, "Exceptions", "()I"), OK)
            self.assertEqual(vm.call("gcCatch", 41, owner="Exceptions"), (OK, 42))
            self.assertEqual(vm.call("uncaught", owner="Exceptions")[0], 22)
            exception = C.c_int32()
            self.assertEqual(LIB.jbv_exception(vm.handle, C.byref(exception)), OK)
            self.assertGreater(exception.value, 0)
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(LIB.jbv_release(vm.handle, exception.value), OK)
            self.assertEqual(vm.call("nested", 0, owner="Exceptions"), (OK, 17))

    def test_differential_hotspot(self):
        rng = random.Random(20261110)
        cases = []
        edges = [-2147483648, -2147483647, -65537, -1, 0, 1, 31, 32, 65535, 2147483647]
        pairs = [(a, b) for a in edges for b in edges]
        pairs += [(rng.randint(-2**31, 2**31 - 1), rng.randint(-2**31, 2**31 - 1)) for _ in range(100)]
        for name in ("arithmetic", "divide", "remainder", "shifts"):
            cases.extend((name, (a, b)) for a, b in pairs if b or name not in ("divide", "remainder"))
        for name in ("negate", "narrow", "dense", "sparse"):
            cases.extend((name, (a,)) for a in edges + [-1000, 50, 100000, 2])
        cases += [("sum", (a,)) for a in (0, 1, 2, 100, 100000)]
        cases += [("recursive", (a,)) for a in (0, 1, 5, 12, 13)]
        stdin = "\n".join(" ".join(map(str, (name, *args))) for name, args in cases) + "\n"
        oracle = subprocess.run([str(JAVA), "-cp", str(CLASSES), "Oracle"], input=stdin, capture_output=True, text=True, check=True, timeout=30)
        expected = [int(line) for line in oracle.stdout.splitlines()]
        self.assertEqual(len(cases), len(expected))
        with VM() as vm:
            self.assertEqual(vm.load_name("Core"), OK)
            for (name, args), value in zip(cases, expected):
                self.assertEqual(vm.call(name, *args), (OK, value), (name, args))
        print(f"HotSpot differential cases: {len(cases)}", flush=True)

    def test_static_initialization_and_multiple_vms(self):
        with VM() as first, VM() as second:
            for vm in (first, second):
                self.assertEqual(vm.load_name("Core"), OK)
                self.assertEqual(vm.load_name("Helper"), OK)
                self.assertEqual(vm.call("cross", 9), (OK, 23))
            self.assertEqual(first.call("tick"), (OK, 7))
            self.assertEqual(first.call("tick"), (OK, 8))
            self.assertEqual(second.call("tick"), (OK, 7))
            self.assertEqual(first.load_name("Core"), LINKAGE)

    def test_reentry_and_recovery(self):
        observations = []
        with VM() as vm:
            self.assertEqual(vm.load_name("Core"), OK)

            def leaf(handle, user, args, count, result):
                observations.append(("leaf", count, args[0]))
                result[0] = args[0] * 2
                return OK

            def bridge(handle, user, args, count, result):
                observations.append(("bridge", count, args[0]))
                observations.append(("busy", LIB.jbv_destroy(handle), vm.load_name("Helper")))
                observations.append(("failure", vm.call("divide", 10, 0)))
                status, value = vm.call("callback", args[0])
                result[0] = value
                return status

            self.assertEqual(vm.bind("leaf", leaf), OK)
            self.assertEqual(vm.bind("bridge", bridge), OK)
            self.assertEqual(vm.call("entry", 7), (OK, 28))
            self.assertEqual(vm.call("entry", 8), (OK, 30))
            self.assertIn(("busy", BUSY, BUSY), observations)
            self.assertIn(("failure", (DIV_ZERO, 0x13579)), observations)
            self.assertIn(("leaf", 1, 7), observations)

    def test_nested_native_depth_and_error_unwind(self):
        with VM(depth=16) as vm:
            self.assertEqual(vm.load_name("Core"), OK)

            def bridge(handle, user, args, count, result):
                if args[0] == 0:
                    result[0] = 100
                    return OK
                status, value = vm.call("entry", args[0] - 1)
                result[0] = value
                return status

            self.assertEqual(vm.bind("bridge", bridge), OK)
            self.assertEqual(vm.call("entry", 3), (OK, 144))
            self.assertEqual(vm.call("entry", 100)[0], LIMIT)
            self.assertEqual(vm.call("entry", 0), (OK, 111))

    def test_limits_share_budget_and_recover(self):
        with VM(depth=12, instructions=1000) as vm:
            self.assertEqual(vm.load_name("Core"), OK)
            self.assertEqual(vm.call("spin")[0], LIMIT)
            self.assertEqual(vm.call("recurseForever")[0], LIMIT)
            self.assertEqual(vm.call("sum", 5), (OK, 10))
        with VM(slots=2) as vm:
            self.assertEqual(vm.load_name("Core"), OK)
            self.assertEqual(vm.call("sum", 5)[0], LIMIT)
            self.assertEqual(vm.call("negate", 4), (OK, -4))
        with VM(instructions=80) as vm:
            self.assertEqual(vm.load_name("Core"), OK)

            def bridge(handle, user, args, count, result):
                # Each call needs less than 80 instructions. Together they must
                # exhaust the outer budget instead of resetting it on reentry.
                for _ in range(100):
                    status, value = vm.call("sum", 1)
                    if status != OK:
                        return status
                result[0] = 0
                return OK

            self.assertEqual(vm.bind("bridge", bridge), OK)
            self.assertEqual(vm.call("entry", 1)[0], LIMIT)
            self.assertEqual(vm.call("negate", 4), (OK, -4))

    def test_failure_statuses_and_initialization(self):
        with VM() as vm:
            self.assertEqual(vm.load_name("Core"), OK)
            self.assertEqual(vm.call("entry", 7)[0], MISSING)
            self.assertEqual(vm.call("noSuchMethod")[0], MISSING)
            self.assertEqual(vm.call("unsupportedLong", descriptor="()J")[0], UNSUPPORTED)
            self.assertEqual(vm.call("sum", descriptor="(I)I")[0], BAD_ARG)
            self.assertEqual(vm.call("divide", 1, 0), (DIV_ZERO, 0x13579))
            self.assertEqual(vm.load_name("BrokenInit"), OK)
            self.assertEqual(vm.call("get", owner="BrokenInit")[0], DIV_ZERO)
            self.assertEqual(vm.call("get", owner="BrokenInit")[0], LINKAGE)
            self.assertEqual(vm.call("sum", 5), (OK, 10))

    def test_indy_gate_and_concat_experiment(self):
        with VM() as vm:
            for name in ("Indy", "Concat"):
                data = (CLASSES / f"{name}.class").read_bytes()
                self.assertTrue(has_indy(data))
                self.assertEqual(vm.load(data), INDY)
            inline = ROOT / "build/concat-inline/Concat.class"
            data = inline.read_bytes()
            self.assertEqual(struct.unpack_from(">HH", data, 4), (0, 69))
            self.assertFalse(has_indy(data))
            self.assertEqual(vm.load(data), OK)
            status, result = vm.call("join", 7, owner="Concat", descriptor="(I)Ljava/lang/String;")
            if FEATURES & 8:
                self.assertEqual(status, OK)
                self.assertEqual(LIB.jbv_release(vm.handle, result), OK)
            else: self.assertIn(status, (MISSING, UNSUPPORTED))
            code = subprocess.run([str(JAVAP), "-c", str(inline)], capture_output=True, text=True, check=True).stdout
            self.assertIn("java/lang/StringBuilder", code)
            self.assertNotIn("invokedynamic", code)

    def test_versions_and_truncation(self):
        data = (CLASSES / "Core.class").read_bytes()
        with VM() as vm:
            for length in range(len(data)):
                self.assertEqual(vm.load(data[:length]), BAD_CLASS, length)
            for minor, major in ((0, 68), (0, 70), (65535, 69), (1, 69)):
                changed = bytearray(data)
                struct.pack_into(">HH", changed, 4, minor, major)
                self.assertEqual(vm.load(bytes(changed)), VERSION)
            self.assertEqual(vm.load(data + b"trailing"), BAD_CLASS)
            self.assertEqual(vm.load(data), OK)

    def test_code_is_loaded_without_verification(self):
        original = (CLASSES / 'Core.class').read_bytes()
        codes = class_code(original)
        changed = bytearray(original)
        spin, _, _ = codes['spin']
        struct.pack_into('>h', changed, spin + 1, 1)  # invalid branch target
        struct.pack_into('>H', changed, codes['arithmetic'][2], 0)  # invalid max_stack
        with VM() as vm:
            # Code is opaque to the loader. Never execute these invalid methods.
            self.assertEqual(vm.load(bytes(changed)), OK)
            self.assertEqual(vm.call('sum', 5), (OK, 10))

    def test_allocator_failures_leave_no_leaks(self):
        # Fail every remaining class-loading allocation site in turn.
        completed = False
        for limit in range(100):
            vm = VM(fail_after=limit)
            if vm.status == OK:
                status = vm.load_name("Core")
                self.assertIn(status, (OK, OOM))
                completed = status == OK
            else:
                self.assertEqual(vm.status, OOM)
            vm.close()
            if completed:
                break
        self.assertTrue(completed)

    def test_shared_jar_loads_lazily(self):
        import jar_pack
        jar = jar_pack.pack_classes([("Core", (CLASSES / "Core.class").read_bytes())])
        with VM() as vm:
            before = vm.live_bytes
            self.assertEqual(vm.load_jar(jar), OK)
            self.assertEqual(vm.call("negate", 5), (OK, -5))
            self.assertGreater(vm.live_bytes, before)
            self.assertNotEqual(vm.load_jar(jar), OK)
        with VM() as vm:
            self.assertNotEqual(vm.load_jar(jar[:len(jar) // 2]), OK)
            self.assertNotEqual(vm.call("negate", 5)[0], OK)

    def test_runtime_image_imports(self):
        # The runtime DLL may not hide its size in a redistributable CRT DLL.
        data = (BUILD / "Release/jbytevm.dll").read_bytes()
        pe = struct.unpack_from("<I", data, 0x3c)[0]
        self.assertEqual(data[pe:pe + 4], b"PE\x00\x00")
        optional = pe + 24
        self.assertEqual(struct.unpack_from("<H", data, pe + 4)[0], 0x14c)
        self.assertEqual(struct.unpack_from("<H", data, optional)[0], 0x10b)
        imports = struct.unpack_from("<II", data, optional + 96 + 8)
        self.assertEqual(imports, (0, 0), "Runtime must have no DLL imports")

    def test_objects_against_hotspot(self):
        cases = [("inheritedStatic", ()), ("initializeChild", ())]
        for name in ("dispatch", "privateDispatch", "references", "assignment", "churn"):
            cases.extend((name, (n,)) for n in (0, 1, 7, 100))
        cases.extend(("arrays", (n,)) for n in (0, 1, 3, 10, 100))
        cases.extend(("matrix", (n,)) for n in (0, 1, 3, 10))
        cases.extend(("multi", (n,)) for n in (0, 1, 3, 10))
        cases.extend((name, ()) for name in ("cycle", "nullCast"))
        stdin = "\n".join(" ".join(map(str, ("Objects#" + name, *args))) for name, args in cases) + "\n"
        oracle = subprocess.run([str(JAVA), "-cp", str(CLASSES), "Oracle"], input=stdin, capture_output=True, text=True, check=True, timeout=30)
        expected = [int(line) for line in oracle.stdout.splitlines()]
        with VM() as vm:
            vm.load_objects()
            for (name, args), value in zip(cases, expected):
                self.assertEqual(vm.call(name, *args, owner="Objects"), (OK, value), (name, args))
            self.assertEqual(len(expected), len(cases))
        print(f"Object/array HotSpot cases: {len(cases)}", flush=True)

    def test_object_errors_and_recovery(self):
        with VM() as vm:
            vm.load_objects()
            for name, args, expected in (
                ("nullField", (), NULL), ("nullCall", (), NULL), ("nullArray", (), NULL),
                ("index", (-1,), BOUNDS), ("index", (2,), BOUNDS),
                ("negative", (-1,), NEGATIVE_SIZE), ("badStore", (), ARRAY_STORE),
                ("badCast", (), CLASS_CAST), ("multi", (-1,), NEGATIVE_SIZE),
                ("emptyNegative", (-1,), NEGATIVE_SIZE),
            ):
                self.assertEqual(vm.call(name, *args, owner="Objects"), (expected, 0x13579), name)
                self.assertEqual(vm.call("nullCast", owner="Objects"), (OK, 1))
            self.assertEqual(vm.load_name("DefaultMethod"), OK)
            self.assertEqual(vm.load_name("DefaultProbe"), OK)
            self.assertEqual(vm.call("run", owner="DefaultProbe"), (OK, 1))
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 0)

    def test_default_interface_selection_and_initialization(self):
        cases = [("init", 0), ("dispatch", 0), ("dispatch", 42), ("direct", -7), ("interfaceInit", 0)]
        stdin = "\n".join(f"Defaults#{name} {n}" for name, n in cases) + "\n"
        oracle = subprocess.run([str(JAVA), "-cp", str(CLASSES), "Oracle"], input=stdin,
                                capture_output=True, text=True, check=True, timeout=30)
        expected = [int(line) for line in oracle.stdout.splitlines()]
        self.assertEqual(len(cases), len(expected))
        with VM() as vm:
            self.assertEqual(vm.load_name("Defaults"), OK)
            for path in sorted(CLASSES.glob("Defaults$*.class")):
                self.assertEqual(vm.load_name(path.stem), OK)
            for (name, n), value in zip(cases, expected):
                self.assertEqual(vm.call(name, n, owner="Defaults"), (OK, value), name)

    def test_gc_handles_and_native_ownership(self):
        with VM() as vm:
            vm.load_objects()
            status, ref = vm.call("make", 123, owner="Objects", descriptor="(I)LObjects$Node;")
            self.assertEqual(status, OK)
            self.assertGreater(ref, 0)
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 1)
            self.assertEqual(vm.call("read", ref, owner="Objects", descriptor="(LObjects$Node;)I"), (OK, 123))
            self.assertEqual(LIB.jbv_retain(vm.handle, ref), OK)
            self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 1)
            self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)
            self.assertEqual(LIB.jbv_release(vm.handle, ref), BAD_REF)
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 0)
            self.assertEqual(vm.call("read", ref, owner="Objects", descriptor="(LObjects$Node;)I")[0], BAD_REF)
            status, other = vm.call("make", 456, owner="Objects", descriptor="(I)LObjects$Node;")
            self.assertEqual(status, OK)
            self.assertNotEqual(other, ref)
            self.assertEqual(LIB.jbv_retain(vm.handle, ref), BAD_REF)
            self.assertEqual(LIB.jbv_release(vm.handle, other), OK)
            self.assertEqual(LIB.jbv_retain(vm.handle, 0), OK)
            self.assertEqual(LIB.jbv_release(vm.handle, 0), OK)

    def test_gc_graphs_static_fields_and_arrays(self):
        with VM() as vm:
            vm.load_objects()
            status, ref = vm.call("chain", 1000, owner="Objects", descriptor="(I)LObjects$Node;")
            self.assertEqual(status, OK)
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 1000)
            self.assertEqual(vm.call("chainSum", ref, owner="Objects", descriptor="(LObjects$Node;)I"), (OK, 499500))
            self.assertEqual(vm.call("keep", ref, owner="Objects", descriptor="(LObjects$Node;)V"), (OK, 0))
            self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 1000)
            self.assertEqual(vm.call("readSaved", owner="Objects"), (OK, 999))
            self.assertEqual(vm.call("clearSaved", owner="Objects", descriptor="()V"), (OK, 0))
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 0)
            self.assertEqual(vm.call("cycle", owner="Objects"), (OK, 30))
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 0)
            status, array = vm.call("arrayRoot", 21, owner="Objects", descriptor="(I)[LObjects$Node;")
            self.assertEqual(status, OK)
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 3)
            self.assertEqual(vm.call("arraySum", array, owner="Objects", descriptor="([LObjects$Node;)I"), (OK, 43))
            self.assertEqual(LIB.jbv_release(vm.handle, array), OK)
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 0)

    def test_gc_during_native_reentry(self):
        observations = []
        with VM() as vm:
            vm.load_objects()
            self.assertEqual(vm.load_name("InitWithGc"), OK)
            self.assertEqual(LIB.jbv_set_heap_limit(vm.handle, 512), OK)

            def collect(handle, user, args, count, result):
                observations.append(LIB.jbv_collect(handle))
                result[0] = 2
                return OK

            def probe(handle, user, args, count, result):
                ref = args[0]
                observations.append(LIB.jbv_collect(handle))
                # Repeated Java allocation triggers GC while the native frame
                # still needs its borrowed argument.
                observations.append(vm.call("churn", 1000, owner="Objects"))
                status, value = vm.call("read", ref, owner="Objects", descriptor="(LObjects$Node;)I")
                result[0] = value
                return status

            def round_trip(handle, user, args, count, result):
                status, ref = vm.call("identity", args[0], owner="Objects", descriptor="(LObjects$Node;)LObjects$Node;")
                if status == OK:
                    observations.append(LIB.jbv_collect(handle))
                    result[0] = ref
                    observations.append(LIB.jbv_release(handle, ref))
                return status

            self.assertEqual(vm.bind("collectNative", collect, "Objects", "()I"), OK)
            self.assertEqual(vm.bind("probe", probe, "Objects", "(LObjects$Node;)I"), OK)
            self.assertEqual(vm.bind("roundTrip", round_trip, "Objects", "(LObjects$Node;)LObjects$Node;"), OK)
            self.assertEqual(vm.call("suspendedOperand", owner="Objects"), (OK, 42))
            self.assertEqual(vm.call("nativeRoot", 77, owner="Objects"), (OK, 77))
            self.assertEqual(vm.call("nativeReference", 91, owner="Objects"), (OK, 91))
            self.assertEqual(vm.call("makeAndCollect", 17, owner="Objects"), (OK, 17))
            self.assertEqual(vm.call("inheritedRoot", owner="Objects"), (OK, 42))
            # No caller frame owns this argument: it must be pinned before the
            # callee's <clinit> invokes native GC.
            status, ref = vm.call("make", 33, owner="Objects", descriptor="(I)LObjects$Node;")
            self.assertEqual(status, OK)
            self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)
            self.assertEqual(vm.call("read", ref, owner="InitWithGc", descriptor="(LObjects$Node;)I"), (OK, 33))
            self.assertIn((OK, 7007), observations)
            self.assertTrue(all(value == OK or value == (OK, 7007) for value in observations))
            self.assertGreater(vm.stats().collections, 10)
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 0)

    def test_heap_limit_and_allocation_failures(self):
        with VM() as vm:
            vm.load_objects()
            self.assertEqual(LIB.jbv_set_heap_limit(vm.handle, 256), OK)
            self.assertEqual(vm.call("churn", 10000, owner="Objects"), (OK, 70007))
            self.assertLessEqual(vm.stats().bytes, 256)
            self.assertEqual(vm.call("negative", 10000, owner="Objects")[0], OOM)
            self.assertEqual(vm.call("chain", 100, owner="Objects", descriptor="(I)LObjects$Node;")[0], OOM)
            self.assertEqual(vm.call("matrix", 100, owner="Objects")[0], OOM)
            self.assertEqual(LIB.jbv_clear_exception(vm.handle), OK)
            self.assertEqual(LIB.jbv_collect(vm.handle), OK)
            self.assertEqual(vm.stats().objects, 0)
            self.assertEqual(vm.call("churn", 10, owner="Objects"), (OK, 77))
        for allowance in range(10):
            with VM() as vm:
                vm.load_objects()
                vm.fail_after = vm.allocations + allowance
                status, ref = vm.call("make", 7, owner="Objects", descriptor="(I)LObjects$Node;")
                self.assertIn(status, (OK, OOM))
                vm.fail_after = None
                if status == OK:
                    self.assertEqual(LIB.jbv_release(vm.handle, ref), OK)
                else:
                    self.assertEqual(LIB.jbv_clear_exception(vm.handle), OK)
                self.assertEqual(LIB.jbv_collect(vm.handle), OK)
                self.assertEqual(vm.stats().objects, 0)
                self.assertEqual(vm.call("churn", 5, owner="Objects"), (OK, 42))

    def test_baseline_timing(self):
        with VM() as vm:
            self.assertEqual(vm.load_name("Core"), OK)
            expected = sum(range(100000)) & 0xffffffff
            if expected >= 2**31:
                expected -= 2**32
            durations = []
            for _ in range(7):
                start = time.perf_counter_ns()
                self.assertEqual(vm.call("sum", 100000), (OK, expected))
                durations.append((time.perf_counter_ns() - start) / 1e6)
            report = {"benchmark": "Core.sum(100000)", "result": expected,
                      "samples_ms": durations, "median_ms": sorted(durations)[3],
                      "notes": "Wall time via ctypes, warmed VM, no HotSpot speed comparison."}
            (BUILD / "timing-report.json").write_text(json.dumps(report, indent=2) + "\n")
            print(f"sum(100000) median: {report['median_ms']:.3f} ms", flush=True)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)
