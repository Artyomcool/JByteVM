"""Differential primitive-library, array-copy, monitor and host-service checks."""
import ctypes as C
import random
import subprocess
import unittest
from test_vm import VM, LIB, JAVA, CLASSES, remaining, OK, LIMIT
from test_strings import read_units
from test_numbers import nan

def call(vm,name,desc,*values):
    slots=[]
    # Tests use primitive parameters, or a single String handle.
    kinds='L' if desc.startswith('(Ljava/lang/String;') else desc[1:desc.index(')')]
    for kind,value in zip(kinds,values):
        slots.append(value & 0xffffffff)
        if kind in 'JD':slots.append((value>>32)&0xffffffff)
    out=C.c_uint64(0x1234)
    status=LIB.jbv_call_slots(vm.handle,b'LibraryValues',name.encode(),desc.encode(),(C.c_int32*len(slots))(*slots),len(slots),C.byref(out))
    return status,out.value

class LibraryTests(unittest.TestCase):
    def prepare(self,**kw):
        vm=VM(**kw);self.addCleanup(vm.close)
        self.assertEqual(vm.load_name('LibraryValues'),OK)
        return vm

    def compare(self,cases):
        lines=[' '.join(['LibraryValues#'+name,desc,*[format(v & ((1<<64)-1),'x') for v in args]]) for name,desc,args in cases]
        oracle=subprocess.run([str(JAVA),'-cp',str(CLASSES),'NumericOracle'],input='\n'.join(lines)+'\n',capture_output=True,text=True,check=True)
        values=[int(s,16) for s in oracle.stdout.splitlines()];self.assertEqual(len(values),len(cases))
        vm=self.prepare()
        for (name,desc,args),expected in zip(cases,values):
            status,actual=call(vm,name,desc,*args)
            self.assertEqual(status,OK,(name,desc,args,status))
            if desc[-1] in 'FD' and nan(expected,desc[-1]):self.assertTrue(nan(actual,desc[-1]),(name,args,actual))
            else:self.assertEqual(actual,expected,(name,desc,args,hex(actual),hex(expected)))

    def test_wrappers_arrays_math_and_monitors(self):
        cases=[(name,'()I',()) for name in ['boxing','parseIntegers','arrays','exactMath','monitors']]
        rng=random.Random(25008)
        for a in [0,1,-1,-(1<<63),(1<<63)-1]+[rng.getrandbits(64) for _ in range(70)]:
            for n in [0,1,2,8,10,16,36,63,64,65,-7]:cases.append(('integerBits','(JI)J',(a,n)))
            for n in [0,2,7,10,16,36,37]:cases.append(('integerText','(JI)I',(a,n)))
        self.compare(cases)

    def test_floating_math(self):
        rng=random.Random(25009);cases=[]
        for kind,width,fraction in [('D',64,52),('F',32,23)]:
            values=[0,1,2,(1<<fraction)-1,1<<fraction,((1<<(width-fraction-1))-1)<<fraction]
            values+=[rng.getrandbits(width-1) for _ in range(180)]
            values += [v | (1<<(width-1)) for v in values[:40]]
            for a in values:
                if kind=='D':cases += [('floating','(DI)D',(a,n)) for n in range(11)]
                cases.append(('round',f'({kind})'+('J' if kind=='D' else 'I'),(a,)))
                for n in [-2100,-1075,-278,-53,-1,0,1,53,278,1075,2100]:cases.append(('scale',f'({kind}I){kind}',(a,n)))
        self.compare(cases)
        print('Library numeric HotSpot cases:',len(cases),flush=True)

    def test_parse_fp_against_hotspot(self):
        rng=random.Random(25010)
        inputs=['',' ','+','-','.','NaN','-NaN','Infinity','+Infinity','-Infinity','nan','NaNf','InfinityD','1f','1D','0x1p0','0x.1p-1','0x1','1e','1e+','1_0','1\x00','\x001\x00','0x1p999999999999999999999','1e-999999999999999999999',
                '2.2250738585072012e-308','1.7976931348623157e308','1.7976931348623159e308','2.4703282292062327e-324','2.4703282292062328e-324',
                '0x1.00000000000008p0','0x1.0000000000000800001p0','0x0.00000000000008p-1022','0x0.00000000000008001p-1022',
                '1.000000059604644775390625','1.000000059604644775390626','1.000000059604644775390624', '1'+'0'*1800+'e-1800', '0.'+'0'*1800+'1e1801']
        for _ in range(1600):
            n=rng.randrange(1,100)
            digits=''.join(str(rng.randrange(10)) for _ in range(n));pos=rng.randrange(n+1)
            inputs.append(('-' if rng.randrange(2) else '')+digits[:pos]+'.'+digits[pos:]+'e'+str(rng.randrange(-420,420)))
        for _ in range(500):inputs.append(('-' if rng.randrange(2) else '')+'0x'+format(rng.getrandbits(160),'x')+'.'+format(rng.getrandbits(100),'x')+'p'+str(rng.randrange(-1400,1300)))
        cases=[(kind,s) for kind in 'FD' for s in inputs]
        oracle=subprocess.run([str(JAVA),'-cp',str(CLASSES),'ParseOracle'],input='\n'.join(kind+' '+s.encode('utf-16-be').hex() for kind,s in cases)+'\n',capture_output=True,text=True,check=True)
        expected=[int(s,16) for s in oracle.stdout.splitlines()];self.assertEqual(len(expected),len(cases))
        vm=self.prepare()
        for (kind,s),value in zip(cases,expected):
            data=s.encode('utf-8');ref=C.c_int32()
            self.assertEqual(LIB.jbv_string_new_utf8(vm.handle,data,len(data),C.byref(ref)),OK)
            self.assertEqual(call(vm,'parse'+kind,'(Ljava/lang/String;)J',ref.value),(OK,value),(kind,s))
            self.assertEqual(LIB.jbv_release(vm.handle,ref),OK)
        print('FP parse HotSpot cases:',len(cases),flush=True)

    def test_monitor_cleanup_on_budget_abort(self):
        vm=self.prepare(instructions=200)
        self.assertEqual(call(vm,'lockedBudget','(I)I',10000)[0],LIMIT)
        self.assertEqual(call(vm,'checkUnlocked','()I'),(OK,1))

    def test_host_services(self):
        clock=C.CFUNCTYPE(C.c_int64,C.c_void_p,C.c_int)
        write=C.CFUNCTYPE(C.c_int,C.c_void_p,C.c_void_p,C.c_int32,C.c_int)
        class Services(C.Structure):_fields_=[('clock',clock),('write',write),('user',C.c_void_p)]
        LIB.jbv_set_host_services.argtypes=[C.c_void_p,C.POINTER(Services)]
        vm=self.prepare();seen=[]
        def output(handle,user,ref,error):
            self.assertEqual(LIB.jbv_collect(handle),OK)
            seen.append((''.join(chr(x) for x in read_units(vm,ref)),error))
            return OK
        services=Services(clock(lambda user,mono:9876543210123 if mono else 1700000000456),write(output),None)
        self.assertEqual(LIB.jbv_set_host_services(vm.handle,C.byref(services)),OK)
        self.assertEqual(call(vm,'clocks','()J'),(OK,9876543210123^1700000000456))
        self.assertEqual(call(vm,'output','()I'),(OK,7))
        self.assertEqual(''.join(s for s,e in seen if not e),'hello')
        self.assertEqual(''.join(s for s,e in seen if e),'42\r\n')
        self.assertEqual(LIB.jbv_set_host_services(vm.handle,None),OK)

    def test_fp_environment_and_native_reentry(self):
        from test_typed import FIXTURE
        FIXTURE.typed_fp_environment.argtypes=[C.c_void_p]
        vm=self.prepare()
        for _ in range(100):self.assertEqual(FIXTURE.typed_fp_environment(vm.handle),1)

if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
