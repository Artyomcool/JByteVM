"""Compile the small class library and embed it as a deflated JAR."""
from pathlib import Path
import subprocess
import shutil
import struct
import jar_pack
import generate_wrappers
import generate_functions
import generate_factories
from check_no_indy import has_indy
from slim_class import without_stack_maps

ROOT=Path(__file__).resolve().parents[1]

def build(jdk,build_dir):
    generate_wrappers.generate()
    generate_functions.generate()
    generate_factories.generate()
    subprocess.run([str(jdk/'bin/java.exe'),str(ROOT/'tools/GenerateUnicode.java'),str(ROOT/'classpath/jbv/runtime/Unicode.java')],check=True)
    classes=build_dir/'classpath'
    # This directory belongs only to this generator. Drop obsolete .class files
    # before compiling, including inner classes removed since the last build.
    if not classes.resolve().is_relative_to((ROOT/'build').resolve()):
        raise ValueError('Generated classpath must stay inside the project build directory.')
    if classes.exists(): shutil.rmtree(classes)
    classes.mkdir(parents=True,exist_ok=True)
    sources=sorted((ROOT/'classpath').rglob('*.java'))
    subprocess.run([str(jdk/'bin/javac.exe'),'--release','25','-g:none','-XDstringConcat=inline','-Xlint:-removal',
                    '--patch-module','java.base='+str(ROOT/'classpath'),'-d',str(classes),*[str(p) for p in sources]],check=True)
    entries=[]
    image_bytes=0
    for path in sorted(classes.rglob('*.class')):
        data=without_stack_maps(path.read_bytes())
        image_bytes+=len(data)
        if has_indy(data): raise ValueError(f'Library must not contain invokedynamic: {path}')
        entries.append((path.relative_to(classes).as_posix(),data))
    # One solid DEFLATE stream: repeated names and descriptors across classes
    # compress together. Layout is read by jbv_classpath_find (classpath.c).
    entries.sort()
    names=[n[:-6].encode() for n,_ in entries]
    offset=4+sum(9+len(n) for n in names)
    index=bytearray(struct.pack('<I',len(entries)))
    for n,(_,data) in zip(names,entries):
        if len(n)>255: raise ValueError(f'Class name too long for library index: {n}')
        index+=struct.pack('<IIB',offset,len(data),len(n))+n; offset+=len(data)
    library=bytes(index)+b''.join(d for _,d in entries)
    jar=jar_pack.pack([('jbv/library.bin',library)])
    (build_dir/'classpath.jar').write_bytes(jar)
    lines=['/* Generated: the class library as a deflated JAR (also written to classpath.jar). */','#include "classpath.h"',
           f'const uint32_t jbv_library_jar_size={len(jar)};','const uint8_t jbv_library_jar[]={']
    for off in range(0,len(jar),32): lines.append(','.join(str(x) for x in jar[off:off+32])+',')
    lines.append('};')
    output=build_dir/'generated_classpath.c'
    content='\n'.join(lines)+'\n'
    if not output.exists() or output.read_text()!=content: output.write_text(content)
    return image_bytes, len(jar)
