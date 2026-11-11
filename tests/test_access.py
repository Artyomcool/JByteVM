"""Runtime resolution tests, including binary-incompatible replacement (there are no access checks)."""
import struct
import subprocess
import unittest
from test_vm import VM, CLASSES, JAVA, remaining, OK

def pool(data):
    count=struct.unpack_from('>H',data,8)[0];pos=10;i=1;texts={};offsets={}
    while i<count:
        tag=data[pos];pos+=1
        if tag==1:
            n=struct.unpack_from('>H',data,pos)[0];pos+=2;texts[i]=data[pos:pos+n].decode('utf-8');offsets[texts[i]]=(pos,n);pos+=n
        elif tag in (3,4,9,10,11,12,17,18):pos+=4
        elif tag in (5,6):pos+=8;i+=1
        elif tag in (7,8,16,19,20):pos+=2
        elif tag==15:pos+=3
        else:raise ValueError(tag)
        i+=1
    return pos,texts,offsets

def rename(data,old,new):
    data=bytearray(data);_,_,offsets=pool(data);pos,n=offsets[old];assert len(new)==n;data[pos:pos+n]=new.encode();return bytes(data)

class AccessTests(unittest.TestCase):
    def prepare(self,api=None,caller=None):
        vm=VM();self.addCleanup(vm.close)
        for p in sorted(CLASSES.glob('AccessValues*.class')):self.assertEqual(vm.load(caller if caller is not None and p.name=='AccessValues.class' else p.read_bytes()),OK)
        for p in sorted((CLASSES/'access').rglob('*.class')):self.assertEqual(vm.load(api if api is not None and p.name=='Api.class' else p.read_bytes()),OK)
        return vm
    def test_nestmates_and_package_override(self):
        oracle=subprocess.run([str(JAVA),'-cp',str(CLASSES),'NumericOracle'],input='AccessValues#positive (I)I 7\n',text=True,capture_output=True,check=True)
        vm=self.prepare();self.assertEqual(vm.call('positive',7,owner='AccessValues'),(OK,int(oracle.stdout,16)))
    def test_resolution_errors_are_java_exceptions(self):
        # No access checks: only missing members and wrong member kinds fail.
        original=(CLASSES/'access/base/Api.class').read_bytes()
        for old,new,method,result in [('field','other','field',2),('call','gone','method',5)]:
            vm=self.prepare(api=rename(original,old,new));self.assertEqual(vm.call(method,0,owner='AccessValues'),(OK,result))
        vm=self.prepare(caller=rename((CLASSES/'AccessValues.class').read_bytes(),'call','inst'))
        self.assertEqual(vm.call('wrongStatic',0,owner='AccessValues'),(OK,8))

if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
