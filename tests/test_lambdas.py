"""Original HotSpot, lowered HotSpot, and interpreter results for lambda sites."""
import subprocess
import unittest
from test_vm import VM, LIB, JAVA, ROOT, remaining, OK, has_indy
class LambdaTests(unittest.TestCase):
    def test_lowered_lambdas(self):
        original=ROOT/'build/lambda-original';lowered=ROOT/'build/lambda-lowered'
        a=subprocess.run([str(JAVA),'-cp',str(original),'LambdaValues'],capture_output=True,text=True,check=True)
        b=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(lowered),'LambdaValues'],capture_output=True,text=True,check=True)
        self.assertEqual(a.stdout,b.stdout)
        expected=[int(s) for s in a.stdout.splitlines()];cases=[(m,n) for n in [0,1,-1,17,12345] for m in ['basic','advanced','errors']]
        self.assertEqual(len(expected),len(cases))
        with VM() as vm:
            for p in sorted(lowered.rglob('*.class')):
                data=p.read_bytes();self.assertFalse(has_indy(data),p);self.assertEqual(vm.load(data),OK,p)
            for (m,n),value in zip(cases,expected):
                self.assertEqual(vm.call(m,n,owner='LambdaValues'),(OK,value),(m,n));self.assertEqual(LIB.jbv_collect(vm.handle),OK)
if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
