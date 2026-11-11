"""Prepare mods for JByteVM: one or more class directories/JARs become one
shared application JAR (jbv_load_jar). Lambdas, record methods, pattern switches
and condy can be lowered;
invokedynamic, non-Java-25 classes, duplicates and library packages are refused."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile
from build import find_jdk
from check_no_indy import has_indy, has_constant
import jar_pack

ROOT=Path(__file__).resolve().parents[1]
# Classes here belong to the runtime library; a mod copy would be shadowed.
RESERVED=('java/','javax/','jdk/','sun/','jbv/')

def _unpack(source,target,origins):
    def put(name,data):
        name=name.replace('\\','/')
        upper=name.upper()
        if upper=='META-INF/MANIFEST.MF':return
        if upper.startswith('META-INF/VERSIONS/'):raise ValueError('Select one class-file version before preparing a multi-release JAR.')
        if upper.startswith('META-INF/') and upper.endswith(('.SF','.RSA','.DSA','.EC')):raise ValueError('Signed JARs must be rebuilt and signed again after bytecode transformation.')
        path=(target/name).resolve()
        if not path.is_relative_to(target.resolve()):raise ValueError('Unsafe archive entry: '+name)
        if name in origins:raise ValueError(f'{name} is present in both {origins[name]} and {source}.')
        origins[name]=source
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    if source.is_dir():
        for path in sorted(source.rglob('*')):
            if path.is_file():put(path.relative_to(source).as_posix(),path.read_bytes())
    else:
        with zipfile.ZipFile(source) as archive:
            for entry in archive.infolist():
                if not entry.is_dir():put(entry.filename,archive.read(entry))

def prepare(sources,output,jdk,lower,condy=False):
    if isinstance(sources,(str,Path)):sources=[sources]
    sources=[Path(s).resolve() for s in sources];output=Path(output).resolve()
    if not sources:raise ValueError('No input.')
    if output.suffix.lower()!='.jar':raise ValueError('Output must be a .jar file.')
    if output.exists():raise ValueError('Output already exists; use a new output path.')
    for s in sources:
        if s.is_dir() and output.is_relative_to(s):raise ValueError('Output must be outside the input directories.')
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='jbv-prepare-',dir=output.parent) as temporary:
        staging=Path(temporary).resolve();unpacked=staging/'input';compiled=staging/'output'
        unpacked.mkdir();origins={}
        for s in sources:_unpack(s,unpacked,origins)
        if lower:subprocess.run([str(jdk/'bin/java.exe'),str(ROOT/'tools/LowerLambdas.java'),str(unpacked),str(compiled)],check=True)
        else:shutil.copytree(unpacked,compiled)
        if condy:
            lowered=staging/'condy'
            subprocess.run([str(jdk/'bin/java.exe'),str(ROOT/'tools/LowerCondy.java'),str(compiled),str(lowered)],check=True)
            compiled=lowered
        classes,resources=[],[]
        for path in sorted(compiled.rglob('*')):
            if not path.is_file():continue
            name=path.relative_to(compiled).as_posix();data=path.read_bytes()
            if not name.endswith('.class'):resources.append((name,data));continue
            if name.startswith(RESERVED):raise ValueError(f'{name}: package is reserved for the runtime library.')
            if has_constant(data,17):raise ValueError(f'{name} contains CONSTANT_Dynamic; use --lower-condy.')
            if has_indy(data):raise ValueError(f'{name} contains invokedynamic; use --lower-lambdas (lambdas, records, pattern switches).')
            if int.from_bytes(data[6:8],'big')!=69 or int.from_bytes(data[4:6],'big')!=0:raise ValueError('Only non-preview Java 25 class files are supported: '+name)
            classes.append((name[:-6],data))
        result=staging/'result.jar'
        result.write_bytes(jar_pack.pack_classes(classes,resources))
        result.rename(output)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs',type=Path,nargs='+',help='class directories or JARs')
    parser.add_argument('-o','--output',type=Path,required=True,help='the shared application JAR')
    parser.add_argument('--lower-lambdas',action='store_true',help='lower lambdas, record methods and pattern switches (string concatenation needs javac -XDstringConcat=inline)');parser.add_argument('--jdk',type=Path)
    parser.add_argument('--lower-condy',action='store_true')
    parser.add_argument('--unpack',action='store_true',help='expand an existing JByteVM JAR (single input) into the output directory')
    args=parser.parse_args()
    try:
        if args.unpack:
            if len(args.inputs)!=1 or args.output.exists():raise ValueError('--unpack takes one JAR and a new output directory.')
            jar_pack.unpack(args.inputs[0],args.output)
        else:prepare(args.inputs,args.output,find_jdk(args.jdk),args.lower_lambdas,args.lower_condy)
    except (ValueError,OSError,zipfile.BadZipFile) as error:parser.exit(1,str(error)+'\n')
    print('Prepared',args.output)
if __name__=='__main__':main()
