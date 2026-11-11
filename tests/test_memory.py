"""Whole-VM budgets, verified against the host allocator's actual requests."""
import ctypes as C
import unittest
from test_vm import VM, LIB, OK, OOM, BAD_ARG, BUILD, remaining
import zipfile

# The full profile inflates its class library once per VM, inside the budget.
JAR=BUILD/'classpath.jar'
LIBRARY=zipfile.ZipFile(JAR).getinfo('jbv/classes.bin').file_size+64 if JAR.is_file() else 0

class MemoryStats(C.Structure):
    _fields_=[('used',C.c_size_t),('peak',C.c_size_t),('limit',C.c_size_t)]
LIB.jbv_memory_stats.argtypes=[C.c_void_p,C.POINTER(MemoryStats)]
LIB.jbv_new_array.argtypes=[C.c_void_p,C.c_char_p,C.c_int32,C.POINTER(C.c_int32)]

class MemoryTests(unittest.TestCase):
    def stats(self,vm):
        out=MemoryStats()
        self.assertEqual(LIB.jbv_memory_stats(vm.handle,C.byref(out)),OK)
        self.assertEqual(out.used,sum(vm.live.values()))
        self.assertEqual(out.peak,vm.peak_bytes)
        self.assertLessEqual(out.peak,out.limit)
        return out

    def array(self,vm,n):
        ref=C.c_int32(123)
        status=LIB.jbv_new_array(vm.handle,b'[I',n,C.byref(ref))
        if status!=OK:self.assertEqual(ref.value,123)
        self.stats(vm)
        return status,ref.value

    def test_default_and_configured_startup(self):
        with VM() as vm:
            self.assertEqual(self.stats(vm).limit,10*1024*1024)
            required=vm.peak_bytes
        for limit in (1,required-1,required):
            vm=VM(memory=limit)
            self.addCleanup(vm.close)
            self.assertEqual(vm.status,OK if limit==required else OOM)
            self.assertLessEqual(vm.peak_bytes,limit)
            if vm.status==OK:self.stats(vm)
            else:self.assertFalse(vm.live)
        with VM(slots=128,memory=8192) as vm:self.stats(vm)
        vm=VM(memory=8192,heap=8193);self.addCleanup(vm.close)
        self.assertEqual(vm.status,BAD_ARG);self.assertEqual(vm.allocations,0)

    def test_class_metadata_is_budgeted_and_rolled_back(self):
        with VM() as probe:
            initial=self.stats(probe).used
            self.assertEqual(probe.load_name('Core'),OK)
            needed=self.stats(probe).peak
            self.assertEqual(probe.stats().bytes,0)
        with VM(memory=needed-1) as vm:
            self.assertEqual(vm.load_name('Core'),OOM)
            self.assertEqual(self.stats(vm).used,initial)
            self.assertEqual(vm.load_name('NativeDemo'),OK)
            self.stats(vm)

    def test_default_budget_allows_heap_above_old_four_mib(self):
        with VM() as vm:
            status,ref=self.array(vm,8*1024*1024//4)
            self.assertEqual(status,OK)
            self.assertGreater(vm.stats().bytes,8*1024*1024)
            self.assertEqual(self.array(vm,3*1024*1024//4)[0],OOM)
            self.assertEqual(LIB.jbv_release(vm.handle,ref),OK)
            self.assertEqual(LIB.jbv_collect(vm.handle),OK)
            self.assertEqual(vm.stats().objects,0);self.stats(vm)

    def test_total_budget_gc_retry_and_recovery(self):
        with VM(slots=128,memory=64*1024+LIBRARY) as vm:
            refs=[]
            while True:
                status,ref=self.array(vm,1024)
                if status==OOM:break
                self.assertEqual(status,OK);refs.append(ref)
                self.assertLess(len(refs),20)
            self.assertGreater(len(refs),1)
            released=refs.pop();self.assertEqual(LIB.jbv_release(vm.handle,released),OK)
            # No explicit GC: object allocation must collect and retry safely.
            status,ref=self.array(vm,1024);self.assertEqual(status,OK);refs.append(ref)
            self.assertGreater(vm.stats().collections,0)
            for ref in refs:self.assertEqual(LIB.jbv_release(vm.handle,ref),OK)
            self.assertEqual(LIB.jbv_collect(vm.handle),OK)
            self.assertEqual(vm.stats().objects,0);self.stats(vm)

    def test_heap_limit_is_independent_and_never_raises_total_limit(self):
        with VM(memory=2*1024*1024,heap=1024) as vm:
            self.assertEqual(self.array(vm,1024)[0],OOM)
            self.assertEqual(LIB.jbv_set_heap_limit(vm.handle,3*1024*1024),BAD_ARG)
            self.assertEqual(self.array(vm,1024)[0],OOM)
            self.assertEqual(LIB.jbv_set_heap_limit(vm.handle,1024*1024),OK)
            status,ref=self.array(vm,1024);self.assertEqual(status,OK)
            self.assertEqual(LIB.jbv_release(vm.handle,ref),OK)
            self.assertEqual(self.stats(vm).limit,2*1024*1024)

    def test_native_reentry_shares_budget(self):
        with VM(memory=128*1024+LIBRARY) as vm:
            self.assertEqual(vm.load_name('Core'),OK)
            results=[]
            def bridge(handle,user,args,count,result):
                results.append(self.array(vm,32768)[0])
                status,value=vm.call('negate',args[0]);result[0]=value
                return status
            self.assertEqual(vm.bind('bridge',bridge),OK)
            self.assertEqual(vm.call('entry',7)[0],OK)
            self.assertEqual(results,[OOM]);self.stats(vm)

    def test_host_failure_does_not_charge_memory(self):
        with VM() as vm:
            initial=self.stats(vm).used;vm.fail_after=vm.allocations
            self.assertEqual(vm.load_name('Core'),OOM)
            self.assertEqual(self.stats(vm).used,initial)
            vm.fail_after=None
            self.assertEqual(vm.load_name('Core'),OK);self.stats(vm)
        self.assertEqual(LIB.jbv_memory_stats(None,None),BAD_ARG)

if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
