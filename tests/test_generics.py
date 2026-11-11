"""Generic signatures and parameters through reflection, against HotSpot."""
import subprocess
import unittest
from test_vm import VM, LIB, JAVA, CLASSES, remaining, OK

class GenericTests(unittest.TestCase):
    def test_generics_against_hotspot(self):
        seeds=[0,1,-1,17]
        oracle=subprocess.run([str(JAVA),'-cp',str(CLASSES),'NumericOracle'],input='\n'.join(f'GenericValues#generics (I)I {n&0xffffffff:x}' for n in seeds)+'\n',text=True,capture_output=True,timeout=60)
        self.assertEqual(oracle.returncode,0,oracle.stderr)
        expected=[int(s,16) for s in oracle.stdout.splitlines()];self.assertEqual(len(expected),len(seeds))
        with VM(instructions=100000000) as vm:
            for p in sorted(CLASSES.glob('GenericValues*.class')):self.assertEqual(vm.load(p.read_bytes()),OK,p)
            for n,value in zip(seeds,expected):
                status,actual=vm.call('generics',n,owner='GenericValues')
                self.assertEqual((status,actual&0xffffffff),(OK,value),n)
                self.assertEqual(LIB.jbv_collect(vm.handle),OK)
if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
