"""Collections with collisions, backed views, callbacks, and iterator mutation."""
import subprocess
import unittest
from test_vm import VM, LIB, JAVA, CLASSES, remaining, OK
class CollectionTests(unittest.TestCase):
    def test_collections_against_hotspot(self):
        cases=[(method,n) for method in ['list','views','map','functions','factories','sets','errors'] for n in [0,1,-1,17,123456789]]
        oracle=subprocess.run([str(JAVA),'-cp',str(CLASSES),'NumericOracle'],input='\n'.join(f'CollectionValues#{m} (I)I {n&0xffffffff:x}' for m,n in cases)+'\n',text=True,capture_output=True,timeout=30)
        self.assertEqual(oracle.returncode,0,oracle.stderr)
        expected=[int(s,16) for s in oracle.stdout.splitlines()]
        self.assertEqual(len(expected),len(cases))
        with VM(instructions=50000000) as vm:
            for p in sorted(CLASSES.glob('CollectionValues*.class')):self.assertEqual(vm.load(p.read_bytes()),OK,p)
            for (m,n),value in zip(cases,expected):
                status,actual=vm.call(m,n,owner='CollectionValues')
                self.assertEqual((status,actual&0xffffffff),(OK,value),(m,n))
                self.assertEqual(LIB.jbv_collect(vm.handle),OK)
        print('Collection HotSpot scenarios:',len(cases),flush=True)
if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
