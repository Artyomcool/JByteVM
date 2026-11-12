"""Test helpers: the Java build tools (tools/Prepare.java) called from the Python tests, and a
constant-pool tag check for compiled classes."""
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def _java(jdk):
    return str(Path(jdk) / "bin/java.exe")


def prepare(sources, output, jdk, lower, condy=False):
    """tools/Prepare.java; a refusal raises ValueError with its message."""
    if isinstance(sources, (str, Path)): sources = [sources]
    args = [_java(jdk), str(ROOT / "tools/Prepare.java"), *[str(s) for s in sources], "-o", str(output)]
    if lower: args.append("--lower-lambdas")
    if condy: args.append("--lower-condy")
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        raise ValueError((r.stderr or r.stdout).strip().splitlines()[-1] if (r.stderr or r.stdout).strip() else "prepare failed")


def unpack(jar, directory, jdk):
    r = subprocess.run([_java(jdk), str(ROOT / "tools/Prepare.java"), "--unpack", str(jar), "-o", str(directory)], capture_output=True, text=True)
    if r.returncode != 0: raise ValueError(r.stderr.strip())


def pack_classes(classes, jdk):
    """A JByteVM JAR of (internal name, class bytes) pairs, made by Prepare."""
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as work:
        source = Path(work) / "classes"
        for name, data in classes:
            (source / (name + ".class")).parent.mkdir(parents=True, exist_ok=True)
            (source / (name + ".class")).write_bytes(data)
        prepare(source, Path(work) / "out.jar", jdk, False)
        return (Path(work) / "out.jar").read_bytes()


def has_constant(data, wanted):
    """Whether the constant pool has an entry with this tag (18 invokedynamic, 17 dynamic)."""
    if len(data) < 10 or data[:4] != b"\xca\xfe\xba\xbe": raise ValueError("not a class file")
    count = struct.unpack_from(">H", data, 8)[0]
    index, pos = 1, 10
    while index < count:
        tag = data[pos]; pos += 1
        if tag == wanted: return True
        if tag == 1: pos += 2 + struct.unpack_from(">H", data, pos)[0]
        elif tag in (3, 4, 9, 10, 11, 12, 17, 18): pos += 4
        elif tag in (5, 6): pos += 8; index += 1
        elif tag in (7, 8, 16, 19, 20): pos += 2
        elif tag == 15: pos += 3
        else: raise ValueError(f"unknown constant pool tag {tag}")
        index += 1
    return False


def has_indy(data):
    return has_constant(data, 18)
