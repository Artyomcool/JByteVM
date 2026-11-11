"""Public preparation pipeline: bytecode, resources and atomic error behavior."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from test_vm import ROOT, JAVA, CLASSES, remaining, has_indy
from prepare import prepare
from check_no_indy import has_constant

class PrepareTests(unittest.TestCase):
    def test_condy_and_lambdas_together(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            work=Path(temporary);source=work/'source';shutil.copytree(ROOT/'build/lambda-original',source)
            for p in CLASSES.glob('Condy*.class'):shutil.copy2(p,source)
            shutil.copy2(CLASSES/'NumericOracle.class',source)
            output=work/'prepared.jar'
            with self.assertRaisesRegex(ValueError,'CONSTANT_Dynamic'):prepare(source,output,JAVA.parent.parent,True)
            self.assertFalse(output.exists())
            prepare(source,output,JAVA.parent.parent,True,True)
            with zipfile.ZipFile(output) as jar:
                for name in jar.namelist():
                    if name.endswith('.class'):
                        self.assertFalse(has_constant(jar.read(name),17),name)
                        self.assertFalse(has_indy(jar.read(name)),name)
            original=subprocess.run([str(JAVA),'-cp',str(source),'LambdaValues'],capture_output=True,check=True)
            actual=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(output),'LambdaValues'],capture_output=True,check=True)
            self.assertEqual(actual.stdout,original.stdout)
            result=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(output),'NumericOracle'],input='CondyExtra#lifecycle (I)I 0\n',text=True,capture_output=True,check=True)
            self.assertEqual(int(result.stdout.strip(),16),7)

    def test_directory_and_jar(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            work=Path(temporary)
            original=ROOT/'build/lambda-original'
            source=work/'source';shutil.copytree(original,source)
            payload=b'configuration\x00\xff\n';(source/'mod.dat').write_bytes(payload)
            output=work/'prepared'
            prepare(source,output,JAVA.parent.parent,True)
            self.assertEqual((output/'mod.dat').read_bytes(),payload)
            for path in output.rglob('*.class'):self.assertFalse(has_indy(path.read_bytes()),path)
            oracle=subprocess.run([str(JAVA),'-cp',str(source),'LambdaValues'],capture_output=True,check=True)
            actual=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(output),'LambdaValues'],capture_output=True,check=True)
            self.assertEqual(actual.stdout,oracle.stdout)
            archive=work/'source.jar'
            with zipfile.ZipFile(archive,'w') as jar:
                for path in source.rglob('*'):
                    if path.is_file():jar.write(path,path.relative_to(source).as_posix())
            target=work/'prepared.jar';prepare(archive,target,JAVA.parent.parent,True)
            with zipfile.ZipFile(target) as jar:
                self.assertEqual(jar.read('mod.dat'),payload)
                for name in jar.namelist():
                    if name.endswith('.class'):self.assertFalse(has_indy(jar.read(name)),name)
            actual=subprocess.run([str(JAVA),'-Xverify:all','-cp',str(target),'LambdaValues'],capture_output=True,check=True)
            self.assertEqual(actual.stdout,oracle.stdout)
            with self.assertRaisesRegex(ValueError,'already exists'):prepare(source,output,JAVA.parent.parent,True)
            self.assertEqual((output/'mod.dat').read_bytes(),payload)

    def test_rejected_input_leaves_no_output(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            work=Path(temporary);source=work/'source';source.mkdir();output=work/'result.jar'
            shutil.copy2(CLASSES/'Concat.class',source)
            with self.assertRaisesRegex(ValueError,'invokedynamic'):prepare(source,output,JAVA.parent.parent,False)
            self.assertFalse(output.exists())
            with self.assertRaises(subprocess.CalledProcessError):prepare(source,output,JAVA.parent.parent,True)
            self.assertFalse(output.exists())
            archive=work/'unsafe.jar'
            for name in ['../escape','META-INF/VERSIONS/25/Mod.class','META-INF/MOD.SF']:
                with zipfile.ZipFile(archive,'w') as jar:jar.writestr(name,b'data')
                with self.assertRaises(ValueError):prepare(archive,output,JAVA.parent.parent,False)
                self.assertFalse(output.exists())
                self.assertFalse((work/'escape').exists())

if __name__=='__main__':unittest.main(argv=[__file__,*remaining],verbosity=2)
