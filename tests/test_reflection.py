"""Reflection compared with HotSpot, with GC pressure and native reentry."""
import subprocess
import unittest
from test_vm import VM, LIB, CLASSES, JAVA, remaining, OK, NATIVE

class ReflectionTests(unittest.TestCase):
    def load(self,vm):
        for p in sorted(CLASSES.rglob('*.class')):
            if p.name.startswith('Reflection') or p.parent.name=='reflection':
                self.assertEqual(vm.load(p.read_bytes()),OK,str(p))

    def test_hotspot(self):
        cases=[('ReflectionValues',m,0) for m in ['metadata','enumeration','calls','errors','fields','arrays','initialize']]+[('ReflectionAccess','check',0),('ReflectionValues','churn',300)]
        oracle=subprocess.run([str(JAVA),'-cp',str(CLASSES),'NumericOracle'],input=''.join(f'{c}#{m} (I)I {n:x}\n' for c,m,n in cases),text=True,capture_output=True,timeout=30)
        self.assertEqual(oracle.returncode,0,oracle.stderr)
        expected=[int(x,16) for x in oracle.stdout.splitlines()]
        self.assertEqual(expected[:-1],[255]*8)
        with VM() as vm:
            self.load(vm)
            for (c,m,n),value in zip(cases,expected):
                with self.subTest(method=m):
                    self.assertEqual(vm.call(m,n,owner=c),(OK,value))
                    self.assertEqual(LIB.jbv_collect(vm.handle),OK)

    def test_annotations(self):
        cases=[('values',0),('members',0),('equality',30)]
        oracle=subprocess.run([str(JAVA),'-cp',str(CLASSES),'NumericOracle'],input=''.join(f'ReflectionAnnotations#{m} (I)I {n:x}\n' for m,n in cases),text=True,capture_output=True,timeout=30)
        self.assertEqual(oracle.returncode,0,oracle.stderr)
        expected=[int(x,16) for x in oracle.stdout.splitlines()]
        self.assertEqual(expected,[255,255,15])
        with VM(heap=48*1024,instructions=20000000) as vm:
            self.load(vm)
            for (m,n),value in zip(cases,expected):
                with self.subTest(method=m):self.assertEqual(vm.call(m,n,owner='ReflectionAnnotations'),(OK,value))
                LIB.jbv_collect(vm.handle)

    def test_gc_and_reentry(self):
        with VM(heap=24*1024,instructions=10000000) as vm:
            self.load(vm)
            callback=NATIVE(lambda handle,user,args,count,out: self.callback(vm,args[0],out))
            vm.callbacks.append(callback)
            self.assertEqual(LIB.jbv_bind_native(vm.handle,b'ReflectionValues',b'callback',b'(I)I',callback,None),OK)
            self.assertEqual(vm.call('reentry',100,owner='ReflectionValues'),(OK,5450))
            self.assertEqual(vm.call('churn',600,owner='ReflectionValues'),(OK,182700))
            self.assertGreater(vm.stats().collections,0)

    def callback(self,vm,count,out):
        status,value=vm.call('churn',count,owner='ReflectionValues');out[0]=value;return status

if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
