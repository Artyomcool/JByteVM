"""Condy bootstrap, caching, errors, primitive adaptation and direct handles."""
import subprocess
import unittest
from test_vm import VM, LIB, CLASSES, JAVA, ROOT, remaining, OK, NATIVE, LIMIT, UNSUPPORTED
from check_no_indy import has_constant
class DynamicTests(unittest.TestCase):
    def test_interface_private_bootstrap_and_lifetime(self):
        lowered=ROOT/'build/condy-lowered'
        request='CondyExtra#lifecycle (I)I 0\n'
        reference=subprocess.run([str(JAVA),'-cp',str(CLASSES),'NumericOracle'],input=request,text=True,capture_output=True,check=True)
        actual=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(lowered),'NumericOracle'],input=request,text=True,capture_output=True,check=True)
        self.assertEqual(actual.stdout,reference.stdout)
        with VM(heap=24*1024) as vm:
            for p in lowered.glob('CondyExtra*.class'):self.assertEqual(vm.load(p.read_bytes()),OK,p)
            self.assertEqual(vm.call('lifecycle',0,owner='CondyExtra'),(OK,7))

    def test_host_abort_is_not_cached_as_bootstrap_failure(self):
        with VM() as vm:
            for p in (ROOT/'build/condy-lowered').glob('CondyExtra*.class'):self.assertEqual(vm.load(p.read_bytes()),OK,p)
            attempts=[]
            def bootstrap(handle,user,args,count,out):
                attempts.append(count)
                if len(attempts)==1:return LIMIT
                LIB.jbv_collect(handle);out[0]=42;return OK
            callback=NATIVE(bootstrap);vm.callbacks.append(callback)
            self.assertEqual(LIB.jbv_bind_native(vm.handle,b'CondyExtra',b'nativeBootstrap',b'(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/Class;)I',callback,None),OK)
            self.assertEqual(vm.call('readNative',0,owner='CondyExtra')[0],LIMIT)
            self.assertEqual(vm.call('readNative',0,owner='CondyExtra'),(OK,42))
            self.assertEqual(vm.call('readNative',0,owner='CondyExtra'),(OK,42))
            self.assertEqual(attempts,[3,3])

    def test_unprepared_condy_is_rejected(self):
        with VM() as vm:self.assertEqual(vm.load((CLASSES/'Condy.class').read_bytes()),UNSUPPORTED)

    def test_condy_and_handles_against_hotspot(self):
        methods=['constants','constants','errors','errors','handles']
        oracle=subprocess.run([str(JAVA),'-cp',str(CLASSES),'NumericOracle'],input='\n'.join(f'CondyValues#{m} (I)I 0' for m in methods)+'\n',text=True,capture_output=True,timeout=30)
        self.assertEqual(oracle.returncode,0,oracle.stderr)
        expected=[int(s,16) for s in oracle.stdout.splitlines()];self.assertEqual(len(expected),len(methods))
        lowered=ROOT/'build/condy-lowered'
        actual=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(lowered),'NumericOracle'],input='\n'.join(f'CondyValues#{m} (I)I 0' for m in methods)+'\n',text=True,capture_output=True,timeout=30)
        self.assertEqual(actual.returncode,0,actual.stderr)
        self.assertEqual(actual.stdout,oracle.stdout)
        for p in lowered.glob('Condy*.class'):self.assertFalse(has_constant(p.read_bytes(),17),p)
        with VM() as vm:
            for p in sorted(lowered.glob('Condy*.class')):self.assertEqual(vm.load(p.read_bytes()),OK,p)
            for m,e in zip(methods,expected):
                self.assertEqual(vm.call(m,0,owner='CondyValues'),(OK,e),m)
                self.assertEqual(LIB.jbv_collect(vm.handle),OK)
if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
