"""Prepare a class directory or JAR for JByteVM; optionally lower lambdas."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile
from build import find_jdk
from check_no_indy import has_indy, has_constant

ROOT=Path(__file__).resolve().parents[1]

def prepare(source,output,jdk,lower,condy=False):
    source=source.resolve();output=output.resolve()
    if output.exists():raise ValueError('Output already exists; use a new output path.')
    if source.is_dir() and output.is_relative_to(source):raise ValueError('Output must be outside the input directory.')
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='jbv-prepare-',dir=output.parent) as temporary:
        staging=Path(temporary).resolve();unpacked=staging/'input';compiled=staging/'output'
        if source.is_dir():shutil.copytree(source,unpacked)
        else:
            with zipfile.ZipFile(source) as archive:
                for entry in archive.infolist():
                    name=entry.filename.replace('\\','/')
                    if name.upper().startswith('META-INF/VERSIONS/'):raise ValueError('Select one class-file version before preparing a multi-release JAR.')
                    if name.upper().startswith('META-INF/') and name.upper().endswith(('.SF','.RSA','.DSA','.EC')):raise ValueError('Signed JARs must be rebuilt and signed again after bytecode transformation.')
                    target=(unpacked/name).resolve()
                    if not target.is_relative_to(unpacked.resolve()):raise ValueError('Unsafe archive entry: '+entry.filename)
                    if not entry.is_dir():target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(archive.read(entry))
        if lower:subprocess.run([str(jdk/'bin/java.exe'),str(ROOT/'tools/LowerLambdas.java'),str(unpacked),str(compiled)],check=True)
        else:shutil.copytree(unpacked,compiled)
        if condy:
            lowered=staging/'condy'
            subprocess.run([str(jdk/'bin/java.exe'),str(ROOT/'tools/LowerCondy.java'),str(compiled),str(lowered)],check=True)
            compiled=lowered
        for path in compiled.rglob('*.class'):
            data=path.read_bytes()
            if has_constant(data,17):raise ValueError(f'{path.relative_to(compiled)} contains CONSTANT_Dynamic; use --lower-condy.')
            if has_indy(data):raise ValueError(f'{path.relative_to(compiled)} contains invokedynamic; try --lower-lambdas and compile string concatenation with -XDstringConcat=inline.')
            if int.from_bytes(data[6:8],'big')!=69 or int.from_bytes(data[4:6],'big')!=0:raise ValueError('Only non-preview Java 25 class files are supported: '+str(path.relative_to(compiled)))
        if output.suffix.lower()=='.jar':
            jar=staging/'result.jar'
            with zipfile.ZipFile(jar,'w',zipfile.ZIP_DEFLATED) as archive:
                for path in sorted(compiled.rglob('*')):
                    if path.is_file():archive.write(path,path.relative_to(compiled).as_posix())
            jar.rename(output)
        else:compiled.rename(output)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--lower-lambdas',action='store_true');parser.add_argument('--jdk',type=Path)
    parser.add_argument('--lower-condy',action='store_true')
    args=parser.parse_args()
    try:prepare(args.input,args.output,find_jdk(args.jdk),args.lower_lambdas,args.lower_condy)
    except (ValueError,OSError,zipfile.BadZipFile) as error:parser.exit(1,str(error)+'\n')
    print('Prepared',args.output)
if __name__=='__main__':main()
