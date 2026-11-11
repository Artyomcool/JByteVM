"""Public preparation pipeline: one shared JAR, bytecode, resources, errors."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from test_vm import ROOT, JAVA, CLASSES, VM, LIB, OK, remaining, has_indy
from prepare import prepare
from check_no_indy import has_constant
import jar_pack

JDK=JAVA.parent.parent

def expand(jar,work):
    target=work/(jar.stem+'-expanded');jar_pack.unpack(jar,target);return target

class PrepareTests(unittest.TestCase):
    def test_condy_and_lambdas_together(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            work=Path(temporary);source=work/'source';shutil.copytree(ROOT/'build/lambda-original',source)
            for p in CLASSES.glob('Condy*.class'):shutil.copy2(p,source)
            shutil.copy2(CLASSES/'NumericOracle.class',source)
            output=work/'prepared.jar'
            with self.assertRaisesRegex(ValueError,'CONSTANT_Dynamic'):prepare(source,output,JDK,True)
            self.assertFalse(output.exists())
            prepare(source,output,JDK,True,True)
            expanded=expand(output,work)
            for path in expanded.rglob('*.class'):
                self.assertFalse(has_constant(path.read_bytes(),17),path);self.assertFalse(has_indy(path.read_bytes()),path)
            original=subprocess.run([str(JAVA),'-cp',str(source),'LambdaValues'],capture_output=True,check=True)
            actual=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(expanded),'LambdaValues'],capture_output=True,check=True)
            self.assertEqual(actual.stdout,original.stdout)
            result=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(expanded),'NumericOracle'],input='CondyExtra#lifecycle (I)I 0\n',text=True,capture_output=True,check=True)
            self.assertEqual(int(result.stdout.strip(),16),7)

    def test_shared_jar_runs_on_jbytevm(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            work=Path(temporary)
            source=work/'source';shutil.copytree(ROOT/'build/lambda-original',source)
            payload=b'configuration\x00\xff\n';(source/'mod.dat').write_bytes(payload)
            archive=work/'source.jar'
            with zipfile.ZipFile(archive,'w') as jar:
                for path in source.rglob('*'):
                    if path.is_file():jar.write(path,path.relative_to(source).as_posix())
            # A second mod as a plain directory: both end up in one JAR.
            other=work/'other';other.mkdir();shutil.copy2(CLASSES/'Core.class',other)
            target=work/'prepared.jar';prepare([archive,other],target,JDK,True)
            with zipfile.ZipFile(target) as jar:
                self.assertEqual(jar.read('mod.dat'),payload)
                self.assertEqual(sorted(jar.namelist()),['jbv/classes.bin','mod.dat'])
            oracle=subprocess.run([str(JAVA),'-cp',str(source),'LambdaValues'],capture_output=True,text=True,check=True)
            actual=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(expand(target,work)),'LambdaValues'],capture_output=True,text=True,check=True)
            self.assertEqual(actual.stdout,oracle.stdout)
            expected=[int(s) for s in oracle.stdout.splitlines()];cases=[(m,n) for n in [0,1,-1,17,12345] for m in ['basic','advanced','errors']]
            data=target.read_bytes()
            with VM() as vm:
                self.assertEqual(vm.load_jar(data),OK)
                self.assertNotEqual(vm.load_jar(data),OK)  # one shared JAR per VM
                for (m,n),value in zip(cases,expected):
                    self.assertEqual(vm.call(m,n,owner='LambdaValues'),(OK,value),(m,n));self.assertEqual(LIB.jbv_collect(vm.handle),OK)
                self.assertEqual(vm.call('negate',5)[0],OK)
                self.assertNotEqual(vm.load_name('Core'),OK)  # already provided by the JAR
            with VM() as vm:
                broken=bytearray(data);broken[len(broken)//3]^=0x55
                self.assertNotEqual(vm.load_jar(bytes(broken)),OK)
            with self.assertRaisesRegex(ValueError,'already exists'):prepare(source,target,JDK,True)

    def test_rejected_input_leaves_no_output(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            work=Path(temporary);source=work/'source';source.mkdir();output=work/'result.jar'
            shutil.copy2(CLASSES/'Concat.class',source)
            with self.assertRaisesRegex(ValueError,'invokedynamic'):prepare(source,output,JDK,False)
            self.assertFalse(output.exists())
            with self.assertRaises(subprocess.CalledProcessError):prepare(source,output,JDK,True)
            self.assertFalse(output.exists())
            with self.assertRaisesRegex(ValueError,'\.jar'):prepare(source,work/'directory',JDK,False)
            twin=work/'twin';twin.mkdir();shutil.copy2(CLASSES/'Concat.class',twin)
            with self.assertRaisesRegex(ValueError,'present in both'):prepare([source,twin],output,JDK,False)
            reserved=work/'reserved';(reserved/'java/lang').mkdir(parents=True);shutil.copy2(CLASSES/'Core.class',reserved/'java/lang/Core.class')
            with self.assertRaisesRegex(ValueError,'reserved'):prepare(reserved,output,JDK,False)
            self.assertFalse(output.exists())
            archive=work/'unsafe.jar'
            for name in ['../escape','META-INF/VERSIONS/25/Mod.class','META-INF/MOD.SF']:
                with zipfile.ZipFile(archive,'w') as jar:jar.writestr(name,b'data')
                with self.assertRaises(ValueError):prepare(archive,output,JDK,False)
                self.assertFalse(output.exists())
                self.assertFalse((work/'escape').exists())

if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
