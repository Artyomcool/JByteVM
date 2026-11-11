"""Throwable state, source lines and host-routed stack diagnostics."""
import ctypes as C
import subprocess
import unittest
from test_vm import VM, LIB, CLASSES, JAVA, remaining, OK, HeapStats
from test_strings import read_units
class DiagnosticTests(unittest.TestCase):
    def prepare(self):
        vm=VM();self.addCleanup(vm.close)
        for p in sorted(CLASSES.glob('Diagnostics*.class')):self.assertEqual(vm.load(p.read_bytes()),OK)
        return vm
    def test_trace_and_throwable(self):
        oracle=subprocess.run([str(JAVA),'-cp',str(CLASSES),'Diagnostics'],capture_output=True,text=True,check=True)
        vm=self.prepare();status,ref=vm.call('trace',owner='Diagnostics',descriptor='()Ljava/lang/String;');self.assertEqual(status,OK)
        self.assertEqual(''.join(chr(x) for x in read_units(vm,ref)),oracle.stdout);LIB.jbv_release(vm.handle,ref)
        oracle=subprocess.run([str(JAVA),'-cp',str(CLASSES),'NumericOracle'],input='Diagnostics#semantics (I)I 0\n',capture_output=True,text=True,check=True)
        self.assertEqual(vm.call('semantics',0,owner='Diagnostics'),(OK,int(oracle.stdout,16)))
    def test_print_stack_trace(self):
        import os
        env=dict(os.environ);env.pop('JAVA_TOOL_OPTIONS',None)
        oracle=subprocess.run([str(JAVA),'-cp',str(CLASSES),'Diagnostics','print'],capture_output=True,text=True,check=True,env=env)
        clock=C.CFUNCTYPE(C.c_int64,C.c_void_p,C.c_int);write=C.CFUNCTYPE(C.c_int,C.c_void_p,C.c_void_p,C.c_int32,C.c_int)
        class Services(C.Structure):_fields_=[('clock',clock),('write',write),('user',C.c_void_p)]
        LIB.jbv_set_host_services.argtypes=[C.c_void_p,C.POINTER(Services)]
        vm=self.prepare();parts=[]
        def output(handle,user,ref,error):parts.append(''.join(chr(x) for x in read_units(vm,ref)));return OK
        services=Services(clock(lambda user,mono:0),write(output),None)
        self.assertEqual(LIB.jbv_set_host_services(vm.handle,C.byref(services)),OK)
        self.assertEqual(vm.call('print',0,owner='Diagnostics'),(OK,1))
        self.assertEqual(''.join(parts).replace('\r\n','\n'),oracle.stderr)
    def test_heap_and_stack_errors(self):
        vm=self.prepare()
        self.assertEqual(LIB.jbv_set_heap_limit(vm.handle,65536),OK)
        self.assertEqual(vm.call('memory',0,owner='Diagnostics'),(OK,42))
        self.assertEqual(vm.call('stack',0,owner='Diagnostics'),(OK,17))
        self.assertEqual(LIB.jbv_collect(vm.handle),OK)
    def test_repeated_retained_oom_is_bounded(self):
        vm=self.prepare();self.assertEqual(LIB.jbv_set_heap_limit(vm.handle,1024),OK)
        status,ref=vm.call('memoryRepeated',owner='Diagnostics',descriptor='()[Ljava/lang/Throwable;')
        self.assertEqual(status,OK)
        stats=HeapStats();self.assertEqual(LIB.jbv_heap_stats(vm.handle,C.byref(stats)),OK)
        self.assertLessEqual(stats.bytes,1024+44)
        self.assertEqual(LIB.jbv_release(vm.handle,ref),OK)
        self.assertEqual(LIB.jbv_clear_exception(vm.handle),OK)
        self.assertEqual(LIB.jbv_collect(vm.handle),OK)
        self.assertEqual(LIB.jbv_heap_stats(vm.handle,C.byref(stats)),OK)
        self.assertEqual(stats.objects,0)
if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
