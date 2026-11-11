"""Arrays, Collections, Random, Comparator and StrictMath scenarios against HotSpot.
The scenarios use lambdas, so JByteVM runs the build-time lowered classes."""
import os
import subprocess
import unittest
from test_vm import VM, LIB, JAVA, CLASSES, ROOT, remaining, OK

class UtilTests(unittest.TestCase):
    def test_util_against_hotspot(self):
        cases=[(m,n) for m in ['arrays','collections','random','comparators','math'] for n in [0,1,-1,17,123456789]]
        original=ROOT/'build/lambda-original';lowered=ROOT/'build/lambda-lowered'
        oracle=subprocess.run([str(JAVA),'-cp',os.pathsep.join([str(CLASSES),str(original)]),'NumericOracle'],
            input='\n'.join(f'UtilValues#{m} (I)I {n&0xffffffff:x}' for m,n in cases)+'\n',text=True,capture_output=True,timeout=60)
        self.assertEqual(oracle.returncode,0,oracle.stderr)
        expected=[int(s,16) for s in oracle.stdout.splitlines()];self.assertEqual(len(expected),len(cases))
        with VM(instructions=400000000) as vm:
            for p in sorted(lowered.glob('UtilValues*.class')):self.assertEqual(vm.load(p.read_bytes()),OK,p)
            for (m,n),value in zip(cases,expected):
                status,actual=vm.call(m,n,owner='UtilValues')
                self.assertEqual((status,actual&0xffffffff),(OK,value),(m,n))
                self.assertEqual(LIB.jbv_collect(vm.handle),OK)
        print('Util HotSpot scenarios:',len(cases),flush=True)
if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
